"""Bake an isolated real-elevation pilot, keeping every original dataset untouched."""
import argparse
import math
import time
from pathlib import Path

import numpy as np
from shapely.geometry import Polygon, box, shape, Point, mapping
from shapely.ops import unary_union
from shapely.prepared import prep

from expansion_regions import metric_region
from relief_limits import bake_limits
from relief_regions import apply_boundary_outsets
from relief_core import Elevation, HeightField, binary_faces, digest, read, triangulate, write, fair_road_grades, write_heightfield, constrain_coast

ROOT = Path(__file__).resolve().parents[1]


def build(mode='pilot'):
    start = time.perf_counter()
    cfg = read(ROOT / 'config/relief_config.json')
    if cfg['grid_step_m'] not in (4,8,16,32) or cfg['smoothing_sigma_m'] <= 0:
        raise ValueError('Relief grid must divide the existing 256m sectors; positive smoothing required')
    if not 0 < cfg['max_road_grade'] < math.tan(math.radians(42)):
        raise ValueError('Road grade limit exceeds production car floor angle')
    geo = read(ROOT / 'config/map_config.json')
    data = read(ROOT / 'data/processed/la_paz_map.json')
    arcade = read(ROOT / 'data/processed/arcade_layout.json')
    city = read(ROOT / 'data/processed/urban/city_manifest.json')
    if geo['origin_lat'] != data['metadata']['origin_lat'] or geo['origin_lon'] != data['metadata']['origin_lon']:
        raise ValueError('DEM preparation origin must exactly match existing map projection')
    if digest(ROOT/'data/processed/urban/urban_geography.json') != city['b6_files']['urban_geography.json']:
        raise ValueError('Geographic source is stale or corrupt')
    geographic = read(ROOT / 'data/processed/urban/urban_geography.json')
    sea = shape(geographic['water_geometry_xz'])
    full_region = metric_region(geo)
    region = full_region
    if mode == 'pilot':
        region = region.intersection(box(*cfg['pilot_bounds_xz']))
    else:
        region = apply_boundary_outsets(region,cfg.get('local_boundary_outsets',[]))
    out = ROOT / 'data/processed/relief' / mode
    dem_path = ROOT / cfg['source_file']
    meta = read(dem_path.with_suffix('.meta.json'))
    if digest(dem_path) != meta['sha256']:
        raise ValueError('DEM snapshot hash mismatch')
    dem = Elevation(dem_path, (geo['origin_lat'], geo['origin_lon']), cfg['smoothing_sigma_m'])
    # Grid extends beyond buildings and the playable boundary for interpolation.
    field = HeightField(dem, region.buffer(80).bounds, cfg['grid_step_m'], sea, region)
    asphalt = unary_union([Polygon([(x+c['origin_xz'][0],z+c['origin_xz'][1]) for x,z in t])
        for c in arcade['chunks'] if box(c['origin_xz'][0],c['origin_xz'][1],c['origin_xz'][0]+256,c['origin_xz'][1]+256).intersects(region)
        for t in c['triangles_xz']]).intersection(region)
    dry = region.difference(sea)
    coast=sea.boundary.difference(full_region.boundary.buffer(1)).intersection(region.buffer(80))
    coast_adjustment=constrain_coast(field,coast)
    fairing=fair_road_grades(field,asphalt)
    write_heightfield(out,field,ROOT)
    print('Road fairing',fairing,flush=True)
    # Same base triangles partitioned between ground and road: exact shared plane.
    road_entries, terrain_entries = [], []
    max_grade, total_road, total_terrain = 0., 0, 0
    step = cfg['grid_step_m']
    x0,z0,x1,z1 = region.bounds
    for cx in range(math.floor(x0/256), math.ceil(x1/256)):
        for cz in range(math.floor(z0/256), math.ceil(z1/256)):
            cell = box(cx*256,cz*256,(cx+1)*256,(cz+1)*256)
            local_region = dry.intersection(cell)
            if local_region.is_empty:
                continue
            local_road = asphalt.intersection(cell)
            local_ground = local_region.difference(local_road)
            ready_road, ready_ground = prep(local_road), prep(local_ground)
            road_faces, ground_faces = [], []
            for x in range(cx*256,(cx+1)*256,step):
                for z in range(cz*256,(cz+1)*256,step):
                    for points in [[(x,z),(x+step,z),(x+step,z+step)],[(x,z),(x+step,z+step),(x,z+step)]]:
                        tri = Polygon(points)
                        for geometry, ready, faces in [(local_road,ready_road,road_faces),(local_ground,ready_ground,ground_faces)]:
                            if ready.covers(tri):
                                faces.append(points)
                            elif ready.intersects(tri):
                                faces.extend(triangulate(geometry.intersection(tri)))
            for faces, entries, kind in [(road_faces,road_entries,'roads'),(ground_faces,terrain_entries,'terrain')]:
                if not faces:
                    continue
                path = out / kind / f'{cx}_{cz}.bin'
                entry = binary_faces(path,faces,field,[cx*256,cz*256])
                entry.update(id=f'{cx}_{cz}',origin_xz=[cx*256,cz*256])
                entry['file'] = path.relative_to(ROOT).as_posix()
                entries.append(entry)
                if kind == 'roads':
                    max_grade = max(max_grade,entry['max_grade'])
            total_road += len(road_faces)
            total_terrain += len(ground_faces)
        print(f'Prepared column {cx}; roads={total_road}, ground={total_terrain}',flush=True)
    # Derive buildings after all footprint/manual/arcade modifications.
    urban_entries = []
    foundation_spreads = []
    foundation_review = []
    for entry in city['chunks']:
        if not box(*entry['bounds_xz']).intersects(region):
            continue
        chunk = read(ROOT / 'data/processed/urban' / entry['file'])
        if digest(ROOT/'data/processed/urban'/entry['file']) != entry['sha256']:
            raise ValueError('Urban source sector is stale or corrupt: '+entry['id'])
        changes = arcade['building_overrides']
        if entry['id'] in arcade['chunk_overrides']:
            override=arcade['chunk_overrides'][entry['id']]
            if digest(ROOT/override['file']) != override['sha256']:
                raise ValueError('Arcade source sector is stale or corrupt: '+entry['id'])
            changes = read(ROOT / override['file'])
        kept = []
        for original in chunk['buildings']:
            building = dict(original)
            if building['id'] in changes:
                building.update(changes[building['id']])
                building.pop('model_path',None)
                building.pop('facade_edge_index',None)
            if building.get('disabled'):
                continue
            poly = Polygon(building['footprint_xz'],building.get('holes_xz',[]))
            if not region.covers(poly):
                continue
            samples = []
            for ring in [building['footprint_xz']] + building.get('holes_xz',[]):
                for i,p in enumerate(ring):
                    q=ring[(i+1)%len(ring)]
                    for t in np.linspace(0,1,max(2,math.ceil(math.dist(p,q)/step)+1)):
                        samples.append(field.height(p[0]+t*(q[0]-p[0]),p[1]+t*(q[1]-p[1])))
            # Include interior canonical grid nodes; exclude courtyards.
            bx0,bz0,bx1,bz1=poly.bounds
            for x in range(math.ceil(bx0/step)*step,math.ceil(bx1/step)*step,step):
                for z in range(math.ceil(bz0/step)*step,math.ceil(bz1/step)*step,step):
                    if poly.covers(Point(x,z)): samples.append(field.height(x,z))
            base=max(samples)
            building['base_y_m']=base
            building['foundation_min_y_m']=min(samples)-.2
            building['elevation_source']='CEM4 shared smoothed triangulated surface; level foundation'
            foundation_spreads.append(base-min(samples))
            if base-min(samples)>6:
                foundation_review.append({'id':building['id'],'spread_m':base-min(samples),'base_y_m':base,
                    'height_m':building['height_m'],'footprint_xz':building['footprint_xz'],
                    'reason':'Large level foundation requires visual review; source footprint and roof are preserved'})
            kept.append(building)
        if not kept:
            continue
        chunk['buildings']=kept
        path=out/'urban'/entry['file']
        write(path,chunk)
        urban_entries.append({**entry,'building_count':len(kept),'sha256':digest(path)})
    derived_city={**city,'chunks':urban_entries}
    derived_city['statistics']={**city['statistics'],'buildings':sum(e['building_count'] for e in urban_entries)}
    write(out/'urban/city_manifest.json',derived_city)
    write(out/'foundation_review.json',foundation_review)
    # The production sea includes the explicitly requested offshore quadrants;
    # the isolated pilot keeps its original small capture envelope.
    water_faces=triangulate((sea if mode=='world' else sea.intersection(region)).difference(asphalt))
    write(out/'water.json',{'surfaces':[{'kind':'water','color':'397f99','y':cfg['sea_level_m'],'triangles_xz':water_faces}]})
    route_region=prep(region.buffer(-20))
    roads=[r for r in data['roads'] if all(route_region.covers(Point(p)) for p in r['points_xz'])]
    chosen=next(r for r in roads if r['id']==cfg['pilot_road_id'])
    # A real connected north route, both directions tested with production car.
    route=make_route(roads,chosen['from'])
    p=route[0]; q=route[1]
    length=math.dist(p,q)
    spawn=[p[0]+(q[0]-p[0])*8/length,p[1]+(q[1]-p[1])*8/length]
    stats=dict(road_chunks=len(road_entries),terrain_chunks=len(terrain_entries),road_triangles=total_road,
        terrain_triangles=sum(e['triangles_count'] for e in terrain_entries),buildings=sum(e['building_count'] for e in urban_entries),
        max_road_grade=max_grade, max_foundation_spread_m=max(foundation_spreads,default=0),
        foundation_over_6m=sum(s>6 for s in foundation_spreads),source_profile=dem.profile,
        height_min_m=float(field.values.min()),height_max_m=float(field.values.max()),
        grid_estimated_samples=int((field.quality!=0).sum()),coastal_estimated_samples=int((field.quality==3).sum()),road_fairing=fairing,
        omitted_submillimetre_area_m2=sum(e['omitted_area_m2'] for e in road_entries+terrain_entries),coast_adjustment=coast_adjustment)
    stats['road_triangles']=sum(e['triangles_count'] for e in road_entries)
    manifest=dict(schema_version=1,mode=mode,bounds_xz=list(region.bounds),boundary_xz=list(region.exterior.coords)[:-1] if region.geom_type=='Polygon' else [],
        region_geojson=mapping(region),flat_safety_triangles_xz=triangulate(region),origin_lat=geo['origin_lat'],origin_lon=geo['origin_lon'],
        sources={p:digest(ROOT/p) for p in ['data/processed/la_paz_map.json','data/processed/arcade_layout.json','data/processed/urban/city_manifest.json','data/processed/urban/urban_geography.json','config/map_config.json','config/relief_config.json',cfg['source_file'],str(Path(cfg['source_file']).with_suffix('.meta.json')).replace('\\','/')]},
        heightfield_file=(out/'heightfield.json').relative_to(ROOT).as_posix(),heightfield_sha256=digest(out/'heightfield.json'),
        city_root=(out/'urban').relative_to(ROOT).as_posix()+'/',city_sha256=digest(out/'urban/city_manifest.json'),
        water_file=(out/'water.json').relative_to(ROOT).as_posix(),water_sha256=digest(out/'water.json'),
        roads=road_entries,terrain=terrain_entries,limits=bake_limits(out,region,field,ROOT,sea,cfg.get('fictional_boundary_mountains') if mode=='world' else None),road_ids=[r['id'] for r in roads],
        fictional_boundary_mountains=cfg.get('fictional_boundary_mountains',{}) if mode=='world' else {},
        local_boundary_outsets=cfg.get('local_boundary_outsets',[]) if mode=='world' else [],
        spawn={'position_xz':spawn,'forward_xz':[(q[0]-p[0])/length,(q[1]-p[1])/length]},route_xz=route,statistics=stats,
        source_metadata=meta,notes=['Gaussian 20m smoothing is a declared gameplay adjustment, not higher resolution or surveyed road profiles.',
        'Common triangulated field resolves same-level junctions; no independent per-vertex road draping.',
        'Specific vertical geoid and local vertical accuracy not confirmed; no mixing of DEM datums.',
        'Pilot excludes all multi-level bridges.'])
    if geo.get('preserved_sea_file'):
        manifest['sources'][geo['preserved_sea_file']]=digest(ROOT/geo['preserved_sea_file'])
    if max_grade>cfg['max_road_grade']:
        raise ValueError(f'Road grade requires review: {max_grade}')
    write(out/'manifest.json',manifest)
    write(ROOT/f'docs/phase_b7r_{mode}_bake.json',dict(passed=True,statistics=stats,bake_seconds=time.perf_counter()-start,manifest_sha256=digest(out/'manifest.json')))
    print(stats,flush=True)
    return manifest


def make_route(roads,start):
    graph={}
    for road in roads:
        for reverse in ([False] if road['oneway'] else [False,True]):
            a,b=(road['to'],road['from']) if reverse else (road['from'],road['to'])
            pts=list(reversed(road['points_xz'])) if reverse else road['points_xz']
            graph.setdefault(a,[]).append((b,road['length_m'],pts))
    # Select an uncomplicated directed route for a slope/contact test. Hairpin
    # navigation is tested separately; do not hide autopilot errors in geometry.
    stack=[(start,0.,[],{start})]; best=(0.,[]);iterations=0
    while stack and iterations<20000:
        node,cost,route,visited=stack.pop();iterations+=1
        if cost>best[0]:best=(cost,route)
        for end,length,pts in sorted(graph.get(node,[])):
            if end in visited or cost+length>1000:continue
            if route:
                incoming=np.array(route[-1])-route[-2]
                outgoing=np.array(pts[1])-pts[0]
                if np.dot(incoming,outgoing)/(np.linalg.norm(incoming)*np.linalg.norm(outgoing))<0.1:continue
            stack.append((end,cost+length,route+pts[1:] if route else pts,visited|{end}))
    if best[0]<250:raise ValueError('No suitable connected slope probe')
    return best[1]


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--mode',choices=['pilot','world'],default='pilot')
    build(parser.parse_args().mode)

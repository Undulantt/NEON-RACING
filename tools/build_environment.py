"""Phase B: genuine OSM building footprints, simple extrusions and test routes."""
import json,math,hashlib
from pathlib import Path
from shapely.geometry import Polygon,LineString,box
from shapely.geometry.polygon import orient
from shapely.ops import unary_union
from shapely import constrained_delaunay_triangles
from map_core import gps_to_local,number,dijkstra
from fetch_buildings import ROOT,cache

def build():
    cfg=json.loads((ROOT/'config/map_config.json').read_text()); mp=ROOT/'data/processed/la_paz_map.json'; data=json.loads(mp.read_text(encoding='utf-8'))
    found=cache(cfg)
    if not found: raise SystemExit('Run tools/fetch_buildings.py first. No fabricated building fallback.')
    raw_path,meta=found; raw=json.loads(raw_path.read_bytes()); nodes={n['id']:n for n in raw['elements'] if n['type']=='node'}
    south,west,north,east=cfg['bbox']; x0,z1=gps_to_local(south,west,cfg['origin_lat'],cfg['origin_lon']); x1,z0=gps_to_local(north,east,cfg['origin_lat'],cfg['origin_lon']); region=box(x0,z0,x1,z1)
    asphalt=unary_union([LineString(r['points_xz']).buffer(r['width_m']/2,quad_segs=4) for r in data['roads']]); clearance=asphalt.buffer(1.0)
    buildings=[]; excluded=[]
    for way in sorted((e for e in raw['elements'] if e['type']=='way'),key=lambda e:e['id']):
        tags=way.get('tags',{}); refs=way.get('nodes',[])
        reason=''
        if len(refs)<4 or refs[0]!=refs[-1] or any(n not in nodes for n in refs): reason='open or missing nodes'
        elif tags.get('building') in ('no','construction','roof') or tags.get('layer','0')!='0' or tags.get('location')=='underground': reason='unsupported building type/level'
        if reason: excluded.append({'way_id':str(way['id']),'reason':reason}); continue
        pts=[gps_to_local(nodes[n]['lat'],nodes[n]['lon'],cfg['origin_lat'],cfg['origin_lon']) for n in refs]
        poly=Polygon(pts)
        if not poly.is_valid or not region.contains(poly) or not 15<=poly.area<=15000: reason='invalid, outside bbox or unsuitable size'
        elif poly.intersects(clearance): reason='overlaps estimated roadway or 1m clearance; original footprint preserved, building omitted'
        if reason: excluded.append({'way_id':str(way['id']),'reason':reason}); continue
        tagged=number(tags.get('height','')); levels=number(tags.get('building:levels',''))
        h=tagged or (levels*3.1 if levels else (1+way['id']%3)*3.1)
        h=max(2.8,min(10.0,h))
        poly=orient(poly,sign=1.0); pts=list(poly.exterior.coords)
        triangles=[list(t.exterior.coords)[:3] for t in constrained_delaunay_triangles(poly).geoms]
        buildings.append({'osm_way_id':str(way['id']),'footprint_xz':pts[:-1],'roof_triangles_xz':triangles,'height_m':h,'height_estimated':not bool(tagged),'height_stylized':bool(tagged and abs(h-tagged)>0.01),'osm_tags':tags,'palette_index':way['id']%6})
    if not buildings: raise SystemExit('No safe real building footprints after filtering')
    # Spawn inside the verified corridor, away from clipped endpoints.
    corridor=LineString(data['verification_route']['points_xz']); at=min(900,corridor.length/2); p=corridor.interpolate(at); q=corridor.interpolate(at+5)
    spawn={'position_xz':[p.x,p.y],'forward_xz':[(q.x-p.x)/p.distance(q),(q.y-p.y)/p.distance(q)],'source':'interpolated on verified OSM corridor','distance_on_phase_a_route_m':at}
    # A separate test traversal visiting distinct streets. Still only a test, not a race.
    roads={r['id']:r for r in data['roads']}; best=None
    for start in data['verification_route']['road_node_sequence'][::max(1,len(data['verification_route']['road_node_sequence'])//10)]:
        distances,previous=dijkstra(data,start)
        for target,length in distances.items():
            if not 900<length<1600: continue
            seq=[]; n=target
            while n!=start: e=previous[n]; seq.append(e); n=e['from']
            seq.reverse(); names={roads[e['road_id']]['street_name'] for e in seq}-{''}
            bends=0; points=[]
            for e in seq:
                rp=roads[e['road_id']]['points_xz']; rp=list(reversed(rp)) if e['reverse'] else rp; points.extend(rp if not points else rp[1:])
            for a,b,c in zip(points,points[1:],points[2:]):
                u=(b[0]-a[0],b[1]-a[1]); v=(c[0]-b[0],c[1]-b[1]); cosine=sum(x*y for x,y in zip(u,v))/(math.hypot(*u)*math.hypot(*v))
                if cosine<0.8: bends+=1
            score=(min(len(names),5),min(bends,4),-abs(length-1200))
            if best is None or score>best[0]: best=(score,{'purpose':'phase_b_automated_driving_test_only','edge_ids':[e['id'] for e in seq],'node_ids':[start]+[e['to'] for e in seq],'points_xz':points,'length_m':length,'street_names':sorted(names),'turns_over_36_degrees':bends})
    output={'schema_version':1,'map_sha256':hashlib.sha256(mp.read_bytes()).hexdigest(),'metadata':{'source':'OpenStreetMap contributors','license':'ODbL-1.0','building_provenance':meta,'buildings_note':'Real simple-way footprints; generic facades and estimated/stylized heights. Multipolygon relations are not imported.','ground_note':'Neutral flat safety platform for the prototype, not mapped land or coastline.'},'bounds_xz':[x0-30,z0-30,x1+30,z1+30],'spawn':spawn,'buildings':buildings,'excluded_buildings':excluded,'driving_test_route':best[1]}
    target=ROOT/'data/processed/la_paz_environment.json'; target.write_text(json.dumps(output,ensure_ascii=False,separators=(',',':'),allow_nan=False),encoding='utf-8')
    print('Environment:',len(buildings),'buildings;',len(excluded),'excluded'); print('Driving test:',best[1]['length_m'],'m',best[1]['street_names'])
    return output
if __name__=='__main__': build()

"""Bounded, offline recovery of real campus/shop roofs; base map stays immutable.

Run with .venv-urban/Scripts/python.exe tools/build_sf3_recovery.py.
The supplementary sectors use the normal city streamer and geographic IDs.
"""
import json
import math
import xml.etree.ElementTree as ET
from collections import Counter, defaultdict

from shapely.geometry import Polygon, Point, shape
from shapely.ops import transform, unary_union
from shapely.strtree import STRtree
from build_urban_city import ROOT, projector, parts, encode_building
from expansion_regions import metric_region
from fetch_urban_sources import digest
from urban_protection import real_building_exclusions


def read(path):
    return json.loads((ROOT / path).read_text(encoding='utf-8'))


def write(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes((json.dumps(value, ensure_ascii=False, separators=(',', ':'), allow_nan=False)+'\n').encode('utf-8'))


def build():
    cfg=read('config/map_config.json'); project=projector(cfg); region=metric_region(cfg)
    city=read('data/processed/urban/city_manifest.json'); arcade=read('data/processed/arcade_layout.json')
    assert (cfg['origin_lat'],cfg['origin_lon'])==(city['origin_lat'],city['origin_lon'])
    root=ROOT/'data/processed/urban/sf3_recovery'
    protected=read('data/processed/urban/placement_audit.json')['protected']
    campus_ids={'way:137201460':'UABCS','way:137201452':'Tec de La Paz'}
    campuses={p['id']:(shape(p['geometry_xz']),campus_ids[p['id']]) for p in protected if p['id'] in campus_ids}
    assert len(campuses)==2
    hard=real_building_exclusions(protected).union(shape(read('data/processed/urban/urban_geography.json')['water_geometry_xz']))
    asphalt_parts=[unary_union([Polygon([(x+c['origin_xz'][0],z+c['origin_xz'][1]) for x,z in t]) for t in c['triangles_xz']]) for c in arcade['chunks']]
    asphalt=unary_union(asphalt_parts); clearance=asphalt.buffer(0.8)
    obstacle_parts=[hard]+[g.buffer(0.8) for g in asphalt_parts]
    obstacle_tree=STRtree(obstacle_parts)
    existing=[]
    for c in city['chunks']:
        assert digest(ROOT/'data/processed/urban'/c['file'])==c['sha256']
        changes=read(arcade['chunk_overrides'][c['id']]['file']) if c['id'] in arcade['chunk_overrides'] else {}
        for b in read('data/processed/urban/'+c['file'])['buildings']:
            b={**b,**changes.get(b['id'],{})}
            if not b.get('disabled'): existing.append(Polygon(b['footprint_xz'],b.get('holes_xz',[])))
    existing_tree=STRtree(existing)
    xml_path='data/raw/osm_map_c6_boundary_expansion.osm'
    osm=ET.parse(ROOT/xml_path).getroot(); nodes={e.attrib['id']:(float(e.attrib['lon']),float(e.attrib['lat'])) for e in osm.findall('node')}
    candidates=[]
    for e in osm.findall('way'):
        tags={t.attrib['k']:t.attrib['v'] for t in e.findall('tag')}
        if tags.get('building') in (None,'no','construction','roof'): continue
        refs=[n.attrib['ref'] for n in e.findall('nd')]
        if len(refs)<4 or refs[0]!=refs[-1] or any(n not in nodes for n in refs): continue
        g=transform(project,Polygon([nodes[n] for n in refs])); identity=e.attrib['id']
        campus=next((name for p,name in campuses.values() if p.covers(g)),None)
        if identity!='1495212806' and campus is None: continue
        try: floors=float(tags.get('building:levels','0')) or None
        except ValueError: floors=None
        candidates.append(('osm:'+identity+':0','osm',g,{'source_id':identity,'sources':[{'dataset':'OpenStreetMap'}],'num_floors':floors},campus or 'Soriana Forjadores'))
    ov_path='data/raw/'+city['metadata']['sources']['overture_buildings']['file']
    for f in sorted(read(ov_path)['features'],key=lambda f:str(f.get('id',f['properties'].get('id')))):
        props=f['properties']
        if props.get('is_underground'): continue
        g=transform(project,shape(f['geometry']))
        campus=next((name for p,name in campuses.values() if p.covers(g)),None)
        if campus is None: continue
        source_id=str(f.get('id',props.get('id')))
        for i,p in enumerate(parts(g)): candidates.append((f'overture:{source_id}:{i}:0','overture',p,{**props,'source_id':source_id},campus))
    accepted=[]; polys=[]; rejected=[]
    for identity,kind,original,props,site in candidates:
        reason=None
        if not original.is_valid or original.is_empty or not region.covers(original): reason='invalid/outside active region'
        elif not 12<=original.area<=25000: reason='area outside real-building limits'
        if reason: rejected.append({'id':identity,'site':site,'reason':reason});continue
        blockers=unary_union([obstacle_parts[int(i)] for i in obstacle_tree.query(original)])
        poly=original.simplify(.12,preserve_topology=True).difference(blockers)
        overlaps=[existing[int(i)] for i in existing_tree.query(original)]+[p for p in polys if p.intersects(original)]
        if overlaps: poly=poly.difference(unary_union(overlaps).buffer(.15))
        options=[p for p in parts(poly) if p.area>=12]
        if not options or sum(p.area for p in options)/original.area<.85:
            rejected.append({'id':identity,'site':site,'reason':'open space/road/duplicate removes >15%'});continue
        for part_index,p in enumerate(options):
            identifier=identity if len(options)==1 else identity+':part'+str(part_index)
            floors=props.get('num_floors'); height=props.get('height')
            measured=isinstance(height,(int,float)) and math.isfinite(height) and height>0
            if not measured: height=3.1*floors if isinstance(floors,(int,float)) and floors>0 else (6.2 if site!='Soriana Forjadores' else 7.0)
            height=max(2.8,min(48,height))
            b=encode_building(identifier,kind,p,height,{},lambda q:q.distance(asphalt)<=38,city['settings'])
            b.update(sf3_recovered=True,site=site,source_id=props['source_id'],sources=props.get('sources',[]),source_attributes={k:props[k] for k in ('class','subtype','num_floors') if props.get(k) is not None},height_estimated=not measured,height_m_source=props.get('height') if measured else None,num_floors_source=floors,height_source='source:height' if measured else 'estimated:SF3 low-poly site fallback',category='commercial' if site=='Soriana Forjadores' else 'institutional',category_source='OSM shop tag' if site=='Soriana Forjadores' else 'real footprint within documented OSM campus; visual category only',retained_fraction=p.area/original.area,geometry_adjusted=not p.equals_exact(original,1e-8),architecture_verified=False)
            # Sample canonical terrain vertices and perimeter offline positions;
            # runtime supplies the same elevation field as the car (or flat 0).
            samples=set(tuple(v) for ring in [b['footprint_xz']]+b['holes_xz'] for v in ring)
            for ring in [b['footprint_xz']]+b['holes_xz']:
                for a,z in zip(ring,ring[1:]+ring[:1]):
                    count=max(1,math.ceil(math.dist(a,z)/8))
                    samples.update((a[0]+(z[0]-a[0])*i/count,a[1]+(z[1]-a[1])*i/count) for i in range(count))
            x0,z0,x1,z1=p.bounds
            samples.update((x,z) for x in range(math.ceil(x0/8)*8,math.ceil(x1/8)*8,8) for z in range(math.ceil(z0/8)*8,math.ceil(z1/8)*8,8) if p.covers(Point(x,z)))
            b['elevation_samples_xz']=sorted(samples)
            accepted.append(b);polys.append(p)
    assert all(any(b['site']==name for b in accepted) for name in ['UABCS','Tec de La Paz','Soriana Forjadores'])
    groups=defaultdict(list)
    for b,p in zip(accepted,polys): groups[f'{math.floor(p.centroid.x/256)}_{math.floor(p.centroid.y/256)}'].append(b)
    entries=[]
    for key,rows in sorted(groups.items()):
        path=root/'chunks'/f'{key}.json';write(path,{'schema_version':1,'id':key,'chunk_cell':[int(v) for v in key.split('_')],'buildings':rows,'category_facades':False})
        bounds=unary_union([Polygon(b['footprint_xz'],b['holes_xz']) for b in rows]).bounds
        entries.append({'id':key,'file':'res://'+path.relative_to(ROOT).as_posix(),'sha256':digest(path),'bounds_xz':bounds,'building_count':len(rows),'collision_count':sum(b['collision_enabled'] for b in rows)})
    sources={p:digest(ROOT/p) for p in [xml_path,ov_path,'config/map_config.json','data/processed/la_paz_map.json','data/processed/arcade_layout.json','data/processed/urban/city_manifest.json','data/processed/urban/placement_audit.json','data/processed/urban/urban_geography.json','scripts/driving/ArcadeCar.gd','config/driving_config.json']}
    report={'schema_version':1,'units':'meters','origin_lat':cfg['origin_lat'],'origin_lon':cfg['origin_lon'],'license':'ODbL-1.0: derived OSM/Overture building database. Attribution and license notices: CREDITS_AND_LICENSES.md','overture_release':city['metadata']['sources']['overture_buildings']['release'],'map_sha256':city['map_sha256'],'arcade_sha256':sources['data/processed/arcade_layout.json'],'source_hashes':sources,'chunks':entries,'statistics':{'buildings':len(accepted),'by_site':dict(Counter(b['site'] for b in accepted)),'candidates':len(candidates),'rejected':len(rejected)},'note':'Real source footprints, approximate heights and facades. Campus parcels are not buildings. Open areas/arcade roads remain excluded. Supplement streams with the existing city; base assets unchanged.'}
    write(root/'manifest.json',report);write(root/'exclusions.json',rejected)
    assert all(p.intersection(hard).area<1e-6 and p.intersection(clearance).area<1e-6 for p in polys)
    assert all(digest(ROOT/p)==h for p,h in sources.items())
    print(json.dumps(report['statistics'],indent=2))


if __name__=='__main__': build()

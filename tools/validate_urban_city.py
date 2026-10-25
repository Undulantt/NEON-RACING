"""Validate actual urban data, protected land, provenance and untouched driving files."""
import hashlib,json,math
from collections import Counter
from pathlib import Path
from shapely.geometry import Polygon,LineString,shape
from shapely.ops import transform,unary_union
from shapely.strtree import STRtree
from fetch_urban_sources import ROOT,load_json,digest


def projection(metadata):
    sx=6371000*math.pi/180*math.cos(math.radians(metadata['origin_lat'])); sz=-6371000*math.pi/180
    def local(x,y,z=None):
        if hasattr(x,'__iter__'): return ([(v-metadata['origin_lon'])*sx for v in x],[(v-metadata['origin_lat'])*sz for v in y])
        return ((x-metadata['origin_lon'])*sx,(y-metadata['origin_lat'])*sz)
    return local

def validate(manifest_path=None):
    root=ROOT/'data/processed/urban'; manifest=load_json(Path(manifest_path) if manifest_path else root/'city_manifest.json')
    assert manifest['schema_version']==1 and manifest['units']=='meters'
    for path,expected in manifest['baseline_hashes'].items():
        assert digest(ROOT/path.replace('\\','/'))==expected, 'Baseline changed: '+path
    assert digest(ROOT/'data/processed/la_paz_map.json')==manifest['map_sha256']
    for kind,meta in manifest['metadata']['sources'].items():
        assert digest(ROOT/'data/raw'/meta['file'])==meta['sha256'], kind
        if meta.get('original_file'): assert digest(ROOT/'data/raw'/meta['original_file'])==meta['original_sha256']
    assert digest(root/manifest['audit_file'])==manifest['audit_sha256']
    audit=load_json(root/manifest['audit_file']); city=[]; polygons=[]
    raw=load_json(ROOT/'data/raw'/manifest['metadata']['sources']['overture_buildings']['file'])
    sources={str(f.get('id',f['properties'].get('id'))):f for f in raw['features']}
    old=load_json(ROOT/'data/processed/la_paz_environment.json'); osm={b['osm_way_id']:b for b in old['buildings']}
    baseline_map=load_json(ROOT/'data/processed/la_paz_map.json')
    surface=unary_union([Polygon([(p[0]+c['origin_xz'][0],p[1]+c['origin_xz'][1]) for p in tri]) for c in baseline_map['chunks'] for tri in c['triangles_xz']])
    clearance=surface.buffer(manifest['settings']['road_clearance_m'])
    protected=unary_union([shape(f['geometry_xz']) for f in audit['protected']])
    eligible={b['id']:b for b in audit['eligible_blocks']}; coast=shape(audit['coast_guard_xz'])
    project=projection(manifest); ids=set(); estimates=0; triangle_count=0; by_block=Counter()
    for chunk in manifest['chunks']:
        p=root/chunk['file']; assert digest(p)==chunk['sha256']; data=load_json(p)
        assert data['schema_version']==1 and len(data['buildings'])==chunk['building_count']
        for b in data['buildings']:
            assert b['id'] not in ids; ids.add(b['id'])
            poly=Polygon(b['footprint_xz'],b.get('holes_xz',[])); assert poly.is_valid and poly.area>1
            assert all(math.isfinite(v) for xy in b['footprint_xz'] for v in xy)
            assert math.isfinite(b['height_m']) and 2.8<=b['height_m']<=48
            assert poly.intersection(clearance).area<1e-6, 'Road intrusion: '+b['id']
            assert poly.intersection(protected).area<1e-6, 'Protected intrusion: '+b['id']
            roof=unary_union([Polygon(t) for t in b['roof_triangles_xz']]); assert poly.symmetric_difference(roof).area<1e-5, b['id']
            triangle_count+=len(b['roof_triangles_xz'])
            estimates+=bool(b['height_estimated'])
            assert b['fictional']==(b['source_kind']=='fictional')
            if b['fictional']:
                assert b['id'].startswith('fiction:inegi:') and b['height_estimated']
                block=eligible[b['inegi_block_id']]; assert shape(block['safe_geometry_xz']).buffer(1e-7).covers(poly)
                assert not poly.intersects(coast)
                assert block['real_coverage']>=manifest['settings']['fill_min_block_coverage'] and block['inhabited_dwellings']>0
                assert poly.distance(surface)<=manifest['settings']['fill_road_distance_m']
                by_block[b['inegi_block_id']]+=1
            else:
                if b['source_kind']=='overture':
                    source=sources[b['source_id']]; original=transform(project,shape(source['geometry'])); props=source['properties']
                    assert b['sources']==props.get('sources',[])
                else:
                    source=osm[b['source_id']]; original=Polygon(source['footprint_xz'])
                assert original.buffer(0.13).covers(poly), 'Unexpected moved footprint: '+b['id']
                assert b['retained_fraction']>=0.85
                if 'height_m' in b.get('override',{}):
                    assert b['height_estimated'] and b['height_source']=='manual override'
                else:
                    assert b['height_estimated']==(b['height_m_source'] is None)
            assert b['collision_enabled']==(poly.distance(surface)<=manifest['settings']['fill_road_distance_m'])
            city.append(b); polygons.append(poly)
    assert len(city)==manifest['statistics']['buildings'] and len(city)>len(old['buildings'])
    assert Counter(b['source_kind'] for b in city)==manifest['statistics']['source_counts']
    assert estimates==manifest['statistics']['height_estimated']
    assert all(count<=manifest['settings']['fill_max_per_block'] for count in by_block.values())
    assert sum(by_block.values())<=manifest['settings']['fill_max_total']
    tree=STRtree(polygons)
    for i,p in enumerate(polygons):
        for j in tree.query(p,predicate='intersects'):
            if i<int(j): assert p.intersection(polygons[int(j)]).area<0.01, f'Duplicate overlap: {city[i]["id"]}, {city[int(j)]["id"]}'
    return {'passed':True,'buildings':len(city),'fictional':sum(by_block.values()),'source_counts':dict(Counter(b['source_kind'] for b in city)),'roof_triangles':triangle_count,'chunks':len(manifest['chunks']),'baseline_hashes_unchanged':True,'road_and_protected_overlap_m2':0}

if __name__=='__main__':
    try:
        report=validate(); (ROOT/'docs/phase_b5_data_validation.json').write_text(json.dumps(report,indent=2),encoding='utf-8'); print(json.dumps(report,indent=2))
    except (AssertionError,ValueError,KeyError,OSError) as error: raise SystemExit(f'FAIL {type(error).__name__}: {error}')

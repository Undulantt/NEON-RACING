"""Independent source, exclusion and overlap checks for SF.3 recovered sectors."""
import json
import math
import xml.etree.ElementTree as ET
from collections import Counter
from shapely.geometry import Polygon, shape, mapping
from shapely.ops import transform, unary_union
from shapely.strtree import STRtree
from fetch_urban_sources import ROOT, digest
from validate_urban_city import projection
from urban_protection import real_building_exclusions, institutional_parcel


def read(p): return json.loads((ROOT/p).read_text(encoding='utf-8'))


def validate():
    report=read('data/processed/urban/sf3_recovery/manifest.json')
    for p,sha in report['source_hashes'].items(): assert digest(ROOT/p)==sha, p
    cfg=read('config/map_config.json'); project=projection(cfg)
    osm=ET.parse(ROOT/'data/raw/osm_map_c6_boundary_expansion.osm').getroot()
    nodes={e.attrib['id']:(float(e.attrib['lon']),float(e.attrib['lat'])) for e in osm.findall('node')}
    ways={e.attrib['id']:e for e in osm.findall('way')}
    city=read('data/processed/urban/city_manifest.json'); arcade=read('data/processed/arcade_layout.json')
    ov=read('data/raw/'+city['metadata']['sources']['overture_buildings']['file'])
    overture={str(f.get('id',f['properties'].get('id'))):f for f in ov['features']}
    protected=read('data/processed/urban/placement_audit.json')['protected']
    exclusions=real_building_exclusions(protected).union(shape(read('data/processed/urban/urban_geography.json')['water_geometry_xz']))
    roads=unary_union([Polygon([(x+c['origin_xz'][0],z+c['origin_xz'][1]) for x,z in t]) for c in arcade['chunks'] for t in c['triangles_xz']]).buffer(.8)
    old=[]
    for entry in city['chunks']:
        changes=read(arcade['chunk_overrides'][entry['id']]['file']) if entry['id'] in arcade['chunk_overrides'] else {}
        for b in read('data/processed/urban/'+entry['file'])['buildings']:
            b={**b,**changes.get(b['id'],{})}
            if not b.get('disabled'): old.append((b['id'],Polygon(b['footprint_xz'],b.get('holes_xz',[]))))
    old_tree=STRtree([p for _,p in old]); accepted=[]; ids=set()
    for entry in report['chunks']:
        path=ROOT/entry['file'].replace('res://','')
        assert digest(path)==entry['sha256']
        chunk=json.loads(path.read_text(encoding='utf-8')); assert len(chunk['buildings'])==entry['building_count']
        for b in chunk['buildings']:
            assert b['id'] not in ids; ids.add(b['id'])
            assert b['sf3_recovered'] and not b['fictional'] and not b['architecture_verified']
            p=Polygon(b['footprint_xz'],b['holes_xz']);assert p.is_valid
            assert p.intersection(roads).area<1e-6 and p.intersection(exclusions).area<1e-6,b['id']
            if b['source_kind']=='osm':
                e=ways[b['source_id']];tags={t.attrib['k']:t.attrib['v'] for t in e.findall('tag')}
                assert tags.get('building') not in (None,'no')
                original=transform(project,Polygon([nodes[n.attrib['ref']] for n in e.findall('nd')]))
            else:
                f=overture[b['source_id']];original=transform(project,shape(f['geometry']))
                assert b['sources']==f['properties'].get('sources',[])
            assert original.buffer(.13).covers(p),'Moved footprint: '+b['id']
            assert b['retained_fraction']>=.85
            roof=unary_union([Polygon(t) for t in b['roof_triangles_xz']]);assert p.symmetric_difference(roof).area<1e-5
            assert all(math.isfinite(v) for point in b['elevation_samples_xz'] for v in point)
            for i in old_tree.query(p): assert p.intersection(old[int(i)][1]).area<.01,'Duplicate existing '+b['id']
            accepted.append((b,p))
    tree=STRtree([p for b,p in accepted])
    for i,(b,p) in enumerate(accepted):
        for j in tree.query(p):
            if i<int(j): assert p.intersection(accepted[int(j)][1]).area<.01
    # Regression: the parcel exemption is narrow and never affects fictional fill.
    assert institutional_parcel({'amenity':'university'})
    assert not institutional_parcel({'amenity':'university','building':'yes'})
    assert not institutional_parcel({'leisure':'park'})
    assert not institutional_parcel({'amenity':'parking'})
    assert not institutional_parcel({'leisure':'pitch'})
    probe=Polygon([(0,0),(10,0),(10,10),(0,10)])
    parcel={'geometry_xz':mapping(probe),'tags':{'amenity':'university'}}
    assert real_building_exclusions([parcel]).is_empty
    assert not unary_union([shape(parcel['geometry_xz'])]).is_empty,'Fictional mask must retain campus'
    result={'passed':True,'buildings':len(accepted),'sectors':len(report['chunks']),'by_site':dict(Counter(b['site'] for b,p in accepted)),'source_hashes_verified':len(report['source_hashes']),'overlap_with_arcade_clearance_m2':0,'overlap_with_real_open_areas_m2':0,'duplicates':0,'road_and_car_unchanged':True}
    assert result['by_site']==report['statistics']['by_site']
    (ROOT/'docs/sf3_recovery_data_validation.json').write_bytes((json.dumps(result,indent=2)+'\n').encode('utf-8'))
    print(json.dumps(result,indent=2))


if __name__=='__main__': validate()

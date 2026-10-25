"""Validate B6 outputs independently of runtime rendering."""
import json, math
from pathlib import Path
from shapely.geometry import Point,Polygon,shape
from shapely.ops import unary_union
from build_urban_city import projector
from fetch_urban_sources import ROOT,load_json,digest

def validate():
    root=ROOT/'data/processed/urban'
    manifest=load_json(root/'city_manifest.json')
    for name,expected in manifest['b6_files'].items(): assert digest(root/name)==expected, name
    e=load_json(root/'urban_enrichment.json'); geo=load_json(root/'urban_geography.json'); landmarks=load_json(root/'landmarks.json')['landmarks']
    buildings={b['id']:b for c in manifest['chunks'] for b in load_json(root/c['file'])['buildings']}
    water=shape(geo['water_geometry_xz']); cfg=load_json(ROOT/'config/map_config.json'); project=projector(cfg)
    assert water.area>0 and geo['water_building_overlap_m2']<=0.01
    visual_polys=[Polygon(t) for surface in geo['surfaces'] for t in surface['triangles_xz']]
    visual_union=unary_union(visual_polys)
    assert abs(sum(p.area for p in visual_polys)-visual_union.area)<0.01, 'Visual surfaces overlap'
    data=load_json(ROOT/'data/processed/la_paz_map.json')
    road_polys=[Polygon([(p[0]+c['origin_xz'][0],p[1]+c['origin_xz'][1]) for p in tri]) for c in data['chunks'] for tri in c['triangles_xz']]
    road_union=unary_union(road_polys)
    assert visual_union.intersection(road_union).area<0.01, 'Visual ground underneath asphalt'
    south,west,north,east=cfg['bbox']
    region=Polygon([project(west,south),project(east,south),project(east,north),project(west,north)])
    assert region.difference(visual_union.union(road_union)).area<0.01, 'Missing visual ground'
    assert 5 <= len(landmarks) <= 10
    poi={p['id']:p for p in e['pois']}; assert len(poi)==len(e['pois'])
    south,west,north,east=cfg['bbox']
    source_hashes={}
    for p in poi.values():
        assert math.dist(project(p['lon'],p['lat']),p['position_xz']) < 1e-8
        assert west<=p['lon']<=east and south<=p['lat']<=north
        filename=p['source']['file']
        if filename not in source_hashes: source_hashes[filename]=digest(ROOT/'data/raw'/filename)
        assert source_hashes[filename]==p['source']['sha256']
        if not p.get('eligible_for_classification', True): assert not p['building_id']
        if p['building_id']:
            assert p['building_id'] in buildings
            if p['association_reason']=='unique containment':
                b=buildings[p['building_id']]; assert Polygon(b['footprint_xz'],b['holes_xz']).covers(Point(p['position_xz']))
        else: assert p['needs_review']
    for landmark in landmarks:
        p=poi[landmark['poi_id']]
        assert landmark['position_xz']==p['position_xz'] and landmark['source']==p['source']
        assert not landmark['architecture_verified']
    for b in buildings.values():
        assert Polygon(b['footprint_xz'],b['holes_xz']).intersection(water).area<=0.01
        if 'facade_edge_index' in b: assert 0 <= b['facade_edge_index'] < len(b['footprint_xz'])
    return {'passed':True,'pois':len(poi),'landmarks':len(landmarks),'mapped_surfaces':len(geo['surfaces']),'visual_ground_coverage_verified':True,'visual_surface_overlap_m2':0,'water_area_m2':water.area,'water_building_overlap_m2':0,'orphan_overrides':e['orphan_overrides'],'statistics':e['statistics']}

if __name__=='__main__':
    report=validate()
    (ROOT/'docs/phase_b6_data_validation.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps(report,ensure_ascii=False,indent=2))

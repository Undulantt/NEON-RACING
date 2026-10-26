"""Refresh only B6 visual geography from verified existing city and source snapshots."""
from expansion_regions import metric_region
import json
from shapely.geometry import box, Polygon
from shapely.ops import transform, unary_union
from build_urban_city import projector, protected_shapes
from urban_geography import surfaces, mapped_area_ids
from fetch_urban_sources import ROOT, load_json, digest, cached

def build():
    cfg=load_json(ROOT/'config/map_config.json')
    target=ROOT/'data/processed/urban'
    manifest=load_json(target/'city_manifest.json')
    source_map=ROOT/'data/processed/la_paz_map.json'
    if manifest['map_sha256'] != digest(source_map): raise ValueError('Regenerate the city for this map first')
    data=load_json(source_map)
    buildings=[]
    for chunk in manifest['chunks']:
        path=target/chunk['file']
        if digest(path)!=chunk['sha256']: raise ValueError('City chunk hash mismatch')
        buildings.extend(load_json(path)['buildings'])
    found=cached('osm_protected',cfg['bbox'])
    if not found or found[1]!=manifest['metadata']['sources']['osm_protected']: raise ValueError('Source changed; regenerate full city')
    raw=load_json(found[0]); project=projector(cfg)
    protected,coast=protected_shapes(raw,project)
    south,west,north,east=cfg['bbox']; region=metric_region({**cfg,"active_blocks":{"visual_envelope":cfg["bbox"]}})
    roads=unary_union([Polygon([(p[0]+c['origin_xz'][0],p[1]+c['origin_xz'][1]) for p in tri]) for c in data['chunks'] for tri in c['triangles_xz']])
    geography=surfaces(region,coast,protected,buildings,roads,mapped_area_ids(raw))
    path=target/'urban_geography.json'
    path.write_text(json.dumps(geography,ensure_ascii=False,separators=(',',':')),encoding='utf-8')
    manifest['b6_files'][path.name]=digest(path)
    (target/'city_manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2,allow_nan=False),encoding='utf-8')
    print('Visual surfaces:',len(geography['surfaces']),'hash:',digest(path))
if __name__=='__main__': build()

"""Rebuild geography only after pinning the previous sea, reusing unchanged city footprints and road masks."""
import json
from pathlib import Path
from shapely.geometry import Polygon,shape
from shapely.ops import unary_union
from build_urban_city import protected_shapes,projector
from expansion_regions import metric_region
from fetch_urban_sources import cached,digest
from urban_geography import surfaces,mapped_area_ids

ROOT=Path(__file__).resolve().parents[1]
def read(path):return json.loads(path.read_text(encoding='utf-8'))
def write(path,data):path.write_text(json.dumps(data,ensure_ascii=False,separators=(',',':'))+'\n',encoding='utf-8',newline='\n')

def rebuild():
    cfg=read(ROOT/'config/map_config.json');city=read(ROOT/'data/processed/urban/city_manifest.json')
    found=cached('osm_protected',cfg['bbox']);raw=read(found[0])
    protected,coast=protected_shapes(raw,projector(cfg))
    data=read(ROOT/'data/processed/la_paz_map.json')
    roads=unary_union([unary_union([Polygon([(x+c['origin_xz'][0],z+c['origin_xz'][1]) for x,z in t]) for t in c['triangles_xz']]) for c in data['chunks']])
    buildings=[b for e in city['chunks'] for b in read(ROOT/'data/processed/urban'/e['file'])['buildings']]
    region=metric_region({**cfg,'active_blocks':{'envelope':cfg['bbox']}})
    sea=shape(read(ROOT/cfg['preserved_sea_file'])['geometry'])
    geography=surfaces(region,coast,protected,buildings,roads,mapped_area_ids(raw),sea)
    target=ROOT/'data/processed/urban/urban_geography.json';write(target,geography)
    city['b6_files']['urban_geography.json']=digest(target)
    citypath=ROOT/'data/processed/urban/city_manifest.json';write(citypath,city)
    arcade=read(ROOT/'data/processed/arcade_layout.json');arcade['city_sha256']=digest(citypath)
    write(ROOT/'data/processed/arcade_layout.json',arcade)
    print('Geography rebuilt with exact preserved sea; city volumes and arcade footprints unchanged')

if __name__=='__main__':rebuild()

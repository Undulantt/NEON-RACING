"""Apply the user-authorized fictional sea cells and local Centre/South outset."""
import json
from pathlib import Path
from shapely.geometry import shape,box,Polygon,mapping
from shapely.ops import unary_union
from shapely.prepared import prep

ROOT=Path(__file__).resolve().parents[1]
def read(p):return json.loads(p.read_text(encoding='utf-8'))
def write(p,d):p.write_text(json.dumps(d,indent=2,ensure_ascii=False)+'\n',encoding='utf-8',newline='\n')

def prepare():
    baseline=ROOT/'docs/coast_fix_baseline';baseline.mkdir(exist_ok=True)
    for src,name in [('data/processed/relief/world/manifest.json','relief_manifest.json'),('data/processed/urban/urban_geography.json','urban_geography.json'),('config/relief_config.json','relief_config.json')]:
        target=baseline/name
        if not target.exists():target.write_bytes((ROOT/src).read_bytes())
    manifest=read(baseline/'relief_manifest.json');b=manifest['bounds_xz']
    width=max(b[2]-b[0],(b[3]-b[1])*2/3)*1.12;height=width*1.5
    left=(b[0]+b[2])/2-width/2;top=(b[1]+b[3])/2-height/2
    x1=left+width/4;x2=left+width/2
    y1=top+(100+3640/6)*height/3840;y2=top+(100+2*3640/6)*height/3840
    # The urban lower/eastern part of A3 is retained. The upper/western sea
    # connects to the existing bay, avoiding all streets and buildings.
    a3=Polygon([(left-100,y2),(x1,y2),(-1750,889.56),(-2380,1200),(-2700,1350),(left-100,1350)])
    correction=unary_union([box(left-100,top-100,x1,y2),box(x1,top-100,x2,y1),a3])
    original=shape(read(baseline/'urban_geography.json')['water_geometry_xz'])
    sea=original.union(correction);new_water=prep(sea.difference(original))
    city=read(ROOT/'data/processed/urban/city_manifest.json')
    for entry in city['chunks']:
        for building in read(ROOT/'data/processed/urban'/entry['file'])['buildings']:
            poly=Polygon(building['footprint_xz'],building.get('holes_xz',[]))
            if new_water.intersects(poly) and poly.intersection(sea.difference(original)).area>.01:
                raise ValueError('Coast correction would flood urban A3: '+building['id'])
    target=ROOT/'data/reference/sea_c6_coastal_fix.geojson'
    write(target,{'type':'Feature','geometry':mapping(sea),'properties':{'source':'User-directed fictional sea correction, 2026-10-31','sea_adjustment_geometry_xz':mapping(correction),'affected_cells':['A1','A2','B1','A3 coastal part'],'reference_capture_bounds_xz':b,'original_sea_file':'data/reference/sea_before_c6.geojson','preserve_urban_A3':True}})
    for name in ['config/map_config.json','config/expansion_config.json']:
        path=ROOT/name;cfg=read(path);cfg['preserved_sea_file']=target.relative_to(ROOT).as_posix();write(path,cfg)
    path=ROOT/'config/relief_config.json';cfg=read(path)
    cfg['local_boundary_outsets']=[{'id':'core_south_join','center_xz':[2285.29,889.56],'radius_m':400,'outset_m':60,'note':'User-directed gradual mountain setback outside the Centre/South join'}]
    write(path,cfg)
    print('Sea correction prepared; all urban buildings retained; local 60m boundary setback configured')

if __name__=='__main__':prepare()

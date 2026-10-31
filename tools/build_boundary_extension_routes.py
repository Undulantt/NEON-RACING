"""Reproducible directed OSM test routes into each newly added area."""
import json,math
from pathlib import Path
from shapely.geometry import Point,shape
from map_core import gps_to_local,dijkstra
from expansion_regions import metric_region
from build_expansion_routes import route

ROOT=Path(__file__).resolve().parents[1]
def read(p):return json.loads(p.read_text(encoding='utf-8'))

def build():
    cfg=read(ROOT/'config/map_config.json');data=read(ROOT/'data/processed/la_paz_map.json')
    old=shape(read(ROOT/'docs/map_extension_baseline/relief_manifest.json')['region_geojson'])
    region=metric_region(cfg);added=region.difference(old).buffer(-40)
    manifest=read(ROOT/'data/processed/expansion_manifest.json')
    start=manifest['routes'][0]
    start=read(ROOT/start['file'])['node_ids'][0]
    distances,_=dijkstra(data,start)
    candidates=[n for n in data['nodes'] if n['id'] in distances and not n['boundary_generated'] and added.covers(Point(n['x'],n['z'])) and region.boundary.distance(Point(n['x'],n['z']))>65]
    entries=[]
    for label,lat,lon in [('C2',24.1557,-110.2999),('A4',24.134,-110.3438),('A5',24.120,-110.3430)]:
        x,z=gps_to_local(lat,lon,cfg['origin_lat'],cfg['origin_lon'])
        node=min(candidates,key=lambda n:math.hypot(n['x']-x,n['z']-z))
        assert math.hypot(node['x']-x,node['z']-z)<550,(label,node)
        result=route(data,'extension_'+label,'Test '+label,[start,node['id']])
        path=ROOT/('tracks/extension_'+label+'.json')
        path.write_text(json.dumps(result,indent=2,ensure_ascii=False)+'\n',encoding='utf-8',newline='\n')
        entries.append({'area':label,'file':path.relative_to(ROOT).as_posix(),'length_m':result['length_m'],'target_xz':[node['x'],node['z']],'target_osm_node':node['id']})
    output=ROOT/'docs/map_extension_routes.json'
    output.write_text(json.dumps({'routes':entries},indent=2)+'\n',encoding='utf-8',newline='\n')
    print(entries)

if __name__=='__main__':build()

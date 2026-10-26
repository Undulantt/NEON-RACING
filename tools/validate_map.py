"""Validate geometry, provenance, directions, coverage, and real directed route."""
import argparse
import hashlib
import json
import math
from pathlib import Path
from shapely.geometry import Polygon, LineString, Point
from shapely.ops import unary_union
from shapely.strtree import STRtree
from fetch_osm import ROOT
from map_core import dijkstra, gps_to_local

def validate(data,check_source=True):
    assert data['schema_version']==1
    assert data['metadata']['units']=='meters'
    def finite(value):
        if isinstance(value,float): assert math.isfinite(value)
        elif isinstance(value,dict):
            for v in value.values(): finite(v)
        elif isinstance(value,list):
            for v in value: finite(v)
    finite(data)
    nodes={n['id']:n for n in data['nodes']}; roads={r['id']:r for r in data['roads']}; edges={e['id']:e for e in data['edges']}
    assert len(nodes)==len(data['nodes']) and len(roads)==len(data['roads']) and len(edges)==len(data['edges'])
    assert len(roads)>50 and len(data['chunks'])>0
    from expansion_regions import metric_region
    config={**data['metadata']}
    if not config.get('active_blocks'): config.pop('active_blocks',None)
    region=metric_region(config)
    x0,z0,x1,z1=region.bounds
    assert 1000<max(n['x'] for n in nodes.values())-min(n['x'] for n in nodes.values())<=x1-x0+0.01
    assert 1000<max(n['z'] for n in nodes.values())-min(n['z'] for n in nodes.values())<=z1-z0+0.01
    assert all(region.buffer(1e-5).covers(Point(n['x'],n['z'])) for n in nodes.values()), 'Node outside active blocks'
    for road in roads.values():
        assert road['from'] in nodes and road['to'] in nodes and road['length_m']>0.001
        assert abs(LineString(road['points_xz']).length-road['length_m'])<1e-5
        assert len(road['points_xz'])>=2
        for key,p in zip(('from','to'),(road['points_xz'][0],road['points_xz'][-1])):
            assert math.dist(p,[nodes[road[key]]['x'],nodes[road[key]]['z']])<1e-6
        expected=[False] if road['oneway'] else [False,True]
        assert sorted(e['reverse'] for e in edges.values() if e['road_id']==road['id'])==expected
    for edge in edges.values():
        road=roads[edge['road_id']]
        assert [edge['from'],edge['to']]==([road['to'],road['from']] if edge['reverse'] else [road['from'],road['to']])
        assert edge['length_m']==road['length_m']
    road_list=list(roads.values()); lines=[LineString(r['points_xz']) for r in road_list]; tree=STRtree(lines)
    for i,line in enumerate(lines):
        for j in tree.query(line,predicate='crosses'):
            if i<int(j):
                assert {road_list[i]['from'],road_list[i]['to']} & {road_list[int(j)]['from'],road_list[int(j)]['to']}, f'Nonshared crossing: {road_list[i]["id"]} / {road_list[int(j)]["id"]}'
    route=data['verification_route']; seq=route['road_node_sequence']; length=0; points=[]
    for i,eid in enumerate(route['edge_ids']):
        edge=edges[eid]; assert [edge['from'],edge['to']]==seq[i:i+2]
        length+=edge['length_m']; p=roads[edge['road_id']]['points_xz']
        if edge['reverse']: p=list(reversed(p))
        points.extend(p if not points else p[1:])
    assert len(seq)==len(route['edge_ids'])+1
    assert points==route['points_xz'] and 1200<=length<=2500 and abs(length-route['total_length_m'])<1e-5
    distances,_=dijkstra(data,seq[0]); assert abs(distances[seq[-1]]-length)<1e-5
    polygons=[]
    for chunk in data['chunks']:
        ox,oz=chunk['origin_xz']
        for tri in chunk['triangles_xz']:
            assert len(tri)==3
            polygon=Polygon([(x+ox,z+oz) for x,z in tri]); assert polygon.area>1e-8
            polygons.append(polygon)
    surface=unary_union(polygons)
    assert abs(sum(p.area for p in polygons)-surface.area)<0.01, 'Overlapping asphalt triangles'
    expected=unary_union([LineString(r['points_xz']).buffer(r['width_m']/2,quad_segs=4,cap_style='round',join_style='mitre',mitre_limit=2) for r in roads.values()])
    from expansion_regions import metric_clip
    user_clip=metric_clip(config)
    if user_clip is not None: expected=expected.intersection(user_clip)
    assert surface.symmetric_difference(expected).area<0.01, 'Holes or unexpected asphalt'
    tolerant_surface=surface.buffer(0.00001)
    for road in roads.values():
        assert tolerant_surface.covers(LineString(road['points_xz'])), road['id']
    if check_source:
        meta=data['metadata']['provenance']; raw=ROOT/'data/raw'/meta['file']
        assert hashlib.sha256(raw.read_bytes()).hexdigest()==meta['sha256']
        source=json.loads(raw.read_bytes()); ways={str(e['id']):e for e in source['elements'] if e['type']=='way'}
        original_nodes={str(e['id']):e for e in source['elements'] if e['type']=='node'}
        for n in nodes.values():
            if n['osm_node_id']:
                original=original_nodes[n['osm_node_id']]
                p=gps_to_local(original['lat'],original['lon'],data['metadata']['origin_lat'],data['metadata']['origin_lon'])
                assert math.dist(p,[n['x'],n['z']])<1e-6
        for r in roads.values():
            assert r['osm_tags']==ways[r['osm_way_id']]['tags']
    return data['statistics']

def main():
    parser=argparse.ArgumentParser(description=__doc__); parser.add_argument('--input',default='data/processed/la_paz_map.json'); args=parser.parse_args()
    try:
        data=json.loads((ROOT/args.input).read_text(encoding='utf-8')); print('PASS',validate(data))
    except (AssertionError,ValueError,KeyError,OSError) as error:
        raise SystemExit(f'FAIL {type(error).__name__}: {error}')

if __name__=='__main__': main()

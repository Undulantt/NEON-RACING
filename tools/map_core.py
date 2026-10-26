"""Metric OSM conversion and deterministic planar road mesh. No Godot dependency."""
import heapq
import math
import re
from collections import defaultdict
from shapely.geometry import LineString, box
from shapely.ops import unary_union
from shapely import constrained_delaunay_triangles

R = 6371000.0

def gps_to_local(lat, lon, lat0, lon0):
    return (R * math.radians(lon-lon0) * math.cos(math.radians(lat0)), -R * math.radians(lat-lat0))

def number(value):
    match = re.fullmatch(r'\s*(\d+(?:\.\d+)?)\s*(m|mph|km/h)?\s*', str(value))
    if not match:
        return None
    result = float(match[1])
    return result * 1.609344 if match[2] == 'mph' else result

def allowed(tags):
    access = next((tags[k] for k in ('motorcar','motor_vehicle','vehicle','access') if k in tags), 'yes')
    return access not in ('no','private','agricultural','forestry') and tags.get('area') != 'yes' and tags.get('bridge','no') == 'no' and tags.get('tunnel','no') == 'no' and tags.get('layer','0') == '0' and tags.get('indoor','no') != 'yes'

def allowed_way(tags, cfg, way_id):
    if allowed(tags):
        return True
    reviewed = cfg.get('road_import_policy', {}).get('approved_flat_bridge_way_ids', [])
    return str(way_id) in reviewed and tags.get('bridge') == 'yes' and tags.get('layer') == '1' and allowed({**tags, 'bridge':'no', 'layer':'0'})


def attributes(tags, cfg):
    explicit_width = number(tags.get('width',''))
    lanes = number(tags.get('lanes',''))
    width = explicit_width or (lanes * 3.2 if lanes else cfg['widths_m'][tags['highway']])
    # Reject malformed measurements rather than silently clamping genuine OSM values.
    if not 1 <= width <= 60:
        raise ValueError(f'Invalid width: {tags}')
    oneway = tags.get('oneway', 'yes' if tags.get('junction') == 'roundabout' else 'no')
    if oneway not in ('yes','1','true','-1','no','0','false'):
        raise ValueError(f'Unsupported reversible/conditional direction: {tags}')
    return {'width_m':width,'width_estimated':explicit_width is None,'width_source':'osm:width' if explicit_width else ('estimated:lanes*3.2' if lanes else 'estimated:highway'), 'lanes':lanes,'maxspeed_kph':number(tags.get('maxspeed','')) or cfg['default_speed_kph'],'maxspeed_estimated':number(tags.get('maxspeed','')) is None,'oneway':oneway in ('yes','1','true','-1'),'reversed':oneway == '-1','street_name':tags.get('name',''),'highway':tags['highway']}

def dijkstra(data, start):
    adjacency = defaultdict(list)
    for edge in data['edges']:
        adjacency[edge['from']].append(edge)
    distances = {start:0.0}; previous = {}; heap = [(0.0,start)]
    while heap:
        distance, node = heapq.heappop(heap)
        if distance > distances[node]:
            continue
        for edge in adjacency[node]:
            target = edge['to']; candidate = distance + edge['length_m']
            if candidate < distances.get(target,float('inf')):
                distances[target] = candidate; previous[target] = edge
                heapq.heappush(heap,(candidate,target))
    return distances, previous

def verification_route(data):
    roads = {r['id']:r for r in data['roads']}
    candidates = sorted({r['from'] for r in data['roads'] if 'obreg' in r['street_name'].lower()})
    if not candidates:
        raise ValueError('No Obregon corridor in selected OSM data')
    best = None
    for start in candidates[::max(1,len(candidates)//16)]:
        distances, previous = dijkstra(data,start)
        for target, length in distances.items():
            if not 1200 <= length <= 2500:
                continue
            edges=[]; node=target
            while node != start:
                edge=previous[node]; edges.append(edge); node=edge['from']
            edges.reverse()
            coastal=sum(e['length_m'] for e in edges if 'obreg' in roads[e['road_id']]['street_name'].lower())
            score=(coastal,-abs(length-1800))
            if best is None or score > best[0]:
                points=[]
                for e in edges:
                    p=roads[e['road_id']]['points_xz']
                    if e['reverse']: p=list(reversed(p))
                    points.extend(p if not points else p[1:])
                best=(score,{'purpose':'phase_a_connectivity_probe_not_a_race','edge_ids':[e['id'] for e in edges],'road_node_sequence':[start]+[e['to'] for e in edges],'points_xz':points,'total_length_m':length,'obregon_length_m':coastal})
    if best is None:
        raise ValueError('No directed 1.2-2.5 km route found')
    return best[1]

def convert(raw,cfg,provenance):
    source_nodes={str(e['id']):e for e in raw['elements'] if e['type']=='node'}
    nodes={}; roads=[]; edges=[]; exclusions=[]
    south,west,north,east=cfg['bbox']; lat0=cfg['origin_lat']; lon0=cfg['origin_lon']
    minx,maxz=gps_to_local(south,west,lat0,lon0); maxx,minz=gps_to_local(north,east,lat0,lon0)
    from expansion_regions import metric_region
    bounds=metric_region(cfg)
    for way in sorted((e for e in raw['elements'] if e['type']=='way'),key=lambda e:e['id']):
        tags=way.get('tags',{})
        if str(way['id']) in cfg.get('road_import_policy', {}).get('deferred_lower_crossing_way_ids', []):
            exclusions.append({'way_id':str(way['id']),'reason':'deferred lower-level crossing: flat prototype cannot represent the reviewed Forjadores embankment and its underpass simultaneously','tags':tags}); continue
        if tags.get('highway') not in cfg['highways'] or not allowed_way(tags,cfg,way['id']) or any(k in tags for k in ('oneway:conditional','motor_vehicle:conditional','access:conditional')):
            exclusions.append({'way_id':str(way['id']),'reason':'access, level, area or conditional restriction','tags':tags}); continue
        try:
            attrs=attributes(tags,cfg)
        except ValueError as error:
            exclusions.append({'way_id':str(way['id']),'reason':str(error),'tags':tags}); continue
        for i,(aid,bid) in enumerate(zip(way['nodes'],way['nodes'][1:])):
            a=source_nodes.get(str(aid)); b=source_nodes.get(str(bid))
            if not a or not b:
                raise ValueError(f'Missing OSM node way={way["id"]}, pair={aid},{bid}')
            pa=gps_to_local(a['lat'],a['lon'],lat0,lon0); pb=gps_to_local(b['lat'],b['lon'],lat0,lon0)
            if math.dist(pa,pb) < 0.001:
                continue
            clipped_area=LineString([pa,pb]).intersection(bounds)
            parts=[clipped_area] if clipped_area.geom_type=='LineString' else [g for g in getattr(clipped_area,'geoms',[]) if g.geom_type=='LineString']
            for part_index,clipped in enumerate(parts):
                if clipped.is_empty or clipped.length<0.01:
                    continue
                pts=[list(p) for p in clipped.coords]
                ids=[]
                for side,(p,original,original_p) in enumerate(zip(pts,(str(aid),str(bid)),(pa,pb))):
                    original_match=math.dist(p,original_p)<1e-6
                    key=original if original_match else f'clip:{way["id"]}:{i}:{part_index}:{side}'
                    nodes[key]={'id':key,'x':p[0],'z':p[1],'osm_node_id':original if original_match else None,'boundary_generated':not original_match}
                    ids.append(key)
                if attrs['reversed']:
                    pts.reverse(); ids.reverse()
                road={'id':f'{way["id"]}:{i}'+(f':part{part_index}' if len(parts)>1 else ''),'osm_way_id':str(way['id']),'osm_node_ids':[str(aid),str(bid)],'from':ids[0],'to':ids[1],'points_xz':pts,'length_m':clipped.length,'osm_tags':tags,**attrs}
                if str(way['id']) in cfg.get('road_import_policy',{}).get('approved_flat_bridge_way_ids',[]):
                    road['elevation_treatment']='reviewed source bridge rendered at flat prototype height; source tags retained'
                roads.append(road)
                for reverse in ([False] if attrs['oneway'] else [False,True]):
                    edges.append({'id':road['id']+(':reverse' if reverse else ':forward'),'road_id':road['id'],'from':ids[1] if reverse else ids[0],'to':ids[0] if reverse else ids[1],'length_m':clipped.length,'reverse':reverse})
    data={'schema_version':1,'metadata':{'source':'OpenStreetMap contributors','license':'ODbL-1.0','origin_lat':lat0,'origin_lon':lon0,'bbox':cfg['bbox'],'units':'meters','axes':'+X=east,-Z=north,+Y=up','flat_y_m':0,'elevation_estimated':True,'provenance':provenance,'boundary_policy':'clip centerlines; generated boundary nodes explicitly marked; asphalt extends half-width beyond boundary','topology_policy':'one edge per consecutive OSM node pair; no geometric crossing connections','turn_restrictions':'Not imported; route is a topology probe, not validated legal navigation.'},'nodes':sorted(nodes.values(),key=lambda n:n['id']),'roads':roads,'edges':edges,'exclusions':exclusions,'buildings':[]}
    data['metadata']['active_blocks']=cfg.get('active_blocks',{})
    data['metadata']['road_import_policy']=cfg.get('road_import_policy',{})
    if cfg.get('clip_polygon_lonlat'): data['metadata']['clip_polygon_lonlat']=cfg['clip_polygon_lonlat']
    data['verification_route']=verification_route(data)
    # True planar union removes overlap, including intersections and curved joins.
    asphalt=unary_union([LineString(r['points_xz']).buffer(r['width_m']/2,quad_segs=4,cap_style='round',join_style='mitre',mitre_limit=2) for r in roads])
    from expansion_regions import metric_clip
    user_clip=metric_clip(cfg)
    if user_clip is not None: asphalt=asphalt.intersection(user_clip)
    chunks=[]; size=cfg['chunk_size_m']; x0,z0,x1,z1=asphalt.bounds
    for cx in range(math.floor(x0/size),math.floor(x1/size)+1):
        for cz in range(math.floor(z0/size),math.floor(z1/size)+1):
            tile=asphalt.intersection(box(cx*size,cz*size,(cx+1)*size,(cz+1)*size))
            if tile.is_empty or tile.area < 1e-6:
                continue
            triangles=[]
            for triangle in constrained_delaunay_triangles(tile).geoms:
                pts=list(triangle.exterior.coords)[:3]
                if triangle.area > 1e-8:
                    triangles.append([[p[0]-cx*size,p[1]-cz*size] for p in pts])
            if triangles:
                chunks.append({'id':f'{cx}_{cz}','origin_xz':[cx*size,cz*size],'triangles_xz':triangles})
    data['chunks']=chunks
    data['statistics']={'roads':len(roads),'nodes':len(nodes),'directed_edges':len(edges),'excluded_ways':len(exclusions),'asphalt_area_m2':asphalt.area,'chunks':len(chunks),'triangles':sum(len(c['triangles_xz']) for c in chunks)}
    return data

"""Offline sidewalk/furniture derivation. Never modifies base cartography or physics.

Run .venv-urban/Scripts/python.exe tools/build_streetscape.py.
OSM is evidence, not a municipal asset survey. Inferred dimensions/placements
are explicitly marked, and no medians are inferred from parallel carriageways.
"""
import hashlib
import gzip
import json
import math
import xml.etree.ElementTree as ET
from collections import Counter
from pathlib import Path

from shapely import constrained_delaunay_triangles
from shapely.geometry import LineString, Point, Polygon, box, shape
from shapely.ops import unary_union
from shapely.strtree import STRtree

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'data/processed/streetscape'


def read(path):
    return json.loads((ROOT / path).read_text(encoding='utf-8'))


def digest(path):
    return hashlib.sha256((ROOT / path).read_bytes()).hexdigest()


def write(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    encoded = (json.dumps(data, ensure_ascii=False, separators=(',', ':'), allow_nan=False)+'\n').encode('utf-8')
    path.write_bytes(gzip.compress(encoded, mtime=0) if path.suffix == '.gz' else encoded)


def parts(g):
    if g.geom_type == 'Polygon':
        return [g]
    return [p for child in getattr(g, 'geoms', []) for p in parts(child)]


def local_union(tree, polygons, region):
    return unary_union([polygons[int(i)] for i in tree.query(region)])


def build():
    paths = ['data/processed/la_paz_map.json', 'data/processed/arcade_layout.json',
             'data/processed/urban/city_manifest.json', 'data/processed/urban/placement_audit.json',
             'data/processed/urban/urban_geography.json', 'data/raw/osm_map_c6_boundary_expansion.osm']
    before = {p: digest(p) for p in paths}
    data = read(paths[0]); arcade = read(paths[1]); city = read(paths[2])
    assert arcade['map_sha256'] == before[paths[0]] == city['map_sha256']
    roads = data['roads']
    asphalt = unary_union([LineString(r['points_xz']).buffer(arcade['widths_m'][r['id']]/2, quad_segs=4, cap_style='round', join_style='mitre', mitre_limit=2) for r in roads])
    from expansion_regions import metric_clip
    clip = metric_clip(read('config/map_config.json'))
    if clip is not None:
        asphalt = asphalt.intersection(clip)
    print('Asphalt prepared', flush=True)
    # Retain every effective building, including recovered campuses.
    buildings = []
    for c in city['chunks']:
        p = 'data/processed/urban/'+c['file']; before[p] = digest(p)
        assert before[p] == c['sha256']
        override = arcade['chunk_overrides'].get(c['id'])
        changes = {}
        if override:
            before[override['file']] = digest(override['file'])
            assert before[override['file']] == override['sha256']
            changes = read(override['file'])
        for b in read(p)['buildings']:
            b = {**b, **changes.get(b['id'], {})}
            if not b.get('disabled'):
                buildings.append(Polygon(b['footprint_xz'], b.get('holes_xz', [])))
    recovery_path = 'data/processed/urban/sf3_recovery/manifest.json'
    if (ROOT/recovery_path).exists():
        before[recovery_path] = digest(recovery_path)
        recovery = read(recovery_path)
        for c in recovery.get('chunks', []):
            p = c['file'].removeprefix('res://'); before[p] = digest(p)
            for b in read(p)['buildings']:
                buildings.append(Polygon(b['footprint_xz'], b.get('holes_xz', [])))
    building_tree = STRtree(buildings)
    geography = read(paths[4]); water = shape(geography['water_geometry_xz'])
    protected = [shape(p['geometry_xz']) for p in read(paths[3])['protected']]
    # Do not pave parks, beaches, educational grounds, parking areas or water.
    protected += [Polygon(t) for s in geography['surfaces'] if s['kind'] in ('park', 'parking', 'water') for t in s['triangles_xz']]
    hard = unary_union(protected+[water])
    xml = ET.parse(ROOT/paths[5]).getroot()
    evidence = []
    explicit_medians = []
    for e in xml.findall('way'):
        t = {a.attrib['k']: a.attrib['v'] for a in e.findall('tag')}
        if t.get('footway') == 'sidewalk' or any(k.startswith('sidewalk') for k in t):
            evidence.append({'osm_way_id': e.attrib['id'], 'tags': t})
        if t.get('area:highway') == 'traffic_island' or t.get('traffic_calming') == 'island' or 'median' in t:
            explicit_medians.append(e.attrib['id'])
    # Estimated 2.6m strip outside the actual widened road. OSM sides/no respected.
    bands = []
    eligible = []
    allowed = {'residential', 'unclassified', 'tertiary', 'secondary', 'primary', 'living_street'}
    for r in roads:
        tags = r.get('osm_tags', {})
        if r['highway'] not in allowed or tags.get('sidewalk') == 'no':
            continue
        line = LineString(r['points_xz']); half = arcade['widths_m'][r['id']]/2
        malecon = 'obreg' in r['street_name'].lower()
        width = 4.2 if malecon else 2.6
        for side in ['left', 'right']:
            value = tags.get('sidewalk:'+side, tags.get('sidewalk', 'unknown'))
            if value == 'no' or value in ('left', 'right') and value != side:
                continue
            offset = line.parallel_offset(half+width/2+.22, side, join_style=2)
            bands.append(offset.buffer(width/2, cap_style='flat', join_style='mitre'))
        eligible.append(r)
    sidewalks = unary_union(bands).difference(asphalt.buffer(.22)).difference(hard)
    if clip is not None:
        sidewalks = sidewalks.intersection(clip)
    print('Sidewalk envelope prepared', flush=True)
    road_lines = [LineString(r['points_xz']) for r in eligible]
    road_tree = STRtree(road_lines)
    road_buffers = [LineString(r['points_xz']).buffer(arcade['widths_m'][r['id']]/2+.22, quad_segs=4) for r in roads]
    road_buffer_tree = STRtree(road_buffers)
    chunks = []; counts = Counter(); occupied = {}; samples = []
    max_overlap = 0.0
    # Urban-owned sectors unload all pavement and furniture together.
    for c in sorted(city['chunks'], key=lambda c:c['id']):
        cx, cz = map(int, c['id'].split('_')); tile = box(cx*256, cz*256, (cx+1)*256, (cz+1)*256)
        slab = sidewalks.intersection(tile)
        if slab.is_empty:
            continue
        local_buildings = local_union(building_tree, buildings, tile.buffer(8))
        slab = slab.difference(local_buildings.buffer(.25))
        polys = [p for p in parts(slab) if p.area >= 1.5]
        slab = unary_union(polys)
        if slab.is_empty:
            continue
        local_asphalt = local_union(road_buffer_tree, road_buffers, tile)
        overlap = slab.intersection(asphalt).area
        max_overlap = max(max_overlap, overlap)
        assert overlap < 1e-6
        assert slab.intersection(local_buildings).area < 1e-6
        assert slab.intersection(hard).area < 1e-6
        faces = []; edges = []
        for poly in polys:
            # Simplify only within the legal mask; intersection restores exclusions.
            clean = poly.simplify(.08, preserve_topology=True).intersection(poly)
            for small in parts(clean):
                dense = small.segmentize(12)
                for tri in constrained_delaunay_triangles(dense).geoms:
                    if tri.area > .001:
                        faces.append([[round(x,6), round(z,6)] for x,z in list(tri.exterior.coords)[:3]])
            dense = poly.segmentize(8)
            for ring in [dense.exterior, *dense.interiors]:
                for a,b in zip(ring.coords, list(ring.coords)[1:]):
                    # Omit artificial sector cuts; no neon seams at sector borders.
                    if any(abs(a[i]-b[i])<1e-7 and abs(a[i]/256-round(a[i]/256))<1e-7 for i in (0,1)):
                        continue
                    edges.append([[round(x,6),round(z,6)] for x,z in (a,b)])
        transforms = []
        region = tile.buffer(12)
        candidates = sorted((eligible[int(i)] for i in road_tree.query(region)), key=lambda r:('obreg' not in r['street_name'].lower(), r['id']))
        local_counts = Counter()
        for r in candidates:
            line = LineString(r['points_xz']); length = line.length
            malecon = 'obreg' in r['street_name'].lower()
            if length < 16:
                continue
            a,b = list(line.coords)[0],list(line.coords)[-1]
            dx,dz = (b[0]-a[0])/length,(b[1]-a[1])/length
            half = arcade['widths_m'][r['id']]/2
            # Stable phase along real OSM segments, never inside intersection asphalt.
            for index in range(max(1, math.ceil(length/28))):
                center = line.interpolate((index+.5)/max(1,math.ceil(length/28)), normalized=True)
                for kind, shift in [('lamp',0), ('vegetation',8), ('chair',-8)]:
                    if kind == 'chair' and not malecon:
                        continue
                    limits = {'lamp':24, 'vegetation':18, 'chair':10}
                    if local_counts[kind] >= limits[kind]:
                        continue
                    # Try both sides; promenade seats prefer the side nearest the sea.
                    sides = [1,-1]
                    if malecon:
                        sides.sort(key=lambda s: water.distance(Point(center.x-dz*(half+2)*s,center.y+dx*(half+2)*s)))
                    elif index%2:
                        sides.reverse()
                    for sign in sides:
                        offset = half+(2.2 if malecon else 1.5)
                        p = Point(center.x+dx*shift-dz*offset*sign, center.y+dz*shift+dx*offset*sign)
                        if not tile.covers(p) or not slab.covers(p.buffer(.6 if kind != 'chair' else 1.3)):
                            continue
                        radius = 3.4 if kind == 'vegetation' else 1.3 if kind == 'chair' else .6
                        if p.distance(local_buildings)<radius or local_asphalt.contains(p) or hard.intersects(p.buffer(.6)):
                            continue
                        slot = (math.floor(p.x/8), math.floor(p.y/8))
                        if any(p.distance(q)<6 for x in range(slot[0]-1,slot[0]+2) for z in range(slot[1]-1,slot[1]+2) for q in occupied.get((x,z),[])):
                            continue
                        seed = int(hashlib.sha256((r['id']+str(index)).encode()).hexdigest()[:8],16)
                        model = kind
                        if kind == 'vegetation':
                            model = ('big_palm' if seed%2 else 'palm') if malecon or seed%3 else 'tree'
                        # Source light pole spans Z; align its arms across the roadway.
                        yaw = math.atan2(-dz*sign,dx*sign) if kind == 'lamp' else math.atan2(dz*sign,-dx*sign)
                        item = {'kind':model, 'position_xz':[round(p.x,6),round(p.y,6)], 'yaw':yaw, 'osm_way_id':r['osm_way_id'], 'malecon':malecon, 'placement':'decorative_estimate_on_derived_sidewalk'}
                        transforms.append(item); counts[model]+=1; local_counts[kind]+=1
                        occupied.setdefault(slot,[]).append(p)
                        if malecon and len(samples)<20:
                            samples.append(item)
                        break
        output = {'schema_version':1, 'id':c['id'], 'triangles_xz':faces, 'edges_xz':edges, 'furniture':transforms, 'sidewalk_area_m2':slab.area}
        path = OUT/'chunks'/(c['id']+'.json.gz');write(path, output)
        chunks.append({'id':c['id'], 'file':'chunks/'+path.name, 'sha256':digest(path.relative_to(ROOT)), 'triangles':len(faces), 'furniture':len(transforms)})
    assert max_overlap < 1e-6
    assert all(digest(p)==h for p,h in before.items()), 'Input mutation'
    result = {'schema_version':1, 'sources_sha256':before, 'chunks':chunks, 'settings':{'curb_height_m':.16,'pavement_width_estimated_m':2.6,'malecon_width_estimated_m':4.2,'city_budget_lamps':24,'city_budget_vegetation':18,'city_budget_chairs':10}, 'method':'Derived from widened OSM asphalt, subtracting effective OSM/Overture buildings and protected open space. INEGI blocks are statistical reference, not sidewalk boundaries. All widths, furniture positions and model dimensions are artistic estimates. OSM footway evidence retained separately; no surveyed pavement accuracy asserted.', 'osm_sidewalk_evidence':evidence, 'explicit_median_way_ids':explicit_medians, 'medians_generated':0, 'statistics':{'chunks':len(chunks),'triangles':sum(c['triangles'] for c in chunks),'furniture':dict(counts),'max_asphalt_overlap_m2':max_overlap,'input_hashes_verified':len(before)}, 'malecon_samples':samples}
    write(OUT/'manifest.json',result)
    print(json.dumps(result['statistics']),flush=True)


if __name__ == '__main__':
    build()

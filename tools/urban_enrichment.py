"""B.6 enrichment of existing geometry; offline, deterministic, source preserving."""
import json, math, unicodedata
from pathlib import Path
import xml.etree.ElementTree as ET
from collections import Counter
from shapely.geometry import Point, Polygon
from shapely.strtree import STRtree
from fetch_urban_sources import ROOT, digest


def read(path):
    return json.loads(path.read_text(encoding='utf-8-sig'))


def category(tags):
    amenity = tags.get('amenity', '')
    tourism = tags.get('tourism', '')
    building = tags.get('building', '')
    if amenity in ('restaurant', 'cafe', 'fast_food', 'bar', 'pub'): return 'restaurant'
    if tourism in ('hotel', 'motel', 'hostel', 'guest_house') or building == 'hotel': return 'hotel'
    if amenity in ('school', 'university', 'college', 'hospital', 'clinic', 'police', 'townhall', 'post_office', 'library') or tags.get('office') == 'government': return 'institutional'
    if tourism in ('museum', 'gallery', 'artwork') or tags.get('historic') or amenity in ('theatre', 'arts_centre', 'place_of_worship'): return 'cultural'
    if building in ('industrial', 'warehouse') or tags.get('industrial'): return 'industrial'
    if tags.get('shop') or building in ('commercial', 'retail') or amenity in ('bank', 'marketplace', 'fuel'): return 'commercial'
    if building in ('house', 'residential', 'apartments', 'detached', 'terrace'): return 'residential'
    return 'unknown'


def associate(point, polygons, tree, limit=8, margin=3):
    candidates = sorted((point.distance(polygons[int(i)]), int(i)) for i in tree.query(point.buffer(limit)))
    candidates = [(d, i) for d, i in candidates if d <= limit]
    if not candidates: return None, 0.0, 'no nearby building', []
    inside = [i for d, i in candidates if polygons[i].covers(point)]
    if len(inside) == 1: return inside[0], 0.95, 'unique containment', candidates
    if len(inside) > 1: return None, 0.0, 'ambiguous containment', candidates
    if len(candidates) > 1 and candidates[1][0] - candidates[0][0] < margin:
        return None, 0.0, 'ambiguous proximity', candidates
    # Proximity alone is insufficient evidence for an automatic assignment.
    return None, 0.4, 'proximity requires review', candidates


def enrich(buildings, project, cfg, source):
    settings = read(ROOT/'config/urban_enrichment.json')
    overrides = read(ROOT/'config/urban_overrides.json')
    xml = ROOT/'data/raw'/source['original_file']
    if digest(xml) != source['original_sha256']: raise ValueError('OSM original hash mismatch')
    xml_hash = digest(xml)
    root = ET.parse(xml).getroot()
    nodes = {e.attrib['id']: (float(e.attrib['lon']), float(e.attrib['lat'])) for e in root.findall('node')}
    polys = [Polygon(b['footprint_xz'], b.get('holes_xz', [])) for b in buildings]
    tree = STRtree(polys)
    pois = []; tags_by_way = {}
    south, west, north, east = cfg['bbox']
    for elem in root:
        tags = {t.attrib['k']: t.attrib['v'] for t in elem.findall('tag')}
        if elem.tag == 'way': tags_by_way[elem.attrib['id']] = tags
        if not tags.get('name') or not any(k in tags for k in ('amenity','shop','tourism','historic','office')): continue
        coords = []
        if elem.tag == 'node': coords = [nodes[elem.attrib['id']]]
        elif elem.tag == 'way': coords = [nodes[n.attrib['ref']] for n in elem.findall('nd') if n.attrib['ref'] in nodes]
        if not coords: continue
        if len(coords) >= 4 and coords[0] == coords[-1]:
            polygon = Polygon(coords)
            if not polygon.is_valid: continue
            lon, lat = polygon.representative_point().coords[0]
        elif len(coords) == 1: lon, lat = coords[0]
        else: continue
        if not (west <= lon <= east and south <= lat <= north): continue
        x, z = project(lon, lat)
        idx, confidence, reason, candidates = associate(Point(x,z), polys, tree, settings['association_max_distance_m'], settings['ambiguity_margin_m'])
        name = ' '.join(tags['name'].split())
        pois.append({'id':f"osm:{elem.tag}:{elem.attrib['id']}",'name':name,'normalized_name':unicodedata.normalize('NFKC',name).casefold(),'category':category(tags),'lon':lon,'lat':lat,'position_xz':[x,z],'position_method':'source node' if elem.tag=='node' else 'polygon representative point','tags':tags,'building_id':buildings[idx]['id'] if idx is not None else None,'confidence':confidence,'association_reason':reason,'needs_review':idx is None,'candidates':[{'building_id':buildings[i]['id'],'distance_m':round(d,3)} for d,i in candidates],'source':{'file':xml.name,'sha256':xml_hash,'license':'ODbL-1.0'}})
    pois.sort(key=lambda p:p['id'])
    duplicates=[]
    for i,p in enumerate(pois):
        for q in pois[:i]:
            if p['normalized_name']==q['normalized_name'] and math.dist(p['position_xz'],q['position_xz'])<20:
                duplicates.append([q['id'],p['id']]); p['possible_duplicate_of']=q['id']
    by_id={b['id']:b for b in buildings}; poi_ids={p['id'] for p in pois}; orphan=[]
    for identifier, value in overrides.get('pois',{}).items():
        if not value.get('reason') or not value.get('source'): raise ValueError('Override requires reason and source')
        if identifier not in poi_ids: orphan.append(identifier); continue
        target=value.get('building_id')
        if target is not None and target not in by_id: orphan.append(identifier+' -> '+target); continue
        p=next(p for p in pois if p['id']==identifier)
        p.update(building_id=target,confidence=1.0,association_reason='manual override',needs_review=False,override=value)
    for b in buildings:
        tags=tags_by_way.get(str(b.get('osm_way_id','')), {})
        attributes=b.get('source_attributes',{})
        source_category=category(tags)
        if source_category=='unknown': source_category=category({'building':attributes.get('class',attributes.get('subtype',''))})
        b.update(category=source_category,category_source='OSM building tags' if tags else ('Overture class/subtype' if source_category!='unknown' else 'unknown'),poi_ids=[])
    for p in pois:
        if p['building_id'] and not p.get('possible_duplicate_of'): by_id[p['building_id']]['poi_ids'].append(p['id'])
    for b in buildings:
        categories={p['category'] for p in pois if p['id'] in b['poi_ids']} - {'unknown'}
        if b['category']=='unknown' and len(categories)==1:
            b['category']=next(iter(categories)); b['category_source']='associated POI; visual rule only'
        b['mixed_use']=len(categories)>1
    allowed={'height_m','category','palette_index','disabled','priority','model_path','model_rotation_degrees','model_scale'}
    for identifier,value in overrides.get('buildings',{}).items():
        if not value.get('reason') or not value.get('source'): raise ValueError('Override requires reason and source')
        if identifier not in by_id: orphan.append(identifier); continue
        if set(value)-allowed-{'reason','source'}: raise ValueError('Unsupported override field')
        b=by_id[identifier]
        if 'height_m' in value and (not isinstance(value['height_m'],(int,float)) or not math.isfinite(value['height_m']) or not 2.8 <= value['height_m'] <= 48): raise ValueError('Invalid override height')
        if 'category' in value and value['category'] not in settings['categories']: raise ValueError('Invalid category')
        if 'model_path' in value:
            asset=value['model_path']
            if not isinstance(asset,str) or not asset.startswith('res://') or Path(asset).suffix.lower() not in ('.glb','.tscn'): raise ValueError('Model must be a local glb or tscn')
            model=(ROOT/asset[6:]).resolve()
            if not model.is_relative_to(ROOT.resolve()) or not model.is_file(): raise ValueError('Missing model or model outside project')
        for field in ('model_rotation_degrees','model_scale'):
            if field in value and (not isinstance(value[field],(int,float)) or not math.isfinite(value[field])): raise ValueError('Invalid model transform')
        if 'model_scale' in value and not 0 < value['model_scale'] <= 10: raise ValueError('Invalid model scale')
        if 'palette_index' in value and (type(value['palette_index']) is not int or not 0 <= value['palette_index'] < 6): raise ValueError('Invalid palette')
        if 'disabled' in value and type(value['disabled']) is not bool: raise ValueError('disabled must be boolean')
        b['automatic_height_m']=b['height_m']
        b.update({k:v for k,v in value.items() if k in allowed}); b['override']=value
        if 'height_m' in value: b.update(height_source='manual override',height_estimated=True)
    return {'schema_version':1,'source':source,'pois':pois,'possible_duplicates':duplicates,'orphan_overrides':orphan,'statistics':{'pois':len(pois),'associated':sum(p['building_id'] is not None for p in pois),'unassociated':sum(p['building_id'] is None for p in pois),'duplicate_candidates':len(duplicates),'categories':dict(Counter(b['category'] for b in buildings))},'association_policy':'unique containment 0.95; proximity <=8m review only; competing distance margin 3m; no fuzzy-name merging'}

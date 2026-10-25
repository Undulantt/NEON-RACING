"""B.6 enrichment of existing geometry; offline, deterministic, source preserving."""
import json, math, unicodedata
from pathlib import Path
import xml.etree.ElementTree as ET
from collections import Counter
from shapely.geometry import Point, Polygon, LineString
from shapely.strtree import STRtree
from fetch_urban_sources import ROOT, digest
from poi_sources import read_external, normalized_name


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
    external,source_meta,source_exclusions=read_external(cfg,settings)
    for p in external:
        x,z=project(p['lon'],p['lat'])
        idx,confidence,reason,candidates=associate(Point(x,z),polys,tree,settings['association_max_distance_m'],settings['ambiguity_margin_m'])
        if not p['eligible_for_classification']:
            idx=None; confidence=0.0; reason='source confidence/status requires review'
        p.update(position_xz=[x,z],position_method='source point',normalized_name=normalized_name(p['name']),building_id=buildings[idx]['id'] if idx is not None else None,confidence=confidence,association_reason=reason,needs_review=idx is None,candidates=[{'building_id':buildings[i]['id'],'distance_m':round(d,3)} for d,i in candidates])
        pois.append(p)
    pois.sort(key=lambda p:p['id'])
    lookup={b['id']:b for b in buildings}
    for p in pois:
        p['normalized_name']=normalized_name(p['name'])
        p.setdefault('eligible_for_classification',True)
        p.setdefault('source_existence_confidence',None)
        if p['building_id'] and lookup[p['building_id']].get('fictional'):
            p.update(building_id=None,confidence=0.0,association_reason='fictional footprint is not geographic evidence',needs_review=True)
    # Candidate detection only: no arbitrary suppression/merging, no source voting.
    duplicates=[]
    point_geometries=[Point(p['position_xz']) for p in pois]
    point_tree=STRtree(point_geometries)
    for i,p in enumerate(pois):
        for j in sorted(int(j) for j in point_tree.query(point_geometries[i].buffer(20)) if int(j)<i):
            q=pois[j]
            if p['normalized_name']==q['normalized_name'] and point_geometries[i].distance(point_geometries[j])<=20:
                duplicates.append([q['id'],p['id']])
                p.setdefault('duplicate_candidate_ids',[]).append(q['id'])
                q.setdefault('duplicate_candidate_ids',[]).append(p['id'])
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
        if p['building_id'] and p['eligible_for_classification']: by_id[p['building_id']]['poi_ids'].append(p['id'])
    poi_lookup={p['id']:p for p in pois}
    for b in buildings:
        categories={poi_lookup[pid]['category'] for pid in b['poi_ids']} - {'unknown'}
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
    road_data=read(ROOT/'data/processed/la_paz_map.json')
    streets=[LineString(r['points_xz']) for r in road_data['roads']]
    street_tree=STRtree(streets)
    for b in buildings:
        if b['category']=='unknown': continue
        ring=b['footprint_xz']; candidates=[]
        for index,(a,z) in enumerate(zip(ring,ring[1:]+ring[:1])):
            edge=LineString([a,z])
            if edge.length<3: continue
            midpoint=edge.interpolate(0.5,normalized=True)
            near=streets[int(street_tree.nearest(midpoint))]
            candidates.append((edge.distance(near),-edge.length,index))
        if candidates:
            b['facade_edge_index']=min(candidates)[2]
            b['facade_orientation_source']='nearest existing road centerline; not a surveyed entrance'
    return {'schema_version':1,'source':source,'additional_sources':source_meta,'source_exclusions':source_exclusions,'pois':pois,'possible_duplicates':duplicates,'orphan_overrides':orphan,'statistics':{'pois':len(pois),'records_by_source':dict(Counter(p['id'].split(':')[0] for p in pois)),'classification_ineligible':sum(not p['eligible_for_classification'] for p in pois),'associated':sum(p['building_id'] is not None for p in pois),'unassociated':sum(p['building_id'] is None for p in pois),'duplicate_candidates':len(duplicates),'categories':dict(Counter(b['category'] for b in buildings))},'association_policy':'unique containment 0.95; proximity <=8m review only; competing distance margin 3m; no fuzzy-name merging'}

"""B.5 deterministic Overture/OSM buildings + conservative INEGI fictional infill.

Original snapshots remain immutable. No road or vehicle source is modified.
"""
from expansion_regions import metric_region
import argparse,hashlib,json,math,random,unicodedata
from collections import Counter,defaultdict
from pathlib import Path
from shapely.geometry import Polygon,MultiPolygon,LineString,Point,box,shape,mapping
from shapely.geometry.polygon import orient
from shapely.ops import transform,unary_union,polygonize
from shapely.affinity import rotate
from shapely import constrained_delaunay_triangles
from shapely.strtree import STRtree
from shapely.prepared import prep
from pyproj import Transformer
from fetch_urban_sources import ROOT,cached,digest,load_json


def clean_text(value):
    return ''.join(c for c in unicodedata.normalize('NFD',str(value).lower()) if unicodedata.category(c)!='Mn')

def parts(geom):
    if geom.geom_type=='Polygon': return [geom]
    return [g for g in getattr(geom,'geoms',[]) if g.geom_type=='Polygon']

def projector(cfg):
    sx=6371000*math.pi/180*math.cos(math.radians(cfg['origin_lat'])); sz=-6371000*math.pi/180
    def project(x,y,z=None):
        if hasattr(x,'__iter__'):
            return ([(v-cfg['origin_lon'])*sx for v in x],[(v-cfg['origin_lat'])*sz for v in y])
        return ((x-cfg['origin_lon'])*sx,(y-cfg['origin_lat'])*sz)
    return project

def protected_shapes(raw,project):
    results=[]; coast=[]
    for elem in raw['elements']:
        tags=elem.get('tags',{}); geom=None
        if elem['type']=='way':
            coords=[(p['lon'],p['lat']) for p in elem.get('geometry',[]) if 'lon' in p]
            if len(coords)<2: continue
            line=transform(project,LineString(coords))
            if tags.get('natural')=='coastline': coast.append(line); continue
            if len(coords)>=4 and coords[0]==coords[-1] and tags.get('area')!='no': geom=transform(project,Polygon(coords))
            else: geom=line.buffer(2.0)
        elif elem['type']=='relation':
            outer=[]; inner=[]
            for member in elem.get('members',[]):
                coords=[(p['lon'],p['lat']) for p in member.get('geometry',[]) if 'lon' in p]
                if len(coords)>1: (inner if member.get('role')=='inner' else outer).append(LineString(coords))
            if outer:
                geom=unary_union(list(polygonize(unary_union(outer))))
                if inner: geom=geom.difference(unary_union(list(polygonize(unary_union(inner)))))
                geom=transform(project,geom)
        elif elem['type']=='node' and 'lat' in elem:
            # A protected POI without a boundary does not define its extent.
            # Conservative local no-fill buffer; explicit in audit.
            geom=transform(project,Point(elem['lon'],elem['lat'])).buffer(25)
        if geom is not None and not geom.is_empty and geom.is_valid:
            results.append((str(elem['type'])+':'+str(elem['id']),geom,tags))
    return results,coast

def encode_building(identifier,kind,poly,height,extra,roads,cfg):
    poly=orient(poly,sign=1.0)
    key=int(hashlib.sha256(identifier.encode()).hexdigest()[:12],16)
    return {'id':identifier,'source_kind':kind,'fictional':kind=='fictional','footprint_xz':[list(p) for p in list(poly.exterior.coords)[:-1]],'holes_xz':[[list(p) for p in list(r.coords)[:-1]] for r in poly.interiors],
        'roof_triangles_xz':[[list(p) for p in list(t.exterior.coords)[:3]] for t in constrained_delaunay_triangles(poly).geoms if t.area>1e-6],
        'height_m':height,'palette_index':key%6,'collision_enabled':roads(poly) if callable(roads) else poly.distance(roads)<=cfg['fill_road_distance_m'],**extra}

def build():
    cfg=load_json(ROOT/'config/map_config.json'); settings=load_json(ROOT/'config/urban_config.json'); source_map=ROOT/'data/processed/la_paz_map.json'; data=load_json(source_map); baseline=load_json(ROOT/'data/processed/la_paz_environment.json')
    from urban_enrichment import read
    floor_height=read(ROOT/'config/urban_enrichment.json')['estimated_floor_height_m']
    if not isinstance(floor_height,(int,float)) or not math.isfinite(floor_height) or not 2.8 <= floor_height <= 5: raise ValueError('Invalid estimated floor height')
    inputs={}
    for kind in ['overture_buildings','inegi_blocks','osm_protected']:
        found=cached(kind,cfg['bbox'],release=settings['overture_release'] if kind=='overture_buildings' else None,url=settings['inegi_url'] if kind=='inegi_blocks' else None)
        if not found: raise SystemExit(f'Missing verified source {kind}; run fetch_urban_sources.py. No fictional fallback.')
        inputs[kind]=found
    print("URBAN: verified source snapshots",flush=True)
    project=projector(cfg); south,west,north,east=cfg['bbox']; region=metric_region(cfg)
    road_parts=[unary_union([Polygon([(p[0]+c['origin_xz'][0],p[1]+c['origin_xz'][1]) for p in tri]) for tri in c['triangles_xz']]) for c in data['chunks']]
    road_surface=unary_union(road_parts)
    road_tree=STRtree(road_parts)
    def close_to_road(poly):
        limit=settings['fill_road_distance_m']
        return any(poly.distance(road_parts[int(i)]) <= limit for i in road_tree.query(poly.buffer(limit).envelope))
    road_mask=road_surface.buffer(settings['road_clearance_m'])
    # Exact spatial partition of the unioned mask. Each building uses only the
    # intersecting pieces; never approximate widths or trim against remote roads.
    x0,z0,x1,z1=road_mask.bounds
    mask_tiles=[]
    for x in range(math.floor(x0/256),math.floor(x1/256)+1):
        for z in range(math.floor(z0/256),math.floor(z1/256)+1):
            tile=road_mask.intersection(box(x*256,z*256,(x+1)*256,(z+1)*256))
            if not tile.is_empty: mask_tiles.append(tile)
    mask_tree=STRtree(mask_tiles)
    def local_mask(geometry):
        return unary_union([mask_tiles[int(i)] for i in mask_tree.query(geometry)])
    print("URBAN: indexed exact road mask",len(mask_tiles),flush=True)
    protected,coast=protected_shapes(load_json(inputs['osm_protected'][0]),project)
    protected_union=unary_union([g for _,g,_ in protected])
    protected_prepared=prep(protected_union)
    region_prepared=prep(region)
    # Additional coast guard for fictional fill only. Real buildings still require
    # geometric exclusion of mapped parks/beaches/water.
    obregon=unary_union([LineString(r['points_xz']) for r in data['roads'] if 'obreg' in r['street_name'].lower()])
    coast_guard=unary_union([g.buffer(100) for g in coast]+[obregon.buffer(50)])
    audit=[]; buildings=[]; geometries=[]; grid=defaultdict(list)
    def cells(poly):
        a,b,c,d=poly.bounds
        return [(x,z) for x in range(math.floor(a/64),math.floor(c/64)+1) for z in range(math.floor(b/64),math.floor(d/64)+1)]
    def nearby(poly): return sorted({i for cell in cells(poly) for i in grid[cell]})
    def add_record(record,poly):
        idx=len(geometries); geometries.append(poly); buildings.append(record)
        for cell in cells(poly): grid[cell].append(idx)
    def accept_real(identifier,kind,original,props):
        if not original.is_valid or original.is_empty:
            audit.append({'id':identifier,'reason':'invalid geometry'}); return
        if not region_prepared.covers(original):
            audit.append({'id':identifier,'reason':'outside bbox; no partial landmark'}); return
        if original.area<settings['real_min_area_m2'] or original.area>settings['real_max_area_m2']:
            audit.append({'id':identifier,'reason':'size outside prototype limits'}); return
        if protected_prepared.intersects(original):
            audit.append({'id':identifier,'reason':'mapped protected/open space'}); return
        candidate=original.simplify(0.12,preserve_topology=True).difference(local_mask(original))
        overlap=unary_union([geometries[i] for i in nearby(candidate)] if not candidate.is_empty else [])
        if not overlap.is_empty:
            if candidate.intersection(overlap).area/max(0.01,min(candidate.area,overlap.area))>0.25:
                audit.append({'id':identifier,'reason':'duplicate/overlapping prior building'}); return
            candidate=candidate.difference(overlap.buffer(0.15))
        if candidate.is_empty or candidate.area/original.area<0.85:
            audit.append({'id':identifier,'reason':'road/duplicate conflict removes more than 15 percent'}); return
        observed_height=props.get('height'); floors=props.get('num_floors')
        if not isinstance(observed_height,(float,int)) or not math.isfinite(observed_height) or observed_height<=0: observed_height=None
        if not isinstance(floors,(float,int)) or not math.isfinite(floors) or floors<=0: floors=None
        key=int(hashlib.sha256(identifier.encode()).hexdigest()[:8],16)
        height=observed_height or (floors*floor_height if floors else (1+key%3)*floor_height)
        height=max(2.8,min(48,height))
        for index,p in enumerate(parts(candidate)):
            if p.area<settings['real_min_area_m2']: continue
            extra={'source_id':props.get('source_id',identifier),'height_m_source':observed_height,'num_floors_source':floors,'height_estimated':observed_height is None,'height_source':'source:height' if observed_height else (f'estimated:num_floors*{floor_height}' if floors else 'estimated:deterministic_1_to_3_floors'),'height_stylized':bool(observed_height and abs(height-observed_height)>0.01),'original_area_m2':original.area,'retained_fraction':candidate.area/original.area,'geometry_adjusted':original.symmetric_difference(candidate).area>0.01,'geometry_simplification_m':0.12,'sources':props.get('sources',[]),'source_attributes':{k:props[k] for k in ('class','subtype','names','level','num_floors') if props.get(k) is not None}}
            if kind=='osm': extra['osm_way_id']=props['source_id']
            add_record(encode_building(identifier+':'+str(index),kind,p,height,extra,close_to_road,settings),p)
    # Existing verified OSM footprints have priority over overlapping inferred ML.
    for b in baseline['buildings']:
        tags=b['osm_tags']; h=tags.get('height'); levels=tags.get('building:levels')
        try: h=float(str(h).replace(' m',''))
        except (ValueError,TypeError): h=None
        try: levels=float(levels)
        except (ValueError,TypeError): levels=None
        accept_real('osm:'+b['osm_way_id'],'osm',Polygon(b['footprint_xz']),{'height':h,'num_floors':levels,'source_id':b['osm_way_id'],'sources':[{'dataset':'OpenStreetMap'}]})
    overture=load_json(inputs['overture_buildings'][0])
    for feature_index,feature in enumerate(sorted(overture['features'],key=lambda f:f.get('id',f['properties'].get('id','')))):
        if feature_index % 10000 == 0: print('URBAN: Overture',feature_index,'/',len(overture['features']),flush=True)
        props=feature['properties']; identifier=str(feature.get('id',props.get('id')))
        if props.get('is_underground'):
            audit.append({'id':identifier,'reason':'underground'}); continue
        for i,p in enumerate(parts(transform(project,shape(feature['geometry'])))):
            accept_real('overture:'+identifier+':'+str(i),'overture',p,{**props,'source_id':identifier})
    print(f"URBAN: accepted {len(buildings)} real volumes",flush=True)
    real_count=len(buildings)
    raw_blocks=load_json(inputs['inegi_blocks'][0]); normalized=[]; block_audit=[]; eligible=[]; rejected=[]
    crs_ops={}; transformers={}
    for feature in raw_blocks['features']:
        geom=feature['geometry']; props=feature['properties']; code=props['cvegeo']
        crs_name=geom.get('crs',raw_blocks.get('crs',{})).get('properties',{}).get('name')
        if not crs_name: raise ValueError('INEGI CRS is missing; cannot assume WGS84')
        if crs_name not in transformers: transformers[crs_name]=Transformer.from_crs(crs_name,'EPSG:4326',always_xy=True)
        transformer=transformers[crs_name]
        crs_ops[crs_name]={'operation':transformer.description,'accuracy_m':transformer.accuracy,'always_xy':True}
        geometry=transform(project,transform(transformer.transform,shape(geom)))
        if geometry.is_empty or not geometry.is_valid or not geometry.intersects(region): continue
        record={'id':code,'type':props.get('tipomza'),'properties':props,'geometry_xz':mapping(geometry),'source_crs':crs_name}
        normalized.append(record)
        reason=''
        typical=clean_text(props.get('tipomza'))=='tipica'
        if not typical: reason='not a typical urban block'
        elif not region.covers(geometry): reason='border block'
        elif geometry.area<300 or geometry.area>40000: reason='atypical area'
        elif geometry.intersects(protected_union) or geometry.intersects(coast_guard): reason='open/protected/coastal guard'
        else:
            local_real=unary_union([geometries[i] for i in nearby(geometry)])
            coverage=geometry.intersection(local_real).area/geometry.area
            try: inhabitants=int(props.get('total_viviendas_habitadas') or 0)
            except ValueError: inhabitants=0
            if coverage<settings['fill_min_block_coverage'] or inhabitants<=0: reason='insufficient occupied-building and inhabited-dwelling evidence'
        if reason:
            block_audit.append({'id':code,'reason':reason}); rejected.append(geometry); continue
        safe=geometry.buffer(-5).difference(local_mask(geometry)).difference(protected_union).difference(coast_guard).difference(local_real.buffer(2))
        if safe.is_empty: block_audit.append({'id':code,'reason':'no safe residual area'}); continue
        eligible.append({'id':code,'geometry_xz':mapping(geometry),'safe_geometry_xz':mapping(safe),'real_coverage':coverage,'inhabited_dwellings':inhabitants})
    print(f"URBAN: {len(normalized)} local blocks, {len(eligible)} eligible",flush=True)
    fill_total=0
    for fill_index,entry in enumerate(sorted(eligible,key=lambda b:b['id'])):
        if fill_index % 250 == 0: print('URBAN: infill blocks',fill_index,'/',len(eligible),'volumes',fill_total,flush=True)
        code=entry['id']; safe=shape(entry['safe_geometry_xz']); whole=shape(entry['geometry_xz']); rng=random.Random(f"{settings['fill_seed']}:{code}")
        rect=list(whole.minimum_rotated_rectangle.exterior.coords); edges=[(a,b) for a,b in zip(rect,rect[1:])]; a,b=max(edges,key=lambda e:math.dist(*e)); angle=math.degrees(math.atan2(b[1]-a[1],b[0]-a[0]))
        x0,z0,x1,z1=safe.bounds; count=0
        for x in range(math.floor(x0/settings['fill_spacing_m']),math.ceil(x1/settings['fill_spacing_m'])):
            for z in range(math.floor(z0/settings['fill_spacing_m']),math.ceil(z1/settings['fill_spacing_m'])):
                cx=(x+0.5)*settings['fill_spacing_m']; cz=(z+0.5)*settings['fill_spacing_m']; w=rng.uniform(8,12); depth=rng.uniform(10,16)
                poly=rotate(box(cx-w/2,cz-depth/2,cx+w/2,cz+depth/2),angle,origin=(cx,cz))
                if not safe.covers(poly) or not close_to_road(poly): continue
                if any(poly.distance(geometries[i])<2 for i in nearby(poly)): continue
                ident=f'fiction:inegi:{code}:{x}:{z}'; height=floor_height*rng.randint(1,3)
                extra={'inegi_block_id':code,'height_estimated':True,'height_source':'fictional:seeded_1_to_3_floors','height_stylized':False,'source_note':'Fictional footprint; INEGI block is only a placement constraint, not a building source'}
                add_record(encode_building(ident,'fictional',poly,height,extra,close_to_road,settings),poly); count+=1; fill_total+=1
                if count>=settings['fill_max_per_block'] or fill_total>=settings['fill_max_total']: break
            if count>=settings['fill_max_per_block'] or fill_total>=settings['fill_max_total']: break
        if fill_total>=settings['fill_max_total']: break
    print('URBAN: infill complete',fill_total,flush=True)
    from urban_enrichment import enrich
    enrichment=enrich(buildings,project,cfg,inputs['osm_protected'][1])
    target=ROOT/'data/processed/urban'; target.mkdir(parents=True,exist_ok=True); chunk_dir=target/'chunks'; chunk_dir.mkdir(exist_ok=True)
    print('URBAN: enrichment complete',flush=True)
    from urban_geography import surfaces, landmarks, mapped_area_ids
    visual_region=metric_region({**cfg,"active_blocks":{"visual_envelope":cfg["bbox"]}})
    geography=surfaces(visual_region,coast,protected,buildings,road_surface,mapped_area_ids(load_json(inputs['osm_protected'][0])))
    print('URBAN: geography complete',flush=True)
    (target/'urban_geography.json').write_text(json.dumps(geography,ensure_ascii=False,separators=(',',':')),encoding='utf-8')
    (target/'landmarks.json').write_text(json.dumps(landmarks(enrichment),ensure_ascii=False,indent=2),encoding='utf-8')
    (target/'urban_enrichment.json').write_text(json.dumps(enrichment,ensure_ascii=False,indent=2),encoding='utf-8')
    groups=defaultdict(list); size=settings['chunk_size_m']
    for building,poly in zip(buildings,geometries):
        cx,cz=poly.centroid.coords[0]; key=(math.floor(cx/size),math.floor(cz/size)); groups[key].append(building)
    chunks=[]
    for (x,z),group in sorted(groups.items()):
        identifier=f'{x}_{z}'; p=chunk_dir/f'{identifier}.json'; p.write_text(json.dumps({'schema_version':1,'id':identifier,'chunk_cell':[x,z],'detail_windows':False,'category_facades':True,'buildings':group},ensure_ascii=False,separators=(',',':'),allow_nan=False),encoding='utf-8')
        a,b,c,d=unary_union([Polygon(r['footprint_xz'],r['holes_xz']) for r in group]).bounds
        chunks.append({'id':identifier,'file':f'chunks/{identifier}.json','sha256':digest(p),'bounds_xz':[a,b,c,d],'building_count':len(group),'collision_count':sum(r['collision_enabled'] for r in group)})
    exclusions={'schema_version':1,'protected':[{'id':identifier,'geometry_xz':mapping(g),'tags':tags} for identifier,g,tags in protected],'coast_guard_xz':mapping(coast_guard),'blocks':normalized,'eligible_blocks':eligible,'excluded_blocks':block_audit,'excluded_buildings':audit,'inegi_crs_operations':crs_ops}
    p=target/'placement_audit.json'; p.write_text(json.dumps(exclusions,ensure_ascii=False,separators=(',',':'),allow_nan=False),encoding='utf-8')
    manifest={'schema_version':1,'map_sha256':digest(source_map),'units':'meters','origin_lat':cfg['origin_lat'],'origin_lon':cfg['origin_lon'],'bbox':cfg['bbox'],'metadata':{'sources':{k:v[1] for k,v in inputs.items()},'license':'ODbL-1.0 for derived OSM/Overture database; INEGI terms retained separately','height_note':'Observed height where provided; otherwise explicitly estimated from floors or deterministic low-rise fallback','fictional_note':'Only footprints with source_kind=fictional are invented; never attributed to Overture or INEGI','inegi_metadata':raw_blocks.get('metadatos'),'crs_operations':crs_ops},'settings':settings,'chunks':chunks,'audit_file':'placement_audit.json','audit_sha256':digest(p),'statistics':{'overture_downloaded':len(overture['features']),'source_counts':dict(Counter(b['source_kind'] for b in buildings)),'buildings':len(buildings),'real_buildings':real_count,'fictional_buildings':fill_total,'height_estimated':sum(b['height_estimated'] for b in buildings),'collision_buildings':sum(b['collision_enabled'] for b in buildings),'chunks':len(chunks),'protected_features':len(protected),'inegi_blocks_in_bbox':len(normalized),'eligible_infill_blocks':len(eligible),'excluded_buildings':len(audit)},'baseline_hashes':{str(p.relative_to(ROOT)):digest(p) for p in [ROOT/'scripts/driving/ArcadeCar.gd',ROOT/'config/driving_config.json',source_map,ROOT/'data/processed/la_paz_environment.json']}}
    manifest['enrichment_statistics']=enrichment['statistics']
    manifest['b6_files']={name:digest(target/name) for name in ['urban_enrichment.json','urban_geography.json','landmarks.json']}
    (target/'city_manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2,allow_nan=False),encoding='utf-8')
    print(json.dumps(manifest['statistics'],indent=2)); return manifest
if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__); parser.add_argument('--check-determinism',action='store_true'); args=parser.parse_args()
    manifest=ROOT/'data/processed/urban/city_manifest.json'; before=digest(manifest) if manifest.exists() else None
    result=build()
    if args.check_determinism:
        if before is None or before!=digest(manifest): raise SystemExit('Determinism comparison failed: city manifest or its content hashes changed')
        print('DETERMINISTIC: manifest, chunk hashes and audit unchanged')


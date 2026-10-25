"""Schema-checked, offline readers for pinned Overture Places and INEGI DENUE."""
import csv, io, json, math, re, unicodedata, zipfile
from collections import Counter
from fetch_urban_sources import ROOT, digest, load_json

DENUE_FIELDS={'id','clee','nom_estab','codigo_act','nombre_act','latitud','longitud','nom_vial','numero_ext'}

def normalized_name(value):
    text=unicodedata.normalize('NFKD',str(value)).casefold()
    return ' '.join(re.sub(r'[^\w\s]',' ',''.join(c for c in text if not unicodedata.combining(c))).split())

def overture_category(props):
    taxonomy=props.get('taxonomy') or {}
    hierarchy=taxonomy.get('hierarchy') or []
    labels=set(hierarchy+[taxonomy.get('primary',''),props.get('basic_category','')])
    if 'lodging' in labels: return 'hotel'
    if 'food_and_drink' in labels: return 'restaurant'
    if labels.intersection({'education','health_care','community_and_government'}): return 'institutional'
    if labels.intersection({'cultural_and_historic','museum','art_gallery','theater','performing_arts_venue'}): return 'cultural'
    if labels.intersection({'factory','warehouse','manufacturing_facility'}): return 'industrial'
    if labels.intersection({'shopping','services_and_business','lifestyle_services'}): return 'commercial'
    return 'unknown'

def denue_category(code):
    code=str(code)
    if code.startswith('813210'): return 'cultural'
    if code.startswith('722'): return 'restaurant'
    if code.startswith('721'): return 'hotel'
    if code.startswith(('61','62','93')): return 'institutional'
    if code.startswith(('711','712')): return 'cultural'
    if code.startswith(('31','32','33')): return 'industrial'
    if code.startswith(('43','46','52','53','54','55','56','81')): return 'commercial'
    return 'unknown'

def denue_rows(path):
    with zipfile.ZipFile(path) as archive:
        candidates=[n for n in archive.namelist() if n.startswith('conjunto_de_datos/') and n.lower().endswith('.csv')]
        if len(candidates)!=1: raise ValueError('DENUE requires one dataset CSV')
        raw=archive.read(candidates[0])
        try: text=raw.decode('utf-8-sig'); encoding='utf-8-sig'
        except UnicodeDecodeError: text=raw.decode('cp1252'); encoding='cp1252'
        reader=csv.DictReader(io.StringIO(text,newline=''))
        if not DENUE_FIELDS.issubset(reader.fieldnames or []): raise ValueError('Unexpected DENUE CSV schema')
        return list(reader),{'member':candidates[0],'encoding':encoding,'fields':reader.fieldnames}

def read_external(cfg, settings):
    records=[]; source_meta={}; excluded=[]
    south,west,north,east=cfg['bbox']
    def inside(lon,lat): return math.isfinite(lon) and math.isfinite(lat) and west<=lon<=east and south<=lat<=north
    for kind,entry in sorted(settings.get('sources',{}).items()):
        meta=load_json(ROOT/'data/raw'/entry['metadata_file'])
        path=ROOT/'data/raw'/meta['file']
        if meta['bbox']!=cfg['bbox'] or digest(path)!=meta['sha256']: raise ValueError('POI source hash/bbox mismatch: '+kind)
        source_meta[kind]=meta
        provenance={'file':path.name,'sha256':meta['sha256'],'license':meta['license'],'kind':kind}
        if kind=='overture_places':
            data=load_json(path)
            if data.get('type')!='FeatureCollection': raise ValueError('Expected Overture FeatureCollection')
            for f in data['features']:
                p=f['properties']; ident='overture:place:'+str(f.get('id') or p.get('id',''))
                if f['geometry']['type']!='Point': raise ValueError('Overture place is not a Point')
                if 'categories' in p and not ('taxonomy' in p or 'basic_category' in p): raise ValueError('Legacy Places categories are not supported by this pinned import')
                name=(p.get('names') or {}).get('primary',''); lon,lat=f['geometry']['coordinates'][:2]
                if not inside(lon,lat) or not name: excluded.append({'id':ident,'reason':'outside bbox or missing name'}); continue
                confidence=p.get('confidence')
                if confidence is not None and (not isinstance(confidence,(int,float)) or not math.isfinite(confidence) or not 0<=confidence<=1): raise ValueError('Invalid source confidence')
                eligible=confidence is not None and confidence>=settings.get('overture_min_confidence',0.6) and p.get('operating_status') not in ('permanently_closed','temporarily_closed')
                records.append({'id':ident,'name':name,'lon':lon,'lat':lat,'category':overture_category(p),'eligible_for_classification':eligible,'source_existence_confidence':confidence,'operating_status':p.get('operating_status','not supplied'),'source_attributes':{'basic_category':p.get('basic_category'),'taxonomy':p.get('taxonomy'),'addresses':p.get('addresses',[]),'sources':p.get('sources',[])},'source':provenance})
        elif kind=='denue':
            rows,schema=denue_rows(path)
            for row in rows:
                ident='denue:'+row['id']
                try: lon=float(row['longitud']); lat=float(row['latitud'])
                except (TypeError,ValueError): excluded.append({'id':ident,'reason':'invalid coordinates'}); continue
                if not inside(lon,lat): continue
                name=row['nom_estab'].strip()
                if not name: excluded.append({'id':ident,'reason':'missing establishment name'}); continue
                records.append({'id':ident,'name':name,'lon':lon,'lat':lat,'category':denue_category(row['codigo_act']),'eligible_for_classification':True,'source_existence_confidence':None,'operating_status':'listed in DENUE snapshot; not live status','source_attributes':{k:row[k] for k in ('clee','codigo_act','nombre_act','nom_vial','numero_ext','numero_int','edificio','cod_postal','fecha_alta') if k in row},'source':{**provenance,'member':schema['member'],'encoding':schema['encoding']}})
        else: raise ValueError('Unsupported POI source '+kind)
    ids=[r['id'] for r in records]
    if len(set(ids))!=len(ids): raise ValueError('Duplicate stable source ID')
    return records,source_meta,excluded

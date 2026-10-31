"""Download separate verifiable urban sources. Nothing is downloaded by Godot."""
import argparse,hashlib,json,subprocess,sys,urllib.request,urllib.parse
import xml.etree.ElementTree as ET
from datetime import datetime,timezone
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]

def load_json(path): return json.loads(path.read_text(encoding='utf-8'))
def digest(path): return hashlib.sha256(path.read_bytes()).hexdigest()
def cached(kind,bbox,release=None,url=None):
    for mp in sorted((ROOT/'data/raw').glob(kind+'_*.meta.json'),reverse=True):
        meta=load_json(mp); p=mp.with_name(meta['file'])
        compatible=(release is None or meta.get('release')==release) and (url is None or meta.get('url')==url)
        original_ok=not meta.get('original_file') or ((mp.parent/meta['original_file']).exists() and digest(mp.parent/meta['original_file'])==meta.get('original_sha256'))
        if compatible and original_ok and meta.get('selection_bbox',meta.get('bbox'))==bbox and p.exists() and digest(p)==meta.get('sha256'):
            return p,meta
    return None

def save_meta(path,kind,bbox,extra):
    meta={'kind':kind,'file':path.name,'bbox':bbox,'sha256':digest(path),'extracted_at_utc':datetime.now(timezone.utc).isoformat(),**extra}
    path.with_suffix('.meta.json').write_text(json.dumps(meta,ensure_ascii=False,indent=2),encoding='utf-8')
    print('VERIFIED',kind,path.name,path.stat().st_size,'bytes',flush=True)
    return meta

def request(url,data=None):
    req=urllib.request.Request(url,data=data,headers={'User-Agent':'LaPazUrbanPrototype/0.5 (small offline geographic extract)'})
    with urllib.request.urlopen(req,timeout=150) as response: return response.read()

def main():
    ap=argparse.ArgumentParser(description=__doc__); ap.add_argument('source',choices=['overture','inegi','protected','places','denue']); ap.add_argument('--refresh',action='store_true'); args=ap.parse_args()
    if args.source in ('places','denue'):
        from fetch_poi_sources import fetch
        fetch(args.source,args.refresh); return
    cfg=load_json(ROOT/'config/map_config.json'); urban=load_json(ROOT/'config/urban_config.json'); bbox=cfg['bbox']; kind={'overture':'overture_buildings','inegi':'inegi_blocks','protected':'osm_protected'}[args.source]
    found=cached(kind,bbox,release=urban["overture_release"] if args.source=="overture" else None,url=urban["inegi_url"] if args.source=="inegi" else None)
    if found and not args.refresh:
        print('CACHE VERIFIED',found[0]); return
    stamp=datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ'); path=ROOT/'data/raw'/f'{kind}_{stamp}.geojson'
    if args.source=='overture':
        south,west,north,east=bbox
        cmd=[sys.executable,'-m','overturemaps','download',f'--bbox={west},{south},{east},{north}','-f','geojson','--type=building','--release',urban['overture_release'],'--connect_timeout','30','--request_timeout','120','-o',str(path)]
        subprocess.run(cmd,check=True,timeout=600)
        parsed=load_json(path)
        if not parsed.get('features'): raise SystemExit('Overture returned no building footprints. No fabricated replacement.')
        save_meta(path,kind,bbox,{'source':'Overture Maps Foundation','release':urban['overture_release'],'license':'ODbL-1.0','command':cmd[1:],'url':f'https://stac.overturemaps.org/{urban["overture_release"]}/catalog.json','feature_count':len(parsed['features'])})
    elif args.source=='inegi':
        raw=request(urban['inegi_url']); parsed=json.loads(raw)
        if parsed.get('type')!='FeatureCollection' or not parsed.get('features'): raise SystemExit('INEGI returned no valid block geometries; fictional filling must remain disabled.')
        path.write_bytes(raw)
        save_meta(path,kind,bbox,{'source':'INEGI Marco Geoestadistico / Catalogo Unico','url':urban['inegi_url'],'locality_code':urban['inegi_locality_code'],'license_url':'https://www.inegi.org.mx/inegi/terminos.html','feature_count':len(parsed['features']),'scope':'Full locality, subset clipped offline; source publication date not asserted'})
    else:
        south,west,north,east=bbox; b=f'{south-0.002},{west-0.002},{north+0.002},{east+0.002}'
        filters=['["leisure"~"^(park|garden|pitch|nature_reserve|playground|golf_course|sports_centre)$"]','["natural"~"^(beach|water|wetland|sand|scrub|coastline)$"]','["landuse"~"^(forest|grass|cemetery|recreation_ground|greenfield|farmland|orchard)$"]','["amenity"~"^(parking|school|university|hospital|grave_yard)$"]','["place"="square"]','["highway"~"^(footway|path|cycleway|pedestrian|steps)$"]','["waterway"="riverbank"]']
        query='[out:json][timeout:90];('+''.join(f'nwr{f}({b});' for f in filters)+');out geom;'
        errors=[]
        for url in ['https://maps.mail.ru/osm/tools/overpass/api/interpreter']:
            try:
                raw=request(url,urllib.parse.urlencode({'data':query}).encode()); parsed=json.loads(raw)
                if parsed.get('remark') or 'elements' not in parsed: raise ValueError('Incomplete Overpass response')
                path=path.with_suffix('.json'); path.write_bytes(raw)
                save_meta(path,kind,bbox,{'source':'OpenStreetMap contributors','url':url,'license':'ODbL-1.0','query':query,'osm_base_timestamp':parsed.get('osm3s',{}).get('timestamp_osm_base'),'element_count':len(parsed['elements'])}); return
            except (OSError,ValueError) as error: errors.append(str(error)); print(url,error,flush=True)
        # Standard OSM map extract: preserve exact XML bytes and separately
        # normalize only protected tags, keeping identifiers and all coordinates.
        south,west,north,east=bbox
        url=f'https://api.openstreetmap.org/api/0.6/map?bbox={west-0.002},{south-0.002},{east+0.002},{north+0.002}'
        raw=request(url); root=ET.fromstring(raw)
        raw_path=ROOT/'data/raw'/f'osm_map_{stamp}.osm'; raw_path.write_bytes(raw)
        node_table={n.attrib['id']:n for n in root.findall('node')}
        way_table={w.attrib['id']:w for w in root.findall('way')}
        def tags(e): return {t.attrib['k']:t.attrib['v'] for t in e.findall('tag')}
        def selected(t):
            return t.get('leisure') in ('park','garden','pitch','nature_reserve','playground','golf_course','sports_centre') or t.get('natural') in ('beach','water','wetland','sand','scrub','coastline') or t.get('landuse') in ('forest','grass','cemetery','recreation_ground','greenfield','farmland','orchard') or t.get('amenity') in ('parking','school','university','hospital','grave_yard') or t.get('place')=='square' or t.get('highway') in ('footway','path','cycleway','pedestrian','steps') or t.get('waterway')=='riverbank'
        def geometry(w):
            refs=[n.attrib['ref'] for n in w.findall('nd')]
            if any(ref not in node_table for ref in refs): return []
            return [{'lat':float(node_table[ref].attrib['lat']),'lon':float(node_table[ref].attrib['lon'])} for ref in refs]
        elements=[]; incomplete_relations=[]
        for e in root:
            t=tags(e)
            if not selected(t): continue
            record={'type':e.tag,'id':int(e.attrib['id']),'tags':t}
            if e.tag=='node': record.update(lat=float(e.attrib['lat']),lon=float(e.attrib['lon']))
            elif e.tag=='way': record['geometry']=geometry(e)
            elif e.tag=='relation':
                members=[]; complete=True
                for m in e.findall('member'):
                    if m.attrib['type']!='way': continue
                    w=way_table.get(m.attrib['ref'])
                    if w is None or not geometry(w): complete=False; break
                    members.append({'type':'way','ref':int(m.attrib['ref']),'role':m.attrib.get('role',''),'geometry':geometry(w)})
                if not complete: incomplete_relations.append(record['id']); continue
                record['members']=members
            else: continue
            elements.append(record)
        if not elements: raise SystemExit('No protected features in OSM map extract')
        path=ROOT/'data/raw'/f'osm_protected_{stamp}.json'; path.write_text(json.dumps({'elements':elements},ensure_ascii=False,separators=(',',':')),encoding='utf-8')
        save_meta(path,kind,bbox,{'source':'OpenStreetMap contributors','url':url,'license':'ODbL-1.0','normalization':'Protected tagged elements normalized from original OSM XML; exact XML kept separately','original_file':raw_path.name,'original_sha256':digest(raw_path),'element_count':len(elements),'incomplete_relations_omitted':incomplete_relations,'overpass_failures':errors})

if __name__=='__main__': main()

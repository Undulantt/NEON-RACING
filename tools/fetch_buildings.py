"""Separate authentic OSM building snapshot; immutable cache, no synthetic fallback."""
import argparse,hashlib,json,time,urllib.parse,urllib.request
from datetime import datetime,timezone
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]

def cache(cfg):
    for mp in sorted((ROOT/'data/raw').glob('la_paz_buildings_*.meta.json'),reverse=True):
        meta=json.loads(mp.read_text(encoding='utf-8')); p=mp.with_name(meta['file'])
        if meta['bbox']==cfg['bbox'] and p.exists() and hashlib.sha256(p.read_bytes()).hexdigest()==meta['sha256']:
            return p,meta
    return None

def main():
    ap=argparse.ArgumentParser(description=__doc__); ap.add_argument('--refresh',action='store_true'); args=ap.parse_args()
    cfg=json.loads((ROOT/'config/map_config.json').read_text()); found=cache(cfg)
    if found and not args.refresh:
        print('BUILDING CACHE VERIFIED',found[0]); return
    bbox=','.join(map(str,cfg['bbox']))
    query=f'[out:json][timeout:90];way["building"]["building"!="no"]({bbox});(._;>;);out body;'
    urls=['https://overpass.private.coffee/api/interpreter','https://maps.mail.ru/osm/tools/overpass/api/interpreter']
    for i,url in enumerate(urls):
        if i: time.sleep(4)
        try:
            req=urllib.request.Request(url,data=urllib.parse.urlencode({'data':query}).encode(),headers={'User-Agent':'LaPazPhaseBPrototype/1.0'})
            with urllib.request.urlopen(req,timeout=115) as response: raw=response.read()
            data=json.loads(raw)
            if data.get('remark') or not any(e['type']=='way' for e in data.get('elements',[])): raise ValueError('Empty/incomplete building response')
            now=datetime.now(timezone.utc); p=ROOT/'data/raw'/('la_paz_buildings_'+now.strftime('%Y%m%dT%H%M%SZ')+'.json')
            p.write_bytes(raw)
            meta={'file':p.name,'kind':'buildings','bbox':cfg['bbox'],'query':query,'url':url,'extracted_at_utc':now.isoformat(),'osm_base_timestamp':data.get('osm3s',{}).get('timestamp_osm_base'),'sha256':hashlib.sha256(raw).hexdigest(),'license':'ODbL-1.0','source':'OpenStreetMap contributors'}
            p.with_suffix('.meta.json').write_text(json.dumps(meta,indent=2),encoding='utf-8')
            print('BUILDINGS DOWNLOADED',len(raw),'bytes',p); return
        except (OSError,ValueError) as error: print(url,error,flush=True)
    raise SystemExit('No verified building snapshot available; do not invent mapped footprints.')
if __name__=='__main__': main()

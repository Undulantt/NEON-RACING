"""Download an immutable Overpass response; never use fabricated fallback data."""
import argparse
import hashlib
import json
from datetime import datetime, timezone
from pathlib import Path
import time
import urllib.parse
import urllib.request

ROOT = Path(__file__).resolve().parents[1]

def checked_cache(config):
    for meta_path in sorted((ROOT / 'data/raw').glob('*.meta.json'), reverse=True):
        meta = json.loads(meta_path.read_text(encoding='utf-8'))
        raw_path = meta_path.with_name(meta['file'])
        if meta['bbox'] == config['bbox'] and meta.get('highways') == config['highways'] and raw_path.exists():
            raw = raw_path.read_bytes()
            if hashlib.sha256(raw).hexdigest() == meta['sha256']:
                parsed = json.loads(raw)
                if not parsed.get('remark') and any(e['type'] == 'way' for e in parsed.get('elements', [])):
                    return raw_path, meta
    return None

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--config', default='config/map_config.json')
    parser.add_argument('--refresh', action='store_true')
    args = parser.parse_args()
    cfg = json.loads((ROOT / args.config).read_text(encoding='utf-8'))
    cache = checked_cache(cfg)
    if cache and not args.refresh:
        print('CACHE VERIFIED:', cache[0]); return
    bbox = ','.join(str(v) for v in cfg['bbox'])
    types = '|'.join(cfg['highways'])
    query = f'[out:json][timeout:90];way["highway"~"^({types})$"]({bbox});(._;>;);out body;'
    errors = []
    for index, url in enumerate(cfg['overpass_urls']):
        if index:
            time.sleep(4)
        try:
            request = urllib.request.Request(url, data=urllib.parse.urlencode({'data':query}).encode(), headers={'User-Agent':'LaPazPhaseAPrototype/1.0 (offline OSM road research)'})
            with urllib.request.urlopen(request, timeout=115) as response:
                raw = response.read()
            data = json.loads(raw)
            if data.get('remark') or not any(e['type'] == 'way' for e in data.get('elements', [])):
                raise ValueError('Incomplete/empty Overpass response: ' + str(data.get('remark')))
            now = datetime.now(timezone.utc)
            path = ROOT / 'data/raw' / ('la_paz_roads_' + now.strftime('%Y%m%dT%H%M%SZ') + '.json')
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(raw)
            meta = {'file':path.name,'extracted_at_utc':now.isoformat(),'url':url,'bbox':cfg['bbox'],'highways':cfg['highways'],'query':query,'sha256':hashlib.sha256(raw).hexdigest(),'osm_base_timestamp':data.get('osm3s',{}).get('timestamp_osm_base'),'source':'OpenStreetMap contributors','license':'ODbL-1.0'}
            path.with_suffix('.meta.json').write_text(json.dumps(meta, indent=2), encoding='utf-8')
            print('DOWNLOADED:', path, len(raw), 'bytes'); return
        except (OSError, ValueError) as error:
            errors.append(f'{url}: {error}')
            print(errors[-1], flush=True)
    raise SystemExit('Overpass unavailable. No data invented. Use a verified cache or retry later. ' + '; '.join(errors))

if __name__ == '__main__':
    main()

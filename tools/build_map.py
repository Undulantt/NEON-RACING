"""Build deterministic metric graph and unioned asphalt from a verified snapshot."""
import argparse
import json
from pathlib import Path
from fetch_osm import ROOT, checked_cache
from map_core import convert

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--config',default='config/map_config.json')
    args=parser.parse_args()
    cfg=json.loads((ROOT/args.config).read_text(encoding='utf-8'))
    overrides=json.loads((ROOT/'config/map_overrides.json').read_text(encoding='utf-8'))
    if overrides['overrides']:
        raise SystemExit('Overrides unsupported in phase A; review and implement explicitly before conversion.')
    cached=checked_cache(cfg)
    if not cached:
        raise SystemExit('No verified OSM snapshot. Run python tools/fetch_osm.py. No synthetic fallback.')
    path,meta=cached
    data=convert(json.loads(path.read_bytes()),cfg,meta)
    target=ROOT/'data/processed/la_paz_map.json'; target.parent.mkdir(parents=True,exist_ok=True)
    target.write_text(json.dumps(data,ensure_ascii=False,separators=(',',':'),allow_nan=False),encoding='utf-8')
    print(json.dumps(data['statistics'],indent=2)); print('Route:', data['verification_route']['total_length_m'],'m')

if __name__=='__main__':
    main()

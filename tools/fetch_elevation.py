"""Fetch a bounded, version-verified INEGI CEM 4.0 WCS snapshot (never national ZIP)."""
import argparse
import hashlib
import json
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import urlencode
from urllib.request import urlopen

ROOT = Path(__file__).resolve().parents[1]
BASE = 'https://www.inegi.org.mx/app/geo2/elevacionesmex/'


def fetch(url):
    with urlopen(url, timeout=120) as response:
        return response.read()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', default='data/raw/elevation/cem4_la_paz.tif')
    args = parser.parse_args()
    output = ROOT / args.output
    meta_path = output.with_suffix('.meta.json')
    if output.exists():
        meta = json.loads(meta_path.read_text(encoding='utf-8'))
        if hashlib.sha256(output.read_bytes()).hexdigest() != meta['sha256']:
            raise ValueError('Cached DEM hash mismatch')
        print('Verified offline DEM', meta['sha256'])
        return
    cfg = json.loads((ROOT / 'config/map_config.json').read_text(encoding='utf-8'))
    south, west, north, east = cfg['bbox']
    # Halo for smoothing and future seams, not extra playable territory.
    bbox = [west - .005, south - .005, east + .005, north + .005]
    versions_raw = fetch(BASE + 'api/versiones')
    version = next(v for v in json.loads(versions_raw) if v['version'] == '4.0')
    resolutions_raw = fetch(BASE + 'api/resoluciones?' + urlencode({'version': version['id']}))
    resolution = next(v for v in json.loads(resolutions_raw) if v['opcion'] == 15)
    url = version['urlWCS'] + urlencode(dict(request='GetCoverage', service='WCS',
        version='1.0.0', coverage=resolution['capaWCS'], crs='epsg:4326',
        bbox=','.join(map(str, bbox)), resx=.0001388889, resy=.0001388889, format='GeoTIFF'))
    content = fetch(url)
    if content[:4] not in (b'II*\x00', b'MM\x00*', b'II+\x00'):
        raise ValueError('Not a TIFF: ' + content[:500].decode('utf-8', errors='replace'))
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_bytes(content)
    (output.parent / 'cem_versions.json').write_bytes(versions_raw)
    (output.parent / 'cem4_resolutions.json').write_bytes(resolutions_raw)
    describe = version['urlWCS'] + urlencode(dict(service='WCS', version='1.0.0',
        request='DescribeCoverage', coverage=resolution['capaWCS']))
    (output.parent / 'cem4_coverage.xml').write_bytes(fetch(describe))
    meta = dict(source='INEGI Continuo de Elevaciones Mexicano 4.0',
        version=version, resolution=resolution, url=url, bbox_lonlat=bbox,
        fetched_utc=datetime.now(timezone.utc).isoformat(), bytes=len(content),
        sha256=hashlib.sha256(content).hexdigest(),
        license_url='https://www.inegi.org.mx/inegi/terminos.html',
        attribution='Fuente: INEGI, Continuo de Elevaciones Mexicano 4.0.',
        vertical_reference='Metres above mean sea level per official product description; specific geoid not confirmed',
        vertical_accuracy_m=None,
        product_url='https://www.inegi.org.mx/app/biblioteca/ficha.html?upc=794551151600')
    meta_path.write_text(json.dumps(meta, ensure_ascii=False, indent=2), encoding='utf-8')
    print(json.dumps(meta, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()

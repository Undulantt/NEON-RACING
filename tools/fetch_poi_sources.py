"""Acquire optional POI snapshots; pins are explicit in urban_enrichment.json."""
import argparse,json,subprocess,sys,zipfile
from datetime import datetime,timezone
from fetch_urban_sources import ROOT,load_json,digest,request,save_meta
from poi_sources import denue_rows

def fetch(kind,refresh=False):
    cfg=load_json(ROOT/'config/map_config.json'); settings=load_json(ROOT/'config/urban_enrichment.json')
    key='overture_places' if kind=='places' else 'denue'
    pin=settings.get('sources',{}).get(key)
    if pin and not refresh:
        meta=load_json(ROOT/'data/raw'/pin['metadata_file']);path=ROOT/'data/raw'/meta['file']
        if digest(path)!=meta['sha256'] or meta['bbox']!=cfg['bbox']: raise ValueError('Pinned source mismatch')
        print('PIN VERIFIED',path);return
    stamp=datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ')
    if kind=='places':
        release=load_json(ROOT/'config/urban_config.json')['overture_release'];south,west,north,east=cfg['bbox']
        path=ROOT/'data/raw'/f'overture_places_{stamp}.geojson'
        command=[sys.executable,'-m','overturemaps','download',f'--bbox={west},{south},{east},{north}','-f','geojson','--type=place','--release',release,'--connect_timeout','30','--request_timeout','120','-o',str(path)]
        subprocess.run(command,check=True,timeout=600)
        data=load_json(path)
        if not data.get('features'): raise ValueError('Empty Places snapshot')
        fields=sorted({k for f in data['features'] for k in f['properties']})
        if 'taxonomy' not in fields and 'basic_category' not in fields: raise ValueError('Unexpected Places schema; inspect before importing')
        save_meta(path,key,cfg['bbox'],{'source':'Overture Maps Foundation Places','release':release,'license':'Per-record sources: CDLA-Permissive-2.0 / Apache-2.0 / CC0-1.0','url':f'https://stac.overturemaps.org/{release}/catalog.json','observed_fields':fields,'feature_count':len(data['features']),'command':command[1:]})
    else:
        url='https://www.inegi.org.mx/contenidos/masiva/denue/denue_03_csv.zip'
        path=ROOT/'data/raw'/f'denue_{stamp}.zip';path.write_bytes(request(url));rows,schema=denue_rows(path)
        with zipfile.ZipFile(path) as z: metadata=z.read('metadatos/metadatos_denue.txt').decode('utf-8-sig')
        save_meta(path,key,cfg['bbox'],{'source':'INEGI DENUE','license':'INEGI Terminos de Libre Uso','url':url,'license_url':'https://www.inegi.org.mx/inegi/terminos.html','row_count':len(rows),'schema':schema,'source_metadata':metadata,'metadata_encoding':'utf-8-sig'})
    print('Inspect and pin this metadata_file in config/urban_enrichment.json:',path.with_suffix('.meta.json').name)
if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('source',choices=['places','denue']);parser.add_argument('--refresh',action='store_true');args=parser.parse_args();fetch(args.source,args.refresh)

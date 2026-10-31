"""Select unchanged Overture snapshot explicitly; new western footprints come from verified OSM patches.

Never claim Overture coverage outside its original download envelope. Selection
metadata is separate from actual source coverage and original bytes stay intact.
"""
import json
from pathlib import Path
from fetch_urban_sources import digest

ROOT=Path(__file__).resolve().parents[1]

def prepare():
    cfg=json.loads((ROOT/'config/map_config.json').read_text(encoding='utf-8'))
    source=ROOT/'data/raw/overture_buildings_20261026T064408Z.meta.json'
    meta=json.loads(source.read_text(encoding='utf-8'))
    assert digest(ROOT/'data/raw'/meta['file'])==meta['sha256']
    meta.update(selection_bbox=cfg['bbox'],prior_metadata_file=source.name,
        selection_note='Original Overture coverage bbox unchanged. The westward addition outside bbox uses real OSM footprints from the C6 patches, plus explicitly fictional INEGI infill under existing rules. No Overture coverage is asserted there.',
        supplemental_footprint_source='la_paz_buildings_c6_boundary_expansion.meta.json')
    target=ROOT/'data/raw/overture_buildings_c6_boundary_selection.meta.json'
    target.write_text(json.dumps(meta,indent=2,ensure_ascii=False)+'\n',encoding='utf-8',newline='\n')
    print('Overture original source coverage retained; extended OSM coverage explicitly recorded')

if __name__=='__main__':prepare()

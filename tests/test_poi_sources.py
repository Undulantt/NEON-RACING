import json,sys,unittest
from pathlib import Path
from unittest.mock import patch
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools'))
from poi_sources import denue_rows,denue_category,overture_category,normalized_name,read_external,ROOT
from fetch_urban_sources import load_json

class PoiSourcesTests(unittest.TestCase):
    def test_observed_denue_schema_and_publication(self):
        rows,schema=denue_rows(ROOT/'data/raw/denue_03_csv.zip')
        self.assertEqual(len(rows),42577)
        self.assertIn('codigo_act',schema['fields'])
        self.assertEqual(schema['encoding'],'cp1252')
        metadata=load_json(ROOT/'data/raw/denue_03_csv.meta.json')
        self.assertEqual(metadata['publication_date'],'2026-05-20')
        self.assertIn('Estadístico',metadata['source_metadata'])
        self.assertNotIn('Ã',metadata['source_metadata'])
    def test_current_taxonomy_and_scian_rules(self):
        self.assertEqual(overture_category({'taxonomy':{'hierarchy':['food_and_drink','restaurant']}}),'restaurant')
        self.assertEqual(overture_category({'taxonomy':{'hierarchy':['lodging','hotel']}}),'hotel')
        for code,want in [('722511','restaurant'),('721111','hotel'),('611111','institutional'),('712111','cultural'),('311812','industrial'),('461110','commercial')]: self.assertEqual(denue_category(code),want)
        self.assertEqual(normalized_name('CAFÉ  La-Paz'),'cafe la paz')
    def test_low_confidence_and_closed_are_retained_for_review(self):
        cfg=load_json(ROOT/'config/map_config.json');settings=load_json(ROOT/'config/urban_enrichment.json')
        records,meta,_=read_external(cfg,settings)
        self.assertEqual(set(meta),{'denue','overture_places'})
        self.assertGreater(len(records),5000)
        for p in records:
            self.assertTrue(cfg['bbox'][0]<=p['lat']<=cfg['bbox'][2])
            if p['id'].startswith('overture:') and (p['source_existence_confidence'] or 0)<0.6: self.assertFalse(p['eligible_for_classification'])
    def test_corrupt_source_rejected(self):
        meta={'file':'fixture.geojson','sha256':'expected','bbox':[0,0,1,1]}
        with patch('poi_sources.load_json',return_value=meta), patch('poi_sources.digest',return_value='corrupt'):
            with self.assertRaisesRegex(ValueError,'hash/bbox'):
                read_external({'bbox':[0,0,1,1]},{'sources':{'overture_places':{'metadata_file':'fixture.meta.json'}}})

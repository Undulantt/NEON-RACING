import importlib.util,json,math,sys,unittest
from pathlib import Path
from shapely.geometry import Polygon,Point
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
from validate_urban_city import validate,projection

class UrbanDataTests(unittest.TestCase):
    def test_full_hybrid_city_and_untouched_baseline(self):
        self.assertTrue(validate()['passed'])
    def test_cache_is_bound_to_requested_release_and_source(self):
        from fetch_urban_sources import cached
        cfg=json.loads((ROOT/'config/map_config.json').read_text()); urban=json.loads((ROOT/'config/urban_config.json').read_text())
        self.assertIsNotNone(cached('overture_buildings',cfg['bbox'],release=urban['overture_release']))
        self.assertIsNone(cached('overture_buildings',cfg['bbox'],release='not-a-cached-release'))
        self.assertIsNotNone(cached('inegi_blocks',cfg['bbox'],url=urban['inegi_url']))
        self.assertIsNone(cached('inegi_blocks',cfg['bbox'],url='https://example.invalid/not-this-source'))
    def test_same_projection_as_roads(self):
        from map_core import gps_to_local
        cfg=json.loads((ROOT/'config/map_config.json').read_text())
        local=projection(cfg)
        for lat,lon in [(24.159,-110.3195),(24.148,-110.334),(24.17,-110.305)]:
            actual=local(lon,lat); expected=gps_to_local(lat,lon,cfg['origin_lat'],cfg['origin_lon'])
            self.assertLess(math.dist(actual,expected),1e-8)
    @unittest.skipUnless(importlib.util.find_spec('pyproj'),'Run with .venv-urban for INEGI CRS check')
    def test_inegi_crs_is_explicit(self):
        from pyproj import CRS,Transformer
        self.assertTrue(CRS('EPSG:6365').is_geographic)
        transformer=Transformer.from_crs('EPSG:6365','EPSG:4326',always_xy=True)
        lon,lat=transformer.transform(-110.32,24.159)
        self.assertAlmostEqual(lon,-110.32,places=4); self.assertAlmostEqual(lat,24.159,places=4)
    @unittest.skipUnless(importlib.util.find_spec('pyproj'),'Run with .venv-urban for protected-area fixture')
    def test_water_and_coast_fixture(self):
        # Technical fixtures only; never exported to the game map.
        from build_urban_city import protected_shapes
        raw={'elements':[{'type':'way','id':1,'tags':{'natural':'water'},'geometry':[{'lon':0,'lat':0},{'lon':2,'lat':0},{'lon':2,'lat':2},{'lon':0,'lat':2},{'lon':0,'lat':0}]},{'type':'way','id':2,'tags':{'natural':'coastline'},'geometry':[{'lon':3,'lat':0},{'lon':3,'lat':2}]}]}
        protected,coast=protected_shapes(raw,lambda x,y:(x,y))
        self.assertEqual(len(protected),1); self.assertEqual(len(coast),1)
        self.assertTrue(protected[0][1].covers(Point(1,1)))
    def test_all_source_types_are_explicit(self):
        p=ROOT/'data/processed/urban/city_manifest.json'; manifest=json.loads(p.read_text(encoding='utf-8'))
        self.assertIn('overture',manifest['statistics']['source_counts'])
        self.assertIn('osm',manifest['statistics']['source_counts'])
        self.assertGreater(manifest['statistics']['overture_downloaded'],239)

if __name__=='__main__': unittest.main()

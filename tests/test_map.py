"""Synthetic inputs are isolated unit fixtures; integration uses the authentic snapshot."""
import copy
import json
import math
from pathlib import Path
import sys
import unittest
from unittest.mock import patch
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools'))
from fetch_osm import ROOT, checked_cache
from map_core import gps_to_local, attributes, allowed, dijkstra, convert
from validate_map import validate

class ProjectionTests(unittest.TestCase):
    def test_origin_and_axes(self):
        self.assertEqual(gps_to_local(24.159,-110.32,24.159,-110.32),(0,0))
        self.assertLess(gps_to_local(24.160,-110.32,24.159,-110.32)[1],0)
        self.assertAlmostEqual(gps_to_local(24.159,-110.319,24.159,-110.32)[0],101.45,delta=0.1)
        self.assertAlmostEqual(-gps_to_local(24.160,-110.32,24.159,-110.32)[1],111.195,delta=0.01)

class AttributeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.cfg=json.loads((ROOT/'config/map_config.json').read_text())
    def test_width_sources(self):
        exact=attributes({'highway':'residential','width':'8.5 m'},self.cfg)
        self.assertEqual(exact['width_m'],8.5); self.assertFalse(exact['width_estimated'])
        lanes=attributes({'highway':'residential','lanes':'2'},self.cfg)
        self.assertEqual(lanes['width_m'],6.4); self.assertTrue(lanes['width_estimated'])
        self.assertEqual(attributes({'highway':'residential'},self.cfg)['width_m'],7)
    def test_oneway_reverse_roundabout(self):
        self.assertTrue(attributes({'highway':'service','oneway':'-1'},self.cfg)['reversed'])
        self.assertTrue(attributes({'highway':'service','junction':'roundabout'},self.cfg)['oneway'])
        self.assertFalse(attributes({'highway':'service','junction':'roundabout','oneway':'no'},self.cfg)['oneway'])
    def test_access_and_levels(self):
        for tags in ({'access':'private'},{'motor_vehicle':'no'},{'bridge':'yes'},{'tunnel':'yes'},{'layer':'1'}):
            self.assertFalse(allowed(tags))
        self.assertTrue(allowed({'access':'private','motorcar':'yes'}))
    def test_reverse_way_and_boundary_fixture(self):
        # Deliberately synthetic and only in memory: never written to game data.
        fixture={'elements':[{'type':'node','id':1,'lat':24.159,'lon':-110.34},{'type':'node','id':2,'lat':24.159,'lon':-110.31},{'type':'way','id':3,'nodes':[1,2],'tags':{'highway':'residential','oneway':'-1'}}]}
        with patch('map_core.verification_route',return_value={}):
            result=convert(fixture,self.cfg,{'source':'SYNTHETIC UNIT TEST ONLY'})
        road=result['roads'][0]
        self.assertEqual(road['from'],'2')
        self.assertTrue(road['to'].startswith('clip:'))
        self.assertGreater(road['points_xz'][0][0],road['points_xz'][1][0])
        self.assertEqual(len(result['edges']),1)
        self.assertEqual(result['edges'][0]['from'],'2')
    def test_directed_dijkstra_fixture(self):
        fixture={'edges':[{'from':'test_A','to':'test_B','length_m':30},{'from':'test_B','to':'test_C','length_m':40}]}
        self.assertEqual(dijkstra(fixture,'test_A')[0]['test_C'],70)
        self.assertNotIn('test_A',dijkstra(fixture,'test_C')[0])

class RealMapTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.data=json.loads((ROOT/'data/processed/la_paz_map.json').read_text(encoding='utf-8'))
    def test_real_source_export_surface_and_route(self):
        validate(self.data)
    def test_cache_hash(self):
        cfg=json.loads((ROOT/'config/map_config.json').read_text())
        self.assertIsNotNone(checked_cache(cfg))
    def test_no_hidden_example_data(self):
        for road in self.data['roads']:
            self.assertTrue(road['osm_way_id'].isdigit())
            self.assertNotIn('sample',road['id'])
        self.assertGreater(self.data['verification_route']['obregon_length_m'],1200)
    def test_corrupt_direction_is_rejected(self):
        damaged=copy.deepcopy(self.data)
        damaged['edges'][0]['from']='missing_osm_node'
        with self.assertRaises(AssertionError): validate(damaged,check_source=False)
    def test_nan_is_rejected(self):
        damaged=copy.deepcopy(self.data); damaged['nodes'][0]['x']=float('nan')
        with self.assertRaises(AssertionError): validate(damaged,check_source=False)
    def test_deterministic_build(self):
        cfg=json.loads((ROOT/'config/map_config.json').read_text())
        raw,meta=checked_cache(cfg)
        result=convert(json.loads(raw.read_bytes()),cfg,meta)
        self.assertEqual(result,self.data)

if __name__=='__main__': unittest.main()

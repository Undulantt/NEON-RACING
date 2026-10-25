import sys, unittest
from pathlib import Path
from shapely.geometry import Polygon, Point
from shapely.strtree import STRtree
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools'))
from urban_enrichment import associate, category, read, ROOT

class EnrichmentTests(unittest.TestCase):
    def test_ambiguous_and_proximity_are_not_assigned(self):
        shapes=[Polygon([(0,0),(5,0),(5,5),(0,5)]),Polygon([(7,0),(12,0),(12,5),(7,5)])]
        tree=STRtree(shapes)
        self.assertIsNone(associate(Point(6,2),shapes,tree)[0])
        self.assertIsNone(associate(Point(-1,2),shapes,tree)[0])
        self.assertEqual(associate(Point(2,2),shapes,tree)[0],0)
    def test_courtyard_is_not_containment(self):
        poly=Polygon([(0,0),(10,0),(10,10),(0,10)],[[(3,3),(7,3),(7,7),(3,7)]])
        self.assertIsNone(associate(Point(5,5),[poly],STRtree([poly]))[0])
    def test_categories_use_evidence(self):
        self.assertEqual(category({}),'unknown')
        self.assertEqual(category({'amenity':'restaurant'}),'restaurant')
        self.assertEqual(category({'tourism':'hotel'}),'hotel')
    def test_real_records_reference_existing_buildings(self):
        enrichment=read(ROOT/'data/processed/urban/urban_enrichment.json')
        manifest=read(ROOT/'data/processed/urban/city_manifest.json')
        buildings={b['id']:b for c in manifest['chunks'] for b in read(ROOT/'data/processed/urban'/c['file'])['buildings']}
        self.assertGreater(len(enrichment['pois']),0)
        self.assertFalse(enrichment['orphan_overrides'])
        for p in enrichment['pois']:
            self.assertIn(p['category'],read(ROOT/'config/urban_enrichment.json')['categories'])
            if p['building_id']:
                b=buildings[p['building_id']]
                self.assertTrue(Polygon(b['footprint_xz'],b['holes_xz']).covers(Point(p['position_xz'])))
            else: self.assertTrue(p['needs_review'])
    def test_overrides_persist_and_orphans_are_reported(self):
        from copy import deepcopy
        from unittest.mock import patch
        from urban_enrichment import enrich
        from build_urban_city import projector
        cfg=read(ROOT/'config/map_config.json')
        meta=read(ROOT/'data/raw/osm_protected_20261024T221536Z.meta.json')
        manifest=read(ROOT/'data/processed/urban/city_manifest.json')
        original=read(ROOT/'data/processed/urban'/manifest['chunks'][0]['file'])['buildings'][0]
        overrides={'buildings':{original['id']:{'height_m':12,'category':'hotel','disabled':True,'reason':'unit test fixture','source':'test only'},'missing-id':{'reason':'fixture','source':'test'}},'pois':{}}
        actual_read=read
        def configured(path):
            return overrides if path.name=='urban_overrides.json' else actual_read(path)
        with patch('urban_enrichment.read',side_effect=configured):
            a=[deepcopy(original)]; b=[deepcopy(original)]
            first=enrich(a,projector(cfg),cfg,meta); second=enrich(b,projector(cfg),cfg,meta)
        self.assertEqual(first,second)
        self.assertEqual(a,b)
        self.assertEqual(a[0]['height_m'],12)
        self.assertEqual(a[0]['category'],'hotel')
        self.assertTrue(a[0]['disabled'])
        self.assertEqual(a[0]['footprint_xz'],original['footprint_xz'])
        self.assertIn('missing-id',first['orphan_overrides'])

    def test_coast_direction_and_building_conflict(self):
        from urban_geography import surfaces
        from shapely.geometry import box,LineString,shape
        region=box(0,0,10,10)
        # Northward in local XZ: water to east, land west.
        coast=[LineString([(5,11),(5,-1)])]
        result=surfaces(region,coast,[],[],Polygon())
        sea=shape(result['water_geometry_xz'])
        self.assertTrue(sea.covers(Point(8,5)))
        self.assertFalse(sea.covers(Point(2,5)))
        with self.assertRaises(ValueError):
            surfaces(region,coast,[],[{'footprint_xz':[[7,1],[9,1],[9,3],[7,3]]}],Polygon())

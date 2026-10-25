import hashlib,json,math,sys,unittest
from pathlib import Path
from shapely.geometry import Polygon,LineString,box
from shapely.ops import unary_union
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
from map_core import gps_to_local

class EnvironmentTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.data=json.loads((ROOT/'data/processed/la_paz_environment.json').read_text(encoding='utf-8'))
        cls.map=json.loads((ROOT/'data/processed/la_paz_map.json').read_text(encoding='utf-8'))
    def test_bound_map_and_authentic_source(self):
        self.assertEqual(self.data['map_sha256'],hashlib.sha256((ROOT/'data/processed/la_paz_map.json').read_bytes()).hexdigest())
        meta=self.data['metadata']['building_provenance']; raw=(ROOT/'data/raw'/meta['file']).read_bytes()
        self.assertEqual(hashlib.sha256(raw).hexdigest(),meta['sha256'])
        source=json.loads(raw); ways={str(e['id']):e for e in source['elements'] if e['type']=='way'}; nodes={e['id']:e for e in source['elements'] if e['type']=='node'}
        for building in self.data['buildings']:
            way=ways[building['osm_way_id']]
            expected=Polygon([gps_to_local(nodes[n]['lat'],nodes[n]['lon'],self.map['metadata']['origin_lat'],self.map['metadata']['origin_lon']) for n in way['nodes']])
            self.assertLess(expected.symmetric_difference(Polygon(building['footprint_xz'])).area,1e-6)
    def test_buildings_clear_roads_and_valid_roofs(self):
        surface=unary_union([LineString(r['points_xz']).buffer(r['width_m']/2,quad_segs=4) for r in self.map['roads']]).buffer(1)
        self.assertGreater(len(self.data['buildings']),10)
        for b in self.data['buildings']:
            p=Polygon(b['footprint_xz']); self.assertTrue(p.is_valid); self.assertFalse(p.intersects(surface)); self.assertTrue(2.8<=b['height_m']<=10)
            roof=unary_union([Polygon(t) for t in b['roof_triangles_xz']]); self.assertLess(p.symmetric_difference(roof).area,1e-6)
    def test_driving_route_is_real_and_multistreet(self):
        edges={e['id']:e for e in self.map['edges']}; route=self.data['driving_test_route']; seq=route['node_ids']; total=0
        for i,eid in enumerate(route['edge_ids']):
            e=edges[eid]; self.assertEqual([e['from'],e['to']],seq[i:i+2]); total+=e['length_m']
        self.assertAlmostEqual(total,route['length_m']); self.assertGreaterEqual(len(route['street_names']),3); self.assertGreaterEqual(route['turns_over_36_degrees'],2)
    def test_spawn_and_bounds(self):
        spawn=self.data['spawn']; p=spawn['position_xz']; bounds=self.data['bounds_xz']
        self.assertTrue(bounds[0]<p[0]<bounds[2] and bounds[1]<p[1]<bounds[3])
        self.assertAlmostEqual(math.hypot(*spawn['forward_xz']),1)

if __name__=='__main__': unittest.main()

"""Critical Cajoncito road import, provenance and directed connectivity."""
import hashlib,json,sys,unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
from map_core import allowed_way

def read(p): return json.loads((ROOT/p).read_text(encoding='utf-8'))

class CajoncitoTests(unittest.TestCase):
    def test_reviewed_bridge_policy_does_not_relax_access_or_tunnels(self):
        cfg=read('config/map_config.json')
        tags={'highway':'primary','bridge':'yes','layer':'1'}
        self.assertTrue(allowed_way(tags,cfg,'127454232'))
        self.assertFalse(allowed_way(tags,cfg,'unknown'))
        for extra in [{'access':'private'},{'motor_vehicle':'no'},{'tunnel':'yes'},{'layer':'2'}]:
            self.assertFalse(allowed_way({**tags,**extra},cfg,'127454232'))

    def test_all_four_corridors_and_both_forjadores_crossings_exist(self):
        data=read('data/processed/la_paz_map.json')
        by_way={r['osm_way_id'] for r in data['roads']}
        self.assertTrue({'268729687','268780989','28785401','949534856','309422738','1244386447','127454232','127454233','443101245','443101250'}.issubset(by_way))
        self.assertTrue(any(r['osm_tags'].get('ref')=='MEX 1' for r in data['roads']))
        self.assertNotIn('660516292',by_way)
        deferred=[e for e in data['exclusions'] if e['way_id']=='660516292']
        self.assertEqual(len(deferred),1)
        self.assertIn('lower-level crossing',deferred[0]['reason'])
        for r in data['roads']:
            if r['osm_way_id'] in ['127454232','127454233','443101245','443101250']:
                self.assertEqual(r['osm_tags']['layer'],'1')
                self.assertEqual(r['osm_tags']['bridge'],'yes')
                self.assertIn('flat prototype',r['elevation_treatment'])

    def test_critical_routes_traverse_required_source_nodes_and_directed_edges(self):
        data=read('data/processed/la_paz_map.json')
        manifest=read('data/processed/expansion_manifest.json')
        profile=read('config/expansion_config.json')
        self.assertEqual(len(manifest['critical_routes']),4)
        edges={e['id']:e for e in data['edges']}
        roads={r['id']:r for r in data['roads']}
        definitions={e['id']:e for e in profile['critical_corridors']}
        for entry in manifest['critical_routes']:
            path=ROOT/entry['file']
            self.assertEqual(hashlib.sha256(path.read_bytes()).hexdigest(),entry['sha256'])
            route=json.loads(path.read_text(encoding='utf-8'))
            used=set(); length=0
            pairs=set(zip(route['node_ids'],route['node_ids'][1:]))
            for i,identifier in enumerate(route['edge_ids']):
                edge=edges[identifier]
                self.assertEqual([edge['from'],edge['to']],route['node_ids'][i:i+2])
                used.add(roads[edge['road_id']]['osm_way_id'])
                length+=edge['length_m']
            self.assertTrue(set(route['required_osm_way_ids']).issubset(used))
            self.assertAlmostEqual(length,route['length_m'])
            key=entry['id'].removeprefix('cajoncito_')
            for chain in definitions[key]['source_node_chains']:
                self.assertTrue(set(zip(chain,chain[1:])).issubset(pairs))

if __name__=='__main__': unittest.main()

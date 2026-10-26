"""C.5 real-data checks and isolated block-boundary fixtures."""
import hashlib, json, math, sys, unittest
from pathlib import Path
from unittest.mock import patch
from shapely.geometry import Point, LineString
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
from expansion_regions import metric_region
from map_core import convert, dijkstra

class ExpansionTests(unittest.TestCase):
    def test_block_mask_does_not_open_future_southeast(self):
        cfg=json.loads((ROOT/'config/map_config.json').read_text(encoding='utf-8'))
        from expansion_regions import region_lonlat
        region=region_lonlat(cfg)
        self.assertTrue(region.covers(Point(-110.32,24.159)))
        self.assertTrue(region.covers(Point(-110.29,24.1714)))
        self.assertFalse(region.covers(Point(-110.29,24.15)))
        self.assertEqual((cfg['origin_lat'],cfg['origin_lon']),(24.159,-110.3195))
    def test_disjoint_fixture_never_invents_connector(self):
        cfg=json.loads((ROOT/'config/map_config.json').read_text(encoding='utf-8'))
        cfg['active_blocks']={'test_a':[24.15,-110.334,24.16,-110.325],'test_b':[24.15,-110.315,24.16,-110.305]}
        raw={'elements':[{'type':'node','id':1,'lat':24.155,'lon':-110.34},{'type':'node','id':2,'lat':24.155,'lon':-110.30},{'type':'way','id':3,'nodes':[1,2],'tags':{'highway':'residential'}}]}
        with patch('map_core.verification_route',return_value={}):
            data=convert(raw,cfg,{'source':'SYNTHETIC TEST ONLY'})
        self.assertEqual(len(data['roads']),2)
        distances,_=dijkstra(data,data['roads'][0]['from'])
        self.assertNotIn(data['roads'][1]['to'],distances)
        region=metric_region(cfg)
        self.assertTrue(all(region.buffer(1e-6).covers(LineString(r['points_xz'])) for r in data['roads']))
    def test_routes_follow_real_directed_edges_and_reach_north(self):
        manifest=json.loads((ROOT/'data/processed/expansion_manifest.json').read_text(encoding='utf-8'))
        path=ROOT/'data/processed/la_paz_map.json'
        self.assertEqual(hashlib.sha256(path.read_bytes()).hexdigest(),manifest['map_sha256'])
        data=json.loads(path.read_text(encoding='utf-8'))
        edges={e['id']:e for e in data['edges']}
        roads={r['id']:r for r in data['roads']}
        for entry in manifest['routes']:
            path=ROOT/entry['file']; self.assertEqual(hashlib.sha256(path.read_bytes()).hexdigest(),entry['sha256'])
            route=json.loads(path.read_text(encoding='utf-8')); total=0; points=[]
            for i,eid in enumerate(route['edge_ids']):
                edge=edges[eid]
                self.assertEqual([edge['from'],edge['to']],route['node_ids'][i:i+2])
                p=roads[edge['road_id']]['points_xz']
                if edge['reverse']: p=list(reversed(p))
                points.extend(p if not points else p[1:]); total+=edge['length_m']
            self.assertEqual(points,route['points_xz'])
            self.assertAlmostEqual(total,route['length_m'])
            self.assertGreater(total,3000)
            if entry['id'].startswith('north_'):
                self.assertLess(min(p[1] for p in points),-1200)
            else:
                self.assertGreater(max(p[1] for p in points),4800)
        self.assertGreater(manifest['statistics']['area_ratio'],2)
        self.assertTrue(all(a['directed_distance_from_core_m']>0 for a in manifest['anchors']))
    def test_south_connects_real_hospital_and_university(self):
        manifest=json.loads((ROOT/'data/processed/expansion_manifest.json').read_text(encoding='utf-8'))
        anchors={a['id']:a for a in manifest['anchors']}
        cfg=json.loads((ROOT/'config/map_config.json').read_text(encoding='utf-8'))
        south=metric_region({**cfg,'active_blocks':{'south':cfg['active_blocks']['south']}})
        for identifier in ['hospital_salvatierra','uabcs','conexion_sur']:
            self.assertTrue(south.covers(Point(anchors[identifier]['position_xz'])))
            self.assertLess(anchors[identifier].get('snap_distance_m',0),350)
        enrichment=json.loads((ROOT/'data/processed/urban/urban_enrichment.json').read_text(encoding='utf-8'))
        pois={p['id']:p for p in enrichment['pois']}
        for identifier,category in [('osm:way:137201460','university'),('osm:way:301737276','hospital')]:
            self.assertIn(identifier,pois)
            self.assertEqual(pois[identifier]['tags']['amenity'],category)
        self.assertEqual({b['id'] for b in manifest['active_blocks']},{'core','north','south'})

    def test_streamed_facades_are_hash_bound_to_their_city_sector(self):
        layout=json.loads((ROOT/'data/processed/arcade_layout.json').read_text(encoding='utf-8'))
        city=json.loads((ROOT/'data/processed/urban/city_manifest.json').read_text(encoding='utf-8'))
        chunks={c['id']:c for c in city['chunks']}
        self.assertFalse(layout['building_overrides'])
        count=0
        for cell,entry in layout['chunk_overrides'].items():
            self.assertIn(cell,chunks)
            path=ROOT/entry['file']
            self.assertEqual(hashlib.sha256(path.read_bytes()).hexdigest(),entry['sha256'])
            overrides=json.loads(path.read_text(encoding='utf-8'))
            self.assertEqual(len(overrides),entry['buildings'])
            buildings=json.loads((ROOT/'data/processed/urban'/chunks[cell]['file']).read_text(encoding='utf-8'))['buildings']
            self.assertTrue(set(overrides).issubset({b['id'] for b in buildings}))
            count+=len(overrides)
        self.assertEqual(count,layout['statistics']['buildings_adjusted']+layout['statistics']['buildings_removed'])

    def test_red_line_excludes_all_generated_surfaces_and_buildings(self):
        from expansion_regions import region_lonlat, metric_clip
        from shapely.geometry import Polygon
        from shapely.prepared import prep
        cfg=json.loads((ROOT/'config/map_config.json').read_text(encoding='utf-8'))
        region=region_lonlat(cfg)
        for lon,lat in [(-110.339,24.094),(-110.296,24.11),(-110.317,24.0905)]:
            self.assertFalse(region.covers(Point(lon,lat)))
        for lon,lat in [(-110.31907,24.11237),(-110.3191762,24.1046213)]:
            self.assertTrue(region.covers(Point(lon,lat)))
        clip=prep(metric_clip(cfg).buffer(0.0001))
        for name in ['la_paz_map.json','arcade_layout.json']:
            data=json.loads((ROOT/'data/processed'/name).read_text(encoding='utf-8'))
            for chunk in data['chunks']:
                x,z=chunk['origin_xz']
                for tri in chunk['triangles_xz']:
                    self.assertTrue(clip.covers(Polygon([(p[0]+x,p[1]+z) for p in tri])),name)
        city=json.loads((ROOT/'data/processed/urban/city_manifest.json').read_text(encoding='utf-8'))
        for entry in city['chunks']:
            for building in json.loads((ROOT/'data/processed/urban'/entry['file']).read_text(encoding='utf-8'))['buildings']:
                self.assertTrue(clip.covers(Polygon(building['footprint_xz'],building['holes_xz'])))
        geo=json.loads((ROOT/'data/processed/urban/urban_geography.json').read_text(encoding='utf-8'))
        for surface in geo['surfaces']:
            for tri in surface['triangles_xz']:
                self.assertTrue(clip.covers(Polygon(tri)),surface['id'])
        env=json.loads((ROOT/'data/processed/la_paz_environment.json').read_text(encoding='utf-8'))
        self.assertIn('playable_boundary_xz',env)
        for tri in env['safety_triangles_xz']:
            self.assertTrue(clip.covers(Polygon(tri)))

    def test_all_immutable_osm_tiles_verify(self):
        profile=json.loads((ROOT/'config/expansion_config.json').read_text(encoding='utf-8'))
        meta=json.loads((ROOT/('data/raw/osm_protected_'+profile.get('source_selection','c5_north')+'.meta.json')).read_text(encoding='utf-8'))
        seen=set()
        for tile in meta['source_tiles']:
            self.assertNotIn(tile['file'],seen);seen.add(tile['file'])
            self.assertEqual(hashlib.sha256((ROOT/'data/raw'/tile['file']).read_bytes()).hexdigest(),tile['sha256'])
        self.assertGreater(len(seen),1)

if __name__=='__main__': unittest.main()

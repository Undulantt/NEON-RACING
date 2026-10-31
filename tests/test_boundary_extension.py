"""Boundary extension geometry, sea exclusion and reproducible fictional ridges."""
import hashlib
import json
import math
from pathlib import Path
import sys
import tempfile
import unittest

import numpy as np
from shapely.geometry import Point, Polygon, box, shape
from shapely.ops import unary_union

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
from expansion_regions import region_lonlat
from relief_limits import bake_limits

class FlatField:
    def height(self,x,z):return 10.0

class BoundaryExtensionTests(unittest.TestCase):
    def test_sea_geometry_changes_only_in_user_approved_cells(self):
        before=json.loads((ROOT/'docs/map_extension_baseline/urban_geography.json').read_text(encoding='utf-8'))
        after=json.loads((ROOT/'data/processed/urban/urban_geography.json').read_text(encoding='utf-8'))
        cfg=json.loads((ROOT/'config/map_config.json').read_text(encoding='utf-8'))
        source=json.loads((ROOT/cfg['preserved_sea_file']).read_text(encoding='utf-8'))
        approved=shape(source['properties']['sea_adjustment_geometry_xz']) if 'sea_adjustment_geometry_xz' in source.get('properties',{}) else Polygon()
        change=shape(before['water_geometry_xz']).symmetric_difference(shape(after['water_geometry_xz']))
        self.assertLess(change.difference(approved).area,0.001)

    def test_local_extensions_preserve_original_region(self):
        old=json.loads((ROOT/'docs/map_extension_baseline/expansion_config.json').read_text(encoding='utf-8'))
        new=json.loads((ROOT/'config/expansion_config.json').read_text(encoding='utf-8'))
        def cfg(profile):
            return {**profile,'bbox':[24.09,-110.3455,24.185,-110.281],'active_blocks':{k:profile['blocks'][k]['bbox'] for k in profile['active_blocks']}}
        a,b=region_lonlat(cfg(old)),region_lonlat(cfg(new))
        self.assertLess(a.difference(b).area,1e-12)
        for point in [(-110.3005,24.156),(-110.344,24.136),(-110.3435,24.119)]:
            self.assertFalse(a.covers(Point(point)))
            self.assertTrue(b.covers(Point(point)))
        self.assertFalse(b.covers(Point(-110.29,24.15)))

    def test_fictional_ridge_keeps_sea_and_interior_clear(self):
        region=box(0,0,256,256)
        sea=box(-500,-500,-1,700)
        settings={'enabled':True,'height_m':120,'width_m':220,'shore_clearance_m':40}
        temporary_root=ROOT/'.godot-local-profile'
        temporary_root.mkdir(exist_ok=True)
        with tempfile.TemporaryDirectory(dir=temporary_root) as folder:
            root=Path(folder);out=root/'world'
            entries=bake_limits(out,region,FlatField(),root,sea,settings)
            hashes={e['file']:e['sha256'] for e in entries}
            faces=[];front_grades=[];hidden=0
            for e in entries:
                mesh=np.fromfile(root/e['file'],dtype='<f4').reshape(-1,3,3).astype(float)
                mesh[:,:,0]+=e['origin_xz'][0];mesh[:,:,2]+=e['origin_xz'][1]
                hidden+=len(mesh)-e['visible_triangles_count']
                for tri in mesh[:e['visible_triangles_count']]:
                    p=Polygon(tri[:,[0,2]])
                    self.assertLess(p.intersection(region).area,0.005)
                    self.assertLess(p.intersection(sea.buffer(39.9)).area,0.005)
                    faces.append(p)
                    n=np.cross(tri[1]-tri[0],tri[2]-tri[0])
                    if min(tri[:,1])<10 and max(tri[:,1])>40 and max(region.distance(Point(v[0],v[2])) for v in tri)<9:
                        front_grades.append(math.degrees(math.atan2(np.linalg.norm(n[[0,2]]),abs(n[1]))))
            self.assertTrue(faces)
            self.assertGreater(hidden,0)
            self.assertTrue(front_grades)
            self.assertGreater(min(front_grades),42)
            second=bake_limits(out,region,FlatField(),root,sea,settings)
            self.assertEqual(hashes,{e['file']:e['sha256'] for e in second})

    def test_concave_join_has_no_crossed_or_overlapping_faces(self):
        region=box(0,0,256,512).union(box(0,256,512,512))
        sea=box(-1000,-1000,-500,1000)
        settings={'enabled':True,'height_m':120,'width_m':220,'shore_clearance_m':40}
        folder=ROOT/'.godot-local-profile';folder.mkdir(exist_ok=True)
        with tempfile.TemporaryDirectory(dir=folder) as directory:
            root=Path(directory);entries=bake_limits(root/'world',region,FlatField(),root,sea,settings)
            faces=[]
            for e in entries:
                mesh=np.fromfile(root/e['file'],dtype='<f4').reshape(-1,3,3).astype(float)[:e['visible_triangles_count']]
                mesh[:,:,0]+=e['origin_xz'][0];mesh[:,:,2]+=e['origin_xz'][1]
                faces.extend(Polygon(t[:,[0,2]]) for t in mesh)
            self.assertLess(abs(sum(p.area for p in faces)-unary_union(faces).area),.01)

if __name__=='__main__':unittest.main()

"""Physical geometry invariants for the real DEM pilot, independent of runtime queries."""
import math
import sys
import unittest
from pathlib import Path

import numpy as np
from shapely.geometry import Polygon, box, shape
from shapely.ops import unary_union

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
from relief_core import Elevation, HeightField, digest, read


class ReliefTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.path=ROOT/'data/processed/relief/pilot'
        cls.manifest=read(cls.path/'manifest.json')
        cls.grid=read(cls.path/'heightfield.json')
        cls.field=object.__new__(HeightField)
        cls.field.step=cls.grid['step_m']
        cls.field.x0,cls.field.z0=cls.grid['origin_xz']
        cls.field.nx=cls.grid['width'];cls.field.nz=cls.grid['depth']
        cls.field.values=np.fromfile(ROOT/cls.grid['heights_file'],dtype='<f4').reshape(cls.field.nz,cls.field.nx).astype(float)
        cls.field.quality=np.fromfile(ROOT/cls.grid['quality_file'],dtype='uint8').reshape(cls.field.nz,cls.field.nx)

    def meshes(self,kind):
        for e in self.manifest[kind]:
            self.assertEqual(digest(ROOT/e['file']),e['sha256'])
            a=np.fromfile(ROOT/e['file'],dtype='<f4').reshape(-1,3,3).astype(float)
            a[:,:,0]+=e['origin_xz'][0];a[:,:,2]+=e['origin_xz'][1]
            yield e,a

    def test_verified_source_and_no_missing_pilot_samples(self):
        meta=self.manifest['source_metadata']
        self.assertEqual(meta['version']['version'],'4.0')
        self.assertEqual(digest(ROOT/'data/raw/elevation/cem4_la_paz.tif'),meta['sha256'])
        dem=Elevation(ROOT/'data/raw/elevation/cem4_la_paz.tif',(24.159,-110.3195))
        self.assertEqual(dem.profile['crs'],'EPSG:4326')
        self.assertIsNone(dem.sample(999999,0))
        self.assertEqual(self.field.quality.sum(),0)
        for x,z in [(1749,-1921),(1680,-1828),(1800,-1600)]:
            self.assertIsNotNone(dem.sample(x,z,False))
            self.assertLess(abs(self.field.height(x,z)-dem.sample(x,z)),1)

    def test_canonical_triangle_interpolation(self):
        field=object.__new__(HeightField)
        field.step=8;field.x0=0;field.z0=0;field.nx=2;field.nz=2
        field.values=np.array([[0,8],[16,32]])
        self.assertEqual(field.height(6,2),12)
        self.assertEqual(field.height(2,6),16)
        self.assertEqual(field.height(8,8),32)
        with self.assertRaises(ValueError):field.height(-1,0)

    def test_road_and_ground_share_identical_surface(self):
        max_error=0
        for kind in ['roads','terrain']:
            for _,faces in self.meshes(kind):
                self.assertTrue(np.isfinite(faces).all())
                for p in faces.reshape(-1,3):
                    max_error=max(max_error,abs(p[1]-self.field.height(p[0],p[2])))
                # An interior sample catches triangles accidentally bridging grid diagonals.
                for tri in faces[::13]:
                    center=tri.mean(axis=0)
                    self.assertLess(abs(center[1]-self.field.height(center[0],center[2])),.001)
        self.assertLess(max_error,.0001)

    def test_partition_coverage_and_shared_sector_edges(self):
        all_polys=[];seams={}
        for kind in ['roads','terrain']:
            for e,faces in self.meshes(kind):
                x0,z0=e['origin_xz']
                for tri in faces:
                    all_polys.append(Polygon([(p[0],p[2]) for p in tri]))
                    for p in tri:
                        for axis,edges in [(0,[x0,x0+256]),(2,[z0,z0+256])]:
                            for boundary in edges:
                                if abs(p[axis]-boundary)<1e-5:
                                    key=(axis,boundary)
                                    seams.setdefault(key,{}).setdefault(e['id'],set()).add(tuple(round(v,4) for v in p))
        total=sum(p.area for p in all_polys)
        joined=unary_union(all_polys)
        sea=shape(read(ROOT/'data/processed/urban/urban_geography.json')['water_geometry_xz'])
        region=shape(self.manifest['region_geojson']).difference(sea)
        self.assertLess(total-joined.area,.05)
        # Actual clipped block region, not its enclosing rectangle.
        self.assertLess(region.symmetric_difference(joined).area,.1)
        compared=0
        for (axis,_),cells in seams.items():
            ids=list(cells)
            for i,a in enumerate(ids):
                for b in ids[i+1:]:
                    # Compare edge interval shared by adjacent chunks, excluding corner-only contacts.
                    ax,az=map(int,a.split('_'));bx,bz=map(int,b.split('_'))
                    if (axis==0 and abs(ax-bx)==1 and az==bz) or (axis==2 and abs(az-bz)==1 and ax==bx):
                        self.assertEqual(cells[a],cells[b]);compared+=1
        self.assertGreaterEqual(compared,6)

    def test_level_buildings_preserve_roofs_and_courtyards(self):
        manifest=read(self.path/'urban/city_manifest.json')
        count=0
        for entry in manifest['chunks']:
            path=self.path/'urban'/entry['file']
            self.assertEqual(digest(path),entry['sha256'])
            for b in read(path)['buildings']:
                self.assertGreater(b['height_m'],0)
                self.assertGreaterEqual(b['base_y_m'],b['foundation_min_y_m'])
                for ring in [b['footprint_xz']]+b.get('holes_xz',[]):
                    for x,z in ring:
                        self.assertLessEqual(self.field.height(x,z),b['base_y_m']+.001)
                footprint=Polygon(b['footprint_xz'],b.get('holes_xz',[]))
                roof=unary_union([Polygon(t) for t in b['roof_triangles_xz']])
                self.assertLess(footprint.symmetric_difference(roof).area,.001)
                count+=1
        self.assertEqual(count,self.manifest['statistics']['buildings'])


if __name__=='__main__':unittest.main()

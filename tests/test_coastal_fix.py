"""User-directed fictional water and local mountain setback invariants."""
import json
from pathlib import Path
import sys
import unittest
from shapely.geometry import shape,box,Point

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
from relief_regions import apply_boundary_outsets

class CoastalFixTests(unittest.TestCase):
    def test_requested_aerial_cells_are_water(self):
        before=json.loads((ROOT/'docs/coast_fix_baseline/relief_manifest.json').read_text(encoding='utf-8'))
        b=before['bounds_xz'];w=max(b[2]-b[0],(b[3]-b[1])*2/3)*1.12;h=w*1.5
        left=(b[0]+b[2])/2-w/2;top=(b[1]+b[3])/2-h/2
        sea=shape(json.loads((ROOT/'data/processed/urban/urban_geography.json').read_text(encoding='utf-8'))['water_geometry_xz'])
        for col,row in [(0,0),(0,1),(1,0)]:
            cell=box(left+col*w/4,top+(100+row*3640/6)*h/3840,left+(col+1)*w/4,top+(100+(row+1)*3640/6)*h/3840)
            self.assertLess(cell.difference(sea).area,.001)
        self.assertTrue(sea.covers(Point(-2800,900)))
        self.assertFalse(sea.covers(Point(-2400,1900)))

    def test_local_outset_preserves_interior_and_tapers(self):
        original=box(0,0,1000,1000)
        expanded=apply_boundary_outsets(original,[{'center_xz':[1000,500],'radius_m':200,'outset_m':60}])
        self.assertLess(original.difference(expanded).area,1e-8)
        self.assertTrue(expanded.covers(Point(1030,500)))
        self.assertFalse(expanded.covers(Point(1070,500)))
        self.assertFalse(expanded.covers(Point(1010,50)))
        self.assertEqual(expanded.wkb,apply_boundary_outsets(original,[{'center_xz':[1000,500],'radius_m':200,'outset_m':60}]).wkb)

if __name__=='__main__':unittest.main()

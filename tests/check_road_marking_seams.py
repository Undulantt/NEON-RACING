"""Independent check of painted intervals at shared sector boundaries."""
import json
from pathlib import Path
import shapely
from shapely.geometry import Polygon, LineString
ROOT = Path(__file__).resolve().parents[1]
source = ROOT / ".godot-local-profile/road_markings"
manifest = json.loads((source / "manifest.json").read_text(encoding="utf-8"))
regions = {}
for name in manifest["tiles"]:
    x, z = map(int, name.split("_"))
    polygons = json.loads((source / (name+".json")).read_text(encoding="utf-8"))
    regions[x,z] = shapely.union_all([Polygon([(p[0]+x*256,p[1]+z*256) for p in ring]) for ring in polygons])
checked, mismatches = 0, []
for (x,z), area in regions.items():
    for dx,dz in [(1,0),(0,1)]:
        other = regions.get((x+dx,z+dz))
        if other is None: continue
        edge = LineString([((x+1)*256,z*256+.001),((x+1)*256,(z+1)*256-.001)]) if dx else LineString([(x*256+.001,(z+1)*256),((x+1)*256-.001,(z+1)*256)])
        a, b = area.intersection(edge), other.intersection(edge)
        if a.is_empty and b.is_empty: continue
        checked += 1
        if abs(a.length-b.length) > .0001:
            mismatches.append({"cell":[x,z],"neighbor":[x+dx,z+dz],"difference_m":abs(a.length-b.length)})
report = {"checked_painted_seams":checked,"mismatches":mismatches,"passed":not mismatches,"tolerance_m":.0001}
(ROOT / "docs/phase_e_marking_seams.json").write_text(json.dumps(report,indent=2),encoding="utf-8")
print(report)
raise SystemExit(0 if report["passed"] else 1)

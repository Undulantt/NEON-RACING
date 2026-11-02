"""Build continuous cosmetic lane paint offline, before splitting into sectors."""
import hashlib, json, math
from collections import defaultdict
from pathlib import Path
import shapely
from shapely.geometry import LineString, Point, box
from shapely.ops import linemerge, substring
ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / ".godot-local-profile/road_markings"

def parts(g, kind):
    if g.is_empty: return []
    if g.geom_type == kind: return [g]
    return [p for child in getattr(g, "geoms", []) for p in parts(child, kind)]

def generate():
    OUT.mkdir(parents=True, exist_ok=True)
    data = json.loads((ROOT / "data/processed/la_paz_map.json").read_text(encoding="utf-8"))
    layout = json.loads((ROOT / "data/processed/arcade_layout.json").read_text(encoding="utf-8"))
    relief = json.loads((ROOT / "data/processed/relief/world/manifest.json").read_text(encoding="utf-8"))
    groups, neighbors, nodes, widths = defaultdict(dict), defaultdict(set), {}, defaultdict(float)
    for r in data["roads"]:
        if r.get("highway") in ("footway", "path", "steps", "cycleway", "track", "service"): continue
        coords = tuple(tuple(p) for p in r["points_xz"])
        width = float(layout["widths_m"][r["id"]])
        lanes = max(1, min(6, int(r.get("lanes") or 2)))
        one_way = bool(r.get("oneway", False))
        # Keep carriageways separate by connectivity; a shared name alone never joins them.
        name = r.get("street_name") or str(r["osm_way_id"])
        key = (name, round(width, 2), lanes, one_way)
        canonical = min(coords, coords[::-1])
        groups[key][canonical] = LineString(canonical)
        a, b = str(r["from"]), str(r["to"])
        neighbors[a].add(b); neighbors[b].add(a)
        nodes[a], nodes[b] = coords[0], coords[-1]
        widths[a] = max(widths[a], width); widths[b] = max(widths[b], width)
    junctions = [Point(nodes[n]).buffer(max(4, widths[n] * .55), quad_segs=4) for n in neighbors if len(neighbors[n]) >= 3]
    junction_tree = shapely.STRtree(junctions) if junctions else None
    strokes, counts = [], {"chains": 0, "one_way_chains": 0, "junctions": len(junctions), "dashes": 0}
    for key, unique in sorted(groups.items()):
        _, width, lanes, one_way = key
        chains = parts(linemerge(list(unique.values())), "LineString")
        for chain in chains:
            if chain.length < 2: continue
            counts["chains"] += 1
            counts["one_way_chains"] += int(one_way)
            offsets = []
            if not one_way and lanes >= 2:
                offsets.extend([(-.16, False), (.16, False)])
            for lane in range(1, lanes):
                offset = -width*.5 + width*lane/lanes
                if not one_way and abs(offset) < .35: continue
                offsets.append((offset, True))
            for offset, dashed in offsets:
                curve = chain.offset_curve(offset, join_style="round", quad_segs=3)
                for line in parts(curve, "LineString"):
                    # Arc length is defined on the whole chain, never reset at tile borders.
                    pieces = [line] if not dashed else [substring(line, d, min(d+3.5, line.length)) for d in range(0, math.ceil(line.length), 8) if line.length-d > .15]
                    for piece in pieces:
                        if not isinstance(piece, LineString): continue
                        stroke = piece.buffer(.09, cap_style="flat", join_style="round", quad_segs=3)
                        if junction_tree is not None:
                            ids = junction_tree.query(stroke)
                            if len(ids): stroke = stroke.difference(shapely.union_all([junctions[int(i)] for i in ids]))
                        if not stroke.is_empty:
                            strokes.append(stroke)
                            counts["dashes"] += int(dashed)
    tree = shapely.STRtree(strokes)
    tiles = {}
    for entry in relief["roads"]:
        x, z = entry["origin_xz"]
        tile = box(x, z, x+256, z+256)
        polygons = []
        for i in tree.query(tile):
            for poly in parts(strokes[int(i)].intersection(tile), "Polygon"):
                if poly.area < .00001: continue
                pieces = parts(shapely.constrained_delaunay_triangles(poly), "Polygon") if poly.interiors else [poly]
                for piece in pieces:
                    polygons.append([[round(px-x, 6), round(pz-z, 6)] for px, pz in list(piece.exterior.coords)[:-1]])
        path = OUT / (entry["id"] + ".json")
        path.write_text(json.dumps(polygons, separators=(",", ":")), encoding="utf-8")
        tiles[entry["id"]] = {"polygons": len(polygons)}
    report = {"version": 1, "map_sha256": hashlib.sha256((ROOT / "data/processed/la_paz_map.json").read_bytes()).hexdigest(), "layout_sha256": hashlib.sha256((ROOT / "data/processed/arcade_layout.json").read_bytes()).hexdigest(), "counts": counts, "tiles": tiles}
    (OUT / "manifest.json").write_text(json.dumps(report), encoding="utf-8")
    print(json.dumps({"tiles": len(tiles), **counts}))
if __name__ == "__main__": generate()

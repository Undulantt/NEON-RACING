"""Derive wider playable asphalt and matching facade shells, preserving source files."""
import hashlib
import json
import math
from pathlib import Path
from shapely.geometry import LineString, Polygon, box
from shapely.geometry.polygon import orient
from shapely.ops import unary_union
from shapely import constrained_delaunay_triangles
from shapely.strtree import STRtree
from shapely.prepared import prep

ROOT = Path(__file__).resolve().parents[1]

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def read(path):
    return json.loads(path.read_text(encoding="utf-8"))

def triangles(geometry):
    parts = [geometry] if geometry.geom_type == "Polygon" else list(getattr(geometry, "geoms", []))
    return [[list(p) for p in list(t.exterior.coords)[:3]] for part in parts if part.geom_type == "Polygon" for t in constrained_delaunay_triangles(part).geoms if t.area > 1e-8]

def build():
    config_path = ROOT / "config/arcade_roads.json"
    cfg = read(config_path)
    for key in ("width_multiplier", "minimum_width_m", "building_clearance_m"):
        if not isinstance(cfg[key], (int, float)) or not math.isfinite(cfg[key]) or cfg[key] <= 0:
            raise ValueError("Invalid arcade road setting: " + key)
    if cfg["width_multiplier"] < 1:
        raise ValueError("Arcade streets must not shrink source roads")
    map_path = ROOT / "data/processed/la_paz_map.json"
    city_path = ROOT / "data/processed/urban/city_manifest.json"
    data, city = read(map_path), read(city_path)
    widths = {r["id"]: max(r["width_m"] * cfg["width_multiplier"], cfg["minimum_width_m"]) for r in data["roads"]}
    asphalt = unary_union([LineString(r["points_xz"]).buffer(widths[r["id"]] / 2, quad_segs=4, cap_style="round", join_style="mitre", mitre_limit=2) for r in data["roads"]])
    original = unary_union([LineString(r["points_xz"]).buffer(r["width_m"] / 2, quad_segs=4, cap_style="round", join_style="mitre", mitre_limit=2) for r in data["roads"]])
    from expansion_regions import metric_clip
    user_clip = metric_clip(read(ROOT / "config/map_config.json"))
    if user_clip is not None:
        asphalt = asphalt.intersection(user_clip)
        original = original.intersection(user_clip)
    clearance = asphalt.buffer(cfg["building_clearance_m"])
    clearance_prepared = prep(clearance)
    asphalt_prepared = prep(asphalt)
    clearance_tiles = []
    a,b,c,d = clearance.bounds
    for x in range(math.floor(a / 256), math.floor(c / 256) + 1):
        for z in range(math.floor(b / 256), math.floor(d / 256) + 1):
            part = clearance.intersection(box(x*256,z*256,(x+1)*256,(z+1)*256))
            if not part.is_empty: clearance_tiles.append(part)
    clearance_tree = STRtree(clearance_tiles)
    chunks = []
    size = read(ROOT / "config/map_config.json")["chunk_size_m"]
    x0, z0, x1, z1 = asphalt.bounds
    for cx in range(math.floor(x0 / size), math.floor(x1 / size) + 1):
        for cz in range(math.floor(z0 / size), math.floor(z1 / size) + 1):
            tile = asphalt.intersection(box(cx * size, cz * size, (cx + 1) * size, (cz + 1) * size))
            faces = triangles(tile)
            if faces:
                chunks.append({"id": f"{cx}_{cz}", "origin_xz": [cx * size, cz * size], "triangles_xz": [[[x - cx * size, z - cz * size] for x, z in face] for face in faces]})
    chunk_overrides = {}
    override_dir = ROOT / "data/processed/arcade/chunks"
    override_dir.mkdir(parents=True, exist_ok=True)
    adjusted = removed = total = 0
    max_overlap = 0.0
    for entry in city["chunks"]:
        overrides = {}
        path = city_path.parent / entry["file"]
        if digest(path) != entry["sha256"]:
            raise ValueError("Stale city chunk: " + str(path))
        for building in read(path)["buildings"]:
            total += 1
            polygon = Polygon(building["footprint_xz"], building.get("holes_xz", []))
            if not clearance_prepared.intersects(polygon):
                continue
            local_clearance = unary_union([clearance_tiles[int(i)] for i in clearance_tree.query(polygon)])
            clipped = polygon.difference(local_clearance)
            parts = [clipped] if clipped.geom_type == "Polygon" else [p for p in getattr(clipped, "geoms", []) if p.geom_type == "Polygon"]
            parts = [p for p in parts if p.area >= 6.0]
            if not parts:
                overrides[building["id"]] = {"disabled": True}
                removed += 1
                continue
            # Retain the largest part; never reconnect split pieces across a street.
            kept = orient(max(parts, key=lambda p: p.area), sign=1)
            overrides[building["id"]] = {"footprint_xz": list(kept.exterior.coords)[:-1], "holes_xz": [list(r.coords)[:-1] for r in kept.interiors], "roof_triangles_xz": triangles(kept), "arcade_adjusted": True}
            adjusted += 1
            if asphalt_prepared.intersects(kept):
                max_overlap = max(max_overlap, kept.intersection(asphalt).area)
        if overrides:
            override_path = override_dir / (entry["id"] + ".json")
            override_path.write_text(json.dumps(overrides,ensure_ascii=False,separators=(",", ":")),encoding="utf-8",newline="\n")
            chunk_overrides[entry["id"]] = {"file":str(override_path.relative_to(ROOT)).replace("\\", "/"),"sha256":digest(override_path),"buildings":len(overrides)}
    surface_area = sum(Polygon([(x + c["origin_xz"][0], z + c["origin_xz"][1]) for x, z in t]).area for c in chunks for t in c["triangles_xz"])
    if abs(surface_area - asphalt.area) > 0.01 or max_overlap > 1e-6 or original.difference(asphalt).area > 0.01:
        raise ValueError("Arcade layout coverage/clearance validation failed")
    stats = {"source_asphalt_area_m2": original.area, "arcade_asphalt_area_m2": asphalt.area, "buildings_total": total, "buildings_adjusted": adjusted, "buildings_removed": removed, "max_adjusted_building_overlap_m2": max_overlap, "triangulation_error_m2": abs(surface_area - asphalt.area)}
    output = {"schema_version": 1, "map_sha256": digest(map_path), "city_sha256": digest(city_path), "config_sha256": digest(config_path), "settings": cfg, "widths_m": widths, "chunks": chunks, "building_overrides": {}, "chunk_overrides": chunk_overrides, "statistics": stats, "note": "Arcade adaptation: real centerlines preserved, widened asphalt, facade clipping. Not surveyed street widths."}
    destination = ROOT / "data/processed/arcade_layout.json"
    destination.write_text(json.dumps(output, ensure_ascii=False, separators=(",", ":"), allow_nan=False), encoding="utf-8", newline="\n")
    print(json.dumps(stats, indent=2))
    return output

if __name__ == "__main__":
    build()

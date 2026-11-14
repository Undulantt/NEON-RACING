"""Offline research inventory. Writes only docs/sf3_urban_evidence.json.

Counts source records, not completeness of the city. Uses existing Shapely.
OSM ways are intersected as lines (not inferred filled areas); relations use
available members and report incompleteness. No game assets are generated.
"""
import hashlib
import json
import xml.etree.ElementTree as ET
from collections import Counter, defaultdict
from pathlib import Path

from shapely.geometry import Point, LineString, shape
from shapely.ops import unary_union
from expansion_regions import region_lonlat

ROOT = Path(__file__).resolve().parents[1]


def read(path):
    return json.loads((ROOT / path).read_text(encoding="utf-8"))


def digest(path):
    return hashlib.sha256((ROOT / path).read_bytes()).hexdigest()


def categories(t):
    found = []
    rules = {
        "sidewalk_attribute": any(k == "sidewalk" or k.startswith("sidewalk:") for k in t),
        "sidewalk_geometry": t.get("highway") == "footway" and t.get("footway") == "sidewalk",
        "crossing": t.get("highway") == "crossing" or t.get("footway") == "crossing",
        "traffic_signals": t.get("highway") == "traffic_signals",
        "traffic_sign": "traffic_sign" in t or t.get("highway") in ("stop", "give_way", "traffic_sign"),
        "median_explicit": t.get("area:highway") == "traffic_island" or "median" in t or t.get("traffic_calming") == "island",
        "parking": t.get("amenity") in ("parking", "parking_space", "parking_entrance"),
        "parking_attribute": any(k.startswith("parking:") for k in t),
        "street_lamp": t.get("highway") == "street_lamp" or t.get("man_made") == "street_lamp",
        "lit_attribute": "lit" in t,
        "barrier": "barrier" in t and t["barrier"] != "no",
        "bench": t.get("amenity") == "bench",
        "tree": t.get("natural") == "tree",
        "palm_explicit": t.get("natural") == "tree" and any(v in " ".join(t.values()).lower() for v in ("palm", "arecaceae", "washingtonia", "phoenix")),
        "tree_row": t.get("natural") == "tree_row",
        "park_garden": t.get("leisure") in ("park", "garden"),
        "green_area": t.get("landuse") in ("grass", "forest", "recreation_ground", "village_green") or t.get("natural") in ("wood", "scrub"),
        "square": t.get("place") == "square",
        "pedestrian": t.get("highway") in ("pedestrian", "footway", "path", "steps"),
        "beach": t.get("natural") == "beach",
        "coastline": t.get("natural") == "coastline",
        "building": t.get("building") not in (None, "no"),
        "building_height": t.get("building") not in (None, "no") and "height" in t,
        "building_levels": t.get("building") not in (None, "no") and "building:levels" in t,
        "building_appearance": t.get("building") not in (None, "no") and any(k in t for k in ("building:colour", "building:material", "roof:colour", "roof:material", "roof:shape", "building:architecture")),
        "shop": "shop" in t and t["shop"] != "no",
        "food": t.get("amenity") in ("restaurant", "cafe", "fast_food", "bar", "pub"),
        "hotel": t.get("tourism") in ("hotel", "motel", "hostel", "guest_house"),
        "public_cultural": t.get("amenity") in ("school", "university", "college", "hospital", "clinic", "police", "townhall", "library", "theatre", "arts_centre", "place_of_worship") or t.get("office") == "government" or t.get("tourism") in ("museum", "gallery"),
        "monument": t.get("historic") in ("monument", "memorial"),
        "artwork": t.get("tourism") == "artwork",
        "tourist_attraction": t.get("tourism") in ("attraction", "viewpoint", "information"),
        "malecon_named": "malec" in t.get("name", "").lower(),
    }
    for key, valid in rules.items():
        if valid:
            found.append(key)
    return found, rules


def main():
    cfg = read("config/map_config.json")
    # Buildings use visual envelope + user clip; roads use active blocks + clip.
    domains = {"visual": region_lonlat({**cfg, "active_blocks": {"envelope": cfg["bbox"]}}), "roads": region_lonlat(cfg)}
    manifest = read("data/processed/urban/city_manifest.json")
    osm_path = "data/raw/osm_map_c6_boundary_expansion.osm"
    paths = ["config/map_config.json", osm_path, "data/processed/urban/city_manifest.json", "data/processed/la_paz_map.json", "data/processed/arcade_layout.json", "data/processed/urban/urban_enrichment.json", "data/processed/urban/landmarks.json"]
    paths += ["data/raw/" + manifest["metadata"]["sources"][k]["file"] for k in ("overture_buildings", "inegi_blocks")]
    paths += ["data/raw/overture_places_20261021.geojson", "data/raw/denue_03_csv.zip"]
    paths += ["data/processed/urban/" + c["file"] for c in manifest["chunks"]]
    arcade = read("data/processed/arcade_layout.json")
    paths += [v["file"] for v in arcade["chunk_overrides"].values()]
    before = {p: digest(p) for p in paths}
    assert before["data/processed/la_paz_map.json"] == manifest["map_sha256"]
    for kind in ("overture_buildings", "inegi_blocks"):
        source = manifest["metadata"]["sources"][kind]
        assert before["data/raw/" + source["file"]] == source["sha256"]
    assert before[osm_path] == manifest["metadata"]["sources"]["osm_protected"]["original_sha256"]
    elements = {(e.tag, e.attrib["id"]): e for e in ET.parse(ROOT / osm_path).getroot() if e.tag in ("node", "way", "relation")}
    geometries = {}
    missing_members = Counter()

    def geometry(key, visiting=None):
        if key in geometries:
            return geometries[key]
        visiting = set() if visiting is None else visiting
        if key in visiting or key not in elements:
            return None
        visiting = visiting | {key}
        e = elements[key]
        if key[0] == "node":
            g = Point(float(e.attrib["lon"]), float(e.attrib["lat"]))
        elif key[0] == "way":
            refs = [("node", n.attrib["ref"]) for n in e.findall("nd")]
            pts = [geometry(n, visiting) for n in refs]
            if len(pts) < 2 or any(p is None for p in pts):
                missing_members[key[0]] += 1
                g = None
            else:
                g = LineString([(p.x, p.y) for p in pts])
        else:
            parts = [geometry((n.attrib["type"], n.attrib["ref"]), visiting) for n in e.findall("member")]
            if any(p is None for p in parts):
                missing_members[key[0]] += 1
            g = unary_union([p for p in parts if p is not None]) if parts else None
        geometries[key] = g
        return g

    counts = {d: defaultdict(Counter) for d in domains}
    examples = defaultdict(list)
    _, rules = categories({})
    unresolved = Counter()
    for key, e in elements.items():
        tags = {t.attrib["k"]: t.attrib["v"] for t in e.findall("tag")}
        cats, _ = categories(tags)
        if not cats:
            continue
        g = geometry(key)
        if g is None or g.is_empty:
            unresolved.update(cats)
            continue
        for domain, mask in domains.items():
            if not mask.intersects(g):
                continue
            for cat in cats:
                counts[domain][cat][key[0]] += 1
                if domain == "visual" and len(examples[cat]) < 3:
                    p = g.intersection(mask).representative_point()
                    examples[cat].append({"id": f"osm:{key[0]}:{key[1]}", "lat": p.y, "lon": p.x, "position_method": "source point" if key[0] == "node" else "derived representative point on available geometry; not an entrance", "tags": tags})
    osm = {"counts": {d: {k: dict(counts[d][k]) for k in rules} for d in domains}, "examples": dict(examples), "unresolved_category_records": dict(unresolved), "incomplete_geometry_by_type": dict(missing_members), "unique_elements_by_type": dict(Counter(k[0] for k in elements))}
    geojson = {}
    for name, path in [("overture_buildings", "data/raw/" + manifest["metadata"]["sources"]["overture_buildings"]["file"]), ("inegi_blocks", "data/raw/" + manifest["metadata"]["sources"]["inegi_blocks"]["file"]), ("overture_places", "data/raw/overture_places_20261021.geojson")]:
        features = read(path)["features"]
        info = {"file_records": len(features), "domains": {}}
        for domain, mask in domains.items():
            subset = [f for f in features if f.get("geometry") and mask.intersects(shape(f["geometry"]))]
            attrs = Counter(k for f in subset for k, v in f.get("properties", {}).items() if v is not None and v != "" and v != [])
            sources = Counter(s.get("dataset", "unknown") for f in subset for s in f.get("properties", {}).get("sources", []) if s.get("property", "") == "")
            info["domains"][domain] = {"records": len(subset), "nonnull_attributes": dict(sorted(attrs.items())), "primary_source_records": dict(sources)}
        geojson[name] = info
    prepared = []
    for c in manifest["chunks"]:
        path = "data/processed/urban/" + c["file"]
        assert digest(path) == c["sha256"], path
        prepared.extend(read(path)["buildings"])
    assert len({b["id"] for b in prepared}) == len(prepared)
    overrides = dict(arcade.get("building_overrides", {}))
    for v in arcade["chunk_overrides"].values():
        assert digest(v["file"]) == v["sha256"], v["file"]
        overrides.update(read(v["file"]))
    effective = [b for b in prepared if not overrides.get(b["id"], {}).get("disabled", False)]
    def building_stats(rows):
        return {"records": len(rows), "sources": dict(Counter(b["source_kind"] for b in rows)), "categories": dict(Counter(b.get("category", "unknown") for b in rows)), "height_estimated": sum(bool(b.get("height_estimated")) for b in rows), "height_sources": dict(Counter(b.get("height_source", "unspecified") for b in rows)), "floor_source_present": sum(b.get("num_floors_source") is not None for b in rows), "fictional": sum(bool(b.get("fictional")) for b in rows)}
    enrichment = read("data/processed/urban/urban_enrichment.json")
    pois = enrichment["pois"]
    poi_counts = {d: dict(Counter(p["source"].get("kind", "osm") for p in pois if mask.covers(Point(p["lon"], p["lat"])))) for d, mask in domains.items()}
    report = {"scope": "Offline audit; no new geographic downloads. Snapshot records are not field verification or completeness estimates.", "bbox_south_west_north_east": cfg["bbox"], "domain_definition": {"visual": "bbox intersect user clip (city builder)", "roads": "union of active block polygons/bboxes intersect user clip (road importer)"}, "source_sha256": before, "osm": osm, "geojson": geojson, "buildings_prepared": building_stats(prepared), "buildings_effective_after_arcade": building_stats(effective), "arcade_statistics": arcade["statistics"], "poi_records_by_domain": poi_counts, "poi_statistics": enrichment["statistics"], "poi_association_reasons": dict(Counter(p.get("association_reason", "unspecified") for p in pois)), "poi_position_methods": dict(Counter(p.get("position_method", "unspecified") for p in pois)), "landmarks": read("data/processed/urban/landmarks.json")["landmarks"]}
    assert len(prepared) == manifest["statistics"]["buildings"]
    assert len(effective) == len(prepared) - arcade["statistics"]["buildings_removed"]
    assert len(pois) == sum(enrichment["statistics"]["records_by_source"].values())
    assert all(digest(p) == sha for p, sha in before.items()), "Research input modified"
    report["validation"] = {"input_files_unchanged": len(before), "sector_hashes_verified": len(manifest["chunks"]), "arcade_sector_hashes_verified": len(arcade["chunk_overrides"]), "counts_crosschecked": True}
    out = ROOT / "docs/sf3_urban_evidence.json"
    out.write_bytes((json.dumps(report, ensure_ascii=False, indent=2) + "\n").encode("utf-8"))
    print(json.dumps({"output": str(out), "buildings": report["buildings_effective_after_arcade"], "validation": report["validation"], "osm_visual": osm["counts"]["visual"], "geojson": geojson}, ensure_ascii=True, indent=2))


if __name__ == "__main__":
    main()

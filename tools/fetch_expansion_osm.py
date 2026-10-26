"""C.5: immutable OSM API tiles for active blocks; deterministic, audited merge."""
import argparse, copy, hashlib, json, math, time, urllib.request
import xml.etree.ElementTree as ET
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RAW = ROOT / "data/raw"

def read(p): return json.loads(p.read_text(encoding="utf-8"))
def digest(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def save_json(p, value): p.write_text(json.dumps(value, ensure_ascii=False, indent=2), encoding="utf-8", newline="\n")
def tags(e): return {t.attrib["k"]: t.attrib["v"] for t in e.findall("tag")}
def selected(t):
    return t.get("leisure") in ("park","garden","pitch","nature_reserve","playground","golf_course","sports_centre") or t.get("natural") in ("beach","water","wetland","sand","scrub","coastline") or t.get("landuse") in ("forest","grass","cemetery","recreation_ground","greenfield","farmland","orchard") or t.get("amenity") in ("parking","school","university","hospital","grave_yard") or t.get("place") == "square" or t.get("highway") in ("footway","path","cycleway","pedestrian","steps") or t.get("waterway") == "riverbank"

def fetch(offline=False):
    expansion = read(ROOT / "config/expansion_config.json")
    cfg = read(ROOT / "config/map_config.json")
    selection = expansion.get("source_selection", "c5_north")
    blocks = [expansion["blocks"][key]["bbox"] for key in expansion["active_blocks"]]
    bbox = [min(b[0] for b in blocks), min(b[1] for b in blocks), max(b[2] for b in blocks), max(b[3] for b in blocks)]
    snapshots = []
    # Reuse the verified original core XML: source nodes/way IDs join across tiles.
    core_meta = read(RAW / "osm_protected_20261024T221536Z.meta.json")
    core = RAW / core_meta["original_file"]
    if digest(core) != core_meta["original_sha256"]:
        raise ValueError("Core XML source hash mismatch")
    snapshots.append({"file": core.name, "sha256": digest(core), "scope": "existing core snapshot"})
    for key in expansion["active_blocks"]:
        if key == "core": continue
        south, west, north, east = expansion["blocks"][key]["bbox"]
        # Small overlap avoids incomplete ways at the active-block boundary.
        south -= .002; west -= .002; north += .002; east += .002
        limit = expansion["max_osm_tile_degrees"]
        nx, ny = math.ceil((east-west)/limit), math.ceil((north-south)/limit)
        for x in range(nx):
            for y in range(ny):
                tile = [south+(north-south)*y/ny, west+(east-west)*x/nx, south+(north-south)*(y+1)/ny, west+(east-west)*(x+1)/nx]
                token = hashlib.sha256(json.dumps(tile).encode()).hexdigest()[:12]
                path = RAW / f"osm_c5_{key}_{token}.osm"
                meta_path = path.with_suffix(".meta.json")
                url = "https://api.openstreetmap.org/api/0.6/map?bbox=" + ",".join(str(tile[i]) for i in (1,0,3,2))
                if path.exists() and meta_path.exists() and digest(path) == read(meta_path)["sha256"]:
                    meta = read(meta_path)
                    print("CACHE", path.name, flush=True)
                else:
                    if offline: raise ValueError("Missing verified offline tile: " + path.name)
                    last = None
                    for attempt in range(3):
                        try:
                            request = urllib.request.Request(url, headers={"User-Agent": "LaPazOfflinePrototype/0.5 (bounded city research extract)"})
                            with urllib.request.urlopen(request, timeout=90) as response:
                                raw = response.read()
                            tree = ET.fromstring(raw)
                            if tree.tag != "osm" or not tree.findall("way"): raise ValueError("Empty OSM tile")
                            path.write_bytes(raw)
                            meta = {"file":path.name,"sha256":digest(path),"bbox":tile,"url":url,"source":"OpenStreetMap contributors","license":"ODbL-1.0","extracted_at_utc":datetime.now(timezone.utc).isoformat()}
                            save_json(meta_path, meta)
                            print("DOWNLOADED", path.name, len(raw), flush=True)
                            break
                        except (OSError, ValueError, ET.ParseError) as exc:
                            last = exc
                            print("OSM RETRY", attempt + 1, str(exc), flush=True)
                            time.sleep(2 * (attempt+1))
                    else: raise RuntimeError("Could not fetch real OSM tile: " + str(last))
                    time.sleep(1)
                snapshots.append(meta)
    merged = {}
    versions = {}
    for source in snapshots:
        path = RAW / source["file"]
        if digest(path) != source["sha256"]: raise ValueError("OSM source changed")
        for element in ET.parse(path).getroot():
            if element.tag not in ("node","way","relation"): continue
            key = element.tag, element.attrib["id"]
            version = int(element.attrib.get("version", "0"))
            if key not in merged or version > versions[key]:
                merged[key] = copy.deepcopy(element)
                versions[key] = version
    output = ET.Element("osm", {"version":"0.6","generator":"LaPaz C.5 audited tile merge"})
    order = {"node":0,"way":1,"relation":2}
    for key in sorted(merged, key=lambda k:(order[k[0]],int(k[1]))): output.append(merged[key])
    xml = RAW / f"osm_map_{selection}.osm"
    ET.ElementTree(output).write(xml, encoding="utf-8", xml_declaration=True)
    nodes = {e.attrib["id"]:e for e in output.findall("node")}
    ways = {e.attrib["id"]:e for e in output.findall("way")}
    base = {"bbox":bbox,"source":"OpenStreetMap contributors","license":"ODbL-1.0","url":"https://api.openstreetmap.org/api/0.6/map","normalization":"Deterministic merge of immutable XML tiles; highest OSM version wins per type/id. Exact original responses retained.","original_file":xml.name,"original_sha256":digest(xml),"source_tiles":snapshots}
    source_elements = [{"type":"node","id":int(e.attrib["id"]),"lat":float(e.attrib["lat"]),"lon":float(e.attrib["lon"])} for e in nodes.values()]
    def geometry(w):
        refs = [n.attrib["ref"] for n in w.findall("nd")]
        return [{"lat":float(nodes[n].attrib["lat"]),"lon":float(nodes[n].attrib["lon"])} for n in refs] if all(n in nodes for n in refs) else []
    for kind, predicate in [("roads",lambda t:t.get("highway") in cfg["highways"]),("buildings",lambda t:t.get("building") not in (None,"no"))]:
        elements = list(source_elements)
        for w in ways.values():
            t = tags(w)
            if predicate(t): elements.append({"type":"way","id":int(w.attrib["id"]),"nodes":[int(n.attrib["ref"]) for n in w.findall("nd")],"tags":t})
        path = RAW / f"la_paz_{kind}_{selection}.json"
        path.write_text(json.dumps({"elements":elements},ensure_ascii=False,separators=(",", ":")),encoding="utf-8",newline="\n")
        meta = {**base,"file":path.name,"sha256":digest(path),"kind":kind}
        if kind == "roads": meta["highways"] = cfg["highways"]
        save_json(path.with_suffix(".meta.json"),meta)
    protected = []; omitted = []
    for e in output:
        t = tags(e)
        if not selected(t): continue
        record = {"type":e.tag,"id":int(e.attrib["id"]),"tags":t}
        if e.tag == "node": record.update(lat=float(e.attrib["lat"]),lon=float(e.attrib["lon"]))
        elif e.tag == "way": record["geometry"] = geometry(e)
        else:
            members=[]; complete=True
            for m in e.findall("member"):
                if m.attrib["type"] != "way": continue
                w=ways.get(m.attrib["ref"])
                if w is None or not geometry(w): complete=False; break
                members.append({"type":"way","ref":int(m.attrib["ref"]),"role":m.attrib.get("role",""),"geometry":geometry(w)})
            if not complete: omitted.append(record["id"]); continue
            record["members"]=members
        protected.append(record)
    path = RAW / f"osm_protected_{selection}.json"
    path.write_text(json.dumps({"elements":protected},ensure_ascii=False,separators=(",", ":")),encoding="utf-8",newline="\n")
    save_json(path.with_suffix(".meta.json"),{**base,"kind":"osm_protected","file":path.name,"sha256":digest(path),"element_count":len(protected),"incomplete_relations_omitted":omitted})
    print("C5 OSM READY",len(nodes),"nodes",len(ways),"ways",len(protected),"protected features",flush=True)

if __name__ == "__main__":
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--offline",action="store_true",help="Normalize verified cached XML tiles only; never download")
    fetch(parser.parse_args().offline)

"""Regenerate the active La Paz blocks; network access only with --fetch."""
import argparse, json, subprocess, sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]

def read(path): return json.loads(path.read_text(encoding="utf-8"))
def write(path,data): path.write_text(json.dumps(data,ensure_ascii=False,indent=2)+"\n",encoding="utf-8",newline="\n")
def run(script,*args): subprocess.run([sys.executable,str(ROOT/"tools"/script),*args],cwd=ROOT,check=True)

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--fetch",action="store_true",help="Download missing verified OSM tiles and Overture buildings")
    args=parser.parse_args()
    profile=read(ROOT/"config/expansion_config.json")
    cfg=read(ROOT/"config/map_config.json")
    selection=profile.get("source_selection", "c5_north")
    blocks={key:profile["blocks"][key]["bbox"] for key in profile["active_blocks"]}
    areas=list(blocks.values())
    cfg.update(active_blocks=blocks,bbox=[min(b[0] for b in areas),min(b[1] for b in areas),max(b[2] for b in areas),max(b[3] for b in areas)],origin_lat=profile["origin_lat"],origin_lon=profile["origin_lon"])
    cfg["road_import_policy"]=profile.get("road_import_policy", {})
    cfg["block_polygons_lonlat"]=profile.get("block_polygons_lonlat", {})
    if profile.get("preserved_sea_file"):
        cfg["preserved_sea_file"]=profile["preserved_sea_file"]
    if profile.get("clip_polygon_lonlat"):
        cfg["clip_polygon_lonlat"]=profile["clip_polygon_lonlat"]
    else:
        cfg.pop("clip_polygon_lonlat",None)
    write(ROOT/"config/map_config.json",cfg)
    urban=read(ROOT/"config/urban_config.json");urban.update(profile["streaming"])
    if cfg["chunk_size_m"] != 256 or urban["chunk_size_m"] != 256:
        raise ValueError("C.5 streaming uses an aligned 256m sector grid for roads and buildings")
    write(ROOT/"config/urban_config.json",urban)
    # Existing INEGI locality/state sources cover the larger selection. Keep their
    # exact bytes and original metadata; derive only a new selection manifest.
    for original,destination in [("inegi_blocks_20261024T220934Z.meta.json",f"inegi_blocks_{selection}.meta.json"),("denue_03_csv.meta.json",f"denue_{selection}.meta.json")]:
        meta=read(ROOT/"data/raw"/original)
        meta.update(prior_selection_bbox=meta["bbox"],bbox=cfg["bbox"],selection_note="Same immutable full-locality/full-state source, reselected for C.5 blocks; not a new download.",prior_metadata_file=original)
        write(ROOT/"data/raw"/destination,meta)
    enrichment=read(ROOT/"config/urban_enrichment.json")
    enrichment["sources"]["denue"]["metadata_file"]=f"denue_{selection}.meta.json"
    write(ROOT/"config/urban_enrichment.json",enrichment)
    if args.fetch:
        run("fetch_expansion_osm.py")
        run("fetch_urban_sources.py","overture")
    for script in ["build_map.py","build_environment.py","build_urban_city.py","build_arcade_layout.py","build_expansion_routes.py","validate_map.py"]:
        run(script)
    from validate_urban_city import validate as validate_city
    from validate_urban_enrichment import validate as validate_geography
    report={"urban":validate_city(),"geography":validate_geography()}
    write(ROOT/"docs/phase_c5_data_validation.json",report)
    print("C5 BUILD VERIFIED",flush=True)

if __name__=="__main__": main()

"""C.5 active block manifest and real directed route candidates; no race logic."""
import json, math, hashlib
from pathlib import Path
from shapely.geometry import Point, Polygon
from expansion_regions import metric_region
from map_core import gps_to_local, dijkstra

ROOT = Path(__file__).resolve().parents[1]
def read(p): return json.loads(p.read_text(encoding="utf-8"))
def digest(p): return hashlib.sha256(p.read_bytes()).hexdigest()

def route(data, identifier, name, waypoints):
    road_by_id={r["id"]:r for r in data["roads"]}
    edge_ids=[]; sequence=[waypoints[0]]; length=0; points=[]
    for start,end in zip(waypoints,waypoints[1:]):
        distances,previous=dijkstra(data,start)
        if end not in distances: raise ValueError("No real directed connection for " + name)
        part=[]; node=end
        while node!=start:
            edge=previous[node]; part.append(edge); node=edge["from"]
        for edge in reversed(part):
            edge_ids.append(edge["id"]); sequence.append(edge["to"]); length+=edge["length_m"]
            geometry=road_by_id[edge["road_id"]]["points_xz"]
            if edge["reverse"]: geometry=list(reversed(geometry))
            points.extend(geometry if not points else geometry[1:])
    return {"id":identifier,"name":name,"purpose":"future fictional race candidate and production driving validation only","edge_ids":edge_ids,"node_ids":sequence,"points_xz":points,"length_m":length,"street_names":sorted({road_by_id[e.rsplit(":",1)[0]]["street_name"] for e in edge_ids})}

def build():
    cfg=read(ROOT/"config/map_config.json"); settings=read(ROOT/"config/expansion_config.json")
    data=read(ROOT/"data/processed/la_paz_map.json")
    spawn=settings["core_spawn"]["position_xz"]
    start=min(data["nodes"],key=lambda n:math.dist([n["x"],n["z"]],spawn))["id"]
    distances,_=dijkstra(data,start)
    # Approximate locality reference points, snapped only to actual reachable OSM nodes.
    # They are not surveyed neighborhood boundaries or fabricated roads.
    references=[("esterito","Esterito",24.1695,-110.3075),("colina_del_sol","Colina del Sol",24.1724,-110.3006),("pedregal_del_cortez","Pedregal del Cortez",24.1714,-110.29025)]
    if "south" in settings["active_blocks"]:
        references.extend([("hospital_salvatierra","Área hospitalaria Salvatierra",24.11237,-110.31907),("uabcs","Zona UABCS — avenida de acceso",24.1046213,-110.3191762),("conexion_sur","Conexión vial sur",*settings.get("south_connection_reference",[24.093,-110.313]))])
    anchors=[]
    for key,name,lat,lon in references:
        x,z=gps_to_local(lat,lon,cfg["origin_lat"],cfg["origin_lon"])
        node=min((n for n in data["nodes"] if n["id"] in distances and not n["boundary_generated"]),key=lambda n:math.dist([n["x"],n["z"]],[x,z]))
        offset=math.dist([node["x"],node["z"]],[x,z])
        if offset>350: raise ValueError("Locality reference too far from real connected network: "+name)
        anchors.append({"id":key,"name":name,"reference_latlon":[lat,lon],"node_id":node["id"],"position_xz":[node["x"],node["z"]],"snap_distance_m":offset,"directed_distance_from_core_m":distances[node["id"]],"reference_note":"approximate sector reference, not an administrative boundary"})
    nodes={n["id"]:n for n in data["nodes"]}
    coastal={r["from"] for r in data["roads"] if "pichilingue" in r["street_name"].lower()} | {r["to"] for r in data["roads"] if "pichilingue" in r["street_name"].lower()}
    coast=min((nodes[n] for n in coastal if n in distances and not nodes[n]["boundary_generated"]),key=lambda n:n["z"])
    anchors.append({"id":"costa_norte","name":"Prolongación costera norte","node_id":coast["id"],"position_xz":[coast["x"],coast["z"]],"directed_distance_from_core_m":distances[coast["id"]],"source":"OSM Carretera La Paz-Pichilingue, northernmost reachable non-clipped road node"})
    by_id={a["id"]:a for a in anchors}
    routes=[route(data,"north_coast","Malecón — costa norte",[start,by_id["esterito"]["node_id"],coast["id"]]),route(data,"north_neighborhoods","Centro — Colina del Sol — Pedregal",[start,by_id["pedregal_del_cortez"]["node_id"]])]
    if "south" in settings["active_blocks"]:
        routes.extend([route(data,"south_hospital","Centro — área hospitalaria Salvatierra",[start,by_id["hospital_salvatierra"]["node_id"]]),route(data,"south_uabcs","Centro — UABCS — conexión sur",[start,by_id["uabcs"]["node_id"],by_id["conexion_sur"]["node_id"]])])
    critical_routes=[]
    for entry in settings.get("critical_corridors",[]):
        waypoints=[start]
        for chain in entry["source_node_chains"]:
            if any(node not in nodes for node in chain):
                raise ValueError("Critical corridor source node was clipped or omitted: " + entry["id"])
            for node in chain:
                if waypoints[-1]!=node: waypoints.append(node)
        candidate=route(data,"cajoncito_"+entry["id"],entry["name"],waypoints)
        actual={data_road["id"]:data_road["osm_way_id"] for data_road in data["roads"]}
        used={actual[e.rsplit(":",1)[0]] for e in candidate["edge_ids"]}
        if not set(entry["source_way_ids"]).issubset(used):
            raise ValueError("Critical route bypassed its required source roads: " + entry["id"])
        candidate["required_osm_way_ids"]=entry["source_way_ids"]
        critical_routes.append(candidate)
    folder=ROOT/"tracks"; folder.mkdir(exist_ok=True)
    for r in routes+critical_routes:
        (folder/("c5_"+r["id"]+".json")).write_text(json.dumps(r,ensure_ascii=False,indent=2),encoding="utf-8",newline="\n")
    blocks=[]
    for key in settings["active_blocks"]:
        b=settings["blocks"][key]; local=metric_region({**cfg,"active_blocks":{key:b["bbox"]}})
        blocks.append({"id":key,"name":b["name"],"bounds_xz":list(local.bounds),"boundary_xz":[list(p) for p in local.exterior.coords],"bbox":b["bbox"],"neighborhoods":b["neighborhoods"]})
    previous=settings["blocks"]["core"]["bbox"]
    core=metric_region({**cfg,"active_blocks":{"core":previous}})
    active=metric_region(cfg)
    manifest={"schema_version":1,"phase":"C.5","active_blocks":blocks,"map_sha256":digest(ROOT/"data/processed/la_paz_map.json"),"config_sha256":digest(ROOT/"config/expansion_config.json"),"origin_lat":cfg["origin_lat"],"origin_lon":cfg["origin_lon"],"sector_size_m":cfg["chunk_size_m"],"anchors":anchors,"routes":[{"id":r["id"],"file":"tracks/c5_"+r["id"]+".json","sha256":digest(folder/("c5_"+r["id"]+".json")),"length_m":r["length_m"]} for r in routes],"statistics":{"core_envelope_area_km2":core.area/1e6,"active_envelope_area_km2":active.area/1e6,"area_ratio":active.area/core.area,"reachable_nodes_from_core":len(distances),"total_nodes":len(nodes)},"note":"Active blocks declared in expansion_config.json. Coast and height remain stylized; original coordinates and directed topology retained. Routes are fictional game candidates, not real street-racing advice."}
    manifest["critical_routes"]=[{"id":r["id"],"file":"tracks/c5_"+r["id"]+".json","sha256":digest(folder/("c5_"+r["id"]+".json")),"length_m":r["length_m"]} for r in critical_routes]
    path=ROOT/"data/processed/expansion_manifest.json"
    path.write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding="utf-8",newline="\n")
    print(json.dumps({"statistics":manifest["statistics"],"routes":manifest["routes"]},ensure_ascii=False,indent=2))
    return manifest

if __name__ == "__main__": build()

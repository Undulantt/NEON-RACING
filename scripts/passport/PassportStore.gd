extends RefCounted
# Content and player progress are separate, versioned offline files.
const CONTENT := "res://data/passport/pois.json"
const LOCAL := "user://passport/catalog.json"
const DRAFT := "user://passport/draft.json"
var progress_path := "user://passport/progress.json"
var discovered: Dictionary = {}
var warning := ""

static func read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):return {}
	var parser:=JSON.new()
	if parser.parse(FileAccess.get_file_as_string(path))!=OK or not parser.data is Dictionary:return {}
	return parser.data

static func write(path: String, data: Dictionary) -> String:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var file:=FileAccess.open(path+".tmp",FileAccess.WRITE)
	if file==null:return "No se pudo escribir el archivo."
	file.store_string(JSON.stringify(data,"  "));file.flush()
	var error:=file.get_error();file.close()
	if error!=OK:return "No se pudo completar el guardado."
	var main:=ProjectSettings.globalize_path(path)
	if FileAccess.file_exists(path):
		if FileAccess.file_exists(path+".bak"):DirAccess.remove_absolute(main+".bak")
		if DirAccess.rename_absolute(main,main+".bak")!=OK:return "No se pudo conservar el respaldo."
	if DirAccess.rename_absolute(main+".tmp",main)!=OK:
		if FileAccess.file_exists(path+".bak"):DirAccess.rename_absolute(main+".bak",main)
		return "No se pudo reemplazar el archivo; se conserva el anterior."
	return ""

static func safe_id(value: String) -> bool:
	if value.is_empty() or value.length()>64:return false
	for c in value:
		if not c in "abcdefghijklmnopqrstuvwxyz0123456789_":return false
	return true

static func url_ok(value: String) -> bool:
	return value.begins_with("https://") and value.length()>12 and not " " in value and not "\n" in value

static func world_point(lat: float, lon: float, origin: Dictionary) -> Vector2:
	return Vector2(6371000.0*deg_to_rad(lon-float(origin["origin_lon"]))*cos(deg_to_rad(origin["origin_lat"])),-6371000.0*deg_to_rad(lat-float(origin["origin_lat"])))

static func geographic(at: Vector2, origin: Dictionary) -> Vector2:
	return Vector2(float(origin["origin_lat"])-rad_to_deg(at.y/6371000.0),float(origin["origin_lon"])+rad_to_deg(at.x/(6371000.0*cos(deg_to_rad(origin["origin_lat"])))) )

static func approach(poi: Dictionary, graph: RefCounted) -> Vector2:
	var road: Dictionary=graph.roads[str(poi["activation"]["road_id"])]
	var a: Vector2=graph.nodes[str(road["from"])];var b: Vector2=graph.nodes[str(road["to"])]
	return a.lerp(b,float(poi["activation"]["t"]))

static func snap(at: Vector2, graph: RefCounted, maximum:=80.0) -> Dictionary:
	var best:=maximum;var result: Dictionary={}
	for road in graph.roads.values():
		var a: Vector2=graph.nodes[str(road["from"])];var b: Vector2=graph.nodes[str(road["to"])]
		if graph.navigation!=null and not graph.navigation_pairs.has(str(road["from"])+">"+str(road["to"])) and not graph.navigation_pairs.has(str(road["to"])+">"+str(road["from"])):continue
		var p:=Geometry2D.get_closest_point_to_segment(at,a,b)
		if p.distance_to(at)<best:
			best=p.distance_to(at)
			result={"road_id":str(road["id"]),"t":clampf((p-a).dot(b-a)/maxf(.001,(b-a).length_squared()),0,1),"position_xz":[p.x,p.y],"radius_m":9.0,"max_speed_mps":3.0,"street":str(road["street_name"])}
	return result

static func validate(data: Dictionary, graph: RefCounted, metadata: Dictionary) -> String:
	if data.get("schema_version")!=1 or not data.get("pois") is Array:return "Catálogo no compatible."
	if data.get("map_sha256")!=graph.map_hash:return "El mapa cambió; revisar las aproximaciones antes de aplicar."
	var ids: Dictionary={};var count:=0
	for poi in data["pois"]:
		if not poi is Dictionary or not safe_id(str(poi.get("id",""))):return "Identificador de POI inválido."
		if ids.has(poi["id"]):return "ID duplicado: "+str(poi["id"])
		ids[poi["id"]]=true
		if not poi.get("enabled",false):continue
		count+=1
		for key in ["name","category","description"]:
			if not poi.get(key) is String or poi[key].strip_edges().is_empty():return "Completa nombre, categoría y descripción."
		for key in ["latitude","longitude"]:
			var value=poi.get(key)
			if not (value is float or value is int) or not is_finite(float(value)):return "Coordenada inválida."
		var bbox: Array=metadata["bbox"]
		if poi["latitude"]<bbox[0] or poi["latitude"]>bbox[2] or poi["longitude"]<bbox[1] or poi["longitude"]>bbox[3]:return "Lugar fuera del mapa actual."
		if not poi.get("coordinate_evidence") is Dictionary or not poi["coordinate_evidence"].get("verified",false) or str(poi["coordinate_evidence"].get("source_ref","")).is_empty():return "Falta una referencia y la verificación declarada de las coordenadas."
		if not poi.get("references") is Array or poi["references"].is_empty():return "Añade una fuente verificable."
		for source in poi["references"]:
			if not source is Dictionary or not url_ok(str(source.get("url",""))):return "Las fuentes deben tener una URL HTTPS válida."
		var zone=poi.get("activation")
		if not zone is Dictionary or not graph.roads.has(str(zone.get("road_id",""))):return "Selecciona una calle para la aproximación."
		for key in ["t","radius_m","max_speed_mps"]:
			var value=zone.get(key)
			if not (value is float or value is int) or not is_finite(float(value)):return "Aproximación inválida."
		if zone["t"]<0 or zone["t"]>1 or zone["radius_m"]<4 or zone["radius_m"]>15 or zone["max_speed_mps"]<0 or zone["max_speed_mps"]>3:return "Radio permitido: 4–15 m; velocidad máxima: 0–3 m/s."
		if not zone.get("validated",false) or zone.get("validation_map_sha256")!=graph.map_hash:return "Prueba la aproximación sobre el asfalto antes de aplicar."
		var at:=approach(poi,graph)
		if at.distance_to(world_point(poi["latitude"],poi["longitude"],metadata))>180:return "La zona de aproximación está a más de 180 m del lugar."
		var road: Dictionary=graph.roads[str(zone["road_id"])]
		if graph.navigation!=null and not graph.navigation_pairs.has(str(road["from"])+">"+str(road["to"])) and not graph.navigation_pairs.has(str(road["to"])+">"+str(road["from"])):return "La aproximación no pertenece a la red transitable actual."
	if count==0 or count>3:return "D.4 permite entre uno y tres POI activos; conserva los demás como borradores."
	return ""

func load_progress() -> void:
	var data:=read(progress_path)
	if data.get("schema_version")!=1 or not data.get("discovered") is Dictionary:
		data=read(progress_path+".bak")
		if FileAccess.file_exists(progress_path):warning="Progreso no legible; se intentó recuperar el respaldo."
	discovered=data.get("discovered",{}).duplicate(true) if data.get("schema_version")==1 and data.get("discovered") is Dictionary else {}

func register(id: String) -> String:
	if discovered.has(id):return ""
	var next:=discovered.duplicate(true);next[id]=Time.get_datetime_string_from_system(true)
	var error:=write(progress_path,{"schema_version":1,"discovered":next})
	if error.is_empty():discovered=next
	return error

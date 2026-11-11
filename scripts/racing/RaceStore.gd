extends RefCounted
const CONTENT := "res://data/races/"
const LOCAL := "user://races/"

static func safe_id(id: String) -> bool:
	for character in id:
		if not character in "abcdefghijklmnopqrstuvwxyz0123456789_": return false
	return not id.is_empty() and id.length() <= 64 and id.validate_node_name() == id and not "." in id and not "/" in id and not "\\" in id

static func create(graph: RefCounted, anchors: Array, id: String, title: String, spacing := 30.0, wrong_way := false, race_type := "sprint", laps := 0) -> Dictionary:
	return build(graph,anchors,id,title,spacing,wrong_way,race_type,laps)["data"]

static func invalid(message: String) -> Dictionary:
	return {"data":{},"error":message}

static func build(graph: RefCounted, anchors: Array, id: String, title: String, spacing := 30.0, wrong_way := false, race_type := "sprint", laps := 0) -> Dictionary:
	if graph == null: return invalid("Todavía no está preparada la red vial.")
	if not safe_id(id): return invalid("ID inválido: usa sólo minúsculas, números y guion bajo, con un máximo de 64 caracteres.")
	if title.strip_edges().is_empty(): return invalid("Escribe un nombre para la carrera.")
	if race_type not in ["sprint","circuit"]: return invalid("Elige Sin vueltas (sprint) o Con vueltas (circuito).")
	if race_type == "circuit" and (laps < 1 or laps > 99): return invalid("El circuito necesita entre 1 y 99 vueltas.")
	if race_type == "sprint" and laps != 0: return invalid("Una carrera sin vueltas debe tener 0 vueltas.")
	if anchors.is_empty(): return invalid("Falta el recorrido: haz clic sobre una carretera para colocar la salida; después coloca la meta.")
	if anchors.size() == 1: return invalid("Salida colocada. Haz clic en otro punto de la carretera para añadir la meta o un paso del circuito.")
	for i in range(anchors.size()):
		if not graph.nodes.has(anchors[i]): return invalid("El punto %d ya no existe en este mapa. Muévelo o elimínalo." % i)
		if i > 0 and anchors[i] == anchors[i-1]: return invalid("Los puntos %d y %d son el mismo nodo. Elimina uno o elige otra intersección." % [i-1,i])
	var ordered := anchors.duplicate()
	if race_type == "circuit":
		var unique := {}
		for node in anchors: unique[node] = true
		if unique.size() < 3: return invalid("Para un circuito coloca al menos 3 puntos distintos. El regreso a la salida se calcula automáticamente.")
		if ordered[-1] != ordered[0]: ordered.append(ordered[0])
	var traced: Dictionary = graph.route(ordered, wrong_way)
	if traced.is_empty():
		for i in range(ordered.size()-1):
			if graph.route([ordered[i],ordered[i+1]],wrong_way).is_empty():
				return invalid("No hay conexión transitable del punto %d al %s. Cambia los puntos o revisa el sentido de circulación%s." % [i,"inicio del circuito" if i+1 >= anchors.size() else "punto %d" % (i+1),"; la excepción de contrasentido es opcional y explícita" if not wrong_way else ""])
		return invalid("No se pudo construir un recorrido conectado.")
	var refs: Array = traced["edges"]
	var points: Array = []
	var gates: Array = []
	var distance := 0.0
	spacing = clampf(spacing, 10.0, 80.0)
	for i in range(refs.size()):
		var ref: Dictionary = refs[i]
		var a: Vector2 = graph.nodes[ref["from"]]
		var b: Vector2 = graph.nodes[ref["to"]]
		var length := a.distance_to(b)
		if length < 0.01: return invalid("El recorrido contiene un tramo menor de un centímetro. Cambia los puntos de paso.")
		var direction := (b-a).normalized()
		if points.is_empty(): points.append([a.x,a.y])
		points.append([b.x,b.y])
		var steps := maxi(1, ceili(length/spacing))
		var half := maxf(2.0, float(graph.roads[ref["road_id"]]["width_m"])*0.48)
		for j in range(1, steps+1):
			var p := a.lerp(b,float(j)/steps)
			gates.append({"position_xz":[p.x,p.y],"forward_xz":[direction.x,direction.y],"half_width_m":half,"distance_m":distance+length*j/steps,"edge_index":i})
		distance += length
	var a := Vector2(points[0][0],points[0][1])
	var direction := (Vector2(points[1][0],points[1][1])-a).normalized()
	# Spawn a few metres into the first road, never behind an intersection.
	var spawn := a + direction * minf(3.0, a.distance_to(Vector2(points[1][0],points[1][1]))*0.2)
	var start := {"position_xz":[spawn.x,spawn.y],"forward_xz":[direction.x,direction.y]}
	var data := {"schema_version":1,"id":id,"name":title,"type":race_type,"laps":laps,"map_sha256":graph.map_hash,"anchors":anchors.duplicate(),"edges":refs,"points_xz":points,"checkpoints":gates,"start":start,"finish":gates[-1].duplicate(true),"spawn_positions":[start.duplicate(true)],"distance_m":distance*maxi(1,laps),"settings":{"checkpoint_spacing_m":spacing,"allow_wrong_way":wrong_way,"countdown_s":3.0}}
	if race_type == "circuit": data["lap_distance_m"] = distance
	return {"data":data,"error":""}

static func format_label(data: Dictionary) -> String:
	return "Circuito · %d vueltas" % int(data.get("laps",1)) if data.get("type") == "circuit" else "Sin vueltas · Sprint A → B"

static func validate(data: Dictionary, graph: RefCounted) -> String:
	if data.is_empty(): return "No hay un recorrido válido: coloca salida y meta sobre carreteras conectadas."
	if data.get("schema_version") != 1: return "Versión de archivo de carrera no compatible."
	if data.get("type") not in ["sprint","circuit"]: return "Tipo de carrera no compatible: se admite sprint o circuito."
	if not safe_id(str(data.get("id",""))): return "ID de carrera inválido: usa minúsculas, números y guion bajo."
	var laps = data.get("laps",0)
	if not (laps is float or laps is int) or not is_finite(float(laps)) or float(laps) != floorf(float(laps)): return "El número de vueltas debe ser un entero."
	if data["type"] == "sprint" and int(laps) != 0: return "Un sprint es sin vueltas (0)."
	if data["type"] == "circuit" and (int(laps) < 1 or int(laps) > 99): return "El circuito necesita entre 1 y 99 vueltas."
	if data.get("map_sha256") != graph.map_hash: return "El mapa cambió: reabrir y regenerar la carrera en el editor."
	if not data.get("settings") is Dictionary or not data.get("anchors") is Array or not data.get("edges") is Array: return "Estructura de carrera inválida."
	var settings: Dictionary = data["settings"]
	if not settings.get("allow_wrong_way",false) is bool: return "Excepción de circulación inválida."
	for anchor in data["anchors"]:
		if not anchor is String: return "Identificador de nodo inválido."
	for key in ["checkpoint_spacing_m","countdown_s"]:
		var value = settings.get(key)
		if not (value is float or value is int) or not is_finite(float(value)): return "Configuración numérica inválida."
	if float(settings["checkpoint_spacing_m"]) < 10 or float(settings["checkpoint_spacing_m"]) > 80 or float(settings["countdown_s"]) < 1 or float(settings["countdown_s"]) > 10: return "Configuración fuera de rango."
	var error: String = graph.validate_refs(data.get("edges",[]),settings.get("allow_wrong_way",false))
	if not error.is_empty(): return error
	# Geometry and gates are derived, never trusted independently of road references.
	var built := build(graph,data["anchors"],data["id"],str(data.get("name","")),float(settings["checkpoint_spacing_m"]),settings.get("allow_wrong_way",false),data["type"],int(laps))
	if not built["error"].is_empty(): return built["error"]
	var rebuilt: Dictionary = built["data"]
	for key in ["edges","points_xz","checkpoints","start","finish","spawn_positions","distance_m"]:
		if not equivalent(data.get(key),rebuilt[key]): return "Geometría o checkpoints alterados: regenerar el recorrido."
	if data["type"] == "circuit" and not equivalent(data.get("lap_distance_m"),rebuilt["lap_distance_m"]): return "Distancia por vuelta alterada: regenera el circuito."
	return ""

static func load_id(id: String) -> Dictionary:
	if not safe_id(id): return {}
	for root in [LOCAL, CONTENT]:
		var path: String = root+id+".json"
		if FileAccess.file_exists(path):
			var value = JSON.parse_string(FileAccess.get_file_as_string(path))
			return value if value is Dictionary else {}
	return {}

static func save(data: Dictionary, graph: RefCounted, publish := false) -> String:
	var error := validate(data,graph)
	if not error.is_empty(): return error
	if publish and not OS.has_feature("editor"): return "Publicación disponible sólo en desarrollo."
	var root := CONTENT if publish else LOCAL
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(root))
	var path := root+str(data["id"])+".json"
	var file := FileAccess.open(path+".tmp",FileAccess.WRITE)
	if file == null: return "No se pudo escribir la carrera."
	file.store_string(JSON.stringify(data,"  "))
	file.close()
	if DirAccess.rename_absolute(path+".tmp",path) != OK: return "No se pudo finalizar el archivo de carrera."
	return ""

static func equivalent(a: Variant, b: Variant) -> bool:
	if (a is float or a is int) and (b is float or b is int): return absf(float(a)-float(b)) <= 0.00001
	if a is Array and b is Array:
		if a.size() != b.size(): return false
		for i in range(a.size()):
			if not equivalent(a[i],b[i]): return false
		return true
	if a is Dictionary and b is Dictionary:
		if a.size() != b.size(): return false
		for key in a:
			if not b.has(key) or not equivalent(a[key],b[key]): return false
		return true
	return a == b

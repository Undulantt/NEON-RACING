extends RefCounted
# Pure data: built off-thread before the world strips OSM metadata.
var nodes: Dictionary = {}
var roads: Dictionary = {}
var edges: Dictionary = {}
var pairs: Dictionary = {}
var ids: Dictionary = {}
var names: Dictionary = {}
var legal := AStar2D.new()
var exceptions := AStar2D.new()
var map_hash := ""
var navigation: AStar2D
var navigation_pairs: Dictionary = {}

func configure_navigation(allowed_roads: Array) -> void:
	# Optional drivable subset for GPS; editor/race source validation stays intact.
	navigation = AStar2D.new()
	navigation_pairs.clear()
	var allowed := {}
	var used := {}
	for id in allowed_roads: allowed[str(id)] = true
	for edge in edges.values():
		if allowed.has(str(edge["road_id"])):
			used[str(edge["from"])] = true
			used[str(edge["to"])] = true
	for id in used: navigation.add_point(ids[id],nodes[id])
	for edge in edges.values():
		if not allowed.has(str(edge["road_id"])): continue
		var a := str(edge["from"])
		var b := str(edge["to"])
		navigation.connect_points(ids[a],ids[b],false)
		navigation_pairs[a+">"+b] = str(edge["id"])

func build(data: Dictionary, fingerprint: String) -> void:
	map_hash = fingerprint
	for n in data["nodes"]:
		var id := str(n["id"])
		var index := ids.size()
		ids[id] = index
		names[index] = id
		nodes[id] = Vector2(n["x"], n["z"])
		legal.add_point(index, nodes[id])
		exceptions.add_point(index, nodes[id])
	for r in data["roads"]:
		roads[str(r["id"])] = r.duplicate(true)
	for e in data["edges"]:
		var a := str(e["from"])
		var b := str(e["to"])
		if not ids.has(a) or not ids.has(b): continue
		edges[str(e["id"])] = e.duplicate(true)
		pairs[a + ">" + b] = str(e["id"])
		legal.connect_points(ids[a], ids[b], false)
		if not exceptions.are_points_connected(ids[a], ids[b]): exceptions.connect_points(ids[a], ids[b], true)

func nearest(p: Vector2, maximum := 100.0, active_only := false) -> String:
	var network := navigation if active_only and navigation != null else legal
	var index := network.get_closest_point(p)
	if index < 0 or network.get_point_position(index).distance_to(p) > maximum: return ""
	return names[index]

func route(anchors: Array, allow_wrong_way := false, active_only := false) -> Dictionary:
	var refs: Array = []
	var graph := exceptions if allow_wrong_way else legal
	var connections := pairs
	if active_only and navigation != null:
		graph = navigation
		connections = navigation_pairs
	for i in range(anchors.size() - 1):
		if not ids.has(anchors[i]) or not ids.has(anchors[i+1]): return {}
		if not graph.has_point(ids[anchors[i]]) or not graph.has_point(ids[anchors[i+1]]): return {}
		var path := graph.get_id_path(ids[anchors[i]], ids[anchors[i+1]])
		if path.size() < 2: return {}
		for j in range(path.size() - 1):
			var a: String = names[path[j]]
			var b: String = names[path[j+1]]
			var key := a + ">" + b
			var against := not connections.has(key)
			var edge: Dictionary = edges[connections[b + ">" + a] if against else connections[key]]
			refs.append({"road_id": str(edge["road_id"]), "from": a, "to": b, "wrong_way": against})
	return {"edges": refs}

func validate_refs(refs: Array, allow_wrong_way: bool) -> String:
	if refs.is_empty(): return "El recorrido está vacío."
	var last := ""
	for ref in refs:
		if not ref is Dictionary: return "Tramo inválido."
		var a := str(ref.get("from", ""))
		var b := str(ref.get("to", ""))
		var road: Dictionary = roads.get(str(ref.get("road_id", "")), {})
		if road.is_empty() or not nodes.has(a) or not nodes.has(b): return "Desapareció un tramo o nodo del mapa."
		if not last.is_empty() and last != a: return "Conexión interrumpida."
		if not ((str(road["from"]) == a and str(road["to"]) == b) or (str(road["from"]) == b and str(road["to"]) == a)): return "El tramo no conecta esos nodos."
		var legal_ref: Dictionary = edges.get(pairs.get(a + ">" + b, ""), {})
		var valid_direction := not legal_ref.is_empty() and str(legal_ref["road_id"]) == str(ref["road_id"])
		if not valid_direction and (not allow_wrong_way or not ref.get("wrong_way", false)): return "Sentido contrario sin excepción explícita."
		last = b
	return ""

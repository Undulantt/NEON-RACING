extends Node
signal changed
var world: Node3D
var destination_id := ""
var destination := Vector2.ZERO
var points: Array = []
var route_edges: Array = []
var distance_m := 0.0
var status := "Haz clic en una calle para elegir destino."
var route_anchor := Vector2.ZERO
var refresh_timer := 0.0

func configure(target: Node3D) -> void:
	world = target

func set_destination(at: Vector2) -> bool:
	var graph = GameFlow.road_graph
	var id: String = graph.nearest(at,100.0,true)
	if id.is_empty():
		status = "Elige un punto más próximo a una carretera."
		changed.emit()
		return false
	destination_id = id
	destination = graph.nodes[id]
	return recalculate()

func clear_destination() -> void:
	destination_id = ""
	points.clear()
	route_edges.clear()
	distance_m = 0
	status = "Sin destino. Haz clic en una calle."
	changed.emit()

func recalculate() -> bool:
	var graph = GameFlow.road_graph
	var car = world.player
	var at := Vector2(car.position.x,car.position.z)
	route_anchor = at
	var roads: Dictionary = {}
	var center := Vector2i(floori(at.x/256),floori(at.y/256))
	for x in range(center.x-1,center.x+2):
		for y in range(center.y-1,center.y+2):
			for road in car.road_cells.get(Vector2i(x,y),[]): roads[str(road["id"])] = road
	var candidates: Array = []
	for road in roads.values():
		var a: Vector2 = graph.nodes[str(road["from"])]
		var b: Vector2 = graph.nodes[str(road["to"])]
		var on_road := Geometry2D.get_closest_point_to_segment(at,a,b)
		candidates.append({"road":road,"projection":on_road,"offset":at.distance_to(on_road)})
	candidates.sort_custom(func(a,b):return a["offset"]<b["offset"])
	var best := INF
	var chosen: Array = []
	var edges: Array = []
	# Start on the current road in a permitted direction, rather than drawing a
	# straight line to an arbitrary nearby intersection across city blocks.
	for candidate in candidates.slice(0,4):
		if float(candidate["offset"])>float(candidates[0]["offset"])+3.0: continue
		var road: Dictionary = candidate["road"]
		for pair in [[str(road["from"]),str(road["to"])],[str(road["to"]),str(road["from"])]]:
			var edge: Dictionary = graph.edges.get((graph.navigation_pairs if graph.navigation != null else graph.pairs).get(pair[0]+">"+pair[1],""),{})
			if edge.is_empty() or str(edge["road_id"]) != str(road["id"]): continue
			var traced: Dictionary = {"edges":[]} if pair[1] == destination_id else graph.route([pair[1],destination_id],false,true)
			if traced.is_empty(): continue
			var p: Vector2 = candidate["projection"]
			var endpoint: Vector2 = graph.nodes[pair[1]]
			var cost := p.distance_to(endpoint)
			for ref in traced["edges"]: cost += graph.nodes[ref["from"]].distance_to(graph.nodes[ref["to"]])
			if cost+float(candidate["offset"]) >= best: continue
			best = cost+float(candidate["offset"])
			distance_m = cost
			chosen = [[p.x,p.y],[endpoint.x,endpoint.y]]
			edges = traced["edges"].duplicate(true)
			for ref in traced["edges"]:
				var node: Vector2 = graph.nodes[ref["to"]]
				chosen.append([node.x,node.y])
	points = chosen
	route_edges = edges
	if chosen.is_empty():
		distance_m = 0
		status = "No hay conexión vial permitida con ese destino."
	else:
		status = "Destino fijado · %.0f m por calles OSM" % distance_m
	changed.emit()
	return not chosen.is_empty()

func _process(delta: float) -> void:
	if destination_id.is_empty() or GameFlow.current_state != &"free_drive": return
	refresh_timer -= delta
	if refresh_timer>0: return
	refresh_timer = 0.75
	var at := Vector2(world.player.position.x,world.player.position.z)
	if at.distance_to(destination)<18:
		clear_destination()
		status = "Destino alcanzado."
		world.hud.show_notice(status)
		changed.emit()
	elif at.distance_to(route_anchor)>30: recalculate()

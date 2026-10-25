extends Camera3D

var route := PackedVector3Array()
var distances := PackedFloat64Array()
var progress := 0.0
var touring := false
var overview := true
var label: Label
var road_names: Array = []
var map_roads: Dictionary = {}

func configure(data: Dictionary, hud: Label) -> void:
	label = hud
	for p in data["verification_route"]["points_xz"]:
		route.append(Vector3(p[0], 1.8, p[1]))
	distances.append(0.0)
	for i in range(1, route.size()):
		distances.append(distances[-1] + route[i].distance_to(route[i - 1]))
	for road in data["roads"]:
		map_roads[road["id"]] = road
	var edges := {}
	for edge in data["edges"]:
		edges[edge["id"]] = edge
	for edge_id in data["verification_route"]["edge_ids"]:
		road_names.append(map_roads[edges[edge_id]["road_id"]]["street_name"])
	show_overview()

func show_overview() -> void:
	projection = Camera3D.PROJECTION_PERSPECTIVE
	near = 5.0
	touring = false
	overview = true
	position = Vector3(0, 2900, 1100)
	look_at(Vector3.ZERO, Vector3.UP)

func route_position(at: float) -> Vector3:
	var index := clampi(distances.bsearch(at) - 1, 0, route.size() - 2)
	var t := clampf((at - distances[index]) / (distances[index + 1] - distances[index]), 0.0, 1.0)
	return route[index].lerp(route[index + 1], t)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("debug_tour"):
		touring = not touring
		overview = false
	if event.is_action_pressed("debug_overview"):
		show_overview()
	if event.is_action_pressed("debug_reset"):
		progress = 0.0
		touring = true
		overview = false
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if event.pressed else Input.MOUSE_MODE_VISIBLE
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		touring = false
		overview = false
		rotate_y(-event.relative.x * 0.003)
		rotation.x = clampf(rotation.x - event.relative.y * 0.003, -1.5, 1.5)

func _physics_process(delta: float) -> void:
	if route.is_empty():
		return
	if touring:
		projection = Camera3D.PROJECTION_PERSPECTIVE
		near = 0.1
		progress = minf(progress + delta * 18.0, distances[-1] - 0.01)
		position = route_position(progress)
		var ahead := route_position(minf(progress + 8.0, distances[-1]))
		if position.distance_to(ahead) > 0.01:
			look_at(ahead, Vector3.UP)
		if progress >= distances[-1] - 0.02:
			touring = false
	else:
		var movement := Vector3(Input.get_axis("debug_left", "debug_right"), Input.get_axis("debug_down", "debug_up"), Input.get_axis("debug_forward", "debug_back"))
		if movement.length_squared() > 0:
			near = 0.1
			overview = false
			position += (global_basis * movement.normalized()) * delta * (160.0 if Input.is_action_pressed("debug_fast") else 35.0)
	var index := clampi(distances.bsearch(progress) - 1, 0, road_names.size() - 1)
	label.text = "LA PAZ · FASE A / INSPECCIÓN VIAL\n%d m de %d m · %s\nESPACIO: recorrido a 1.8 m · TAB: mapa · INICIO: reiniciar\nWASD + Q/E: cámara libre · SHIFT: rápido · ratón derecho: mirar\n1 unidad = 1 m · alturas planas y anchos estimados donde falta OSM\n© OpenStreetMap contributors · ODbL · openstreetmap.org/copyright" % [progress, distances[-1], road_names[index]]

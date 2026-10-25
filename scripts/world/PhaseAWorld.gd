extends Node3D

const Loader = preload("res://scripts/world/MapLoader.gd")
const Builder = preload("res://scripts/world/RoadBuilder.gd")
const DebugCamera = preload("res://scripts/world/DebugCamera.gd")
var map_data: Dictionary = {}
var camera: Camera3D
var road_root: Node3D
var stats: Dictionary = {}
var capture_frames := 0
var capture_path := ""

func _ready() -> void:
	var actions := {"debug_tour": KEY_SPACE, "debug_overview": KEY_TAB, "debug_reset": KEY_HOME, "debug_forward": KEY_W, "debug_back": KEY_S, "debug_left": KEY_A, "debug_right": KEY_D, "debug_up": KEY_E, "debug_down": KEY_Q, "debug_fast": KEY_SHIFT}
	for action in actions:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		var event := InputEventKey.new()
		event.physical_keycode = actions[action]
		InputMap.action_add_event(action, event)
	var hud := Label.new()
	hud.position = Vector2(18, 16)
	hud.add_theme_font_size_override("font_size", 17)
	hud.add_theme_color_override("font_color", Color.WHITE)
	hud.add_theme_color_override("font_shadow_color", Color.BLACK)
	hud.add_theme_constant_override("shadow_offset_x", 2)
	hud.add_theme_constant_override("shadow_offset_y", 2)
	var layer := CanvasLayer.new()
	layer.add_child(hud)
	add_child(layer)
	map_data = Loader.load_map()
	if map_data.is_empty():
		hud.text = "FASE A: faltan datos OSM válidos. Ejecuta las herramientas offline."
		return
	road_root = Node3D.new()
	road_root.name = "RoadChunks"
	add_child(road_root)
	var start := Time.get_ticks_msec()
	stats = Builder.build(road_root, map_data)
	stats["build_ms"] = Time.get_ticks_msec() - start
	print("MAP_READY ", stats)
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color("b4c6d0")
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color.WHITE
	settings.ambient_light_energy = 0.7
	environment.environment = settings
	add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55, -35, 0)
	light.light_energy = 1.0
	add_child(light)
	# Visual reference plane only: no ground collision masking asphalt holes.
	# It is not a land/coast dataset and is explicitly labelled as a neutral backdrop.
	var backdrop := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(12000, 12000)
	backdrop.mesh = plane
	backdrop.position.y = -2.0
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("b9ab8c")
	backdrop.material_override = mat
	add_child(backdrop)
	camera = Camera3D.new()
	camera.set_script(DebugCamera)
	camera.far = 16000
	camera.near = 0.1
	add_child(camera)
	camera.current = true
	camera.configure(map_data, hud)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="):
			capture_path = arg.trim_prefix("--capture=")
		if arg == "--plan":
			camera.projection = Camera3D.PROJECTION_ORTHOGONAL
			camera.size = 2700.0
			camera.position = Vector3(0, 3000, 0)
			camera.look_at(Vector3.ZERO, Vector3.FORWARD)
		if arg == "--tour":
			camera.touring = true
			camera.overview = false
		if arg.begins_with("--at="):
			camera.progress = float(arg.trim_prefix("--at="))
			camera.touring = true

func _process(_delta: float) -> void:
	if capture_path.is_empty():
		return
	capture_frames += 1
	if capture_frames == 45:
		var error := get_viewport().get_texture().get_image().save_png(capture_path)
		print("CAPTURE ", capture_path, " result=", error)
		get_tree().quit(error)

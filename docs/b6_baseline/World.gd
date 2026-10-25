extends Node3D

const Loader = preload("res://scripts/world/MapLoader.gd")
const Roads = preload("res://scripts/world/RoadBuilder.gd")
const Buildings = preload("res://scripts/world/BuildingBuilder.gd")
const PlayerScene = preload("res://scenes/cars/PlayerCar.tscn")
const Follow = preload("res://scripts/driving/FollowCamera.gd")
const UrbanManager = preload("res://scripts/world/UrbanChunkManager.gd")
const HUD = preload("res://scripts/ui/DrivingHUD.gd")
var map_data: Dictionary = {}
var environment_data: Dictionary = {}
var player: CharacterBody3D
var follow_camera: Node3D
var overhead: Camera3D
var hud: CanvasLayer
var road_root: Node3D
var building_root: Node3D
var stats: Dictionary = {}
var capture_frames := 0
var capture_path := ""
var capture_after := 90
var aerial := false
var runtime_error := ""
var city_manager: Node3D
var legacy_city := false

func _ready() -> void:
	var start := Time.get_ticks_msec()
	map_data = Loader.load_map()
	var env_path := "res://data/processed/la_paz_environment.json"
	if map_data.is_empty() or not FileAccess.file_exists(env_path):
		show_error("Faltan datos offline. Ejecuta tools/build_map.py y tools/build_environment.py.")
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(env_path))
	if not parsed is Dictionary or parsed.get("schema_version") != 1:
		show_error("Entorno inválido: se requiere schema_version=1.")
		return
	environment_data = parsed
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(FileAccess.get_file_as_bytes("res://data/processed/la_paz_map.json"))
	if hashing.finish().hex_encode() != environment_data["map_sha256"]:
		show_error("El mapa cambió. Regenera el entorno con tools/build_environment.py.")
		return
	road_root = Node3D.new()
	road_root.name = "RoadChunks"
	add_child(road_root)
	stats = Roads.build(road_root, map_data)
	building_root = Node3D.new()
	building_root.name = "EnvironmentChunks"
	add_child(building_root)
	legacy_city = legacy_city or "--legacy-city" in OS.get_cmdline_user_args()
	if legacy_city:
		stats.merge(Buildings.build(building_root, environment_data))
	Buildings.build_limits(building_root, environment_data["bounds_xz"])
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color("92b9c7")
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color("c5d8e5")
	settings.ambient_light_energy = 0.45
	environment.environment = settings
	add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42, -28, 0)
	sun.light_color = Color("ffe0b0")
	sun.light_energy = 0.75
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 160.0
	add_child(sun)
	player = PlayerScene.instantiate()
	add_child(player)
	player.configure(map_data, environment_data)
	if not legacy_city:
		var city_path := "res://data/processed/urban/city_manifest.json"
		var city = JSON.parse_string(FileAccess.get_file_as_string(city_path))
		if not city is Dictionary or city.get("schema_version") != 1 or city.get("map_sha256") != environment_data["map_sha256"] or city.get("units") != "meters":
			show_error("Ciudad B.5 inválida o desactualizada. Ejecuta tools/build_urban_city.py; --legacy-city abre la fase B anterior.")
			player.driving_enabled = false
			return
		city_manager = Node3D.new()
		city_manager.set_script(UrbanManager)
		add_child(city_manager)
		city_manager.configure(city, player)
		stats.merge(city["statistics"])
		stats["urban_chunks"] = city["chunks"].size()

	follow_camera = Node3D.new()
	follow_camera.set_script(Follow)
	add_child(follow_camera)
	follow_camera.attach(player)
	overhead = Camera3D.new()
	overhead.far = 6000
	overhead.near = 1
	add_child(overhead)
	hud = CanvasLayer.new()
	hud.set_script(HUD)
	add_child(hud)
	hud.attach(player, self)
	stats["build_ms"] = Time.get_ticks_msec() - start
	print("PHASE_B5_READY ", stats)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="):
			capture_path = arg.trim_prefix("--capture=")
		if arg.begins_with("--capture-after="):
			capture_after = int(arg.trim_prefix("--capture-after="))
		if arg == "--no-city" and city_manager != null:
			city_manager.set_city_enabled(false)
		if arg == "--aerial":
			toggle_camera()

func show_error(message: String) -> void:
	runtime_error = message
	push_error(message)
	var layer := CanvasLayer.new()
	var label := Label.new()
	label.text = message
	label.position = Vector2(24, 24)
	layer.add_child(label)
	add_child(layer)

func toggle_camera() -> void:
	aerial = not aerial
	player.driving_enabled = not aerial
	if aerial:
		overhead.current = true
	else:
		follow_camera.snap()
		follow_camera.camera.current = true

func get_collision_test_buildings() -> Array:
	return city_manager.fixture_buildings() if city_manager != null else environment_data["buildings"]

func _unhandled_input(event: InputEvent) -> void:
	if city_manager != null and event.is_action_pressed("debug_city_toggle"):
		var success: bool = city_manager.set_city_enabled(not city_manager.city_enabled)
		if success:
			hud.show_notice("Ciudad activada" if city_manager.city_enabled else "Ciudad desactivada · depuración sin fachadas")
		else:
			hud.show_notice("Vuelve completamente al asfalto antes de activar la ciudad")
	if player != null and event.is_action_pressed("camera_toggle"):
		toggle_camera()

func _physics_process(_delta: float) -> void:
	if player != null and aerial:
		overhead.position = player.position + Vector3(0, 150, 70)
		overhead.look_at(player.position)

func _process(_delta: float) -> void:
	if capture_path.is_empty():
		return
	capture_frames += 1
	if capture_frames == capture_after:
		var error := get_viewport().get_texture().get_image().save_png(capture_path)
		print("CAPTURE ", capture_path, " result=", error)
		get_tree().quit(error)

extends "res://tests/benchmark_burst_balance.gd"

var saving := false
var capture_started := false
var starting_contacts := 0
var starting_recoveries := 0

func capture(name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://docs/evidence/burst_" + name + ".png")

func _process(_delta: float) -> bool:
	if not capture_started or saving or car == null:
		return false
	if car.abilities.burst_state == 2 and car.abilities.burst_bonus >= 0.10:
		saving = true
		finish.call_deferred()
	return false

func finish() -> void:
	await capture("hud_active")
	var passed: bool = world.hud.burst_label.text.contains("ACTIVO") and world.hud.cap_label.text.contains("VECTOR") and car.current_speed_cap > car.base_speed_cap and car.wall_contacts == starting_contacts and car.recovery_count == starting_recoveries
	var result := {"passed": passed, "scene": "Main.tscn (production night city)", "mode": "Real physics, same automated pilot as route balance, standing start on existing extension_C2 aligned road run", "burst_label": world.hud.burst_label.text, "cap_label": world.hud.cap_label.text, "speed_kmh": car.speed_mps*3.6, "cap_kmh": car.current_speed_cap*3.6, "bonus": car.abilities.burst_bonus, "on_asphalt": car.on_asphalt, "wall_contacts": car.wall_contacts-starting_contacts, "recoveries": car.recovery_count-starting_recoveries}
	FileAccess.open("res://docs/burst_hud_validation.json", FileAccess.WRITE).store_string(JSON.stringify(result,"  "))
	print("BURST_HUD_REPORT ",JSON.stringify(result))
	world.queue_free()
	for i in range(4):
		await process_frame
	quit(0 if passed else 1)

func run() -> void:
	root.size = Vector2i(1280, 720)
	world = preload("res://scenes/Main.tscn").instantiate()
	root.add_child(world)
	car = world.player
	car.external_control = true
	await step(60)
	await capture("hud_normal")
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tracks/extension_C2.json"))
	var geometry: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://docs/burst_route_geometry.json"))
	var span: Dictionary = geometry["extension_C2"]["longest_runs"][0]
	build_path(data["points_xz"].slice(int(span["first_point_index"]), int(span["last_point_index"]) + 1))
	starting_contacts = car.wall_contacts
	starting_recoveries = car.recovery_count
	capture_started = true
	var result: Dictionary = await route("VECTOR", 6000)
	if not saving:
		print("BURST_HUD_FAILED ",JSON.stringify(result))
		quit(1)

extends "res://tests/benchmark_burst_balance.gd"

const Presentation = preload("res://scripts/driving/BurstPresentation.gd")
var capture_started := false
var saving := false
var captured_numbers := {}
var countdown_records := []

func capture(name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://docs/evidence/burst_vfx_" + name + ".png")

func _process(_delta: float) -> bool:
	if not capture_started or saving or car == null:
		return false
	var number := Presentation.countdown(car)
	if number > 0 and not captured_numbers.has(number):
		captured_numbers[number] = true
		countdown_capture.call_deferred(number)
	if car.abilities.burst_state == 2 and car.abilities.burst_time > 2.0:
		saving = true
		finish.call_deferred()
	return false

func countdown_capture(number: int) -> void:
	await capture("countdown_" + str(number))
	countdown_records.append({"number": number, "label": world.hud.countdown_label.text, "arming_time": car.abilities.arming_time})

func finish() -> void:
	car.set_physics_process(false)
	world.follow_camera.set_physics_process(false)
	var hud: CanvasLayer = world.hud
	hud.ground_flames.set_physics_process(false)
	hud.speed_effects.set_process(false)
	await capture("active")
	var report := {"passed":captured_numbers.size()==3 and hud.ground_flames.marks.size()>0 and car.on_asphalt, "mode":"Production Main.tscn; actual standing start on C2; frozen pose for close inspection of the grounded flame trail", "countdown":countdown_records,"fov":world.follow_camera.camera.fov,"ground_marks":hud.ground_flames.marks.size(),"speed_kmh":car.speed_mps*3.6,"bonus":car.abilities.burst_bonus}
	# Inspect the flame silhouette on the actual road from above, with the original scene colors.
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.global_position = car.global_position + car.global_basis.z * 9 + Vector3.UP * 12
	camera.look_at(car.global_position + car.global_basis.z * 5, Vector3.UP)
	camera.fov = 62
	camera.current = true
	hud.hide()
	await capture("ground_detail")
	camera.global_position = car.global_position + car.global_basis.x * 6 + car.global_basis.z * 8 + Vector3.UP * 2.8
	camera.look_at(car.global_position + car.global_basis.z * 5 + Vector3.UP * 0.3, Vector3.UP)
	await capture("wheel_fire_side")
	var with_fire := root.get_texture().get_image()
	hud.ground_flames.visual.hide()
	await process_frame
	await RenderingServer.frame_post_draw
	var without_fire := root.get_texture().get_image()
	var fire_samples := 0
	for y in range(0,with_fire.get_height(),4):
		for x in range(0,with_fire.get_width(),4):
			var a := with_fire.get_pixel(x,y)
			var b := without_fire.get_pixel(x,y)
			if a.r > a.g + 0.12 and a.b > 0.18 and absf(a.r-b.r)+absf(a.g-b.g)+absf(a.b-b.b) > 0.3:
				fire_samples += 1
	report["rendered_pink_fire_samples"] = fire_samples
	report["passed"] = report["passed"] and fire_samples > 32
	FileAccess.open("res://docs/burst_vfx_render_validation.json", FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("BURST_VFX_RENDER_REPORT ",JSON.stringify(report))
	world.queue_free()
	for i in range(4):
		await process_frame
	quit(0 if report["passed"] else 1)

func run() -> void:
	root.size = Vector2i(1280,720)
	world = preload("res://scenes/Main.tscn").instantiate()
	root.add_child(world)
	car = world.player
	car.external_control = true
	await step(60)
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tracks/extension_C2.json"))
	var geometry: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://docs/burst_route_geometry.json"))
	var span: Dictionary = geometry["extension_C2"]["longest_runs"][0]
	build_path(data["points_xz"].slice(int(span["first_point_index"]), int(span["last_point_index"])+1))
	capture_started = true
	var result: Dictionary = await route("VECTOR",6000)
	if not saving:
		print("BURST_VFX_RENDER_FAILED ",JSON.stringify(result))
		quit(1)

extends "res://tests/godot_phase_b.gd"

var results := {}
var measuring := false
var frame_times: Array[float] = []
var previous_time := 0
var peak_memory := 0.0
var peak_nodes := 0.0

func measure() -> void:
	if not measuring:
		return
	var now := Time.get_ticks_usec()
	frame_times.append(float(now - previous_time) / 1000)
	previous_time = now
	peak_memory = maxf(peak_memory, Performance.get_monitor(Performance.MEMORY_STATIC))
	peak_nodes = maxf(peak_nodes, Performance.get_monitor(Performance.OBJECT_NODE_COUNT))

func _run() -> void:
	route_frame_limit = 90000
	facade_min_length = 6.0
	root.content_scale_size = Vector2i(1280, 720)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	root.size = Vector2i(1280, 720)
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	process_frame.connect(measure)
	world = Main.instantiate()
	root.add_child(world)
	await physics_frame
	await physics_frame
	if world.player == null:
		check(false, world.runtime_error)
		quit(1)
		return
	car = world.player
	car.external_control = true
	await step(60)
	var expansion: Dictionary = world.expansion
	var profile: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://config/expansion_config.json"))
	check(expansion["active_blocks"].size() == profile["active_blocks"].size(), "All configured urban blocks expected")
	var critical := "--critical-corridors" in OS.get_cmdline_user_args()
	var entries: Array = expansion.get("critical_routes", []) if critical else expansion["routes"]
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--route="):
			var selected := argument.trim_prefix("--route=")
			entries = entries.filter(func(entry: Dictionary): return entry["id"] == selected)
	check(not entries.is_empty(), "Expected driving routes")
	for entry in entries:
		points.clear()
		lengths.clear()
		route_progress = 0
		route_index = 0
		metrics = {}
		var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://" + entry["file"]))
		world.environment_data["driving_test_route"] = data
		frame_times.clear()
		peak_memory = 0
		peak_nodes = 0
		previous_time = Time.get_ticks_usec()
		measuring = true
		print("C5_DRIVE_START ", entry["id"], " ", entry["length_m"])
		await drive_route()
		measuring = false
		frame_times.sort()
		var total := 0.0
		for value in frame_times:
			total += value
		var record := {"driving": metrics.duplicate(), "urban_streaming": world.city_manager.status(), "road_streaming": world.road_root.status(), "mean_frame_ms": total / max(1, frame_times.size()), "p95_frame_ms": frame_times[int(frame_times.size() * 0.95)] if not frame_times.is_empty() else 0, "max_frame_ms": frame_times[-1] if not frame_times.is_empty() else 0, "peak_static_memory_bytes": peak_memory, "peak_nodes": peak_nodes}
		if DisplayServer.get_name() != "headless":
			check(record["p95_frame_ms"] <= float(profile["acceptance"]["max_p95_frame_ms"]), "Rendered traversal p95 exceeds budget")
			check(peak_memory <= float(profile["acceptance"]["max_static_memory_mb"]) * 1024 * 1024, "Rendered traversal memory exceeds budget")
		results[entry["id"]] = record
		print("C5_DRIVE_END ", entry["id"], " ", JSON.stringify(record))
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://docs/evidence/phase_c5_" + entry["id"] + ".png")
	# Actual facade and SpringArm collisions in each new neighborhood.
	var facades := {}
	for anchor in expansion["anchors"]:
		var p: Array = anchor["position_xz"]
		place(Vector3(p[0], 0.67, p[1]), Vector3.FORWARD)
		await step(40)
		metrics = {}
		await facade_and_camera()
		facades[anchor["id"]] = metrics.duplicate()
	# Reset from the farthest active corridor after core sectors have streamed out.
	for anchor in expansion["anchors"]:
		if anchor["id"] == "conexion_sur":
			var p: Array = anchor["position_xz"]
			place(Vector3(p[0], 0.67, p[1]), Vector3.FORWARD)
			await step(60)
	var previous_recoveries: int = car.recovery_count
	world.hud.menu_open = true
	world.hud.set_pause(true)
	world.hud.buttons[1].pressed.emit()
	await step(30)
	check(car.recovery_count == previous_recoveries + 1 and car.position.distance_to(car.spawn_transform.origin) < 0.2 and car.on_asphalt and car.is_on_floor(), "Restart from distant corridor must prime core road support")
	check(world.city_manager.max_loaded_chunks <= int(profile["acceptance"]["max_loaded_urban_chunks"]), "Urban sector budget exceeded")
	check(world.city_manager.failed_chunks.is_empty(), "No corrupt or missing streamed city sectors")
	check(world.city_manager.max_loaded_chunks < world.city_manager.manifest["chunks"].size(), "Urban streaming must unload distant city")
	check(world.road_root.max_loaded < world.road_root.entries.size(), "Road streaming must keep a bounded neighbourhood")
	var report := {"passed": failures.is_empty(), "failures": failures, "rendered": DisplayServer.get_name() != "headless", "viewport_px": [root.get_texture().get_width(), root.get_texture().get_height()], "routes": results, "anchor_facade_tests": facades, "physics_frames": test_frames, "world": world.stats}
	var path := "res://docs/phase_c5_south_cut_driving_render.json" if report["rendered"] else "res://docs/phase_c5_south_cut_driving.json"
	if critical:
		path = "res://docs/cajoncito_driving_render.json" if report["rendered"] else "res://docs/cajoncito_driving.json"
	var output := FileAccess.open(path, FileAccess.WRITE)
	output.store_string(JSON.stringify(report, "  "))
	print("C5_REPORT ", JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)

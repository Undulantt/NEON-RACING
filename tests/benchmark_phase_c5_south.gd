extends SceneTree

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	root.content_scale_size = Vector2i(1280, 720)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	root.size = Vector2i(1280, 720)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var world := preload("res://scenes/Main.tscn").instantiate()
	var start := Time.get_ticks_usec()
	root.add_child(world)
	var startup_ms := float(Time.get_ticks_usec() - start) / 1000
	world.player.external_control = true
	world.player.set_controls(0, 0)
	var warmup := Time.get_ticks_usec()
	while Time.get_ticks_usec() - warmup < 2000000:
		await process_frame
	var times: Array[float] = []
	var previous := Time.get_ticks_usec()
	start = previous
	var peak_memory := 0.0
	var peak_nodes := 0.0
	while Time.get_ticks_usec() - start < 5000000:
		await process_frame
		var now := Time.get_ticks_usec()
		times.append(float(now - previous) / 1000)
		previous = now
		peak_memory = maxf(peak_memory, Performance.get_monitor(Performance.MEMORY_STATIC))
		peak_nodes = maxf(peak_nodes, Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	times.sort()
	var elapsed := float(previous - start) / 1000000
	var report := {"scenario": "Same core spawn and camera; VSync off; 2s warmup plus 5s render sample; not a traversal benchmark", "startup_ms": startup_ms, "mean_frame_ms": elapsed * 1000 / times.size(), "average_fps": times.size() / elapsed, "p95_ms": times[int(times.size() * 0.95)], "max_frame_ms": times[-1], "peak_static_memory_bytes": peak_memory, "peak_nodes": peak_nodes, "viewport_px": [root.get_texture().get_width(), root.get_texture().get_height()], "streaming": world.city_manager.status()}
	var baseline := false
	var path := "res://docs/cajoncito_benchmark.json"
	if not baseline:
		var old = JSON.parse_string(FileAccess.get_file_as_string("res://docs/phase_c5_benchmark.json"))
		report["mean_frame_ratio"] = report["mean_frame_ms"] / old["mean_frame_ms"]
		report["static_memory_ratio"] = peak_memory / old["peak_static_memory_bytes"]
	if not baseline:
		var profile: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://config/expansion_config.json"))
		var criteria: Dictionary = profile["acceptance"]
		report["passed"] = report["mean_frame_ratio"] <= criteria["max_mean_frame_ratio"] and report["static_memory_ratio"] <= criteria["max_static_memory_ratio"] and report["average_fps"] >= criteria["minimum_render_fps"]
	var output := FileAccess.open(path, FileAccess.WRITE)
	output.store_string(JSON.stringify(report, "  "))
	print("C5_BENCHMARK ", JSON.stringify(report))
	quit(0 if baseline or report.get("passed", false) else 1)

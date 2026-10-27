extends SceneTree

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	root.content_scale_size = Vector2i(1280,720)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	root.size = Vector2i(1280,720)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var world := preload("res://scenes/Main.tscn").instantiate()
	# Baseline is explicit now that the shipped main scene enables full relief.
	# --relief-pilot/--relief-world still select the paired measured profile.
	world.relief_profile = "flat"
	var begin := Time.get_ticks_usec()
	root.add_child(world)
	var startup := float(Time.get_ticks_usec()-begin)/1000
	if world.player == null:
		quit(1)
		return
	world.player.external_control = true
	var warmup := Time.get_ticks_usec()
	while Time.get_ticks_usec()-warmup<2000000:
		await process_frame
	var times: Array[float] = []
	var physics_times: Array[float] = []
	var previous := Time.get_ticks_usec()
	begin = previous
	var memory := 0.0
	var nodes := 0.0
	var primitives := 0.0
	var pairs := 0.0
	var long_frames: Array = []
	while Time.get_ticks_usec()-begin<5000000:
		await process_frame
		var now := Time.get_ticks_usec()
		var frame_ms := float(now-previous)/1000
		times.append(frame_ms)
		if frame_ms>16.67 and long_frames.size()<10:
			long_frames.append({"frame_ms":frame_ms,"process_monitor_ms":Performance.get_monitor(Performance.TIME_PROCESS)*1000,"physics_monitor_ms":Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000,"urban_pending":world.city_manager.pending.size(),"road_loads":world.road_root.total_loads})
		previous = now
		physics_times.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000)
		memory = maxf(memory,Performance.get_monitor(Performance.MEMORY_STATIC))
		nodes = maxf(nodes,Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
		primitives = maxf(primitives,Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
		pairs = maxf(pairs,Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS))
	times.sort()
	var mean := float(previous-begin)/1000/times.size()
	var baseline: bool = world.relief_flat_baseline or world.relief_manifest.is_empty()
	var world_test := "--benchmark-world" in OS.get_cmdline_user_args()
	var report := {"scenario":"Same spawn XZ, camera, buildings, streaming radii, viewport and renderer; original flat road triangles+safety platform versus CEM4 terrain and roads; static 2s warmup+5s sample", "scope":"full_world" if world_test else "isolated_pilot",
		"baseline":baseline,"rendered":DisplayServer.get_name()!="headless","startup_ms":startup,"mean_frame_ms":mean,"average_fps":1000/mean,"p95_ms":times[int(times.size()*.95)],"p99_ms":times[int(times.size()*.99)],"max_frame_ms":times[-1],
		"peak_static_memory_bytes":memory,"peak_nodes":nodes,"peak_render_primitives":primitives,"peak_collision_pairs":pairs,"mean_physics_monitor_ms":mean_array(physics_times),"viewport_px":[1280,720],"road_streaming":world.road_root.status(),"terrain_streaming":world.terrain_root.status() if world.terrain_root!=null else {},"urban_streaming":world.city_manager.status(),"long_frames":long_frames}
	var suffix := "flat" if baseline else "relief"
	if world_test:
		suffix = "world_" + suffix
	var sample_tag := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--sample="):
			sample_tag = "_" + argument.trim_prefix("--sample=")
	var file := FileAccess.open("res://docs/phase_b7r_benchmark_"+suffix+sample_tag+".json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://docs/evidence/phase_b7r_"+suffix+".png")
	print("RELIEF_BENCHMARK ",JSON.stringify(report))
	quit(0)

func mean_array(values: Array[float]) -> float:
	var total := 0.0
	for value in values:
		total += value
	return total / maxi(1,values.size())

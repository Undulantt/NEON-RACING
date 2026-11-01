extends SceneTree
func _initialize() -> void:
	run.call_deferred()
func run() -> void:
	root.size = Vector2i(1280,720)
	root.content_scale_size = Vector2i(1280,720)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var results := {}
	var boost_test := OS.get_cmdline_user_args().has("--turbo")
	for enabled in [false,true]:
		var world = load("res://scenes/NightPilot.tscn").instantiate()
		world.night_enabled = enabled
		root.add_child(world)
		world.player.external_control = true
		for i in range(540):
			if i%180 == 0:
				world.player.global_transform = world.player.spawn_transform
				world.player.velocity = Vector3.ZERO
				world.player.reset_surface_motion()
				world.player.turbo_charge = 1.0
			world.player.set_controls(1,0,false,boost_test and i%180>=110)
			await process_frame
		var intervals: Array[float] = []
		var peak_memory := 0.0
		var max_nodes := 0.0
		var previous := Time.get_ticks_usec()
		var offroad := 0
		var boost_frames := 0
		for i in range(1080):
			if i%180 == 0:
				world.player.global_transform = world.player.spawn_transform
				world.player.velocity = Vector3.ZERO
				world.player.speed_mps = 0
				world.player.signed_speed = 0
				world.player.reset_surface_motion()
				world.player.turbo_charge = 1.0
				world.follow_camera.snap()
			world.player.set_controls(1,0,false,boost_test and i%180>=110)
			await process_frame
			var now := Time.get_ticks_usec()
			intervals.append(float(now-previous)/1000)
			previous = now
			peak_memory = maxf(peak_memory,Performance.get_monitor(Performance.MEMORY_STATIC))
			max_nodes = maxf(max_nodes,Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
			if world.player.turbo_active:
				boost_frames += 1
			if not world.player.on_asphalt:
				offroad += 1
		intervals.sort()
		var total := 0.0
		for value in intervals:
			total += value
		results[str(enabled)] = {"mean_ms":total/intervals.size(),"p95_ms":intervals[int(intervals.size()*0.95)],"max_ms":intervals[-1],"fps":1000*intervals.size()/total,"peak_static_memory":peak_memory,"peak_nodes":max_nodes,"offroad_frames":offroad,"boost_frames":boost_frames,"streaming":world.city_manager.status()}
		world.queue_free()
		await process_frame
		await process_frame
	var ratio: float = results["true"]["mean_ms"]/results["false"]["mean_ms"]
	var report := {"scenario":"1280x720 Compatibility, VSync off, fixed simulation 60 Hz; same short acceleration repeated six times, 1080 rendered frames per mode; no city-wide traversal","turbo_test":boost_test,"results":results,"mean_ratio":ratio,"passed":ratio<=1.15 and results["true"]["offroad_frames"]==0 and (not boost_test or results["true"]["boost_frames"]>300)}
	FileAccess.open("res://docs/phase_e_motion_benchmark.json" if boost_test else "res://docs/phase_e_benchmark.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("PHASE_E_BENCHMARK ",JSON.stringify(report))
	quit(0 if report["passed"] else 1)

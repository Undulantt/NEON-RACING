extends SceneTree

const Main = preload("res://scenes/Main.tscn")
var reports := {}

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	# Fix the render viewport independently of Windows DPI/window resizing.
	root.content_scale_size = Vector2i(1280,720)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	root.size = Vector2i(1280,720)
	for mode in ["legacy", "urban", "urban_hidden"]:
		var world: Node3D = Main.instantiate()
		world.legacy_city = mode=="legacy"
		root.add_child(world)
		world.player.external_control = true
		world.player.set_controls(0,0)
		if mode=="urban_hidden":
			world.city_manager.set_city_enabled(false)
		var start := Time.get_ticks_usec()
		while Time.get_ticks_usec()-start<2000000:
			await process_frame
		var intervals: Array[float]=[]
		var calls := 0.0
		var primitives := 0.0
		var previous := Time.get_ticks_usec()
		start=previous
		while Time.get_ticks_usec()-start<5000000:
			await process_frame
			var now := Time.get_ticks_usec()
			intervals.append(float(now-previous)/1000)
			previous=now
			calls+=Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
			primitives+=Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
		var elapsed := float(previous-start)/1000000
		intervals.sort()
		var count := intervals.size()
		var record := {"average_fps":count/elapsed,"sample_s":elapsed,"frames":count,"p95_frame_ms":intervals[int(count*0.95)],"max_frame_ms":intervals[-1],"mean_draw_calls":calls/count,"mean_visible_primitives":primitives/count,"viewport_px":[root.get_texture().get_width(),root.get_texture().get_height()],"nodes":Performance.get_monitor(Performance.OBJECT_NODE_COUNT),"world":world.stats,"streaming":world.city_manager.status() if world.city_manager!=null else {}}
		reports[mode]=record
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://docs/evidence/phase_b5_"+mode+".png")
		print("URBAN_BENCHMARK_MODE ",mode," ",JSON.stringify(record))
		world.queue_free()
		await process_frame
	var report := {"scenario":"Static spawn, same camera, fixed 1280x720 viewport, 2s warmup + 5s sample per mode; not a sustained driving benchmark","results":reports,"urban_to_legacy_fps_ratio":reports["urban"]["average_fps"]/reports["legacy"]["average_fps"]}
	var file := FileAccess.open("res://docs/phase_b5_benchmark.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	print("PHASE_B5_BENCHMARK ",JSON.stringify(report))
	quit()

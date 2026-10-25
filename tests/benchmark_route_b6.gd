extends "res://tests/godot_phase_b.gd"
var measuring := false
var intervals: Array[float] = []
var previous := 0
var peak_memory := 0.0
var peak_nodes := 0.0
func measure() -> void:
	if not measuring:
		return
	var now := Time.get_ticks_usec()
	intervals.append(float(now - previous) / 1000.0)
	previous = now
	peak_memory = maxf(peak_memory, Performance.get_monitor(Performance.MEMORY_STATIC))
	peak_nodes = maxf(peak_nodes, Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
func _run() -> void:
	root.content_scale_size = Vector2i(1280,720)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	root.size = Vector2i(1280,720)
	process_frame.connect(measure)
	var results := {}
	for mode in ["b5_equivalent", "b6"]:
		world = Main.instantiate()
		world.baseline_b6 = mode == "b5_equivalent"
		root.add_child(world)
		car = world.player
		car.external_control = true
		await step(120)
		points.clear()
		lengths.clear()
		route_progress = 0
		route_index = 0
		metrics = {}
		intervals.clear()
		peak_memory = 0
		peak_nodes = 0
		previous = Time.get_ticks_usec()
		measuring = true
		await drive_route()
		measuring = false
		var total := 0.0
		for interval in intervals:
			total += interval
		intervals.sort()
		results[mode] = {"mean_frame_ms":total/intervals.size(),"average_fps":1000.0*intervals.size()/total,"p95_frame_ms":intervals[int(intervals.size()*0.95)],"max_frame_ms":intervals[-1],"render_frames":intervals.size(),"peak_static_memory_bytes":peak_memory,"peak_nodes":peak_nodes,"route":metrics.duplicate(),"streaming":world.city_manager.status()}
		print("B6_ROUTE_MODE ", mode, " ", JSON.stringify(results[mode]))
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://docs/evidence/phase_b6_route_"+mode+".png")
		world.queue_free()
		await process_frame
		await process_frame
	check(results["b6"]["mean_frame_ms"] / results["b5_equivalent"]["mean_frame_ms"] <= 1.15, "frame-time regression exceeds 15 percent")
	var report := {"passed":failures.is_empty(),"failures":failures,"scenario":"Same 1.2 km route, production car, 1280x720; B5-equivalent uses same footprints with B6 cosmetics and geography disabled","results":results,"frame_time_ratio":results["b6"]["mean_frame_ms"]/results["b5_equivalent"]["mean_frame_ms"]}
	var output := FileAccess.open("res://docs/phase_b6_route_benchmark.json",FileAccess.WRITE)
	output.store_string(JSON.stringify(report,"  "))
	quit(0 if failures.is_empty() else 1)

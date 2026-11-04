extends SceneTree

var world: Node3D
var car: CharacterBody3D
var hud: CanvasLayer
var flames: Node3D
var bursts := false
var results: Array = []

func _initialize() -> void:
	run.call_deferred()

func frame() -> void:
	if bursts:
		if flames.marks.size() != flames.instances.instance_count:
			flames.clear_trail()
			for i in range(flames.instances.instance_count):
				var track := i % 2
				var wheel: Node3D = car.visuals["pivots"][track+2]
				var point := wheel.global_position + car.global_basis.z * (1 + (i/2) * 0.4)
				var start: Dictionary = flames.ground_at(point + car.global_basis.z * 0.3)
				var finish: Dictionary = flames.ground_at(point - car.global_basis.z * 0.3)
				if start.is_empty() or finish.is_empty():
					continue
				flames.append_segment(track,start,finish)
			flames.last_car_position = car.global_position
		for mark in flames.marks:
			mark["born"] = flames.clock - 0.10
	await process_frame
	await RenderingServer.frame_post_draw

func sample(name: String, burst: bool) -> void:
	bursts = burst
	car.abilities.burst_state = 2 if burst else 0
	car.abilities.burst_time = 4.0 if burst else 0.0
	car.abilities.burst_bonus = 0.20 if burst else 0.0
	for i in range(150):
		await frame()
	var intervals: Array[float] = []
	var previous := Time.get_ticks_usec()
	var draw_calls := 0.0
	var peak_marks := 0
	for i in range(360):
		await frame()
		var now := Time.get_ticks_usec()
		intervals.append(float(now - previous) / 1000.0)
		previous = now
		draw_calls += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		peak_marks = maxi(peak_marks, flames.marks.size())
	intervals.sort()
	var total := 0.0
	for value in intervals:
		total += value
	var value := {"name":name,"mean_ms":total/intervals.size(),"median_ms":intervals[intervals.size()/2],"p95_ms":intervals[int(intervals.size()*0.95)],"draw_calls":draw_calls/intervals.size(),"max_flames":peak_marks,"burst":burst}
	results.append(value)
	print("BURST_VFX_BENCH_SAMPLE ",JSON.stringify(value))

func run() -> void:
	root.size = Vector2i(1280,720)
	root.content_scale_size = Vector2i(1280,720)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	world = preload("res://scenes/NightPilot.tscn").instantiate()
	root.add_child(world)
	car = world.player
	hud = world.hud
	flames = hud.ground_flames
	car.external_control = true
	car.set_controls(0,0)
	for i in range(180):
		await frame()
	# Fixed geometry and camera isolate visual cost. No claim of driving FPS.
	car.set_physics_process(false)
	world.follow_camera.set_physics_process(false)
	world.follow_camera.camera.fov = 95
	car.speed_mps = 60
	car.signed_speed = 60
	car.abilities.current_speed_cap = car.base_speed_cap * 1.2
	await sample("normal_A", false)
	await sample("burst_A", true)
	await sample("burst_B", true)
	await sample("normal_B", false)
	var normal_mean: float = (results[0]["mean_ms"] + results[3]["mean_ms"]) * 0.5
	var burst_mean: float = (results[1]["mean_ms"] + results[2]["mean_ms"]) * 0.5
	var overhead := burst_mean - normal_mean
	var economical := overhead <= maxf(2.0, normal_mean * 0.5)
	var report := {"passed":economical,"scenario":"1280x720 Compatibility / VSync off; static NightPilot geometry and fixed 95-degree FOV; 128 stressed wheel-track segments; 150 warmup and 360 rendered samples per stage; normal/BURST/BURST/normal comparison; timing includes test harness and is not city-traversal FPS","samples":results,"burst_overhead_ms":overhead,"burst_overhead_percent":overhead/normal_mean*100,"additional_draw_calls":float(results[1]["draw_calls"])-float(results[0]["draw_calls"]),"gpu":RenderingServer.get_video_adapter_name()}
	FileAccess.open("res://docs/burst_vfx_benchmark.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("BURST_VFX_BENCHMARK ",JSON.stringify(report))
	world.queue_free()
	for i in range(4):
		await process_frame
	quit(0 if economical else 1)

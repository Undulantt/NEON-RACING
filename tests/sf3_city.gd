extends "res://tests/sf1_city.gd"
var registration_max_us:=0
var sf3_failures: Array=[]
func check_sf3(value: bool, message: String) -> void:
	if not value: sf3_failures.append(message);push_error(message)

func render_frame() -> void:
	# Keep the camera fixed while driving the presentation model, not car physics.
	if is_instance_valid(world) and world.follow_camera!=null:
		world.follow_camera.speed_feedback.sample(1.0/60)
	await super.render_frame()

func benchmark() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	car.set_physics_process(false)
	car.speed_mps=car.base_speed_cap;car.forward_plane_speed=car.base_speed_cap
	car.powertrain.rpm=6500;car.powertrain.gear=7;car.powertrain.load=1
	car.abilities.burst_time=5.0
	car.abilities.burst_state=2;car.abilities.burst_bonus=float(car.config["burst_max_bonus"])
	var rig: Node3D=world.follow_camera
	rig.set_physics_process(false)
	rig.camera.fov=75
	var environment: Node=rig.speed_feedback.environment_feedback
	environment.reset_experiment()
	# Isolate environment in screenshots; existing screen streaks stay the same (off).
	for effect in world.hud.get_children():
		if effect.get_script()==load("res://scripts/ui/SpeedEffects.gd"): effect.effect_strength=0
	# Finish the current decoration coroutine, then freeze cosmetic generation equally.
	var warmup_end:=Time.get_ticks_msec()+6500
	while Time.get_ticks_msec()<warmup_end: await render_frame()
	while world.night_style.decorating: await render_frame()
	world.night_style.set_process(false)
	if "--capture-only" in OS.get_cmdline_user_args():
		await capture_views(environment)
		cleanup()
		quit(0)
		return
	for mode in ["original","partial","full","full","partial","original"]:
		environment.set_mode(mode)
		var until:=Time.get_ticks_msec()+3000
		while Time.get_ticks_msec()<until: await render_frame()
		var intervals: Array[float]=[]
		var update_us:=0.0
		var previous:=Time.get_ticks_usec()
		var bindings: int=environment.bindings.size()
		for i in range(600):
			await render_frame()
			var now:=Time.get_ticks_usec()
			intervals.append(float(now-previous)/1000)
			previous=now
			update_us+=environment.last_update_us
			registration_max_us=maxi(registration_max_us,environment.last_registration_us)
		intervals.sort()
		var total:=0.0
		for v in intervals: total+=v
		var sample:={"mode":mode,"mean_ms":total/600,"median_ms":intervals[300],"p95_ms":intervals[570],"environment_mean_us":update_us/600,"bindings":bindings,"active_light_pools":count_pools(environment),"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)}
		sf1_results.append(sample)
		print("SF3_BENCH_SAMPLE ",JSON.stringify(sample))
		if sf1_results.size()<=3: root.get_texture().get_image().save_png("res://docs/evidence/sf3_%s.png"%mode)
		check_sf3(environment.bindings.size()<=96,"Bindings are bounded")
		if mode=="original":
			check_sf3(environment.bindings.is_empty(),"Original restores every material override")
			check_sf3(float(environment.road_material.get_shader_parameter("sf3_asphalt"))==0,"Original asphalt is disabled")
		else: check_sf3(environment.bindings.size()>0,"Existing real markings are bound")
	environment.set_mode("full")
	rig.experiment_panel.open_requested=true
	rig.experiment_panel.tabs.current_tab=2
	var until:=Time.get_ticks_msec()+1500
	while Time.get_ticks_msec()<until: await render_frame()
	root.get_texture().get_image().save_png("res://docs/evidence/sf3_panel.png")
	var original: float=(sf1_results[0]["mean_ms"]+sf1_results[5]["mean_ms"])/2
	var full: float=(sf1_results[2]["mean_ms"]+sf1_results[3]["mean_ms"])/2
	check_sf3(full-original<=maxf(1.0,original*0.15),"Full mode meets the 1 ms / 15% static benchmark budget")
	var report:={"passed":sf3_failures.is_empty(),"failures":sf3_failures,"scenario":"Existing full city 1280x720 Compatibility, VSync off; same frozen decoration/pose/camera/FOV75, synthetic max-normal speed with full BURST telemetry; screen streaks disabled equally; original/partial/full/full/partial/original, 3s warmup and 600 rendered wall-clock samples each; NOT city traversal FPS","gpu":RenderingServer.get_video_adapter_name(),"samples":sf1_results,"full_minus_original_ms":full-original,"max_registration_us":registration_max_us}
	FileAccess.open("res://docs/sf3_benchmark.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("SF3_BENCHMARK ",JSON.stringify(report))
	cleanup()
	quit(0 if sf3_failures.is_empty() else 1)

func count_pools(environment: Node) -> int:
	var total:=0
	if environment.furniture!=null:
		for pool in environment.furniture.street_pools:
			if pool.w>0: total+=1
	return total

func capture_views(environment: Node) -> void:
	for mode in ["original","partial","full"]:
		environment.set_mode(mode)
		var until:=Time.get_ticks_msec()+1500
		while Time.get_ticks_msec()<until: await render_frame()
		root.get_texture().get_image().save_png("res://docs/evidence/sf3_%s.png"%mode)
	world.follow_camera.experiment_panel.open_requested=true
	world.follow_camera.experiment_panel.tabs.current_tab=2
	for i in range(12): await render_frame()
	world.follow_camera.experiment_panel.refresh_timer=0
	await render_frame()
	root.get_texture().get_image().save_png("res://docs/evidence/sf3_panel.png")
	print("SF3_CAPTURES_OK")

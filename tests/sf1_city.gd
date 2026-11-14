extends "res://tests/benchmark_burst_balance.gd"
# Reuses an existing OSM path and the existing test driver. Never creates a race.
var sf1_results := []
var sf1_spawn := {}
var restarting := false

func run() -> void:
	var flow := root.get_node("GameFlow")
	flow.settings_path = "res://tests/.sf1_city_settings.cfg"
	root.size=Vector2i(1280,720)
	root.content_scale_size=Vector2i(1280,720)
	change_scene_to_file(flow.definition["menu_scene"])
	await process_frame
	flow.show_screen(&"play_menu")
	flow.choose_mode(&"free_drive")
	flow.select_vehicle("VECTOR")
	flow.start_selected()
	var deadline := Time.get_ticks_msec()+90000
	while flow.transition_busy or flow.current_state != &"free_drive":
		await process_frame
		if Time.get_ticks_msec()>deadline: quit(1);return
	world=current_scene
	car=world.player
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tracks/extension_C2.json"))
	var geometry: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://docs/burst_route_geometry.json"))
	var span: Dictionary = geometry["extension_C2"]["longest_runs"][0]
	build_path(data["points_xz"].slice(int(span["first_point_index"]),int(span["last_point_index"])+1))
	var at := sample(3)
	var forward := (points[1]-points[0]).normalized()
	sf1_spawn={"position_xz":[at.x,at.z],"forward_xz":[forward.x,forward.z]}
	await restart_route()
	if not world.runtime_error.is_empty(): push_error(world.runtime_error);quit(1);return
	if "--manual-route" in OS.get_cmdline_user_args() or "--manual-smoke" in OS.get_cmdline_user_args():
		world.follow_camera.experiment_panel.add_button("restart_route","Reiniciar tramo OSM (SF.1)",restart_route,world.follow_camera.experiment_panel.panel.get_child(0))
		print("SF1_MANUAL_ROUTE: Existing extension_C2 points 25..42, %.2f m; Ctrl+Alt+P settings/restart, Ctrl+Alt+B A/B"%lengths[-1])
		if "--manual-smoke" in OS.get_cmdline_user_args(): await manual_smoke()
		return
	if "--benchmark" in OS.get_cmdline_user_args():
		await benchmark()
		return
	car.external_control=true
	var compare_environment: bool="--sf3-compare" in OS.get_cmdline_user_args()
	for enabled in [false,true]:
		world.follow_camera.speed_feedback.reset_experiment()
		world.follow_camera.speed_feedback.set_experimental(true if compare_environment else enabled)
		if compare_environment: world.follow_camera.speed_feedback.environment_feedback.set_mode("full" if enabled else "original")
		await restart_route()
		car.external_control=true
		var value: Dictionary = await route("VECTOR",6000)
		value["mode"]="B" if enabled else "A"
		sf1_results.append(value)
		print("SF1_CITY_DRIVE ",JSON.stringify(value))
	var passed := true
	for value in sf1_results: passed=passed and value["completed"] and value["recoveries"]==0 and value["wall_contacts"]==0 and value["burst_seconds"]>0
	var output := {"comparison":"SF.3 original/full with identical camera/audio" if compare_environment else "Camera A/B","passed":passed,"source":"Existing extension_C2 OSM path, points 25..42; existing pure-pursuit test driver; actual unchanged physical controller; no teleports during route","samples":sf1_results}
	FileAccess.open("res://docs/sf3_city_drive.json" if compare_environment else "res://docs/sf1_city_drive.json",FileAccess.WRITE).store_string(JSON.stringify(output,"  "))
	cleanup()
	quit(0 if passed else 1)

func restart_route() -> void:
	if restarting or not is_instance_valid(world): return
	restarting=true
	await world.prepare_at(sf1_spawn)
	car.abilities.reset("sf1_test_restart")
	car.powertrain.reset()
	car.driving_enabled=true
	car.external_control=false
	world.follow_camera.snap()
	restarting=false

func render_frame() -> void:
	await process_frame
	await RenderingServer.frame_post_draw

func manual_smoke() -> void:
	var panel: CanvasLayer=world.follow_camera.experiment_panel
	var mode: bool=world.follow_camera.speed_feedback.settings["experimental_enabled"]
	var audio_mode: bool=world.follow_camera.speed_feedback.audio_feedback.settings["experimental_enabled"]
	var environment_mode: String=world.follow_camera.speed_feedback.environment_feedback.mode()
	var key:=InputEventKey.new()
	key.keycode=KEY_W;key.physical_keycode=KEY_W;key.pressed=true
	Input.parse_input_event(key)
	await step(8)
	for code in [KEY_P,KEY_B,KEY_O,KEY_L]:
		key=InputEventKey.new()
		key.keycode=code;key.physical_keycode=code;key.pressed=true;key.ctrl_pressed=true;key.alt_pressed=true
		Input.parse_input_event(key)
		await step(3)
	var passed: bool=world.follow_camera.speed_feedback.environment_feedback.mode()!=environment_mode and world.follow_camera.speed_feedback.audio_feedback.settings["experimental_enabled"]!=audio_mode and panel.open_requested and world.follow_camera.speed_feedback.settings["experimental_enabled"]!=mode and car.throttle_input>0.99 and panel.can_use()
	key=InputEventKey.new()
	key.keycode=KEY_W;key.physical_keycode=KEY_W;key.pressed=false
	Input.parse_input_event(key)
	await restart_route()
	passed=passed and panel.buttons.has("restart_route") and car.driving_enabled and world.runtime_error.is_empty()
	var result:={"passed":passed,"native_shortcuts_and_W_throttle":passed,"restart_on_existing_road":world.runtime_error.is_empty()}
	FileAccess.open("res://docs/sf1_manual_validation.json",FileAccess.WRITE).store_string(JSON.stringify(result,"  "))
	print("SF1_MANUAL_SMOKE ",JSON.stringify(result))
	cleanup()
	quit(0 if passed else 1)

func benchmark() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	# Identical static car/telemetry: isolates presentation, NOT driving performance.
	car.set_physics_process(false)
	car.speed_mps=50
	car.forward_plane_speed=50
	car.signed_speed=50
	car.abilities.burst_state=2
	car.abilities.burst_bonus=float(car.config["burst_max_bonus"])*0.5
	car.abilities.burst_time=5
	var rig: Node3D=world.follow_camera
	rig.speed_feedback.reset_experiment()
	for mode in [false,true,true,false]:
		rig.speed_feedback.set_experimental(mode)
		var warmup_until := Time.get_ticks_msec()+3500
		while Time.get_ticks_msec()<warmup_until: await render_frame()
		var intervals: Array[float]=[]
		var camera_us := 0.0
		var previous := Time.get_ticks_usec()
		for i in range(600):
			await render_frame()
			var now := Time.get_ticks_usec()
			intervals.append(float(now-previous)/1000)
			previous=now
			camera_us+=rig.sf1_camera_us
		intervals.sort()
		var total := 0.0
		for v in intervals: total+=v
		var value := {"mode":"B" if mode else "A","mean_ms":total/intervals.size(),"median_ms":intervals[300],"p95_ms":intervals[570],"camera_mean_us":camera_us/600}
		sf1_results.append(value)
		print("SF1_BENCH_SAMPLE ",JSON.stringify(value))
		if sf1_results.size()<3:
			root.get_texture().get_image().save_png("res://docs/evidence/sf1_%s_180kmh.png"%value["mode"])
	rig.speed_feedback.set_experimental(true)
	rig.experiment_panel.open_requested=true
	var panel_until := Time.get_ticks_msec()+3500
	while Time.get_ticks_msec()<panel_until: await render_frame()
	root.get_texture().get_image().save_png("res://docs/evidence/sf1_panel.png")
	var a: float=(sf1_results[0]["mean_ms"]+sf1_results[3]["mean_ms"])*0.5
	var b: float=(sf1_results[1]["mean_ms"]+sf1_results[2]["mean_ms"])*0.5
	var passed := b-a<=maxf(1.0,a*0.15)
	var output := {"passed":passed,"scenario":"1280x720, Compatibility, VSync off, existing complete city, same frozen pose and synthetic 180 km/h / half BURST telemetry; A/B/B/A, 3.5 seconds warmup and 600 rendered wall-clock samples each; NOT city-traversal FPS","gpu":RenderingServer.get_video_adapter_name(),"samples":sf1_results,"B_minus_A_ms":b-a,"B_overhead_percent":(b/a-1)*100,"regression_budget":"max(1 ms, 15% of A)"}
	FileAccess.open("res://docs/sf1_benchmark.json",FileAccess.WRITE).store_string(JSON.stringify(output,"  "))
	print("SF1_BENCHMARK ",JSON.stringify(output))
	cleanup()
	quit(0 if passed else 1)

func cleanup() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(root.get_node("GameFlow").settings_path))

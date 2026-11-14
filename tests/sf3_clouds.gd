extends "res://tests/sf1_city.gd"
var cloud_failures: Array[String] = []
var cloud_checks := 0

func verify(value: bool, message: String) -> void:
	cloud_checks += 1
	if not value: cloud_failures.append(message);push_error(message)

func benchmark() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	car.set_physics_process(false)
	world.follow_camera.set_physics_process(false)
	var clouds: Node3D = world.night_style.clouds
	clouds.set_process(false)
	clouds.set_enabled(true)
	clouds.elapsed=0.0
	clouds.advance(0)
	verify(clouds.batch.multimesh.instance_count==81,"Bounded field of 81 instanced flat clouds")
	verify(clouds.batch.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,"Clouds never cast shadows")
	verify(clouds.find_children("*","CollisionObject3D",true,false).is_empty(),"Clouds have no collisions")
	var tracked: Vector2i=clouds.last_cell+Vector2i(1,2)
	var original: Vector3=clouds.cloud_world_position(tracked)
	var camera: Camera3D=world.follow_camera.camera
	var camera_pose:=camera.global_transform
	var projected:=camera.unproject_position(original)
	var physics: Array=[car.global_transform,car.velocity,car.config.duplicate(true),car.vehicle_profile,car.abilities.burst_bonus]
	var count: int=clouds.rebuilds
	for i in range(120): clouds.advance(0)
	verify(clouds.rebuilds==count,"No per-frame instance regeneration while in one grid cell")
	camera.global_position.x+=100
	clouds.advance(0)
	verify(clouds.cloud_world_position(tracked).distance_to(original)<0.001,"Cloud does not follow a translated camera")
	verify(camera.unproject_position(original).distance_to(projected)>0.5,"Finite position produces visible camera parallax")
	camera.global_position.x+=float(clouds.settings["cell_size_m"])*1.1
	clouds.advance(0)
	verify(clouds.rebuilds>count,"Crossing a cell recycles the bounded field")
	verify(clouds.cloud_world_position(tracked).distance_to(original)<0.001,"Shared clouds retain their world position across recycling")
	camera.global_transform=camera_pose
	clouds.advance(0)
	clouds.advance(60)
	var wind: Vector2=clouds.wind_offset()
	verify(clouds.cloud_world_position(tracked).distance_to(original+Vector3(wind.x,0,wind.y))<0.001,"Only configured wind moves clouds at rest")
	clouds.elapsed=0
	clouds.advance(0)
	var toggle: CheckBox=world.follow_camera.experiment_panel.find_child("NeonCloudToggle",true,false)
	verify(toggle!=null,"Cloud control exists in the SF.3 panel")
	toggle.button_pressed=false
	verify(not clouds.enabled and not clouds.batch.visible,"Panel disables clouds immediately")
	var key:=InputEventKey.new()
	key.keycode=KEY_C;key.physical_keycode=KEY_C;key.pressed=true;key.ctrl_pressed=true;key.alt_pressed=true
	Input.parse_input_event(key)
	Input.flush_buffered_events()
	for i in range(3): await process_frame
	verify(clouds.enabled and toggle.button_pressed,"Ctrl+Alt+C toggles independently and synchronizes panel")
	verify(physics==[car.global_transform,car.velocity,car.config,car.vehicle_profile,car.abilities.burst_bonus],"Clouds and controls preserve car physics, selected profile and abilities")
	var update_us:=0
	var max_update_us:=0
	for i in range(1000):
		clouds.advance(0)
		update_us+=clouds.last_update_us
		max_update_us=maxi(max_update_us,clouds.last_update_us)
	var measurements:=[]
	if DisplayServer.get_name()!="headless":
		# Finish background city work before comparing identical views.
		var until:=Time.get_ticks_msec()+2500
		while Time.get_ticks_msec()<until: await render_frame()
		while world.night_style.decorating: await render_frame()
		world.night_style.set_process(false)
		for active in [false,true,true,false]:
			clouds.set_enabled(active)
			until=Time.get_ticks_msec()+2000
			while Time.get_ticks_msec()<until: await render_frame()
			var intervals: Array[float]=[]
			var previous:=Time.get_ticks_usec()
			for i in range(600):
				await render_frame()
				var now:=Time.get_ticks_usec()
				intervals.append((now-previous)/1000.0);previous=now
			intervals.sort()
			measurements.append({"enabled":active,"median_ms":intervals[300],"p95_ms":intervals[570],"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)})
			if measurements.size()<=2: root.get_texture().get_image().save_png("res://docs/evidence/sf3_clouds_%s.png"%["on" if active else "off"])
		var before: float=(measurements[0]["p95_ms"]+measurements[3]["p95_ms"])*0.5
		var after: float=(measurements[1]["p95_ms"]+measurements[2]["p95_ms"])*0.5
		verify(after-before<0.5,"Cloud p95 increase stays below 0.5 ms in this fixed view")
	clouds.set_enabled(true)
	var report:={"passed":cloud_failures.is_empty(),"checks":cloud_checks,"failures":cloud_failures,"cloud_instances":81,"triangles":162,"mean_update_us":update_us/1000.0,"max_update_us":max_update_us,"effective_altitude_m":clouds.altitude,"samples":measurements,"gpu":RenderingServer.get_video_adapter_name(),"scenario":"Existing OSM SF.1 avenue, frozen identical pose/camera, 1280x720 Compatibility, VSync off. A/B/B/A with 2s settle and 600 rendered frames per sample; not driving FPS."}
	FileAccess.open("res://docs/sf3_clouds_validation.json" if DisplayServer.get_name()=="headless" else "res://docs/sf3_clouds_render_validation.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("SF3_CLOUDS_REPORT ",JSON.stringify(report))
	cleanup()
	quit(0 if cloud_failures.is_empty() else 1)

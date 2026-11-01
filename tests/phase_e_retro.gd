extends SceneTree
var failures: Array[String] = []
func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)
func _initialize() -> void:
	run.call_deferred()
func run() -> void:
	root.size = Vector2i(1280,720)
	root.content_scale_size = Vector2i(1280,720)
	var results := {}
	for enabled in [false,true]:
		var world = load("res://scenes/NightPilot.tscn").instantiate()
		world.night_enabled = enabled
		root.add_child(world)
		check(world.runtime_error.is_empty(),"World load failed")
		world.player.external_control = true
		for i in range(120):
			await physics_frame
		check(world.player.on_asphalt and world.player.is_on_floor(),"Pilot spawn needs safe asphalt support")
		if enabled:
			var style = world.night_style
			check(style.decorated == 1,"Exactly one decorated sector")
			check(style.window_count > 0 and style.sign_count > 0,"Missing windows or signs")
			check(style.lamps.size() > 0 and style.lamps.size() <= int(world.night_config["lamp_limit"]),"Lamp budget")
			check(style.pilot.find_children("*","CollisionObject3D",true,false).is_empty(),"Decor introduced physics")
			check(not style.audio.music.playing,"Music should remain stopped")
			if DisplayServer.get_name() != "headless":
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png("res://docs/evidence/phase_e_retro_driver.png")
				var camera := Camera3D.new()
				world.add_child(camera)
				camera.position = world.player.position + Vector3(-28,24,28)
				camera.look_at(world.player.position+Vector3(25,3,-55))
				camera.current = true
				await process_frame
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png("res://docs/evidence/phase_e_retro_sector.png")
				camera.queue_free()
				world.follow_camera.camera.current = true
		world.player.global_transform = world.player.spawn_transform
		world.player.velocity = Vector3.ZERO
		world.player.speed_mps = 0
		world.player.signed_speed = 0
		world.player.reset_surface_motion()
		for i in range(10):
			await physics_frame
		world.player.set_controls(1,0)
		var offroad := 0
		for i in range(180):
			await physics_frame
			if not world.player.on_asphalt:
				offroad += 1
		results[str(enabled)] = {"position":[world.player.position.x,world.player.position.y,world.player.position.z],"speed":world.player.speed_mps,"offroad_frames":offroad}
		check(offroad == 0,"Pilot straight left asphalt")
		if enabled:
			check(world.city_manager.set_city_enabled(false),"F8 disable failed")
			check(not style_visible(world),"Decoration ignores city visibility")
			world.city_manager.set_city_enabled(true)
			world.player.set_controls(1,0,false,true)
			for i in range(40):
				await physics_frame
			check(world.player.turbo_active and world.player.visuals["exhaust"][0].visible,"Existing turbo visuals")
			check(world.follow_camera.camera.fov > 70,"Existing dynamic camera")
			world.player.set_controls(0,0)
			world.player.position = Vector3(1400,world.player.surface_height(1400,-100)+2,-100)
			world.player.velocity = Vector3.ZERO
			for i in range(90):
				await physics_frame
			check(not world.city_manager.loaded.has("0_-1"),"Pilot sector did not unload")
			world.player.global_transform = world.player.spawn_transform
			world.player.velocity = Vector3.ZERO
			world.player.reset_surface_motion()
			for i in range(120):
				await physics_frame
			check(world.night_style.decorated == 2,"Pilot decoration did not reload exactly once")
			results["decoration"] = {"windows":world.night_style.window_count,"neon_accents":world.night_style.sign_count,"lamp_fixtures":world.night_style.lamps.size(),"reloads":world.night_style.decorated}
		world.queue_free()
		await process_frame
		await process_frame
	check(absf(results["false"]["speed"]-results["true"]["speed"])<0.001,"Night changes speed")
	for i in range(3):
		check(absf(results["false"]["position"][i]-results["true"]["position"][i])<0.01,"Night changes trajectory")
	var report := {"passed":failures.is_empty(),"failures":failures,"results":results}
	FileAccess.open("res://docs/phase_e_retro_validation.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("PHASE_E_TEST ",JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
func style_visible(world: Node3D) -> bool:
	return world.night_style.pilot.is_visible_in_tree()

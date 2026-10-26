extends SceneTree

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var road_fix := "--road-fix" in OS.get_cmdline_user_args()
	var prefix := "res://docs/evidence/road_width" if road_fix else "res://docs/evidence/phase_c"
	var world := preload("res://scenes/Main.tscn").instantiate()
	root.add_child(world)
	await physics_frame
	await physics_frame
	var car: CharacterBody3D = world.player
	car.external_control = true
	var road: Dictionary = {}
	for candidate in world.map_data["roads"]:
		if candidate["id"] == "24503430:18":
			road = candidate
	var a := Vector3(road["points_xz"][0][0], 0.67, road["points_xz"][0][1])
	var b := Vector3(road["points_xz"][-1][0], 0.67, road["points_xz"][-1][1])
	var forward := (b - a).normalized()
	car.global_transform = Transform3D(Basis(Vector3.UP, atan2(-forward.x, -forward.z)), a + forward * 20)
	world.follow_camera.snap()
	car.set_controls(1, 0)
	for i in range(150):
		await physics_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(prefix + "_cruise.png")
	car.set_controls(1, 0, false, true)
	for i in range(65):
		await physics_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(prefix + "_turbo.png")
	print("PHASE_C_RENDER speed=", car.speed_mps, " boost=", car.turbo_active, " fov=", world.follow_camera.camera.fov, " audio=", car.feedback.engine.playing)
	if road_fix:
		var side := -forward.cross(Vector3.UP)
		var outside := a.lerp(b, 0.5) + side * (float(road["width_m"]) * 0.5 + 5.0)
		car.global_transform = Transform3D(Basis(Vector3.UP, atan2(side.x, side.z)), outside)
		car.velocity = Vector3.ZERO
		car.set_controls(0, 0)
		world.follow_camera.snap()
		for i in range(35):
			await physics_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(prefix + "_reentry.png")
	quit()

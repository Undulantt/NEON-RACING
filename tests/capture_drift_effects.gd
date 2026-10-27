extends SceneTree

func _initialize() -> void:
	run.call_deferred()

func capture(path: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://docs/evidence/" + path + ".png")

func run() -> void:
	var world := preload("res://scenes/FlatWorld.tscn").instantiate()
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
	var right := forward.cross(Vector3.UP)
	car.global_transform = Transform3D(Basis(Vector3.UP, atan2(-forward.x, -forward.z)), a + forward * 50 - right * 5)
	car.velocity = forward * 26
	world.follow_camera.snap()
	car.set_controls(1, 1, true)
	for i in range(44):
		await physics_frame
	await capture("drift_smoke_meter")
	print("DRIFT_RENDER charge=", car.drift_charge, " smoke=", car.drift_particles.smoke[0].emitting, " on_asphalt=", car.on_asphalt)
	car.set_controls(1, 0)
	for i in range(80):
		await physics_frame
		if car.drift_boost_active:
			break
	await capture("drift_exit_boost")
	print("EXIT_RENDER active=", car.drift_boost_active, " strength=", car.drift_boost_strength)
	car.global_transform = Transform3D(Basis(Vector3.UP, atan2(-forward.x, -forward.z)), a + forward * 50)
	car.velocity = forward * 32
	car.clear_drift_reward()
	car.drift_particles.clear_trail()
	world.follow_camera.snap()
	car.set_controls(1, 0, false, true)
	for i in range(60):
		await physics_frame
	await capture("turbo_speed_streaks")
	print("TURBO_RENDER active=", car.turbo_active, " speed=", car.speed_mps)
	quit()

extends SceneTree

var failures: Array[String] = []
func _initialize() -> void:
	run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func run() -> void:
	var world := preload("res://scenes/ReliefWorld.tscn").instantiate()
	root.add_child(world)
	for i in range(40):
		await physics_frame
	var car: CharacterBody3D = world.player
	check(car.collision_shape.size.is_equal_approx(Vector3(1.44, 0.96, 3.28)), "Smaller production collision box")
	check(car.visual_root.scale.is_equal_approx(Vector3.ONE * 0.8), "Visual and physical scale agree")
	check(is_equal_approx(float(car.config["drift_bonus_mps"]), 3.0 * 1.25), "Boost strength +25%")
	check(is_equal_approx(float(car.config["drift_bonus_duration_s"]), 0.9 * 1.25), "Boost duration +25%")
	check(world.hud.instruments.minimap.nearby.size() > 0, "Minimap receives actual nearby roads")
	if not "--headless" in OS.get_cmdline_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://docs/evidence/phase_c6_hud.png")
	# Isolate surface transition with the production controller on a known flat fixture.
	world.queue_free()
	await process_frame
	var fixture := Node3D.new()
	root.add_child(fixture)
	var ground := StaticBody3D.new()
	ground.collision_layer = 1
	ground.position.y = -0.5
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2000, 1, 2000)
	shape.shape = box
	ground.add_child(shape)
	fixture.add_child(ground)
	car = preload("res://scenes/cars/PlayerCar.tscn").instantiate()
	fixture.add_child(car)
	car.external_control = true
	car.configure({"roads": [{"points_xz": [[0, 0], [0, -900]], "oneway": false, "street_name": "C6 FIXTURE"}]}, {"bounds_xz": [-990, -990, 990, 990], "spawn": {"position_xz": [0, 0], "forward_xz": [0, -1]}})
	car.set_controls(1, 0)
	for i in range(180):
		await physics_frame
	var before: float = car.speed_mps
	ground.collision_layer = 2
	for i in range(30):
		await physics_frame
	var after: float = car.speed_mps
	check(not car.on_asphalt and before - after < 1.6, "Road departure loses at most 1.5 m/s in half a second")
	for i in range(180):
		await physics_frame
	check(absf(car.speed_mps - 28.8) < 0.1, "Offroad cruise is 90% of road cruise")
	car.set_controls(1, 0, false, true)
	for i in range(60):
		await physics_frame
	check(car.turbo_active and car.speed_mps > 43, "Turbo reaches full speed on terrain")
	car.set_controls(1, 0.25, true)
	for i in range(60):
		await physics_frame
	check(car.drift_charge > 0.18 and car.drift_particles.smoke[0].emitting, "Terrain drift charges and emits smoke")
	var rewards: int = car.drift_rewards
	car.set_controls(1, 0)
	for i in range(80):
		await physics_frame
	check(car.drift_rewards == rewards + 1, "Terrain drift awards one exit boost")
	var report := {"passed": failures.is_empty(), "failures": failures, "departure_before_mps": before, "departure_after_half_second_mps": after}
	FileAccess.open("res://docs/c6_validation.json", FileAccess.WRITE).store_string(JSON.stringify(report, "  "))
	print("C6_REPORT ", JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)


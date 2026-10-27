extends SceneTree

var car: CharacterBody3D
var failures: Array[String] = []
var metrics := {}

func _initialize() -> void:
	run.call_deferred()

func check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
		push_error(message)

func step(frames: int, throttle: float, turbo: bool = false) -> void:
	car.set_controls(throttle, 0, false, turbo)
	for i in range(frames):
		await physics_frame

func key_t(echo: bool = false) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = KEY_T
	event.pressed = true
	event.echo = echo
	Input.parse_input_event(event)
	await process_frame
	event = InputEventKey.new()
	event.physical_keycode = KEY_T
	event.pressed = false
	Input.parse_input_event(event)
	await process_frame

func reset() -> void:
	car.global_position = Vector3(0, 0.67, 0)
	car.velocity = Vector3.ZERO
	car.reset_surface_motion()
	car.set_controls(0, 0, true)
	for i in range(30):
		await physics_frame

func run() -> void:
	var level := Node3D.new()
	root.add_child(level)
	var ground := StaticBody3D.new()
	ground.collision_layer = 1
	var collider := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(100, 1, 10000)
	collider.shape = box
	collider.position.y = -0.5
	ground.add_child(collider)
	level.add_child(ground)
	car = preload("res://scenes/cars/PlayerCar.tscn").instantiate()
	level.add_child(car)
	car.configure({"roads":[{"points_xz":[[0,4900],[0,-4900]],"oneway":false,"street_name":"DEBUG SPEED FIXTURE"}]}, {"bounds_xz":[-45,-4950,45,4950],"spawn":{"position_xz":[0,0],"forward_xz":[0,-1]}})
	car.external_control = true
	var original_config: Dictionary = car.config.duplicate(true)
	var source_hash := FileAccess.get_sha256("res://config/driving_config.json")
	check(not car.debug_speed_enabled, "Test mode must start disabled")
	for doubled in [false, true]:
		if doubled:
			await key_t()
			check(car.debug_speed_enabled, "Physical T must enable test mode")
			await key_t(true)
			check(car.debug_speed_enabled, "Held T key repeat must not toggle again")
		var factor := 2.0 if doubled else 1.0
		await reset()
		await step(60, 1)
		var acceleration_speed: float = car.signed_speed
		check(absf(acceleration_speed - 13 * factor) < 0.6, "Engine acceleration must scale by selected multiplier")
		await step(240, 1)
		check(absf(car.signed_speed - 32 * factor) < 0.1, "Forward cap must scale by selected multiplier")
		metrics[str(factor)] = {"speed_after_one_second_mps":acceleration_speed,"forward_cap_mps":car.signed_speed}
		await reset()
		await step(120, -1)
		check(absf(car.signed_speed + 7 * factor) < 0.1, "Reverse cap must scale by selected multiplier")
		metrics[str(factor)]["reverse_cap_mps"] = car.signed_speed
		await reset()
		car.turbo_charge = 1
		car.turbo_exhausted = false
		car.velocity = Vector3(0, 0, -10 * factor)
		await step(60, 1, true)
		check(absf(car.signed_speed - 29 * factor) < 0.8, "Turbo acceleration must scale by selected multiplier")
		await step(60, 1, true)
		check(car.turbo_active and absf(car.signed_speed - 44 * factor) < 0.1, "Turbo cap must scale by selected multiplier")
		metrics[str(factor)]["turbo_cap_mps"] = car.signed_speed
		ground.collision_layer = 2
		await reset()
		await step(180, 1)
		check(absf(car.signed_speed - 12 * factor) < 0.1, "Offroad cap must scale by selected multiplier")
		metrics[str(factor)]["offroad_cap_mps"] = car.signed_speed
		ground.collision_layer = 1
	await reset()
	car.velocity = Vector3(0, 0, -60)
	car.set_controls(0, 0)
	await key_t()
	check(not car.debug_speed_enabled and car.speed_mps > 55, "Disabling T must restore mode without instant velocity reset")
	await step(240, 1)
	check(absf(car.signed_speed - 32) < 0.1, "Normal speed limit must return after disabling T")
	check(car.config == original_config and FileAccess.get_sha256("res://config/driving_config.json") == source_hash, "Toggle must not mutate baseline configuration")
	check(car.recovery_count == 0, "Test must not require recovery")
	var report := {"passed":failures.is_empty(),"failures":failures,"metrics":metrics,"controller_sha256":FileAccess.get_sha256("res://scripts/driving/ArcadeCar.gd")}
	var output := FileAccess.open("res://docs/debug_speed_validation.json", FileAccess.WRITE)
	output.store_string(JSON.stringify(report, "  "))
	print("DEBUG_SPEED_REPORT ", JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)

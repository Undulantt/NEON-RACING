extends SceneTree

# Explicit synthetic physics fixture, never used as the playable La Paz map.
const Car = preload("res://scenes/cars/PlayerCar.tscn")
const Follow = preload("res://scripts/driving/FollowCamera.gd")
var car: CharacterBody3D
var follow: Node3D
var failures: Array[String] = []
var metrics := {}

func _initialize() -> void:
	run.call_deferred()

func check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
		push_error(message)

func step(frames: int, throttle: float = 0, steer: float = 0, handbrake: bool = false, turbo: bool = false) -> void:
	car.set_controls(throttle, steer, handbrake, turbo)
	for i in range(frames):
		await physics_frame

func reset() -> void:
	car.global_transform = Transform3D(Basis.IDENTITY, Vector3(0, 0.67, 0))
	car.velocity = Vector3.ZERO
	car.steering = 0
	car.clear_drift_reward()
	car.grip_blend = 1
	car.turbo_active = false
	car.turbo_exhausted = false
	car.turbo_charge = 1
	car.turbo_cooldown = 0
	await step(5)

func tap(action: String) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	event = InputEventAction.new()
	event.action = action
	event.pressed = false
	Input.parse_input_event(event)
	await process_frame

func run() -> void:
	var level := Node3D.new()
	root.add_child(level)
	var ground := StaticBody3D.new()
	ground.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2000, 1, 2000)
	shape.shape = box
	ground.position.y = -0.5
	ground.add_child(shape)
	level.add_child(ground)
	car = Car.instantiate()
	level.add_child(car)
	car.configure({"roads": [{"points_xz": [[0, 0], [0, -900]], "oneway": false, "street_name": "SYNTHETIC TEST ONLY"}]}, {"bounds_xz": [-990, -990, 990, 990], "spawn": {"position_xz": [0, 0], "forward_xz": [0, -1]}})
	car.external_control = true
	follow = Node3D.new()
	follow.set_script(Follow)
	level.add_child(follow)
	follow.attach(car)
	await reset()
	await step(60, 0, 1)
	check(absf(car.rotation.y) < 0.001, "No steering rotation at rest")
	await step(240, 1)
	metrics["normal_top_mps"] = car.speed_mps
	check(car.speed_mps > 31.9 and car.speed_mps < 32.1, "Normal speed cap")
	await step(80, 1, 0, false, true)
	metrics["turbo_top_mps"] = car.speed_mps
	check(car.turbo_active and car.speed_mps > 43.5 and car.speed_mps < 44.1, "Turbo increases speed with bounded cap")
	check(car.turbo_charge < 0.7 and car.turbo_charge > 0.5, "Turbo consumes reserve")
	check(follow.camera.fov > 85, "Turbo widens FOV")
	check(car.visuals["exhaust"][0].visible, "Turbo exhaust visible")
	var reserve: float = car.turbo_charge
	var position: Vector3 = car.position
	paused = true
	for i in range(10):
		await process_frame
	check(car.turbo_charge == reserve and car.position == position, "Pause freezes active turbo reserve and movement")
	paused = false
	await step(150, 1, 0, false, true)
	check(not car.turbo_active and car.turbo_exhausted, "Reserve exhaustion cuts boost")
	await step(240, 1, 0, false, true)
	check(not car.turbo_active, "Holding exhausted turbo cannot pulse restart")
	await step(60, 1)
	check(car.speed_mps <= 32.1 and not car.visuals["exhaust"][0].visible, "Release restores normal cap and exhaust")
	await step(540)
	check(car.turbo_charge > 0.99, "Turbo recharges to full")
	await reset()
	await step(90, -1, 0, false, true)
	check(car.signed_speed >= -7.1 and not car.turbo_active and car.turbo_charge == 1, "Reverse cannot boost")
	await reset()
	await step(90, 1)
	car.driving_enabled = false
	await step(15, 1, 0, false, true)
	check(not car.turbo_active, "Inspection disables turbo")
	car.driving_enabled = true
	await reset()
	await step(90, 1)
	await step(10, 1, 0, true, true)
	check(not car.turbo_active and car.turbo_charge == 1, "Handbrake prevents boost consumption")
	ground.collision_layer = 2
	await step(10, 1, 0, false, true)
	check(not car.on_asphalt and not car.turbo_active and car.turbo_charge == 1, "Offroad prevents boost consumption")
	ground.collision_layer = 1
	var slips: Array[float] = []
	for brake in [false, true]:
		await reset()
		car.velocity = Vector3(0, 0, -20)
		await step(25, 1, 0.65, brake)
		slips.append(absf(car.slip_angle))
	metrics["normal_slip_rad"] = slips[0]
	metrics["drift_slip_rad"] = slips[1]
	check(slips[1] > slips[0] + 0.12 and car.drift_amount > 0.15, "Handbrake produces measurable drift")
	await step(80, 1)
	check(car.grip_blend > 0.99 and absf(car.slip_angle) < 0.04, "Grip and heading recover after drift release")
	car.recover()
	check(car.drift_amount == 0 and not car.turbo_active and car.velocity == Vector3.ZERO, "Recovery clears feedback and motion")
	check(InputMap.action_has_event("turbo", physical(KEY_SHIFT)), "Shift physical turbo binding")
	await tap("driving_camera")
	await step(90)
	check(follow.close_view and follow.arm.spring_length < 5.5, "V selects close driving view")
	await tap("audio_toggle")
	check(car.feedback.muted, "M toggles audio")
	# Runtime integration against actual production city and HUD.
	level.queue_free()
	await process_frame
	var world := preload("res://scenes/FlatWorld.tscn").instantiate()
	root.add_child(world)
	await physics_frame
	await physics_frame
	check(world.player != null and world.hud.turbo_bar != null, "Production world and turbo HUD load")
	world.toggle_camera()
	check(not world.player.driving_enabled and world.overhead.current, "Aerial inspection preserved")
	world.toggle_camera()
	world.hud.set_pause(true)
	var frozen: Vector3 = world.player.position
	for i in range(10):
		await process_frame
	check(world.player.position == frozen, "Pause freezes vehicle")
	world.hud.set_pause(false)
	var report := {"passed": failures.is_empty(), "failures": failures, "metrics": metrics}
	var output := FileAccess.open("res://docs/phase_c_validation.json", FileAccess.WRITE)
	output.store_string(JSON.stringify(report, "  "))
	print("PHASE_C_REPORT ", JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)

func physical(code: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = code
	return event

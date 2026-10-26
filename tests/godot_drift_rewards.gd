extends SceneTree

const Car = preload("res://scenes/cars/PlayerCar.tscn")
var car: CharacterBody3D
var level: Node3D
var ground: StaticBody3D
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
	car.grip_blend = 1
	car.driving_enabled = true
	car.clear_drift_reward()
	car.drift_particles.clear_trail()
	car.turbo_active = false
	car.turbo_charge = 1
	await step(6)

func charge(frames: int = 90) -> void:
	await reset()
	car.velocity = Vector3(0, 0, -26)
	await step(frames, 1, 0.25, true)

func run() -> void:
	# Synthetic fixture only; uses the production controller and collision shapes.
	level = Node3D.new()
	root.add_child(level)
	ground = StaticBody3D.new()
	ground.collision_layer = 1
	ground.position.y = -0.5
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2000, 1, 2000)
	shape.shape = box
	ground.add_child(shape)
	level.add_child(ground)
	car = Car.instantiate()
	level.add_child(car)
	car.configure({"roads": [{"points_xz": [[0, 0], [0, -900]], "oneway": false, "street_name": "SYNTHETIC TEST ONLY"}]}, {"bounds_xz": [-990, -990, 990, 990], "spawn": {"position_xz": [0, 0], "forward_xz": [0, -1]}})
	car.external_control = true
	await reset()
	await step(100, 1, 0, true)
	check(car.drift_charge == 0 and car.drift_rewards == 0, "Straight handbraking must not charge")
	car.velocity = Vector3(0, 0, -26)
	await step(10, 1, 0.6, true)
	await step(75, 1)
	check(car.drift_rewards == 0 and not car.drift_boost_active, "Short handbrake taps must not earn boost")
	await charge(45)
	var short_charge: float = car.drift_charge
	await charge()
	metrics["controlled_drift_charge"] = car.drift_charge
	metrics["shorter_drift_charge"] = short_charge
	check(car.drift_charge > short_charge + 0.05 and car.drift_charge >= float(car.config["drift_min_charge"]), "Sustained controlled drift must earn more charge")
	check(car.drift_particles.smoke.size() == 2 and car.drift_particles.smoke[0].emitting, "Rear-wheel smoke emits during actual drift")
	var reserve: float = car.turbo_charge
	var stored: float = car.drift_charge
	paused = true
	for i in range(8):
		await process_frame
	check(car.drift_charge == stored, "Pause freezes drift meter")
	paused = false
	var before: int = car.drift_rewards
	var frames := 0
	while car.drift_rewards == before and frames < 100:
		await step(1, 1)
		frames += 1
	metrics["exit_frames_until_reward"] = frames
	metrics["earned_strength"] = car.drift_boost_strength
	check(car.drift_rewards == before + 1 and car.drift_boost_active, "Clean aligned exit must award exactly one boost")
	check(car.turbo_charge == reserve, "Drift bonus must not spend Shift reserve")
	var pose: Transform3D = car.global_transform
	var motion: Vector3 = car.velocity
	var grip: float = car.grip_blend
	var steer: float = car.steering
	await step(30, 1)
	var bonus_speed: float = car.speed_mps
	check(car.drift_boost_active, "Exit bonus lasts long enough to accelerate")
	car.global_transform = pose
	car.velocity = motion
	car.grip_blend = grip
	car.steering = steer
	car.clear_drift_reward()
	await step(30, 1)
	metrics["exit_bonus_speed_mps"] = bonus_speed
	metrics["same_exit_without_bonus_mps"] = car.speed_mps
	metrics["measured_gain_mps"] = bonus_speed - car.speed_mps
	check(bonus_speed > car.speed_mps + 0.35, "Earned drift bonus must measurably increase speed over identical exit")
	await step(120, 1)
	check(car.drift_rewards == before + 1, "One drift cannot repeatedly award boosts")
	# Digital steering must also earn a reward using the actual keyboard path.
	await reset()
	car.external_control = false
	car.velocity = Vector3(0, 0, -26)
	for code in [KEY_W, KEY_D, KEY_SPACE]:
		physical_key(code, true)
	for i in range(44):
		await physics_frame
	metrics["digital_drift_charge"] = car.drift_charge
	physical_key(KEY_D, false)
	physical_key(KEY_SPACE, false)
	before = car.drift_rewards
	for i in range(65):
		await physics_frame
	check(car.drift_rewards == before + 1, "Physical W/D/Space drift can earn an exit bonus")
	physical_key(KEY_W, false)
	car.external_control = true
	await charge()
	for i in range(80):
		await step(1, 1)
		if car.drift_boost_active:
			break
	await step(2, 1, 0, false, true)
	check(car.turbo_active and not car.drift_boost_active and car.speed_mps <= 44.1, "Shift supersedes drift bonus without stacking")
	await reset()
	car.velocity = Vector3(0, 0, -26)
	await step(90, 1, 1, true)
	check(car.drift_charge == 0 and not car.drift_boost_active, "Slow spin cannot preserve or earn charge")
	# Cancellation on road departure and on actual wall contact.
	await charge()
	ground.collision_layer = 2
	await step(4, 1)
	check(car.drift_charge == 0 and not car.drift_boost_active, "Offroad cancels earned charge")
	ground.collision_layer = 1
	await charge()
	var wall := StaticBody3D.new()
	wall.collision_layer = 4
	var direction: Vector3 = Vector3(car.velocity.x, 0, car.velocity.z).normalized()
	wall.global_transform = Transform3D(Basis(Vector3.UP, atan2(-direction.x, -direction.z)), car.position + direction * 3)
	var collision := CollisionShape3D.new()
	var wall_shape := BoxShape3D.new()
	wall_shape.size = Vector3(100, 3, 0.5)
	collision.shape = wall_shape
	wall.add_child(collision)
	level.add_child(wall)
	var contacts: int = car.wall_contacts
	before = car.drift_rewards
	await step(25, 1)
	check(car.wall_contacts > contacts and car.drift_charge == 0 and car.drift_rewards == before, "Crash loses meter without rewarding exit")
	wall.queue_free()
	await process_frame
	await charge()
	car.driving_enabled = false
	await step(2)
	check(car.drift_charge == 0 and not car.drift_boost_active, "Inspection cancels charge")
	await charge()
	car.recover()
	await step(2)
	check(car.drift_charge == 0 and not car.drift_boost_active and not car.drift_particles.smoke[0].emitting, "Recovery resets drift meter, bonus and smoke")
	var report := {"passed": failures.is_empty(), "failures": failures, "metrics": metrics}
	var output := FileAccess.open("res://docs/drift_rewards_validation.json", FileAccess.WRITE)
	output.store_string(JSON.stringify(report, "  "))
	print("DRIFT_REWARDS_REPORT ", JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)

func physical_key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)

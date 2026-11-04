extends SceneTree

const Profiles = preload("res://scripts/driving/VehicleProfiles.gd")
const Abilities = preload("res://scripts/driving/DrivingAbilities.gd")
var car: CharacterBody3D
var ground: StaticBody3D
var level: Node3D
var failures: Array[String] = []
var metrics := {}
var starts := 0
var ends := 0
var drift_events := 0

func _initialize() -> void:
	run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func step(frames: int, throttle: float = 0.0, steer: float = 0.0, handbrake: bool = false, turbo: bool = false, brake: float = 0.0) -> void:
	car.set_controls(throttle, steer, handbrake, turbo, brake)
	for i in range(frames):
		await car.physics_updated

func reset(id: String = "VECTOR") -> void:
	car.velocity = Vector3.ZERO
	car.speed_mps = 0.0
	car.signed_speed = 0.0
	car.external_control = true
	car.driving_enabled = true
	car.debug_speed_enabled = false
	car.apply_vehicle_profile(id)
	car.global_transform = car.spawn_transform
	car.reset_surface_motion()
	car.steering = 0.0
	car.grip_blend = 1.0
	car.drift_particles.clear_trail()
	ground.collision_layer = 1
	await step(5)

func ability_tick(a: RefCounted, seconds: float, speed: float, throttle: float = 1.0, brake: float = 0.0, grounded: bool = true) -> void:
	for i in range(roundi(seconds * 60)):
		a.tick(1.0 / 60, throttle, brake, false, false, speed, grounded, true, true, 1.0)

func state_machine_checks() -> void:
	for id in Profiles.IDS:
		var profile: Dictionary = Profiles.load_profile(id)
		var c: Dictionary = profile["config"]
		var a := Abilities.new()
		a.configure(c)
		var base := float(c["max_forward_speed_mps"])
		ability_tick(a, 4, base * 0.94)
		check(a.burst_state == 0 and a.arming_time == 0, id + " cannot arm below threshold")
		ability_tick(a, float(c["burst_arming_time_s"]) - 1.0/60, base)
		check(a.burst_state == 1, id + " requires full preparation time")
		ability_tick(a, 1.0/60, base)
		check(a.burst_state == 2 and a.burst_time == 0, id + " activates after configured real seconds")
		ability_tick(a, 5, base)
		var expected := base * (1 + minf(float(c["burst_max_bonus"]), 5 * float(c["burst_growth_per_second"])))
		check(absf(a.current_speed_cap - expected) < 0.0001, id + " dynamic cap follows real BURST seconds")
		ability_tick(a, 15, base * 1.1)
		check(absf(a.current_speed_cap - base * (1 + float(c["burst_max_bonus"]))) < 0.001, id + " caps bonus")
		a.tick(1.0/60, 0.849, 0, false, false, base * 1.2, true, true, true, 1)
		check(a.burst_state == 3 and a.burst_bonus == 0 and a.burst_time == 0 and a.arming_time == 0 and a.current_speed_cap == base, id + " same-tick throttle cancellation")
		ability_tick(a, 6, base * 1.1)
		check(a.burst_state == 3 and a.arming_time == 0, id + " residual overspeed cannot rearm")
		ability_tick(a, float(c["burst_arming_time_s"]) + 0.1, base)
		a.tick(1.0/60, 1, 0.11, false, false, base, true, true, true, 1)
		check(a.burst_state != 2 and a.burst_time == 0, id + " brake wins over growth in same tick")
		ability_tick(a, float(c["burst_arming_time_s"]) + 0.1, base)
		a.after_motion(base * 0.89)
		check(a.burst_state != 2 and a.burst_bonus == 0, id + " collision speed loss cancels after motion")
		a.reset("test")
		ability_tick(a, 10, 0, 1, 0, false)
		check(a.burst_state == 0 and a.arming_time == 0, id + " falling cannot arm")
		ability_tick(a, float(c["burst_arming_time_s"]) + 0.1, base)
		ability_tick(a, 0.2, base, 1, 0, false)
		check(a.burst_state == 2, id + " short crest does not cancel BURST")
		ability_tick(a, 0.4, base, 1, 0, false)
		check(a.burst_state != 2, id + " extended flight cancels BURST")
		# Emptying the tank and earning a drift in the same step must not regenerate fuel.
		a.reset("test")
		a.turbo_charge = 0.001
		a.turbo_active = true
		a.update_turbo(0.1, true, true, true)
		a.drift_tracking = true
		a.drift_charge = 1.0
		a.drift_valid_time = 1.0
		a.update_drift(0.1, false, false, true, true, 28, 1, 0, 0, 0)
		check(a.turbo_charge == 0 and a.drift_boost_active, id + " no regeneration in the same tick as consumption")
		metrics[id] = {"scores": profile["stats"], "base_kmh": base*3.6, "maximum_burst_kmh": base*3.6*(1+float(c["burst_max_bonus"]))}

func run() -> void:
	state_machine_checks()
	level = Node3D.new()
	root.add_child(level)
	ground = StaticBody3D.new()
	ground.collision_layer = 1
	ground.position.y = -0.5
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4000, 1, 40000)
	shape.shape = box
	ground.add_child(shape)
	level.add_child(ground)
	car = preload("res://scenes/cars/PlayerCar.tscn").instantiate()
	level.add_child(car)
	car.configure({"roads": [{"points_xz": [[0, 19000], [0, -19000]], "oneway": false, "street_name": "BURST SYNTHETIC FIXTURE"}]}, {"bounds_xz": [-1900, -19000, 1900, 19000], "spawn": {"position_xz": [0, 0], "forward_xz": [0, -1]}})
	car.burst_started.connect(func(): starts += 1)
	car.burst_ended.connect(func(_reason: String): ends += 1)
	car.drift_boost_triggered.connect(func(_strength: float): drift_events += 1)
	for id in Profiles.IDS:
		await reset(id)
		var frames := 0
		while car.signed_speed < 100.0/3.6 and frames < 600:
			await step(1, 1)
			frames += 1
		var t100 := frames / 60.0
		metrics[id]["measured_0_100_s"] = t100
		check(absf(t100 - float(car.config["target_0_100_s"])) < 0.08, id + " 0-100 matches target")
		# Turbo can hold 94% input without arming BURST at less than threshold speed.
		await reset(id)
		car.config["burst_arming_time_s"] = 1000.0
		await step(900, 1, 0, false, true)
		check(car.speed_mps <= car.base_speed_cap + 0.03 and car.abilities.burst_state != 2, id + " turbo alone cannot raise base cap")
		check(car.turbo_exhausted, id + " reserve exhausts without pulse restart")
		await reset(id)
		await step(1800, 1)
		check(car.abilities.burst_state == 2 and car.speed_mps > car.base_speed_cap * 1.15, id + " engine exploits BURST margin")
		metrics[id]["burst_speed_after_30_s_kmh"] = car.speed_mps*3.6
		var before: float = car.signed_speed
		var position: Vector3 = car.position
		await step(1, 0)
		check(car.abilities.burst_bonus == 0 and car.current_speed_cap == car.base_speed_cap, id + " controller cancels on release in same tick")
		check(before - car.signed_speed > 0 and before - car.signed_speed < 0.3 and car.position.distance_to(position) < 3, id + " release preserves smooth velocity and position")
		await step(3, 1)
		check(car.abilities.burst_state == 3 and car.abilities.arming_time == 0, id + " recovery does not exploit residual speed")
		before = car.signed_speed
		await step(1, 1, 0, false, false, 0.5)
		check(before - car.signed_speed > 0 and car.abilities.burst_bonus == 0, id + " independent brake overrides accelerator")
		car.recover()
		check(car.abilities.burst_state == 0 and not car.drift_boost_active and not car.turbo_active, id + " recovery resets abilities")
	# Digital steering must earn a valid exit, not only analogue test steering.
	await reset()
	car.external_control = false
	car.velocity = Vector3(0, 0, -28)
	key(KEY_W, true)
	key(KEY_D, true)
	key(KEY_SPACE, true)
	for i in range(70):
		await car.physics_updated
	metrics["keyboard_drift_charge"] = car.drift_charge
	key(KEY_D, false)
	key(KEY_SPACE, false)
	var digital_rewards: int = car.drift_rewards
	for i in range(80):
		await car.physics_updated
	check(car.drift_rewards == digital_rewards + 1, "W/D/Space controlled drift earns a reward")
	key(KEY_W, false)
	# Same-tick physical collision cancellation, with production slide response.
	await reset()
	await step(1100, 1)
	var wall := StaticBody3D.new()
	wall.collision_layer = 4
	var collision := CollisionShape3D.new()
	var wall_shape := BoxShape3D.new()
	wall_shape.size = Vector3(100, 12, 0.5)
	collision.shape = wall_shape
	wall.add_child(collision)
	wall.position = car.position + Vector3(0, 0, -8)
	level.add_child(wall)
	var contacts: int = car.wall_contacts
	for i in range(30):
		await step(1, 1)
		if car.wall_contacts > contacts:
			break
	check(car.wall_contacts > contacts and car.abilities.burst_bonus == 0 and car.abilities.burst_time == 0, "Physical wall cancels BURST in collision tick")
	check(car.velocity.is_finite(), "Wall impact preserves finite velocity")
	wall.queue_free()
	await reset()
	ground.collision_layer = 2
	await step(1500, 1)
	check(car.abilities.burst_state == 2 and car.current_speed_cap > car.base_speed_cap * 0.9, "Terrain can prepare and sustain BURST at its contextual base cap")
	car.driving_enabled = false
	await step(1, 1)
	check(car.abilities.burst_bonus == 0 and not car.turbo_active, "Inspection cancels abilities")
	# Real keyboard and joypad paths; raw analogue values share the defined thresholds.
	await reset()
	car.external_control = false
	key(KEY_W, true)
	car.velocity = Vector3(0, 0, -float(car.config["max_forward_speed_mps"]))
	for i in range(195):
		await car.physics_updated
	check(car.abilities.burst_state == 2, "Physical W input arms BURST")
	key(KEY_W, false)
	await car.physics_updated
	check(car.abilities.burst_bonus == 0, "Physical W release cancels immediately")
	await reset()
	car.external_control = false
	joy(JOY_AXIS_TRIGGER_RIGHT, 0.86)
	car.velocity = Vector3(0, 0, -float(car.config["max_forward_speed_mps"]))
	for i in range(195):
		await car.physics_updated
	check(car.abilities.burst_state == 2, "Gamepad RT above 0.85 arms BURST")
	joy(JOY_AXIS_TRIGGER_LEFT, 0.04)
	await car.physics_updated
	check(car.abilities.burst_state == 2 and car.brake_input == 0, "Small analogue brake noise does not suppress acceleration")
	joy(JOY_AXIS_TRIGGER_LEFT, 0.11)
	await car.physics_updated
	check(car.abilities.burst_bonus == 0 and car.brake_input > 0.10, "Gamepad LT 0.11 cancels with RT held")
	joy(JOY_AXIS_TRIGGER_RIGHT, 0)
	joy(JOY_AXIS_TRIGGER_LEFT, 0)
	# Controlled drifts are independently rewarded, once per event and on terrain too.
	for terrain in [false, true]:
		await reset("APEX")
		if terrain:
			ground.collision_layer = 2
		car.turbo_charge = 0.5
		car.velocity = Vector3(0, 0, -28)
		var drift_probe := []
		for j in range(9):
			await step(10, 1, 0.6, true)
			drift_probe.append({"speed":car.signed_speed, "angle":rad_to_deg(absf(car.slip_angle)), "charge":car.drift_charge, "valid":car.drift_valid_time})
		metrics["terrain_drift" if terrain else "asphalt_drift"] = drift_probe
		check(car.drift_charge >= float(car.config["drift_min_charge"]), "Controlled drift charges on road/terrain")
		var before_rewards: int = car.drift_rewards
		var old_charge: float = car.turbo_charge
		var frames := 0
		while car.drift_rewards == before_rewards and frames < 100:
			await step(1, 1)
			frames += 1
		check(car.drift_rewards == before_rewards + 1 and car.drift_boost_active, "Clean exit grants exactly one Drift Boost")
		check(car.turbo_charge > old_charge, "Valid drift restores a bounded amount of turbo")
		check(car.abilities.burst_state == 0 and car.abilities.arming_time == 0, "Drift Boost does not activate or preserve BURST")
		var frozen_time: float = car.drift_boost_time
		paused = true
		for i in range(6):
			await process_frame
		check(car.drift_boost_time == frozen_time, "Pause freezes Drift Boost")
		paused = false
		await step(3, 1, 0, false, true)
		check(car.turbo_active and car.drift_boost_active, "Turbo and Drift Boost stay independent")
		await step(240, 1)
		check(car.drift_rewards == before_rewards + 1, "One exit cannot repeatedly grant boost")
	await reset()
	car.velocity = Vector3(30, 0, 0)
	await step(195, 1)
	check(car.abilities.burst_state != 2, "Lateral speed cannot simulate forward eligibility")
	await reset()
	car.velocity = Vector3(0, 0, -28)
	await step(100, 1, 0, true)
	check(car.drift_charge == 0, "Straight handbrake never charges")
	var tap_rewards: int = car.drift_rewards
	for i in range(8):
		await step(8, 1, 0.6, true)
		await step(8, 1)
	check(car.drift_rewards == tap_rewards, "Input tap sequence remains finite")
	check(is_finite(car.speed_mps) and car.velocity.is_finite(), "No nonfinite motion")
	check(starts > 0 and ends > 0 and drift_events > 0, "Ability events are exposed")
	metrics["events"] = {"burst_started": starts, "burst_ended": ends, "drift_boost": drift_events}
	var hashes := {}
	for file in ["scripts/driving/ArcadeCar.gd", "scripts/driving/DrivingAbilities.gd", "scripts/driving/VehicleProfiles.gd", "scripts/driving/DrivingInput.gd", "scripts/driving/AutomaticTransmission.gd", "config/powertrain_config.json", "config/driving_config.json", "config/vehicles/vector.json", "config/vehicles/comet.json", "config/vehicles/apex.json"]:
		hashes[file] = FileAccess.get_sha256("res://" + file)
	var report := {"source_hashes": hashes, "passed": failures.is_empty(), "failures": failures, "metrics": metrics, "physics_hz": Engine.physics_ticks_per_second}
	var suffix := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--report-suffix="):
			suffix = arg.trim_prefix("--report-suffix=")
	FileAccess.open("res://docs/burst_validation%s.json" % suffix, FileAccess.WRITE).store_string(JSON.stringify(report, "  "))
	print("BURST_REPORT ", JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)

func key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)

func joy(axis: JoyAxis, value: float) -> void:
	var event := InputEventJoypadMotion.new()
	event.device = 0
	event.axis = axis
	event.axis_value = value
	Input.parse_input_event(event)

extends SceneTree

const Profiles = preload("res://scripts/driving/VehicleProfiles.gd")
var car: CharacterBody3D
var world: Node3D
var points := PackedVector3Array()
var lengths := PackedFloat64Array()
var turns: Array = []
var failures: Array[String] = []
var report := {"physics_hz": 60, "pilot": "Shared pure-pursuit driver; profile-specific braking/steering physical parameters; no teleport corrections", "synthetic": {}, "real_routes": {}}

func _initialize() -> void:
	run.call_deferred()

func step(frames: int) -> void:
	for i in range(frames):
		await car.physics_updated

func build_path(data: Array) -> void:
	points.clear()
	lengths.clear()
	turns.clear()
	for p in data:
		points.append(Vector3(p[0], 0, p[1]))
	lengths.append(0)
	for i in range(1, points.size()):
		lengths.append(lengths[-1] + points[i].distance_to(points[i-1]))
	for i in range(1, points.size()-1):
		var a := (points[i] - points[i-1]).normalized()
		var b := (points[i+1] - points[i]).normalized()
		var angle := acos(clampf(a.dot(b), -1, 1))
		if angle > 0.025:
			turns.append({"distance": lengths[i], "angle": angle})

func sample(distance: float) -> Vector3:
	var index := clampi(lengths.bsearch(distance) - 1, 0, points.size()-2)
	return points[index].lerp(points[index+1], clampf((distance - lengths[index]) / (lengths[index+1] - lengths[index]), 0, 1))

func place(id: String, at: Vector3, direction: Vector3) -> void:
	car.velocity = Vector3.ZERO
	car.speed_mps = 0
	car.signed_speed = 0
	car.apply_vehicle_profile(id)
	car.external_control = true
	car.steering = 0
	car.grip_blend = 1
	var yaw := atan2(-direction.x, -direction.z)
	at.y = car.supported_pose_height(at.x, at.z, yaw)
	car.global_transform = Transform3D(Basis(Vector3.UP, yaw), at)
	car.reset_surface_motion()
	car.abilities.reset("balance_fixture")
	car.set_controls(0, 0, true)
	if world != null:
		world.road_root.ensure_recovery_support()
		world.terrain_root.ensure_recovery_support()
	await step(30)

func route(id: String, limit: int = 90000) -> Dictionary:
	await place(id, sample(3), (points[1]-points[0]).normalized())
	var progress := 3.0
	var index := 0
	var frames := 0
	var offroad := 0
	var unsupported := 0
	var max_deviation := 0.0
	var peak_speed := 0.0
	var burst_frames := 0
	var burst_peak := 0.0
	var recoveries: int = car.recovery_count
	var walls: int = car.wall_contacts
	while progress < lengths[-1] - 5 and frames < limit:
		var at := Vector3(car.position.x, 0, car.position.z)
		var nearest := INF
		for i in range(maxi(0, index-2), mini(points.size()-1, index+12)):
			var closest := Geometry3D.get_closest_point_to_segment(at, points[i], points[i+1])
			var distance := at.distance_to(closest)
			if distance < nearest:
				nearest = distance
				index = i
				progress = maxf(progress, lengths[i] + points[i].distance_to(closest))
		max_deviation = maxf(max_deviation, nearest)
		var speed: float = car.speed_mps
		var lookahead := clampf(4 + speed * 0.45, 5, 32)
		var target := sample(minf(progress + lookahead, lengths[-1]))
		var direction := (target - at).normalized()
		var error := wrapf(atan2(-direction.x, -direction.z) - car.rotation.y, -PI, PI)
		var reduction := lerpf(1, 1 - float(car.config["steering_reduction_at_high_speed"]), clampf(speed / float(car.config["max_forward_speed_mps"]), 0, 1))
		var wheel_angle := atan(2 * float(car.config["wheelbase_m"]) * sin(error) / lookahead)
		var steer := -wheel_angle / (float(car.config["max_steer_radians"]) * reduction * float(car.config["steering_sensitivity"]))
		var desired := 1000.0
		var next_corner := INF
		for turn in turns:
			var ahead: float = turn["distance"] - progress
			if ahead < -lookahead * 0.5:
				continue
			if ahead > 500:
				break
			var angle: float = turn["angle"]
			var corner_speed := clampf(sqrt(30.0 * float(car.config["steering_sensitivity"]) / angle), 6, 40)
			var available := maxf(0, ahead - lookahead * 0.7 - 5)
			desired = minf(desired, sqrt(corner_speed * corner_speed + 2 * float(car.config["braking_mps2"]) * 0.75 * available))
			if angle > 0.3:
				next_corner = minf(next_corner, ahead)
		var throttle := 1.0 if speed <= desired - 0.3 else clampf((desired-speed)*0.65, -1, 1)
		var turbo: bool = throttle > 0.99 and next_corner > 180 and speed < car.current_speed_cap * 0.9 and car.turbo_charge > 0.25
		car.set_controls(throttle, clampf(steer, -1, 1), false, turbo)
		await step(1)
		frames += 1
		offroad += int(not car.on_asphalt)
		unsupported += int(not car.is_on_floor())
		peak_speed = maxf(peak_speed, car.speed_mps * 3.6)
		if car.abilities.burst_state == 2:
			burst_frames += 1
			burst_peak = maxf(burst_peak, car.abilities.burst_bonus)
		if nearest > 20 or car.recovery_count > recoveries or car.wall_contacts > walls or not car.velocity.is_finite():
			break
	car.set_controls(0, 0, true)
	var completed: bool = progress >= lengths[-1]-5
	return {"completed": completed, "time_s": frames / 60.0, "distance_m": progress, "expected_m": lengths[-1], "max_deviation_m": max_deviation, "offroad_frames": offroad, "airborne_frames": unsupported, "wall_contacts": car.wall_contacts-walls, "recoveries": car.recovery_count-recoveries, "peak_speed_kmh": peak_speed, "burst_seconds": burst_frames/60.0, "peak_burst_bonus": burst_peak}

func run() -> void:
	var level := Node3D.new()
	root.add_child(level)
	var ground := StaticBody3D.new()
	ground.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(5000, 1, 12000)
	shape.shape = box
	ground.position.y = -0.5
	ground.add_child(shape)
	level.add_child(ground)
	car = preload("res://scenes/cars/PlayerCar.tscn").instantiate()
	level.add_child(car)
	car.configure({"roads": [{"points_xz": [[0, 5000], [0, -5000]], "oneway": false, "street_name": "BALANCE SYNTHETIC FIXTURE"}]}, {"bounds_xz": [-2400, -5500, 2400, 5500], "spawn": {"position_xz": [0, 0], "forward_xz": [0, -1]}})
	for id in Profiles.IDS:
		var straight := {}
		await place(id, Vector3.ZERO, Vector3.FORWARD)
		car.set_controls(1, 0)
		var frames := 0
		for distance in [500, 1000, 2000]:
			while -car.position.z < distance and frames < 6000:
				await step(1)
				frames += 1
			straight[str(distance)] = {"time_s": frames/60.0, "speed_kmh": car.speed_mps*3.6, "burst_bonus": car.abilities.burst_bonus}
		build_path([[0,0],[0,-350],[350,-350],[350,-700],[700,-700],[700,-1050]])
		var corners: Dictionary = await route(id, 24000)
		report["synthetic"][id] = {"straight": straight, "right_angle_course": corners}
		if not corners["completed"]:
			failures.append(id + " synthetic 90-degree course incomplete")
		print("BALANCE_SYNTHETIC ", id, " ", JSON.stringify(report["synthetic"][id]))
	level.queue_free()
	await process_frame
	if "--synthetic-only" in OS.get_cmdline_user_args():
		report["passed"] = failures.is_empty()
		report["failures"] = failures
		FileAccess.open("res://docs/burst_balance_synthetic.json", FileAccess.WRITE).store_string(JSON.stringify(report, "  "))
		quit(0 if failures.is_empty() else 1)
		return
	# Resolve after Autoload initialization; derived SF.1 tools reuse the driver.
	world = load("res://scenes/ReliefWorld.tscn").instantiate()
	root.add_child(world)
	car = world.player
	car.external_control = true
	await step(10)
	for file in ["c5_cajoncito_federal_1", "c5_north_neighborhoods", "c5_north_coast"]:
		var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tracks/" + file + ".json"))
		build_path(data["points_xz"])
		report["real_routes"][file] = {}
		for id in Profiles.IDS:
			var result: Dictionary = await route(id)
			report["real_routes"][file][id] = result
			if not result["completed"] or result["recoveries"] > 0 or result["wall_contacts"] > 0:
				failures.append(id + " real route failed: " + file)
			print("BALANCE_REAL ",file," ",id," ", JSON.stringify(result))
	report["passed"] = failures.is_empty()
	report["failures"] = failures
	FileAccess.open("res://docs/burst_balance.json", FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("BALANCE_REPORT ",JSON.stringify({"passed":failures.is_empty(),"failures":failures}))
	quit(0 if failures.is_empty() else 1)

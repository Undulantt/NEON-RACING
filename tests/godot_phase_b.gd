extends SceneTree

const Main = preload("res://scenes/FlatWorld.tscn")
var world: Node3D
var car: CharacterBody3D
var failures: Array[String] = []
var metrics := {}
var points := PackedVector3Array()
var lengths := PackedFloat64Array()
var route_progress := 0.0
var route_index := 0
var visualize := false
var test_frames := 0
var route_frame_limit := 20000
var facade_min_length := 12.0

func _initialize() -> void:
	visualize = "--visual-test" in OS.get_cmdline_user_args()
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("PHASE_B_TEST: " + message)

func step(frames: int, throttle: float = 0, steer: float = 0, brake: bool = false) -> void:
	car.set_controls(throttle, steer, brake)
	for i in range(frames):
		await physics_frame
		test_frames += 1

func place(p: Vector3, forward: Vector3) -> void:
	car.global_transform = Transform3D(Basis(Vector3.UP, atan2(-forward.x, -forward.z)), p)
	car.velocity = Vector3.ZERO
	car.speed_mps = 0
	car.signed_speed = 0
	car.steering = 0
	car.clear_drift_reward()
	car.set_controls(0, 0)
	world.follow_camera.snap()

func _run() -> void:
	world = Main.instantiate()
	root.add_child(world)
	await physics_frame
	await physics_frame
	if world.player == null:
		check(false, "Main scene failed to create player: " + world.runtime_error)
		finish()
		return
	car = world.player
	car.external_control = true
	await step(20)
	check(car.is_on_floor() and car.on_asphalt, "Spawn must be on asphalt with support")
	check(car.safe_road_transform(car.spawn_transform), "Spawn full footprint must be safe")
	var road: Dictionary = {}
	for candidate in world.map_data["roads"]:
		if candidate["id"] == "24503430:18":
			road = candidate
	check(not road.is_empty(), "Known authentic long straight missing")
	if road.is_empty():
		finish()
		return
	var a := Vector3(road["points_xz"][0][0], 0.67, road["points_xz"][0][1])
	var b := Vector3(road["points_xz"][-1][0], 0.67, road["points_xz"][-1][1])
	var forward := (b - a).normalized()
	place(a + forward * 15, forward)
	await step(20)
	var stationary_yaw := car.rotation.y
	await step(60, 0, 1)
	check(absf(wrapf(car.rotation.y - stationary_yaw, -PI, PI)) < 0.01, "Vehicle rotates at zero speed")
	await step(240, 1)
	metrics["forward_speed_mps"] = car.speed_mps
	check(car.speed_mps > 31.0 and car.speed_mps <= 32.1, "Forward acceleration/speed cap")
	check(absf(float(world.hud.speed_label.text.split(" ")[0]) - car.speed_mps * 3.6) < 2, "HUD km/h conversion")
	var braking_frames := 0
	while car.signed_speed > 0.15 and braking_frames < 180:
		await step(1, -1)
		braking_frames += 1
	metrics["braking_frames_from_max"] = braking_frames
	check(braking_frames > 30 and braking_frames < 110, "Brake must decelerate progressively")
	await step(120, -1)
	metrics["reverse_speed_mps"] = car.signed_speed
	check(car.signed_speed < -6.5 and car.signed_speed >= -7.1, "Reverse speed cap")
	await step(60, 1)
	check(car.signed_speed > -0.2, "Forward input must brake reverse")
	# Real InputMap path: physical key events, no direct controller commands.
	place(a + forward * 15, forward)
	await step(20)
	car.external_control = false
	await hold_key(KEY_W, 120)
	check(car.speed_mps > 20, "Physical W mapping did not accelerate")
	await hold_key(KEY_DOWN, 60)
	check(absf(car.signed_speed) < 1.0, "Arrow-down mapping did not brake")
	await hold_key(KEY_S, 60)
	check(car.signed_speed < -6, "Physical S mapping did not reverse")
	var yaw_before := car.rotation.y
	await hold_key(KEY_A, 12)
	check(absf(wrapf(car.rotation.y - yaw_before, -PI, PI)) > 0.01, "Physical A mapping did not steer")
	var count_before: int = car.recovery_count
	await hold_key(KEY_R, 2)
	await step(20)
	check(car.recovery_count == count_before + 1 and car.speed_mps < 0.1, "Physical R mapping failed")
	await hold_key(KEY_UP, 60)
	check(car.speed_mps > 9, "Arrow-up mapping did not accelerate")
	await hold_key(KEY_SPACE, 60)
	check(car.speed_mps < 0.5, "Space mapping did not apply handbrake")
	car.external_control = true
	metrics["physical_key_events_tested"] = ["W", "Down", "S", "A", "R", "Up", "Space"]
	# Same initial state: handbrake must retain more lateral slip than normal grip.
	var slips: Array[float] = []
	for handbrake in [false, true]:
		place(a + forward * 70, forward)
		await step(10)
		car.velocity = forward * 16.0
		await step(35, 1, 0.65, handbrake)
		var velocity_flat := Vector3(car.velocity.x, 0, car.velocity.z)
		slips.append(absf(velocity_flat.normalized().signed_angle_to(-car.global_basis.z, Vector3.UP)))
	metrics["normal_slip_rad"] = slips[0]
	metrics["handbrake_slip_rad"] = slips[1]
	check(slips[1] > slips[0] + 0.015, "Handbrake must increase controllable slip")
	# The actual production controller drives a real connected multi-street route.
	await drive_route()
	# Recovery must zero motion, restore clear asphalt, and work repeatedly.
	for i in range(3):
		car.position.y = -8
		await step(3)
		await step(15)
		check(car.is_on_floor() and car.on_asphalt and car.speed_mps < 0.1, "Automatic recovery failed")
		car.velocity = Vector3(12, 0, 0)
		car.recover("prueba manual")
		await step(15)
		check(car.safe_road_transform(car.global_transform) and car.speed_mps < 0.1, "Manual recovery failed")
	await facade_and_camera()
	await boundaries()
	# Pausing must stop both movement and physics, and can resume.
	place(car.spawn_transform.origin, -car.spawn_transform.basis.z)
	await step(20)
	car.set_controls(1, 0)
	await tap_key(KEY_ESCAPE)
	check(paused, "Escape mapping did not pause")
	world.hud.buttons[2].pressed.emit()
	check(world.hud.menu_open and paused, "Return-to-menu button failed")
	world.hud.buttons[1].pressed.emit()
	check(not paused and car.position.distance_to(car.spawn_transform.origin) < 0.1, "Menu restart failed")
	await tap_key(KEY_ESCAPE)
	var frozen: Vector3 = car.position
	for i in range(10):
		await process_frame
	check(car.position.distance_to(frozen) < 0.001, "Pause does not freeze car")
	await tap_key(KEY_ESCAPE)
	check(not paused, "Escape mapping did not resume")
	await step(30, 1)
	check(car.speed_mps > 2.0, "Resume did not restore driving")
	world.toggle_camera()
	await step(20, 1)
	check(world.aerial and not car.driving_enabled and world.overhead.current, "Inspection camera toggle failed")
	world.toggle_camera()
	check(car.driving_enabled and world.follow_camera.camera.current, "Driving camera restore failed")
	metrics["recovery_count_total"] = car.recovery_count
	finish()

func tap_key(code: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	event = InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = false
	Input.parse_input_event(event)
	await process_frame

func hold_key(code: Key, frames: int) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = true
	Input.parse_input_event(event)
	for i in range(frames):
		await physics_frame
		test_frames += 1
	event = InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = false
	Input.parse_input_event(event)
	await physics_frame

func sample(at: float) -> Vector3:
	var i := clampi(lengths.bsearch(at) - 1, 0, points.size() - 2)
	return points[i].lerp(points[i + 1], clampf((at - lengths[i]) / (lengths[i + 1] - lengths[i]), 0, 1))

func drive_route() -> void:
	var data: Dictionary = world.environment_data["driving_test_route"]
	for p in data["points_xz"]:
		points.append(Vector3(p[0], 0, p[1]))
	lengths.append(0)
	for i in range(1, points.size()):
		lengths.append(lengths[-1] + points[i].distance_to(points[i - 1]))
	place(points[0] + Vector3.UP * 0.67, (points[1] - points[0]).normalized())
	await step(20)
	var starting_recoveries: int = car.recovery_count
	var starting_contacts: int = car.wall_contacts
	var frames := 0
	var offroad_frames := 0
	var unsupported_frames := 0
	var max_deviation := 0.0
	var captures := 0
	while route_progress < lengths[-1] - 3 and frames < route_frame_limit:
		var best := INF
		var point := Vector3(car.position.x, 0, car.position.z)
		for i in range(maxi(0, route_index - 2), mini(points.size() - 1, route_index + 8)):
			var closest := Geometry3D.get_closest_point_to_segment(point, points[i], points[i + 1])
			var deviation := point.distance_to(closest)
			if deviation < best:
				best = deviation
				route_index = i
				route_progress = maxf(route_progress, lengths[i] + points[i].distance_to(closest))
		max_deviation = maxf(max_deviation, best)
		var desired_speed := 12.0
		for i in range(maxi(1, route_index), mini(points.size() - 1, route_index + 8)):
			if lengths[i] - route_progress > 25:
				break
			if lengths[i] > route_progress - 4:
				var incoming := (points[i] - points[i - 1]).normalized()
				var outgoing := (points[i + 1] - points[i]).normalized()
				if incoming.dot(outgoing) < 0.85:
					desired_speed = 5.0
		var target := sample(minf(route_progress + 3.0 + car.speed_mps * 0.35, lengths[-1]))
		var direction := (target - point).normalized()
		var yaw := atan2(-direction.x, -direction.z)
		var error := wrapf(yaw - car.rotation.y, -PI, PI)
		var steer := clampf(-error * 2.0, -1, 1)
		var throttle := clampf((desired_speed - car.speed_mps) * 0.7, -1, 1)
		await step(1, throttle, steer)
		frames += 1
		if not car.on_asphalt:
			offroad_frames += 1
		if not car.is_on_floor():
			unsupported_frames += 1
		if visualize and captures < 3 and route_progress > [200.0, 600.0, 1000.0][captures]:
			await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(("res://docs/evidence/phase_b5_drive_%d.png" if world.city_manager != null else "res://docs/evidence/phase_b_drive_%d.png") % captures)
			captures += 1
		if best > 10 or car.recovery_count > starting_recoveries:
			break
	var degree := {}
	for road in world.map_data["roads"]:
		for id in [road["from"], road["to"]]:
			degree[id] = degree.get(id, 0) + 1
	var crossed := 0
	for i in range(data["node_ids"].size()):
		if lengths[i] <= route_progress and degree.get(data["node_ids"][i], 0) >= 3:
			crossed += 1
	metrics["route_junctions_crossed"] = crossed
	check(crossed >= 5, "Fewer than five connected intersections driven")
	metrics["route_distance_m"] = route_progress
	metrics["route_expected_m"] = lengths[-1]
	metrics["route_streets"] = data["street_names"]
	metrics["route_frames"] = frames
	metrics["route_max_deviation_m"] = max_deviation
	metrics["route_offroad_frames"] = offroad_frames
	metrics["route_unsupported_frames"] = unsupported_frames
	metrics["route_wall_contacts"] = car.wall_contacts - starting_contacts
	metrics["route_recoveries"] = car.recovery_count - starting_recoveries
	check(route_progress >= lengths[-1] - 3, "Car did not complete multi-street driving test")
	check(unsupported_frames == 0, "Car lost ground during connected-road traversal")
	check(offroad_frames == 0, "Car left asphalt during connected-road traversal")
	check(car.wall_contacts == starting_contacts and car.recovery_count == starting_recoveries, "Route required collision/recovery")

func facade_and_camera() -> void:
	var found := false
	for building in world.get_collision_test_buildings():
		var ring: Array = building["footprint_xz"]
		for i in range(ring.size()):
			var a := Vector3(ring[i][0], 0, ring[i][1])
			var b := Vector3(ring[(i + 1) % ring.size()][0], 0, ring[(i + 1) % ring.size()][1])
			if a.distance_to(b) < facade_min_length:
				continue
			var side := (b - a).normalized()
			var normal := Vector3(side.z, 0, -side.x)
			var middle := (a + b) / 2
			var position := middle + normal * 8 + Vector3.UP * 0.67
			var pose := Transform3D(Basis(Vector3.UP, atan2(normal.x, normal.z)), position)
			if not car.clear_of_obstacles(pose):
				continue
			place(position, -normal)
			await step(20)
			var before: int = car.wall_contacts
			await step(180, 1)
			var distance: float = (car.position - middle).dot(normal)
			metrics["facade_distance_after_impact_m"] = distance
			metrics["facade_contacts"] = car.wall_contacts - before
			check(distance > 1.8 and distance < 2.4 and car.wall_contacts > before, "Car penetrated/missed real facade")
			check(car.speed_mps < 0.2, "Facade impact did not reduce speed")
			place(middle + normal * 3.0 + Vector3.UP * 0.67, normal)
			await step(30)
			metrics["camera_arm_at_facade_m"] = world.follow_camera.arm.get_hit_length()
			check(world.follow_camera.arm.get_hit_length() < 4.0, "SpringArm did not retract at facade")
			found = true
			break
		if found:
			break
	check(found, "No suitable real facade available for collision test")

func boundaries() -> void:
	if world.environment_data.has("playable_boundary_xz"):
		await polygon_boundaries()
		return
	var bounds: Array = world.environment_data["bounds_xz"]
	var fixtures := [
		[Vector3(bounds[0] + 8, 0.67, bounds[1] + 15), Vector3.LEFT],
		[Vector3(bounds[2] - 8, 0.67, bounds[1] + 15), Vector3.RIGHT],
		[Vector3(bounds[0] + 15, 0.67, bounds[1] + 8), Vector3.FORWARD],
		[Vector3(bounds[0] + 15, 0.67, bounds[3] - 8), Vector3.BACK]]
	for i in range(fixtures.size()):
		place(fixtures[i][0], fixtures[i][1])
		await step(20)
		var before: int = car.wall_contacts
		await step(120, 1)
		check(car.world_bounds.has_point(Vector2(car.position.x, car.position.z)) and car.wall_contacts > before and car.speed_mps < 0.2, "World boundary %d failed" % i)
	metrics["boundaries_tested"] = fixtures.size()

func polygon_boundaries() -> void:
	# C.5 removed the old rectangular southern corner. Test the current
	# playable polygon instead of teleporting outside the map's physical floor.
	var ring: Array = world.environment_data["playable_boundary_xz"]
	var polygon := PackedVector2Array()
	for p in ring:polygon.append(Vector2(p[0],p[1]))
	var tested := 0
	for i in range(ring.size()):
		var a := Vector3(ring[i][0],0,ring[i][1])
		var b := Vector3(ring[(i+1)%ring.size()][0],0,ring[(i+1)%ring.size()][1])
		if a.distance_to(b)<25:continue
		var middle := (a+b)*0.5
		var side := (b-a).normalized()
		var outward := Vector3(side.z,0,-side.x)
		if Geometry2D.is_point_in_polygon(Vector2(middle.x+outward.x*3,middle.z+outward.z*3),polygon):outward=-outward
		var start := middle-outward*8+Vector3.UP*0.67
		place(start,outward)
		await step(30)
		if not car.is_on_floor() or not car.clear_of_obstacles(car.global_transform):continue
		var clear := true
		for distance in [4.0,5.0,6.0]:
			var pose := car.global_transform
			pose.origin=middle-outward*distance+Vector3.UP*0.67
			var query:=PhysicsShapeQueryParameters3D.new()
			query.shape=car.collision_shape
			query.transform=pose
			query.collision_mask=4
			if not world.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty():clear=false
		if not clear:continue
		var before: int=car.wall_contacts
		await step(180,1)
		check(Geometry2D.is_point_in_polygon(Vector2(car.position.x,car.position.z),polygon) and car.wall_contacts>before and car.speed_mps<0.2,"Playable polygon boundary failed")
		tested+=1
		if tested==4:break
	check(tested==4,"Four physical polygon boundaries must be tested")
	metrics["boundaries_tested"]=tested

func finish() -> void:
	var report := {"passed": failures.is_empty(), "failures": failures, "metrics": metrics, "physics_frames": test_frames, "world": world.stats, "city_streaming": world.city_manager.status() if world.city_manager != null else {}}
	var prefix := "res://docs/phase_b5_driving_validation" if world.city_manager != null else "res://docs/phase_b_validation"
	if "--phase-c-regression" in OS.get_cmdline_user_args():
		prefix = "res://docs/phase_c_route_validation"
	if "--slope-regression" in OS.get_cmdline_user_args():
		prefix = "res://docs/slope_controls_validation"
	if "--road-regression" in OS.get_cmdline_user_args():
		prefix = "res://docs/road_width_route_validation"
	var file := FileAccess.open(prefix + ("_render.json" if visualize else ".json"), FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(report, "  "))
	print("PHASE_B_REPORT ", JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)

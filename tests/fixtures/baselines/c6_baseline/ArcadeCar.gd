extends CharacterBody3D

signal recovered(reason: String)
const VisualBuilder = preload("res://scripts/driving/CarVisual.gd")
var config: Dictionary
var driving_enabled := true
var debug_speed_enabled := false
var external_control := false
var command_throttle := 0.0
var command_steer := 0.0
var command_handbrake := false
var command_turbo := false
var turbo_charge := 1.0
var turbo_active := false
var turbo_exhausted := false
var turbo_cooldown := 0.0
var drift_amount := 0.0
var slip_angle := 0.0
var drift_charge := 0.0
var drift_quality := 0.0
var drift_tracking := false
var drift_valid_time := 0.0
var drift_exit_time := 0.0
var drift_settle_time := 0.0
var drift_boost_time := 0.0
var drift_boost_strength := 0.0
var drift_boost_active := false
var drift_rewards := 0
var drift_particles: Node3D
var grip_blend := 1.0
var throttle_input := 0.0
var feedback: Node
var speed_mps := 0.0
var signed_speed := 0.0
var steering := 0.0
var on_asphalt := false
var recovery_count := 0
var wall_contacts := 0
var street_name := ""
var spawn_transform := Transform3D.IDENTITY
var safe_transform := Transform3D.IDENTITY
var safety_timer := 0.0
var collision_shape: BoxShape3D
var road_segments: Array = []
var road_cells: Dictionary = {}
var world_bounds := Rect2()
var visuals: Dictionary
var visual_root: Node3D
var elevation: RefCounted
var ground_vertical_speed := 0.0
var takeoff_cooldown := 0.0
var airborne_time := 0.0
var crest_takeoffs := 0
var slope_acceleration := 0.0
var previous_motion_position := Vector3.ZERO
var crest_release_remaining := 0.0
var crest_launch_velocity := 0.0

func drive_test_multiplier() -> float:
	return 2.0 if debug_speed_enabled else 1.0

func _unhandled_input(event: InputEvent) -> void:
	if driving_enabled and not get_tree().paused and event.is_action_pressed("debug_speed_toggle") and not event.is_echo():
		debug_speed_enabled = not debug_speed_enabled
		get_viewport().set_input_as_handled()

func reset_surface_motion() -> void:
	ground_vertical_speed = 0.0
	takeoff_cooldown = 0.2
	airborne_time = 0.0
	crest_release_remaining = 0.0
	crest_launch_velocity = 0.0
	floor_snap_length = 0.35
	previous_motion_position = global_position

func predicted_support_height(at: Vector3) -> float:
	# Query the physical surface, including ramps/bridges, rather than assuming
	# every drivable surface is the geographic DEM. Upright chassis support uses
	# its four corners; the ray excludes cars, buildings and boundary walls.
	var height := -INF
	for local in [Vector3(-0.9,0,-2.05), Vector3(0.9,0,-2.05), Vector3(-0.9,0,2.05), Vector3(0.9,0,2.05)]:
		var p: Vector3 = at + global_basis * local
		var query := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 3, p - Vector3.UP * 8, 3)
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		if hit.is_empty():
			return NAN
		height = maxf(height, hit["position"].y)
	return height + collision_shape.size.y * 0.5 + safe_margin

func should_leave_crest(horizontal: Vector3, gravity: float) -> bool:
	if takeoff_cooldown > 0 or horizontal.length() < float(config["crest_min_speed_mps"]) or ground_vertical_speed < float(config["crest_min_rise_mps"]):
		return false
	var time: float = config["crest_prediction_s"]
	var future := global_position + horizontal * time
	var support := predicted_support_height(future)
	if not is_finite(support):
		return false
	var rise := minf(ground_vertical_speed, float(config["crest_max_vertical_speed_mps"]))
	var ballistic_y := global_position.y + rise * time - 0.5 * gravity * time * time
	return ballistic_y - support > float(config["crest_min_clearance_m"])

func surface_height(x: float, z: float) -> float:
	return elevation.get_height_at(x, z) if elevation != null else 0.0

func supported_pose_height(x: float, z: float, yaw: float) -> float:
	var height := surface_height(x, z)
	if elevation != null:
		var basis := Basis(Vector3.UP, yaw)
		for local in [Vector3(-0.9, 0, -2.05), Vector3(0.9, 0, -2.05), Vector3(-0.9, 0, 2.05), Vector3(0.9, 0, 2.05)]:
			var p: Vector3 = basis * local + Vector3(x, 0, z)
			height = maxf(height, surface_height(p.x, p.z))
	return height + 0.67

func _ready() -> void:
	config = JSON.parse_string(FileAccess.get_file_as_string("res://config/driving_config.json"))
	collision_layer = 16
	collision_mask = 15
	floor_snap_length = 0.35
	floor_max_angle = deg_to_rad(42)
	safe_margin = 0.005
	max_slides = 6
	collision_shape = BoxShape3D.new()
	collision_shape.size = Vector3(1.8, 1.2, 4.1)
	var collider := CollisionShape3D.new()
	collider.shape = collision_shape
	add_child(collider)
	visual_root = Node3D.new()
	add_child(visual_root)
	visuals = VisualBuilder.build(visual_root)
	feedback = Node.new()
	feedback.set_script(preload("res://scripts/driving/DrivingFeedback.gd"))
	add_child(feedback)
	feedback.attach(self)
	drift_particles = Node3D.new()
	drift_particles.set_script(preload("res://scripts/driving/DriftParticles.gd"))
	add_child(drift_particles)
	drift_particles.attach(self)

func configure(map_data: Dictionary, environment: Dictionary) -> void:
	road_segments = map_data["roads"]
	road_cells.clear()
	# Index the original segments with margin; safety queries need only local roads.
	for road in road_segments:
		var a: Array = road["points_xz"][0]
		var b: Array = road["points_xz"][-1]
		for x in range(floori((minf(a[0], b[0]) - 32) / 256), floori((maxf(a[0], b[0]) + 32) / 256) + 1):
			for z in range(floori((minf(a[1], b[1]) - 32) / 256), floori((maxf(a[1], b[1]) + 32) / 256) + 1):
				var cell := Vector2i(x, z)
				if not road_cells.has(cell):
					road_cells[cell] = []
				road_cells[cell].append(road)
	var bounds: Array = environment["bounds_xz"]
	world_bounds = Rect2(bounds[0], bounds[1], bounds[2] - bounds[0], bounds[3] - bounds[1])
	var p: Array = environment["spawn"]["position_xz"]
	var f: Array = environment["spawn"]["forward_xz"]
	var yaw := atan2(-float(f[0]), -float(f[1]))
	spawn_transform = Transform3D(Basis(Vector3.UP, yaw), Vector3(p[0], supported_pose_height(p[0], p[1], yaw), p[1]))
	safe_transform = spawn_transform
	global_transform = spawn_transform
	reset_surface_motion()

func set_controls(throttle: float, steer: float, handbrake: bool = false, turbo: bool = false) -> void:
	command_throttle = clampf(throttle, -1, 1)
	command_steer = clampf(steer, -1, 1)
	command_handbrake = handbrake
	command_turbo = turbo

func road_hit(p: Vector3) -> bool:
	var depth := 2.5 if elevation != null else 1.17
	var query := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 1.13, p - Vector3.UP * depth, 1)
	return not get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func clear_of_obstacles(at: Transform3D) -> bool:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = collision_shape
	query.transform = at
	query.collision_mask = 12
	query.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()

func safe_road_transform(at: Transform3D) -> bool:
	if not world_bounds.grow(-3).has_point(Vector2(at.origin.x, at.origin.z)) or not clear_of_obstacles(at):
		return false
	for local in [Vector3.ZERO, Vector3(-0.85, 0, -1.9), Vector3(0.85, 0, -1.9), Vector3(-0.85, 0, 1.9), Vector3(0.85, 0, 1.9)]:
		if not road_hit(at * local):
			return false
	return true

func update_safe_position() -> void:
	var best := INF
	var candidate := global_transform
	var found := false
	var p := Vector2(global_position.x, global_position.z)
	for road in road_cells.get(Vector2i(floori(p.x / 256), floori(p.y / 256)), []):
		var a := Vector2(road["points_xz"][0][0], road["points_xz"][0][1])
		var b := Vector2(road["points_xz"][-1][0], road["points_xz"][-1][1])
		var closest := Geometry2D.get_closest_point_to_segment(p, a, b)
		var distance := p.distance_squared_to(closest)
		if distance < best:
			best = distance
			var direction := Vector3(b.x - a.x, 0, b.y - a.y).normalized()
			if not road["oneway"] and direction.dot(-global_basis.z) < 0:
				direction = -direction
			var height := surface_height(closest.x, closest.y)
			if not is_finite(height):
				continue
			var yaw := atan2(-direction.x, -direction.z)
			candidate = Transform3D(Basis(Vector3.UP, yaw), Vector3(closest.x, supported_pose_height(closest.x, closest.y, yaw), closest.y))
			street_name = road["street_name"]
			found = true
	if found and on_asphalt and is_on_floor() and best < 4.0 and safe_road_transform(candidate):
		safe_transform = candidate

func recover(reason: String = "manual") -> void:
	var target := safe_transform
	if not safe_road_transform(target):
		target = spawn_transform
	if not safe_road_transform(target):
		push_error("Recovery rejected: no clear, fully supported road pose")
		return
	global_transform = target
	reset_surface_motion()
	velocity = Vector3.ZERO
	speed_mps = 0.0
	signed_speed = 0.0
	steering = 0.0
	turbo_active = false
	drift_amount = 0.0
	slip_angle = 0.0
	grip_blend = 1.0
	throttle_input = 0.0
	clear_drift_reward()
	drift_particles.clear_trail()
	recovery_count += 1
	reset_physics_interpolation()
	recovered.emit(reason)

func _physics_process(delta: float) -> void:
	if road_segments.is_empty():
		return
	if global_position.distance_squared_to(previous_motion_position) > 9.0:
		reset_surface_motion()
	takeoff_cooldown = maxf(0.0, takeoff_cooldown - delta)
	crest_release_remaining = maxf(0.0, crest_release_remaining - delta)
	if driving_enabled and Input.is_action_just_pressed("recover") and not external_control:
		recover()
	var throttle := command_throttle if external_control else Input.get_axis("brake_reverse", "accelerate")
	var steer := command_steer if external_control else Input.get_axis("steer_left", "steer_right")
	var handbrake := command_handbrake if external_control else Input.is_action_pressed("handbrake")
	if not driving_enabled:
		throttle = 0
		steer = 0
		handbrake = true
	throttle_input = throttle
	on_asphalt = road_hit(global_position)
	var forward := -global_basis.z
	var horizontal := Vector3(velocity.x, 0, velocity.z)
	var longitudinal := horizontal.dot(forward)
	var lateral := horizontal - forward * longitudinal
	var grounded := is_on_floor()
	var gravity: float = config["gravity_mps2"]
	slope_acceleration = Vector3.DOWN.slide(get_floor_normal()).dot(forward) * gravity if grounded else 0.0
	if grounded:
		longitudinal += slope_acceleration * delta
	var test_multiplier := drive_test_multiplier()
	var max_speed: float = config["max_forward_speed_mps"] if on_asphalt else config["offroad_speed_mps"]
	var turbo_requested := command_turbo if external_control else Input.is_action_pressed("turbo")
	if not turbo_requested:
		turbo_exhausted = false
	var eligible := driving_enabled and on_asphalt and is_on_floor() and throttle > 0 and longitudinal > 2.0 and not handbrake
	var was_active := turbo_active
	turbo_active = turbo_requested and eligible and not turbo_exhausted and (turbo_charge > 0 if was_active else turbo_charge >= float(config["turbo_min_charge"]))
	if turbo_active:
		turbo_charge = maxf(0.0, turbo_charge - delta / float(config["turbo_duration_s"]))
		turbo_cooldown = float(config["turbo_recharge_delay_s"])
		if turbo_charge <= 0:
			turbo_exhausted = true
			turbo_active = false
	else:
		turbo_cooldown = maxf(0.0, turbo_cooldown - delta)
		if turbo_cooldown <= 0 and driving_enabled:
			turbo_charge = minf(1.0, turbo_charge + delta / float(config["turbo_recharge_s"]))
	# The earned exit boost is separate from the Shift reserve and cannot stack.
	if handbrake or turbo_active or not eligible or throttle <= 0:
		drift_boost_time = 0.0
	drift_boost_time = maxf(0.0, drift_boost_time - delta)
	drift_boost_active = drift_boost_time > 0.0
	if turbo_active:
		max_speed = float(config["turbo_speed_mps"])
	elif drift_boost_active:
		max_speed += float(config["drift_bonus_mps"]) * drift_boost_strength
	max_speed *= test_multiplier
	if grounded and throttle > 0:
		# Engine force must compete with gravity even when rolling backwards;
		# do not silently substitute the stronger service brake for engine torque.
		longitudinal = move_toward(longitudinal, max_speed, float(config["turbo_acceleration_mps2"] if turbo_active else config["acceleration_mps2"]) * test_multiplier * throttle * delta)
	elif grounded and throttle < 0:
		var reverse_force := float(config["braking_mps2"]) if longitudinal > 0.1 else float(config["acceleration_mps2"]) * test_multiplier
		longitudinal = move_toward(longitudinal, -float(config["max_reverse_speed_mps"]) * test_multiplier, reverse_force * -throttle * delta)
	elif grounded:
		longitudinal = move_toward(longitudinal, 0, float(config["coast_deceleration_mps2"]) * delta)
	if drift_boost_active:
		longitudinal = minf(max_speed, longitudinal + float(config["drift_bonus_mps"]) * test_multiplier * drift_boost_strength / float(config["drift_bonus_duration_s"]) * delta)
	if grounded and handbrake:
		longitudinal = move_toward(longitudinal, 0, float(config["handbrake_deceleration_mps2"]) * delta)
	if grounded and absf(longitudinal) > max_speed:
		longitudinal = move_toward(longitudinal, signf(longitudinal) * max_speed, 12.0 * delta)
	steering = move_toward(steering, steer, float(config["steering_response_per_second"]) * delta)
	var reduction := lerpf(1.0, 1.0 - float(config["steering_reduction_at_high_speed"]), clampf(absf(longitudinal) / (float(config["max_forward_speed_mps"]) * test_multiplier), 0, 1))
	var angle := steering * float(config["max_steer_radians"]) * reduction * float(config["steering_sensitivity"])
	var yaw_delta := -clampf(longitudinal / float(config["wheelbase_m"]) * tan(angle), -1.7, 1.7) * delta
	if not grounded:
		yaw_delta *= float(config["air_steering_multiplier"])
	var proposed := Transform3D(Basis(Vector3.UP, rotation.y + yaw_delta), global_position)
	if absf(yaw_delta) > 0.00001 and clear_of_obstacles(proposed):
		rotation.y += yaw_delta
	var grip: float = config["lateral_grip_per_second"]
	var drifting := handbrake and absf(longitudinal) >= float(config["drift_min_speed_mps"])
	grip_blend = move_toward(grip_blend, float(config["handbrake_grip_multiplier"]) if drifting else 1.0, (8.0 if drifting else float(config["drift_grip_recovery_per_second"])) * delta)
	grip *= grip_blend
	if not grounded:
		grip = 0.0
	horizontal = (forward * longitudinal + lateral).lerp(-global_basis.z * longitudinal, 1.0 - exp(-grip * delta))
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	if grounded and (handbrake or throttle < 0 or horizontal.length() < float(config["crest_min_speed_mps"])):
		crest_release_remaining = 0.0
	var taking_off := grounded and not handbrake and throttle >= 0 and should_leave_crest(horizontal, gravity)
	if taking_off:
		crest_launch_velocity = ground_vertical_speed
		crest_release_remaining = 0.2
		velocity.y = crest_launch_velocity
		takeoff_cooldown = float(config["crest_cooldown_s"])
		floor_snap_length = 0.0
	elif grounded and crest_release_remaining > 0:
		# Finish leaving the crest with the existing ramp momentum. Capping it
		# below the ramp's tangent speed before separation would glue the box
		# back to the hill. Apply the arcade cap once it is actually airborne.
		velocity.y = crest_launch_velocity
		floor_snap_length = 0.0
	elif grounded:
		velocity.y = -2.0
		floor_snap_length = 0.35
	else:
		velocity.y -= gravity * delta
		floor_snap_length = 0.0
	move_and_slide()
	var hit_wall := false
	for i in range(get_slide_collision_count()):
		var collision := get_slide_collision(i)
		if absf(collision.get_normal().y) < 0.5:
			wall_contacts += 1
			hit_wall = true
	var actual := get_real_velocity()
	if is_on_floor():
		ground_vertical_speed = actual.y
		airborne_time = 0.0
	elif grounded and crest_release_remaining > 0:
		velocity.y = minf(velocity.y, float(config["crest_max_vertical_speed_mps"]))
		crest_takeoffs += 1
		crest_release_remaining = 0.0
		airborne_time = delta
	elif grounded and not taking_off:
		# Natural ledges also preserve the ramp's upward momentum.
		velocity.y = maxf(velocity.y, minf(ground_vertical_speed, float(config["crest_max_vertical_speed_mps"])))
	else:
		airborne_time += delta
	previous_motion_position = global_position
	speed_mps = Vector2(actual.x, actual.z).length()
	signed_speed = Vector3(velocity.x, 0, velocity.z).dot(-global_basis.z)
	var flat_velocity := Vector3(velocity.x, 0, velocity.z)
	slip_angle = flat_velocity.normalized().signed_angle_to(-global_basis.z, Vector3.UP) if speed_mps > 1.0 else 0.0
	drift_amount = clampf(absf(slip_angle) / 0.65, 0.0, 1.0) if on_asphalt and is_on_floor() and signed_speed > float(config["drift_min_speed_mps"]) else 0.0
	update_drift_reward(delta, handbrake, hit_wall)
	safety_timer += delta
	if safety_timer >= float(config["recovery_interval_s"]):
		safety_timer = 0.0
		update_safe_position()
	var ground_height := surface_height(global_position.x, global_position.z)
	if not is_finite(ground_height) or global_position.y < ground_height - 4 or not world_bounds.grow(5).has_point(Vector2(global_position.x, global_position.z)) or global_basis.y.dot(Vector3.UP) < 0.5:
		recover("fuera de límites")
	visual_root.rotation.z = lerpf(visual_root.rotation.z, steering * minf(speed_mps / 32, 1) * 0.05, 8 * delta)
	if elevation != null and is_on_floor():
		align_visual_to_surface()
	elif not is_on_floor():
		# Retract wheels to their chassis mounts in flight. They must not stretch
		# back down toward the terrain while the collision body is airborne.
		visual_root.position.y = lerpf(visual_root.position.y, 0.0, minf(1.0, 12.0 * delta))
		for pivot in visuals["pivots"]:
			pivot.position.y = -0.26
		if elevation != null:
			var visual_lift := 0.0
			for pivot in visuals["pivots"]:
				var p: Vector3 = pivot.global_position
				var h := surface_height(p.x,p.z)
				if is_finite(h):
					visual_lift = maxf(visual_lift,h+0.345-p.y)
			visual_root.position.y += visual_lift
	for i in range(visuals["pivots"].size()):
		if i < 2:
			visuals["pivots"][i].rotation.y = -angle
		visuals["wheels"][i].rotate_object_local(Vector3.UP, -signed_speed * delta / 0.34)
	visuals["brake_material"].emission_energy_multiplier = 2.5 if throttle < 0 or handbrake else 0.3

	for flame in visuals["exhaust"]:
		flame.visible = turbo_active or drift_boost_active
		flame.scale.z = (1.0 if turbo_active else 0.45) * (1.0 + sin(Time.get_ticks_msec() * 0.06) * 0.22)

func align_visual_to_surface() -> void:
	# Keep the arcade collision box upright; fit the visual chassis to axle contacts.
	var heights: Array[float] = []
	for local in [Vector3(-0.91,0,-1.3), Vector3(0.91,0,-1.3), Vector3(-0.91,0,1.3), Vector3(0.91,0,1.3)]:
		var p: Vector3 = global_basis * local + global_position
		heights.append(surface_height(p.x,p.z))
	var front := (heights[0]+heights[1])*0.5
	var rear := (heights[2]+heights[3])*0.5
	var left := (heights[0]+heights[2])*0.5
	var right := (heights[1]+heights[3])*0.5
	visual_root.rotation.x = atan2(front-rear,2.6)
	visual_root.rotation.z = atan2(right-left,1.82)
	visual_root.position.y = (front+rear)*0.5 + 0.60 - global_position.y
	for i in range(4):
		var pivot: Node3D = visuals["pivots"][i]
		var p := pivot.global_position
		var local_center := visual_root.to_local(Vector3(p.x, surface_height(p.x,p.z)+0.34, p.z))
		pivot.position.y = local_center.y

func clear_drift_reward() -> void:
	drift_charge = 0.0
	drift_quality = 0.0
	drift_tracking = false
	drift_valid_time = 0.0
	drift_exit_time = 0.0
	drift_settle_time = 0.0
	drift_boost_time = 0.0
	drift_boost_strength = 0.0
	drift_boost_active = false

func update_drift_reward(delta: float, handbrake: bool, hit_wall: bool) -> void:
	if not driving_enabled or not on_asphalt or not is_on_floor() or signed_speed < float(config["drift_min_speed_mps"]) or throttle_input < 0 or hit_wall or turbo_active:
		clear_drift_reward()
		return
	var degrees := absf(rad_to_deg(slip_angle))
	drift_quality = 0.0
	if handbrake:
		drift_exit_time = 0.0
		drift_settle_time = 0.0
		# Reward speed plus a controlled slip band, not spins or straight braking.
		if degrees >= 12.0 and degrees <= 55.0 and absf(steering) > 0.15:
			var angle_quality := clampf((degrees - 10.0) / 18.0, 0, 1) * clampf((65.0 - degrees) / 22.0, 0, 1)
			var speed_quality := clampf((signed_speed - 9.0) / 16.0, 0.25, 1.0)
			drift_quality = angle_quality * speed_quality
			drift_tracking = true
			drift_valid_time += delta
			drift_charge = minf(1.0, drift_charge + drift_quality * delta / float(config["drift_charge_time_s"]))
		elif drift_tracking:
			drift_charge = maxf(0.0, drift_charge - delta * 0.25)
	elif drift_tracking:
		drift_exit_time += delta
		drift_settle_time = drift_settle_time + delta if degrees < 8.0 else 0.0
		if drift_settle_time >= 0.1:
			var earned := drift_charge if drift_charge >= float(config["drift_min_charge"]) and drift_valid_time >= float(config["drift_min_duration_s"]) else 0.0
			clear_drift_reward()
			if earned > 0 and throttle_input > 0:
				drift_boost_strength = earned
				drift_boost_time = float(config["drift_bonus_duration_s"])
				drift_boost_active = true
				drift_rewards += 1
		elif drift_exit_time > float(config["drift_exit_timeout_s"]):
			clear_drift_reward()

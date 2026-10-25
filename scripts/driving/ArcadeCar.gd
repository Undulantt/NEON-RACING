extends CharacterBody3D

signal recovered(reason: String)
const VisualBuilder = preload("res://scripts/driving/CarVisual.gd")
var config: Dictionary
var driving_enabled := true
var external_control := false
var command_throttle := 0.0
var command_steer := 0.0
var command_handbrake := false
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
var world_bounds := Rect2()
var visuals: Dictionary
var visual_root: Node3D

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

func configure(map_data: Dictionary, environment: Dictionary) -> void:
	road_segments = map_data["roads"]
	var bounds: Array = environment["bounds_xz"]
	world_bounds = Rect2(bounds[0], bounds[1], bounds[2] - bounds[0], bounds[3] - bounds[1])
	var p: Array = environment["spawn"]["position_xz"]
	var f: Array = environment["spawn"]["forward_xz"]
	var yaw := atan2(-float(f[0]), -float(f[1]))
	spawn_transform = Transform3D(Basis(Vector3.UP, yaw), Vector3(p[0], 0.67, p[1]))
	safe_transform = spawn_transform
	global_transform = spawn_transform

func set_controls(throttle: float, steer: float, handbrake: bool = false) -> void:
	command_throttle = clampf(throttle, -1, 1)
	command_steer = clampf(steer, -1, 1)
	command_handbrake = handbrake

func road_hit(p: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(Vector3(p.x, 1.8, p.z), Vector3(p.x, -0.5, p.z), 1)
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
	for road in road_segments:
		var a := Vector2(road["points_xz"][0][0], road["points_xz"][0][1])
		var b := Vector2(road["points_xz"][-1][0], road["points_xz"][-1][1])
		var closest := Geometry2D.get_closest_point_to_segment(p, a, b)
		var distance := p.distance_squared_to(closest)
		if distance < best:
			best = distance
			var direction := Vector3(b.x - a.x, 0, b.y - a.y).normalized()
			if not road["oneway"] and direction.dot(-global_basis.z) < 0:
				direction = -direction
			candidate = Transform3D(Basis(Vector3.UP, atan2(-direction.x, -direction.z)), Vector3(closest.x, 0.67, closest.y))
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
	velocity = Vector3.ZERO
	speed_mps = 0.0
	signed_speed = 0.0
	steering = 0.0
	recovery_count += 1
	reset_physics_interpolation()
	recovered.emit(reason)

func _physics_process(delta: float) -> void:
	if road_segments.is_empty():
		return
	if driving_enabled and Input.is_action_just_pressed("recover") and not external_control:
		recover()
	var throttle := command_throttle if external_control else Input.get_axis("brake_reverse", "accelerate")
	var steer := command_steer if external_control else Input.get_axis("steer_left", "steer_right")
	var handbrake := command_handbrake if external_control else Input.is_action_pressed("handbrake")
	if not driving_enabled:
		throttle = 0
		steer = 0
		handbrake = true
	on_asphalt = road_hit(global_position)
	var forward := -global_basis.z
	var horizontal := Vector3(velocity.x, 0, velocity.z)
	var longitudinal := horizontal.dot(forward)
	var lateral := horizontal - forward * longitudinal
	var max_speed: float = config["max_forward_speed_mps"] if on_asphalt else config["offroad_speed_mps"]
	if throttle > 0:
		longitudinal = move_toward(longitudinal, max_speed, float(config["braking_mps2"] if longitudinal < -0.1 else config["acceleration_mps2"]) * throttle * delta)
	elif throttle < 0:
		longitudinal = move_toward(longitudinal, -float(config["max_reverse_speed_mps"]), float(config["braking_mps2"] if longitudinal > 0.1 else config["acceleration_mps2"]) * -throttle * delta)
	else:
		longitudinal = move_toward(longitudinal, 0, float(config["coast_deceleration_mps2"]) * delta)
	if handbrake:
		longitudinal = move_toward(longitudinal, 0, 12.0 * delta)
	if absf(longitudinal) > max_speed:
		longitudinal = move_toward(longitudinal, signf(longitudinal) * max_speed, 12.0 * delta)
	steering = move_toward(steering, steer, 5.5 * delta)
	var reduction := lerpf(1.0, 1.0 - float(config["steering_reduction_at_high_speed"]), clampf(absf(longitudinal) / float(config["max_forward_speed_mps"]), 0, 1))
	var angle := steering * float(config["max_steer_radians"]) * reduction * float(config["steering_sensitivity"])
	var yaw_delta := -clampf(longitudinal / float(config["wheelbase_m"]) * tan(angle), -1.7, 1.7) * delta
	var proposed := Transform3D(Basis(Vector3.UP, rotation.y + yaw_delta), global_position)
	if absf(yaw_delta) > 0.00001 and clear_of_obstacles(proposed):
		rotation.y += yaw_delta
	var grip: float = config["lateral_grip_per_second"]
	if handbrake:
		grip *= float(config["handbrake_grip_multiplier"])
	horizontal = (forward * longitudinal + lateral).lerp(-global_basis.z * longitudinal, 1.0 - exp(-grip * delta))
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	velocity.y = -2.0 if is_on_floor() else velocity.y - float(config["gravity_mps2"]) * delta
	move_and_slide()
	for i in range(get_slide_collision_count()):
		var collision := get_slide_collision(i)
		if absf(collision.get_normal().y) < 0.5:
			wall_contacts += 1
	var actual := get_real_velocity()
	speed_mps = Vector2(actual.x, actual.z).length()
	signed_speed = Vector3(velocity.x, 0, velocity.z).dot(-global_basis.z)
	safety_timer += delta
	if safety_timer >= float(config["recovery_interval_s"]):
		safety_timer = 0.0
		update_safe_position()
	if global_position.y < -4 or not world_bounds.grow(5).has_point(Vector2(global_position.x, global_position.z)) or global_basis.y.dot(Vector3.UP) < 0.5:
		recover("fuera de límites")
	visual_root.rotation.z = lerpf(visual_root.rotation.z, steering * minf(speed_mps / 32, 1) * 0.05, 8 * delta)
	for i in range(visuals["pivots"].size()):
		if i < 2:
			visuals["pivots"][i].rotation.y = -angle
		visuals["wheels"][i].rotate_object_local(Vector3.UP, -signed_speed * delta / 0.34)
	visuals["brake_material"].emission_energy_multiplier = 2.5 if throttle < 0 or handbrake else 0.3

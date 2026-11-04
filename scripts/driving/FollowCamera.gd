extends Node3D

var car: CharacterBody3D
var arm: SpringArm3D
var camera: Camera3D
var initialized := false
var close_view := false
const BurstPresentation = preload("res://scripts/driving/BurstPresentation.gd")
var burst_effect_strength := 1.0
var burst_camera_blend := 0.0
var turbo_blend := 0.0

func _ready() -> void:
	arm = SpringArm3D.new()
	arm.spring_length = 7.5
	arm.margin = 0.3
	arm.collision_mask = 15
	var shape := SphereShape3D.new()
	shape.radius = 0.25
	arm.shape = shape
	arm.rotation.x = deg_to_rad(-14)
	add_child(arm)
	camera = Camera3D.new()
	camera.fov = 70
	camera.near = 0.15
	camera.far = 4000
	arm.add_child(camera)
	camera.current = true

func attach(target: CharacterBody3D) -> void:
	car = target
	arm.add_excluded_object(car.get_rid())
	arm.spring_length = float(car.config["camera_distance_m"])
	car.recovered.connect(_on_recovered)
	snap()

func snap() -> void:
	if car == null:
		return
	global_position = car.global_position + Vector3.UP * 1.25
	rotation.y = car.rotation.y
	turbo_blend = 0.0
	burst_camera_blend = 0.0
	camera.fov = 70.0
	camera.h_offset = 0.0
	camera.v_offset = 0.0
	initialized = true

func _on_recovered(_reason: String) -> void:
	snap()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("driving_camera") and not event.is_echo() and car != null and car.driving_enabled:
		close_view = not close_view

func _physics_process(delta: float) -> void:
	if car == null:
		return
	# Position follows exactly to prevent lagging into geometry; heading is smoothed.
	global_position = car.global_position + Vector3.UP * 1.25
	rotation.y = lerp_angle(rotation.y, car.rotation.y, 1.0 - exp(-7.0 * delta))
	var mix := 1.0 - exp(-5.0 * delta)
	turbo_blend = lerpf(turbo_blend, 1.0 if car.turbo_active else 0.0, mix)
	var speed_ratio := clampf(car.speed_mps / float(car.config["max_forward_speed_mps"]), 0, 1)
	var target_fov := lerpf(70.0, float(car.config["camera_speed_fov"]), speed_ratio)
	target_fov = lerpf(target_fov, float(car.config["camera_turbo_fov"]), turbo_blend)
	if car.drift_boost_active and not car.turbo_active:
		target_fov += 3.0 * car.drift_boost_strength
	var settings := BurstPresentation.settings()
	var progress := BurstPresentation.preparation_progress(car)
	var preparing: bool = car.abilities.burst_state == 1
	var bursting: bool = car.abilities.burst_state == 2
	var burst_target := target_fov
	if preparing:
		burst_target = lerpf(target_fov, float(settings["camera_preparation_fov"]), smoothstep(0, 1, progress))
	elif bursting:
		var entry_progress := clampf(car.abilities.burst_time / 2.0, 0, 1)
		burst_target = lerpf(float(settings["camera_preparation_fov"]), float(settings["camera_burst_fov"]), smoothstep(0, 1, entry_progress))
		burst_target += float(settings["camera_bonus_fov"]) * car.abilities.burst_bonus / float(car.config["burst_max_bonus"])
	var transition := 1.0 - exp(-float(settings["camera_transition_per_second"]) * delta)
	burst_camera_blend = lerpf(burst_camera_blend, burst_effect_strength if preparing or bursting else 0.0, transition)
	target_fov = lerpf(target_fov, maxf(target_fov, burst_target), clampf(burst_camera_blend, 0, 1))
	camera.fov = lerpf(camera.fov, target_fov, transition if preparing or bursting or burst_camera_blend > 0.01 else mix)
	arm.spring_length = lerpf(arm.spring_length, (5.3 if close_view else float(car.config["camera_distance_m"])) + turbo_blend * 1.1, mix)
	arm.rotation.x = lerpf(arm.rotation.x, deg_to_rad(-10 if close_view else -14), mix)
	camera.h_offset = lerpf(camera.h_offset, clampf(car.slip_angle, -0.6, 0.6) * 0.4, mix)

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
var speed_feedback: Node
var experiment_panel: CanvasLayer
var experimental_far_view := false
var sf1_pivot_offset := 1.25
var sf1_lateral_offset := 0.0
var sf1_handoff_s := 0.0
var sf1_previous_mode := true
var sf1_camera_us := 0
var sf1_actual_height := 0.0
var sf1_collision_retracted := false

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
	speed_feedback = preload("res://scripts/feedback/SpeedFeedbackController.gd").new()
	add_child(speed_feedback)
	speed_feedback.configure(car)
	sf1_previous_mode = speed_feedback.settings["experimental_enabled"]
	speed_feedback.settings_changed.connect(_on_sf1_settings)
	experiment_panel = preload("res://scripts/ui/SpeedFeelPanel.gd").new()
	add_child(experiment_panel)
	experiment_panel.configure(self)
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
	sf1_pivot_offset = 1.25
	sf1_lateral_offset = 0.0
	sf1_handoff_s = 0.0
	if speed_feedback != null:
		speed_feedback.reset_telemetry()
		speed_feedback.sample(1.0/60.0)
		if speed_feedback.settings["experimental_enabled"]: _experimental_physics_process(1.0/60.0,true)

func _on_recovered(_reason: String) -> void:
	snap()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("driving_camera") and not event.is_echo() and car != null and car.driving_enabled:
		if speed_feedback != null and speed_feedback.settings["experimental_enabled"]: experimental_far_view = not experimental_far_view
		else: close_view = not close_view

func _original_physics_process(delta: float) -> void:
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

func _on_sf1_settings() -> void:
	var enabled: bool = speed_feedback.settings["experimental_enabled"]
	if enabled != sf1_previous_mode:
		sf1_handoff_s = 0.7
		sf1_previous_mode = enabled

func _physics_process(delta: float) -> void:
	if car == null: return
	var start := Time.get_ticks_usec()
	speed_feedback.sample(delta)
	if speed_feedback.settings["experimental_enabled"]:
		_experimental_physics_process(delta)
	else:
		arm.shape.radius = 0.25
		arm.margin = 0.3
		_original_physics_process(delta)
		if sf1_handoff_s > 0:
			sf1_pivot_offset = lerpf(sf1_pivot_offset,1.25,1.0-exp(-8.0*delta))
			sf1_lateral_offset = lerpf(sf1_lateral_offset,0,1.0-exp(-8.0*delta))
			global_position = car.global_position+Vector3.UP*sf1_pivot_offset+car.global_basis.x*sf1_lateral_offset
		else:
			sf1_pivot_offset = 1.25
			sf1_lateral_offset = 0.0
	sf1_handoff_s = maxf(0,sf1_handoff_s-delta)
	sf1_camera_us = Time.get_ticks_usec()-start

func _experimental_physics_process(delta: float, instant := false) -> void:
	var s: Dictionary = speed_feedback.settings
	var fov_before := camera.fov
	var mix := 1.0 if instant else 1.0-exp(-float(s["spatial_response_per_s"])*delta)
	var fov_mix := 1.0 if instant else 1.0-exp(-speed_feedback.fov_response_rate*delta)
	if not s["position_enabled"] or not s["fov_enabled"]:
		# Retain the previous component when only testing the other one.
		_original_physics_process(delta)
	if s["fov_enabled"]:
		camera.fov = lerpf(fov_before,speed_feedback.fov_target,fov_mix)
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	if not s["position_enabled"]:
		sf1_pivot_offset = lerpf(sf1_pivot_offset,1.25,mix)
		sf1_lateral_offset = lerpf(sf1_lateral_offset,0,mix)
		global_position = car.global_position+Vector3.UP*sf1_pivot_offset+car.global_basis.x*sf1_lateral_offset
		_update_sf1_collision()
		return
	var accel := clampf(speed_feedback.acceleration_mps2/8.0,-1,1) if s["motion_enabled"] else 0.0
	var brake := clampf(car.brake_input,0,1) if s["motion_enabled"] else 0.0
	var distance := float(s["distance_m"])+(1.3 if experimental_far_view else 0.0)
	if s["motion_enabled"]:
		distance += maxf(0,accel)*float(s["acceleration_pull_m"])-maxf(brake,maxf(0,-accel))*float(s["brake_push_m"])
		distance += maxf(speed_feedback.turbo_intensity*float(s["turbo_pull_m"]),speed_feedback.burst_intensity*float(s["burst_pull_m"]))
	distance = clampf(distance,4.5,9.0)
	var pitch := deg_to_rad(float(s["pitch_deg"]))
	var length := distance/maxf(0.5,cos(pitch))
	arm.spring_length = lerpf(arm.spring_length,length,mix)
	arm.rotation.x = lerpf(arm.rotation.x,-pitch,mix)
	var height := float(s["height_m"])+accel*0.04 if s["motion_enabled"] else float(s["height_m"])
	var half_height: float = car.collision_shape.size.y*0.5+car.safe_margin
	var rise := -sin(arm.rotation.x)*arm.spring_length
	var roof_clearance := maxf(1.2,0.91*float(car.config["vehicle_scale"])+arm.shape.radius+0.08)
	var minimum_pivot := roof_clearance if arm.get_hit_length()<2.6 and not instant else 0.85
	var desired_pivot := maxf(minimum_pivot,height-half_height-rise)
	# Raise promptly when squeezed against a wall, above the car's roof.
	sf1_pivot_offset = maxf(minimum_pivot,lerpf(sf1_pivot_offset,desired_pivot,mix))
	var slip: float = clampf(car.slip_angle,-0.6,0.6) if s["drift_enabled"] else 0.0
	sf1_lateral_offset = lerpf(sf1_lateral_offset,-slip/0.6*float(s["drift_shift_m"]),mix)
	global_position = car.global_position+Vector3.UP*sf1_pivot_offset+car.global_basis.x*sf1_lateral_offset
	var yaw_offset := clampf(slip*0.12,-deg_to_rad(float(s["drift_yaw_deg"])),deg_to_rad(float(s["drift_yaw_deg"])))
	rotation.y = lerp_angle(rotation.y,car.rotation.y-yaw_offset,1.0 if instant else 1.0-exp(-float(s["heading_response_per_s"])*delta))
	camera.h_offset = lerpf(camera.h_offset,0.0,mix)
	camera.v_offset = lerpf(camera.v_offset,0.0,mix)
	_update_sf1_collision()
	sf1_actual_height = camera.global_position.y-(car.global_position.y-half_height)
	sf1_collision_retracted = arm.get_hit_length()<arm.spring_length-0.25

func _update_sf1_collision() -> void:
	# Protect the near-plane corners as FOV/aspect grow; offsets also fit in the cast.
	var view := get_viewport().get_visible_rect().size
	var aspect := view.x/maxf(1,view.y)
	var radius := camera.near*tan(deg_to_rad(camera.fov)*0.5)*sqrt(1+aspect*aspect)+0.07+absf(camera.h_offset)
	arm.shape.radius = clampf(radius,0.32,1.2)
	arm.margin = 0.22

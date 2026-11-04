extends SceneTree

const Presentation = preload("res://scripts/driving/BurstPresentation.gd")
class Fixture extends Node3D:
	var follow_camera: Node3D

var car: CharacterBody3D
var hud: CanvasLayer
var level: Node3D
var failures: Array[String] = []
var metrics := {}

func _initialize() -> void:
	run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func step(frames: int, throttle: float = 1.0) -> void:
	car.set_controls(throttle, 0)
	for i in range(frames):
		await car.physics_updated
	await process_frame

func run() -> void:
	level = Fixture.new()
	root.add_child(level)
	var ground := StaticBody3D.new()
	ground.collision_layer = 1
	ground.position.y = -0.5
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2000, 1, 20000)
	shape.shape = box
	ground.add_child(shape)
	level.add_child(ground)
	car = preload("res://scenes/cars/PlayerCar.tscn").instantiate()
	level.add_child(car)
	car.external_control = true
	car.configure({"roads": [{"points_xz": [[0, 9000], [0, -9000]], "oneway": false, "street_name": "VFX PHYSICAL FIXTURE"}]}, {"bounds_xz": [-900,-9500,900,9500], "spawn": {"position_xz": [0,0], "forward_xz": [0,-1]}})
	level.follow_camera = preload("res://scripts/driving/FollowCamera.gd").new()
	level.add_child(level.follow_camera)
	level.follow_camera.attach(car)
	hud = preload("res://scripts/ui/DrivingHUD.gd").new()
	level.add_child(hud)
	hud.attach(car, level)
	await step(5, 0)
	for id in ["VECTOR", "COMET", "APEX"]:
		car.velocity = Vector3.ZERO
		car.apply_vehicle_profile(id)
		car.abilities.burst_state = 1
		for remaining in [2.4, 1.4, 0.4]:
			car.abilities.arming_time = float(car.config["burst_arming_time_s"]) - remaining
			hud.update_burst_presentation(0, Vector2(1280,720))
			check(hud.countdown_label.visible and hud.countdown_label.text == str(ceili(remaining)), id + " correct 3/2/1 countdown")
		car.abilities.reset("test")
		check(Presentation.countdown(car) == 0, "Countdown disappears when preparation is cancelled")
	car.apply_vehicle_profile("VECTOR")
	hud.speed_effects.retro_profile = true
	car.velocity = Vector3(0, 0, -float(car.config["max_forward_speed_mps"]))
	await step(120)
	var pre_fov: float = level.follow_camera.camera.fov
	check(car.abilities.burst_state == 1 and hud.countdown_label.visible, "Actual physics shows preparation countdown")
	check(pre_fov > 79 and pre_fov < 87, "FOV slowly anticipates BURST")
	var fov_before: float = pre_fov
	var biggest_fov_step := 0.0
	for i in range(200):
		await step(1)
		biggest_fov_step = maxf(biggest_fov_step, absf(level.follow_camera.camera.fov - fov_before))
		fov_before = level.follow_camera.camera.fov
	check(car.abilities.burst_state == 2 and hud.ground_flames.marks.size() > 0, "Physical BURST leaves grounded flames")
	check(hud.ground_flames.marks.size() <= 128 and hud.ground_flames.instances.instance_count == 128, "Fixed instance budget")
	check(hud.speed_effects.intensity > 1.9, "BURST doubles peak turbo streak intensity")
	check(level.follow_camera.camera.fov > 89 and biggest_fov_step < 0.7, "FOV grows smoothly during BURST")
	for mark in hud.ground_flames.marks:
		check(absf(mark["position"].y - 0.025) < 0.01 and mark["basis"].y.dot(Vector3.UP) > 0.99, "Flames are anchored to actual ground")
	var previous_end := {}
	var track_x := {}
	for mark in hud.ground_flames.marks:
		var track: int = mark["track"]
		if previous_end.has(track):
			check(Vector3(mark["start"]).distance_to(previous_end[track]) < 0.001, "Each tire track is continuous without stamp gaps")
		previous_end[track] = mark["end"]
		track_x[track] = mark["position"].x
	check(track_x.size() == 2 and absf(float(track_x[1])-float(track_x[0])) > 1.4, "Two separate tracks originate at the real rear wheels")
	check(hud.ground_flames.instances.mesh.get_surface_count() == 1, "Both tracks share one batched mesh/material")
	var effects: Control = hud.speed_effects
	var burst_lines: int = effects.retro_segments(Vector2(1280,720)).size()
	var saved_intensity: float = effects.intensity
	var saved_blend: float = effects.burst_blend
	effects.intensity = 1.0
	effects.burst_blend = 0.0
	var turbo_lines: int = effects.retro_segments(Vector2(1280,720)).size()
	effects.intensity = saved_intensity
	effects.burst_blend = saved_blend
	check(burst_lines > turbo_lines * 2 and burst_lines >= 15, "BURST has substantially denser visible streaks")
	metrics = {"preparation_fov":pre_fov, "burst_fov":level.follow_camera.camera.fov, "maximum_fov_step_degrees":biggest_fov_step, "flame_instances":hud.ground_flames.marks.size(), "ground_ray_queries":hud.ground_flames.ray_queries, "burst_streaks":burst_lines, "turbo_streaks":turbo_lines}
	var first_direction: Vector3 = hud.ground_flames.marks[-1]["basis"].z
	for i in range(18):
		car.set_controls(1, 0.35)
		await car.physics_updated
	await process_frame
	var last_direction: Vector3 = hud.ground_flames.marks[-1]["basis"].z
	check(first_direction.dot(last_direction) < 0.999, "Fire tracks follow curved wheel paths")
	var frozen_clock: float = hud.ground_flames.clock
	paused = true
	for i in range(5):
		await process_frame
	check(hud.ground_flames.clock == frozen_clock, "Pause freezes flames")
	paused = false
	effects.effect_strength = 0
	await step(3)
	check(hud.ground_flames.marks.is_empty(), "Effects-off clears flames")
	effects.effect_strength = 1
	await step(10)
	check(hud.ground_flames.marks.size() > 0, "Re-enabling effects restores flames")
	await step(130, 0)
	check(car.abilities.burst_state != 2 and not hud.countdown_label.visible and hud.ground_flames.marks.is_empty(), "Cancelling BURST clears countdown and fades old flames")
	check(level.follow_camera.camera.fov < 81, "Exit restores FOV smoothly")
	car.recover()
	check(hud.ground_flames.marks.is_empty(), "Recovery clears ground flames")
	# Cross-slope support fit on a real inclined collision surface.
	ground.rotation.z = 0.08
	car.velocity = Vector3.ZERO
	car.global_position = Vector3(0,1,0)
	car.reset_surface_motion()
	await step(40,0)
	hud.ground_flames.sample_wheels()
	car.position.z -= 1.0
	hud.ground_flames.sample_wheels()
	var mark: Dictionary = hud.ground_flames.marks[-1]
	check(mark["basis"].y.dot(Vector3.UP.rotated(Vector3.FORWARD, -0.08)) > 0.99, "Ground flames follow an inclined surface")
	hud.ground_flames.clock = 3600.0
	hud.ground_flames.sample_wheels()
	car.position.z -= 1.0
	hud.ground_flames.sample_wheels()
	await step(2,0)
	check(hud.ground_flames.instances.get_instance_custom_data(0).r < 0.2, "Normalized GPU ages remain precise after a long session")
	var report := {"passed":failures.is_empty(), "failures":failures, "metrics":metrics}
	FileAccess.open("res://docs/burst_vfx_validation.json", FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("BURST_VFX_REPORT ",JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)

extends SceneTree
# Synthetic telemetry cases are intentionally separate from the physical replay.
const Profiles = preload("res://scripts/driving/VehicleProfiles.gd")
var car: CharacterBody3D
var rig: Node3D
var legacy: Node3D
var failures: Array[String] = []
var checks := 0
var metrics := {}

func _initialize() -> void: run.call_deferred()
func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		push_error(message)
func ticks(n: int) -> void:
	for i in range(n): await physics_frame
func solid(parent: Node, at: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = at
	body.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	parent.add_child(body)
	return body
func telemetry(speed: float, turbo: bool, progress: float) -> void:
	car.forward_plane_speed = speed
	car.speed_mps = speed
	car.abilities.turbo_active = turbo
	car.abilities.burst_state = 2 if progress >= 0 else 0
	car.abilities.burst_bonus = maxf(0,progress)*float(car.config["burst_max_bonus"])
func settle() -> void:
	for i in range(300): rig._physics_process(1.0/60)
func run() -> void:
	var level := Node3D.new()
	root.add_child(level)
	solid(level,Vector3(0,-0.5,0),Vector3(2000,1,20000))
	car = preload("res://scenes/cars/PlayerCar.tscn").instantiate()
	level.add_child(car)
	car.external_control = true
	car.configure({"roads":[{"points_xz":[[0,9000],[0,-9000]],"oneway":false,"street_name":"TEST FIXTURE, NOT MAP GEOMETRY"}]},{"bounds_xz":[-900,-9500,900,9500],"spawn":{"position_xz":[0,0],"forward_xz":[0,-1]}})
	rig = preload("res://scripts/driving/FollowCamera.gd").new()
	level.add_child(rig)
	rig.attach(car)
	rig.close_view = true
	rig.speed_feedback.settings_path = "res://tests/.sf1_settings.cfg"
	rig.speed_feedback.reset_experiment()
	var old_script := GDScript.new()
	old_script.source_code = FileAccess.get_file_as_string("res://docs/sf1_baseline/FollowCamera.gd.txt")
	check(old_script.reload() == OK,"Original camera snapshot compiles")
	legacy = old_script.new()
	level.add_child(legacy)
	legacy.attach(car)
	legacy.close_view = true
	legacy.set_physics_process(false)
	await ticks(10)
	car.set_physics_process(false)
	rig.set_physics_process(false)
	for id in Profiles.IDS:
		car.apply_vehicle_profile(id)
		rig.speed_feedback.reset_experiment()
		rig.speed_feedback.set_setting("turbo_fov_percent",0)
		var cap: float = car.base_speed_cap
		var values := []
		for state in [[0.0,false,-1.0,70.0],[cap,false,-1.0,75.0],[cap,true,-1.0,78.0],[cap,false,0.0,75.84],[cap,false,0.5,78.92],[cap,true,1.0,82.0]]:
			telemetry(state[0],state[1],state[2])
			settle()
			values.append(rig.camera.fov)
			check(absf(rig.camera.fov-state[3])<0.02,id+" bounded FOV at "+str(state))
		check(rig.camera.keep_aspect == Camera3D.KEEP_HEIGHT,id+" FOV remains vertical")
		var projection: Projection = rig.camera.get_camera_projection()
		check(absf(rad_to_deg(2*atan(1/projection.y.y))-rig.camera.fov)<0.01,id+" projection confirms vertical FOV")
		var intensity: float = rig.speed_feedback.burst_intensity
		car.abilities.tick(1.0/60,0,0,false,false,cap,true,true,true,1)
		rig._physics_process(1.0/60)
		check(car.abilities.burst_bonus == 0 and car.abilities.burst_state != 2,id+" physical BURST cancels immediately on release")
		check(rig.speed_feedback.burst_intensity>0 and rig.speed_feedback.burst_intensity<intensity,id+" presentation exits BURST smoothly")
		# A is compared numerically with the actual pre-SF.1 script, not a reimplementation.
		rig.speed_feedback.set_experimental(false)
		rig.snap()
		legacy.snap()
		rig.arm.spring_length = 7.5
		legacy.arm.spring_length = 7.5
		rig.arm.rotation.x = deg_to_rad(-14)
		legacy.arm.rotation.x = deg_to_rad(-14)
		var parity := true
		for frame in range(420):
			telemetry(cap*minf(float(frame)/100,1),frame>100 and frame<200,float(frame-250)/170 if frame>=250 else -1.0)
			car.slip_angle = 0.3*sin(float(frame)/40)
			rig._physics_process(1.0/60)
			legacy._physics_process(1.0/60)
			parity = parity and absf(rig.camera.fov-legacy.camera.fov)<0.00001 and rig.global_position.is_equal_approx(legacy.global_position) and absf(rig.arm.spring_length-legacy.arm.spring_length)<0.00001 and absf(rig.arm.rotation.x-legacy.arm.rotation.x)<0.00001 and absf(rig.camera.h_offset-legacy.camera.h_offset)<0.00001
		check(parity,id+" original A matches baseline through acceleration/TURBO/BURST/drift")
		metrics[id] = {"fov_samples":values,"original_parity":parity}
	# Save/load, invalid values and live widgets.
	var feedback: Node = rig.speed_feedback
	var responses := []
	for hz in [30,60,120]:
		feedback.reset_experiment()
		feedback.reset_telemetry()
		telemetry(car.base_speed_cap,true,0.6)
		for i in range(hz*2): feedback.sample(1.0/hz)
		responses.append(feedback.fov_target)
	check(absf(responses[0]-responses[2])<0.001,"Time-based telemetry response agrees at 30/60/120 Hz")
	metrics["response_by_hz"]=responses
	feedback.reset_experiment()
	feedback.set_setting("distance_m",6.1)
	check(feedback.save_trial(),"Trial settings save separately from physics")
	feedback.set_setting("distance_m",5.0)
	check(feedback.load_trial() and is_equal_approx(feedback.settings["distance_m"],6.1),"Trial settings restore")
	check(not feedback.set_setting("height_m",NAN) and not feedback.set_setting("turbo_active",true),"Invalid values and physics settings rejected")
	feedback.reset_experiment()
	rig.experiment_panel.sliders["distance_m"].value = 5.8
	check(is_equal_approx(feedback.settings["distance_m"],5.8),"Live slider updates presentation")
	rig.experiment_panel.buttons["original"].pressed.emit()
	check(not feedback.settings["experimental_enabled"],"Restore original button selects A")
	rig.experiment_panel.buttons["defaults"].pressed.emit()
	check(feedback.settings == feedback.defaults(),"Reset B restores experimental defaults")
	var focus_free := true
	for widget in rig.experiment_panel.sliders.values()+rig.experiment_panel.toggles.values()+rig.experiment_panel.buttons.values():
		focus_free = focus_free and widget.focus_mode == Control.FOCUS_NONE
	check(focus_free,"Panel does not capture driving keyboard focus")
	root.get_node("GameFlow").current_state = &"free_drive"
	rig.camera.current = true
	var key := InputEventKey.new()
	key.ctrl_pressed=true;key.alt_pressed=true;key.keycode=KEY_P;key.pressed=true
	rig.experiment_panel._input(key)
	check(rig.experiment_panel.open_requested,"Panel shortcut works during driving")
	paused=true
	check(not rig.experiment_panel.can_use(),"Pause suppresses SF.1 panel")
	paused=false
	# Cast clearance against a close rear wall at the widest FOV.
	car.slip_angle=0
	car.global_position=Vector3(0,0.49,0)
	car.rotation=Vector3.ZERO
	telemetry(car.base_speed_cap,false,1)
	settle()
	rig.set_physics_process(true)
	await ticks(30)
	check(absf(rig.camera.global_position.y-1.8)<0.08,"Experimental eye height settles at 1.8 m on flat ground")
	check(absf(rig.camera.global_position.z-5.75)<0.08,"BURST camera distance reflects gradual pullback")
	var wall := solid(level,Vector3(0,2,3),Vector3(8,4,0.3))
	await ticks(60)
	check(rig.arm.get_hit_length()<3.0,"SpringArm retracts before rear wall")
	check(rig.camera.global_position.z+rig.arm.shape.radius<2.85,"Camera clearance sphere does not penetrate wall")
	check(rig.camera.global_position.y-rig.arm.shape.radius>car.global_position.y+0.728,"Retracted camera stays above own vehicle")
	wall.queue_free()
	await ticks(10)
	root.size=Vector2i(2520,1080)
	await ticks(20)
	var view := root.get_visible_rect().size
	var corner: float = rig.camera.near*tan(deg_to_rad(rig.camera.fov)/2)*sqrt(1+pow(view.x/view.y,2))
	check(rig.arm.shape.radius>corner,"Collision sphere covers near-plane corners at ultrawide aspect")
	var bank := solid(level,Vector3(0,0.6,4.5),Vector3(8,1.2,2))
	await ticks(30)
	check(rig.camera.global_position.z+rig.arm.shape.radius<3.5 or rig.camera.global_position.y-rig.arm.shape.radius>1.2,"Camera clears raised terrain fixture")
	bank.queue_free()
	root.size=Vector2i(1280,720)
	await ticks(10)
	# Deterministic physical replay: same profile, spawn and controls in A and B.
	for id in Profiles.IDS:
		var runs := []
		for enabled in [false,true]:
			feedback.set_experimental(enabled)
			car.apply_vehicle_profile(id)
			car.global_transform=car.spawn_transform
			car.velocity=Vector3.ZERO
			car.reset_surface_motion()
			car.abilities.configure(car.config)
			car.powertrain.reset()
			car.set_controls(0,0)
			car.set_physics_process(true)
			await ticks(20)
			var trace := []
			for frame in range(1800):
				car.set_controls(1 if frame<1600 else -1,0,false,frame>=500 and frame<600)
				await car.physics_updated
				trace.append([car.position.x,car.position.y,car.position.z,car.speed_mps,car.abilities.burst_state,car.abilities.burst_bonus])
			runs.append(trace)
			car.set_physics_process(false)
		var max_difference := 0.0
		for i in range(runs[0].size()):
			for column in range(6): max_difference=maxf(max_difference,absf(float(runs[0][i][column])-float(runs[1][i][column])))
		check(max_difference<0.0001,id+" A/B physical replay is identical")
		metrics[id]["physical_replay_max_difference"]=max_difference
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://docs/sf1_baseline/manifest.json"))
	for path in manifest["sha256"]:
		if path.ends_with("FollowCamera.gd"): continue
		check(FileAccess.get_sha256("res://"+path)==manifest["sha256"][path],"Preserved bytes: "+path)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(feedback.settings_path))
	var report := {"passed":failures.is_empty(),"checks":checks,"failures":failures,"metrics":metrics,"physics_replay":"1800 fixed 60 Hz steps per mode/profile: accelerate, TURBO, BURST and braking; synthetic flat test fixture, not La Paz map"}
	FileAccess.open("res://docs/sf1_validation.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("SF1_REPORT ",JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)

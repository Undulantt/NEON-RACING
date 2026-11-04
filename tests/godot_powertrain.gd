extends SceneTree

const Profiles = preload("res://scripts/driving/VehicleProfiles.gd")
const Transmission = preload("res://scripts/driving/AutomaticTransmission.gd")
class Fixture extends Node3D:
	var follow_camera: Node3D
var car: CharacterBody3D
var hud: CanvasLayer
var failures: Array[String] = []
var metrics := {}
var current_shift: Dictionary = {}
var shifts: Array = []

func _initialize() -> void:
	run.call_deferred()
func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)
func step(frames: int, throttle: float) -> void:
	car.set_controls(throttle,0)
	for i in range(frames):
		await car.physics_updated
		if not current_shift.is_empty():
			current_shift["minimum_rpm"] = minf(current_shift["minimum_rpm"],car.powertrain.rpm)
			current_shift["maximum_rpm"] = maxf(current_shift["maximum_rpm"],car.powertrain.rpm)
			if car.powertrain.shift_remaining <= 0:
				shifts.append(current_shift)
				current_shift = {}
func on_shift(previous: int, next: int) -> void:
	if previous>0 and next>0:
		current_shift = {"from":previous,"to":next,"before_rpm":car.powertrain.rpm,"minimum_rpm":car.powertrain.rpm,"maximum_rpm":car.powertrain.rpm,"speed_kmh":car.signed_speed*3.6}

func run() -> void:
	for id in Profiles.IDS:
		var config: Dictionary = Profiles.load_profile(id)["config"]
		var end_states := []
		for hz in [30,60,120]:
			var model := Transmission.new()
			model.configure(config)
			var top: float = float(config["max_forward_speed_mps"])*(1.0+float(config["burst_max_bonus"]))
			for i in range(40*hz):
				model.update(1.0/hz,minf(float(i)/hz/30,1)*top,1,0,true,true)
			check(model.gear==7 and model.upshifts==6,id+" reaches all seven gears without hunting")
			check(absf(model.rpm-7600)<1,id+" top-gear RPM tracks profile BURST cap")
			end_states.append({"hz":hz,"gear":model.gear,"rpm":model.rpm,"upshifts":model.upshifts})
			for i in range(hz*15):
				model.update(1.0/hz,top*(1-float(i)/(hz*15)),0,1,true,true)
			check(model.downshifts>0,id+" reduces gears during braking")
			model.reset()
			for i in range(hz*5):
				model.update(1.0/hz,0,1,0,true,true)
			check(model.gear==1 and model.upshifts==6 and model.rpm<4000,id+" launch revs cannot shift while stationary")
		var hunting := Transmission.new()
		hunting.configure(config)
		var threshold_speed := float(hunting.settings["upshift_rpm"])/hunting.rpm_for_speed(1.0,1)
		for i in range(600):
			hunting.update(1.0/60,threshold_speed*(0.99 if i%2==0 else 1.01),1,0,true,true)
		check(hunting.gear==2 and hunting.upshifts==1 and hunting.downshifts==0,id+" shift hysteresis prevents threshold hunting")
		metrics[id] = {"frame_rates":end_states}
	var level := Fixture.new()
	root.add_child(level)
	var body := StaticBody3D.new()
	body.collision_layer=1
	body.position.y=-0.5
	var shape:=CollisionShape3D.new()
	var box:=BoxShape3D.new()
	box.size=Vector3(2000,1,20000)
	shape.shape=box
	body.add_child(shape)
	level.add_child(body)
	car=preload("res://scenes/cars/PlayerCar.tscn").instantiate()
	car.vehicle_profile="VECTOR"
	level.add_child(car)
	car.external_control=true
	car.configure({"roads":[{"points_xz":[[0,9000],[0,-9000]],"oneway":false,"street_name":"TRANSMISSION PHYSICS FIXTURE"}]},{"bounds_xz":[-900,-9500,900,9500],"spawn":{"position_xz":[0,0],"forward_xz":[0,-1]}})
	level.follow_camera=preload("res://scripts/driving/FollowCamera.gd").new()
	level.add_child(level.follow_camera)
	level.follow_camera.attach(car)
	hud=preload("res://scripts/ui/DrivingHUD.gd").new()
	level.add_child(hud)
	hud.attach(car,level)
	car.powertrain.gear_changed.connect(on_shift)
	await step(6,0)
	check(car.powertrain.gear==0 and car.powertrain.rpm==900,"Idle is neutral at 900 RPM")
	for id in Profiles.IDS:
		car.velocity=Vector3.ZERO
		car.global_transform=car.spawn_transform
		car.reset_surface_motion()
		car.apply_vehicle_profile(id)
		shifts.clear()
		current_shift={}
		await step(6,0)
		await step(1800,1)
		await process_frame
		check(car.powertrain.gear==7 and car.powertrain.upshifts==6,id+" actual controller shifts through all gears")
		check(hud.gear_label.text=="7" and hud.speed_label.text=="%03d"%roundi(car.speed_mps*3.6),id+" HUD shows physical speed and current gear")
		check(absf(hud.instruments.needle_rpm-car.powertrain.rpm)<100,id+" needle tracks engine RPM")
		check(absf(car.feedback.engine_pitch_target-car.powertrain.rpm/3000.0)<0.01,id+" audio and dial use identical RPM")
		var real_shifts:=shifts.duplicate(true)
		var drops:=0
		for event in real_shifts:
			if event["to"]>event["from"] and event["before_rpm"]-event["minimum_rpm"]>600:
				drops+=1
		check(drops==6,id+" six upshifts produce visible RPM drops")
		metrics[id]["physical_upshifts"]=real_shifts
		metrics[id]["top_rpm"]=car.powertrain.rpm
		var frames:=0
		while car.signed_speed>0.5 and frames<700:
			await step(1,-1)
			frames+=1
		await step(120,0)
		check(car.powertrain.downshifts>0 and car.powertrain.gear==0,id+" brakes down through gears to neutral")
		var blips := 0
		for event in shifts:
			if event["to"]<event["from"] and event["maximum_rpm"]-event["before_rpm"]>450:
				blips += 1
		check(blips==6,id+" all six reductions give a rev-matching RPM blip")
		metrics[id]["downshift_blips"]=blips
		metrics[id]["physical_downshifts"]=car.powertrain.downshifts
		await step(120,-1)
		check(car.powertrain.gear==-1 and car.powertrain.rpm>=900,id+" reverse has valid RPM")
		car.recover()
		check(car.powertrain.gear==0 and car.powertrain.rpm==900,id+" recovery clears gear and RPM")
	var frozen_rpm:float=car.powertrain.rpm
	paused=true
	for i in range(5):await process_frame
	check(car.powertrain.rpm==frozen_rpm,"Pause freezes engine telemetry")
	paused=false
	var report:={"passed":failures.is_empty(),"failures":failures,"metrics":metrics}
	FileAccess.open("res://docs/powertrain_validation.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("POWERTRAIN_REPORT ",JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)

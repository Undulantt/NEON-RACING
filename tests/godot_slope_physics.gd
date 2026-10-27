extends SceneTree

# Synthetic geometry, production controller. This deliberately does not use a
# DEM service, so takeoff/gravity must work on actual collision surfaces.
var car: CharacterBody3D
var level: Node3D
var failures: Array[String] = []
var metrics := {}

func _initialize() -> void:
	run.call_deferred()

func check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
		push_error(message)

func height(s: float) -> float:
	if s<20:return 0.0
	if s<80:return (s-20)*0.25
	if s<110:return 15.0
	if s<170:return 15.0-(s-110)*0.25
	return 0.0

func step(frames: int, throttle: float = 0, handbrake: bool = false) -> void:
	car.set_controls(throttle,0,handbrake)
	for i in range(frames):
		await physics_frame

func reset(s: float, downhill: bool = false) -> void:
	var yaw := PI if downhill else 0.0
	car.global_transform=Transform3D(Basis(Vector3.UP,yaw),Vector3(0,height(s)+1.18,-s))
	car.velocity=Vector3.ZERO
	car.speed_mps=0
	car.signed_speed=0
	car.steering=0
	car.reset_surface_motion()
	await step(30,0,true)

func run() -> void:
	level=Node3D.new()
	root.add_child(level)
	var faces := PackedVector3Array()
	for s in range(-100,301,2):
		var a:=Vector3(-40,height(s),-s)
		var b:=Vector3(40,height(s),-s)
		var c:=Vector3(40,height(s+2),-s-2)
		var d:=Vector3(-40,height(s+2),-s-2)
		faces.append_array(PackedVector3Array([a,c,b,a,d,c]))
	var body:=StaticBody3D.new()
	body.collision_layer=1
	var shape:=ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	shape.backface_collision=true
	var collider:=CollisionShape3D.new()
	collider.shape=shape
	body.add_child(collider)
	level.add_child(body)
	car=preload("res://scenes/cars/PlayerCar.tscn").instantiate()
	level.add_child(car)
	car.configure({"roads":[{"points_xz":[[0,80],[0,-280]],"oneway":false,"street_name":"SYNTHETIC SLOPE TEST ONLY"}]},{"bounds_xz":[-35,-290,35,90],"spawn":{"position_xz":[0,0],"forward_xz":[0,-1]}})
	car.external_control=true
	await reset(55,true)
	var start:=car.position
	await step(120)
	metrics["unbraked_downhill"]={"distance_m":car.position.distance_to(start),"signed_speed_mps":car.signed_speed}
	check(car.signed_speed>4 and car.position.z>start.z+3,"Unbraked car must accelerate downhill from rest")
	await reset(55,true)
	start=car.position
	await step(180,0,true)
	metrics["hill_hold_drift_m"]=car.position.distance_to(start)
	check(car.position.distance_to(start)<0.08 and car.speed_mps<0.1,"Handbrake must hold the car on the hill")
	await reset(40)
	await step(90,0.15)
	metrics["weak_uphill_speed_mps"]=car.signed_speed
	check(car.signed_speed < -1,"Insufficient engine force must allow rollback rather than magical uphill traction")
	await reset(35)
	await step(60,1)
	var uphill_speed: float=car.signed_speed
	await reset(-35)
	await step(60,1)
	var flat_speed: float=car.signed_speed
	metrics["uphill_full_throttle_mps"]=uphill_speed
	metrics["flat_full_throttle_mps"]=flat_speed
	check(uphill_speed>2 and flat_speed>uphill_speed+2,"Full throttle must climb, with slower acceleration than flat ground")
	await reset(35)
	car.velocity=Vector3(0,0,-7)
	var furthest:=car.position.z
	for i in range(180):
		await step(1)
		furthest=minf(furthest,car.position.z)
	metrics["coast_uphill_final_speed_mps"]=car.signed_speed
	check(car.signed_speed < -1 and car.position.z>furthest+1,"An unpowered uphill car must lose speed and roll back")
	await reset(28)
	car.velocity=Vector3(0,0,-30)
	var uphill_takeoffs: int=car.crest_takeoffs
	var uphill_airframes:=0
	for i in range(45):
		await step(1)
		uphill_airframes+=int(not car.is_on_floor())
	check(uphill_airframes==0 and car.crest_takeoffs==uphill_takeoffs,"Speed on a constant uphill slope must not cause a jump")
	metrics["constant_uphill_airborne_frames"]=uphill_airframes
	for speed in [8.0,30.0]:
		await reset(60)
		car.velocity=Vector3(0,0,-speed)
		car.set_controls(0,0)
		var unsupported:=0
		var peak_clearance:=0.0
		var maximum_upward_velocity:=0.0
		var initial_takeoffs: int=car.crest_takeoffs
		var airborne_engine_gain:=0.0
		var airborne_speed_change:=0.0
		var previous_speed:=0.0
		var previous_airborne:=false
		var landed:=false
		for i in range(420 if speed<10 else 180):
			await physics_frame
			if not car.is_on_floor():
				unsupported+=1
				maximum_upward_velocity=maxf(maximum_upward_velocity,car.velocity.y)
				var support: float=car.predicted_support_height(car.position)
				if is_finite(support):peak_clearance=maxf(peak_clearance,car.position.y-support)
				# Engine/brake input in air must not propel or stop the vehicle.
				if previous_airborne:
					airborne_engine_gain=maxf(airborne_engine_gain,car.speed_mps-previous_speed)
					airborne_speed_change=maxf(airborne_speed_change,absf(car.speed_mps-previous_speed))
				car.set_controls(1 if unsupported<12 else -1,0,unsupported>=12)
			else:
				if previous_airborne:landed=true
				if speed<10:
					car.set_controls(clampf((8.0-car.signed_speed)*0.7-car.slope_acceleration/13.0,-1,1),0)
				else:
					car.set_controls(0,0)
			previous_speed=car.speed_mps
			previous_airborne=not car.is_on_floor()
			if -car.position.z>100:break
		metrics["slow_crest" if speed<10 else "fast_crest"]={"airborne_frames":unsupported,"peak_clearance_m":peak_clearance,"maximum_upward_velocity_mps":maximum_upward_velocity,"takeoffs":car.crest_takeoffs-initial_takeoffs,"landed":landed,"airborne_engine_gain_mps":airborne_engine_gain,"airborne_speed_change_mps":airborne_speed_change}
		if speed>=10:
			check(unsupported>3 and peak_clearance>0.08 and peak_clearance<1.5,"Fast uphill crest must produce a small ballistic hop")
			check(landed and car.is_on_floor(),"Crest hop must land normally")
			check(maximum_upward_velocity>0.5 and maximum_upward_velocity<=6.01,"Hop must preserve bounded upward momentum")
			check(airborne_engine_gain<0.05,"Throttle must not accelerate in midair")
			check(airborne_speed_change<0.05,"Service brake/handbrake must not stop the car in midair")
		else:
			check(unsupported==0 and car.crest_takeoffs==initial_takeoffs,"Slow crest crossing should remain grounded")
	check(car.recovery_count==0,"Hill fixture required recovery")
	var report:={"passed":failures.is_empty(),"failures":failures,"controller_sha256":FileAccess.get_sha256("res://scripts/driving/ArcadeCar.gd"),"driving_config_sha256":FileAccess.get_sha256("res://config/driving_config.json"),"metrics":metrics,"fixture":"Synthetic 25% hill with flat crest; production CharacterBody3D controller"}
	var output:=FileAccess.open("res://docs/slope_physics_validation.json",FileAccess.WRITE)
	output.store_string(JSON.stringify(report,"  "))
	print("SLOPE_PHYSICS_REPORT ",JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)

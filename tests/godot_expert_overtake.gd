extends SceneTree
func _initialize() -> void: run.call_deferred()
func run() -> void:
	await process_frame
	var scene:=Node3D.new()
	root.add_child(scene)
	current_scene=scene
	var floor_body:=StaticBody3D.new()
	floor_body.collision_layer=1
	var collider:=CollisionShape3D.new()
	var box:=BoxShape3D.new()
	box.size=Vector3(50,1,3000)
	collider.shape=box
	floor_body.add_child(collider)
	floor_body.position=Vector3(0,-0.5,-1250)
	scene.add_child(floor_body)
	var gates: Array=[]
	for index in range(1,51): gates.append({"position_xz":[0,-index*50],"forward_xz":[0,-1],"distance_m":index*50,"half_width_m":10,"edge_index":0})
	var data:={"id":"pass_probe","type":"sprint","distance_m":2500,"points_xz":[[0,0],[0,-2500]],"checkpoints":gates,"settings":{"countdown_s":0}}
	var config: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://config/rivals.json"))
	var cars: Array=[]
	var drivers: Array=[]
	var sessions: Array=[]
	var previous: Array=[]
	var path=preload("res://scripts/racing/RaceTrajectory.gd").new()
	for index in range(2):
		var car=preload("res://scenes/cars/PlayerCar.tscn").instantiate()
		car.external_control=true
		car.driving_enabled=false
		scene.add_child(car)
		car.set_physics_process(false)
		car.configure({"roads":[{"points_xz":[[0,0],[0,-2500]],"width_m":20,"oneway":true,"street_name":"Passing"}]},{"bounds_xz":[-100,-2800,100,100],"spawn":{"position_xz":[0,-20.0 if index==0 else 0.0],"forward_xz":[0,-1]}})
		car.apply_vehicle_profile("COMET")
		if index==0: path.configure(data,car)
		var progress=preload("res://scripts/racing/RaceSession.gd").new()
		progress.begin(data)
		var driver=preload("res://scripts/racing/RivalDriver.gd").new()
		driver.configure(car,progress,"aggressive",preload("res://scripts/racing/RivalDifficulty.gd").settings(config["profiles"]["aggressive"],"expert"),path)
		if index==0: driver.cruise_speed_limit=12.0
		cars.append(car)
		drivers.append(driver)
		sessions.append(progress)
		previous.append(car.position)
	for driver in drivers: driver.participants=cars
	for index in range(4): await physics_frame
	var initial_gap: float=cars[1].position.z-cars[0].position.z
	for car in cars: car.set_physics_process(true)
	var contacts:=0
	var lead_time:=0.0
	var actual_lead_peak:=-INF
	var lateral_peak:=0.0
	var measured:=false
	for step in range(2400):
		await physics_frame
		for index in range(2):
			var car=cars[index]
			var at: Vector3=previous[index]
			sessions[index].advance(Vector2(at.x,at.z),Vector2(car.position.x,car.position.z),1.0/60,true,at.y,car.position.y)
			previous[index]=car.position
			car.driving_enabled=sessions[index].phase=="running"
			drivers[index].update(1.0/60)
			for hit_index in range(car.get_slide_collision_count()):
				if car.get_slide_collision(hit_index).get_collider() is CharacterBody3D:
					contacts+=1
		var lead: float=drivers[1].nav_s-drivers[0].nav_s
		actual_lead_peak=maxf(actual_lead_peak,lead)
		lateral_peak=maxf(lateral_peak,absf(cars[1].position.x))
		lead_time=lead_time+1.0/60 if lead>7 else 0.0
		measured=measured or lead_time+0.000001>=0.5
		if measured and drivers[1].completed_passes==1 and lead>25: break
	var report:={"passed":measured and drivers[1].completed_passes==1 and contacts==0,"measured_completed":measured,"reported_completed":drivers[1].completed_passes,"lead_peak_m":actual_lead_peak,"lateral_peak_m":lateral_peak,"vehicle_contact_frames":contacts,"physics_unchanged":cars.all(func(c):return c.config==preload("res://scripts/driving/VehicleProfiles.gd").load_profile("COMET")["config"]),"fixture":"Two real COMET cars with RivalDriver. Leader cruises at 12 m/s by controller speed target; follower is expert. No speed/transform/ability injection while driving. Simulates gaining on a slower opponent, not overtaking an equally fast expert."}
	report["initial_gap_m"]=initial_gap
	report["passed"]=report["passed"] and report["physics_unchanged"] and initial_gap>18 and initial_gap<22
	FileAccess.open("res://.local/artifacts/expert_overtake.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("EXPERT_OVERTAKE ",JSON.stringify(report))
	quit(0 if report["passed"] else 1)

extends SceneTree
func _initialize() -> void: run.call_deferred()
func run() -> void:
	await process_frame
	var scene:=Node3D.new()
	root.add_child(scene)
	current_scene=scene
	var floor_body:=StaticBody3D.new()
	floor_body.collision_layer=1
	var shape:=CollisionShape3D.new()
	var box:=BoxShape3D.new()
	box.size=Vector3(50,1,3000)
	shape.shape=box
	floor_body.add_child(shape)
	floor_body.position=Vector3(0,-0.5,-1250)
	scene.add_child(floor_body)
	var settings: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://config/rivals.json"))
	var cases: Array=[]
	for entry in settings["lineup"]:
		cases.append(await run_case(scene,entry,settings["profiles"][entry["personality"]]))
	var report:={"passed":cases.all(func(r):return r["passed"]),"burst_earned":cases.all(func(r):return r["burst_earned"]),"turbo_used":cases.all(func(r):return r["turbo_used"]),"racers":cases,"fixture":"Synthetic flat 2500 m straight; current rival lineup, real AI/car/abilities, no injected speed, charge or ability state"}
	report["difficulty"]=root.get_node("GameFlow").rival_difficulty
	FileAccess.open("res://.local/artifacts/d3_abilities_validation.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("D3_ABILITIES ",JSON.stringify(report))
	quit(0 if report["passed"] else 1)

func run_case(scene: Node3D, entry: Dictionary, personality: Dictionary) -> Dictionary:
	var car=preload("res://scenes/cars/PlayerCar.tscn").instantiate()
	car.external_control=true
	scene.add_child(car)
	car.configure({"roads":[{"points_xz":[[0,0],[0,-2500]],"width_m":20,"oneway":true,"street_name":"Prueba"}]},{"bounds_xz":[-100,-2800,100,100],"spawn":{"position_xz":[0,0],"forward_xz":[0,-1]}})
	car.apply_vehicle_profile(entry["vehicle"])
	var gates:Array=[]
	for i in range(1,51): gates.append({"position_xz":[0,-i*50],"forward_xz":[0,-1],"distance_m":i*50,"half_width_m":10,"edge_index":0})
	var data:={"id":"test_straight","type":"sprint","laps":0,"distance_m":2500,"points_xz":[[0,0],[0,-2500]],"checkpoints":gates,"settings":{"countdown_s":3.0}}
	var session=preload("res://scripts/racing/RaceSession.gd").new()
	session.begin(data)
	var driver=preload("res://scripts/racing/RivalDriver.gd").new()
	driver.configure(car,session,entry["personality"],preload("res://scripts/racing/RivalDifficulty.gd").settings(personality,root.get_node("GameFlow").rival_difficulty))
	var previous:=Vector2.ZERO
	var previous_y: float=car.position.y
	var burst:=false
	var turbo:=false
	var peak:=0.0
	var burst_frames:=0
	var bonus_peak:=0.0
	var above_base_frames:=0
	for i in range(12000):
		await physics_frame
		var p:=Vector2(car.position.x,car.position.z)
		session.advance(previous,p,1.0/60,true,previous_y,car.position.y)
		previous=p
		previous_y=car.position.y
		car.driving_enabled=session.phase=="running"
		driver.update(1.0/60)
		burst=burst or car.abilities.burst_state==2
		if car.abilities.burst_state==2:
			burst_frames+=1
			if car.speed_mps>car.base_speed_cap*1.01: above_base_frames+=1
		bonus_peak=maxf(bonus_peak,car.abilities.burst_bonus)
		turbo=turbo or car.turbo_active
		peak=maxf(peak,car.speed_mps)
		if session.phase=="finished": break
	var report:={"name":entry["name"],"vehicle":entry["vehicle"],"personality":entry["personality"],"passed":burst and turbo and above_base_frames>0 and session.phase=="finished","burst_earned":burst,"turbo_used":turbo,"burst_seconds":burst_frames/60.0,"burst_bonus_peak":bonus_peak,"above_base_seconds":above_base_frames/60.0,"peak_mps":peak,"elapsed":session.elapsed,"phase":session.phase}
	scene.remove_child(car)
	car.queue_free()
	await physics_frame
	return report

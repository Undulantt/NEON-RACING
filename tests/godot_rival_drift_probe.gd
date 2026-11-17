extends SceneTree
const Radius:=35.0
func _initialize() -> void: run.call_deferred()
func run() -> void:
	await process_frame
	var scene:=Node3D.new()
	root.add_child(scene)
	current_scene=scene
	var floor_body:=StaticBody3D.new()
	floor_body.collision_layer=1
	var collision:=CollisionShape3D.new()
	var box:=BoxShape3D.new()
	box.size=Vector3(400,1,400)
	collision.shape=box
	floor_body.add_child(collision)
	floor_body.position.y=-0.5
	scene.add_child(floor_body)
	# A sampled circular racing line gives a continuous moderate bend, with
	# no 12 m urban fillets. The car is still moved only by RivalDriver inputs.
	var path=preload("res://scripts/racing/RaceTrajectory.gd").new()
	path.closed=true
	var points: Array=[]
	var gates: Array=[]
	for index in range(73):
		var angle:=TAU*index/72.0
		var p:=Vector2(sin(angle),cos(angle))*Radius
		points.append([p.x,p.y])
		path.append_point(p,20.0)
		path.curvature.append(-1.0/Radius)
		path.left_limits.append(-3.5)
		path.right_limits.append(3.5)
		if index==0: continue
		var f:=Vector2(cos(angle),-sin(angle))
		gates.append({"position_xz":[p.x,p.y],"forward_xz":[f.x,f.y],"distance_m":path.length,"half_width_m":8.0,"edge_index":index-1})
		path.gate_distances.append(path.length)
	var data:={"id":"npc_drift_circle","type":"circuit","laps":2,"lap_distance_m":path.length,"distance_m":path.length*2,"points_xz":points,"checkpoints":gates,"settings":{"countdown_s":3.0}}
	var config: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://config/rivals.json"))
	var results: Array=[]
	for entry in config["lineup"]:
		results.append(await run_car(scene,path,data,entry,config["profiles"][entry["personality"]]))
	var report:={"audit_completed":results.all(func(r):return r["finished"]),"npc_drift_demonstrated":results.any(func(r):return r["drift_rewards"]>0 and r["boost_frames"]>0),"fixture":"Synthetic flat 35 m radius circular route, two laps, wide asphalt, no traffic or walls. Actual RivalDriver; no scripted handbrake, speed, charge or rewards. Sampled circle supplied as shared navigation geometry.","rows":results}
	report["difficulty"]=root.get_node("GameFlow").rival_difficulty
	FileAccess.open("res://.local/artifacts/rival_acceptance_drift_probe.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("RIVAL_DRIFT_PROBE ",JSON.stringify(report))
	quit(0 if report["audit_completed"] else 1)

func run_car(scene: Node3D,path: RefCounted,data: Dictionary,entry: Dictionary,personality: Dictionary) -> Dictionary:
	var car=preload("res://scenes/cars/PlayerCar.tscn").instantiate()
	car.external_control=true
	scene.add_child(car)
	car.configure({"roads":[{"points_xz":data["points_xz"],"width_m":40,"oneway":true,"street_name":"Circle"}]},{"bounds_xz":[-180,-180,180,180],"spawn":{"position_xz":[0,Radius],"forward_xz":[1,0]}})
	car.apply_vehicle_profile(entry["vehicle"])
	var progress=preload("res://scripts/racing/RaceSession.gd").new()
	progress.begin(data)
	var driver=preload("res://scripts/racing/RivalDriver.gd").new()
	driver.configure(car,progress,entry["personality"],preload("res://scripts/racing/RivalDifficulty.gd").settings(personality,root.get_node("GameFlow").rival_difficulty),path)
	var previous: Vector3=car.position
	var requests:=0
	var valid:=0
	var boost:=0
	var applied_boost:=0
	var charge:=0.0
	var slip:=0.0
	var peak:=0.0
	for step in range(7200):
		var had_boost: bool=car.abilities.drift_boost_active
		await physics_frame
		progress.advance(Vector2(previous.x,previous.z),Vector2(car.position.x,car.position.z),1.0/60,true,previous.y,car.position.y)
		previous=car.position
		car.driving_enabled=progress.phase=="running"
		driver.update(1.0/60)
		requests+=int(car.command_handbrake and progress.phase=="running")
		valid+=int(car.abilities.drift_quality>0)
		boost+=int(car.abilities.drift_boost_active)
		applied_boost+=int(had_boost and car.brake_input<=0 and car.throttle_input>0 and car.is_on_floor() and car.speed_mps<car.current_speed_cap)
		charge=maxf(charge,car.abilities.drift_charge)
		slip=maxf(slip,absf(rad_to_deg(car.slip_angle)))
		peak=maxf(peak,car.speed_mps)
		if progress.phase=="finished": break
	var result:={"name":entry["name"],"vehicle":entry["vehicle"],"personality":entry["personality"],"finished":progress.phase=="finished","laps":progress.completed_laps,"elapsed_s":progress.elapsed,"drift_requested_frames":requests,"valid_drift_frames":valid,"drift_charge_peak":charge,"drift_rewards":car.drift_rewards,"boost_frames":boost,"slip_peak_degrees":slip,"peak_mps":peak,"recovery_manoeuvres":driver.recovery_attempts,"teleport_recoveries":car.recovery_count,"route_error_peak_m":driver.route_error_peak}
	scene.remove_child(car)
	result["boost_eligible_acceleration_frames"]=applied_boost
	car.queue_free()
	await physics_frame
	return result

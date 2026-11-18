extends SceneTree
const Driver=preload("res://scripts/racing/RivalDriver.gd")
const Assist=preload("res://scripts/racing/RivalAssist.gd")
const Profiles=preload("res://scripts/driving/VehicleProfiles.gd")
var failures: Array=[]
var checks:=0
func _initialize() -> void:run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok:failures.append(label);push_error(label)
func run() -> void:
	await process_frame
	var catalog: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://config/game_flow.json"))
	check(not FileAccess.file_exists("res://data/races/grand_tour_la_paz.json") and not catalog["menu_race_ids"].has("grand_tour_la_paz"),"Retired race absent from content and selector")
	var scene:=Node3D.new();root.add_child(scene);current_scene=scene
	var floor_body:=StaticBody3D.new();floor_body.collision_layer=1
	var shape:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=Vector3(40,1,5200)
	shape.shape=box;floor_body.add_child(shape);floor_body.position=Vector3(0,-.5,-2400);scene.add_child(floor_body)
	var settings: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://config/rivals.json"))
	await streaming_case(scene,floor_body)
	var cases: Array=[]
	for profile in Profiles.IDS:cases.append(await drive_case(scene,profile,settings))
	var report:={"passed":failures.is_empty(),"checks":checks,"failures":failures,"cases":cases,"fixture":"Synthetic flat asphalt for tests only; narrow checkpoints every 30m. Real cars, collisions and abilities; no transforms, velocity or ability-state injection during driving."}
	FileAccess.open("res://.local/artifacts/arcade_rivals_validation.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("ARCADE_RIVALS_REPORT ",JSON.stringify(report));quit(0 if report["passed"] else 1)

func streaming_case(scene: Node3D, floor_body: StaticBody3D) -> void:
	floor_body.collision_layer=0
	await physics_frame;await physics_frame
	var car=preload("res://scenes/cars/PlayerCar.tscn").instantiate();car.external_control=true;scene.add_child(car);car.set_physics_process(false)
	car.configure({"roads":[{"points_xz":[[0,0],[0,-300]],"width_m":12,"oneway":true,"street_name":"Streaming test only"}]},{"bounds_xz":[-100,-500,100,100],"spawn":{"position_xz":[0,0],"forward_xz":[0,-1]}})
	var data:={"type":"sprint","points_xz":[[0,0],[0,-300]],"checkpoints":[{"position_xz":[0,-300],"forward_xz":[0,-1],"distance_m":300,"edge_index":0,"half_width_m":3}]}
	var path=preload("res://scripts/racing/RaceTrajectory.gd").new();path.configure(data,car)
	check(path.sample(100)["freedom"]==0 and not path.unloaded_corridors.is_empty(),"Unloaded asphalt does not invent a lateral corridor")
	floor_body.collision_layer=1
	await physics_frame;await physics_frame
	var before: int=path.unloaded_corridors.size()
	path.refresh_streamed_corridors(100,car)
	check(before-path.unloaded_corridors.size()<=4,"Streaming corridor refresh has a four-sample work budget")
	for i in range(20):path.refresh_streamed_corridors(100,car)
	check(path.sample(100)["freedom"]>1.8 and path.sample(110)["freedom"]>1.8,"Loaded asphalt enables overtaking away from the starting sector")
	check(not path.unloaded_corridors.is_empty(),"Refresh remains local instead of loading or rebuilding the world")
	data["start"]={"position_xz":[0,0],"forward_xz":[0,-1]}
	var competition=preload("res://scripts/racing/RaceCompetition.gd").new()
	for kind in ["sprint","circuit"]:
		data["type"]=kind
		var grid: Array=competition.starting_grid(car,data,6)
		check(grid.size()==6,"Six supported grid slots for "+kind)
		if grid.size()==6:
			check(is_equal_approx(grid[0].origin.x,-2.2) and is_equal_approx(grid[1].origin.x,2.2) and is_equal_approx(grid[5].origin.z-grid[1].origin.z,14),"Two columns and three parallel rows for "+kind)
	data["start"]["position_xz"]=[100,0]
	check(competition.starting_grid(car,data,6).is_empty(),"Unsupported start is rejected instead of silently using a single-file grid")
	competition.free()
	car.queue_free();await process_frame

func drive_case(scene: Node3D, profile: String, settings: Dictionary) -> Dictionary:
	var gates: Array=[]
	for i in range(1,134):gates.append({"position_xz":[0,-i*30],"forward_xz":[0,-1],"distance_m":i*30,"half_width_m":3.2,"edge_index":0})
	var data:={"id":"arcade_fixture","type":"sprint","laps":0,"distance_m":3990,"points_xz":[[0,0],[0,-3990]],"checkpoints":gates,"settings":{"countdown_s":0}}
	var cars: Array=[];var drivers: Array=[];var sessions: Array=[];var previous: Array=[]
	var trajectory=preload("res://scripts/racing/RaceTrajectory.gd").new()
	for i in range(2):
		var car=preload("res://scenes/cars/PlayerCar.tscn").instantiate();car.external_control=true;car.driving_enabled=false
		scene.add_child(car);car.set_physics_process(false)
		car.configure({"roads":[{"points_xz":[[0,0],[0,-3990]],"width_m":20,"oneway":true,"street_name":"Test only"}]},{"bounds_xz":[-100,-5000,100,200],"spawn":{"position_xz":[0,-120 if i==0 else 0],"forward_xz":[0,-1]}})
		car.apply_vehicle_profile(profile)
		if i==0:trajectory.configure(data,car)
		var session=preload("res://scripts/racing/RaceSession.gd").new();session.begin(data)
		# The leader begins 120m into this test scenario, with matching initial
		# progress. Neither progress nor transforms are injected while driving.
		if i==0:session.next_checkpoint=4;session.progress_m=120
		var driver=Driver.new();driver.configure(car,session,"balanced",settings["profiles"]["balanced"],trajectory)
		driver.tactics_rng.seed=730+i
		if i==0:driver.cruise_speed_limit=float(car.config["max_forward_speed_mps"])*.94
		cars.append(car);drivers.append(driver);sessions.append(session);previous.append(car.position)
	for d in drivers:d.participants=cars
	var base_player: Dictionary=cars[0].config.duplicate(true)
	var assist=Assist.new();assist.configure(cars[1],drivers[1],settings["arcade_assists"],"expert")
	check(cars[0].config==base_player and cars[0].config==Profiles.load_profile(profile)["config"],"Player config unaffected: "+profile)
	check(cars[1].config["braking_mps2"]>base_player["braking_mps2"] and cars[1].config["steering_response_per_second"]>base_player["steering_response_per_second"],"NPC-only handling/braking bonuses: "+profile)
	for i in range(4):await physics_frame
	for c in cars:c.set_physics_process(true)
	var contacts:=0;var burst_frames:=0;var turbo_frames:=0;var lateral_at_gate:=0.0;var lead_time:=0.0;var pass_measured:=false
	var peak_speed:=0.0;var previous_cp:=0;var catchup_before:=0.0
	for tick in range(9000):
		await physics_frame
		for i in range(2):
			var p: Vector3=cars[i].position;var before: Vector3=previous[i]
			sessions[i].advance(Vector2(before.x,before.z),Vector2(p.x,p.z),1.0/60,true,before.y,p.y);previous[i]=p
			cars[i].driving_enabled=sessions[i].phase=="running"
		assist.update(1.0/60,sessions[0])
		for d in drivers:d.update(1.0/60)
		if tick%600==0:print("ARCADE_SAMPLE ",JSON.stringify({"vehicle":profile,"t":tick/60.0,"lead_z":cars[0].position.z,"npc_z":cars[1].position.z,"x":cars[1].position.x,"nav":drivers[1].nav_s,"state":drivers[1].state,"lane":drivers[1].lane,"speed":cars[1].speed_mps,"target":drivers[1].target_speed,"burst":cars[1].abilities.burst_state,"brake":cars[1].command_brake,"bonus":assist.speed_bonus}))
		for c in cars:
			for hit in range(c.get_slide_collision_count()):
				if c.get_slide_collision(hit).get_collider() is CharacterBody3D:contacts+=1
		if cars[1].abilities.burst_state==2:burst_frames+=1
		if cars[1].turbo_active:turbo_frames+=1
		peak_speed=maxf(peak_speed,cars[1].speed_mps)
		if sessions[1].next_checkpoint>previous_cp:
			lateral_at_gate=maxf(lateral_at_gate,absf(cars[1].position.x));previous_cp=sessions[1].next_checkpoint
		var lead: float=cars[0].position.z-cars[1].position.z
		lead_time=lead_time+1.0/60 if lead>7 else 0.0
		pass_measured=pass_measured or lead_time>.5
		if tick==180:catchup_before=assist.speed_bonus
		if sessions[1].phase=="finished":break
	var row:={"vehicle":profile,"finished":sessions[1].phase=="finished","gates":sessions[1].next_checkpoint,"passes_measured":pass_measured,"passes_reported":drivers[1].completed_passes,"contact_frames":contacts,"lateral_at_gate_m":lateral_at_gate,"line_choices":drivers[1].line_choices,"burst_frames":burst_frames,"turbo_frames":turbo_frames,"peak_speed_mps":peak_speed,"catchup_peak":assist.peak_bonus,"catchup_final":assist.speed_bonus,"catchup_early":catchup_before,"teleports":cars[1].recovery_count}
	check(row["finished"],"Physical completion: "+profile)
	check(pass_measured and drivers[1].completed_passes>0,"Measured overtake of moving same-model car: "+profile)
	check(contacts==0,"No vehicle contacts during overtake: "+profile)
	check(lateral_at_gate>1.2,"Checkpoints allow lateral racing line: "+profile)
	check(burst_frames>30 and turbo_frames>0,"Real TURBO and sustained BURST: "+profile)
	check(assist.peak_bonus>.06 and assist.peak_bonus<=float(settings["arcade_assists"]["maximum_speed_bonus"])+.001 and assist.speed_bonus<.001,"Bounded catchup activates behind and fades after passing: "+profile)
	check(cars[0].config==base_player and cars[1].recovery_count==0,"No player buffs or NPC teleports: "+profile)
	assist.restore();check(cars[1].config==Profiles.load_profile(profile)["config"] and not drivers[1].arcade,"Assists restore base profile: "+profile)
	for c in cars:c.queue_free()
	await process_frame
	return row

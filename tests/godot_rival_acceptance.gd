extends SceneTree
const Driver=preload("res://scripts/racing/RivalDriver.gd")
const Session=preload("res://scripts/racing/RaceSession.gd")
const Profiles=preload("res://scripts/driving/VehicleProfiles.gd")
const PassMeasurement=preload("res://tests/RivalPassMeasurement.gd")
var flow: Node
var settings: Dictionary
var names: Dictionary={}
var solo_start_pose := Transform3D.IDENTITY
var solo_pose_initialized := false
var source_hashes: Dictionary={}

func _initialize() -> void: run.call_deferred()

func run() -> void:
	source_hashes={"rivals_config_sha256":FileAccess.get_sha256("res://config/rivals.json"),"driver_sha256":FileAccess.get_sha256("res://scripts/racing/RivalDriver.gd"),"physics_sha256":FileAccess.get_sha256("res://scripts/driving/ArcadeCar.gd")}
	await process_frame
	flow=root.get_node("GameFlow")
	flow.settings_path="res://tests/.acceptance_settings_%d.cfg" % OS.get_process_id()
	settings=JSON.parse_string(FileAccess.get_file_as_string("res://config/rivals.json"))
	change_scene_to_file(flow.definition["menu_scene"])
	await process_frame
	flow.show_screen(&"play_menu")
	flow.choose_mode(&"race")
	flow.select_vehicle("COMET")
	flow.start_selected()
	var deadline:=Time.get_ticks_msec()+120000
	while flow.current_state!=&"race" or flow.transition_busy:
		if Time.get_ticks_msec()>deadline: push_error("World load timeout");quit(1);return
		await process_frame
	var solo: bool="--personalities" in OS.get_cmdline_user_args()
	var modes: Array=["conservative","balanced","aggressive"] if solo else ["normal","npc_only","npc_reverse_grid"]
	var cases: Array=[]
	for mode in modes:
		if not cases.is_empty():
			flow.restart_race()
			while flow.transition_busy: await process_frame
		cases.append(await run_case(current_scene,mode,solo))
	var completed: bool=cases.all(func(c):return c["completed"])
	var report:={"audit_completed":completed,"acceptance_approved":false,"group":"same_car_personalities" if solo else "traffic","cases":cases,"note":"Completion means measurements ran successfully; it does not approve all five acceptance criteria. Drift by NPC and subjective fun need separate evidence.","rivals_config_sha256":FileAccess.get_sha256("res://config/rivals.json"),"driver_sha256":FileAccess.get_sha256("res://scripts/racing/RivalDriver.gd"),"physics_sha256":FileAccess.get_sha256("res://scripts/driving/ArcadeCar.gd")}
	report.merge(source_hashes,true)
	report["difficulty"]=flow.rival_difficulty
	var path:="res://.local/artifacts/rival_acceptance_%s_%s.json" % ["personalities" if solo else "traffic",flow.rival_difficulty]
	FileAccess.open(path,FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("RIVAL_ACCEPTANCE ",JSON.stringify(report))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(flow.settings_path))
	quit(0 if completed else 1)

func disable_car(car: CharacterBody3D) -> void:
	car.set_physics_process(false)
	car.collision_layer=0
	car.collision_mask=0
	car.hide()

func frozen_probe(racer: Dictionary, trajectory: RefCounted) -> Dictionary:
	var car: CharacterBody3D=racer["car"]
	var pose:=car.global_transform
	var motion:=car.velocity
	var was_enabled: bool=car.driving_enabled
	car.driving_enabled=true
	car.set_physics_process(false)
	var progress=Session.new()
	progress.begin(racer["session"].definition)
	progress.phase="running"
	var probe=Driver.new()
	probe.configure(car,progress,racer["driver"].personality_id,racer["driver"].personality,trajectory)
	probe.preferred_lane=-3.5
	var throttle:=false
	var steering:=false
	for index in range(60):
		probe.update(1.0/60)
		throttle=throttle or car.command_throttle>0.1
		steering=steering or absf(car.command_steer)>0.01
	var result:={"updates":60,"physics_disabled":true,"transform_unchanged":car.global_transform==pose,"velocity_unchanged":car.velocity==motion,"throttle_requested":throttle,"steering_requested":steering}
	car.set_controls(0,0)
	car.driving_enabled=was_enabled
	car.set_physics_process(true)
	racer["driver"].configure(car,racer["session"],racer["driver"].personality_id,racer["driver"].personality,trajectory)
	return result

func run_case(world: Node3D, mode: String, solo: bool) -> Dictionary:
	var competition=world.race_activity.competition
	var targets: Array=competition.racers.duplicate()
	var autopilot=Driver.new()
	names.clear()
	for racer in competition.racers: names[racer["car"].get_instance_id()]=racer["name"]
	var probes: Dictionary={}
	if mode=="normal":
		for racer in competition.racers:
			if racer["driver"]!=null: probes[racer["name"]]=frozen_probe(racer,competition.trajectory)
		autopilot.configure(world.player,world.race_activity.session,"balanced",settings["profiles"]["balanced"],competition.trajectory)
		autopilot.participants=[world.player]+competition.rivals
	else:
		disable_car(world.player)
		targets=competition.racers.filter(func(r):return r["car"]!=world.player)
		for racer in targets: racer["driver"].participants=competition.rivals.duplicate()
	if mode=="npc_reverse_grid":
		var poses: Array=[]
		for racer in targets: poses.append(racer["car"].global_transform)
		poses.reverse()
		for index in range(targets.size()):
			var racer: Dictionary=targets[index]
			racer["car"].global_transform=poses[index]
			racer["car"].reset_surface_motion()
			racer["previous"]=Vector2(poses[index].origin.x,poses[index].origin.z)
			racer["previous_y"]=poses[index].origin.y
	if solo:
		var selected: Dictionary=targets[0]
		for racer in targets:
			if racer==selected: continue
			disable_car(racer["car"])
			racer["session"].phase="idle"
		targets=[selected]
		# Reuse the exact pose: the first load can settle a few millimetres
		# before the fixture starts, whereas an immediate restart has not.
		if not solo_pose_initialized:
			solo_start_pose=selected["car"].global_transform
			solo_pose_initialized=true
		selected["car"].global_transform=solo_start_pose
		selected["car"].velocity=Vector3.ZERO
		selected["car"].reset_surface_motion()
		selected["previous"]=Vector2(solo_start_pose.origin.x,solo_start_pose.origin.z)
		selected["previous_y"]=solo_start_pose.origin.y
		selected["session"].begin(world.race_activity.definition)
		selected["session"].set_surface_heights(selected["car"].surface_height)
		selected["car"].apply_vehicle_profile("VECTOR")
		selected["driver"].personality_id=mode
		selected["driver"].personality=preload("res://scripts/racing/RivalDifficulty.gd").settings(settings["profiles"][mode],flow.rival_difficulty)
		selected["driver"].expert=flow.rival_difficulty=="expert"
		selected["driver"].preferred_lane=0.0
		selected["driver"].participants=[selected["car"]]
	var metrics: Dictionary={}
	var events: Array=[]
	var episodes: Dictionary={}
	var contact_seconds: Dictionary={}
	var old_pairs: Dictionary={}
	var last_contact_step: Dictionary={}
	var encounters: Dictionary={}
	var pilots: Dictionary={world.player.get_instance_id():autopilot}
	var sessions: Dictionary={}
	for racer in competition.racers:
		sessions[racer["car"].get_instance_id()]=racer["session"]
		if racer["driver"]!=null: pilots[racer["car"].get_instance_id()]=racer["driver"]
	for racer in targets:
		var c=racer["car"]
		var expected: Dictionary=Profiles.load_profile(c.vehicle_profile)["config"]
		metrics[racer["name"]]={"vehicle":c.vehicle_profile,"personality":racer["driver"].personality_id if racer["driver"]!=null else "test_autopilot","initial_position":[c.position.x,c.position.y,c.position.z],"physics_config_hash":hash(expected),"physics_config_equal":c.config==expected,"speed_multiplier_normal":c.drive_test_multiplier()==1.0,"frames":0,"throttle_frames":0,"brake_frames":0,"steer_frames":0,"left_steer_frames":0,"right_steer_frames":0,"distance_m":0.0,"peak_mps":0.0,"motion_residual_peak_m":0.0,"wall_contact_frames":0,"vehicle_contact_frames":0,"offroad_frames":0,"turbo_frames":0,"drift_requests":0,"drift_valid_frames":0,"drift_rewards":0,"burst_frames":0,"previous_position":c.position,"previous_speed":c.speed_mps,"last_passes":0,"active_pass":{},"done":false}
	for step in range(18000):
		await physics_frame
		if mode=="normal": autopilot.update(1.0/60)
		var pairs: Dictionary={}
		for racer in targets:
			var c=racer["car"]
			var m: Dictionary=metrics[racer["name"]]
			if m["done"]: continue
			if racer["session"].phase=="countdown":
				m["previous_position"]=c.position
				continue
			m["frames"]+=1
			m["throttle_frames"]+=int(c.throttle_input>0.1)
			m["brake_frames"]+=int(c.brake_input>0.1)
			m["steer_frames"]+=int(absf(c.steering)>0.05)
			m["left_steer_frames"]+=int(c.steering< -0.05)
			m["right_steer_frames"]+=int(c.steering>0.05)
			var movement: Vector3=c.position-m["previous_position"]
			m["distance_m"]+=movement.length()
			m["peak_mps"]=maxf(m["peak_mps"],c.speed_mps)
			m["motion_residual_peak_m"]=maxf(m["motion_residual_peak_m"],(movement-c.get_real_velocity()/60.0).length())
			m["previous_position"]=c.position
			m["physics_config_equal"]=m["physics_config_equal"] and c.config==Profiles.load_profile(c.vehicle_profile)["config"] if step%120==0 else m["physics_config_equal"]
			m["speed_multiplier_normal"]=m["speed_multiplier_normal"] and c.drive_test_multiplier()==1.0
			m["offroad_frames"]+=int(not c.on_asphalt)
			m["turbo_frames"]+=int(c.turbo_active)
			m["drift_requests"]+=int(c.command_handbrake)
			m["drift_valid_frames"]+=int(c.abilities.drift_quality>0)
			m["drift_rewards"]=c.drift_rewards
			m["burst_frames"]+=int(c.abilities.burst_state==2)
			var wall:=false
			var vehicle:=false
			for hit_index in range(c.get_slide_collision_count()):
				var hit=c.get_slide_collision(hit_index)
				if absf(hit.get_normal().y)>0.5: continue
				var other=hit.get_collider()
				if other is CharacterBody3D and names.has(other.get_instance_id()):
					vehicle=true
					pairs[pair_key(racer["name"],names[other.get_instance_id()])]=true
				else: wall=true
			m["wall_contact_frames"]+=int(wall)
			m["vehicle_contact_frames"]+=int(vehicle)
			var pilot=racer["driver"]
			if pilot!=null:
				var active: Dictionary=m["active_pass"]
				if pilot.completed_passes>int(m["last_passes"]) and not active.is_empty():
					active["driver_reported_completed"]=true
					active["end_s"]=racer["session"].elapsed
				m["last_passes"]=pilot.completed_passes
				if is_instance_valid(pilot.passing_car):
					var defender: String=names.get(pilot.passing_car.get_instance_id(),"unknown")
					if active.is_empty() or active["defender"]!=defender or active["driver_reported_completed"]:
						var defender_pilot=pilots[pilot.passing_car.get_instance_id()]
						active={"attacker":racer["name"],"defender":defender,"attacker_id":c.get_instance_id(),"defender_id":pilot.passing_car.get_instance_id(),"defender_npc":pilot.passing_car!=world.player,"defender_moving":pilot.passing_car.speed_mps>1.0,"start_s":racer["session"].elapsed,"driver_reported_completed":false,"measured_completed":false,"initial_gap_m":pilot.nav_s-defender_pilot.nav_s,"measured_lead_peak_m":-INF,"lead_frames":0,"lateral_peak_m":0.0,"pair_contact_frames":0}
						events.append(active)
						m["active_pass"]=active
					var projected: Dictionary=competition.trajectory.project(Vector2(c.position.x,c.position.z),pilot.nav_s)
					active["lateral_peak_m"]=maxf(active["lateral_peak_m"],absf(float(projected["lateral"])))
				elif not active.is_empty() and not active.has("end_s"):
					active["end_s"]=racer["session"].elapsed
					m["active_pass"]={}
			if racer["session"].phase=="finished": m["done"]=true
		for key in pairs:
			contact_seconds[key]=float(contact_seconds.get(key,0.0))+1.0/60
			if not old_pairs.has(key): episodes[key]=int(episodes.get(key,0))+1
			if not last_contact_step.has(key) or step-int(last_contact_step[key])>30: encounters[key]=int(encounters.get(key,0))+1
			last_contact_step[key]=step
		for event in events:
			if event.has("end_s") and float(event["end_s"])<float(sessions[event["attacker_id"]].elapsed)-0.000001: continue
			if pairs.has(pair_key(event["attacker"],event["defender"])): event["pair_contact_frames"]+=1
			# Compare each car's own continuous progress. Re-projecting a distant
			# target using the attacker's local search window can report a false
			# pass. A measurement needs 7 m of real lead held for half a second,
			# with both cars still racing and an initially following attacker.
			var both_racing: bool=sessions[event["attacker_id"]].phase=="running" and sessions[event["defender_id"]].phase=="running"
			PassMeasurement.sample(event,pilots[event["attacker_id"]].nav_s,pilots[event["defender_id"]].nav_s,both_racing)
		old_pairs=pairs
		if targets.all(func(r):return r["session"].phase=="finished"): break
	var rows: Array=[]
	for racer in targets:
		var m: Dictionary=metrics[racer["name"]]
		for key in ["previous_position","previous_speed","last_passes","active_pass","done"]: m.erase(key)
		m["name"]=racer["name"]
		m["finished"]=racer["session"].phase=="finished"
		m["laps"]=racer["session"].completed_laps
		m["elapsed_s"]=racer["session"].elapsed
		m["lap_times"]=racer["session"].lap_times.duplicate()
		m["teleport_recoveries"]=racer["car"].recovery_count
		m["recovery_manoeuvres"]=racer["driver"].recovery_attempts if racer["driver"]!=null else 0
		m["checkpoint_recoveries"]=racer["driver"].checkpoint_recoveries if racer["driver"]!=null else 0
		rows.append(m)
	for event in events:
		event.erase("attacker_id")
		event.erase("defender_id")
	var result:={"mode":mode,"completed":rows.all(func(r):return r["finished"] and r["laps"]==2),"player_in_perception":mode=="normal","same_car_solo":solo,"rows":rows,"passes":events,"vehicle_contact_episodes":episodes,"vehicle_contact_encounters":encounters,"vehicle_contact_seconds":contact_seconds,"contact_method":"Episodes are contiguous contact runs; encounters group interruptions up to 0.5 s to avoid counting every bounce as a separate crash.","frozen_controller_probes":probes,"scope":"Two laps on production Centro LP, real world and physics. Changes to car/lineup/grid occur only before countdown; finish parking excluded."}
	print("ACCEPTANCE_CASE ",mode," completed=",result["completed"]," contacts=",episodes," passes=",events.size())
	return result

func pair_key(a: String,b: String) -> String:
	return a+" / "+b if a<b else b+" / "+a

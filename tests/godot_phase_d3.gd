extends SceneTree
var flow: Node
func _initialize() -> void: run.call_deferred()
func run() -> void:
	await process_frame
	flow=root.get_node("GameFlow")
	flow.settings_path="res://tests/.d3_settings_%d.cfg" % OS.get_process_id()
	change_scene_to_file(flow.definition["menu_scene"])
	await process_frame
	flow.show_screen(&"play_menu")
	flow.choose_mode(&"race")
	flow.select_vehicle("COMET")
	flow.start_selected()
	var deadline:=Time.get_ticks_msec()+120000
	while flow.current_state!=&"race" or flow.transition_busy:
		if Time.get_ticks_msec()>deadline: print("LOAD FAILED ",flow.navigation_error);quit(1);return
		await process_frame
	var world=current_scene
	var activity=world.race_activity
	var competition=activity.competition
	var driver=preload("res://scripts/racing/RivalDriver.gd").new()
	var settings: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://config/rivals.json"))
	driver.configure(world.player,activity.session,"balanced",settings["profiles"]["balanced"],competition.trajectory)
	driver.participants=[world.player]+competition.rivals
	var stationary: bool="--stationary-player" in OS.get_cmdline_user_args()
	var legacy_grid: bool="--single-file-grid" in OS.get_cmdline_user_args()
	var ability_audit: bool="--audit-abilities" in OS.get_cmdline_user_args()
	if legacy_grid:
		competition.grid_columns=1
		var start_at:=Vector2(activity.definition["start"]["position_xz"][0],activity.definition["start"]["position_xz"][1])
		var direction:=Vector2(activity.definition["start"]["forward_xz"][0],activity.definition["start"]["forward_xz"][1])
		for index in range(competition.racers.size()):
			var racer: Dictionary=competition.racers[index]
			var at:=start_at-direction*(index*7.0)
			racer["car"].global_transform=competition.grid_pose(racer["car"],at,direction)
			racer["car"].reset_surface_motion()
			racer["previous"]=at
			racer["previous_y"]=racer["car"].position.y
		activity.previous=start_at
		activity.previous_y=world.player.position.y
	var capture_route: bool="--capture-route" in OS.get_cmdline_user_args()
	if capture_route:
		DisplayServer.window_set_title("Neon Racing LP - IA continua (prueba)")
		competition.observe=mini(4,competition.rivals.size()-1)
	var parked_at: Vector3=world.player.position
	var initial_safe: bool=competition.racers.all(func(r): return r["car"].safe_road_transform(r["car"].global_transform))
	var launch_locked: bool=competition.racers.all(func(r):return not r["car"].driving_enabled)
	var ability_metrics: Dictionary={}
	var physics_samples: Array[float]=[]
	var max_physics_ms:=0.0
	var peak:=0.0
	var start:=Time.get_ticks_msec()
	for frame in range(36000):
		await physics_frame
		if stationary: world.player.set_controls(0,0,true)
		else: driver.update(1.0/60)
		peak=maxf(peak,world.player.speed_mps)
		if frame>240 and activity.session.phase=="running":
			var physics_ms:=Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000
			max_physics_ms=maxf(max_physics_ms,physics_ms)
			physics_samples.append(physics_ms)
		for racer in competition.racers:
			# Freeze each racer's observations at its finish. Retiring/parking
			# handbrake commands are not competitive drift attempts.
			if racer["session"].phase!="running": continue
			var c=racer["car"]
			var m: Dictionary=ability_metrics.get(racer["name"],{"vehicle":c.vehicle_profile,"personality":racer["driver"].personality_id if racer["driver"]!=null else "balanced_test_autopilot","observed_frames":0,"peak_mps":0.0,"turbo_frames":0,"drift_requested_frames":0,"drift_valid_frames":0,"drift_charge_peak":0.0,"drift_rewards":0,"drift_boost_frames":0,"drift_boost_with_acceleration_frames":0,"burst_preparation_frames":0,"burst_arming_peak_s":0.0,"burst_frames":0,"burst_entries":0,"burst_bonus_peak":0.0,"burst_above_base_cap_frames":0,"was_burst":false})
			m["observed_frames"]+=1
			m["peak_mps"]=maxf(m["peak_mps"],c.speed_mps)
			if c.turbo_active: m["turbo_frames"]+=1
			if c.command_handbrake: m["drift_requested_frames"]+=1
			if c.abilities.drift_quality>0: m["drift_valid_frames"]+=1
			m["drift_charge_peak"]=maxf(m["drift_charge_peak"],c.abilities.drift_charge)
			m["drift_rewards"]=c.drift_rewards
			if c.abilities.drift_boost_active:
				m["drift_boost_frames"]+=1
				if c.throttle_input>0 and c.brake_input<=0 and c.is_on_floor() and c.speed_mps<c.current_speed_cap: m["drift_boost_with_acceleration_frames"]+=1
			if c.abilities.burst_state==1: m["burst_preparation_frames"]+=1
			m["burst_arming_peak_s"]=maxf(m["burst_arming_peak_s"],c.abilities.arming_time)
			var in_burst: bool=c.abilities.burst_state==2
			if in_burst:
				m["burst_frames"]+=1
				if not m["was_burst"]: m["burst_entries"]+=1
				if c.speed_mps>c.base_speed_cap*1.01: m["burst_above_base_cap_frames"]+=1
			m["burst_bonus_peak"]=maxf(m["burst_bonus_peak"],c.abilities.burst_bonus)
			m["was_burst"]=in_burst
			ability_metrics[racer["name"]]=m
		if "--capture-d3" in OS.get_cmdline_user_args() and frame in ([1,600,1200,1800,2400,3000,3600,4200] if capture_route else [1,2400,8400]):
			await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(("res://.local/artifacts/evidence/d3_route_%d.png" if capture_route else "res://.local/artifacts/evidence/d3_race_%d.png") % frame)
		if frame%1800==0:
			print("D3 ",frame," ",competition.table()," player ",world.player.position)
			for racer in competition.racers:
				if racer["driver"]!=null: print(racer["name"]," ",racer["car"].position," ",racer["driver"].telemetry())
		if competition.racers.all(func(r):return (stationary and r["car"]==world.player) or r["session"].phase=="finished") and (ability_audit or competition.racers.all(func(r):return r["car"]==world.player or r.get("parked",false))): break
	var rows:Array=[]
	for racer in competition.racers:
		var s=racer["session"]
		var agent=racer["driver"]
		var drive_metrics: Dictionary={} if agent==null else {"completed_passes":agent.completed_passes,"held_merges":agent.held_merges,"checkpoint_recoveries":agent.checkpoint_recoveries,"recovery_attempts":agent.recovery_attempts,"route_error_peak_m":agent.route_error_peak,"steer_delta_per_second":agent.steering_variation/maxf(1,s.elapsed),"mean_update_us":float(agent.update_usec_total)/maxi(1,agent.sampled_frames),"max_update_us":agent.update_usec_max}
		rows.append({"name":racer["name"],"phase":s.phase,"laps":s.completed_laps,"cp":s.next_checkpoint,"elapsed":s.elapsed,"lap_times":s.lap_times,"recoveries":racer["car"].recovery_count,"parked":racer.get("parked",false),"driver":drive_metrics})
	physics_samples.sort()
	var report:={"passed":competition.racers.all(func(r):return (stationary and r["car"]==world.player) or r["session"].phase=="finished"),"stationary_player":stationary,"single_file_fixture":legacy_grid,"grid_columns":competition.grid_columns,"trajectory":{"length_m":competition.trajectory.length,"samples":competition.trajectory.points.size(),"rounded_corners":competition.trajectory.rounded_corners,"fallback_corners":competition.trajectory.fallback_corners},"player_displacement_m":Vector2(world.player.position.x-parked_at.x,world.player.position.z-parked_at.z).length(),"racers":rows,"peak":peak,"wall_s":(Time.get_ticks_msec()-start)/1000.0,"initial_safe":initial_safe,"countdown_locked":launch_locked,"abilities":ability_metrics,"max_physics_ms":max_physics_ms,"physics_p95_ms":physics_samples[int(physics_samples.size()*0.95)],"physics_p99_ms":physics_samples[int(physics_samples.size()*0.99)]}
	report["finish_lane_cleared"]=competition.racers.all(func(r):return r["car"]==world.player or r.get("parked",false))
	report["ability_audit"]=ability_audit
	report["passed"]=report["passed"] and initial_safe and launch_locked and (ability_audit or report["finish_lane_cleared"])
	if stationary: report["passed"]=report["passed"] and report["player_displacement_m"]<0.25 and activity.session.next_checkpoint==0 and activity.session.completed_laps==0
	print("D3_REPORT ",JSON.stringify(report))
	FileAccess.open("res://.local/artifacts/d3_ability_race_audit.json" if ability_audit else "res://.local/artifacts/d3_parked_legacy.json" if stationary and legacy_grid else "res://.local/artifacts/d3_parked_grid.json" if stationary else "res://.local/artifacts/d3_validation_%d.json" % competition.rivals.size(),FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	if "--capture-d3" in OS.get_cmdline_user_args():
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.local/artifacts/evidence/d3_route_results.png" if capture_route else "res://.local/artifacts/evidence/d3_results.png")
	if "--lifecycle-d3" in OS.get_cmdline_user_args():
		var count: int=competition.rivals.size()
		flow.restart_race()
		while flow.transition_busy: await process_frame
		await process_frame
		report["restart_clean"]=activity.competition.rivals.size()==count and world.get_children().filter(func(n):return n is CharacterBody3D).size()==count+1
		flow.return_from_activity()
		while flow.transition_busy: await process_frame
		report["menu_return"]=flow.current_state==&"main_menu"
		flow.show_screen(&"play_menu")
		flow.choose_mode(&"free_drive")
		flow.start_selected()
		while flow.transition_busy: await process_frame
		world=current_scene
		var selected: String=world.player.vehicle_profile
		flow.request_race_from_free_drive(str(flow.definition["default_race_id"]))
		while flow.transition_busy: await process_frame
		activity=world.race_activity
		report["free_drive_race"]=flow.current_state==&"race" and activity.competition.rivals.size()==count and world.player.vehicle_profile==selected
		flow.return_from_activity()
		while flow.transition_busy: await process_frame
		await process_frame
		report["free_drive_return"]=flow.current_state==&"free_drive" and activity.competition==null and world.get_children().filter(func(n):return n is CharacterBody3D).size()==1 and world.player.vehicle_profile==selected
		report["passed"]=report["passed"] and report["restart_clean"] and report["menu_return"] and report["free_drive_race"] and report["free_drive_return"]
		FileAccess.open("res://.local/artifacts/d3_lifecycle_validation.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
		print("D3_LIFECYCLE ",JSON.stringify(report))
	elif is_instance_valid(competition):
		competition.dispose()
		activity.competition=null
	DirAccess.remove_absolute(ProjectSettings.globalize_path(flow.settings_path))
	quit(0 if report["passed"] else 1)

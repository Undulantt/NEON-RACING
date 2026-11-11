extends SceneTree
# Test driver only: no rival or runtime autopilot is added to the game.
var flow: Node
var circuit_id := ""
var circuit_test := false
func _initialize() -> void: run.call_deferred()
func run() -> void:
	await process_frame
	flow = root.get_node("GameFlow")
	flow.settings_path = "res://tests/.d2_drive_settings.cfg"
	circuit_test = "--test-circuit" in OS.get_cmdline_user_args()
	if circuit_test:
		var worker := Thread.new()
		var preparation := preload("res://scripts/navigation/WorldPreparation.gd").new()
		worker.start(preparation.run)
		while worker.is_alive(): await process_frame
		var prepared: Dictionary = worker.wait_to_finish()
		circuit_id = "test_drive_"+Crypto.new().generate_random_bytes(8).hex_encode()
		var store = preload("res://scripts/racing/RaceStore.gd")
		var circuit: Dictionary = store.create(prepared["graph"],["6195649062","313407104","313407631"],circuit_id,"Circuito físico de prueba OSM",30.0,false,"circuit",2)
		var error: String = store.save(circuit,prepared["graph"])
		if not error.is_empty(): push_error(error);quit(1);return
		flow.definition["default_race_id"] = circuit_id
	change_scene_to_file(flow.definition["menu_scene"])
	await process_frame
	flow.show_screen(&"play_menu")
	flow.choose_mode(&"race")
	flow.select_vehicle("COMET")
	flow.start_selected()
	var deadline := Time.get_ticks_msec()+90000
	while flow.current_state != &"race" or flow.transition_busy:
		if Time.get_ticks_msec()>deadline: quit(1);return
		await process_frame
	var world=current_scene
	var car=world.player
	car.external_control=true
	var activity=world.race_activity
	var session=activity.session
	var start_recoveries: int=car.recovery_count
	var peak:=0.0
	var path_m:=0.0
	var previous:Vector3=car.position
	for frame in range(36000) if circuit_test else range(18000):
		await physics_frame
		if session.phase=="finished":break
		if session.phase!="running":continue
		var gate:Dictionary=session.definition["checkpoints"][session.next_checkpoint]
		var at:=Vector2(gate["position_xz"][0],gate["position_xz"][1])
		var forward:=Vector2(gate["forward_xz"][0],gate["forward_xz"][1])
		var target:=at+forward*(0.1 if circuit_test else 5.0)
		var local:Vector3=car.global_basis.inverse()*(Vector3(target.x,car.position.y,target.y)-car.position)
		var angle:=atan2(local.x,-local.z)
		var cruise := 8.0 if circuit_test else 14.0
		if circuit_test:
			var gates: Array=session.definition["checkpoints"]
			var following: Dictionary=gates[(session.next_checkpoint+1)%gates.size()]
			var next_forward:=Vector2(following["forward_xz"][0],following["forward_xz"][1])
			var turn_soon: bool=forward.dot(next_forward)<0.85 and Vector2(car.position.x,car.position.z).distance_to(at)<18
			if turn_soon or absf(angle)>0.2: cruise=2.5
		car.set_controls(1.0 if car.speed_mps<cruise else 0.0,clampf(angle*1.6,-1,1),false,false,0.8 if car.speed_mps>cruise+1 else 0.0)
		peak=maxf(peak,car.speed_mps)
		path_m+=previous.distance_to(car.position)
		previous=car.position
		if frame%1800==0:print("D2_DRIVE_PROGRESS ",session.next_checkpoint," ",car.position," speed ",car.speed_mps)
	var report:={"passed":session.phase=="finished" and car.recovery_count==start_recoveries,"phase":session.phase,"checkpoints":session.next_checkpoint,"completed_laps":session.completed_laps,"elapsed_seconds":session.elapsed,"peak_speed_mps":peak,"driven_m":path_m,"recoveries":car.recovery_count-start_recoveries,"position":[car.position.x,car.position.y,car.position.z]}
	if "--capture-d2" in OS.get_cmdline_user_args():
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://docs/evidence/laps_physical_results.png" if circuit_test else "res://docs/evidence/d2_physical_results.png")
	FileAccess.open("res://docs/laps_physical_drive.json" if circuit_test else "res://docs/phase_d2_physical_drive.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(flow.settings_path))
	if not circuit_id.is_empty(): DirAccess.remove_absolute(ProjectSettings.globalize_path("user://races/"+circuit_id+".json"))
	print("D2_PHYSICAL_DRIVE ",JSON.stringify(report))
	quit(0 if report["passed"] else 1)

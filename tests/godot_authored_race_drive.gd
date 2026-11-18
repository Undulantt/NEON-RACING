extends SceneTree
func _initialize() -> void:run.call_deferred()
func run() -> void:
	await process_frame
	var flow=root.get_node("GameFlow")
	var id:="arracon_malecon"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--race-id="):id=argument.trim_prefix("--race-id=")
	if id not in ["arracon_malecon","circuito_forjadores"]:quit(1);return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://tests/authored_drive"))
	flow.settings_path="user://tests/authored_drive/"+id+".cfg";flow.set_graphics("fps_limit",0)
	change_scene_to_file(flow.definition["menu_scene"]);await process_frame
	flow.show_screen(&"play_menu");flow.choose_mode(&"race");flow.select_vehicle("VECTOR");flow.start_selected();flow.select_race(id);flow.launch_selected_race()
	while flow.transition_busy:await process_frame
	if flow.current_state!=&"race":print("AUTHORED_LOAD_FAILURE ",flow.navigation_error);quit(1);return
	var world=current_scene;var activity=world.race_activity;var competition=activity.competition
	var driver:=preload("res://scripts/racing/RivalDriver.gd").new()
	var settings: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://config/rivals.json"))
	driver.configure(world.player,activity.session,"balanced",settings["profiles"]["balanced"],competition.trajectory);driver.participants=[world.player]+competition.rivals
	var first_place: int=competition.player_place();var seconds:=0.0
	for tick in range(60000):
		await physics_frame;driver.update(1.0/60);seconds=tick/60.0
		if tick%3600==0:
			var rows: Array=[]
			for racer in competition.racers:rows.append({"name":racer["name"],"cp":racer["session"].next_checkpoint,"phase":racer["session"].phase,"state":racer["driver"].state if racer["driver"]!=null else driver.state})
			print("AUTHORED_SAMPLE ",id," ",seconds," ",JSON.stringify(rows))
		if competition.racers.all(func(r):return r["session"].phase=="finished"):break
	var results: Array=[]
	for racer in competition.racers:results.append({"name":racer["name"],"phase":racer["session"].phase,"checkpoints":racer["session"].next_checkpoint,"elapsed":racer["session"].elapsed,"teleports":racer["car"].recovery_count})
	var report:={"passed":first_place==6 and competition.racers.all(func(r):return r["session"].phase=="finished" and r["car"].recovery_count==0),"race_id":id,"seconds":seconds,"first_place":first_place,"racers":results}
	FileAccess.open("res://.local/artifacts/authored_drive_"+id+".json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("AUTHORED_DRIVE_REPORT ",JSON.stringify(report))
	flow.return_to_main_menu()
	while flow.transition_busy:await process_frame
	await flow.menu_audio.shutdown();quit(0 if report["passed"] else 1)

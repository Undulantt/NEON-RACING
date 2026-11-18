extends SceneTree
const HUD=preload("res://scripts/ui/RaceHUD.gd")
var flow: Node
var checks:=0
var failures: Array=[]
var capture:=false
var hashes: Dictionary={}
var geometry: Array=[]

func _initialize() -> void:run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks+=1
	if not ok:failures.append(message);push_error(message)

func state(value: StringName) -> bool:
	var deadline:=Time.get_ticks_msec()+120000
	while flow.current_state!=value or flow.transition_busy:
		if Time.get_ticks_msec()>deadline:check(false,"Load timeout "+str(value));return false
		await process_frame
	for i in range(3):await process_frame
	return true

func shot(name: String, hud: Control) -> void:
	for i in range(4):await process_frame
	geometry.append({"view":name,"time":str(hud.time_label.get_global_rect()),"lap":str(hud.lap_label.get_global_rect()),"position":str(hud.position_label.get_global_rect()),"viewport":str(root.get_visible_rect())})
	if not capture:return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.local/artifacts/evidence/race_hud_"+name+".png")

func finish() -> void:
	for path in hashes:check(FileAccess.get_sha256(path)==hashes[path],"Unchanged driving/race/map source "+path)
	var report:={"passed":failures.is_empty(),"checks":checks,"failures":failures,"rendered":capture,"geometry":geometry}
	FileAccess.open("res://.local/artifacts/race_hud_validation.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("RACE_HUD_REPORT ",JSON.stringify(report))
	await flow.menu_audio.shutdown()
	quit(0 if failures.is_empty() else 1)

func run() -> void:
	await process_frame
	capture="--capture-race-hud" in OS.get_cmdline_user_args()
	flow=root.get_node("GameFlow")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://tests/race_hud"))
	flow.settings_path="user://tests/race_hud/settings.cfg"
	if capture:root.mode=Window.MODE_WINDOWED;root.size=Vector2i(1280,720)
	for path in ["res://scripts/driving/ArcadeCar.gd","res://scripts/racing/RaceSession.gd","res://scripts/racing/RaceCompetition.gd","res://config/vehicles/comet.json","res://data/processed/la_paz_map.json"]:hashes[path]=FileAccess.get_sha256(path)
	check(HUD.format_time(0)=="00.00.00","Clock starts at zero")
	check(HUD.format_time(61.25)=="01.01.25","Clock shows minutes, seconds, hundredths")
	check(HUD.format_time(3599.5)=="59.59.50","Clock handles long races")
	check(HUD.format_time(-1)=="00.00.00" and HUD.format_time(NAN)=="00.00.00","Clock rejects invalid negative/nonfinite display values")
	change_scene_to_file(flow.definition["menu_scene"]);await process_frame
	flow.show_screen(&"play_menu");flow.choose_mode(&"race");flow.select_vehicle("COMET");flow.start_selected()
	if flow.current_state==&"race_select":flow.launch_selected_race()
	if not await state(&"race"):await finish();return
	var world=current_scene;var activity=world.race_activity;var hud=activity.race_hud
	world.player.external_control=true;world.player.set_controls(0,0,true)
	check(hud.visible,"Race displays the new HUD")
	check(hud.time_label.text=="Tiempo: 00.00.00","Countdown does not advance official elapsed time")
	check(hud.mouse_filter==Control.MOUSE_FILTER_IGNORE and hud.block.mouse_filter==Control.MOUSE_FILTER_IGNORE,"HUD cannot intercept driving input")
	await shot("countdown",hud)
	var deadline:=Time.get_ticks_msec()+10000
	while activity.session.phase=="countdown":
		if Time.get_ticks_msec()>deadline:check(false,"Countdown timeout");await finish();return
		await physics_frame
	for i in range(30):await physics_frame
	hud.refresh()
	check(activity.session.elapsed>0 and hud.time_label.text=="Tiempo: "+HUD.format_time(activity.session.elapsed),"Time label reads official elapsed time")
	check(hud.lap_label.text=="Vuelta:  1/%d"%activity.session.total_laps,"Lap count comes from the race definition")
	check(hud.position_label.text=="Pos: %d/%d"%[activity.competition.player_place(),activity.competition.racers.size()],"Position uses official standings and real participant count")
	check(not activity.info.visible and activity.info.text.is_empty(),"Legacy classification block is removed during racing")
	check(world.hud.instruments.minimap.visible and world.hud.speed_label.visible,"Existing minimap and speedometer remain available")
	await shot("running",hud)
	var elapsed: float=activity.session.elapsed
	world.hud.set_pause(true);await create_timer(.2).timeout
	check(not hud.visible and is_equal_approx(activity.session.elapsed,elapsed),"Pause hides race overlay and freezes its official clock")
	world.hud.set_pause(false);await process_frame
	var completed: int=activity.session.completed_laps;var laps: int=activity.session.total_laps
	activity.session.completed_laps=1;activity.session.total_laps=3;hud.refresh()
	check(hud.lap_label.text=="Vuelta:  2/3","HUD reflects later laps without hardcoded race values")
	activity.session.completed_laps=completed;activity.session.total_laps=laps
	var type: String=activity.definition["type"];activity.definition["type"]="sprint";hud.refresh()
	check(hud.lap_label.text=="Sin vueltas","Sprint explicitly shows no laps")
	activity.definition["type"]=type;hud.refresh()
	if capture:
		for dimensions in [Vector2i(1920,1080),Vector2i(1600,720),Vector2i(960,720)]:
			root.size=dimensions
			for i in range(6):await process_frame
			check(is_equal_approx(hud.time_label.global_position.x,root.get_visible_rect().size.x-246),"Timer stays right anchored "+str(dimensions))
			check(root.get_visible_rect().encloses(hud.lap_label.get_global_rect()) and root.get_visible_rect().encloses(hud.position_label.get_global_rect()),"Lap and place stay within viewport "+str(dimensions))
			await shot("%dx%d"%[dimensions.x,dimensions.y],hud)
		root.size=Vector2i(1280,720)
	activity.request_recovery("HUD fixture")
	for i in range(3):await physics_frame
	check(activity.recovering and activity.info.visible and not activity.info.text.is_empty(),"Recovery status remains visible")
	activity.cancel_recovery()
	flow.return_to_main_menu();if not await state(&"main_menu"):await finish();return
	flow.show_screen(&"play_menu");flow.choose_mode(&"free_drive");flow.start_selected()
	if flow.current_state==&"race_select":flow.launch_selected_race()
	if not await state(&"free_drive"):await finish();return
	check(not current_scene.race_activity.race_hud.visible,"Free drive does not show race counters")
	check(current_scene.player.vehicle_profile=="COMET","Navigation retains the selected vehicle")
	await finish()

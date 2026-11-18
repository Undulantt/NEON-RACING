extends SceneTree
const Store=preload("res://scripts/passport/PassportStore.gd")
var flow: Node
var checks:=0
var failures: Array=[]
var measurements: Array=[]
var capture:=false
var performance: Dictionary={}

func _initialize() -> void:run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks+=1
	if not ok:failures.append(message);push_error(message)

func state(value: StringName) -> bool:
	var deadline:=Time.get_ticks_msec()+120000
	while flow.current_state!=value or flow.transition_busy:
		if Time.get_ticks_msec()>deadline:check(false,"Timeout: "+str(value));return false
		await process_frame
	return true

func shot(name: String) -> void:
	if not capture:return
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.local/artifacts/evidence/d4_"+name+".png")

func key(code: Key, ctrl:=false, alt:=false) -> void:
	var event:=InputEventKey.new();event.keycode=code;event.physical_keycode=code;event.pressed=true;event.ctrl_pressed=ctrl;event.alt_pressed=alt
	Input.parse_input_event(event)
	await process_frame
	event=event.duplicate();event.pressed=false;Input.parse_input_event(event)
	await process_frame

func finish() -> void:
	var report:={"passed":failures.is_empty(),"checks":checks,"failures":failures,"positions":measurements,"performance":performance,"rendered":capture,"restart_verification":"--verify-progress" in OS.get_cmdline_user_args()}
	FileAccess.open("res://.local/artifacts/d4_restart.json" if report["restart_verification"] else "res://.local/artifacts/d4_render.json" if capture else "res://.local/artifacts/d4_validation.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("D4_REPORT ",JSON.stringify(report));quit(0 if failures.is_empty() else 1)

func run() -> void:
	await process_frame
	if not "--passport-test" in OS.get_cmdline_user_args():check(false,"Tests require isolated --passport-test paths");finish();return
	capture="--capture" in OS.get_cmdline_user_args()
	if "--verify-progress" in OS.get_cmdline_user_args():
		var saved=Store.new();saved.progress_path="user://tests/d4/progress.json";saved.load_progress()
		check(saved.discovered.size()==3,"Three discoveries survive a new Godot process");finish();return
	for name in ["progress","catalog","draft","backup"]:
		for suffix in [".json",".json.bak",".json.tmp"]:DirAccess.remove_absolute(ProjectSettings.globalize_path("user://tests/d4/"+name+suffix))
	flow=root.get_node("GameFlow")
	flow.settings_path="user://tests/d4/settings.cfg"
	change_scene_to_file(flow.definition["menu_scene"]);await process_frame
	flow.show_screen(&"play_menu");flow.choose_mode(&"free_drive");flow.select_vehicle("COMET");flow.start_selected()
	if flow.current_state==&"race_select":flow.launch_selected_race()
	if not await state(&"free_drive"):finish();return
	var world=current_scene;var passport=world.passport;var car=world.player
	check(passport.active.size()==3 and passport.count()==0,"Exactly three initially unknown POIs")
	check(Store.validate(passport.catalog,flow.road_graph,world.map_data["metadata"]).is_empty(),"Shipped catalog validated against the current road network")
	await key(KEY_P);check(is_instance_valid(passport.book) and paused,"P opens passport and pauses simulation")
	await shot("unknown");await key(KEY_ESCAPE);check(not paused and not is_instance_valid(passport.book),"Esc closes passport without leaving game paused")
	world.hud.set_pause(true);world.hud.free_pause.menu_buttons["passport"].pressed.emit()
	check(is_instance_valid(passport.book),"Pause menu opens passport")
	var cancel:=InputEventJoypadButton.new();cancel.button_index=JOY_BUTTON_B;cancel.pressed=true;Input.parse_input_event(cancel)
	await process_frame
	check(not is_instance_valid(passport.book) and paused and world.hud.free_pause.visible,"Gamepad cancel closes passport and returns to the paused map")
	cancel=cancel.duplicate();cancel.pressed=false;Input.parse_input_event(cancel)
	world.hud.set_pause(false)
	var original_mode: StringName=flow.current_state;flow.current_state=&"race"
	check(not passport.open_book() and not passport.open_editor(),"Passport tools are unavailable during races");flow.current_state=original_mode
	for poi in passport.active:
		var projected:=Store.world_point(poi["latitude"],poi["longitude"],world.map_data["metadata"])
		check(projected.distance_to(Vector2(poi["position_xz"][0],poi["position_xz"][1]))<.02,"Geographic projection matches stored position: "+poi["id"])
		var p: Vector2=poi["interaction_xz"];var road: Dictionary=flow.road_graph.roads[poi["activation"]["road_id"]]
		var a: Vector2=flow.road_graph.nodes[str(road["from"])];var b: Vector2=flow.road_graph.nodes[str(road["to"])];var f: Vector2=(b-a).normalized()
		await world.prepare_at({"position_xz":[p.x,p.y],"forward_xz":[f.x,f.y]})
		car.driving_enabled=true
		for i in range(15):await physics_frame
		check(car.safe_road_transform(car.global_transform),"Accessible full-car asphalt footprint: "+poi["id"])
		check(passport.eligible(poi,true),"Stopped grounded car can interact: "+poi["id"])
		for profile in ["VECTOR","COMET","APEX"]:
			check(car.apply_vehicle_profile(profile) and car.safe_road_transform(car.global_transform),"Accessible with "+profile+": "+poi["id"])
		car.apply_vehicle_profile("COMET")
		check(not passport.store.discovered.has(poi["id"]),"Approaching alone does not discover: "+poi["id"])
		car.set_physics_process(false);var old_speed: float=car.speed_mps;car.speed_mps=20
		check(not passport.discover(poi["id"]),"High speed blocks discovery: "+poi["id"])
		car.speed_mps=old_speed;car.set_physics_process(true)
		await process_frame;await key(KEY_E)
		check(passport.store.discovered.has(poi["id"]),"Explicit E registers: "+poi["id"])
		var stamp=passport.store.discovered.get(poi["id"])
		check(not passport.discover(poi["id"]) and passport.store.discovered.get(poi["id"])==stamp,"Duplicate discovery does not overwrite: "+poi["id"])
		measurements.append({"id":poi["id"],"position":str(car.position),"street":road["street_name"],"safe":car.safe_road_transform(car.global_transform)})
	await key(KEY_P);await shot("complete");await key(KEY_ESCAPE)
	check(passport.count()==3,"Passport reaches 3/3")
	var saved=Store.new();saved.progress_path=passport.store.progress_path;saved.load_progress()
	check(saved.discovered.size()==3,"Persistent progress is readable independently")
	await key(KEY_I,true,true)
	check(is_instance_valid(passport.editor) and paused,"Ctrl+Alt+I opens developer editor")
	if is_instance_valid(passport.editor):
		var editor=passport.editor;editor.select(2);check(editor.test_zone(),"Developer validates streamed road zone without teleport")
		await shot("editor")
		editor.save_draft();check(not Store.read(passport.draft_path).is_empty(),"Developer draft saved separately")
		editor.new_draft();check(editor.draft["pois"].size()==4 and not editor.enabled.button_pressed,"New manual POI starts as inactive unverified draft")
		editor.save_draft();editor.load_draft();check(editor.draft["pois"].size()==4,"Incomplete extra draft survives save/load")
		check(editor.commit(passport.local_catalog_path),"Three active POIs plus inactive draft can be applied locally")
		editor.select(3);editor.enabled.button_pressed=true
		check(not editor.commit(passport.local_catalog_path),"Unverified blank POI cannot be activated")
		check(passport.count()==3,"Editing preserves stable-ID progress")
		await key(KEY_ESCAPE)
		check(not paused,"Closing editor restores driving")
	var start:=Time.get_ticks_usec()
	for i in range(5000):passport._process(1.0/60)
	performance["passport_controller_mean_ms"]=float(Time.get_ticks_usec()-start)/5000000.0
	performance["controller_samples"]=5000
	performance["marker_meshes"]=passport.markers.size()
	check(passport.markers.all(func(marker):return marker.get_child_count()==0),"POI markers add no collision bodies")
	if capture:
		for enabled in [false,true]:
			passport.set_process(enabled)
			if not enabled:
				for marker in passport.markers:marker.hide()
			for i in range(30):await process_frame
			var times: Array=[]
			var previous:=Time.get_ticks_usec()
			for i in range(120):
				await process_frame
				var now:=Time.get_ticks_usec();times.append(float(now-previous)/1000.0);previous=now
			times.sort()
			performance["enabled" if enabled else "disabled"]={"frame_median_ms":times[60],"frame_p95_ms":times[114],"frames":120}
		await shot("driving")
	var bad: Dictionary=passport.catalog.duplicate(true);bad["pois"][1]["id"]=bad["pois"][0]["id"]
	check(not Store.validate(bad,flow.road_graph,world.map_data["metadata"]).is_empty(),"Duplicate IDs are rejected")
	bad=passport.catalog.duplicate(true);var extra: Dictionary=bad["pois"][0].duplicate(true);extra["id"]="fourth";bad["pois"].append(extra)
	check(not Store.validate(bad,flow.road_graph,world.map_data["metadata"]).is_empty(),"Fourth active POI rejected in D.4")
	var backup=Store.new();backup.progress_path="user://tests/d4/backup.json";backup.register("historic_unknown_id");backup.register("poi_001")
	FileAccess.open(backup.progress_path,FileAccess.WRITE).store_string("broken JSON")
	backup.load_progress();check(backup.discovered.has("historic_unknown_id"),"Corrupt main progress recovers backup and retains unknown historical IDs")
	flow.return_to_main_menu();if not await state(&"main_menu"):finish();return
	flow.show_screen(&"play_menu");flow.choose_mode(&"free_drive");flow.start_selected()
	if flow.current_state==&"race_select":flow.launch_selected_race()
	if not await state(&"free_drive"):finish();return
	check(current_scene.passport.count()==3,"Progress survives menu and world recreation")
	check(current_scene.player.vehicle_profile=="COMET","Selected vehicle is retained")
	finish()

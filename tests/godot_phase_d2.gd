extends SceneTree
const Store = preload("res://scripts/racing/RaceStore.gd")
const Session = preload("res://scripts/racing/RaceSession.gd")
var flow: Node
var checks := 0
var failures: Array = []
var metrics: Dictionary = {}
var capture := false
var original_path := ""
var fixture_id := ""

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)

func wait_state(state: StringName) -> bool:
	var deadline := Time.get_ticks_msec()+120000
	while flow.current_state != state or flow.transition_busy:
		if Time.get_ticks_msec() > deadline:
			check(false,"Timeout esperando "+str(state)+": "+flow.navigation_error)
			return false
		await process_frame
	return true

func frames(n: int) -> void:
	for i in range(n): await process_frame

func shot(name: String) -> void:
	if not capture: return
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://docs/evidence/d2_"+name+".png")

func finish() -> void:
	flow.settings_path = original_path
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://races/"+fixture_id+".json"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path("res://data/races/"+fixture_id+".json"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path("res://tests/.d2_settings.cfg"))
	var report := {"passed":failures.is_empty(),"checks":checks,"failures":failures,"metrics":metrics}
	FileAccess.open("res://docs/phase_d2_validation_render.json" if capture else "res://docs/phase_d2_validation.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("PHASE_D2_REPORT ",JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)

func run() -> void:
	await process_frame
	flow = root.get_node("GameFlow")
	fixture_id = "test_d2_"+Crypto.new().generate_random_bytes(8).hex_encode()
	flow.definition["default_race_id"] = fixture_id
	original_path = flow.settings_path
	flow.settings_path = "res://tests/.d2_settings.cfg"
	capture = "--capture-d2" in OS.get_cmdline_user_args()
	change_scene_to_file(flow.definition["menu_scene"])
	await frames(3)
	flow.show_screen(&"play_menu")
	flow.choose_mode(&"free_drive")
	flow.select_vehicle("COMET")
	flow.start_selected()
	await frames(2)
	await shot("loading")
	if not await wait_state(&"free_drive"):
		finish(); return
	metrics["initial_loading"] = flow.last_loading_metrics.duplicate()
	check(flow.last_loading_metrics["frames"] > 10,"Loading indicator rendered frames during real work")
	var world = current_scene
	check(world.world_ready and world.player.driving_enabled,"World ready before player control")
	check(world.player.safe_road_transform(world.player.global_transform),"Initial spawn has road collisions")
	check(flow.road_graph.nodes.size()>10000,"Reused full offline OSM graph")
	check(world.city_manager.is_physics_processing(),"Urban streaming resumed after staged loading")
	var key := InputEventKey.new()
	key.keycode = KEY_E
	key.ctrl_pressed = true
	key.alt_pressed = true
	key.pressed = true
	Input.parse_input_event(key)
	await frames(1)
	key.pressed = false
	Input.parse_input_event(key)
	await frames(2)
	var editor = world.race_activity.editor
	check(is_instance_valid(editor),"Development editor opens from free drive")
	editor.id_field.text = fixture_id
	editor.title_field.text = "Malecón · Sprint de desarrollo"
	var graph = flow.road_graph
	# Existing verified Malecón node chain; no invented geographic coordinates.
	var start: String = graph.nearest(Vector2(113,-251),100)
	var via: String = "313406276"
	var end: String = "6195830555"
	editor.add_map_point(graph.nodes[start])
	editor.add_map_point(graph.nodes[via])
	editor.add_map_point(graph.nodes[end])
	check(not editor.draft.is_empty(),"Editor traces connected directed roadway through mandatory via")
	if editor.draft.is_empty(): finish(); return
	check(Store.validate(editor.draft,graph).is_empty(),"Generated route passes topology and geometry validation")
	check(editor.draft["checkpoints"].size()>15,"Generated gates cover route intersections and long sections")
	editor.publish()
	var race := Store.load_id(fixture_id)
	check(not race.is_empty(),"Editor publishes permanent playable JSON content")
	check(Store.validate(race,graph).is_empty(),"Saved JSON round trip validates")
	editor.spacing.value=20
	check(editor.draft["checkpoints"].size()>race["checkpoints"].size(),"Editor adjusts generated checkpoint spacing")
	editor.spacing.value=30
	metrics["race_distance_m"] = race["distance_m"]
	metrics["checkpoints"] = race["checkpoints"].size()
	await shot("editor")
	editor.save_local()
	check(FileAccess.file_exists("user://races/"+fixture_id+".json"),"Editor saves local independent content")
	editor.load_draft()
	check(editor.anchors.size()==3,"Editor loads saved anchor sequence")
	editor.edit_mode.select(1)
	editor.selected.value=1
	editor.add_map_point(graph.nodes[via])
	check(editor.anchors[1]==via,"Editor supports moving selected route point")
	editor.edit_mode.select(2)
	editor.selected.value=1
	editor.add_map_point(graph.nodes[via])
	check(editor.anchors.size()==2,"Editor deletes selected point")
	editor.anchors = race["anchors"].duplicate()
	editor.rebuild()
	editor.close()
	await frames(2)
	# Invalid content and map changes are rejected.
	var bad := race.duplicate(true)
	bad["map_sha256"]="changed"
	check(not Store.validate(bad,graph).is_empty(),"Changed map version rejected")
	bad=race.duplicate(true);bad["edges"][0]["road_id"]="missing"
	check(not Store.validate(bad,graph).is_empty(),"Missing road rejected")
	bad=race.duplicate(true);bad["checkpoints"][0]["position_xz"]=[0,0]
	check(not Store.validate(bad,graph).is_empty(),"Off-road checkpoint tampering rejected")
	check(not Store.safe_id("../outside"),"Race filenames reject path traversal")
	for edge in graph.edges.values():
		var r: Dictionary=graph.roads[edge["road_id"]]
		if not r.get("oneway",false): continue
		var ref={"road_id":r["id"],"from":edge["to"],"to":edge["from"],"wrong_way":true}
		check(not graph.validate_refs([ref],false).is_empty(),"One-way reverse requires explicit exception")
		check(graph.validate_refs([ref],true).is_empty(),"Fictional wrong-way exception is explicit and valid")
		break
	# Independent crossing tests: wrong order, direction, lateral/height, teleport.
	var session=Session.new()
	session.begin(race)
	var gate: Dictionary=race["checkpoints"][0]
	var p:=Vector2(gate["position_xz"][0],gate["position_xz"][1])
	var f:=Vector2(gate["forward_xz"][0],gate["forward_xz"][1])
	session.advance(p-f,p-f,3.1)
	check(session.phase=="running","Countdown releases race")
	session.advance(p+f,p-f,0.1)
	check(session.next_checkpoint==0,"Reverse crossing rejected")
	session.advance(p-f+f.orthogonal()*100,p+f+f.orthogonal()*100,0.1)
	check(session.next_checkpoint==0,"Lateral crossing rejected")
	session.advance(p-f,p+f,0.1,false)
	check(session.next_checkpoint==0,"Invalid height crossing rejected")
	session.advance(p-f*100,p+f*100,0.016)
	check(session.next_checkpoint==0,"Teleport crossing rejected")
	var last: Dictionary=race["checkpoints"][-1]
	var finish_p:=Vector2(last["position_xz"][0],last["position_xz"][1])
	var finish_f:=Vector2(last["forward_xz"][0],last["forward_xz"][1])
	session.advance(finish_p-finish_f,finish_p+finish_f,0.1)
	check(session.phase=="running" and session.next_checkpoint==0,"Finish cannot skip mandatory gates")
	# Menu origin loads same world and actual selected vehicle.
	flow.return_to_main_menu()
	if not await wait_state(&"main_menu"): finish();return
	flow.definition["default_race_id"]=fixture_id
	flow.show_screen(&"play_menu");flow.choose_mode(&"race");flow.select_vehicle("APEX");flow.start_selected()
	if not await wait_state(&"race"): finish();return
	world=current_scene
	check(world.player.vehicle_profile=="APEX","Menu race preserves chosen vehicle")
	check(world.race_activity.session.phase=="countdown" and not world.player.driving_enabled,"Player locked during race countdown")
	metrics["race_loading"] = flow.last_loading_metrics.duplicate()
	check(flow.last_loading_metrics["max_gap_ms"] < 1500,"No multi-second loading freeze in integration run")
	await shot("countdown")
	# Use the real controller to drive the first gates, then deterministic swept
	# crossings for the full route. Physical driving verified separately below.
	await frames(200)
	await physics_frame
	check(world.race_activity.session.phase=="running","World countdown reaches running")
	var before: Vector3 = world.player.position
	world.player.external_control = true
	world.player.set_controls(1,0)
	for i in range(60): await physics_frame
	check(world.player.position.distance_to(before)>1 and world.player.speed_mps>1,"Actual selected controller accelerates in race")
	world.player.set_controls(0,0)
	world.player.external_control = false
	var running = world.race_activity.session
	for g in race["checkpoints"]:
		if float(g["distance_m"]) <= running.progress_m: continue
		var at:=Vector2(g["position_xz"][0],g["position_xz"][1])
		var dir:=Vector2(g["forward_xz"][0],g["forward_xz"][1])
		running.advance(at-dir,at+dir,0.1)
	check(flow.current_state==&"results","Ordered valid crossings finish race and show results")
	check(flow.activity_result.get("elapsed_seconds",0)>0,"Results contain measured elapsed time")
	await shot("results_fixture")
	flow.restart_race()
	if not await wait_state(&"race"): finish();return
	check(not is_instance_valid(flow.loading_overlay),"Ready restart avoids unnecessary loading overlay")
	check(world==current_scene and world.race_activity.session.next_checkpoint==0,"Restart reuses world and resets progression")
	flow.cancel_activity()
	if not await wait_state(&"main_menu"): finish();return
	check(root.get_children().filter(func(n:Node):return n is Node3D).is_empty(),"Menu abandonment frees race world")
	# Free-drive entry, confirmation, cancellation, restart and return reuse scene.
	flow.show_screen(&"play_menu");flow.choose_mode(&"free_drive");flow.select_vehicle("VECTOR");flow.start_selected()
	if not await wait_state(&"free_drive"):finish();return
	world=current_scene
	for i in range(2): await physics_frame
	var interact := InputEventKey.new()
	interact.keycode = KEY_E
	interact.pressed = true
	Input.parse_input_event(interact)
	await frames(2)
	interact = InputEventKey.new()
	interact.keycode = KEY_E
	interact.pressed = false
	Input.parse_input_event(interact)
	check(world.race_activity.prompting,"Start marker provides confirmation")
	await shot("confirm")
	world.race_activity.cancel_prompt()
	check(world.player.driving_enabled and not world.race_activity.prompting,"Confirm cancel restores free drive")
	world.race_activity.confirm_start()
	world.race_activity.panel_column.get_child(2).pressed.emit()
	check(flow.race_origin==&"free_drive","Confirmed free-drive race entry without vehicle selection")
	if not await wait_state(&"race"):finish();return
	check(current_scene==world and world.player.vehicle_profile=="VECTOR","Free-drive race reuses world and vehicle")
	flow.restart_race()
	if not await wait_state(&"race"):finish();return
	check(world.get_children().filter(func(n:Node):return n is CharacterBody3D).size()==1,"Repeated races retain only one car")
	var free_session=world.race_activity.session
	free_session.advance(Vector2.ZERO,Vector2.ZERO,3.1)
	for g in race["checkpoints"]:
		var at:=Vector2(g["position_xz"][0],g["position_xz"][1])
		var dir:=Vector2(g["forward_xz"][0],g["forward_xz"][1])
		free_session.advance(at-dir,at+dir,0.1)
	check(flow.current_state==&"results","Free-drive race completion opens results")
	flow.return_from_activity()
	if not await wait_state(&"free_drive"):finish();return
	check(current_scene==world and world.player.vehicle_profile=="VECTOR","Return respects free-drive origin")
	var start_at: Array=race["start"]["position_xz"]
	check(Vector2(world.player.position.x,world.player.position.z).distance_to(Vector2(start_at[0],start_at[1]))<1,"Return near race start")
	check(world.player.safe_road_transform(world.player.global_transform),"Return retains safe collision support")
	check(world.race_activity.session==null and world.race_activity.visuals==null,"Temporary race resources cleaned")
	for i in range(3):
		world.request_race(race["id"])
		if not await wait_state(&"race"):finish();return
		world.hud.set_pause(true)
		check(paused and world.hud.buttons[1].text=="Reiniciar carrera","Race pause exposes restart")
		check(root.gui_get_focus_owner()==world.hud.buttons[0],"Pause receives keyboard/controller focus")
		world.hud.buttons[2].pressed.emit()
		if not await wait_state(&"free_drive"):finish();return
		check(not paused and current_scene==world,"Pause abandonment returns to same free-drive world")
	await shot("free_return")
	flow.return_to_main_menu()
	if not await wait_state(&"main_menu"):finish();return
	finish()

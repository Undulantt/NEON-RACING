extends SceneTree
# Real OSM cycle near the current Malecón sector. No shipping content is modified.
const CYCLE := ["6195649062","6195649058","313406908","6195836154","313407105","313407104","313407662","6195649072","6195649073","6195649074","313407631","11744778480","11744778491","313406905","6195649059"]
const Store = preload("res://scripts/racing/RaceStore.gd")
var checks := 0
var failures: Array = []
var metrics := {}
var flow: Node
var saved_id := ""
var capture := false

func _initialize() -> void: run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func state(value: StringName) -> bool:
	var deadline := Time.get_ticks_msec()+60000
	while flow.current_state != value or flow.transition_busy:
		if Time.get_ticks_msec()>deadline:
			check(false,"Timed out waiting for "+str(value)+": "+flow.navigation_error)
			return false
		await process_frame
	return true

func shot(name: String) -> void:
	if not capture: return
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://docs/evidence/laps_"+name+".png")

func cross_lap(session: RefCounted) -> void:
	for gate in session.definition["checkpoints"]:
		var p := Vector2(gate["position_xz"][0],gate["position_xz"][1])
		var f := Vector2(gate["forward_xz"][0],gate["forward_xz"][1])
		session.advance(p-f*0.1,p+f*0.1,0.1)

func finish() -> void:
	if not saved_id.is_empty(): DirAccess.remove_absolute(ProjectSettings.globalize_path(Store.LOCAL+saved_id+".json"))
	var report := {"passed":failures.is_empty(),"checks":checks,"failures":failures,"metrics":metrics,"rendered":capture}
	FileAccess.open("res://docs/editor_laps_validation_render.json" if capture else "res://docs/editor_laps_validation.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("EDITOR_LAPS_REPORT ",JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)

func run() -> void:
	await process_frame
	capture = "--capture-laps" in OS.get_cmdline_user_args()
	flow = root.get_node("GameFlow")
	change_scene_to_file(flow.definition["menu_scene"])
	await process_frame
	flow.show_screen(&"play_menu");flow.choose_mode(&"free_drive");flow.start_selected()
	if not await state(&"free_drive"): finish();return
	var world = current_scene
	world.race_activity.toggle_editor()
	var editor = world.race_activity.editor
	await process_frame
	check(editor.draft.is_empty(),"New draft is initially empty")
	check(editor.notice.text.contains("salida") and not editor.notice.text.contains("compatible"),"Empty draft explains missing start and finish")
	check(editor.write_buttons.all(func(b:Button):return b.disabled),"Invalid draft disables save and test")
	editor.save_local()
	check(not editor.notice.text.contains("compatible"),"Save does not replace draft error with format error")
	editor.test_drive()
	check(is_instance_valid(editor) and flow.current_state==&"free_drive","Testing invalid draft keeps editor open")
	var graph = flow.road_graph
	for node in [CYCLE[0],CYCLE[1]]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = editor.screen(graph.nodes[node])
		event.global_position = event.position
		event.pressed = true
		if DisplayServer.get_name() == "headless": editor._gui_input(event)
		else: Input.parse_input_event(event)
		await process_frame
		event.pressed = false
		if DisplayServer.get_name() == "headless": editor._gui_input(event)
		else: Input.parse_input_event(event)
		await process_frame
	check(editor.anchors.size()==2,"Map click input places road points")
	check(not editor.draft.is_empty(),"Two map clicks create a savable sprint")

	for i in range(50): check(Store.safe_id("sprint_"+Crypto.new().generate_random_bytes(8).hex_encode()),"Generated IDs remain valid")
	var legacy := Store.load_id(str(flow.definition["default_race_id"]))
	check(Store.validate(legacy,graph).is_empty(),"Existing sprint remains compatible without new lap fields")
	editor.anchors = [CYCLE[0],CYCLE[0]]
	editor.rebuild()
	check(editor.notice.text.contains("mismo nodo"),"Repeated-point error is specific")
	editor.anchors = [CYCLE[0],CYCLE[1]]
	editor.id_field.text = "Mi Carrera!"
	editor.rebuild()
	check(editor.notice.text.contains("ID inválido"),"Invalid ID error explains allowed characters")
	saved_id = "test_laps_"+Crypto.new().generate_random_bytes(8).hex_encode()
	editor.id_field.text = saved_id
	editor.title_field.text = ""
	editor.rebuild()
	check(editor.notice.text.contains("nombre"),"Empty name error is specific")
	editor.title_field.text = "Circuito de prueba OSM"
	editor.rebuild()
	check(editor.draft["type"]=="sprint" and editor.draft["laps"]==0,"Default is explicitly without laps")
	editor.race_kind.select(1)
	editor.race_kind.item_selected.emit(1)
	check(editor.laps_count.editable,"Circuit enables lap selector")
	check(editor.notice.text.contains("3 puntos"),"Circuit explains minimum route requirements")
	editor.anchors = [CYCLE[0],CYCLE[5],CYCLE[10]]
	editor.laps_count.value = 2
	editor.rebuild()
	var circuit: Dictionary = editor.draft.duplicate(true)
	check(not circuit.is_empty(),"Real OSM circuit is generated")
	if circuit.is_empty(): finish();return
	check(circuit["type"]=="circuit" and circuit["laps"]==2,"Configured type and lap count reach definition")
	check(circuit["edges"][0]["from"]==circuit["edges"][-1]["to"],"Circuit closes through real connected roads")
	check(is_equal_approx(circuit["distance_m"],circuit["lap_distance_m"]*2),"Total distance includes every lap")
	check(Store.validate(circuit,graph).is_empty(),"Circuit passes canonical topology validation")
	check(editor.write_buttons.all(func(b:Button):return not b.disabled),"Valid route enables save and test")
	metrics["lap_distance_m"] = circuit["lap_distance_m"]
	metrics["checkpoints_per_lap"] = circuit["checkpoints"].size()
	await shot("editor")
	editor.save_local()
	check(FileAccess.file_exists(Store.LOCAL+saved_id+".json"),"Circuit saves independently of map")
	check(Store.validate(Store.load_id(saved_id),graph).is_empty(),"Saved circuit validates after JSON round trip")
	editor.race_kind.select(0)
	editor.race_kind.item_selected.emit(0)
	editor.load_draft()
	check(editor.race_kind.selected==1 and editor.laps_count.value==2 and editor.laps_count.editable,"Loading restores circuit type and laps")
	var bad := circuit.duplicate(true)
	bad["laps"] = 0
	check(not Store.validate(bad,graph).is_empty(),"Circuit cannot have zero laps")
	bad = circuit.duplicate(true);bad["laps"] = 1.5
	check(not Store.validate(bad,graph).is_empty(),"Fractional lap count rejected")
	bad = circuit.duplicate(true);bad["lap_distance_m"] += 10
	check(not Store.validate(bad,graph).is_empty(),"Tampered lap distance rejected")
	editor.test_drive()
	if not await state(&"race"): finish();return
	check(current_scene==world,"Test reuses same world and car")
	var session = world.race_activity.session
	check(session.total_laps==2 and session.completed_laps==0,"Playable session receives configured laps")
	session.advance(Vector2.ZERO,Vector2.ZERO,3.1)
	cross_lap(session)
	check(session.phase=="running" and session.completed_laps==1,"First lap does not finish a two-lap race")
	check(session.next_checkpoint==0 and session.current_lap()==2,"Next lap rearms ordered checkpoints")
	check(absf(session.remaining()-float(circuit["lap_distance_m"]))<0.5,"Remaining distance includes second lap")
	var gate: Dictionary = circuit["checkpoints"][-1]
	var p := Vector2(gate["position_xz"][0],gate["position_xz"][1])
	var f := Vector2(gate["forward_xz"][0],gate["forward_xz"][1])
	session.advance(p-f*0.1,p+f*0.1,0.1)
	check(session.completed_laps==1 and session.next_checkpoint==0,"Re-crossing finish cannot skip a lap")
	await physics_frame
	await shot("hud")
	cross_lap(session)
	check(flow.current_state==&"results" and session.completed_laps==2,"Race ends only after all configured laps")
	check(flow.activity_result["laps"]==2 and flow.activity_result["lap_times"].size()==2,"Results contain completed laps and per-lap timing")
	check(session.remaining()<0.01,"Finished circuit has zero remaining distance")
	await shot("results_fixture")
	flow.restart_race()
	if not await state(&"race"):finish();return
	check(world.race_activity.session.completed_laps==0 and world.race_activity.session.next_checkpoint==0,"Restart resets lap and checkpoint counters")
	flow.cancel_activity()
	if not await state(&"free_drive"):finish();return
	check(current_scene==world and world.player.driving_enabled,"Abandon returns to same free-drive world")
	flow.return_to_main_menu()
	if not await state(&"main_menu"):finish();return
	finish()

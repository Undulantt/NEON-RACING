extends SceneTree
var failures: Array = []
var checks := 0

func _initialize() -> void: run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func key(ctrl: bool, alt: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_E
	event.ctrl_pressed = ctrl
	event.alt_pressed = alt
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	event.pressed = false
	Input.parse_input_event(event)
	await process_frame

func run() -> void:
	await process_frame
	var flow = root.get_node("GameFlow")
	change_scene_to_file(flow.definition["menu_scene"])
	await process_frame
	flow.show_screen(&"play_menu")
	flow.choose_mode(&"free_drive")
	flow.start_selected()
	var deadline := Time.get_ticks_msec()+60000
	while flow.transition_busy or flow.current_state != &"free_drive":
		if Time.get_ticks_msec()>deadline:
			push_error("World did not load")
			quit(1);return
		await process_frame
	var activity = current_scene.race_activity
	# Stop E interaction from masking the modifier checks near the default marker.
	activity.info.text = ""
	await key(true,false)
	check(not is_instance_valid(activity.editor),"Ctrl+E does not open the editor")
	await key(false,true)
	check(not is_instance_valid(activity.editor),"Alt+E does not open the editor")
	# These incomplete shortcuts may trigger ordinary interaction; cancel it.
	if activity.prompting: activity.cancel_prompt()
	await key(true,true)
	check(is_instance_valid(activity.editor),"Ctrl+Alt+E opens the editor through native input")
	check(not current_scene.player.driving_enabled,"Editor disables driving")
	if is_instance_valid(activity.editor):
		activity.editor.id_field.grab_focus()
		await key(true,true)
		check(not is_instance_valid(activity.editor),"Shortcut closes editor with LineEdit focused")
		check(current_scene.player.driving_enabled,"Closing restores driving")
		await key(true,true)
		check(is_instance_valid(activity.editor),"Editor reopens without stopping the game")
		if is_instance_valid(activity.editor): activity.editor.close()
	var report := {"passed":failures.is_empty(),"checks":checks,"failures":failures,"shortcut":"Ctrl+Alt+E"}
	FileAccess.open("res://docs/race_editor_shortcut_validation.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("EDITOR_SHORTCUT_REPORT ",JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)

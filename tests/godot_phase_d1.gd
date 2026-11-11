extends SceneTree

const Profiles = preload("res://scripts/driving/VehicleProfiles.gd")
var flow: Node
var failures: Array[String] = []
var checks := 0
var metrics := {}
var original_settings: Dictionary = {}
var capture := false

func _initialize() -> void:
	run.call_deferred()

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error("D1_TEST: " + message)

func frames(count: int) -> void:
	for i in range(count):
		await process_frame

func physics(count: int) -> void:
	for i in range(count):
		await physics_frame

func wait_state(state: StringName) -> bool:
	var start := Time.get_ticks_msec()
	while flow.transition_busy or flow.current_state != state:
		await process_frame
		if Time.get_ticks_msec()-start > 45000:
			check(false,"Timed out waiting for %s; state=%s error=%s" % [state,flow.current_state,flow.navigation_error])
			return false
	await frames(2)
	return true

func key(code: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode=code
	event.keycode=code
	event.pressed=true
	Input.parse_input_event(event)
	await frames(1)
	event=InputEventKey.new()
	event.physical_keycode=code
	event.keycode=code
	event.pressed=false
	Input.parse_input_event(event)
	await frames(2)

func pad(button_index: JoyButton) -> void:
	var event:=InputEventJoypadButton.new()
	event.button_index=button_index
	event.pressed=true
	Input.parse_input_event(event)
	await frames(1)
	event=InputEventJoypadButton.new()
	event.button_index=button_index
	event.pressed=false
	Input.parse_input_event(event)
	await frames(2)

func screenshot(name_value: String) -> void:
	if not capture:
		return
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://docs/evidence/d1_"+name_value+".png")

func press(id: String) -> void:
	var shell = current_scene
	check(shell.buttons.has(id),"Missing UI action: "+id)
	if shell.buttons.has(id):
		shell.buttons[id].pressed.emit()

func start_free(id: String) -> bool:
	press("play")
	press("free_drive")
	check(current_scene.current_view==&"vehicle_select","Shared selection opens from free mode")
	check(current_scene.stat_values.size()==24,"Eight statistics for each of three vehicles")
	for vehicle in Profiles.IDS:
		var expected: Dictionary=Profiles.load_profile(vehicle)["stats"]
		for key in expected:
			check(current_scene.stat_values[vehicle+":"+key]==expected[key],"Stats must come directly from profile: "+vehicle+" "+key)
	press("vehicle_"+id)
	check(flow.selected_vehicle_id==id,"Selection must update session")
	await screenshot("vehicles_"+id.to_lower())
	press("continue")
	check(flow.transition_busy and not flow.start_selected(),"Repeated launch is rejected while loading")
	if not await wait_state(&"free_drive"):
		return false
	var world=current_scene
	check(world.runtime_error.is_empty(),"World loaded without errors")
	check(world.player.vehicle_profile==id,"Selected profile reaches production car: "+id)
	check(world.player.config==Profiles.load_profile(id)["config"],"No duplicate/altered physics configuration: "+id)
	world.player.external_control=true
	world.player.set_controls(0,0)
	await physics(35)
	var spawn: Array=flow.definition["free_drive_spawn"]["position_xz"]
	check(Vector2(world.player.position.x,world.player.position.z).distance_to(Vector2(spawn[0],spawn[1]))<2,"Free drive starts at configured Malecon spawn")
	check(world.player.on_asphalt and world.player.is_on_floor(),"Selected car has road support: "+id)
	check(world.player.safe_road_transform(world.player.spawn_transform),"Spawn footprint is clear and on road")
	check(world.road_root!=null and world.city_manager!=null,"Road and urban streaming remain active")
	check(world.night_style!=null,"Existing night style is retained")
	if world.night_style!=null:
		check(absf(float(world.night_style.audio.gains["Engine"])-float(flow.volumes["Engine"]))<0.001,"Menu volume survives delayed night audio setup")
	world.player.set_controls(1,0)
	await physics(60)
	check(world.player.speed_mps>1.0,"Production car accelerates after menu launch: "+id)
	metrics[id]={"profile":world.player.vehicle_profile,"speed_after_1s_mps":world.player.speed_mps,"spawn":[world.player.spawn_transform.origin.x,world.player.spawn_transform.origin.z]}
	world.player.set_controls(0,0)
	world.player.velocity=Vector3.ZERO
	await screenshot("free_"+id.to_lower())
	return true

func leave_world() -> void:
	var world=current_scene
	world.hud.set_pause(true)
	check(paused,"Existing pause freezes scene")
	world.hud.buttons[2].pressed.emit()
	if not await wait_state(&"main_menu"):
		return
	check(not paused,"Return to menu clears pause")
	check(not is_instance_valid(world),"Previous world is released")
	check(flow.world_instance()==null,"No invalid world reference retained")

func run() -> void:
	capture=DisplayServer.get_name()!="headless" and "--capture-d1" in OS.get_cmdline_user_args()
	flow=root.get_node("GameFlow")
	original_settings={"path":flow.settings_path,"volumes":flow.volumes.duplicate(true),"mode":flow.screen_mode,"size":flow.window_size,"vehicle":flow.selected_vehicle_id}
	flow.settings_path="res://tests/.d1_settings.cfg"
	root.content_scale_size=Vector2i(1280,720)
	root.content_scale_mode=Window.CONTENT_SCALE_MODE_VIEWPORT
	root.size=Vector2i(1280,720)
	var shell=load("res://scenes/ui/GameShell.tscn").instantiate()
	root.add_child(shell)
	current_scene=shell
	check(ProjectSettings.get_setting("application/run/main_scene")=="res://scenes/ui/GameShell.tscn","Game starts in real main menu")
	check(flow.current_state==&"main_menu","Initial navigation state")
	check(shell.buttons.has_all(["play","how","options","credits","quit"]),"Every required main-menu button exists")
	check(not flow.select_vehicle("INVENTED"),"Unknown vehicle rejected")
	check(not flow.start_selected(),"Launch without selected mode rejected")
	await frames(2)
	shell.buttons["play"].grab_focus()
	await key(KEY_DOWN)
	check(root.gui_get_focus_owner()==shell.buttons["how"],"Keyboard arrows navigate menu focus")
	await key(KEY_ENTER)
	check(flow.current_state==&"how_to_play","Enter activates focused button")
	await key(KEY_ESCAPE)
	check(flow.current_state==&"main_menu","Escape returns to previous screen")
	shell.buttons["play"].grab_focus()
	await pad(JOY_BUTTON_DPAD_DOWN)
	check(root.gui_get_focus_owner()==shell.buttons["how"],"Gamepad direction navigates focus")
	await pad(JOY_BUTTON_A)
	check(flow.current_state==&"how_to_play","Gamepad activates focused submenu")
	await pad(JOY_BUTTON_B)
	check(flow.current_state==&"main_menu","Gamepad returns from submenu")
	shell.buttons["play"].grab_focus()
	await pad(JOY_BUTTON_A)
	check(flow.current_state==&"play_menu","Gamepad accept works in menus; actual state="+str(flow.current_state))
	await pad(JOY_BUTTON_B)
	check(flow.current_state==&"main_menu","Gamepad back works in menus")
	await screenshot("main")
	press("how")
	check(flow.current_state==&"how_to_play","How-to opens")
	await screenshot("how")
	flow.go_back()
	press("options")
	for bus in ["Master","Music","Engine","Effects"]:
		check(shell.sliders.has(bus),"Real audio bus has a slider: "+bus)
		shell.sliders[bus].value=0.42
		var index:=AudioServer.get_bus_index(bus)
		check(absf(db_to_linear(AudioServer.get_bus_volume_db(index))-0.42)<0.001,"Volume has real effect: "+bus)
	shell.sliders["Master"].value=0
	check(AudioServer.is_bus_mute(AudioServer.get_bus_index("Master")),"Zero master volume mutes")
	shell.sliders["Master"].value=0.65
	flow.load_settings()
	check(absf(float(flow.volumes["Engine"])-0.42)<0.001,"Saved audio settings reload")
	if DisplayServer.get_name()=="headless":
		check(shell.display_choice.disabled,"Unsupported headless display controls disabled")
	else:
		check(flow.set_display("borderless",Vector2i(1280,720)),"Borderless mode supported")
		await frames(3)
		check(root.mode==Window.MODE_WINDOWED and root.borderless,"Borderless has real window effect")
		check(flow.set_display("fullscreen",Vector2i(1280,720)),"Fullscreen supported")
		await frames(3)
		check(root.mode==Window.MODE_FULLSCREEN,"Fullscreen has real window effect")
		flow.set_display("windowed",Vector2i(1280,720))
		await frames(3)
		check(root.mode==Window.MODE_WINDOWED and not root.borderless,"Windowed mode restored")
	await screenshot("options")
	flow.go_back()
	press("credits")
	check(flow.current_state==&"credits","Credits opens")
	check(flow.definition["credits"]["contributors"].is_empty(),"No invented collaborators")
	await screenshot("credits")
	flow.go_back()
	press("play")
	press("race")
	flow.go_back()
	check(flow.current_state==&"play_menu","Back from vehicle selection returns to mode choice")
	flow.go_back()
	# Verify both modes share the exact same profile selection presentation.
	# Missing-content fallback remains covered; playable race contracts live in D.2.
	flow.definition["default_race_id"] = "d1_missing_content_fixture"
	for id in Profiles.IDS:
		press("play")
		press("race")
		check(current_scene.stat_values.size()==24,"Race reuses same comparison table")
		press("vehicle_"+id)
		press("continue")
		check(flow.current_state==&"race_pending" and flow.race_origin==&"menu","Menu race is explicitly pending D.2")
		check(flow.selected_vehicle_id==id and flow.return_destination==&"main_menu","Race selection and return destination preserved")
		check(not current_scene is Node3D,"No fake race or world created")
		await screenshot("race_pending")
		if id=="COMET":
			check(flow.finish_activity({"summary":"Resultado externo de fixture de integración","position":2,"elapsed_seconds":12.345}),"Future race can supply results")
			check(flow.current_state==&"results" and flow.activity_result["position"]==2,"Results view uses supplied data only")
			await screenshot("results_fixture")
		press("activity_return")
		check(flow.current_state==&"main_menu" and flow.selected_vehicle_id==id,"Return from menu race preserves selection")
	if "--ui-only" in OS.get_cmdline_user_args():
		finish();return
	for id in Profiles.IDS:
		if not await start_free(id):
			finish();return
		if id!="APEX":
			await leave_world()
			check(flow.selected_vehicle_id==id,"World-to-menu preserves vehicle")
	# D.2 now owns the integration tests for races originating in free drive.
	await leave_world()
	await frames(5)
	check(root.get_children().filter(func(n:Node): return n is Node3D).is_empty(),"Menu has no leaked world or orphan 3D scene")
	check(flow.navigation_error.is_empty(),"No navigation or persistence errors")
	metrics["user_data_dir"]=OS.get_user_data_dir()
	metrics["race_contract_suite"]="tests/godot_phase_d2.gd"
	finish()

func finish() -> void:
	flow.volumes=original_settings["volumes"]
	for bus in flow.volumes:
		flow.set_volume(bus,flow.volumes[bus],false)
	flow.settings_path=original_settings["path"]
	flow.selected_vehicle_id=original_settings["vehicle"]
	flow.screen_mode=original_settings["mode"]
	flow.window_size=original_settings["size"]
	if FileAccess.file_exists("res://tests/.d1_settings.cfg"):
		DirAccess.remove_absolute(ProjectSettings.globalize_path("res://tests/.d1_settings.cfg"))
	var report:={"passed":failures.is_empty(),"checks":checks,"failures":failures,"metrics":metrics,"rendered":capture}
	FileAccess.open("res://docs/phase_d1_validation_render.json" if capture else "res://docs/phase_d1_validation.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("PHASE_D1_REPORT ",JSON.stringify(report))
	if failures.is_empty() and current_scene!=null and current_scene.has_method("render") and current_scene.buttons.has("quit"):
		current_scene.buttons["quit"].pressed.emit()
	else:
		quit(1 if not failures.is_empty() else 0)

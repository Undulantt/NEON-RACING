extends SceneTree
var flow: Node
var failures: Array=[]
var checks:=0
var capture:=false
var hashes: Dictionary={}
var metrics: Dictionary={}
func _initialize() -> void:run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok:failures.append(label);push_error(label)
func frames(count:=3) -> void:
	for i in range(count):await process_frame
func physics(count:=3) -> void:
	for i in range(count):await physics_frame
func button(index: int,pressed: bool) -> void:
	var event:=InputEventJoypadButton.new();event.device=0;event.button_index=index;event.pressed=pressed;Input.parse_input_event(event)
func tap(index: int) -> void:
	button(index,true);await frames(2);button(index,false);await frames(2)
func axis(index: int,value: float) -> void:
	var event:=InputEventJoypadMotion.new();event.device=0;event.axis=index;event.axis_value=value;Input.parse_input_event(event)
func screenshot(label: String) -> void:
	await frames(5)
	if not capture:return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.local/artifacts/evidence/controls_"+label+".png")
func state(value: StringName) -> bool:
	var deadline:=Time.get_ticks_msec()+120000
	while flow.current_state!=value or flow.transition_busy:
		if Time.get_ticks_msec()>deadline:check(false,"Transition timeout "+str(value));return false
		await process_frame
	return true
func run() -> void:
	await process_frame;flow=root.get_node("GameFlow");capture="--capture-controls" in OS.get_cmdline_user_args()
	flow.settings_path="user://tests/player_controls.cfg";flow.load_settings();flow.set_graphics("fps_limit",0)
	metrics["physical_controllers"]=Input.get_connected_joypads()
	for path in ["res://scripts/driving/ArcadeCar.gd","res://scripts/driving/DrivingAbilities.gd","res://config/vehicles/comet.json","res://data/processed/la_paz_map.json"]:hashes[path]=FileAccess.get_sha256(path)
	change_scene_to_file(flow.definition["menu_scene"]);await frames()
	if capture:root.size=Vector2i(1280,720);await frames()
	flow.show_screen(&"how_to_play");await frames()
	var guide=current_scene.body.get_child(0)
	check(guide.get_script().resource_path=="res://scripts/ui/HowToPlay.gd" and guide.tabs.size()==3,"Visual guide exposes keyboard, gamepad and mechanics")
	for control in guide.CONTROLS:
		if not control[4].is_empty():check(InputMap.has_action(control[4]),"Documented action exists: "+control[4])
	await screenshot("keyboard")
	current_scene.presentation.scroll.scroll_vertical=400;await screenshot("keyboard_lower")
	await tap(JOY_BUTTON_RIGHT_SHOULDER)
	check(guide.page==1 and current_scene.presentation.scroll.scroll_vertical==0,"Mando shoulder button opens controller page and resets scroll")
	check(not guide.connection_text.is_empty(),"Controller page reports actual connection status")
	await screenshot("gamepad")
	current_scene.presentation.scroll.scroll_vertical=600;await screenshot("gamepad_lower")
	await tap(JOY_BUTTON_RIGHT_SHOULDER)
	check(guide.page==2,"Controller can navigate to mechanics without mouse")
	await screenshot("mechanics")
	if capture:
		root.size=Vector2i(960,540);guide.show_page(1);await screenshot("gamepad_960");root.size=Vector2i(1280,720)
	await tap(JOY_BUTTON_B)
	check(flow.current_state==&"main_menu","Gamepad B returns from guide")
	for binding in [[JOY_BUTTON_A,"handbrake"],[JOY_BUTTON_X,"turbo"],[JOY_BUTTON_Y,"recover"],[JOY_BUTTON_START,"pause"],[JOY_BUTTON_B,"interact"],[JOY_BUTTON_RIGHT_SHOULDER,"driving_camera"]]:
		var event:=InputEventJoypadButton.new();event.button_index=binding[0];event.pressed=true
		check(InputMap.event_is_action(event,binding[1]),"Native gamepad button maps to "+binding[1])
	for binding in [[KEY_W,"accelerate"],[KEY_S,"brake_reverse"],[KEY_A,"steer_left"],[KEY_D,"steer_right"],[KEY_SPACE,"handbrake"],[KEY_SHIFT,"turbo"],[KEY_R,"recover"],[KEY_ESCAPE,"pause"],[KEY_E,"interact"],[KEY_V,"driving_camera"],[KEY_M,"audio_toggle"]]:
		var event:=InputEventKey.new();event.physical_keycode=binding[0];event.pressed=true
		check(InputMap.event_is_action(event,binding[1]),"Keyboard binding remains valid: "+binding[1])
	flow.show_screen(&"play_menu");flow.choose_mode(&"free_drive");flow.start_selected()
	if not await state(&"free_drive"):await finish();return
	var world=current_scene;var car=world.player
	axis(JOY_AXIS_TRIGGER_RIGHT,.85);await physics(70)
	check(car.throttle_input>.8 and car.speed_mps>2,"Injected RT axis physically accelerates player car")
	button(JOY_BUTTON_X,true);await physics(3)
	check(car.turbo_active,"Gamepad X engages real turbo ability")
	button(JOY_BUTTON_X,false)
	axis(JOY_AXIS_LEFT_X,.7);await physics(3)
	check(Input.get_axis("steer_left","steer_right")>.5 and car.steering>0,"Positive left stick steers right through actual driving controller")
	axis(JOY_AXIS_LEFT_X,-.7);await physics(15)
	check(Input.get_axis("steer_left","steer_right")<-.5 and car.steering<0,"Negative left stick steers left")
	axis(JOY_AXIS_LEFT_X,0);button(JOY_BUTTON_A,true);await physics(3)
	check(Input.is_action_pressed("handbrake"),"Gamepad A holds handbrake without a GUI conflict")
	button(JOY_BUTTON_A,false);axis(JOY_AXIS_TRIGGER_RIGHT,0);axis(JOY_AXIS_TRIGGER_LEFT,.8);await physics(3)
	check(car.brake_input>.75,"LT reaches the physical braking input")
	axis(JOY_AXIS_TRIGGER_LEFT,0)
	var close_view: bool=world.follow_camera.close_view
	var far_view: bool=world.follow_camera.experimental_far_view
	await tap(JOY_BUTTON_RIGHT_SHOULDER)
	check(world.follow_camera.close_view!=close_view or world.follow_camera.experimental_far_view!=far_view,"RB switches actual chase camera")
	await tap(JOY_BUTTON_START)
	check(paused and world.hud.free_pause.visible,"Start opens free-drive pause/map")
	await tap(JOY_BUTTON_DPAD_DOWN)
	check(root.gui_get_focus_owner()==world.hud.free_pause.menu_buttons["passport"],"D-pad reaches Passport in pause menu")
	await tap(JOY_BUTTON_A)
	check(is_instance_valid(world.passport.book) and root.gui_get_focus_owner()==world.passport.book.list,"A opens Passport with focus in its accessible list")
	await tap(JOY_BUTTON_B)
	check(not is_instance_valid(world.passport.book) and paused and root.gui_get_focus_owner()==world.hud.free_pause.menu_buttons["passport"],"B closes Passport and restores pause focus")
	await tap(JOY_BUTTON_START)
	check(not paused,"Start resumes driving")
	await tap(JOY_BUTTON_Y)
	check(world.race_activity.recovering,"Y starts real recovery countdown")
	var deadline:=Time.get_ticks_msec()+20000
	while world.race_activity.recovering and Time.get_ticks_msec()<deadline:await process_frame
	check(not world.race_activity.recovering and car.driving_enabled,"Controller-triggered recovery completes safely")
	# Start marker is near the normal spawn; relocate through the existing world API.
	world.place_at(flow.definition["free_drive_spawn"]);await physics(5)
	if not world.race_activity.info.text.is_empty():
		await tap(JOY_BUTTON_B);check(world.race_activity.prompting,"B opens nearby race confirmation")
		await tap(JOY_BUTTON_B);check(not world.race_activity.prompting,"B cancels race confirmation without reopening it")
	flow.return_to_main_menu();await state(&"main_menu");await finish()
func finish() -> void:
	for path in hashes:check(FileAccess.get_sha256(path)==hashes[path],"Unchanged physics/profile/map: "+path)
	var report={"passed":failures.is_empty(),"checks":checks,"failures":failures,"metrics":metrics,"rendered":capture}
	FileAccess.open("res://.local/artifacts/player_controls_validation.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("PLAYER_CONTROLS_REPORT ",JSON.stringify(report));await flow.menu_audio.shutdown();quit(0 if failures.is_empty() else 1)

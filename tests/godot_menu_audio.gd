extends SceneTree
var flow: Node
var checks:=0
var failures: Array=[]
var capture:=false

func _initialize() -> void:run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks+=1
	if not ok:failures.append(message);push_error(message)

func frames(n:=3) -> void:
	for i in range(n):await process_frame

func shot(name: String) -> void:
	if not capture:return
	await frames()
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.local/artifacts/evidence/menu_feedback_"+name+".png")

func mouse(at: Vector2, down:=false) -> void:
	var motion:=InputEventMouseMotion.new();motion.position=at;motion.global_position=at;root.push_input(motion,true)
	await frames()
	if down:
		var event:=InputEventMouseButton.new();event.position=at;event.global_position=at;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=true;root.push_input(event,true)
		await frames()

func run() -> void:
	await process_frame
	capture="--capture-menu-audio" in OS.get_cmdline_user_args()
	if capture:
		root.mode=Window.MODE_WINDOWED;root.size=Vector2i(1280,720)
		await frames(5)
	flow=root.get_node("GameFlow")
	var audio=flow.menu_audio
	check(not audio.music.playing,"Music does not start without a menu scene")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://tests/menu_audio"))
	flow.settings_path="user://tests/menu_audio/settings.cfg"
	change_scene_to_file(flow.definition["menu_scene"])
	await frames()
	var shell=current_scene
	await mouse(Vector2(20,700))
	var play: Button=shell.buttons["play"]
	play.grab_focus()
	check(not play.highlighted(),"Automatic keyboard focus does not leave a pink base")
	check(audio.music.playing and audio.music.bus=="Music","Main screen plays the supplied song on Music bus")
	check(audio.music.stream.loop and audio.music.stream.resource_path.is_empty(),"Music loops on an instance-local stream")
	check(audio.gain<.5,"Song starts at reduced volume")
	await shot("normal")
	await create_timer(1.6).timeout
	check(is_equal_approx(audio.gain,1.0),"Music reaches normal level after the fade")
	await mouse(play.get_global_rect().get_center())
	check(play.highlighted(),"Mouse hover activates pink artwork")
	await shot("hover")
	var start_count: int=audio.click_count
	await mouse(play.get_global_rect().get_center(),true)
	check(audio.click_count==start_count+1 and audio.clicks.playing,"One click sound per real button press")
	check(play.pressing,"Held press is transient feedback")
	await shot("pressed")
	var release:=InputEventMouseButton.new();release.position=play.get_global_rect().get_center();release.global_position=release.position;release.button_index=MOUSE_BUTTON_LEFT;release.pressed=false;root.push_input(release,true)
	await frames()
	check(flow.current_state==&"play_menu","Mouse activation still navigates")
	check(audio.clicks.playing,"Click tail survives destruction of the previous button")
	check(audio.music.playing and is_equal_approx(audio.gain,1),"Submenu navigation keeps the same song and gain")
	audio.set_state(&"loading")
	await create_timer(.55).timeout
	check(not audio.music.playing and is_zero_approx(audio.gain),"Music fades out during game loading")
	flow.go_back();await frames()
	check(audio.music.playing and audio.gain<.5,"Returning to main fades in again")
	flow.show_screen(&"options");await frames()
	shell.show_options_page(1)
	await mouse(Vector2(20,700))
	check(shell.presentation.tabs[1].button_pressed and not shell.presentation.tabs[1].highlighted(),"A selected tab keeps the cyan base when not hovered")
	var box: StyleBoxFlat=shell.display_choice.get_theme_stylebox("normal")
	check(box.bg_color.a==0,"Dropdown button backgrounds remain transparent")
	await shot("selected_tab")
	var before: int=audio.click_count
	audio.bind_tree(shell);audio.bind_tree(shell)
	shell.back_button.button_down.emit();shell.back_button.button_up.emit()
	check(audio.click_count==before+1,"Repeated binding cannot duplicate click sounds")
	flow.return_to_main_menu();await frames()
	var starts: int=audio.music_starts
	flow.show_screen(&"options");await frames()
	flow.go_back();await frames()
	await create_timer(.6).timeout
	check(audio.music.playing and audio.music_starts==starts,"Fast back-and-forth does not restart or cut the song")
	await create_timer(1.0).timeout
	check(is_equal_approx(audio.gain,1),"Interrupted fades return smoothly to full gain")
	var time:=Time.get_ticks_msec()
	await audio.shutdown()
	check(not audio.music.playing and Time.get_ticks_msec()-time>=400,"Exit uses a complete fade-out before stopping")
	var report:={"checks":checks,"passed":failures.is_empty(),"failures":failures,"rendered":capture,"fade_in_s":audio.FADE_IN_SECONDS,"fade_out_s":audio.FADE_OUT_SECONDS,"click_duration_s":audio.CLICK.get_length()}
	FileAccess.open("res://.local/artifacts/menu_audio_validation.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("MENU_AUDIO_REPORT ",JSON.stringify(report));quit(0 if failures.is_empty() else 1)

extends SceneTree
var flow: Node
var failures: Array=[]
var checks:=0
var captures:=false
var hashes: Dictionary={}
func _initialize() -> void:run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok:failures.append(label);push_error(label)
func delay(seconds: float) -> void:await create_timer(seconds,true,false,true).timeout
func state(value: StringName) -> bool:
	var deadline:=Time.get_ticks_msec()+120000
	while flow.transition_busy or flow.current_state!=value:
		if Time.get_ticks_msec()>deadline:check(false,"Transition timeout: "+str(value));return false
		await process_frame
	return true
func shot(label: String) -> void:
	if not captures:return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.local/artifacts/evidence/media_"+label+".png")
func run() -> void:
	await process_frame;flow=root.get_node("GameFlow");captures="--capture-media" in OS.get_cmdline_user_args()
	flow.settings_path="user://tests/media_quality.cfg";flow.load_settings();flow.set_graphics("fps_limit",0)
	for path in ["res://scripts/driving/ArcadeCar.gd","res://scripts/driving/DrivingAbilities.gd","res://data/processed/la_paz_map.json"]:hashes[path]=FileAccess.get_sha256(path)
	change_scene_to_file(flow.definition["menu_scene"]);await process_frame;await delay(.4)
	var intro=current_scene.cinematic
	check(intro.active and intro.video.is_playing(),"Cinematic automatically plays on startup")
	check(intro.video.get_video_texture()!=null and intro.video.get_video_texture().get_width()==1280,"Native Theora video decodes at original resolution")
	check(flow.menu_audio.cinematic_active and not flow.menu_audio.music.playing,"Cinematic owns audio without overlapping menu music")
	await shot("intro")
	await delay(5.2)
	check(not intro.active and flow.menu_audio.wants_music,"Natural video end returns to main menu and fades music in")
	# An actual 15-second idle interval, without synthetic input.
	var started: int=intro.starts
	await delay(15.2)
	check(intro.active and intro.starts==started+1,"Exactly main-menu inactivity restarts cinematic after 15 seconds")
	var event:=InputEventKey.new();event.keycode=KEY_ENTER;event.pressed=true;Input.parse_input_event(event)
	await process_frame
	check(not intro.active and flow.current_state==&"main_menu","Skip press is consumed without activating Play")
	for screen in [&"options",&"credits",&"how_to_play",&"play_menu"]:
		flow.show_screen(screen);intro.idle_seconds=14.99;intro._process(.1)
		check(not intro.active,"Attract video disabled in "+str(screen))
	flow.show_screen(&"options");current_scene.show_options_page(1)
	check(current_scene.graphic_controls.has("enhanced_graphics"),"Graphics screen exposes enhanced-quality switch")
	flow.show_screen(&"play_menu");flow.choose_mode(&"free_drive");flow.start_selected()
	await process_frame
	check(is_instance_valid(flow.loading_overlay),"Loading artwork displayed while world prepares")
	await shot("loading")
	if not await state(&"free_drive"):await finish();return
	var world=current_scene
	check(flow.last_loading_metrics.get("settle_ms",0)>=2000,"Extra two real-time seconds finish before driving is enabled")
	check(world.presentation_ready and world.player.driving_enabled and not world.night_style.decorating,"World presentation and nearby decoration prepared before reveal")
	var all_decorated:=true
	for sector in world.city_manager.loaded.values():all_decorated=all_decorated and sector["node"].has_meta("night_decorated")
	check(all_decorated,"All initially visible sectors have decorated geometry")
	var quality=world.get_node("EnhancedGraphics")
	flow.set_graphics("enhanced_graphics",true)
	check(quality.enabled and root.msaa_3d==Viewport.MSAA_4X and quality.accents.all(func(light):return light.visible),"Enhanced quality applies antialiasing and bounded neon lights")
	await shot("enhanced")
	flow.set_graphics("enhanced_graphics",false)
	var restored: bool=root.msaa_3d==quality.baseline_msaa
	for record in quality.snapshots:
		for key in record:
			if key!="node":restored=restored and record["node"].get(key)==record[key]
	check(restored and quality.accents.all(func(light):return not light.visible),"Disabling enhanced mode restores exact original lighting and antialiasing")
	await shot("original")
	flow.set_graphics("enhanced_graphics",true);flow.set_graphics("enhanced_graphics",true)
	check(quality.accents.size()==2,"Repeated quality changes never duplicate lights")
	var music=flow.driving_music
	check(music.index==0 and music.player.playing and not music.player.stream.loop,"Free drive starts VENDABAL with looping disabled")
	for expected in [1,2,0]:
		music.player.seek(music.player.stream.get_length()-.15)
		await delay(.5)
		check(music.index==expected and music.player.playing,"Real finished signal advances playlist to "+str(expected))
	var position: float=music.player.get_playback_position()
	music.set_state(&"loading");await delay(.2)
	check(music.player.stream_paused and absf(position-music.player.get_playback_position())<.15,"Loading preserves playlist position")
	music.set_state(&"free_drive")
	flow.return_to_main_menu();await state(&"main_menu");await delay(.6)
	check(not music.player.playing and flow.menu_audio.music.playing,"Returning to menus restores menu soundtrack only")
	flow.show_screen(&"play_menu");flow.choose_mode(&"race");flow.start_selected();flow.select_race("arracon_malecon");flow.launch_selected_race()
	if await state(&"race"):
		check(music.player.playing and not music.player.stream_paused,"Race mode plays shared rotating soundtrack")
		check(current_scene.race_activity.session.phase=="countdown" and current_scene.race_activity.session.countdown>2,"Loading does not consume race countdown")
		check(flow.last_loading_metrics.get("settle_ms",0)>=2000,"Race loading includes stabilization margin")
		flow.return_to_main_menu();await state(&"main_menu")
	await finish()
func finish() -> void:
	for path in hashes:check(FileAccess.get_sha256(path)==hashes[path],"Unchanged driving/geography: "+path)
	var report={"checks":checks,"passed":failures.is_empty(),"failures":failures,"loading":flow.last_loading_metrics}
	FileAccess.open("res://.local/artifacts/media_quality_validation.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("MEDIA_QUALITY_REPORT ",JSON.stringify(report))
	await flow.menu_audio.shutdown();quit(0 if failures.is_empty() else 1)

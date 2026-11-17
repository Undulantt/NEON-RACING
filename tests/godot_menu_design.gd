extends SceneTree
var flow: Node
var checks:=0
var failures: Array=[]
var geometry: Array=[]
var capture:=false
var hashes: Dictionary={}

func _initialize() -> void:run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks+=1
	if not ok:failures.append(message);push_error(message)

func frames(n:=4) -> void:
	for i in range(n):await process_frame

func state(value: StringName) -> bool:
	var deadline:=Time.get_ticks_msec()+120000
	while flow.current_state!=value or flow.transition_busy:
		if Time.get_ticks_msec()>deadline:check(false,"Load timeout "+str(value));return false
		await process_frame
	await frames();return true

func shot(name: String) -> void:
	await frames()
	var shell=current_scene
	geometry.append({"screen":name,"heading":str(shell.heading.position),"canvas":str(shell.presentation.canvas.global_position),"scale":str(shell.presentation.canvas.scale),"viewport":str(root.get_visible_rect())})
	if not capture:return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.local/artifacts/evidence/menu_"+name+".png")

func finish() -> void:
	for path in hashes:check(FileAccess.get_sha256(path)==hashes[path],"Unchanged driving/map data "+path)
	var report:={"checks":checks,"passed":failures.is_empty(),"failures":failures,"rendered":capture,"geometry":geometry}
	var report_path:="res://.local/artifacts/menu_graphics_restart.json" if "--verify-graphics" in OS.get_cmdline_user_args() else "res://.local/artifacts/menu_design_validation.json"
	FileAccess.open(report_path,FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("MENU_DESIGN_REPORT ",JSON.stringify(report));quit(0 if failures.is_empty() else 1)

func run() -> void:
	await process_frame
	capture="--capture-menu" in OS.get_cmdline_user_args()
	for path in ["res://scripts/driving/ArcadeCar.gd","res://scripts/driving/DrivingAbilities.gd","res://config/vehicles/comet.json","res://data/processed/la_paz_map.json"]:hashes[path]=FileAccess.get_sha256(path)
	flow=root.get_node("GameFlow")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://tests/menu"))
	flow.settings_path="user://tests/menu/settings.cfg";flow.load_settings()
	if "--verify-graphics" in OS.get_cmdline_user_args():
		check(flow.graphics_configured and flow.graphics["smoke_quality"]==2 and flow.graphics["clouds_enabled"],"Graphics preferences survive a new Godot process")
		finish();return
	change_scene_to_file(flow.definition["menu_scene"]);await frames()
	var shell=current_scene
	check(shell.buttons.size()==5,"Five main menu actions")
	check(shell.buttons["play"].get_script()==preload("res://scripts/ui/NeonButton.gd"),"Main menu uses reusable native NeonButton")
	await shot("main")
	flow.show_screen(&"credits");await shot("credits")
	check(shell.back_button.has_focus(),"Credits has keyboard/gamepad focus")
	check(flow.definition["credits"]["contributors"].size()==3,"Credits match supplied Figma collaborators")
	flow.go_back();flow.show_screen(&"options");shell.show_options_page(0);await shot("audio")
	check(shell.sliders.size()==4,"All real audio buses retained")
	check(shell.presentation.tabs.size()==3,"Options has sound, graphics, display tabs")
	shell.show_options_page(1);await shot("graphics")
	check(shell.graphic_controls.size()==6,"Six functional graphics preferences")
	shell.graphic_controls["optical_mode"].item_selected.emit(0)
	shell.graphic_controls["smoke_quality"].item_selected.emit(0)
	for key in ["clouds_enabled","smoke_enabled","marks_enabled","burst_enabled"]:shell.graphic_controls[key].toggled.emit(false)
	var selected: Dictionary=flow.graphics.duplicate(true)
	flow.set_volume("Music",.4)
	flow.graphics.clear();flow.load_settings()
	check(flow.graphics==selected and flow.graphics_configured,"Graphics survive save/reload and audio changes")
	check(not flow.set_graphics("smoke_quality",99) and not flow.set_graphics("clouds_enabled","yes"),"Invalid graphics values rejected")
	shell.show_options_page(2);await shot("display")
	check(is_instance_valid(shell.display_choice) and is_instance_valid(shell.size_choice),"Existing screen controls retained")
	flow.go_back();shell.buttons["play"].pressed.emit();shell.buttons["free_drive"].pressed.emit();await shot("vehicles")
	check(shell.stat_values.size()==24,"Vehicle comparison and profiles retained")
	flow.go_back();flow.go_back()
	if capture:
		for size in [Vector2i(1600,900),Vector2i(1920,1080),Vector2i(1600,720),Vector2i(960,720)]:
			root.size=size;await frames(6)
			var bounds:=root.get_visible_rect()
			for button in shell.buttons.values():
				check(bounds.encloses(button.get_global_rect()),"Main action remains within viewport "+str(size)+" "+button.name)
			await shot("%dx%d"%[size.x,size.y])
		root.size=Vector2i(1280,720);await frames(6)
	flow.show_screen(&"play_menu");flow.choose_mode(&"free_drive");flow.start_selected()
	if not await state(&"free_drive"):finish();return
	var world=current_scene
	for i in range(20):await physics_frame
	var fx=world.follow_camera.speed_feedback.vehicle_feedback
	check(world.follow_camera.speed_feedback.environment_feedback.mode()=="original","Menu optical preference reaches existing SF.3 controller")
	check(not world.night_style.clouds.enabled and not world.night_style.clouds.batch.visible,"Cloud preference disables actual cloud batch")
	check(not fx.settings["smoke_enabled"] and fx.smoke_batch.multimesh.visible_instance_count==0,"Smoke preference disables real emitters")
	check(int(fx.settings["smoke_max"])==32 and int(fx.settings["marks_max"])==128,"Low quality lowers real effect budgets")
	check(not fx.settings["marks_enabled"] and not fx.settings["burst_enabled"],"Marks and body BURST preferences reach real controllers")
	check(not world.hud.ground_flames.is_physics_processing() and world.hud.speed_effects.sf4_burst_progress==0,"Disabling BURST visuals does not activate legacy flame fallback")
	check(world.player.config==preload("res://scripts/driving/VehicleProfiles.gd").load_profile(world.player.vehicle_profile)["config"],"Graphics do not change physics or vehicle stats")
	for key in ["clouds_enabled","smoke_enabled","marks_enabled","burst_enabled"]:flow.set_graphics(key,true)
	flow.set_graphics("optical_mode","full");flow.set_graphics("smoke_quality",2)
	check(world.night_style.clouds.enabled and fx.settings["smoke_enabled"] and int(fx.settings["smoke_max"])==128,"Graphics can be restored on the live world")
	flow.return_to_main_menu();if not await state(&"main_menu"):finish();return
	check(current_scene.buttons.size()==5,"World returns to the new menu without invalid references")
	finish()

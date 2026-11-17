extends SceneTree
var failures: Array=[]
var checks:=0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok: failures.append(label);push_error(label)
func run() -> void:
	await process_frame
	var flow=root.get_node("GameFlow")
	flow.settings_path="res://.local/artifacts/expert_menu_settings_%d.cfg" % OS.get_process_id()
	flow.rival_difficulty="expert"
	change_scene_to_file(flow.definition["menu_scene"])
	await process_frame
	flow.show_screen(&"play_menu")
	flow.choose_mode(&"race")
	await process_frame
	var choice: OptionButton=current_scene.find_child("RivalDifficulty",true,false)
	check(choice!=null and choice.item_count==2,"Vehicle selection offers Standard and Expert")
	if choice!=null:
		check(choice.selected==1,"Expert is initially selected")
		choice.select(0)
		choice.item_selected.emit(0)
		check(flow.rival_difficulty=="standard","Selector changes the actual session setting")
		flow.rival_difficulty="expert"
		flow.load_settings()
		check(flow.rival_difficulty=="standard","Difficulty survives settings reload")
		check(not flow.set_rival_difficulty("impossible"),"Unknown difficulty rejected")
		flow.current_state=&"race"
		check(not flow.set_rival_difficulty("expert"),"Difficulty cannot change while racing")
		flow.current_state=&"vehicle_select"
		choice.select(1)
		choice.item_selected.emit(1)
		check(flow.rival_difficulty=="expert","Expert can be restored for next race")
		if "--capture-expert" in OS.get_cmdline_user_args():
			choice.grab_focus()
			var scroll:=choice.get_parent().get_parent() as ScrollContainer
			if scroll!=null: scroll.ensure_control_visible(choice)
			await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://.local/artifacts/evidence/expert_menu.png")
	var base: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://config/rivals.json"))["profiles"]["aggressive"]
	var snapshot:=base.duplicate(true)
	var expert: Dictionary=preload("res://scripts/racing/RivalDifficulty.gd").settings(base,"expert")
	check(base==snapshot and expert["expert"],"Difficulty copies decision parameters without mutating the base")
	check(not expert.has("max_forward_speed_mps") and not expert.has("braking_mps2") and not expert.has("lateral_grip_per_second"),"Expert does not supply physical stat overrides")
	var report:={"passed":failures.is_empty(),"checks":checks,"failures":failures}
	FileAccess.open("res://.local/artifacts/expert_menu_validation.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("EXPERT_MENU ",JSON.stringify(report))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(flow.settings_path))
	quit(0 if failures.is_empty() else 1)

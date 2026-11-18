extends SceneTree
const Profiles=preload("res://scripts/driving/VehicleProfiles.gd")
var flow: Node
var checks:=0
var failures: Array=[]
var capture:=false
var hashes: Dictionary={}
func _initialize() -> void:run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok:failures.append(label);push_error(label)
func frames(count:=4) -> void:
	for i in range(count):await process_frame
func shot(name: String) -> void:
	if not capture:return
	await frames(20);await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.local/artifacts/evidence/vehicle_selector_"+name+".png")
func run() -> void:
	await process_frame;flow=root.get_node("GameFlow");capture="--capture-selector" in OS.get_cmdline_user_args()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://tests/vehicle_selector"));flow.settings_path="user://tests/vehicle_selector/settings.cfg";flow.set_graphics("fps_limit",0)
	if capture:root.mode=Window.MODE_WINDOWED;root.size=Vector2i(1280,720)
	for path in ["res://scripts/driving/ArcadeCar.gd","res://scripts/driving/ImportedCarVisual.gd","res://scripts/driving/DrivingAbilities.gd","res://config/vehicles/vector.json","res://config/vehicles/comet.json","res://config/vehicles/apex.json"]:hashes[path]=FileAccess.get_sha256(path)
	change_scene_to_file(flow.definition["menu_scene"]);await frames()
	flow.show_screen(&"play_menu");flow.choose_mode(&"free_drive");await frames()
	var shell=current_scene;var view=shell.vehicle_selector;var showroom=view.showroom
	check(showroom.viewport.own_world_3d and showroom.viewport.transparent_bg,"Independent transparent 3D preview")
	check(showroom.top_light is SpotLight3D and showroom.top_light.position.y>2.5 and showroom.top_light.light_energy>0,"Actual overhead neon light illuminates preview")
	check(view.bars.size()==8 and shell.stat_values.size()==24,"Eight real statistics retained for all profiles")
	for id in Profiles.IDS:
		for i in range(3):
			if flow.selected_vehicle_id==id:break
			shell.buttons["vehicle_next"].pressed.emit()
		check(showroom.selected_id==id and view.name_label.text==id,"Arrow updates model/name/session: "+id)
		check(showroom.models[id].get_meta("imported_vehicle_model","")==id,"Preview uses supplied imported model: "+id)
		for key in view.bars:check(view.bars[key].value==Profiles.load_profile(id)["stats"][key],"Actual profile bar "+id+" "+key)
		var angle_before: float=showroom.pivot.rotation.y
		var fits:=true
		for step in range(16):
			var angle:=TAU*step/16.0
			showroom.pivot.rotation.y=angle
			for mesh in showroom.models[id].find_children("*","MeshInstance3D",true,false):
				if not mesh.is_visible_in_tree():continue
				for corner in range(8):
					var p: Vector3=mesh.global_transform*mesh.get_aabb().get_endpoint(corner)
					if not showroom.camera.is_position_in_frustum(p):
						if fits:print("SHOWROOM_CLIP ",id," ",angle," ",mesh.name," world ",p," screen ",showroom.camera.unproject_position(p)," viewport ",showroom.viewport.size)
						fits=false
		showroom.pivot.rotation.y=angle_before
		check(fits,"Whole car fits default camera throughout rotation: "+id)
		await shot(id.to_lower())
	var original: String=flow.selected_vehicle_id
	for i in range(3):shell.buttons["vehicle_next"].pressed.emit()
	check(flow.selected_vehicle_id==original,"Next arrow wraps through three vehicles")
	shell.buttons["vehicle_previous"].pressed.emit();shell.buttons["vehicle_next"].pressed.emit()
	check(flow.selected_vehicle_id==original,"Previous arrow reverses cycle")
	check(showroom.models.size()==3,"Models are cached once instead of accumulated per click")
	var point: Vector2=showroom.get_global_rect().get_center()
	var actual_press:=InputEventMouseButton.new();actual_press.position=point;actual_press.global_position=point;actual_press.button_index=MOUSE_BUTTON_LEFT;actual_press.pressed=true
	Input.parse_input_event(actual_press);await frames(2)
	check(showroom.dragging,"Real viewport mouse input reaches rotation control")
	var before_drag: float=showroom.pivot.rotation.y
	var actual_motion:=InputEventMouseMotion.new();actual_motion.position=point+Vector2(30,0);actual_motion.global_position=actual_motion.position;actual_motion.relative=Vector2(30,0)
	Input.parse_input_event(actual_motion);await frames(2)
	check(absf(showroom.pivot.rotation.y-before_drag)>.3,"Real mouse motion rotates the 3D model")
	actual_press.pressed=false;Input.parse_input_event(actual_press);await frames(2)
	check(not showroom.dragging,"Real mouse release ends manual rotation")
	showroom.resume_delay=0
	var yaw: float=showroom.pivot.rotation.y;showroom._process(1)
	check(absf(showroom.pivot.rotation.y-yaw)>.1,"Slow automatic rotation advances")
	var press:=InputEventMouseButton.new();press.button_index=MOUSE_BUTTON_LEFT;press.pressed=true;showroom._gui_input(press)
	var motion:=InputEventMouseMotion.new();motion.relative=Vector2(80,0);showroom._gui_input(motion)
	check(absf(showroom.pivot.rotation.y-yaw)>.8 and showroom.dragging,"Mouse drag turns selected vehicle")
	yaw=showroom.pivot.rotation.y;showroom._process(1)
	check(is_equal_approx(showroom.pivot.rotation.y,yaw),"Automatic rotation pauses while dragging")
	press.pressed=false;showroom._gui_input(press);showroom._process(.5)
	check(is_equal_approx(showroom.pivot.rotation.y,yaw),"Release holds user angle briefly")
	showroom._process(2.1);check(absf(showroom.pivot.rotation.y-yaw)>.1,"Automatic rotation resumes after interaction")
	var distance: float=showroom.camera_distance
	press.button_index=MOUSE_BUTTON_WHEEL_UP;press.pressed=true;showroom._gui_input(press)
	check(showroom.camera_distance<distance,"Wheel zoom works inside showroom")
	var weak: WeakRef=weakref(showroom.viewport)
	flow.go_back();await frames()
	check(weak.get_ref()==null,"Leaving selector releases its 3D viewport")
	flow.choose_mode(&"race");await frames()
	view=current_scene.vehicle_selector
	check(view.showroom.selected_id==original and is_instance_valid(view.difficulty),"Same selected car and difficulty in race flow")
	current_scene.buttons["continue"].pressed.emit()
	check(flow.current_state==&"race_select" and flow.selected_vehicle_id==original,"Continue reaches race selection without losing car")
	flow.go_back();await frames();await shot("race_mode")
	for size in [Vector2i(960,540),Vector2i(1920,1080)]:
		if not capture:continue
		root.size=size;await frames(8)
		var bounds: Rect2=current_scene.presentation.scroll.get_global_rect()
		check(bounds.position.x>=0 and bounds.end.x<=root.get_visible_rect().end.x+1,"Selector fits viewport width: "+str(size))
		await shot(str(size.x))
	flow.return_to_main_menu();await frames()
	for path in hashes:check(FileAccess.get_sha256(path)==hashes[path],"Driving/model adapter unchanged: "+path)
	var report:={"passed":failures.is_empty(),"checks":checks,"failures":failures,"rendered":capture}
	FileAccess.open("res://.local/artifacts/vehicle_selector_validation.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("VEHICLE_SELECTOR_REPORT ",JSON.stringify(report));await flow.menu_audio.shutdown();quit(0 if report["passed"] else 1)

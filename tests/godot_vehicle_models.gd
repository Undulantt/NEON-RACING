extends SceneTree
const Profiles=preload("res://scripts/driving/VehicleProfiles.gd")
const Visual=preload("res://scripts/driving/CarVisual.gd")
var flow: Node
var capture:=false
var checks:=0
var failures: Array=[]
var hashes: Dictionary={}

func _initialize() -> void:run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks+=1
	if not ok:failures.append(message);push_error(message)

func state(value: StringName) -> bool:
	var deadline:=Time.get_ticks_msec()+120000
	while flow.current_state!=value or flow.transition_busy:
		if Time.get_ticks_msec()>deadline:check(false,"Load timeout "+str(value));return false
		await process_frame
	return true

func shot(name: String) -> void:
	if not capture:return
	for i in range(4):await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.local/artifacts/evidence/vehicle_model_"+name+".png")

func finish() -> void:
	for path in hashes:check(FileAccess.get_sha256(path)==hashes[path],"Unchanged physics/race data "+path)
	var report:={"passed":failures.is_empty(),"checks":checks,"failures":failures,"rendered":capture}
	FileAccess.open("res://.local/artifacts/vehicle_models_validation.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("VEHICLE_MODELS_REPORT ",JSON.stringify(report));await flow.menu_audio.shutdown();quit(0 if failures.is_empty() else 1)

func run() -> void:
	await process_frame
	flow=root.get_node("GameFlow");capture="--capture-models" in OS.get_cmdline_user_args()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://tests/vehicle_models"))
	flow.settings_path="user://tests/vehicle_models/settings.cfg"
	if capture:root.mode=Window.MODE_WINDOWED;root.size=Vector2i(1280,720)
	for path in ["res://scripts/driving/ArcadeCar.gd","res://scripts/driving/DrivingAbilities.gd","res://scripts/racing/RaceCompetition.gd","res://config/vehicles/vector.json","res://config/vehicles/comet.json","res://config/vehicles/apex.json"]:hashes[path]=FileAccess.get_sha256(path)
	change_scene_to_file(flow.definition["menu_scene"]);await process_frame
	flow.show_screen(&"play_menu");flow.choose_mode(&"free_drive");flow.select_vehicle("VECTOR");flow.start_selected()
	if flow.current_state==&"race_select":flow.launch_selected_race()
	if not await state(&"free_drive"):await finish();return
	var world=current_scene;var car=world.player
	car.external_control=true
	var collider: Vector3=car.collision_shape.size
	var mask: int=car.collision_mask
	for id in Profiles.IDS:
		car.set_controls(0,0,true)
		await world.prepare_at({"position_xz":[311.195867,-512.400363],"forward_xz":[.3825377,-.9239399]})
		check(car.apply_vehicle_profile(id),"Apply profile "+id)
		car.driving_enabled=true
		for i in range(75):await physics_frame
		var model: Node3D=car.visual_root.get_node_or_null(id.capitalize()+"Model")
		check(model!=null and car.visual_root.get_meta("imported_vehicle_model","")==id,"Correct imported scene "+id)
		if model==null:await finish();return
		check(model.find_children("*","CollisionObject3D",true,false).is_empty(),"Visual model adds no physics bodies "+id)
		check(car.visuals["wheels"].size()==4,"Four imported wheel carriers "+id)
		for i in range(4):
			var pivot: Node3D=car.visuals["pivots"][i]
			check(pivot.position.z<0 if i<2 else pivot.position.z>0,"Correct axle %s %d"%[id,i])
			check(car.visuals["wheels"][i].get_child(0).is_visible_in_tree(),"Visible imported wheel %s %d"%[id,i])
		var tail_count:=0
		for mesh in model.find_children("*","MeshInstance3D",true,false):
			for surface in range(mesh.mesh.get_surface_count()):
				var material: Material=mesh.get_active_material(surface)
				if material!=null and material.resource_name.begins_with("LightBack"):
					tail_count+=1;check(material==car.visuals["brake_material"],"Rear-light surface uses the brake material "+id)
		check(tail_count>0,"Rear lights found by actual material "+id)
		var copy:=Node3D.new();copy.hide();world.add_child(copy)
		var other:=Visual.build(copy,id)
		check(other["brake_material"]!=car.visuals["brake_material"],"Brake material is instance-local "+id)
		copy.free()
		var fx=world.follow_camera.speed_feedback.vehicle_feedback;fx.refresh_body_bindings()
		check(not fx.body_bindings.is_empty(),"BURST recognizes imported paint "+id)
		check(car.safe_road_transform(car.global_transform),"Model retains safe road support "+id)
		var basis: Basis=car.visuals["wheels"][0].basis
		car.set_controls(1,0)
		for i in range(45):await physics_frame
		check(car.speed_mps>1 and not car.visuals["wheels"][0].basis.is_equal_approx(basis),"Imported wheels animate while driving "+id)
		car.set_controls(0,.3)
		for i in range(3):await physics_frame
		check(absf(car.visuals["pivots"][0].rotation.y)>.001 and is_zero_approx(car.visuals["pivots"][2].rotation.y),"Front steering works "+id)
		car.set_controls(-1,0,true)
		for i in range(40):await physics_frame
		check(car.visuals["brake_material"].emission_energy_multiplier>2,"Rear lights react to braking "+id)
		check(car.collision_shape.size==collider and car.collision_mask==mask and car.config==Profiles.load_profile(id)["config"],"Collision and driving stats unchanged "+id)
		await shot(id.to_lower()+"_rear")
		if capture:
			var camera:=Camera3D.new();world.add_child(camera);camera.fov=40
			camera.global_position=car.to_global(Vector3(-7,2.8,-9));camera.look_at(car.to_global(Vector3(0,.2,0)),Vector3.UP);camera.make_current()
			await shot(id.to_lower()+"_front");world.follow_camera.camera.make_current();camera.queue_free()
	flow.return_to_main_menu();if not await state(&"main_menu"):await finish();return
	flow.show_screen(&"play_menu");flow.choose_mode(&"race");flow.select_vehicle("APEX");flow.start_selected()
	if flow.current_state==&"race_select":flow.launch_selected_race()
	if not await state(&"race"):await finish();return
	world=current_scene
	for car_in_race in [world.player]+world.race_activity.competition.rivals:
		check(car_in_race.visual_root.get_node_or_null(car_in_race.vehicle_profile.capitalize()+"Model")!=null,"Race participant uses its actual model "+car_in_race.vehicle_profile)
	if capture:
		for i in range(75):await physics_frame
		await shot("race")
	await finish()

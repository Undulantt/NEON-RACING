extends SceneTree
var flow: Node
var checks:=0
var failures: Array=[]
var capture:=false
var wheel_bounds: Array=[]

func _initialize() -> void:run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks+=1
	if not ok:failures.append(message);push_error(message)

func state(value: StringName) -> bool:
	var deadline:=Time.get_ticks_msec()+120000
	while flow.current_state!=value or flow.transition_busy:
		if Time.get_ticks_msec()>deadline:check(false,"Load timeout: "+str(value));return false
		await process_frame
	return true

func shot(name: String) -> void:
	if not capture:return
	for i in range(3):await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.local/artifacts/evidence/comet_"+name+".png")

func finish() -> void:
	var report:={"passed":failures.is_empty(),"checks":checks,"failures":failures,"rendered":capture,"wheel_bounds":wheel_bounds,"model_sha256":FileAccess.get_sha256("res://assets/autos/Not1965FordMustangHoonicorn.glb")}
	FileAccess.open("res://.local/artifacts/comet_model_validation.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("COMET_MODEL_REPORT ",JSON.stringify(report));quit(0 if failures.is_empty() else 1)

func run() -> void:
	await process_frame
	capture="--capture" in OS.get_cmdline_user_args()
	flow=root.get_node("GameFlow");flow.settings_path="user://tests/comet/settings.cfg"
	change_scene_to_file(flow.definition["menu_scene"]);await process_frame
	flow.show_screen(&"play_menu");flow.choose_mode(&"free_drive");flow.select_vehicle("COMET");flow.start_selected()
	if flow.current_state==&"race_select":flow.launch_selected_race()
	if not await state(&"free_drive"):finish();return
	var world=current_scene;var car=world.player
	# Use the known accessible kiosk approach, away from the race-entry cylinder.
	await world.prepare_at({"position_xz":[311.195867,-512.400363],"forward_xz":[.3825377,-.9239399]})
	car.driving_enabled=true
	# Allow existing startup particles and city streaming to settle before visual QA.
	for i in range(75):await physics_frame
	var shape: Vector3=car.collision_shape.size;var mask: int=car.collision_mask;var config: Dictionary=car.config.duplicate(true)
	check(car.visual_root.get_node_or_null("CometModel")!=null,"Selected COMET uses supplied GLB in free drive")
	check(car.visuals["pivots"].size()==4 and car.visuals["wheels"].size()==4,"Four animated imported wheels retain the driving interface")
	for i in range(4):
		var pivot: Node3D=car.visuals["pivots"][i]
		check(pivot.position.z<0 if i<2 else pivot.position.z>0,"Correct front/rear axle "+str(i))
		check(car.visuals["wheels"][i].get_child(0).is_visible_in_tree(),"Imported wheel visible "+str(i))
		var imported: MeshInstance3D=car.visuals["wheels"][i].get_child(0)
		var bounds: AABB=car.visual_root.global_transform.affine_inverse()*imported.global_transform*imported.get_aabb()
		wheel_bounds.append({"name":imported.name,"size":str(bounds.size),"center":str(bounds.get_center())})
	var model: Node3D=car.visual_root.get_node("CometModel")
	check(model.find_children("*","CollisionObject3D",true,false).is_empty(),"Imported scene adds no physical bodies")
	check(car.safe_road_transform(car.global_transform),"Original safe-road footprint remains valid")
	var vfx=world.follow_camera.speed_feedback.vehicle_feedback
	vfx.refresh_body_bindings()
	check(vfx.body_bindings.size()>=3,"BURST binds to the imported body")
	var head: MeshInstance3D=model.find_child("HeadlightFront",true,false)
	check(car.visual_root.to_local(head.to_global(head.get_aabb().get_center())).z<0,"Headlight geometry faces the driving forward direction")
	await shot("rear")
	if capture and "--diagnose" in OS.get_cmdline_user_args():
		model.hide();await shot("model_hidden");model.show()
		for part in model.get_children():
			if part is MeshInstance3D:
				part.hide();await shot("without_"+part.name);part.show()
	if capture:
		var camera:=Camera3D.new();world.add_child(camera);camera.fov=40
		camera.global_position=car.to_global(Vector3(-7,2.8,-9))
		camera.look_at(car.to_global(Vector3(0,.2,0)),Vector3.UP);camera.make_current()
		await shot("front");world.follow_camera.camera.make_current();camera.queue_free()
	var old_basis: Basis=car.visuals["wheels"][0].basis
	car.external_control=true
	for i in range(90):car.set_controls(1,0);await physics_frame
	check(car.speed_mps>2,"COMET accelerates using existing controls")
	check(not car.visuals["wheels"][0].basis.is_equal_approx(old_basis),"Imported wheels spin during driving")
	car.set_controls(0,.4)
	for i in range(3):await physics_frame
	check(absf(car.visuals["pivots"][0].rotation.y)>.001 and is_zero_approx(car.visuals["pivots"][2].rotation.y),"Only front wheels steer")
	car.set_controls(-1,0,true)
	for i in range(120):await physics_frame
	check(car.visuals["brake_material"].emission_energy_multiplier>2,"Imported rear lights respond to braking")
	car.set_physics_process(false);car.velocity=Vector3.ZERO
	var old_pose: Transform3D=car.global_transform
	var lights_before: int=car.visual_root.find_children("*","Light3D",true,false).size()
	check(car.apply_vehicle_profile("VECTOR") and car.visual_root.get_node_or_null("VectorModel")!=null,"VECTOR uses its own imported model")
	check(car.apply_vehicle_profile("APEX") and car.visual_root.get_node_or_null("ApexModel")!=null,"APEX uses its own imported model")
	check(car.apply_vehicle_profile("COMET") and car.visual_root.get_node_or_null("CometModel")!=null,"Returning to COMET restores imported model")
	check(car.global_transform==old_pose and car.collision_shape.size==shape and car.collision_mask==mask and car.config==config,"Visual replacement preserves transform, collision and COMET stats")
	check(car.visual_root.find_children("*","Light3D",true,false).size()==lights_before,"Profile changes preserve existing headlight nodes")
	flow.return_to_main_menu();if not await state(&"main_menu"):finish();return
	flow.show_screen(&"play_menu");flow.choose_mode(&"race");flow.select_vehicle("COMET");flow.start_selected()
	if flow.current_state==&"race_select":flow.launch_selected_race()
	if not await state(&"race"):finish();return
	world=current_scene
	check(world.player.visual_root.get_node_or_null("CometModel")!=null,"Race player uses the same COMET model")
	for rival in world.race_activity.competition.rivals:
		check((rival.visual_root.get_node_or_null("CometModel")!=null)==(rival.vehicle_profile=="COMET"),"Rival model matches profile "+str(rival.vehicle_profile))
	for i in range(75):await physics_frame
	await shot("race")
	finish()

extends SceneTree
var flow: Node
var checks := 0
var failures: Array = []
var metrics := {}
var capture := false

func _initialize() -> void: run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func physics(n: int) -> void:
	for i in range(n): await physics_frame

func state(value: StringName) -> bool:
	var deadline := Time.get_ticks_msec()+60000
	while flow.current_state != value or flow.transition_busy:
		if Time.get_ticks_msec()>deadline:
			check(false,"Timeout waiting for "+str(value)+": "+flow.navigation_error)
			return false
		await process_frame
	return true

func shot(name: String) -> void:
	if not capture: return
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://docs/evidence/navigation_"+name+".png")

func finish() -> void:
	var report := {"passed":failures.is_empty(),"checks":checks,"failures":failures,"metrics":metrics,"rendered":capture}
	FileAccess.open("res://docs/race_navigation_validation_render.json" if capture else "res://docs/race_navigation_validation.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("RACE_NAVIGATION_REPORT ",JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)

func wait_recovery(activity: Node3D) -> void:
	for i in range(300):
		if not activity.recovering: return
		await physics_frame
	check(false,"Recovery did not finish")

func run() -> void:
	await process_frame
	capture = "--capture-navigation" in OS.get_cmdline_user_args()
	flow = root.get_node("GameFlow")
	change_scene_to_file(flow.definition["menu_scene"])
	await process_frame
	flow.show_screen(&"play_menu");flow.choose_mode(&"free_drive");flow.start_selected()
	if not await state(&"free_drive"):finish();return
	var world = current_scene
	var car = world.player
	var activity = world.race_activity
	var minimap = world.hud.instruments.minimap
	check(activity.marker.mesh is CylinderMesh,"Free-drive race entrance uses a cylinder")
	check(activity.marker.material_override is ShaderMaterial,"Cylinder has transparent gradient shader")
	check(activity.marker.mesh.height==5 and not activity.marker.mesh.cap_top,"Cylinder is open and five metres tall")
	await physics(10)
	await shot("entrance")
	if capture: check(minimap.race_marker_visible,"Minimap shows nearby race entrance")
	world.hud.set_pause(true)
	check(paused and world.hud.free_pause.visible,"Free pause opens full map and freezes simulation")
	check(not world.hud.pause_panel.visible,"Compact race pause does not obscure free-drive map")
	var pause_ui = world.hud.free_pause
	await process_frame
	var destination: Vector2 = flow.road_graph.nodes["6195830555"]
	var click_position: Vector2 = pause_ui.map.screen(destination)
	var pose: Transform3D = car.global_transform
	if capture:
		var event := InputEventMouseButton.new()
		event.position = pause_ui.map.global_position+click_position
		event.global_position = event.position
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = true
		Input.parse_input_event(event)
		await process_frame
		event.pressed = false
		Input.parse_input_event(event)
		await process_frame
	else: pause_ui.map.select_at(click_position)
	check(world.navigation.destination_id=="6195830555","Map click selects actual OSM destination")
	check(world.navigation.points.size()>2,"Destination builds a road route")
	check(flow.road_graph.validate_refs(world.navigation.route_edges,false).is_empty(),"GPS route follows permitted connected road edges")
	var active_roads := {}
	for road in world.map_data["roads"]: active_roads[str(road["id"])]=true
	check(world.navigation.route_edges.all(func(edge: Dictionary):return active_roads.has(str(edge["road_id"]))),"GPS never routes through roads omitted from playable relief")
	check(flow.road_graph.navigation != null and flow.road_graph.navigation.get_point_count()<=flow.road_graph.legal.get_point_count(),"GPS uses active drivable network prepared in worker")
	check(car.global_transform==pose,"Choosing destination never teleports car")
	metrics["gps_distance_m"] = world.navigation.distance_m
	await shot("pause_map")
	pause_ui.menu_buttons["resume"].pressed.emit()
	check(not paused and not pause_ui.visible,"Resume closes map and restores driving")
	check(not world.navigation.points.is_empty(),"Chosen route persists after closing map")
	await shot("gps_minimap")
	check(not world.navigation.set_destination(Vector2(100000,100000)),"Far off-road click has no fabricated route")
	check(world.navigation.set_destination(destination),"Valid destination can be selected again")
	check(world.request_race(str(flow.definition["default_race_id"])),"Existing free-drive race still starts")
	if not await state(&"race"):finish();return
	var visuals = activity.visuals
	check(is_equal_approx(visuals.next_gate.scale.x,1.3) and is_equal_approx(visuals.next_gate.scale.y,1.3),"Checkpoint ring retains thirty-percent scale")
	check(visuals.next_gate.get_child_count()==1 and visuals.next_gate.get_child(0).mesh is ArrayMesh,"Checkpoint is a circular annulus with one mesh")
	check(visuals.next_gate.get_child(0).material_override is ShaderMaterial,"Ring has gradient transparency material")
	var ring_radius: float = visuals.next_gate.get_meta("radius_m")
	var ring_p: Array = activity.definition["checkpoints"][0]["position_xz"]
	var road_y: float = car.surface_height(ring_p[0],ring_p[1])
	check(absf(visuals.next_gate.position.y-ring_radius-road_y+ring_radius*0.25)<0.0001,"Exactly quarter radius lies below local road level")
	var ring_vertices: PackedVector3Array=visuals.next_gate.get_child(0).mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var outer_count := 0
	for v in ring_vertices:
		if absf(Vector2(v.x,v.y).length()*1.3-ring_radius)<0.001: outer_count+=1
	check(outer_count==96*3,"Outer boundary is circular in both axes")
	check(visuals.ribbon.mesh.surface_get_primitive_type(0)==Mesh.PRIMITIVE_TRIANGLES,"Route is visible geometry, not single-pixel lines")
	check(visuals.ribbon.material_override.albedo_color==Color("ff790f"),"Route uses neon orange")
	var vertices: PackedVector3Array=visuals.ribbon.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	check(absf(Vector2(vertices[0].x,vertices[0].z).distance_to(Vector2(vertices[1].x,vertices[1].z))-0.8)<0.01,"Route ribbon is 0.8 metres wide")
	check(not activity.marker.visible,"World entrance cylinder hides during race")
	await shot("race_ring")
	await physics(190)
	check(activity.session.phase=="running","Race countdown still releases controls")
	activity.request_recovery()
	check(activity.recovery_spawn==activity.definition["start"],"Recovery before first checkpoint uses race start")
	activity.cancel_recovery()
	car.driving_enabled = true
	var first: Dictionary=activity.definition["checkpoints"][0]
	var p:=Vector2(first["position_xz"][0],first["position_xz"][1])
	var f:=Vector2(first["forward_xz"][0],first["forward_xz"][1])
	var session_fixture = preload("res://scripts/racing/RaceSession.gd").new()
	session_fixture.begin(activity.definition)
	session_fixture.advance(p,p,3.1)
	var lateral := f.orthogonal()*float(first["half_width_m"])*1.2
	session_fixture.advance(p-f+lateral,p+f+lateral,0.1)
	check(session_fixture.next_checkpoint==1,"Checkpoint detection width remains unchanged by ring presentation")
	activity.session.advance(p-f*0.1,p+f*0.1,0.1)
	check(activity.session.next_checkpoint==1,"Fixture passes first checkpoint")
	var elapsed: float=activity.session.elapsed
	var recoveries: int=car.recovery_count
	var count_before: int=activity.session.next_checkpoint
	var lap_before: int=activity.session.completed_laps
	car.global_position += Vector3(4,0,4)
	pose=car.global_transform
	var recover_key := InputEventKey.new()
	recover_key.physical_keycode = KEY_R
	recover_key.keycode = KEY_R
	recover_key.pressed = true
	Input.parse_input_event(recover_key)
	await physics(2)
	recover_key.pressed = false
	Input.parse_input_event(recover_key)
	check(activity.recovering and not car.is_physics_processing(),"Recovery blocks car instead of teleporting immediately")
	check(car.speed_mps==0 and not car.turbo_active,"Frozen recovery does not display stale speed or turbo")
	pose = car.global_transform
	await physics(120)
	check(activity.recovering and car.recovery_count==recoveries,"No return before three seconds")
	check(car.global_transform==pose,"Car stays frozen during recovery countdown")
	await shot("recovery")
	var remaining: float=activity.recovery_remaining
	car.recover()
	check(activity.recovery_remaining==remaining,"Repeated recover presses do not restart countdown")
	world.hud.set_pause(true)
	check(world.hud.race_recover_button.visible and not pause_ui.visible,"Race pause offers checkpoint recovery without free-drive map")
	for i in range(8): await process_frame
	check(activity.recovery_remaining==remaining,"Pausing freezes recovery countdown")
	world.hud.set_pause(false)
	await wait_recovery(activity)
	check(car.recovery_count==recoveries+1,"Recovery occurs exactly once")
	check(Vector2(car.position.x,car.position.z).distance_to(p)<0.3,"Recovery returns to last passed checkpoint")
	check(car.safe_road_transform(car.global_transform),"Recovered car has valid road support and clearance")
	check(activity.session.next_checkpoint==count_before and activity.session.completed_laps==lap_before,"Recovery cannot skip checkpoints or alter laps")
	check(activity.session.elapsed-elapsed>=3,"Race clock includes recovery delay")
	check(car.driving_enabled and car.is_physics_processing(),"Recovery restores vehicle processing and controls")
	metrics["recovery_elapsed_s"]=activity.session.elapsed-elapsed
	await physics(3)
	await shot("recovered")
	if capture: check(minimap.drawn_checkpoint_indices.size()>0,"Minimap draws nearby unpassed checkpoints")
	activity.request_recovery()
	flow.restart_race()
	if not await state(&"race"):finish();return
	check(not activity.recovering and car.is_physics_processing() and activity.session.next_checkpoint==0,"Restart cancels pending recovery and resets race")
	flow.cancel_activity()
	if not await state(&"free_drive"):finish();return
	var free_pose: Transform3D=car.safe_transform
	car.global_position += Vector3(3,0,3)
	car.recover()
	await wait_recovery(activity)
	check(Vector2(car.position.x,car.position.z).distance_to(Vector2(free_pose.origin.x,free_pose.origin.z))<0.3,"Free recovery uses last safe point after delay")
	check(world.navigation.destination_id=="6195830555","Free-drive destination survives race activity")
	world.hud.set_pause(true)
	pause_ui.menu_buttons["clear"].pressed.emit()
	check(world.navigation.points.is_empty() and world.navigation.destination_id.is_empty(),"Clear destination removes GPS guidance")
	pause_ui.menu_buttons["race"].pressed.emit()
	check(not world.navigation.destination_id.is_empty(),"Map offers race-start destination")
	pause_ui.menu_buttons["resume"].pressed.emit()
	world.hud.set_pause(true)
	pause_ui.menu_buttons["menu"].pressed.emit()
	if not await state(&"main_menu"):finish();return
	check(not is_instance_valid(world) and not paused,"Menu return releases world, navigation and map")
	finish()

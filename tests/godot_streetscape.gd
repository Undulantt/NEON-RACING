extends SceneTree
var flow: Node
var world: Node3D
var checks:=0
var failures: Array=[]
var initial_hashes:={}
var metrics: Array=[]
var rendered:=false

func _initialize() -> void:run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks+=1
	if not ok:failures.append(message);push_error(message)
func state(value: StringName) -> bool:
	var end:=Time.get_ticks_msec()+120000
	while flow.current_state!=value or flow.transition_busy:
		if Time.get_ticks_msec()>end:check(false,"State timeout "+str(value));return false
		await process_frame
	return true
func settle(minimum: int) -> void:
	var end:=Time.get_ticks_msec()+60000
	while Time.get_ticks_msec()<end:
		var furniture=world.night_style.furniture if world.night_style!=null else null
		if furniture!=null and furniture.sectors.size()>=minimum and not world.night_style.decorating:return
		await process_frame
	check(false,"Decoration timeout")
func capture(name: String) -> void:
	if not rendered:return
	for i in range(5):await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.local/artifacts/evidence/streetscape_"+name+".png")
func finish() -> void:
	for path in initial_hashes:check(FileAccess.get_sha256(path)==initial_hashes[path],"Unchanged "+path)
	var report:={"passed":failures.is_empty(),"checks":checks,"failures":failures,"rendered":rendered,"performance":metrics,"scenario":"Stationary 1280x720 Compatibility A/B, same map/car/camera; toggle only new streetscape geometry; not a city traversal benchmark"}
	FileAccess.open("res://.local/artifacts/streetscape_validation.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("STREETSCAPE_REPORT ",JSON.stringify(report));await flow.menu_audio.shutdown();quit(0 if failures.is_empty() else 1)

func run() -> void:
	await process_frame
	flow=root.get_node("GameFlow");rendered="--capture-streetscape" in OS.get_cmdline_user_args()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://tests/streetscape"))
	flow.settings_path="user://tests/streetscape/settings.cfg"
	if rendered:root.mode=Window.MODE_WINDOWED;root.size=Vector2i(1280,720);DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	for path in ["res://scripts/driving/ArcadeCar.gd","res://scripts/driving/DrivingAbilities.gd","res://data/processed/la_paz_map.json","res://data/processed/arcade_layout.json","res://config/vehicles/vector.json","res://config/vehicles/comet.json","res://config/vehicles/apex.json"]:initial_hashes[path]=FileAccess.get_sha256(path)
	change_scene_to_file(flow.definition["menu_scene"]);await process_frame
	flow.show_screen(&"play_menu");flow.choose_mode(&"free_drive");flow.select_vehicle("VECTOR");flow.start_selected()
	if flow.current_state==&"race_select":flow.launch_selected_race()
	if not await state(&"free_drive"):await finish();return
	world=current_scene
	world.player.external_control=true;world.player.set_controls(0,0,true)
	await settle(8)
	var furniture=world.night_style.furniture
	check(furniture.sidewalks.valid,"Derived geometry matches active cartography")
	check(furniture.sidewalks.manifest["medians_generated"]==0,"No unsupported medians invented")
	for kind in furniture.library.HEIGHTS:
		check(is_equal_approx(furniture.library.bounds[kind].size.y,furniture.library.HEIGHTS[kind]),"Model normalized "+kind)
		check(furniture.assets[kind].size()<=2,"At most two material batches "+kind)
	var counts:={"lamp":0,"palm":0,"big_palm":0,"chair":0}
	var roots: Array=[];var bench:=Vector3.ZERO
	for sector in furniture.sectors.values():
		var owner=sector["owner"].get_ref()
		if not is_instance_valid(owner):continue
		check(owner.get_node_or_null("Sidewalks")!=null,"Pavement built before props")
		for node in owner.get_children():
			if node.name=="Sidewalks" or node is MultiMeshInstance3D:roots.append(node)
		for record in owner.get_meta("furniture_records",[]):
			if counts.has(record["kind"]):counts[record["kind"]]+=1
			if record["kind"]=="chair":
				check(record["malecon"],"Every chair belongs to Malecón")
				bench=Vector3(record["position_xz"][0],0,record["position_xz"][1])
	for kind in counts:check(counts[kind]>0,"Visible near Malecón: "+kind)
	check(furniture.lights.is_empty() and furniture.street_pools.size()==4,"No per-pole dynamic lights")
	check(world.player.safe_road_transform(world.player.global_transform),"Car stays supported on original asphalt")
	await capture("drive")
	if bench!=Vector3.ZERO and rendered:
		var camera:=Camera3D.new();world.add_child(camera);camera.fov=60
		bench.y=world.player.surface_height(bench.x,bench.z)
		camera.position=bench+Vector3(-23,16,26);camera.look_at(bench+Vector3.UP*3);camera.make_current()
		await capture("malecon");world.follow_camera.camera.make_current();camera.queue_free()
	# Keep exactly the same settled scene while comparing geometry overhead.
	if rendered:
		world.night_style.set_process(false);world.player.set_physics_process(false);world.follow_camera.set_physics_process(false)
		for enabled in [false,true,true,false]:
			for node in roots:node.visible=enabled
			for i in range(25):await process_frame
			var samples: Array=[];var previous:=Time.get_ticks_usec()
			for i in range(150):
				await process_frame
				var now:=Time.get_ticks_usec();samples.append((now-previous)/1000.0);previous=now
			samples.sort();var total:=0.0
			for sample in samples:total+=sample
			metrics.append({"enabled":enabled,"mean_ms":total/samples.size(),"p95_ms":samples[142],"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),"sector_roots":furniture.sectors.size(),"gpu":RenderingServer.get_video_adapter_name()})
		for node in roots:node.visible=true
		world.night_style.set_process(true);world.player.set_physics_process(true);world.follow_camera.set_physics_process(true)
	check(world.city_manager.set_city_enabled(false),"City debug toggle off")
	for node in roots:check(not node.is_visible_in_tree(),"Props/pavement follow city visibility")
	check(world.city_manager.set_city_enabled(true),"City debug toggle on")
	var fx=world.follow_camera.speed_feedback.environment_feedback
	fx.set_mode("full");fx.register_nearby()
	for binding in fx.bindings.values():
		var node=binding["node"].get_ref()
		if node is MultiMeshInstance3D:check(node.get_meta("sf3_lamp_emitter",false),"SF.3 modifies emitter only, preserving pole atlas")
	fx.set_mode("original")
	var old_roots: Array=[]
	for node in roots:old_roots.append(weakref(node))
	var away: Dictionary={}
	for road in world.map_data["roads"]:
		if not "forjadores" in str(road["street_name"]).to_lower() or float(road["length_m"])<60:continue
		var a:=Vector2(road["points_xz"][0][0],road["points_xz"][0][1])
		var b:=Vector2(road["points_xz"][-1][0],road["points_xz"][-1][1])
		var p:=(a+b)*.5;var f:=(b-a).normalized()
		if p.distance_to(Vector2(world.player.position.x,world.player.position.z))>2200:
			away={"position_xz":[p.x,p.y],"forward_xz":[f.x,f.y]};break
	check(not away.is_empty(),"Real Forjadores segment available for streaming test")
	if not away.is_empty():
		await world.prepare_at(away)
		for i in range(90):await physics_frame
		await settle(3)
		check(world.runtime_error.is_empty(),"Far road support valid after streaming")
		var freed:=0
		for ref in old_roots:
			if not is_instance_valid(ref.get_ref()):freed+=1
		check(freed>0,"Old sidewalk and prop batches unload with sectors")
		var nearby_decor:=false
		for sector in furniture.sectors.values():
			var owner=sector["owner"].get_ref()
			if is_instance_valid(owner) and owner.get_node_or_null("Sidewalks")!=null:nearby_decor=true
		check(nearby_decor,"Sidewalks regenerate at Forjadores")
		await capture("forjadores")
	world.player.driving_enabled=true
	world.player.set_controls(1,0)
	for i in range(60):await physics_frame
	check(world.player.speed_mps>2,"Driving still accelerates")
	flow.return_to_main_menu();await state(&"main_menu")
	check(not is_instance_valid(world),"World and decoration released on menu return")
	flow.show_screen(&"play_menu");flow.choose_mode(&"race");flow.select_vehicle("APEX");flow.start_selected()
	if flow.current_state==&"race_select":flow.launch_selected_race()
	if await state(&"race"):
		world=current_scene;await settle(3)
		check(world.runtime_error.is_empty() and world.race_activity.competition.rivals.size()>0,"Race and rivals preserved")
		check(world.night_style.furniture.sidewalks.valid,"Same streetscape system in races")
		await capture("race")
		flow.return_to_main_menu();await state(&"main_menu")
	await finish()

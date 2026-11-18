extends SceneTree
const Store=preload("res://scripts/passport/PassportStore.gd")
var flow: Node
var checks:=0
var failures: Array=[]
var capture_enabled:=false
var physics_hashes:={}
var visits: Array=[]

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
func shot(world: Node3D, model_id: String) -> void:
	if not capture_enabled:return
	var entry: Dictionary={}
	for item in world.landmark_models.manifest["models"]:
		if item["id"]==model_id:entry=item;break
	if entry.is_empty():return
	var at:=Vector3(entry["position_xz"][0],0,entry["position_xz"][1])
	at.y=world.player.surface_height(at.x,at.z)
	var low: Array=entry["source_bounds_min"];var high: Array=entry["source_bounds_max"]
	var extent:=maxf(maxf(high[0]-low[0],high[2]-low[2]),high[1]-low[1])*float(entry["scale"])
	var camera:=Camera3D.new();world.add_child(camera);camera.fov=55
	var p: Array=world.passport.active.filter(func(v):return v.get("model_id")==model_id)[0]["activation"]["position_xz"]
	var offset:=(Vector3(p[0],at.y,p[1])-at).normalized()
	if offset.length_squared()<.1:offset=Vector3(1,0,1).normalized()
	camera.position=at+offset*extent*1.5+Vector3.UP*extent*.85
	camera.look_at(at+Vector3.UP*extent*.2);camera.make_current()
	for i in range(12):await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.local/artifacts/evidence/landmark_"+model_id+".png")
	world.follow_camera.camera.make_current();camera.queue_free()
func finish() -> void:
	for path in physics_hashes:check(FileAccess.get_sha256(path)==physics_hashes[path],"Physics/data unchanged "+path)
	var report:={"passed":failures.is_empty(),"checks":checks,"failures":failures,"rendered":capture_enabled,"visits":visits}
	FileAccess.open("res://.local/artifacts/passport_landmarks_validation.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("PASSPORT_LANDMARKS_REPORT ",JSON.stringify(report));await flow.menu_audio.shutdown();quit(0 if failures.is_empty() else 1)

func run() -> void:
	await process_frame
	flow=root.get_node("GameFlow");capture_enabled="--capture-landmarks" in OS.get_cmdline_user_args()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://tests/landmarks"))
	flow.settings_path="user://tests/landmarks/settings.cfg"
	if capture_enabled:root.mode=Window.MODE_WINDOWED;root.size=Vector2i(1280,720)
	for path in ["res://scripts/driving/ArcadeCar.gd","res://scripts/driving/DrivingAbilities.gd","res://data/processed/la_paz_map.json","res://data/processed/arcade_layout.json","res://config/vehicles/vector.json","res://config/vehicles/comet.json","res://config/vehicles/apex.json"]:physics_hashes[path]=FileAccess.get_sha256(path)
	var shipped:=Store.read(Store.CONTENT)
	var legacy:=shipped.duplicate(true);legacy.erase("content_revision");legacy["pois"]=legacy["pois"].slice(0,3)
	legacy["pois"][0]["description"]="Texto local conservado";legacy["pois"][1]["enabled"]=false
	var merged:=Store.upgrade_catalog(legacy,shipped)
	check(merged["pois"].size()==6,"Legacy catalog gains all new places")
	check(merged["pois"][0]["description"]=="Texto local conservado" and not merged["pois"][1]["enabled"],"Legacy edits and disabled entries retained")
	check(Store.upgrade_catalog(merged,shipped)==merged,"Revision upgrade is idempotent")
	check(Store.upgrade_catalog({"pois":"broken"},shipped)=={"pois":"broken"},"Malformed legacy content reaches validation without crashing migration")
	change_scene_to_file(flow.definition["menu_scene"]);await process_frame
	flow.show_screen(&"play_menu");flow.choose_mode(&"free_drive");flow.select_vehicle("COMET");flow.start_selected()
	if flow.current_state==&"race_select":flow.launch_selected_race()
	if not await state(&"free_drive"):await finish();return
	var world=current_scene;var passport=world.passport;var car=world.player
	passport.local_catalog_path="user://tests/landmarks/catalog.json";passport.draft_path="user://tests/landmarks/draft.json"
	passport.store.progress_path="user://tests/landmarks/progress.json";passport.store.discovered={}
	check(passport.apply_catalog(shipped) and passport.active.size()==6,"All six shipped interactions are valid")
	check(world.landmark_models.manifest["models"].size()==10,"All ten supplied models configured")
	var model_refs:={}
	for poi in passport.active:
		car.external_control=true;car.set_controls(0,0,true)
		var p: Vector2=poi["interaction_xz"];var road: Dictionary=flow.road_graph.roads[poi["activation"]["road_id"]]
		check(world.navigation.set_destination(p),"GPS reaches place over the existing mapped network "+poi["id"])
		world.navigation.clear_destination()
		var a: Vector2=flow.road_graph.nodes[str(road["from"])];var b: Vector2=flow.road_graph.nodes[str(road["to"])];var f:=(b-a).normalized()
		await world.prepare_at({"position_xz":[p.x,p.y],"forward_xz":[f.x,f.y]})
		car.driving_enabled=true;world.landmark_models.refresh()
		for i in range(35):await physics_frame
		check(world.runtime_error.is_empty(),"Loaded world valid at "+poi["id"])
		check(passport.eligible(poi,true),"Interaction has safe asphalt support "+poi["id"])
		for profile in ["VECTOR","COMET","APEX"]:
			check(car.apply_vehicle_profile(profile) and car.safe_road_transform(car.global_transform),"Approach accessible with %s: %s"%[profile,poi["id"]])
		check(passport.discover(poi["id"]),"Explicit discovery succeeds "+poi["id"])
		check(not passport.discover(poi["id"]),"No duplicate progress "+poi["id"])
		var id: String=poi.get("model_id","")
		if id!="uabcs_campus":
			check(world.landmark_models.loaded.has(id),"Correct model streamed "+id)
			if world.landmark_models.loaded.has(id):
				var model: Node3D=world.landmark_models.loaded[id]
				check(model.get_meta("poi_id")==poi["id"],"Model bound to its passport interaction "+id)
				model_refs[id]=weakref(model)
				await shot(world,id)
		else:
			var polygon:=PackedVector2Array()
			for point in world.landmark_models.manifest["campus_polygon_xz"]:polygon.append(Vector2(point[0],point[1]))
			check(Geometry2D.is_point_in_polygon(p,polygon),"Main UABCS interaction lies inside the actual campus")
		for loaded in world.city_manager.loaded.values():
			var chunk: Dictionary=world.city_manager.read_chunk(loaded["source"]);world.city_manager.apply_arcade_layout(chunk)
			for building in chunk["buildings"]:
				if world.city_manager.landmark_suppressed.has(building["id"]):check(building.get("disabled",false),"Procedural duplicate suppressed "+building["id"])
		visits.append({"id":poi["id"],"position":[p.x,p.y],"loaded_models":world.landmark_models.loaded.keys()})
	check(passport.count()==6,"All discoveries counted")
	var saved=Store.new();saved.progress_path=passport.store.progress_path;saved.load_progress()
	check(saved.discovered.size()==6,"New and historic stable IDs persist")
	check(passport.open_book(),"Expanded passport opens")
	if capture_enabled:
		await process_frame;await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.local/artifacts/evidence/landmark_passport.png")
	passport.close_book();await process_frame
	check(passport.open_editor(),"Developer editor remains available")
	if is_instance_valid(passport.editor):
		check(passport.editor.draft["pois"].size()==6,"Editor exposes all new points")
		passport.close_editor();await process_frame
	car.speed_mps=10
	check(not passport.eligible(passport.active[-1]),"Speed gate retained")
	flow.return_to_main_menu();await state(&"main_menu")
	check(not is_instance_valid(world),"Landmark world releases on menu return")
	await finish()

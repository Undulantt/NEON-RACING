extends SceneTree
const Neon=preload("res://scripts/ui/NeonButton.gd")
const Store=preload("res://scripts/racing/RaceStore.gd")
var flow: Node
var checks:=0
var failures: Array=[]
var metrics: Dictionary={}
var hashes: Dictionary={}
var capture:=false
func _initialize() -> void:run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok:failures.append(label);push_error(label)
func state(value: StringName) -> bool:
	var deadline:=Time.get_ticks_msec()+120000
	while flow.transition_busy or flow.current_state!=value:
		if Time.get_ticks_msec()>deadline:check(false,"Transition timeout: "+str(value)+" "+flow.navigation_error);return false
		await process_frame
	return true
func shot(name: String) -> void:
	if not capture:return
	for i in range(8):await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.local/artifacts/evidence/coast_release_"+name+".png")
func run() -> void:
	await process_frame;flow=root.get_node("GameFlow");capture="--capture-coast" in OS.get_cmdline_user_args()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://tests/coast_release"));flow.settings_path="user://tests/coast_release/settings.cfg"
	flow.load_settings();flow.set_graphics("fps_limit",0)
	if capture:root.mode=Window.MODE_WINDOWED;root.size=Vector2i(1280,720)
	for path in ["res://scripts/driving/ArcadeCar.gd","res://scripts/driving/DrivingAbilities.gd","res://data/processed/la_paz_map.json","res://data/processed/relief/world/water.json","res://data/races/centro_circuit_d3.json"]:hashes[path]=FileAccess.get_sha256(path)
	change_scene_to_file(flow.definition["menu_scene"]);await process_frame
	flow.show_screen(&"options");current_scene.show_options_page(1)
	check(current_scene.graphic_controls.has("fps_limit"),"Graphics screen exposes FPS cap")
	for value in [30,60,90,0]:
		check(flow.set_graphics("fps_limit",value) and Engine.max_fps==value,"FPS cap applies in menus: "+str(value))
		var saved:=ConfigFile.new();saved.load(flow.settings_path)
		check(saved.get_value("graphics","fps_limit",-1)==value,"FPS cap persists: "+str(value))
	check(not flow.set_graphics("fps_limit",45),"Unsupported FPS setting rejected")
	await shot("graphics")
	flow.show_screen(&"play_menu");flow.choose_mode(&"race");flow.select_vehicle("COMET");flow.start_selected()
	check(flow.current_state==&"race_select" and current_scene.race_buttons.has_all(["circuito_forjadores","arracon_malecon","centro_circuit_d3"]),"Three authored/retained races appear in selector")
	await shot("selector")
	for id in ["circuito_forjadores","arracon_malecon"]:
		check(flow.select_race(id),"Select authored race "+id)
		flow.launch_selected_race()
		if not await state(&"race"):await finish();return
		var activity=current_scene.race_activity
		check(activity.definition["id"]==id and Store.validate(activity.definition,flow.road_graph).is_empty(),"Real OSM route validates: "+id)
		var draft: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/reference/race_drafts/"+activity.definition["authoring_source"]["file"]))
		check(activity.definition["points_xz"]==draft["points_xz"] and activity.definition["checkpoints"]==draft["checkpoints"] and activity.definition["type"]==draft["type"] and activity.definition["laps"]==draft["laps"],"Authored geometry, gates and format preserved: "+id)
		check(activity.competition.grid_columns==2 and activity.competition.player_place()==6 and activity.competition.racers.all(func(r):return r["car"].safe_road_transform(r["car"].global_transform)),"Supported 2x3 grid, player sixth: "+id)
		current_scene.hud.set_pause(true)
		check(current_scene.hud.pause_panel.visible and current_scene.hud.pause_background.visible and current_scene.hud.buttons[0] is Neon,"Race pause uses shared neon buttons and backdrop")
		await shot("pause_"+id);current_scene.hud.set_pause(false)
		flow.return_to_main_menu();await state(&"main_menu")
		flow.show_screen(&"play_menu");flow.choose_mode(&"race");flow.start_selected()
	flow.return_to_main_menu();await state(&"main_menu")
	flow.show_screen(&"play_menu");flow.choose_mode(&"free_drive");flow.start_selected()
	if not await state(&"free_drive"):await finish();return
	var world=current_scene;var activity=world.race_activity
	check(activity.entrances.size()==3 and activity.markers.has_all(["circuito_forjadores","arracon_malecon"]),"Every catalog race has a free-drive entrance")
	for race in activity.entrances:
		var p: Array=race["start"]["position_xz"]
		check(activity.nearest_race(Vector2(p[0],p[1]))["id"]==race["id"],"Interaction resolves correct nearby race "+race["id"])
	var pause_ui=world.hud.free_pause;world.hud.set_pause(true)
	check(pause_ui.menu_buttons["resume"] is Neon and pause_ui.race_choice.item_count==3,"Free pause retains map and destination selection in shared style")
	await process_frame
	check(pause_ui.menu_buttons["menu"].get_global_rect().end.y<=get_root().get_visible_rect().end.y,"Pause menu main-menu action fits without scrolling")
	pause_ui.race_choice.select(2);pause_ui._race_destination()
	check(not world.navigation.destination_id.is_empty(),"Pause sets route to selected race entrance")
	await shot("pause_map");world.hud.set_pause(false)
	var water=world.coast_water
	check(water!=null and water.boundary_count>300 and water.visual.material_override is ShaderMaterial,"Animated water follows existing geographic surface")
	check(water.particles.amount==48 and water.barrier.collision_layer==8,"Bounded water particles and solid coastal barrier")
	flow.set_graphics("water_effects",false)
	check(water.visual.material_override is StandardMaterial3D and not water.particles.visible and water.barrier.collision_layer==8,"Reduced water effects retain safety collision")
	flow.set_graphics("water_effects",true)
	water._process(1)
	check(water.particles.emitting and water.particles.emission_points.size()>0,"Coastal sparkles emit near the player")
	var valid_points:=true
	for p in water.particles.emission_points:
		var at: Vector3=water.particles.global_transform*p
		valid_points=valid_points and water.contains_water(Vector2(at.x,at.z))
	check(valid_points,"Every sparkle emission point stays within mapped water")
	var crossed:=false;var swept:=false;var shore:=Vector2.ZERO;var sea_side:=Vector2.ZERO
	for edge in water.boundary:
		var a: Vector2=edge[0];var b: Vector2=edge[1];var mid: Vector2=(a+b)*.5
		if mid.distance_to(Vector2(world.player.position.x,world.player.position.z))>300:continue
		var side:=Vector2(-(b-a).y,(b-a).x).normalized()
		if not water.contains_water(mid+side*2):side=-side
		var from:=Vector3(mid.x-side.x*3,1,mid.y-side.y*3);var to:=Vector3(mid.x+side.x*3,1,mid.y+side.y*3)
		var query:=PhysicsRayQueryParameters3D.create(from,to,8)
		var hit: Dictionary=world.get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty() and hit["collider"]==water.barrier:
			crossed=true;shore=mid;sea_side=side
			var query_shape:=PhysicsShapeQueryParameters3D.new();query_shape.shape=world.player.collision_shape
			query_shape.transform=Transform3D(Basis.IDENTITY,from);query_shape.motion=to-from;query_shape.collision_mask=8;query_shape.exclude=[world.player.get_rid()]
			var fractions: PackedFloat32Array=world.get_world_3d().direct_space_state.cast_motion(query_shape)
			swept=fractions.size()==2 and fractions[0]<1;break
	check(crossed,"Physical crossing of coastline meets the new barrier")
	check(swept,"Swept vehicle-sized collider cannot cross the coastal wall")
	metrics["coastal_segments"]=water.boundary_count;metrics["particles"]=water.particles.amount
	if capture:
		for i in range(50):await physics_frame
		var camera: Camera3D=world.follow_camera.camera;var pose:=camera.global_transform
		paused=true
		camera.global_position=Vector3(shore.x-sea_side.x*16,7,shore.y-sea_side.y*16)
		camera.look_at(Vector3(shore.x+sea_side.x*22,0,shore.y+sea_side.y*22),Vector3.UP)
		await shot("water");camera.global_transform=pose;paused=false
	# Free-drive entry and return retain vehicle and activity origin.
	activity.confirm_start("arracon_malecon")
	check(activity.prompting,"Free-drive prompt opens for authored race")
	world.request_race("arracon_malecon")
	if await state(&"race"):
		check(flow.race_origin==&"free_drive" and current_scene.race_activity.definition["id"]=="arracon_malecon","Free-drive interaction starts selected authored race")
		flow.return_from_activity();await state(&"free_drive")
		check(current_scene.player.vehicle_profile=="COMET","Return from authored race preserves vehicle")
	flow.return_to_main_menu();await state(&"main_menu");await finish()
func finish() -> void:
	Engine.max_fps=0
	for path in hashes:check(FileAccess.get_sha256(path)==hashes[path],"Protected data unchanged: "+path)
	var report:={"passed":failures.is_empty(),"checks":checks,"failures":failures,"metrics":metrics,"rendered":capture}
	FileAccess.open("res://.local/artifacts/coast_release_validation.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("COAST_RELEASE_REPORT ",JSON.stringify(report));await flow.menu_audio.shutdown();quit(0 if failures.is_empty() else 1)

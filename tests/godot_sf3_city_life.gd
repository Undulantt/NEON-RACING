extends SceneTree
# Real game launch, geographic streaming, shared terrain and menu teardown.
var failures: Array[String] = []
var checks := 0
var samples := []
var world: Node3D

func _initialize() -> void: run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message); push_error(message)

func frames(n: int) -> void:
	for i in range(n):
		await process_frame
		if "--render-life" in OS.get_cmdline_user_args(): await RenderingServer.frame_post_draw

func road_spawn(p: Vector2) -> Dictionary:
	var best := INF
	var chosen := Vector2.ZERO
	var forward := Vector2.UP
	for road in world.map_data["roads"]:
		var a := Vector2(road["points_xz"][0][0],road["points_xz"][0][1])
		var b := Vector2(road["points_xz"][-1][0],road["points_xz"][-1][1])
		var q := Geometry2D.get_closest_point_to_segment(p,a,b)
		if q.distance_squared_to(p)<best:
			best=q.distance_squared_to(p);chosen=q;forward=(b-a).normalized()
	return {"position_xz":[chosen.x,chosen.y],"forward_xz":[forward.x,forward.y]}

func run() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	root.size=Vector2i(1280,720)
	root.content_scale_size=Vector2i(1280,720)
	var flow := root.get_node("GameFlow")
	flow.settings_path="res://tests/.sf3_life_settings.cfg"
	change_scene_to_file(flow.definition["menu_scene"])
	await process_frame
	flow.show_screen(&"play_menu");flow.choose_mode(&"free_drive");flow.select_vehicle("VECTOR");flow.start_selected()
	var deadline := Time.get_ticks_msec()+90000
	while flow.transition_busy or flow.current_state != &"free_drive":
		await process_frame
		if Time.get_ticks_msec()>deadline: push_error("SF3 life launch timeout");quit(1);return
	world=current_scene
	var manager: Node3D=world.city_manager
	check(world.runtime_error.is_empty(),"Free drive launches without map errors")
	check(world.player.vehicle_profile=="VECTOR","Vehicle selection survives launch")
	check(manager.recovery_buildings==235,"235 real footprint recoveries registered")
	check(manager.facades_enabled == (not "--sf3-facades-original" in OS.get_cmdline_user_args()),"Facade comparison flag works independently of recovery")
	var sites := [["soriana",Vector2(632,3773),"Soriana Forjadores"],["tec",Vector2(1223,4405),"Tec de La Paz"],["uabcs",Vector2(296,6352),"UABCS"]]
	for site in sites:
		await world.prepare_at(road_spawn(site[1]))
		world.player.set_physics_process(false)
		world.follow_camera.set_physics_process(false)
		manager.set_physics_process(false)
		# Finish all queued sectors and the bounded facade coroutine.
		manager.refresh()
		for item in manager.pending.duplicate():
			manager.load_chunk(item["chunk"])
			await process_frame
		while world.night_style.decorating: await process_frame
		world.night_style.set_process(false)
		var decorated_before: int=world.night_style.decorated
		for id in manager.loaded.keys():
			if not manager.loaded[id]["node"].has_meta("night_decorated"):
				await world.night_style.decorate(id)
		var count := 0
		var unique := {}
		var foundation_max := 0.0
		for entry in manager.manifest["chunks"]:
			if not manager.loaded.has(entry["id"]): continue
			var data: Dictionary=manager.read_chunk(entry)
			check(not data.is_empty(),"Loaded sector reads with verified hash")
			for b in data.get("buildings",[]):
				check(not unique.has(b["id"]),"No duplicate building while merging recovery")
				unique[b["id"]]=true
				if b.get("site","")!=site[2]: continue
				count+=1
				for p in b["elevation_samples_xz"]:
					check(b["base_y_m"]+0.001>=world.player.surface_height(p[0],p[1]),"Recovered roof foundation stays above canonical terrain")
				foundation_max=maxf(foundation_max,b["base_y_m"]-b["foundation_min_y_m"])
		check(count>0,str(site[2])+" renders in streamed sectors near an existing road")
		check(manager.failed_chunks.is_empty(),"No failed/referenced-invalid sector")
		var mesh_count := 0
		var vertices := 0
		for loaded in manager.loaded.values():
			for visual in loaded["node"].find_children("*","MeshInstance3D",true,false):
				mesh_count+=1
				for surface in range(visual.mesh.get_surface_count()): vertices+=visual.mesh.surface_get_array_len(surface)
		var sample := {"site":site[2],"loaded_recoveries":count,"loaded_sectors":manager.loaded.size(),"meshes":mesh_count,"vertices":vertices,"max_foundation_spread_m":foundation_max,"new_decorations":world.night_style.decorated-decorated_before}
		if "--render-life" in OS.get_cmdline_user_args():
			var camera:=Camera3D.new()
			world.add_child(camera)
			var center: Vector2=site[1]
			var ground: float=world.player.surface_height(center.x,center.y)
			camera.position=Vector3(center.x+240,ground+280,center.y+290)
			camera.look_at(Vector3(center.x,ground,center.y))
			camera.current=true
			var warmup_end:=Time.get_ticks_msec()+2000
			while Time.get_ticks_msec()<warmup_end: await frames(1)
			var intervals: Array[float]=[]
			var previous:=Time.get_ticks_usec()
			for i in range(240):
				await frames(1)
				var now:=Time.get_ticks_usec()
				intervals.append((now-previous)/1000.0);previous=now
			intervals.sort()
			sample["median_ms"]=intervals[120];sample["p95_ms"]=intervals[228]
			sample["draw_calls"]=Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
			var mode: String="original" if not manager.facades_enabled else "life"
			root.get_texture().get_image().save_png("res://docs/evidence/sf3_%s_%s.png"%[site[0],mode])
			camera.queue_free()
		samples.append(sample)
		print("SF3_CITY_LIFE_SAMPLE ",JSON.stringify(sample))
		world.night_style.set_process(true)
	check(manager.total_chunk_unloads>0,"Travel between sites unloads old sectors")
	var status: Dictionary=manager.status()
	flow.return_to_main_menu()
	await frames(10)
	check(flow.current_state==&"main_menu","Return to main menu after streaming all three sites")
	check(not is_instance_valid(world),"World and decoration coroutines released")
	var result:={"passed":failures.is_empty(),"checks":checks,"failures":failures,"samples":samples,"status":status,"renderer":RenderingServer.get_video_adapter_name(),"note":"Real game transitions and frozen views at three existing road locations. Static render samples are not driving FPS."}
	var label: String="original" if "--sf3-facades-original" in OS.get_cmdline_user_args() else "life"
	if "--flat-world" in OS.get_cmdline_user_args(): label+="_flat"
	FileAccess.open("res://docs/sf3_city_life_%s_validation.json"%label,FileAccess.WRITE).store_string(JSON.stringify(result,"  "))
	if FileAccess.file_exists(flow.settings_path): DirAccess.remove_absolute(flow.settings_path)
	print("SF3_CITY_LIFE_RESULT ",JSON.stringify({"passed":failures.is_empty(),"checks":checks,"failures":failures}))
	quit(0 if failures.is_empty() else 1)

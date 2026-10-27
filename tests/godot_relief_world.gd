extends "res://tests/godot_phase_b.gd"

func place(p: Vector3, forward: Vector3) -> void:
	p.y = car.supported_pose_height(p.x,p.z,atan2(-forward.x,-forward.z))
	super.place(p,forward)

func _run() -> void:
	# Exercise the actual F5 scene without an elevation command-line override.
	world = preload("res://scenes/Main.tscn").instantiate()
	root.add_child(world)
	await physics_frame
	await physics_frame
	if world.player == null or world.relief_manifest.is_empty():
		check(false,"World relief not ready")
		quit(1)
		return
	car = world.player
	car.external_control = true
	await step(45)
	check(world.relief_profile == "world", "Production main scene must enable full relief")
	var original_environment: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/processed/la_paz_environment.json"))
	var original_spawn: Array = original_environment["spawn"]["position_xz"]
	check(Vector2(car.spawn_transform.origin.x,car.spawn_transform.origin.z).distance_to(Vector2(original_spawn[0],original_spawn[1]))<0.001,"Production spawn moved to the northern pilot")
	check(car.on_asphalt and car.is_on_floor(), "Production spawn lacks elevated road support")
	check(car.safe_road_transform(car.global_transform), "Production spawn unsafe for recovery/F8")
	check(world.city_manager.set_city_enabled(false) and world.city_manager.set_city_enabled(true), "F8 failed at production spawn")
	check(world.building_root.get_node_or_null("ClippedSafetyPlatform")==null and world.building_root.get_node_or_null("NeutralSafetyPlatform")==null, "Flat platform duplicated under relief")
	var results := {}
	for entry in world.expansion["routes"]:
		points.clear()
		lengths.clear()
		route_progress = 0
		route_index = 0
		metrics = {}
		world.environment_data["driving_test_route"] = JSON.parse_string(FileAccess.get_file_as_string("res://"+str(entry["file"])))
		print("RELIEF_WORLD_ROUTE ",entry["id"])
		route_frame_limit = 90000
		await drive_route()
		results[entry["id"]]=metrics.duplicate()
	var anchors := 0
	for anchor in world.expansion["anchors"]:
		var p: Array = anchor["position_xz"]
		place(Vector3(p[0],0,p[1]),Vector3.FORWARD)
		await step(45)
		check(car.on_asphalt and car.is_on_floor(),"Anchor lost elevated support: "+str(anchor["id"]))
		anchors += 1
	check(world.road_root.failed_chunks.is_empty() and world.terrain_root.failed_chunks.is_empty(),"Failed streamed relief sectors")
	check(world.terrain_root.total_unloads>0,"Terrain did not unload")
	check(world.road_root.total_unloads>0,"Roads did not unload")
	car.safe_transform = car.spawn_transform
	world.road_root.ensure_recovery_support()
	world.terrain_root.ensure_recovery_support()
	car.recover()
	await step(30)
	check(car.on_asphalt and car.is_on_floor(),"Distant recovery lost support")
	var report := {"passed":failures.is_empty(),"failures":failures,"default_main_profile":world.relief_profile,"production_spawn_xz":original_spawn,"routes":results,"anchors_tested":anchors,"road_streaming":world.road_root.status(),"terrain_streaming":world.terrain_root.status(),"urban_streaming":world.city_manager.status(),"static_memory_bytes":Performance.get_monitor(Performance.MEMORY_STATIC)}
	var file := FileAccess.open("res://docs/phase_b7r_default_integration.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	print("RELIEF_WORLD_REPORT ",JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)

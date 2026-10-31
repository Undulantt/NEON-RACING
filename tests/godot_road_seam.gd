extends SceneTree

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var world := preload("res://scenes/Main.tscn").instantiate()
	root.add_child(world)
	await physics_frame
	await physics_frame
	var car: CharacterBody3D = world.player
	car.set_physics_process(false)
	var point := Vector3(144,0,1020.795)
	car.position = point
	for manager in [world.road_root,world.terrain_root]:
		manager.anchor=point
		manager.refresh(true)
	await physics_frame
	var failures := []
	var central_misses := 0
	var samples := 0
	for dx in [-0.00003,0.0,0.00003]:
		for i in range(41):
			var p := point + Vector3(dx,0,(i-20)*0.005)
			p.y=car.surface_height(p.x,p.z)+0.67
			var query := PhysicsRayQueryParameters3D.create(p+Vector3.UP*1.13,p-Vector3.UP*2.5,1)
			central_misses+=int(world.get_world_3d().direct_space_state.intersect_ray(query).is_empty())
			if not car.road_hit(p):failures.append(str(p))
			samples+=1
	var report := {"passed":failures.is_empty(),"failures":failures,"seam_x":144,"samples":samples,"raw_central_ray_misses":central_misses,"fallback_radius_m":0.001,"controller_sha256":FileAccess.get_sha256("res://scripts/driving/ArcadeCar.gd")}
	var file := FileAccess.open("res://docs/map_extension_seam_validation.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	print("ROAD_SEAM_REPORT ",JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)

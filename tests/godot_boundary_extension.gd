extends "res://tests/godot_relief_world.gd"

func _run() -> void:
	world = preload("res://scenes/Main.tscn").instantiate()
	root.add_child(world)
	await physics_frame
	await physics_frame
	check(world.player != null and world.runtime_error.is_empty(), "Extended world failed to start")
	if world.player == null:
		quit(1)
		return
	car = world.player
	car.external_control = true
	await step(60)
	var report_routes := {}
	var entries: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://docs/map_extension_routes.json"))
	for entry in entries["routes"]:
		points.clear()
		lengths.clear()
		route_progress = 0
		route_index = 0
		metrics = {}
		world.environment_data["driving_test_route"] = JSON.parse_string(FileAccess.get_file_as_string("res://" + entry["file"]))
		route_frame_limit = 90000
		print("EXTENSION_ROUTE ", entry["area"])
		await drive_route()
		report_routes[entry["area"]] = metrics.duplicate()
	# Exercise physical ridge collisions from the playable side, including a
	# debug-turbo-speed airborne approach. No recovery may mask a barrier failure.
	var polygon := PackedVector2Array()
	var ring: Array = world.relief_manifest["boundary_xz"]
	for p in ring:
		polygon.append(Vector2(p[0],p[1]))
	var barriers := []
	for i in range(ring.size()):
		var a := Vector3(ring[i][0],0,ring[i][1])
		var b := Vector3(ring[(i+1)%ring.size()][0],0,ring[(i+1)%ring.size()][1])
		if a.distance_to(b)<120:
			continue
		var middle := (a+b)*0.5
		var side := (b-a).normalized()
		var outward := Vector3(side.z,0,-side.x)
		if Geometry2D.is_point_in_polygon(Vector2(middle.x+outward.x*3,middle.z+outward.z*3),polygon):
			outward = -outward
		var h: float = car.surface_height(middle.x,middle.z)
		if not is_finite(h):
			continue
		var query := PhysicsRayQueryParameters3D.create(Vector3(middle.x,h+20,middle.z)-outward*10,Vector3(middle.x,h+20,middle.z)+outward*20,8)
		# Sea walls are intentionally low and invisible; skip those edges.
		if world.get_world_3d().direct_space_state.intersect_ray(query).is_empty():
			place(middle-outward*20,outward)
			for manager in [world.road_root,world.terrain_root,world.limit_root]:
				manager.anchor=car.position
				manager.refresh(true)
			await step(35,0,0,true)
			if world.get_world_3d().direct_space_state.intersect_ray(query).is_empty():
				continue
		var start := middle-outward*16
		start.y=car.supported_pose_height(start.x,start.z,atan2(-outward.x,-outward.z))
		var pose := Transform3D(Basis(Vector3.UP,atan2(-outward.x,-outward.z)),start)
		if not car.clear_of_obstacles(pose):
			continue
		place(start,outward)
		await step(30,0,0,true)
		if not car.is_on_floor():
			continue
		var contacts: int = car.wall_contacts
		var recoveries: int = car.recovery_count
		car.debug_speed_enabled = true
		car.global_position.y += 2
		car.velocity = outward*88 + Vector3.UP*6
		car.reset_surface_motion()
		car.set_controls(1,0,false,true)
		var furthest := -INF
		var peak := car.position.y
		for frame in range(120):
			await physics_frame
			furthest=maxf(furthest,(car.position-middle).dot(outward))
			peak=maxf(peak,car.position.y)
		check(car.wall_contacts>contacts,"Mountain ridge did not stop an 88m/s airborne approach")
		check(car.recovery_count==recoveries,"Recovery masked mountain collision")
		check(furthest<6,"Car climbed or crossed the steep mountain face")
		barriers.append({"edge":i,"approach_mps":88,"furthest_outside_m":furthest,"wall_contacts":car.wall_contacts-contacts,"recoveries":car.recovery_count-recoveries,"peak_y":peak})
		car.debug_speed_enabled=false
		if barriers.size()>=3:
			break
	check(barriers.size()>=3,"Fewer than three real mountain barriers tested")
	var report := {"passed":failures.is_empty(),"failures":failures,"routes":report_routes,"mountain_collisions":barriers,"terrain_streaming":world.terrain_root.status(),"boundary_streaming":world.limit_root.status()}
	var file := FileAccess.open("res://docs/map_extension_physics.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	print("EXTENSION_REPORT ",JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)

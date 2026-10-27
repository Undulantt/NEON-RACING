extends "res://tests/godot_phase_b.gd"

func _run() -> void:
	world = Main.instantiate()
	root.add_child(world)
	await physics_frame
	await physics_frame
	if world.player == null or world.relief_manifest.is_empty():
		check(false, "Relief pilot did not load")
		quit(1)
		return
	car = world.player
	car.external_control = true
	await step(30)
	check(car.is_on_floor() and car.on_asphalt, "Elevated spawn unsupported")
	check(car.safe_road_transform(car.global_transform), "Elevated pose not safe for recovery")
	check(world.building_root.find_children("NeutralSafetyPlatform", "", true, false).is_empty(), "Flat platform duplicated")
	var road_samples := 0
	var max_error := 0.0
	for road in world.map_data["roads"]:
		for p in road["points_xz"]:
			var h: float = world.elevation.get_height_at(p[0], p[1])
			var query := PhysicsRayQueryParameters3D.create(Vector3(p[0], h+2, p[1]), Vector3(p[0], h-2, p[1]), 1)
			var hit := world.get_world_3d().direct_space_state.intersect_ray(query)
			if not hit.is_empty():
				max_error = maxf(max_error, absf(hit["position"].y-h))
				road_samples += 1
	check(road_samples > 20 and max_error < 0.002, "Elevation query differs from physics road")
	metrics["raycast_samples"] = road_samples
	metrics["max_physics_height_error_m"] = max_error
	await acceleration_and_braking()
	await high_speed_slope()
	for reverse in [false,true]:
		await traverse(reverse)
	car.recover()
	await step(30)
	check(car.is_on_floor() and car.on_asphalt, "Elevated recovery failed")
	check(world.city_manager.set_city_enabled(false), "F8 disable failed")
	check(world.city_manager.set_city_enabled(true), "F8 restore failed")
	await boundary_collision()
	metrics["road_streaming"] = world.road_root.status()
	metrics["terrain_streaming"] = world.terrain_root.status()
	var report := {"passed": failures.is_empty(), "failures": failures, "metrics": metrics, "physics_frames": test_frames}
	var file := FileAccess.open("res://docs/phase_b7r_pilot_physics.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))
	print("RELIEF_REPORT ", JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)

func traverse(reverse: bool) -> void:
	var route: Array = world.relief_manifest["route_xz"].duplicate(true)
	if reverse:
		route.reverse()
	points.clear()
	lengths.clear()
	route_index = 0
	route_progress = 0
	for p in route:
		points.append(Vector3(p[0], 0, p[1]))
	lengths.append(0)
	for i in range(1, points.size()):
		lengths.append(lengths[-1]+points[i].distance_to(points[i-1]))
	var start := sample(8)
	start.y = world.elevation.get_height_at(start.x,start.z)+1.0
	place(start, (points[1]-points[0]).normalized())
	await step(30)
	var offroad := 0
	var unsupported := 0
	var recoveries: int = car.recovery_count
	var contacts: int = car.wall_contacts
	var frames := 0
	var min_y := car.position.y
	var max_y := min_y
	var seam_cells := {}
	var offroad_probes: Array = []
	var wheel_error := 0.0
	while route_progress < lengths[-1]-4 and frames < 15000:
		var point := Vector3(car.position.x,0,car.position.z)
		var best := INF
		for i in range(maxi(0,route_index-2),mini(points.size()-1,route_index+6)):
			var closest := Geometry3D.get_closest_point_to_segment(point,points[i],points[i+1])
			if point.distance_to(closest)<best:
				best=point.distance_to(closest)
				route_index=i
				route_progress=maxf(route_progress,lengths[i]+points[i].distance_to(closest))
		var desired := 8.0
		for i in range(maxi(1,route_index),mini(points.size()-1,route_index+6)):
			if lengths[i]-route_progress>22:
				break
			if lengths[i]>route_progress-5 and (points[i]-points[i-1]).normalized().dot((points[i+1]-points[i]).normalized())<0.85:
				desired=4.0
		var direction := (sample(minf(route_progress+3+car.speed_mps*.35,lengths[-1]))-point).normalized()
		var error := wrapf(atan2(-direction.x,-direction.z)-car.rotation.y,-PI,PI)
		await step(1,clampf((desired-car.speed_mps)*.7,-1,1),clampf(-error*2,-1,1))
		frames+=1
		offroad+=int(not car.on_asphalt)
		if not car.on_asphalt and offroad_probes.size()<6:
			var qp := PhysicsRayQueryParameters3D.create(car.position+Vector3.UP*3,car.position-Vector3.UP*5,3)
			var hit := world.get_world_3d().direct_space_state.intersect_ray(qp)
			offroad_probes.append({"position":[car.position.x,car.position.y,car.position.z],"height":world.elevation.get_height_at(car.position.x,car.position.z),"nearest_deviation":best,"collider":str(hit.get("collider","none"))})
		unsupported+=int(not car.is_on_floor())
		min_y=minf(min_y,car.position.y)
		max_y=maxf(max_y,car.position.y)
		seam_cells[Vector2i(floori(car.position.x/256),floori(car.position.z/256))]=true
		for pivot in car.visuals["pivots"]:
			var wp: Vector3 = pivot.global_position
			wheel_error=maxf(wheel_error,absf(wp.y-world.elevation.get_height_at(wp.x,wp.z)-0.34))
		if best>12 or car.recovery_count>recoveries:
			break
	metrics["reverse" if reverse else "forward"]={"distance_m":route_progress,"expected_m":lengths[-1],"offroad_frames":offroad,"unsupported_frames":unsupported,"wall_contacts":car.wall_contacts-contacts,"recoveries":car.recovery_count-recoveries,"height_range_m":[min_y,max_y],"sectors_crossed":seam_cells.size(),"frames":frames,"offroad_probes":offroad_probes}
	check(route_progress>=lengths[-1]-4,"Route incomplete")
	check(offroad==0 and unsupported==0,"Road/ground contact lost on slope")
	check(car.wall_contacts==contacts and car.recovery_count==recoveries,"Route required collision or recovery")
	check(max_y-min_y>10 and seam_cells.size()>=2,"Test did not exercise real slope and sector boundary")
	check(wheel_error<0.03,"Visual wheels do not follow road")
	metrics["wheel_error_reverse_m" if reverse else "wheel_error_forward_m"] = wheel_error

func acceleration_and_braking() -> void:
	var route: Array = world.relief_manifest["route_xz"]
	var a := Vector3(route[0][0],0,route[0][1])
	var b := Vector3(route[1][0],0,route[1][1])
	for reverse in [false,true]:
		var direction := (b-a).normalized() if not reverse else (a-b).normalized()
		var p := (a if not reverse else b)+direction*20
		var yaw := atan2(-direction.x,-direction.z)
		p.y=car.supported_pose_height(p.x,p.z,yaw)
		place(p,direction)
		await step(30)
		var y0 := car.position.y
		await step(90,1)
		var speed: float = car.speed_mps
		var braking_frames := 0
		while car.signed_speed>0.15 and braking_frames<120:
			await step(1,-1)
			braking_frames+=1
		check(speed>8 and braking_frames>10 and braking_frames<100,"Acceleration/braking on slope failed")
		check(car.is_on_floor() and car.on_asphalt,"Lost support while braking on slope")
		metrics["braking_reverse" if reverse else "braking_forward"]={"speed_before_braking_mps":speed,"braking_frames":braking_frames,"height_change_m":car.position.y-y0}

func high_speed_slope() -> void:
	var route: Array = world.relief_manifest["route_xz"]
	var a := Vector3(route[0][0],0,route[0][1])
	var b := Vector3(route[1][0],0,route[1][1])
	var direction := (b-a).normalized()
	var p := a+direction*15
	p.y=car.supported_pose_height(p.x,p.z,atan2(-direction.x,-direction.z))
	place(p,direction)
	await step(30)
	car.velocity=direction*30
	car.turbo_charge=1.0
	car.set_controls(1,0,false,true)
	var unsupported := 0
	var offroad := 0
	var maximum := 0.0
	for frame in range(60):
		await physics_frame
		test_frames+=1
		unsupported+=int(not car.is_on_floor())
		offroad+=int(not car.on_asphalt)
		maximum=maxf(maximum,car.speed_mps)
	car.set_controls(0,0)
	check(unsupported==0 and offroad==0 and maximum>35,"High speed/turbo lost slope support")
	metrics["high_speed_slope"]={"maximum_speed_mps":maximum,"unsupported_frames":unsupported,"offroad_frames":offroad}

func boundary_collision() -> void:
	var ring: Array = world.relief_manifest["boundary_xz"]
	var polygon := PackedVector2Array()
	for p in ring:
		polygon.append(Vector2(p[0],p[1]))
	var tested := false
	for i in range(ring.size()):
		var a := Vector3(ring[i][0],0,ring[i][1])
		var b := Vector3(ring[(i+1)%ring.size()][0],0,ring[(i+1)%ring.size()][1])
		for t in [.25,.5,.75]:
			var middle := a.lerp(b,t)
			var side := (b-a).normalized()
			var outward := Vector3(side.z,0,-side.x)
			if Geometry2D.is_point_in_polygon(Vector2(middle.x+outward.x*3,middle.z+outward.z*3),polygon):
				outward = -outward
			var p := middle-outward*10
			p.y=car.supported_pose_height(p.x,p.z,atan2(-outward.x,-outward.z))
			var pose := Transform3D(Basis(Vector3.UP,atan2(-outward.x,-outward.z)),p)
			if not car.clear_of_obstacles(pose):
				continue
			place(p,outward)
			await step(30)
			if not car.is_on_floor():
				continue
			var contacts: int = car.wall_contacts
			await step(180,1)
			check(car.wall_contacts>contacts and car.speed_mps<.2,"Streamed boundary failed to stop car")
			check(Geometry2D.is_point_in_polygon(Vector2(car.position.x,car.position.z),polygon),"Car escaped pilot boundary")
			tested=true
			break
		if tested:
			break
	check(tested,"No boundary collision test executed")
	metrics["boundary_collision_tested"]=tested

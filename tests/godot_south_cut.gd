extends "res://tests/godot_phase_b.gd"

func local_point(lon: float, lat: float) -> Vector3:
	return Vector3(6371000.0 * deg_to_rad(lon + 110.3195) * cos(deg_to_rad(24.159)), 0.67, -6371000.0 * deg_to_rad(lat - 24.159))

func ground_at(p: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 3, p - Vector3.UP * 4, 3)
	return not world.get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func _run() -> void:
	world = Main.instantiate()
	root.add_child(world)
	await physics_frame
	await physics_frame
	if world.player == null:
		check(false, world.runtime_error)
		quit(1)
		return
	car = world.player
	car.external_control = true
	await step(30)
	for point in [Vector2(-110.339,24.094), Vector2(-110.296,24.11), Vector2(-110.317,24.0905)]:
		check(not ground_at(local_point(point.x,point.y)), "Excluded southern ground or asphalt still has a collider")
	for anchor in world.expansion["anchors"]:
		if anchor["id"] in ["uabcs", "hospital_salvatierra", "conexion_sur"]:
			var p: Array = anchor["position_xz"]
			place(Vector3(p[0],0.67,p[1]),Vector3.FORWARD)
			await step(30)
			check(car.on_asphalt and car.is_on_floor(), "Retained southern anchor lost road support: " + str(anchor["id"]))
	var ring: Array = world.environment_data["playable_boundary_xz"]
	var polygon := PackedVector2Array()
	for p in ring:
		polygon.append(Vector2(p[0],p[1]))
	var tested := false
	for i in range(ring.size()):
		var a := Vector3(ring[i][0],0,ring[i][1])
		var b := Vector3(ring[(i+1)%ring.size()][0],0,ring[(i+1)%ring.size()][1])
		var middle := (a+b)*0.5
		if middle.z < 4200 or a.distance_to(b)<40:
			continue
		var side := (b-a).normalized()
		var outward := Vector3(side.z,0,-side.x)
		var probe := middle+outward*8
		if Geometry2D.is_point_in_polygon(Vector2(probe.x,probe.z),polygon):
			outward = -outward
		var start := middle-outward*12+Vector3.UP*0.67
		var pose := Transform3D(Basis(Vector3.UP,atan2(-outward.x,-outward.z)),start)
		if not car.clear_of_obstacles(pose):
			continue
		place(start,outward)
		await step(20)
		var before: int = car.wall_contacts
		await step(240,1)
		check(car.wall_contacts>before and car.speed_mps<0.2, "Car must stop at the clipped boundary")
		check(Geometry2D.is_point_in_polygon(Vector2(car.position.x,car.position.z),polygon), "Car escaped into excluded southern space")
		check(car.is_on_floor(), "Car lost safety ground at clipped edge")
		tested=true
		break
	check(tested,"No clear clipped-edge collision test available")
	var report := {"passed":failures.is_empty(),"failures":failures,"excluded_ground_probes":3,"retained_anchor_probes":3,"clipped_edge_collision_tested":tested}
	var output := FileAccess.open("res://docs/phase_c5_south_cut_physics.json",FileAccess.WRITE)
	output.store_string(JSON.stringify(report,"  "))
	print("SOUTH_CUT_REPORT ",JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)

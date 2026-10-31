extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	run.call_deferred()

func check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
		push_error(message)

func run() -> void:
	var world := preload("res://scenes/Main.tscn").instantiate()
	root.add_child(world)
	await physics_frame
	await physics_frame
	check(world.player != null and world.runtime_error.is_empty(), "Corrected world failed to start")
	if world.player == null:
		quit(1)
		return
	world.player.set_physics_process(false)
	var sea_point := Vector3(-1700,0,-1000)
	var water_cell := Vector2i(floori(sea_point.x/256),floori(sea_point.z/256))
	check(not world.terrain_root.entries.has(water_cell), "A2 still contains a terrain sector in the fully maritime cell")
	check(not world.road_root.entries.has(water_cell), "A2 still contains an asphalt sector")
	var center := Vector3(2285.29,0,889.56)
	world.player.position = center
	for manager in [world.road_root,world.terrain_root,world.limit_root]:
		manager.anchor=center
		manager.refresh(true)
	await physics_frame
	var space: PhysicsDirectSpaceState3D = world.get_world_3d().direct_space_state
	var outward := Vector3(1,0,-1).normalized()
	var height: float = world.elevation.get_height_at(center.x,center.z)
	var near_query := PhysicsRayQueryParameters3D.create(center-outward*10+Vector3.UP*(height+35),center+outward*35+Vector3.UP*(height+35),8)
	check(space.intersect_ray(near_query).is_empty(), "Old mountain front still obstructs the Centre/South join")
	var far_query := PhysicsRayQueryParameters3D.create(center+outward*35+Vector3.UP*(height+35),center+outward*150+Vector3.UP*(height+35),8)
	var mountain: Dictionary = space.intersect_ray(far_query)
	check(not mountain.is_empty(), "Retreated mountain lost collision")
	var at := center+outward*30
	var floor_height: float = world.elevation.get_height_at(at.x,at.z)
	var ground_query := PhysicsRayQueryParameters3D.create(at+Vector3.UP*(floor_height+3),at+Vector3.UP*(floor_height-5),2)
	check(not space.intersect_ray(ground_query).is_empty(), "Terrain gap opened before the retreated mountain")
	var distance := -1.0
	var boundary_distance := INF
	var ring: Array = world.relief_manifest["boundary_xz"]
	var origin := Vector2(center.x,center.z)
	var direction := Vector2(outward.x,outward.z)
	for i in range(ring.size()):
		var a := Vector2(ring[i][0],ring[i][1])
		var b := Vector2(ring[(i+1)%ring.size()][0],ring[(i+1)%ring.size()][1])
		var crossing = Geometry2D.segment_intersects_segment(origin,origin+direction*150,a,b)
		if crossing != null:
			boundary_distance=minf(boundary_distance,origin.distance_to(crossing))
	var before: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://docs/coast_fix_baseline/relief_manifest.json"))
	var old_ring: Array = before["boundary_xz"]
	var boundary_point := origin+direction*boundary_distance
	var normal_setback := INF
	for i in range(old_ring.size()):
		var a := Vector2(old_ring[i][0],old_ring[i][1])
		var b := Vector2(old_ring[(i+1)%old_ring.size()][0],old_ring[(i+1)%old_ring.size()][1])
		normal_setback=minf(normal_setback,boundary_point.distance_to(Geometry2D.get_closest_point_to_segment(boundary_point,a,b)))
	check(normal_setback>45 and normal_setback<=60.1,"Local contour did not retreat by the configured gradual normal offset")
	if not mountain.is_empty():
		distance=Vector2(mountain["position"].x-center.x,mountain["position"].z-center.z).length()
		check(distance>=boundary_distance-.1 and distance<boundary_distance+16,"Collision does not follow the retreated contour's steep front")
	var report := {"passed":failures.is_empty(),"failures":failures,"A2_terrain_absent":not world.terrain_root.entries.has(water_cell),"normal_setback_m":normal_setback,"boundary_distance_along_diagonal_m":boundary_distance,"join_mountain_collision_distance_m":distance,"terrain_before_mountain_supported":not space.intersect_ray(ground_query).is_empty(),"manifest_sha256":FileAccess.get_sha256("res://data/processed/relief/world/manifest.json")}
	var file := FileAccess.open("res://docs/coast_fix_physics.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	print("COAST_FIX_REPORT ",JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)

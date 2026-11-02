extends SceneTree
func _initialize() -> void: run.call_deferred()
func run() -> void:
	root.size=Vector2i(1280,720)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var world=load("res://scenes/Main.tscn").instantiate();root.add_child(world)
	for i in range(30): await physics_frame
	var car=world.player;car.external_control=true
	var points: Array[Vector3]=[];var lengths: Array[float]=[0.0]
	for p in world.environment_data["driving_test_route"]["points_xz"]: points.append(Vector3(p[0],0,p[1]))
	for i in range(1,points.size()): lengths.append(lengths[-1]+points[i].distance_to(points[i-1]))
	var dir:=(points[1]-points[0]).normalized()
	car.rotation.y=atan2(-dir.x,-dir.z)
	car.position=points[0]+Vector3.UP*car.supported_pose_height(points[0].x,points[0].z,car.rotation.y)
	car.velocity=Vector3.ZERO;car.reset_surface_motion();world.follow_camera.snap()
	for i in range(90): await physics_frame
	var intervals: Array[float]=[];var progress:=0.0;var segment:=0;var over33:=0;var over16:=0
	var stalls: Array=[]
	if world.night_style!=null: world.night_style.work_log.clear()
	var previous:=Time.get_ticks_usec()
	for frame in range(1500):
		var position:=Vector3(car.position.x,0,car.position.z);var best:=INF
		for i in range(maxi(0,segment-2),mini(points.size()-1,segment+8)):
			var close:=Geometry3D.get_closest_point_to_segment(position,points[i],points[i+1])
			if position.distance_squared_to(close)<best:
				best=position.distance_squared_to(close);segment=i;progress=maxf(progress,lengths[i]+points[i].distance_to(close))
		var desired:=12.0
		for i in range(maxi(1,segment),mini(points.size()-1,segment+8)):
			if lengths[i]-progress>25: break
			if lengths[i]>progress-4 and (points[i]-points[i-1]).normalized().dot((points[i+1]-points[i]).normalized())<0.85: desired=5.0
		var at:=minf(progress+3+car.speed_mps*0.35,lengths[-1])
		var index:=clampi(lengths.bsearch(at)-1,0,points.size()-2)
		var target:=points[index].lerp(points[index+1],clampf((at-lengths[index])/(lengths[index+1]-lengths[index]),0,1))
		var direction:=(target-position).normalized();var yaw:=atan2(-direction.x,-direction.z)
		car.set_controls(clampf((desired-car.speed_mps)*0.7,-1,1),clampf(-wrapf(yaw-car.rotation.y,-PI,PI)*2,-1,1))
		await process_frame
		var now:=Time.get_ticks_usec();var ms:=(now-previous)/1000.0;previous=now
		intervals.append(ms)
		if ms>33.3:
			over33+=1
			stalls.append({"frame":frame,"ms":ms,"work":world.night_style.work_log.duplicate(true) if world.night_style!=null else [],"physics_ms":Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000,"process_ms":Performance.get_monitor(Performance.TIME_PROCESS)*1000})
		if world.night_style!=null: world.night_style.work_log.clear()
		if ms>16.7: over16+=1
	intervals.sort();var total:=0.0
	for value in intervals: total+=value
	var report:={"mean_ms":total/intervals.size(),"p95_ms":intervals[int(intervals.size()*0.95)],"p99_ms":intervals[int(intervals.size()*0.99)],"max_ms":intervals[-1],"over_16_ms":over16,"over_33_ms":over33,"distance_m":progress,"frames":intervals.size(),"stalls":stalls,"scenario":"1280x720 Compatibility, VSync off, fixed 60 simulation, real route controller, 1500 render frames; short streaming run, not city-wide guarantee"}
	var collider_hits:={}
	var move_hits:={}
	if world.night_style!=null and not "--before" in OS.get_cmdline_user_args():
		for item in world.city_manager.loaded.values():
			var body=item["node"].get_node_or_null("StreetFurnitureCollision")
			if body==null or body.collision_layer!=4: continue
			for shape in body.get_children():
				var kind: String=shape.get_meta("fixture_kind","")
				if move_hits.has(kind): continue
				var center: Vector3=shape.global_position
				var query:=PhysicsRayQueryParameters3D.create(center+Vector3.RIGHT,center,4)
				var hit: Dictionary=world.get_world_3d().direct_space_state.intersect_ray(query)
				if not hit.is_empty() and hit["collider"]==body: collider_hits[kind]=true
				var pose: Transform3D=car.global_transform;pose.origin=center-Vector3.RIGHT*3
				var collision:=KinematicCollision3D.new()
				if car.test_move(pose,Vector3.RIGHT*4,collision) and collision.get_collider()==body: move_hits[kind]=true
		var disabled: bool=world.city_manager.set_city_enabled(false)
		world.night_style.furniture.update_lights()
		for pool in world.night_style.furniture.street_pools: disabled=disabled and pool.w==0
		for item in world.city_manager.loaded.values():
			var body=item["node"].get_node_or_null("StreetFurnitureCollision")
			if body!=null: disabled=disabled and body.collision_layer==0
		report["furniture_ray_hits"]=collider_hits;report["car_collision_hits"]=move_hits;report["F8_disables_collision"]=disabled
		report["collision_passed"]=move_hits.has("lamp") and move_hits.has("palm") and move_hits.has("tree") and disabled
		for node in world.night_style.get_children():
			if node.get_script()==load("res://scripts/style/RetroLook.gd"):
				report["baked_neon_loads"]=node.baked_loads;report["runtime_neon_builds"]=node.runtime_builds
		report["max_city_chunk_build_ms"]=world.city_manager.max_chunk_build_ms
		report["max_road_chunk_build_ms"]=world.road_root.max_build_ms
		report["max_terrain_chunk_build_ms"]=world.terrain_root.max_build_ms
	var suffix:="no_lamps" if "--no-street-lights" in OS.get_cmdline_user_args() else "day" if world.night_style==null else "before" if "--before" in OS.get_cmdline_user_args() else "after"
	FileAccess.open("res://docs/phase_e_stream_"+suffix+".json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("STREAM_PERF ",JSON.stringify(report))
	world.queue_free()
	for i in range(8): await process_frame
	quit(0 if report.get("collision_passed",true) else 1)

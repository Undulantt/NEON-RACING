extends SceneTree
var failures: Array[String]=[]
func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)
func snapshot(world: Node3D) -> Dictionary:
	var result:={"decorated":0,"lamps":0,"palms":0,"trees":0,"active_lights":0,"max_neon_build_ms":0.0,"max_neon_slice_ms":0.0}
	for id in world.night_style.furniture.sectors:
		var node=world.night_style.furniture.sectors[id]["owner"].get_ref()
		if not is_instance_valid(node): continue
		result["decorated"]+=1
		var counts: Dictionary=node.get_meta("furniture_counts")
		for key in ["lamps","palms","trees"]: result[key]+=counts[key]
		check(counts["lamps"]<=24 and counts["palms"]+counts["trees"]<=14,"Sector fixture budget")
		check(node.find_children("*","CollisionObject3D",true,false).is_empty(),"Decoration changed physics")
	for light in world.night_style.furniture.lights:
		if light.visible: result["active_lights"]+=1
	check(result["active_lights"]<=4,"Global light budget")
	for chunk in world.road_root.loaded.values(): result["max_neon_build_ms"]=maxf(result["max_neon_build_ms"],chunk.get_meta("neon_build_ms",0))
	for chunk in world.road_root.loaded.values():
		for visual in chunk.find_children("*","MeshInstance3D",true,false): result["max_neon_slice_ms"]=maxf(result["max_neon_slice_ms"],visual.get_meta("neon_max_slice_ms",0))
	return result
func _initialize() -> void: run.call_deferred()
func run() -> void:
	root.size=Vector2i(1280,720)
	var world=load("res://scenes/Main.tscn").instantiate();root.add_child(world)
	for i in range(420): await physics_frame
	var report:={"sectors":[],"live_lights":0,"coast":snapshot(world)}
	for id in world.night_style.furniture.sectors:
		var owner=world.night_style.furniture.sectors[id]["owner"].get_ref()
		if is_instance_valid(owner): report["sectors"].append({"id":id,"counts":owner.get_meta("furniture_counts")})
	for light in world.night_style.furniture.lights:
		if light.visible: report["live_lights"]+=1
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://docs/evidence/phase_e_city_driver.png")
	var camera:=Camera3D.new();world.add_child(camera)
	camera.position=world.player.position+Vector3(25,32,35)
	camera.look_at(world.player.position+Vector3(0,0,-30));camera.current=true
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://docs/evidence/phase_e_city_sector.png")
	check(report["coast"]["trees"]>0 and report["coast"]["palms"]>0,"Missing vegetation types")
	check(world.city_manager.set_city_enabled(false),"F8 disable")
	world.night_style.furniture.update_lights()
	for light in world.night_style.furniture.lights: check(not light.visible,"Light remains on with city hidden")
	world.city_manager.set_city_enabled(true)
	var initial_ids: Array=world.night_style.furniture.sectors.keys()
	var target:=Vector2(1400,900)
	var nearest:=Vector2.ZERO;var best:=INF
	for road in world.map_data["roads"]:
		var midpoint: Vector2=world.night_style.furniture.point(road["points_xz"][0]).lerp(world.night_style.furniture.point(road["points_xz"][-1]),0.5)
		if midpoint.distance_squared_to(target)<best:
			best=midpoint.distance_squared_to(target);nearest=midpoint
	world.player.set_physics_process(false)
	world.player.position=Vector3(nearest.x,world.player.surface_height(nearest.x,nearest.y)+0.67,nearest.y)
	camera.queue_free();world.follow_camera.camera.current=true;world.follow_camera.snap()
	for i in range(480): await physics_frame
	report["inland"]=snapshot(world)
	check(report["inland"]["decorated"]>3 and report["inland"]["trees"]>0,"New inland sectors not styled")
	var unloaded:=0
	for id in initial_ids:
		if not world.night_style.furniture.sectors.has(id): unloaded+=1
	check(unloaded>0,"Old decoration did not unload")
	report["unloaded_sectors"]=unloaded
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://docs/evidence/phase_e_city_inland.png")
	report["passed"]=failures.is_empty();report["failures"]=failures
	FileAccess.open("res://docs/phase_e_city_validation.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("CITY_STYLE ",JSON.stringify(report))
	world.queue_free()
	for i in range(8): await process_frame
	quit(0 if failures.is_empty() else 1)

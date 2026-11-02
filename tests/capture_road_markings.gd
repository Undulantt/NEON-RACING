extends SceneTree
func _initialize() -> void: run.call_deferred()
func run() -> void:
	root.size=Vector2i(1280,720)
	var world=load("res://scenes/Main.tscn").instantiate();root.add_child(world)
	for i in range(60): await physics_frame
	var car=world.player;car.external_control=true
	for road in world.map_data["roads"]:
		if str(road["id"])!="443101250:0": continue
		var a:=Vector2(road["points_xz"][0][0],road["points_xz"][0][1])
		var b:=Vector2(road["points_xz"][-1][0],road["points_xz"][-1][1])
		var p:=a.lerp(b,0.5);var direction:=(b-a).normalized()
		car.rotation.y=atan2(-direction.x,-direction.y)
		car.position=Vector3(p.x,car.supported_pose_height(p.x,p.y,car.rotation.y),p.y)
		car.velocity=Vector3.ZERO;car.set_controls(0,0,true);car.reset_surface_motion();world.follow_camera.snap()
	for i in range(300): await physics_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://docs/evidence/phase_e_forjadores_continuous.png")
	print("MARKINGS_CAPTURE position=",car.position," on_asphalt=",car.on_asphalt)
	world.queue_free()
	for i in range(8): await process_frame
	quit()

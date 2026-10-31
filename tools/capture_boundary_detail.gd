extends SceneTree

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	root.content_scale_size=Vector2i(1920,1080)
	root.content_scale_mode=Window.CONTENT_SCALE_MODE_VIEWPORT
	root.size=Vector2i(960,540)
	var world:=preload("res://scenes/Main.tscn").instantiate()
	root.add_child(world)
	await physics_frame
	await physics_frame
	world.player.set_physics_process(false)
	world.hud.hide()
	world.follow_camera.set_process(false)
	world.follow_camera.set_physics_process(false)
	var edge:=Vector3(-2635,0,2780)
	var core_south := "--core-south" in OS.get_cmdline_user_args()
	if core_south:
		edge=Vector3(2285.29,0,889.56)
	var height:float=world.elevation.get_height_at(edge.x,edge.z)
	world.player.position=Vector3(-2460,height+0.67,2780)
	if core_south:
		world.player.position=edge+Vector3(-90,height+0.67,130)
	for manager in [world.road_root,world.terrain_root,world.limit_root]:
		manager.anchor=world.player.position
		manager.refresh(true)
	var camera:Camera3D=world.overhead
	camera.position=Vector3(-2450,height+35,2980)
	camera.far=2500
	camera.fov=65
	camera.look_at(edge+Vector3(-55,65,-80))
	if core_south:
		camera.position=edge+Vector3(-200,height+65,220)
		camera.look_at(edge+Vector3(80,height+65,-80))
	camera.current=true
	for i in range(60):
		await physics_frame
	await RenderingServer.frame_post_draw
	var path := "res://docs/evidence/la_paz_core_south_setback.png" if core_south else "res://docs/evidence/la_paz_boundary_mountains_detail.png"
	var err:=root.get_texture().get_image().save_png(path)
	print("BOUNDARY_DETAIL_CAPTURE ",err)
	quit(0 if err==OK else 1)

extends SceneTree
func _initialize() -> void:
	run.call_deferred()
func run() -> void:
	root.size=Vector2i(1280,720);root.content_scale_size=Vector2i(1280,720)
	var world=load("res://scenes/NightPilot.tscn").instantiate();root.add_child(world)
	world.player.external_control=true
	for i in range(150): await physics_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://docs/evidence/phase_e_retro_driver.png")
	var camera:=Camera3D.new();world.add_child(camera)
	camera.position=world.player.position+Vector3(-28,24,28)
	camera.look_at(world.player.position+Vector3(25,3,-55));camera.current=true
	await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://docs/evidence/phase_e_retro_sector.png")
	world.queue_free()
	for i in range(8): await process_frame
	quit()

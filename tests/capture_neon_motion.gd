extends SceneTree
func _initialize() -> void:
	run.call_deferred()
func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://docs/evidence/"+name+".png")
func run() -> void:
	root.size=Vector2i(1280,720);root.content_scale_size=Vector2i(1280,720)
	var world=load("res://scenes/NightPilot.tscn").instantiate();root.add_child(world)
	world.player.external_control=true
	for i in range(120): await physics_frame
	world.player.set_controls(1,0)
	for i in range(110): await physics_frame
	world.player.set_controls(1,0,false,true)
	for i in range(55): await physics_frame
	await shot("phase_e_turbo_driver")
	var camera:=Camera3D.new();world.add_child(camera)
	camera.position=world.player.position+world.player.global_basis*Vector3(6,3,9)
	camera.look_at(world.player.position+Vector3.UP*0.4);camera.current=true
	await process_frame
	await shot("phase_e_turbo_trail")
	print("NEON_MOTION active=",world.player.turbo_active," speed=",world.player.speed_mps)
	world.queue_free()
	for i in range(8): await process_frame
	quit()

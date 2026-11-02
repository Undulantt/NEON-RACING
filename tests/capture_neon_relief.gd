extends SceneTree
func _initialize() -> void:
	run.call_deferred()
func run() -> void:
	root.size=Vector2i(1280,720)
	root.content_scale_size=Vector2i(1280,720)
	var world=load("res://scenes/NightPilot.tscn").instantiate()
	root.add_child(world)
	world.player.external_control=true
	for i in range(120): await physics_frame
	world.player.rotation.y+=PI
	world.follow_camera.snap()
	for i in range(30): await physics_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://docs/evidence/phase_e_neon_relief_fixed.png")
	world.queue_free()
	for i in range(8): await process_frame
	quit()

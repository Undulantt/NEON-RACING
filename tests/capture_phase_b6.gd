extends SceneTree
const Main = preload("res://scenes/FlatWorld.tscn")
func _initialize() -> void:
	run.call_deferred()
func run() -> void:
	root.content_scale_size=Vector2i(1280,720)
	root.content_scale_mode=Window.CONTENT_SCALE_MODE_VIEWPORT
	root.size=Vector2i(1280,720)
	var world := Main.instantiate()
	root.add_child(world)
	world.player.driving_enabled=false
	world.player.position=Vector3(625,0.67,-333)
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.near=2.0
	camera.far=6000
	camera.position=Vector3(610,50,-370)
	camera.look_at(Vector3(670,8,-290))
	camera.current=true
	for i in range(180):
		await physics_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://docs/evidence/phase_b6_cathedral.png")
	camera.near=30.0
	camera.position=Vector3(0,1650,700)
	camera.look_at(Vector3(0,0,0))
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://docs/evidence/phase_b6_coast.png")
	quit()

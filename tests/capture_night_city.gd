extends SceneTree
func _initialize() -> void: run.call_deferred()
func run() -> void:
	root.size=Vector2i(1280,720)
	var world=load("res://scenes/Main.tscn").instantiate();root.add_child(world)
	for i in range(360): await physics_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://docs/evidence/phase_e_direct_night.png")
	var environments:=0;var suns:=0
	for node in world.get_children():
		if node is WorldEnvironment: environments+=1
		if node is DirectionalLight3D: suns+=1
	print("DIRECT_NIGHT environment=",environments," directional=",suns," native_night=",world.night_visuals," urban_native_night=",world.city_manager.night_visuals)
	world.queue_free()
	for i in range(8): await process_frame
	quit()

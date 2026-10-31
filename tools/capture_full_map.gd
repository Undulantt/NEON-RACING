extends SceneTree

# Inspection only: preload the complete production world without changing streaming settings.
const SIZE := Vector2i(2560, 3840)
const OUTPUT := "res://docs/evidence/la_paz_coast_fix"

class ReferenceOverlay:
	extends Control
	var camera: Camera3D
	var blocks: Array
	var bounds: Array
	func _draw() -> void:
		var font := ThemeDB.fallback_font
		for col in range(1, 4):
			var x := SIZE.x * col / 4.0
			draw_line(Vector2(x, 100), Vector2(x, SIZE.y - 100), Color(1, 1, 1, 0.22), 2)
		for row in range(1, 6):
			var y := 100 + (SIZE.y - 200) * row / 6.0
			draw_line(Vector2(0, y), Vector2(SIZE.x, y), Color(1, 1, 1, 0.22), 2)
		for col in range(4):
			draw_string(font, Vector2((col + 0.5) * SIZE.x / 4.0, 125), String.chr(65 + col), HORIZONTAL_ALIGNMENT_CENTER, -1, 40, Color.WHITE)
		for row in range(6):
			draw_string(font, Vector2(28, 100 + (row + 0.5) * (SIZE.y - 200) / 6.0), str(row + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 40, Color.WHITE)
		var colors := {"core":Color("6fc4ff"), "north":Color("ffb856"), "south":Color("76e7a1")}
		for block in blocks:
			var b: Array = block["bounds_xz"]
			var points := PackedVector2Array()
			for p in block.get("boundary_xz", [[b[0],b[1]],[b[2],b[1]],[b[2],b[3]],[b[0],b[3]]]):
				points.append(camera.unproject_position(Vector3(p[0], 0, p[1])))
			points.append(points[0])
			draw_polyline(points, colors[block["id"]], 4, true)
		draw_rect(Rect2(0, 0, SIZE.x, 85), Color(0.025, 0.045, 0.06, 0.9))
		draw_string(font, Vector2(40, 57), "LA PAZ · MAPA COMPLETO DEL JUEGO · NORTE ↑", HORIZONTAL_ALIGNMENT_LEFT, -1, 40, Color.WHITE)
		draw_rect(Rect2(0, SIZE.y - 100, SIZE.x, 100), Color(0.025, 0.045, 0.06, 0.9))
		draw_string(font, Vector2(40, SIZE.y - 56), "Azul: Centro / Malecón   ·   Naranja: norte   ·   Verde: corredor sur", HORIZONTAL_ALIGNMENT_LEFT, -1, 31, Color.WHITE)
		draw_string(font, Vector2(40, SIZE.y - 18), "Cuadrícula A–D / 1–6 para señalar zonas · Captura del mundo 3D; no es una fotografía satelital", HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color("c9d2d8"))
		var start := Vector2(SIZE.x - 430, SIZE.y - 145)
		var length_px := camera.unproject_position(Vector3(bounds[0] + 1000, 0, bounds[1])).x - camera.unproject_position(Vector3(bounds[0], 0, bounds[1])).x
		draw_line(start, start + Vector2(length_px, 0), Color.WHITE, 5)
		draw_string(font, start + Vector2(0, -12), "1 km", HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Color.WHITE)

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	root.content_scale_size = SIZE
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	root.size = Vector2i(800, 1200)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var world := preload("res://scenes/Main.tscn").instantiate()
	root.add_child(world)
	await physics_frame
	await physics_frame
	if world.player == null or not world.runtime_error.is_empty():
		push_error("World failed: " + world.runtime_error)
		quit(1)
		return
	world.set_physics_process(false)
	world.player.set_physics_process(false)
	world.follow_camera.set_process(false)
	world.follow_camera.set_physics_process(false)
	world.hud.hide()
	for manager in [world.road_root, world.terrain_root, world.limit_root, world.city_manager]:
		if manager != null:
			manager.set_physics_process(false)
	var bounds: Array = world.environment_data["bounds_xz"]
	var center := Vector3((bounds[0] + bounds[2]) / 2.0, 0, (bounds[1] + bounds[3]) / 2.0)
	var camera: Camera3D = world.overhead
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_WIDTH
	camera.size = maxf(bounds[2] - bounds[0], (bounds[3] - bounds[1]) * SIZE.x / float(SIZE.y)) * 1.12
	camera.far = 20000
	camera.position = center + Vector3(0, 12000, 0)
	camera.look_at(center, Vector3.FORWARD)
	camera.current = true
	for manager in [world.road_root, world.terrain_root, world.limit_root]:
		if manager == null:
			continue
		for cell in manager.entries:
			manager.load_chunk(cell)
		assert(manager.failed_chunks.is_empty(), "Missing surface sectors")
		print("FULL_AERIAL_SURFACE ", manager.name, " ", manager.loaded.size(), "/", manager.entries.size())
	for entry in world.city_manager.manifest["chunks"]:
		world.city_manager.load_chunk(entry)
	assert(world.city_manager.failed_chunks.is_empty(), "Missing building sectors")
	print("FULL_AERIAL_BUILDINGS ", world.city_manager.loaded.size(), "/", world.city_manager.manifest["chunks"].size(), " buildings=", world.city_manager.loaded_buildings)
	for i in range(8):
		await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	assert(image.get_size() == SIZE, "Unexpected capture resolution")
	assert(image.save_png(OUTPUT + ".png") == OK)
	var layer := CanvasLayer.new()
	var overlay := ReferenceOverlay.new()
	overlay.camera = camera
	overlay.blocks = world.expansion["active_blocks"]
	overlay.bounds = bounds
	layer.add_child(overlay)
	root.add_child(layer)
	for i in range(3):
		await process_frame
	await RenderingServer.frame_post_draw
	assert(root.get_texture().get_image().save_png(OUTPUT + "_grid.png") == OK)
	var report := {"size_px":[SIZE.x, SIZE.y], "profile":world.relief_profile, "north_up":true,"bounds_xz":bounds,"roads_loaded":world.road_root.loaded.size(),"roads_total":world.road_root.entries.size(),"terrain_loaded":world.terrain_root.loaded.size(),"terrain_total":world.terrain_root.entries.size(),"urban_loaded":world.city_manager.loaded.size(),"urban_total":world.city_manager.manifest["chunks"].size(),"buildings":world.city_manager.loaded_buildings,"clean":OUTPUT + ".png","grid":OUTPUT + "_grid.png"}
	var file := FileAccess.open("res://docs/full_aerial_capture.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))
	print("FULL_AERIAL_COMPLETE ", JSON.stringify(report))
	quit()

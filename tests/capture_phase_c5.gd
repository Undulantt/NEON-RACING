extends SceneTree

class BlockOverlay:
	extends Control
	var camera: Camera3D
	var blocks: Array
	func _draw() -> void:
		for block in blocks:
			var b: Array = block["bounds_xz"]
			var corners := PackedVector2Array()
			for p in block.get("boundary_xz", [[b[0], b[1]], [b[2], b[1]], [b[2], b[3]], [b[0], b[3]], [b[0], b[1]]]):
				corners.append(camera.unproject_position(Vector3(p[0], 1, p[1])))
			draw_polyline(corners, {"core": Color("6fc4ff"), "north": Color("ffb856"), "south": Color("76e7a1")}[block["id"]], 2.0, true)

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	root.content_scale_size = Vector2i(1280, 720)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	root.size = Vector2i(1280, 720)
	var world := preload("res://scenes/FlatWorld.tscn").instantiate()
	root.add_child(world)
	await physics_frame
	await physics_frame
	world.player.external_control = true
	for anchor in world.expansion["anchors"]:
		var p: Array = anchor["position_xz"]
		var best_length := -1.0
		var forward := Vector3.FORWARD
		for road in world.map_data["roads"]:
			if road["from"] != anchor["node_id"] and (road["to"] != anchor["node_id"] or road["oneway"]):
				continue
			var a: Array = road["points_xz"][0]
			var b: Array = road["points_xz"][-1]
			var direction := Vector3(b[0] - a[0], 0, b[1] - a[1])
			if road["to"] == anchor["node_id"]:
				direction = -direction
			if direction.length() > best_length:
				best_length = direction.length()
				forward = direction.normalized()
		if anchor["id"] == "costa_norte":
			var route: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tracks/c5_north_coast.json"))
			var distance := 0.0
			var rp: Array = route["points_xz"]
			for i in range(rp.size() - 2, -1, -1):
				var a := Vector3(rp[i][0], 0, rp[i][1])
				var b := Vector3(rp[i + 1][0], 0, rp[i + 1][1])
				distance += a.distance_to(b)
				if distance >= 300:
					p = rp[i]
					forward = (b - a).normalized()
					break
		world.player.global_transform = Transform3D(Basis(Vector3.UP, atan2(-forward.x, -forward.z)), Vector3(p[0], 0.67, p[1]))
		world.player.velocity = Vector3.ZERO
		world.player.set_controls(0, 0)
		world.follow_camera.snap()
		world.hud.show_notice(anchor["name"])
		for i in range(60):
			await physics_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://docs/evidence/phase_c5_" + anchor["id"] + ".png")
	# Inspection-only overview. Load all sectors here, never in normal gameplay.
	world.player.set_physics_process(false)
	for cell in world.road_root.entries:
		world.road_root.load_chunk(cell)
	for entry in world.city_manager.manifest["chunks"]:
		world.city_manager.load_chunk(entry)
	world.road_root.set_physics_process(false)
	world.city_manager.set_physics_process(false)
	world.hud.hide()
	var bounds: Array = world.environment_data["bounds_xz"]
	var center := Vector3((float(bounds[0]) + float(bounds[2])) / 2, 0, (float(bounds[1]) + float(bounds[3])) / 2)
	world.overhead.projection = Camera3D.PROJECTION_ORTHOGONAL
	world.overhead.size = maxf(float(bounds[3]) - float(bounds[1]), (float(bounds[2]) - float(bounds[0])) / (1280.0 / 720.0)) * 1.15
	world.overhead.position = center + Vector3(0, 5400, 0.1)
	world.overhead.look_at(center, Vector3.FORWARD)
	world.overhead.current = true
	var layer := CanvasLayer.new()
	var overlay := BlockOverlay.new()
	overlay.camera = world.overhead
	overlay.blocks = world.expansion["active_blocks"]
	layer.add_child(overlay)
	var title := Label.new()
	title.text = "FASE C.5 · CENTRO + NORTE + CORREDOR SUR"
	title.position = Vector2(24, 16)
	title.add_theme_font_size_override("font_size", 24)
	layer.add_child(title)
	var legend := Label.new()
	legend.text = "Azul: Centro / Malecón    ·    Naranja: norte    ·    Verde: sur"
	legend.position = Vector2(24, 48)
	legend.add_theme_font_size_override("font_size", 18)
	layer.add_child(legend)
	root.add_child(layer)
	for i in range(3):
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://docs/evidence/phase_c5_south_cut_overview.png")
	print("C5_CAPTURE_COMPLETE")
	quit()

extends SceneTree

class CorridorOverlay:
	extends Control
	var camera: Camera3D
	var roads: Array
	var groups: Array
	var colors := [Color("ff9b42"),Color("54caff"),Color("f47dea"),Color("d6f56f")]
	func _draw() -> void:
		for i in range(groups.size()):
			for road in roads:
				if road["osm_way_id"] not in groups[i]["source_way_ids"]:
					continue
				var line := PackedVector2Array()
				for p in road["points_xz"]:
					line.append(camera.unproject_position(Vector3(p[0],1,p[1])))
				draw_polyline(line,colors[i],3,true)

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	root.content_scale_size=Vector2i(1280,720)
	root.content_scale_mode=Window.CONTENT_SCALE_MODE_VIEWPORT
	root.size=Vector2i(1280,720)
	var world := preload("res://scenes/FlatWorld.tscn").instantiate()
	root.add_child(world)
	await physics_frame
	await physics_frame
	world.player.external_control=true
	var groups: Array = JSON.parse_string(FileAccess.get_file_as_string("res://config/expansion_config.json"))["critical_corridors"]
	var capture_ways := ["268780989","28785401","443101245","309422738"]
	for i in range(groups.size()):
		var best := {}
		for road in world.map_data["roads"]:
			if road["osm_way_id"]==capture_ways[i] and (best.is_empty() or road["length_m"]>best["length_m"]):
				best=road
		var a := Vector3(best["points_xz"][0][0],0,best["points_xz"][0][1])
		var b := Vector3(best["points_xz"][-1][0],0,best["points_xz"][-1][1])
		var forward := (b-a).normalized()
		world.player.global_transform=Transform3D(Basis(Vector3.UP,atan2(-forward.x,-forward.z)),(a+b)*0.5+Vector3.UP*0.67)
		world.player.velocity=Vector3.ZERO
		world.player.set_controls(0,0)
		world.follow_camera.snap()
		world.hud.show_notice(groups[i]["name"])
		for frame in range(60):
			await physics_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://docs/evidence/cajoncito_"+str(groups[i]["id"])+".png")
	world.player.set_physics_process(false)
	for cell in world.road_root.entries:
		world.road_root.load_chunk(cell)
	for entry in world.city_manager.manifest["chunks"]:
		world.city_manager.load_chunk(entry)
	world.road_root.set_physics_process(false)
	world.city_manager.set_physics_process(false)
	world.hud.hide()
	var center := Vector3(6371000*deg_to_rad(-110.318+110.3195)*cos(deg_to_rad(24.159)),0,-6371000*deg_to_rad(24.1155-24.159))
	world.overhead.projection=Camera3D.PROJECTION_ORTHOGONAL
	world.overhead.size=5000
	world.overhead.position=center+Vector3(0,5400,0.1)
	world.overhead.look_at(center,Vector3.FORWARD)
	world.overhead.current=true
	var layer := CanvasLayer.new()
	var overlay := CorridorOverlay.new()
	overlay.camera=world.overhead
	overlay.roads=world.map_data["roads"]
	overlay.groups=groups
	layer.add_child(overlay)
	var title := Label.new()
	title.text="CAJONCITO · CORREDORES VIALES RECUPERADOS"
	title.position=Vector2(24,14)
	title.add_theme_font_size_override("font_size",24)
	layer.add_child(title)
	for i in range(groups.size()):
		var label := Label.new()
		label.text=groups[i]["name"]
		label.position=Vector2(24,50+i*24)
		label.add_theme_color_override("font_color",overlay.colors[i])
		label.add_theme_color_override("font_shadow_color",Color.BLACK)
		label.add_theme_constant_override("shadow_offset_x",2)
		label.add_theme_constant_override("shadow_offset_y",2)
		layer.add_child(label)
	root.add_child(layer)
	for frame in range(3):
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://docs/evidence/cajoncito_overview.png")
	print("CAJONCITO_CAPTURE_COMPLETE")
	quit()

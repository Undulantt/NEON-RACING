extends Node
var world: Node3D
var road_material: ShaderMaterial
var timer := 0.0
var road_busy := false
var post: ShaderMaterial
var blur_amount := 0.0
var pilot_cell := Vector2i.ZERO
var turbo_trail: Node3D
func configure(target: Node3D) -> void:
	world=target
	var parts: PackedStringArray = world.night_config["sector"].split("_")
	pilot_cell=Vector2i(int(parts[0]),int(parts[1]))
	for node in world.get_children():
		if node is WorldEnvironment:
			var sky := Sky.new()
			var mat := ShaderMaterial.new();mat.shader=load("res://shaders/retro_sky.gdshader")
			sky.sky_material=mat
			node.environment.sky=sky
			node.environment.background_mode=Environment.BG_SKY
			node.environment.ambient_light_color=Color("9ca7db")
			node.environment.ambient_light_energy=0.48
		if node is DirectionalLight3D:
			node.light_color=Color("ed9bd1")
			node.light_energy=0.42
	road_material=ShaderMaterial.new()
	road_material.shader=load("res://shaders/retro_road.gdshader")
	var segments := PackedVector4Array()
	var widths := PackedFloat32Array()
	for road in world.map_data["roads"]:
		if str(road["osm_way_id"]) != str(world.night_config["promenade_way_id"]):
			continue
		var a: Array=road["points_xz"][0];var b: Array=road["points_xz"][-1]
		if minf(a[1],b[1]) < pilot_cell.y*256-24 or maxf(a[1],b[1]) > (pilot_cell.y+1)*256+20:
			continue
		if segments.size() >= 64:
			break
		segments.append(Vector4(a[0],a[1],b[0],b[1]));widths.append(float(road["width_m"]))
	road_material.set_shader_parameter("segment_count",segments.size())
	segments.resize(64);widths.resize(64)
	road_material.set_shader_parameter("segments",segments)
	road_material.set_shader_parameter("widths",widths)
	var layer := CanvasLayer.new();layer.layer=0;add_child(layer)
	var rect := ColorRect.new();rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter=Control.MOUSE_FILTER_IGNORE
	post=ShaderMaterial.new();post.shader=load("res://shaders/retro_bloom.gdshader")
	rect.material=post;layer.add_child(rect)
	preload("res://scripts/style/RetroCar.gd").build(world.player)
	world.follow_camera.close_view=true
	for effect in world.hud.get_children():
		if effect.get_script()==preload("res://scripts/ui/SpeedEffects.gd"):
			effect.retro_profile=true
			turbo_trail=preload("res://scripts/style/TurboTrail.gd").new()
			add_child(turbo_trail)
			turbo_trail.attach(world.player,effect,world.hud)
	refresh()
func refresh() -> void:
	if road_busy: return
	var cells: Array=world.road_root.loaded.keys() if world.night_config.get("citywide",false) else [pilot_cell]
	cells.sort_custom(func(a,b): return (Vector2(a)*256+Vector2(128,128)).distance_squared_to(Vector2(world.player.position.x,world.player.position.z))<(Vector2(b)*256+Vector2(128,128)).distance_squared_to(Vector2(world.player.position.x,world.player.position.z)))
	for cell in cells:
		if not world.road_root.loaded.has(cell): continue
		var chunk: Node3D=world.road_root.loaded[cell]
		if chunk.has_meta("retro_road"): continue
		chunk.set_meta("retro_road",true)
		var mat:=road_material
		if world.night_config.get("citywide",false):
			mat=road_material.duplicate()
			# Local widened road axes; never project the pilot avenue across town.
			var local_roads: Array=world.night_style.furniture.roads_for(cell).duplicate()
			var center:=Vector2(cell)*256+Vector2(128,128)
			local_roads.sort_custom(func(a,b): return world.night_style.furniture.point(a["points_xz"][0]).distance_squared_to(center)<world.night_style.furniture.point(b["points_xz"][0]).distance_squared_to(center))
			var lines:=PackedVector4Array();var sizes:=PackedFloat32Array()
			for road in local_roads:
				var a: Array=road["points_xz"][0];var b: Array=road["points_xz"][-1]
				lines.append(Vector4(a[0],a[1],b[0],b[1]));sizes.append(float(road["width_m"]))
				if lines.size()==64: break
			mat.set_shader_parameter("segment_count",lines.size())
			lines.resize(64);sizes.resize(64)
			mat.set_shader_parameter("segments",lines);mat.set_shader_parameter("widths",sizes)
		road_busy=true
		for visual in chunk.find_children("*","MeshInstance3D",true,false):
			visual.material_override=mat
			var started:=Time.get_ticks_usec()
			await preload("res://scripts/style/RoadNeon.gd").build(visual,4.0 if world.night_config.get("citywide",false) else 0.0)
			if not is_instance_valid(chunk):
				road_busy=false
				return
			chunk.set_meta("neon_build_ms",(Time.get_ticks_usec()-started)/1000.0)
		road_busy=false
		break
func _process(delta: float) -> void:
	var goal := 0.0
	if is_instance_valid(turbo_trail) and world.player.driving_enabled and world.player.turbo_active:
		goal=turbo_trail.strength
	blur_amount=lerpf(blur_amount,goal,1.0-exp(-8.0*delta))
	post.set_shader_parameter("turbo_blur",blur_amount)
	timer+=delta
	if timer>0.25:
		timer=0
		refresh()

extends Node
var world: Node3D
var road_material: ShaderMaterial
var timer := 0.0
var road_busy := false
var neon_cache := {}
var baked_roads := {}
var baked_loads := 0
var pending_meshes := {}
var ready_meshes := {}
var runtime_builds := 0
var post: ShaderMaterial
var blur_amount := 0.0
var pilot_cell := Vector2i.ZERO
var turbo_trail: Node3D
func configure(target: Node3D) -> void:
	world=target
	var bake_path:="res://data/processed/night_roads/manifest.json"
	if FileAccess.file_exists(bake_path):
		var baked=JSON.parse_string(FileAccess.get_file_as_string(bake_path))
		if baked is Dictionary and baked.get("generator_sha256","")==FileAccess.get_file_as_string("res://scripts/style/RoadNeon.gd").replace("\r\n","\n").sha256_text():
			baked_roads=baked.get("entries",{})
	var parts: PackedStringArray = world.night_config["sector"].split("_")
	pilot_cell=Vector2i(int(parts[0]),int(parts[1]))
	for node in world.get_children():
		if world.night_visuals: continue
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
	poll_baked()
	if road_busy: return
	var cells: Array=world.road_root.loaded.keys() if world.night_config.get("citywide",false) else [pilot_cell]
	cells.sort_custom(func(a,b): return (Vector2(a)*256+Vector2(128,128)).distance_squared_to(Vector2(world.player.position.x,world.player.position.z))<(Vector2(b)*256+Vector2(128,128)).distance_squared_to(Vector2(world.player.position.x,world.player.position.z)))
	# Prefetch only a small nearby window; decompression stays off the driving thread.
	for cell in cells.slice(0,16):
		if world.road_root.loaded.has(cell) and not world.road_root.loaded[cell].has_meta("retro_road"):
			baked_ready(cell)
	for cell in cells:
		if not world.road_root.loaded.has(cell): continue
		var chunk: Node3D=world.road_root.loaded[cell]
		if chunk.has_meta("retro_road"): continue
		if not baked_ready(cell): continue
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
		var visual_index:=0
		for visual in chunk.find_children("*","MeshInstance3D",true,false):
			visual.material_override=mat
			var started:=Time.get_ticks_usec()
			var cache_key:=str(cell)+":"+str(visual_index)
			visual_index+=1
			if restore_baked(visual,cell,visual_index-1):
				pass
			elif neon_cache.has(cache_key):
				var saved: Dictionary=neon_cache[cache_key]
				var edge:=MeshInstance3D.new();edge.name="RoadEdgeNeon"
				edge.mesh=saved["mesh"];edge.material_override=saved["material"]
				edge.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				visual.add_child(edge)
			else:
				runtime_builds+=1
				await preload("res://scripts/style/RoadNeon.gd").build(visual,1.5 if world.night_config.get("citywide",false) else 0.0)
				if is_instance_valid(visual):
					var edge:=visual.get_node_or_null("RoadEdgeNeon")
					if edge!=null: neon_cache[cache_key]={"mesh":edge.mesh,"material":edge.material_override}
				while neon_cache.size()>64: neon_cache.erase(neon_cache.keys()[0])
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
		if world.night_config.get("citywide",false):
			for chunk in world.road_root.loaded.values():
				for visual in chunk.find_children("*","MeshInstance3D",true,false):
					if visual.material_override is ShaderMaterial:
						visual.material_override.set_shader_parameter("street_pools",world.night_style.furniture.street_pools)

func restore_baked(visual: MeshInstance3D, cell: Vector2i, index: int) -> bool:
	var id:=str(cell.x)+"_"+str(cell.y)
	if not baked_roads.has(id): return false
	var entry: Dictionary=baked_roads[id]
	if entry["scene_sha256"]!=world.road_root.entries[cell].get("scene_sha256",""): return false
	if index>=entry["files"].size(): return false
	var path: String=entry["files"][index]
	if path.is_empty(): return true
	if not ResourceLoader.exists(path): return false
	var mesh=ready_meshes.get(path)
	if not mesh is ArrayMesh: return false
	var edge:=MeshInstance3D.new();edge.name="RoadEdgeNeon"
	edge.mesh=mesh;edge.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visual.add_child(edge);baked_loads+=1
	return true

func baked_ready(cell: Vector2i) -> bool:
	var id:=str(cell.x)+"_"+str(cell.y)
	if not baked_roads.has(id): return true
	var entry: Dictionary=baked_roads[id]
	if entry["scene_sha256"]!=world.road_root.entries[cell].get("scene_sha256",""): return true
	var ready:=true
	for path in entry["files"]:
		if str(path).is_empty() or ready_meshes.has(path): continue
		if not pending_meshes.has(path):
			if pending_meshes.size()>=8: ready=false;continue
			if ResourceLoader.load_threaded_request(path,"ArrayMesh")!=OK: return true
			pending_meshes[path]=true
		var status:=ResourceLoader.load_threaded_get_status(path)
		if status==ResourceLoader.THREAD_LOAD_LOADED:
			ready_meshes[path]=ResourceLoader.load_threaded_get(path)
			pending_meshes.erase(path)
			while ready_meshes.size()>64: ready_meshes.erase(ready_meshes.keys()[0])
		elif status==ResourceLoader.THREAD_LOAD_FAILED:
			pending_meshes.erase(path)
			return true
		else: ready=false
	return ready

func poll_baked() -> void:
	# Finish requests even if their sector left the nearby window while driving.
	for path in pending_meshes.keys():
		var status:=ResourceLoader.load_threaded_get_status(path)
		if status==ResourceLoader.THREAD_LOAD_LOADED:
			ready_meshes[path]=ResourceLoader.load_threaded_get(path)
			pending_meshes.erase(path)
		elif status==ResourceLoader.THREAD_LOAD_FAILED:
			pending_meshes.erase(path)
	while ready_meshes.size()>64: ready_meshes.erase(ready_meshes.keys()[0])

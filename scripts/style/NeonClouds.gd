extends Node3D
# Artistic finite-position sprites. No terrain, collision, light or physics writes.
signal enabled_changed(value: bool)
const CONFIG := "res://config/sf3_clouds.json"
var settings: Dictionary = {}
var world: Node3D
var batch: MultiMeshInstance3D
var material: ShaderMaterial
var cells: Array[Vector2i] = []
var instance_origins := PackedVector3Array()
var last_cell := Vector2i(2147483647,2147483647)
var elapsed := 0.0
var enabled := true
var altitude := 380.0
var rebuilds := 0
var last_update_us := 0

func configure(target: Node3D, override_settings: Dictionary = {}) -> void:
	world = target
	settings = JSON.parse_string(FileAccess.get_file_as_string(CONFIG))
	settings.merge(override_settings,true)
	# Bounded work even if a trial configuration contains out-of-range values.
	settings["grid_radius"] = clampi(int(settings["grid_radius"]),2,5)
	settings["cell_size_m"] = clampf(float(settings["cell_size_m"]),300,1000)
	settings["view_radius_m"] = clampf(float(settings["view_radius_m"]),500,float(settings["cell_size_m"])*(int(settings["grid_radius"])-0.5))
	var terrain_max := 0.0
	if "relief_manifest" in world:
		terrain_max = float(world.relief_manifest.get("statistics",{}).get("height_max_m",0.0))
	altitude = maxf(float(settings["altitude_m"]),terrain_max+float(settings["height_max_m"])*0.5+float(settings["altitude_variation_m"])+40)
	material = ShaderMaterial.new()
	material.shader = preload("res://shaders/sf3_clouds.gdshader")
	material.set_shader_parameter("cloud_atlas",preload("res://assets/textures/sf3_cloud_atlas.png"))
	material.set_shader_parameter("top_color",Color(settings["top_color"]))
	material.set_shader_parameter("bottom_color",Color(settings["bottom_color"]))
	material.set_shader_parameter("opacity",clampf(float(settings["opacity"]),0,0.9))
	material.set_shader_parameter("view_radius_m",settings["view_radius_m"])
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_custom_data = true
	multimesh.mesh = quad
	var side := int(settings["grid_radius"])*2+1
	multimesh.instance_count = side*side
	var extent := float(settings["cell_size_m"])*(int(settings["grid_radius"])+1)+float(settings["width_max_m"])
	multimesh.custom_aabb = AABB(Vector3(-extent,altitude-200,-extent),Vector3(extent*2,400,extent*2))
	batch = MultiMeshInstance3D.new()
	batch.name = "NeonCloudBatch"
	batch.multimesh = multimesh
	batch.material_override = material
	batch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(batch)
	set_enabled(bool(settings["enabled"]) and not "--sf3-no-clouds" in OS.get_cmdline_user_args())
	advance(0.0)

func set_enabled(value: bool) -> void:
	enabled = value
	if is_instance_valid(batch): batch.visible = value
	enabled_changed.emit(value)

func toggle() -> void: set_enabled(not enabled)

func wind_offset() -> Vector2:
	return Vector2(float(settings["wind_x_mps"]),float(settings["wind_z_mps"]))*elapsed

func viewer_position() -> Vector3:
	var camera := get_viewport().get_camera_3d()
	if camera != null: return camera.global_position
	if "player" in world and is_instance_valid(world.player): return world.player.global_position
	return Vector3.ZERO

func advance(delta: float) -> void:
	if not enabled or not is_instance_valid(batch): return
	var started := Time.get_ticks_usec()
	elapsed += delta
	var wind := wind_offset()
	var viewer := viewer_position()
	var spacing := float(settings["cell_size_m"])
	var cell := Vector2i(floori((viewer.x-wind.x)/spacing),floori((viewer.z-wind.y)/spacing))
	if cell != last_cell: rebuild(cell)
	batch.position = Vector3(last_cell.x*spacing+wind.x,0,last_cell.y*spacing+wind.y)
	last_update_us = Time.get_ticks_usec()-started

func rebuild(center: Vector2i) -> void:
	last_cell = center
	rebuilds += 1
	cells.clear()
	instance_origins.clear()
	var rng := RandomNumberGenerator.new()
	var radius := int(settings["grid_radius"])
	var spacing := float(settings["cell_size_m"])
	var index := 0
	for x in range(-radius,radius+1):
		for z in range(-radius,radius+1):
			var cell := center+Vector2i(x,z)
			rng.seed = ("%d:%d:%d"%[int(settings["seed"]),cell.x,cell.y]).hash()
			var at := Vector3((x+rng.randf_range(0.15,0.85))*spacing,altitude+rng.randf_range(-float(settings["altitude_variation_m"]),float(settings["altitude_variation_m"])),(z+rng.randf_range(0.15,0.85))*spacing)
			batch.multimesh.set_instance_transform(index,Transform3D(Basis.IDENTITY,at))
			batch.multimesh.set_instance_custom_data(index,Color(rng.randf_range(float(settings["width_min_m"]),float(settings["width_max_m"])),rng.randf_range(float(settings["height_min_m"]),float(settings["height_max_m"])),float(rng.randi_range(0,3)),rng.randf_range(0.72,1.0)))
			cells.append(cell)
			instance_origins.append(at)
			index += 1

func cloud_world_position(cell: Vector2i) -> Vector3:
	var index := cells.find(cell)
	# RenderingServer may defer MultiMesh buffer reads until the next rendered
	# frame. Retain authoritative CPU positions for diagnostics and continuity.
	return batch.to_global(instance_origins[index]) if index>=0 else Vector3.INF

func _process(delta: float) -> void: advance(delta)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.ctrl_pressed and event.alt_pressed and (event.physical_keycode==KEY_C or event.keycode==KEY_C):
		toggle()
		get_viewport().set_input_as_handled()

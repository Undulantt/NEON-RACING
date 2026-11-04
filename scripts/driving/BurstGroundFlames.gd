extends Node3D

# Two world-space tire tracks. Each segment joins successive wheel contacts.
const Presentation = preload("res://scripts/driving/BurstPresentation.gd")
var car: CharacterBody3D
var screen_effects: Control
var settings: Dictionary
var visual: MultiMeshInstance3D
var instances: MultiMesh
var material: ShaderMaterial
var marks: Array = []
var previous_contacts: Dictionary = {}
var track_distances := [0.0, 0.0]
var clock := 0.0
var last_car_position := Vector3.ZERO
var ray_queries := 0
var total_stamps := 0

func flame_mesh() -> ArrayMesh:
	# One ground ribbon and two crossed upright sheets, six triangles per instance.
	var vertices := PackedVector3Array()
	var uv := PackedVector2Array()
	var kinds := PackedVector2Array()
	var quads := [
		[Vector3(-0.5,0,-0.5),Vector3(0.5,0,-0.5),Vector3(0.5,0,0.5),Vector3(-0.5,0,0.5)],
		[Vector3(0,0,-0.5),Vector3(0,0,0.5),Vector3(0,1,0.5),Vector3(0,1,-0.5)],
		[Vector3(-0.5,0,0),Vector3(0.5,0,0),Vector3(0.5,1,0),Vector3(-0.5,1,0)]
	]
	var coords := [
		[Vector2(0,0),Vector2(0,1),Vector2(1,1),Vector2(1,0)],
		[Vector2(0,0),Vector2(1,0),Vector2(1,1),Vector2(0,1)],
		[Vector2(0,0),Vector2(1,0),Vector2(1,1),Vector2(0,1)]
	]
	for plane in range(3):
		for index in [0,1,2,0,2,3]:
			vertices.append(quads[plane][index])
			uv.append(coords[plane][index])
			kinds.append(Vector2(1.0 if plane == 1 else 0.0, 1.0 if plane == 2 else 0.0))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_TEX_UV2] = kinds
	var resource := ArrayMesh.new()
	resource.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return resource

func attach(target: CharacterBody3D, screen: Control) -> void:
	car = target
	screen_effects = screen
	settings = Presentation.settings()
	process_physics_priority = 110
	instances = MultiMesh.new()
	instances.transform_format = MultiMesh.TRANSFORM_3D
	instances.use_custom_data = true
	instances.mesh = flame_mesh()
	instances.instance_count = int(settings["ground_flame_max_marks"])
	instances.visible_instance_count = 0
	instances.custom_aabb = AABB(Vector3(-180,-100,-180),Vector3(360,200,360))
	material = ShaderMaterial.new()
	material.shader = preload("res://shaders/burst_ground_flames.gdshader")
	visual = MultiMeshInstance3D.new()
	visual.multimesh = instances
	visual.material_override = material
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visual.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(visual)
	last_car_position = car.global_position
	car.recovered.connect(func(_reason: String): clear_trail())
	car.vehicle_profile_changed.connect(func(_id: String): clear_trail())

func clear_trail() -> void:
	marks.clear()
	previous_contacts.clear()
	track_distances = [0.0,0.0]
	if instances != null:
		instances.visible_instance_count = 0
	if visual != null:
		visual.hide()

func ground_at(at: Vector3) -> Dictionary:
	ray_queries += 1
	var query := PhysicsRayQueryParameters3D.create(at + Vector3.UP, at - Vector3.UP * 3.0, 3)
	return get_world_3d().direct_space_state.intersect_ray(query)

func append_segment(track: int, start: Dictionary, finish: Dictionary) -> void:
	var displacement: Vector3 = finish["position"] - start["position"]
	var length := displacement.length()
	if length < 0.05 or length > 6.0:
		return
	var up: Vector3 = (start["normal"] + finish["normal"]).normalized()
	if up.y < 0.6:
		return
	var z_axis := displacement / length
	var x_axis := up.cross(z_axis).normalized()
	up = z_axis.cross(x_axis).normalized()
	marks.append({"position": (Vector3(start["position"])+Vector3(finish["position"])) * 0.5 + up * 0.025,
		"basis":Basis(x_axis,up,z_axis), "born":clock, "track":track,
		"distance":float(track_distances[track]), "length":length,
		"start":start["position"], "end":finish["position"]})
	track_distances[track] = fposmod(float(track_distances[track]) + length, 8.0)
	while marks.size() > instances.instance_count:
		marks.pop_front()
	total_stamps += 1

func sample_wheels() -> void:
	for track in range(2):
		# Production rear wheel centers, including the actual visual/suspension pose.
		var wheel: Node3D = car.visuals["pivots"][track+2]
		var wheel_position := wheel.global_position
		var previous: Dictionary = previous_contacts.get(track,{})
		if not previous.is_empty() and wheel_position.distance_to(previous["wheel"]) < float(settings["ground_flame_spacing_m"]):
			continue
		var contact := ground_at(wheel_position)
		if contact.is_empty():
			previous_contacts.erase(track)
			continue
		contact["wheel"] = wheel_position
		if not previous.is_empty():
			append_segment(track, previous, contact)
		previous_contacts[track] = contact

func _physics_process(delta: float) -> void:
	if car == null:
		return
	clock += delta
	var strength: float = screen_effects.effect_strength
	if car.global_position.distance_to(last_car_position) > 12.0 or not car.driving_enabled or strength <= 0:
		clear_trail()
	last_car_position = car.global_position
	var active: bool = car.driving_enabled and car.abilities.burst_state == 2 and car.is_on_floor() and strength > 0
	if active:
		sample_wheels()
	else:
		previous_contacts.clear()
	while not marks.is_empty() and clock - float(marks[0]["born"]) >= float(settings["ground_flame_lifetime_s"]):
		marks.pop_front()
	global_position = car.global_position
	for i in range(marks.size()):
		var mark: Dictionary = marks[i]
		var unit_basis: Basis = mark["basis"]
		var scaled_basis := Basis(unit_basis.x * float(settings["ground_flame_width_m"]), unit_basis.y * float(settings["ground_flame_height_m"]), unit_basis.z * (float(mark["length"])+0.035))
		instances.set_instance_transform(i, Transform3D(scaled_basis, Vector3(mark["position"])-global_position))
		instances.set_instance_custom_data(i, Color(clampf((clock-float(mark["born"]))/float(settings["ground_flame_lifetime_s"]),0,1),float(mark["distance"])/8.0,float(mark["length"]),float(mark["track"])))
	instances.visible_instance_count = marks.size()
	visual.visible = not marks.is_empty()
	material.set_shader_parameter("clock",fposmod(clock,8.0))
	material.set_shader_parameter("strength",strength)

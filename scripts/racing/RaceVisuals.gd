extends Node3D
const SCALE = preload("res://scripts/racing/RaceGeometry.gd").CHECKPOINT_SCALE
const SUBMERGED_RADIUS_FRACTION := 0.25
const SEGMENTS := 96
var world: Node3D
var next_gate: Node3D
var route_data: Dictionary = {}
var shown_gate := -1
var ribbon: MeshInstance3D

func configure(target: Node3D, data: Dictionary) -> void:
	world = target
	route_data = data
	ribbon = preload("res://scripts/racing/RouteRibbon.gd").new()
	add_child(ribbon)
	ribbon.configure(world,data["points_xz"])
	next_gate = Node3D.new()
	next_gate.name = "CheckpointRing"
	add_child(next_gate)
	show_gate(0)

func ring_mesh(radius: float) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var uv := PackedVector2Array()
	var inner := radius-clampf(radius*0.1,0.25,0.65)
	for i in range(SEGMENTS):
		var a := TAU*float(i)/SEGMENTS
		var b := TAU*float(i+1)/SEGMENTS
		var corners: Array[Vector3] = [Vector3(cos(a)*inner,sin(a)*inner,0),Vector3(cos(a)*radius,sin(a)*radius,0),Vector3(cos(b)*radius,sin(b)*radius,0),Vector3(cos(b)*inner,sin(b)*inner,0)]
		var coords: Array[Vector2] = [Vector2(float(i)/SEGMENTS,0),Vector2(float(i)/SEGMENTS,1),Vector2(float(i+1)/SEGMENTS,1),Vector2(float(i+1)/SEGMENTS,0)]
		for index in [0,1,2,0,2,3]:
			vertices.append(corners[index])
			uv.append(coords[index])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uv
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	return mesh

func show_gate(index: int) -> void:
	if shown_gate == index: return
	shown_gate = index
	if index >= route_data["checkpoints"].size():
		next_gate.hide()
		return
	next_gate.show()
	var gate: Dictionary = route_data["checkpoints"][index]
	var p: Array = gate["position_xz"]
	var d: Array = gate["forward_xz"]
	# Keep the existing width at road level: chord = R * sqrt(1 - 0.75^2).
	# The center is 0.75 R above the local road, so the lowest edge is -0.25 R.
	var center_fraction := 1.0-SUBMERGED_RADIUS_FRACTION
	var radius := float(gate["half_width_m"])/sqrt(1.0-center_fraction*center_fraction)
	var world_radius := radius*SCALE
	var ground: float = world.player.surface_height(p[0],p[1])
	next_gate.position = Vector3(p[0],ground+center_fraction*world_radius,p[1])
	next_gate.rotation.y = atan2(-float(d[0]),-float(d[1]))
	next_gate.scale = Vector3.ONE*SCALE
	next_gate.set_meta("radius_m",world_radius)
	next_gate.set_meta("submerged_depth_m",world_radius*SUBMERGED_RADIUS_FRACTION)
	for child in next_gate.get_children():
		next_gate.remove_child(child)
		child.queue_free()
	var ring := MeshInstance3D.new()
	ring.name = "NeonRing"
	ring.mesh = ring_mesh(radius)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := ShaderMaterial.new()
	material.shader = preload("res://shaders/checkpoint_ring.gdshader")
	material.set_shader_parameter("neon_color",Color(0.035,0.36,1.0,1.0))
	ring.material_override = material
	next_gate.add_child(ring)

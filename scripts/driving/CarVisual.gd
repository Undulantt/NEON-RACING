extends RefCounted

static func material(color: Color, glow: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.55
	if glow > 0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = glow
	return m

static func box(parent: Node3D, size: Vector3, at: Vector3, mat: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.material_override = mat
	node.position = at
	parent.add_child(node)
	return node

static func build(parent: Node3D) -> Dictionary:
	var paint := material(Color("26a99c"))
	var glass := material(Color("193342"))
	var rubber := material(Color("17212b"))
	var rim := material(Color("c5cbd2"))
	var lights := material(Color("fff0bf"), 0.8)
	var brake := material(Color("b52e2b"), 0.3)
	box(parent, Vector3(1.8, 0.55, 4.0), Vector3(0, 0.02, 0), paint)
	box(parent, Vector3(1.48, 0.62, 1.95), Vector3(0, 0.57, 0.15), glass)
	box(parent, Vector3(1.5, 0.08, 1.96), Vector3(0, 0.91, 0.15), paint)
	box(parent, Vector3(1.84, 0.16, 0.15), Vector3(0, -0.1, -2.02), rubber)
	box(parent, Vector3(1.84, 0.16, 0.15), Vector3(0, -0.1, 2.02), rubber)
	for x in [-0.61, 0.61]:
		box(parent, Vector3(0.44, 0.17, 0.04), Vector3(x, 0.15, -2.025), lights)
		box(parent, Vector3(0.48, 0.16, 0.04), Vector3(x, 0.15, 2.025), brake)
	var pivots: Array[Node3D] = []
	var wheels: Array[MeshInstance3D] = []
	for z in [-1.3, 1.3]:
		for x in [-0.91, 0.91]:
			var pivot := Node3D.new()
			pivot.position = Vector3(x, -0.26, z)
			parent.add_child(pivot)
			var wheel := MeshInstance3D.new()
			var tire := CylinderMesh.new()
			tire.top_radius = 0.34
			tire.bottom_radius = 0.34
			tire.height = 0.24
			tire.radial_segments = 12
			wheel.mesh = tire
			wheel.material_override = rubber
			wheel.rotation.z = PI / 2
			pivot.add_child(wheel)
			var hub := MeshInstance3D.new()
			var cylinder := CylinderMesh.new()
			cylinder.top_radius = 0.18
			cylinder.bottom_radius = 0.18
			cylinder.height = 0.25
			cylinder.radial_segments = 8
			hub.mesh = cylinder
			hub.material_override = rim
			wheel.add_child(hub)
			pivots.append(pivot)
			wheels.append(wheel)
	var turbo_material := material(Color("49dcff"), 2.0)
	var exhaust: Array[MeshInstance3D] = []
	for x in [-0.62, 0.62]:
		var flame := box(parent, Vector3(0.16, 0.16, 0.8), Vector3(x, -0.15, 2.35), turbo_material)
		flame.visible = false
		exhaust.append(flame)
	return {"exhaust": exhaust, "pivots": pivots, "wheels": wheels, "brake_material": brake}

extends RefCounted

# Vertices are chunk-local meters. Both rendering and physics use the same
# non-overlapping planar union, triangulated offline including polygon holes.
static func build(parent: Node3D, data: Dictionary) -> Dictionary:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("343c47")
	material.roughness = 0.96
	var count := 0
	for chunk in data["chunks"]:
		var vertices := PackedVector3Array()
		var normals := PackedVector3Array()
		for tri in chunk["triangles_xz"]:
			var a := Vector3(tri[0][0], 0.0, tri[0][1])
			var b := Vector3(tri[1][0], 0.0, tri[1][1])
			var c := Vector3(tri[2][0], 0.0, tri[2][1])
			# Godot uses clockwise front faces; upward collision face normal.
			if (b - a).cross(c - a).y < 0.0:
				var swap := b
				b = c
				c = swap
			vertices.append_array(PackedVector3Array([a, c, b]))
			normals.append_array(PackedVector3Array([Vector3.UP, Vector3.UP, Vector3.UP]))
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_NORMAL] = normals
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(0, material)
		var body := StaticBody3D.new()
		body.name = "Road_" + str(chunk["id"])
		body.collision_layer = 1
		body.collision_mask = 0
		body.position = Vector3(chunk["origin_xz"][0], 0.0, chunk["origin_xz"][1])
		var instance := MeshInstance3D.new()
		instance.mesh = mesh
		body.add_child(instance)
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(vertices)
		shape.backface_collision = true
		var collision := CollisionShape3D.new()
		collision.shape = shape
		body.add_child(collision)
		parent.add_child(body)
		count += vertices.size() / 3
	return {"chunks": data["chunks"].size(), "triangles": count}

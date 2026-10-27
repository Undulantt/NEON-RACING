extends RefCounted

# Vertices are chunk-local meters. Both rendering and physics use the same
# non-overlapping planar union, triangulated offline including polygon holes.
static func build(parent: Node3D, data: Dictionary) -> Dictionary:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("343c47") if int(data.get("layer", 1)) == 1 else Color("b4a386")
	material.roughness = 0.96
	var count := 0
	for chunk in data["chunks"]:
		if chunk.has("scene_file"):
			var scene_path := "res://" + str(chunk["scene_file"])
			if FileAccess.get_sha256(scene_path) != chunk["scene_sha256"]:
				push_error("Relief cached scene corrupt: " + scene_path)
				return {"error": "relief_scene_corrupt"}
			var scene = load(scene_path)
			if not scene is PackedScene:
				return {"error": "invalid_relief_scene"}
			parent.add_child(scene.instantiate())
			count += int(chunk["triangles_count"])
			continue
		var vertices := PackedVector3Array()
		var normals := PackedVector3Array()
		if chunk.has("file"):
			var bytes := FileAccess.get_file_as_bytes("res://" + str(chunk["file"]))
			var hashing := HashingContext.new()
			hashing.start(HashingContext.HASH_SHA256)
			hashing.update(bytes)
			if hashing.finish().hex_encode() != chunk["sha256"] or bytes.size() != int(chunk["triangles_count"]) * 36:
				push_error("Relief mesh corrupt: " + str(chunk["file"]))
				return {"error": "relief_mesh_corrupt"}
			var values := bytes.to_float32_array()
			for index in range(0, values.size(), 3):
				vertices.append(Vector3(values[index], values[index+1], values[index+2]))
			for index in range(0, vertices.size(), 3):
				var normal := (vertices[index+2] - vertices[index]).cross(vertices[index+1] - vertices[index]).normalized()
				normals.append_array(PackedVector3Array([normal, normal, normal]))
		for tri in chunk.get("triangles_xz", []):
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
		body.collision_layer = int(data.get("layer", 1))
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

extends RefCounted
# Trace the actual elevated asphalt boundary, not the original OSM centerline.
static func key(p: Vector3) -> String:
	return "%d,%d,%d" % [roundi(p.x*1000),roundi(p.y*1000),roundi(p.z*1000)]

static func chunk_cut(a: Vector3, b: Vector3) -> bool:
	for axis in [0,2]:
		if absf(a[axis]-b[axis])<0.002 and absf(a[axis]/256.0-roundf(a[axis]/256.0))<0.00001:
			return true
	return false

static func build(road: MeshInstance3D) -> void:
	var edges := {}
	for surface in range(road.mesh.get_surface_count()):
		var arrays := road.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
		var indices := PackedInt32Array()
		if arrays[Mesh.ARRAY_INDEX] != null:
			indices=arrays[Mesh.ARRAY_INDEX]
		if indices.is_empty():
			for i in range(vertices.size()):
				indices.append(i)
		for i in range(0,indices.size(),3):
			for side in range(3):
				var a := vertices[indices[i+side]]
				var b := vertices[indices[i+(side+1)%3]]
				var c := vertices[indices[i+(side+2)%3]]
				var ka := key(a);var kb := key(b)
				var edge_key := ka+"/"+kb if ka<kb else kb+"/"+ka
				if edges.has(edge_key):
					edges[edge_key]["count"]+=1
				else:
					edges[edge_key]={"a":a,"b":b,"c":c,"count":1}
	var points := PackedVector3Array()
	var boundary_count := 0
	for edge in edges.values():
		if edge["count"]!=1:
			continue
		var a: Vector3=edge["a"];var b: Vector3=edge["b"];var c: Vector3=edge["c"]
		if chunk_cut(road.to_global(a),road.to_global(b)) or a.distance_to(b)<0.002:
			continue
		var normal := (b-a).cross(c-a).normalized()
		if normal.y<0: normal=-normal
		var inward := normal.cross((b-a).normalized())
		if inward.dot(c-a)<0: inward=-inward
		var width := minf(0.18,absf((c-a).dot(inward))*0.8)
		var lift := normal*0.018
		points.append_array(PackedVector3Array([a+lift,b+lift,b+inward*width+lift,a+lift,b+inward*width+lift,a+inward*width+lift]))
		boundary_count+=1
	if points.is_empty(): return
	var result := MeshInstance3D.new()
	result.name="RoadEdgeNeon"
	var arrays := [];arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=points
	var mesh := ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	result.mesh=mesh
	var material := StandardMaterial3D.new()
	material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color=Color("38e9ff")
	material.cull_mode=BaseMaterial3D.CULL_DISABLED
	result.material_override=material
	result.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	result.set_meta("boundary_segments",boundary_count)
	road.add_child(result)

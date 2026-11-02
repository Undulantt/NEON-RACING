extends RefCounted
const GRID=preload("res://scripts/style/RoadNeon.gd")
static func project(road: MeshInstance3D, polygons: Array) -> ArrayMesh:
	var strokes: Array[PackedVector2Array]=[];var grid:={}
	for ring in polygons:
		var polygon:=PackedVector2Array()
		for p in ring: polygon.append(Vector2(p[0],p[1]))
		GRID.add_stroke(polygon,strokes,grid)
	var points:=PackedVector3Array()
	for surface in range(road.mesh.get_surface_count()):
		var source:=road.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array=source[Mesh.ARRAY_VERTEX]
		var indices:=PackedInt32Array()
		if source[Mesh.ARRAY_INDEX]!=null: indices=source[Mesh.ARRAY_INDEX]
		if indices.is_empty():
			for i in range(vertices.size()): indices.append(i)
		for i in range(0,indices.size(),3):
			var a:=vertices[indices[i]];var b:=vertices[indices[i+1]];var c:=vertices[indices[i+2]]
			var triangle:=PackedVector2Array([Vector2(a.x,a.z),Vector2(b.x,b.z),Vector2(c.x,c.z)])
			var denominator:=(triangle[1]-triangle[0]).cross(triangle[2]-triangle[0])
			if absf(denominator)<0.000001: continue
			var candidates:={}
			for cell in GRID.cells(triangle):
				for id in grid.get(cell,[]): candidates[id]=true
			for id in candidates:
				for polygon in Geometry2D.intersect_polygons(triangle,strokes[id]):
					for index in Geometry2D.triangulate_polygon(polygon):
						var p: Vector2=polygon[index]
						var u:=(p-triangle[0]).cross(triangle[2]-triangle[0])/denominator
						var v:=(triangle[1]-triangle[0]).cross(p-triangle[0])/denominator
						points.append(Vector3(p.x,a.y+u*(b.y-a.y)+v*(c.y-a.y)+0.025,p.y))
	var result:=ArrayMesh.new()
	if points.is_empty(): return result
	var arrays:=[];arrays.resize(Mesh.ARRAY_MAX);arrays[Mesh.ARRAY_VERTEX]=points
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var material:=StandardMaterial3D.new();material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color=Color("a5b9d6");material.cull_mode=BaseMaterial3D.CULL_DISABLED
	result.surface_set_material(0,material)
	return result

extends RefCounted
# Trace the actual elevated asphalt boundary, not the original OSM centerline.
const WIDTH := 0.18
const LIFT := 0.018
const GRID_SIZE := 8.0

static func key(p: Vector3) -> String:
	return "%d,%d,%d" % [roundi(p.x*1000),roundi(p.y*1000),roundi(p.z*1000)]

static func chunk_cut(a: Vector3, b: Vector3) -> bool:
	for axis in [0,2]:
		if absf(a[axis]-b[axis])<0.002 and absf(a[axis]/256.0-roundf(a[axis]/256.0))<0.00001:
			return true
	return false

static func build(road: MeshInstance3D, budget_ms: float = 0.0) -> void:
	var slice_start:=Time.get_ticks_usec()
	var max_slice:=0.0
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
			if budget_ms>0 and (Time.get_ticks_usec()-slice_start)>budget_ms*1000:
				max_slice=maxf(max_slice,(Time.get_ticks_usec()-slice_start)/1000.0)
				await road.get_tree().process_frame
				if not is_instance_valid(road) or road.is_queued_for_deletion(): return
				slice_start=Time.get_ticks_usec()
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
	# A constant-width stroke is clipped onto EACH supporting road triangle.
	# No quad may extend onto a neighbouring triangle's different slope.
	var strokes: Array[PackedVector2Array] = []
	var grid := {}
	var caps := {}
	var boundary_count := 0
	for edge in edges.values():
		if budget_ms>0 and Time.get_ticks_usec()-slice_start>budget_ms*1000:
			max_slice=maxf(max_slice,(Time.get_ticks_usec()-slice_start)/1000.0)
			await road.get_tree().process_frame
			if not is_instance_valid(road) or road.is_queued_for_deletion(): return
			slice_start=Time.get_ticks_usec()
		if edge["count"]!=1:
			continue
		var a: Vector3=edge["a"];var b: Vector3=edge["b"]
		if chunk_cut(road.to_global(a),road.to_global(b)) or a.distance_to(b)<0.002:
			continue
		var start := Vector2(a.x,a.z);var end := Vector2(b.x,b.z)
		var direction := (end-start).normalized()
		var side := Vector2(-direction.y,direction.x)*WIDTH
		add_stroke(PackedVector2Array([start-side,end-side,end+side,start+side]),strokes,grid)
		for point in [start,end]:
			var cap_key := "%d,%d" % [roundi(point.x*1000),roundi(point.y*1000)]
			if caps.has(cap_key): continue
			caps[cap_key]=true
			var circle := PackedVector2Array()
			for i in range(12):
				circle.append(point+Vector2.from_angle(TAU*i/12.0)*WIDTH)
			add_stroke(circle,strokes,grid)
		boundary_count+=1
	var points := PackedVector3Array()
	for surface in range(road.mesh.get_surface_count()):
		var source := road.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array=source[Mesh.ARRAY_VERTEX]
		var indices := PackedInt32Array()
		if source[Mesh.ARRAY_INDEX]!=null: indices=source[Mesh.ARRAY_INDEX]
		if indices.is_empty():
			for i in range(vertices.size()): indices.append(i)
		for i in range(0,indices.size(),3):
			if budget_ms>0 and (Time.get_ticks_usec()-slice_start)>budget_ms*1000:
				max_slice=maxf(max_slice,(Time.get_ticks_usec()-slice_start)/1000.0)
				await road.get_tree().process_frame
				if not is_instance_valid(road) or road.is_queued_for_deletion(): return
				slice_start=Time.get_ticks_usec()
			var a := vertices[indices[i]];var b := vertices[indices[i+1]];var c := vertices[indices[i+2]]
			var triangle := PackedVector2Array([Vector2(a.x,a.z),Vector2(b.x,b.z),Vector2(c.x,c.z)])
			var denominator := (triangle[1]-triangle[0]).cross(triangle[2]-triangle[0])
			if absf(denominator)<0.000001: continue
			var candidates := {}
			for cell in cells(triangle):
				for id in grid.get(cell,[]): candidates[id]=true
			for id in candidates:
				for polygon in Geometry2D.intersect_polygons(triangle,strokes[id]):
					var triangles := Geometry2D.triangulate_polygon(polygon)
					for index in triangles:
						var p: Vector2=polygon[index]
						var u := (p-triangle[0]).cross(triangle[2]-triangle[0])/denominator
						var v := (triangle[1]-triangle[0]).cross(p-triangle[0])/denominator
						points.append(Vector3(p.x,a.y+u*(b.y-a.y)+v*(c.y-a.y)+LIFT,p.y))
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
	road.set_meta("neon_max_slice_ms",maxf(max_slice,(Time.get_ticks_usec()-slice_start)/1000.0))

static func cells(polygon: PackedVector2Array) -> Array[Vector2i]:
	var low := polygon[0];var high := polygon[0]
	for point in polygon:
		low=low.min(point);high=high.max(point)
	var result: Array[Vector2i]=[]
	for x in range(floori(low.x/GRID_SIZE),floori(high.x/GRID_SIZE)+1):
		for z in range(floori(low.y/GRID_SIZE),floori(high.y/GRID_SIZE)+1):
			result.append(Vector2i(x,z))
	return result

static func add_stroke(polygon: PackedVector2Array, strokes: Array[PackedVector2Array], grid: Dictionary) -> void:
	var id := strokes.size()
	strokes.append(polygon)
	for cell in cells(polygon):
		if not grid.has(cell): grid[cell]=[]
		grid[cell].append(id)

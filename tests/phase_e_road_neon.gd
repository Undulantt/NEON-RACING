extends SceneTree
func _initialize() -> void:
	run.call_deferred()
func run() -> void:
	var road := MeshInstance3D.new()
	root.add_child(road)
	var a:=Vector3(10,3,10);var b:=Vector3(20,5,10)
	var c:=Vector3(20,6,20);var d:=Vector3(10,4,20)
	var arrays:=[];arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=PackedVector3Array([a,b,c,a,c,d])
	var mesh:=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	road.mesh=mesh
	preload("res://scripts/style/RoadNeon.gd").build(road)
	var neon=road.get_node("RoadEdgeNeon")
	assert(neon.get_meta("boundary_segments")==4,"Internal diagonal incorrectly outlined")
	var plane:=Plane(a,c,b)
	var error:=0.0
	for v in neon.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
		error=maxf(error,absf(absf(plane.distance_to(v))-0.018))
	assert(error<0.0001,"Neon must lie on the inclined road plane plus depth bias")
	assert(preload("res://scripts/style/RoadNeon.gd").chunk_cut(Vector3(256,3,10),Vector3(256,6,20)))
	assert(not preload("res://scripts/style/RoadNeon.gd").chunk_cut(a,b))
	print("ROAD_NEON_PASS four external edges, no diagonal, slope deviation=",error)
	road.queue_free()
	await process_frame
	quit()

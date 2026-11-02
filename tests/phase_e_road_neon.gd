extends SceneTree
const Neon=preload("res://scripts/style/RoadNeon.gd")
var failures: Array[String]=[]
func check(ok: bool, message: String) -> void:
	if not ok and not message in failures:
		failures.append(message)
		push_error(message)
func _initialize() -> void:
	run.call_deferred()
func height_on(p: Vector2, triangles: PackedVector3Array) -> float:
	for i in range(0,triangles.size(),3):
		var a:=triangles[i];var b:=triangles[i+1];var c:=triangles[i+2]
		var start:=Vector2(a.x,a.z)
		var ab:=Vector2(b.x-a.x,b.z-a.z);var ac:=Vector2(c.x-a.x,c.z-a.z)
		var u: float=(p-start).cross(ac)/ab.cross(ac)
		var v: float=ab.cross(p-start)/ab.cross(ac)
		if u>=-0.00001 and v>=-0.00001 and u+v<=1.00001:
			return a.y+u*(b.y-a.y)+v*(c.y-a.y)
	return NAN
func run() -> void:
	var sources: Array[PackedVector3Array]=[]
	var a:=Vector3(10,3,10);var b:=Vector3(20,5,10)
	var c:=Vector3(20,6,20);var d:=Vector3(10,4,20)
	sources.append(PackedVector3Array([a,b,c,a,c,d]))
	var folded:=PackedVector3Array()
	var rows:=[10.0,12.0,16.0,19.0,24.0]
	var heights:=[3.0,5.0,4.0,7.0,6.0]
	for i in range(rows.size()-1):
		a=Vector3(10,heights[i],rows[i]);b=Vector3(20,heights[i]+1,rows[i])
		c=Vector3(20,heights[i+1]+1,rows[i+1]);d=Vector3(10,heights[i+1],rows[i+1])
		folded.append_array(PackedVector3Array([a,b,c,a,c,d]))
	sources.append(folded)
	var worst:=0.0
	for source in sources:
		var road:=MeshInstance3D.new();root.add_child(road)
		var arrays:=[];arrays.resize(Mesh.ARRAY_MAX);arrays[Mesh.ARRAY_VERTEX]=source
		var mesh:=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays);road.mesh=mesh
		Neon.build(road)
		var neon=road.get_node("RoadEdgeNeon")
		check(neon.get_meta("boundary_segments")==4 if source==sources[0] else neon.get_meta("boundary_segments")==10,"Unexpected boundary edges")
		var output: PackedVector3Array=neon.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		for i in range(0,output.size(),3):
			for point in [output[i],output[i+1],output[i+2],(output[i]+output[i+1]+output[i+2])/3.0]:
				var expected:=height_on(Vector2(point.x,point.z),source)
				check(not is_nan(expected),"Ribbon protrudes beyond asphalt")
				var error: float=absf(point.y-expected-Neon.LIFT)
				worst=maxf(worst,error)
				check(error<0.0001,"Ribbon bridges or sinks into a slope change")
		# Probe both borders through every slope junction, inside the stroke.
		var end:=20.0 if source==sources[0] else 24.0
		for step in range(1,int((end-10)*20)):
			var z:=10.0+step*0.05
			for x in [10.09,19.91]:
				check(not is_nan(height_on(Vector2(x,z),output)),"Gap at a shared border junction")
		road.queue_free()
	check(Neon.chunk_cut(Vector3(256,3,10),Vector3(256,6,20)),"Chunk seam must not be outlined")
	var report:={"passed":failures.is_empty(),"failures":failures,"max_surface_error_m":worst,"scenarios":["inclined plane","successive slope reversals","border continuity","chunk seam"]}
	FileAccess.open("res://docs/phase_e_road_neon_validation.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("ROAD_NEON ",JSON.stringify(report))
	await process_frame
	quit(0 if failures.is_empty() else 1)

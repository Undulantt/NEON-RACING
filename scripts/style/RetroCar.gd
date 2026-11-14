extends RefCounted
const B = preload("res://scripts/world/BuildingBuilder.gd")
const V = preload("res://scripts/driving/CarVisual.gd")
static func shell(parent: Node3D, lower: Array[Vector3], upper: Array[Vector3], material: Material) -> void:
	var out := {"vertices":PackedVector3Array(),"normals":PackedVector3Array(),"colors":PackedColorArray()}
	for i in range(4):
		var j := (i+1)%4
		var normal := (upper[i]-lower[i]).cross(lower[j]-lower[i]).normalized()
		B.quad(out,lower[i],lower[j],upper[j],upper[i],normal,Color.WHITE)
	B.quad(out,upper[0],upper[1],upper[2],upper[3],Vector3.UP,Color.WHITE)
	var arrays := [];arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=out["vertices"];arrays[Mesh.ARRAY_NORMAL]=out["normals"]
	var mesh := ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var visual := MeshInstance3D.new();visual.mesh=mesh;visual.material_override=material;parent.add_child(visual)
static func build(car: CharacterBody3D) -> void:
	var root: Node3D = car.visual_root
	for child in root.get_children():
		if child is MeshInstance3D and child not in car.visuals["exhaust"]:
			child.visible=false
	var paint := V.material(Color("a697c9"));paint.metallic=0.45;paint.roughness=0.18
	paint.set_meta("sf4_body",true)
	var glass := V.material(Color("121b3a"));glass.metallic=0.8;glass.roughness=0.12
	var trim := V.material(Color("151426"))
	var cyan := V.material(Color("20eeff"),2.0)
	var pink := V.material(Color("ff219c"),2.0)
	car.visuals["brake_material"].albedo_color=Color("ff249f")
	car.visuals["brake_material"].emission=Color("ff249f")
	shell(root,[Vector3(-0.88,-0.24,-2.05),Vector3(0.88,-0.24,-2.05),Vector3(0.96,-0.24,2.05),Vector3(-0.96,-0.24,2.05)],[Vector3(-0.88,0.16,-2.05),Vector3(0.88,0.16,-2.05),Vector3(0.94,0.36,1.98),Vector3(-0.94,0.36,1.98)],paint)
	shell(root,[Vector3(-0.78,0.26,-0.95),Vector3(0.78,0.26,-0.95),Vector3(0.78,0.34,1.25),Vector3(-0.78,0.34,1.25)],[Vector3(-0.61,0.94,-0.25),Vector3(0.61,0.94,-0.25),Vector3(0.62,0.92,0.64),Vector3(-0.62,0.92,0.64)],glass)
	V.box(root,Vector3(1.25,0.05,0.92),Vector3(0,0.96,0.18),paint)
	for x in [-0.8,0.8]:
		V.box(root,Vector3(0.10,0.44,0.12),Vector3(x,0.58,1.66),trim)
		V.box(root,Vector3(0.04,0.065,3.5),Vector3(x*1.18,-0.16,0),cyan)
	V.box(root,Vector3(2.02,0.10,0.38),Vector3(0,0.82,1.68),paint)
	V.box(root,Vector3(1.8,0.12,0.07),Vector3(0,0.22,2.05),car.visuals["brake_material"])
	for i in range(12):
		V.box(root,Vector3(0.02,0.15,0.085),Vector3(-0.83+i*0.15,0.22,2.06),trim)
	for x in [-0.65,0.65]:
		V.box(root,Vector3(0.46,0.12,0.07),Vector3(x,0.13,-2.06),cyan)
	for i in range(5):
		V.box(root,Vector3(1.22,0.035,0.055),Vector3(0,0.87-i*0.10,0.77+i*0.10),trim)
	V.box(root,Vector3(1.7,0.07,0.08),Vector3(0,-0.14,2.07),pink)

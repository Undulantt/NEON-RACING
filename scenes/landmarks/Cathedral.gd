extends Node3D
# Reference: Mexican Ministry of Culture, monograph MX-SC-DGSMPC-EM-03-001004.
# OSM footprint retained. Heights 10/18/21 m are illustrative estimates, not surveys.
const Builder = preload("res://scripts/world/BuildingBuilder.gd")
const RING = [[-15.591207889853877, 0.9799052909513648], [-3.355647963902925, -15.410226896397035], [0.7228720099723205, -12.37460539907994], [-1.661337428033562, -9.183311004221423], [23.864921919303015, 9.83102145218686], [16.093413707801574, 20.327822527241267], [-8.976294895749675, 1.4914019535680723], [-11.096719459536416, 4.3379920757506625]]
const ROOF = [[[-15.591207889853877, 0.9799052909513648], [-11.096719459536416, 4.3379920757506625], [-8.976294895749675, 1.4914019535680723]], [[-8.976294895749675, 1.4914019535680723], [16.093413707801574, 20.327822527241267], [23.864921919303015, 9.83102145218686]], [[-1.661337428033562, -9.183311004221423], [0.7228720099723205, -12.37460539907994], [-3.355647963902925, -15.410226896397035]], [[-1.661337428033562, -9.183311004221423], [-15.591207889853877, 0.9799052909513648], [-8.976294895749675, 1.4914019535680723]], [[-8.976294895749675, 1.4914019535680723], [23.864921919303015, 9.83102145218686], [-1.661337428033562, -9.183311004221423]], [[-15.591207889853877, 0.9799052909513648], [-1.661337428033562, -9.183311004221423], [-3.355647963902925, -15.410226896397035]]]
const TOWERS = [[-12.092332091051503, 0.47209809864853014], [-2.84784077160009, -11.911351097594547]]
const ANGLE = 0.9295262017450114
func _ready() -> void:
	var out := {"vertices":PackedVector3Array(),"normals":PackedVector3Array(),"colors":PackedColorArray()}
	var color := Color("c4a28e")
	for tri in ROOF:
		Builder.triangle(out,Vector3(tri[0][0],10,tri[0][1]),Vector3(tri[1][0],10,tri[1][1]),Vector3(tri[2][0],10,tri[2][1]),Vector3.UP,color.darkened(0.2))
	for i in range(RING.size()):
		var a := Vector3(RING[i][0],0,RING[i][1])
		var b := Vector3(RING[(i+1)%RING.size()][0],0,RING[(i+1)%RING.size()][1])
		var direction := (b-a).normalized()
		Builder.quad(out,a,b,b+Vector3.UP*10,a+Vector3.UP*10,Vector3(direction.z,0,-direction.x),color)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=out["vertices"]
	arrays[Mesh.ARRAY_NORMAL]=out["normals"]
	arrays[Mesh.ARRAY_COLOR]=out["colors"]
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo=true
	material.cull_mode=BaseMaterial3D.CULL_DISABLED
	mesh.surface_set_material(0,material)
	var base := MeshInstance3D.new()
	base.mesh=mesh
	add_child(base)
	var stone := StandardMaterial3D.new()
	stone.albedo_color=color
	for p in TOWERS:
		var tower := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size=Vector3(4,18,4)
		tower.mesh=box
		tower.material_override=stone
		tower.position=Vector3(p[0],9,p[1])
		tower.rotation.y=ANGLE
		add_child(tower)
		var cap := MeshInstance3D.new()
		var pyramid := CylinderMesh.new()
		pyramid.top_radius=0
		pyramid.bottom_radius=sqrt(8.0)
		pyramid.height=3
		pyramid.radial_segments=4
		cap.mesh=pyramid
		cap.material_override=stone
		cap.position=Vector3(p[0],19.5,p[1])
		cap.rotation.y=ANGLE+PI/4
		add_child(cap)

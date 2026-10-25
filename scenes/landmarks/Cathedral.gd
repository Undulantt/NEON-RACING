extends Node3D
# Original simplified geometry. Reference: Cultura MX-SC-DGSMPC-EM-03-001004.
# Arches, oculus, four tower stages, gable and pyramid/cross silhouette are referenced.
# Every dimension/detail placement is illustrative, not surveyed. No imported artwork.
const Builder = preload("res://scripts/world/BuildingBuilder.gd")
const RING = [[-15.591207889853877, 10.000000000000007, 0.9799052909513648], [-9.473427926878458, 12.4, -7.215160802722835], [-3.355647963902925, 10.0, -15.410226896397035], [0.7228720099723205, 10.0, -12.37460539907994], [-1.661337428033562, 10.933152109911047, -9.183311004221423], [23.864921919303015, 10.925342445490925, 9.83102145218686], [20.125855873019532, 12.399999999999993, 14.881293732185497], [16.093413707801574, 10.809637265442175, 20.327822527241267], [-8.976294895749675, 10.832464351981024, 1.4914019535680723], [-11.096719459536416, 10.0, 4.3379920757506625]]
const ROOF = [[[-8.976294895749675, 10.832464351981024, 1.4914019535680723], [-15.591207889853877, 10.000000000000007, 0.9799052909513648], [-11.096719459536416, 10.0, 4.3379920757506625]], [[-8.976294895749675, 10.832464351981024, 1.4914019535680723], [16.093413707801574, 10.809637265442175, 20.327822527241267], [20.125855873019532, 12.399999999999993, 14.881293732185497]], [[-15.591207889853877, 10.000000000000007, 0.9799052909513648], [-8.976294895749675, 10.832464351981024, 1.4914019535680723], [-9.473427926878458, 12.39999999999999, -7.215160802722778]], [[-8.976294895749675, 10.832464351981024, 1.4914019535680723], [20.125855873019532, 12.399999999999993, 14.881293732185497], [-9.473427926878458, 12.39999999999999, -7.215160802722778]], [[20.125855873019532, 12.399999999999993, 14.881293732185497], [23.864921919303015, 10.925342445490925, 9.83102145218686], [-1.661337428033562, 10.933152109911047, -9.183311004221423]], [[-1.661337428033562, 10.933152109911047, -9.183311004221423], [0.7228720099723205, 10.0, -12.37460539907994], [-3.355647963902925, 10.0, -15.410226896397035]], [[-9.473427926878458, 12.39999999999999, -7.215160802722778], [20.125855873019532, 12.399999999999993, 14.881293732185497], [-1.661337428033562, 10.933152109911047, -9.183311004221423]], [[-1.661337428033562, 10.933152109911047, -9.183311004221423], [-3.355647963902925, 10.0, -15.410226896397035], [-9.473427926878458, 12.39999999999999, -7.215160802722778]]]
const TOWERS = [[-12.092332091051503, 0.47209809864853014], [-2.84784077160009, -11.911351097594547]]
const FRONT = [-9.473427926878458, -7.215160802722835]
const SIDE = Vector3(0.5982137212999272,0,-0.8013365982210553)
const INWARD = Vector3(0.8013365982210553,0,0.5982137212999272)
var out := {"vertices":PackedVector3Array(),"normals":PackedVector3Array(),"colors":PackedColorArray()}
var stone := Color("c4a28e")
func prism(at: Vector3, width: float, height: float, depth: float, color: Color) -> void:
	var a := at-SIDE*width/2-INWARD*depth/2
	var b := at+SIDE*width/2-INWARD*depth/2
	var c := at+SIDE*width/2+INWARD*depth/2
	var d := at-SIDE*width/2+INWARD*depth/2
	var up := Vector3.UP*height
	Builder.quad(out,a,b,b+up,a+up,-INWARD,color)
	Builder.quad(out,b,c,c+up,b+up,SIDE,color)
	Builder.quad(out,c,d,d+up,c+up,INWARD,color)
	Builder.quad(out,d,a,a+up,d+up,-SIDE,color)
	Builder.quad(out,a+up,b+up,c+up,d+up,Vector3.UP,color)
func arch(at: Vector3, right: Vector3, normal: Vector3, width: float, height: float) -> void:
	var points: Array[Vector3]=[at-right*width/2,at+right*width/2]
	for i in range(9):
		var angle := PI*float(i)/8
		points.append(at+right*cos(angle)*width/2+Vector3.UP*(height-width/2+sin(angle)*width/2))
	for i in range(1,points.size()-1):
		Builder.triangle(out,points[0],points[i],points[i+1],normal,Color("34434a"))
func _ready() -> void:
	for tri in ROOF:
		var a := Vector3(tri[0][0],tri[0][1],tri[0][2])
		var b := Vector3(tri[1][0],tri[1][1],tri[1][2])
		var c := Vector3(tri[2][0],tri[2][1],tri[2][2])
		var normal := (b-a).cross(c-a).normalized()
		if normal.y<0: normal=-normal
		Builder.triangle(out,a,b,c,normal,stone.darkened(0.25))
	for i in range(RING.size()):
		var p: Array=RING[i]
		var q: Array=RING[(i+1)%RING.size()]
		var a := Vector3(p[0],0,p[2])
		var b := Vector3(q[0],0,q[2])
		var direction := (b-a).normalized()
		Builder.quad(out,a,b,Vector3(q[0],q[1],q[2]),Vector3(p[0],p[1],p[2]),Vector3(direction.z,0,-direction.x),stone)
	var front := Vector3(FRONT[0],0,FRONT[1])-INWARD*0.025
	arch(front+Vector3.UP*0.2,SIDE,-INWARD,2.6,4.4)
	for shift in [-4.0,4.0]:
		arch(front+SIDE*shift+Vector3.UP*5.6,SIDE,-INWARD,1.25,2.1)
	var eye := front+Vector3.UP*7.8
	for i in range(16):
		var a := TAU*i/16.0
		var b := TAU*(i+1)/16.0
		Builder.triangle(out,eye,eye+(SIDE*cos(a)+Vector3.UP*sin(a))*0.7,eye+(SIDE*cos(b)+Vector3.UP*sin(b))*0.7,-INWARD,Color("34434a"))
	for p in TOWERS:
		var at := Vector3(p[0],0,p[1])
		prism(at,4,18,4,stone)
		for level in [4.5,9.0,13.5,17.6]:
			prism(at+Vector3.UP*level,4.2,0.3,4.2,stone.lightened(0.15))
		for normal in [SIDE,-SIDE,INWARD,-INWARD]:
			var right := Vector3(-normal.z,0,normal.x)
			arch(at+normal*2.025+Vector3.UP*14.2,right,normal,1.4,2.6)
		var peak := at+Vector3.UP*21
		var corners: Array[Vector3]=[]
		for offsets in [Vector2(-2,-2),Vector2(2,-2),Vector2(2,2),Vector2(-2,2)]:
			corners.append(at+SIDE*offsets.x+INWARD*offsets.y+Vector3.UP*18)
		for i in range(4):
			var a: Vector3=corners[i]
			var b: Vector3=corners[(i+1)%4]
			var normal := (b-a).cross(peak-a).normalized()
			if normal.y<0: normal=-normal
			Builder.triangle(out,a,b,peak,normal,stone.darkened(0.2))
		prism(peak,0.18,1.7,0.18,Color("474342"))
		prism(peak+Vector3.UP*1.05,1.2,0.18,0.18,Color("474342"))
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
	var visual := MeshInstance3D.new()
	visual.mesh=mesh
	add_child(visual)

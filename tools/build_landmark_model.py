"""Generate an original, source-referenced Cathedral silhouette inside its OSM footprint."""
import json, math
from pathlib import Path
from shapely.geometry import Polygon, LineString
from shapely.ops import split
from shapely import constrained_delaunay_triangles
ROOT=Path(__file__).resolve().parents[1]
manifest=json.loads((ROOT/'data/processed/urban/city_manifest.json').read_text(encoding='utf-8'))
b=next(b for c in manifest['chunks'] for b in json.loads((ROOT/'data/processed/urban'/c['file']).read_text(encoding='utf-8'))['buildings'] if b['id']=='osm:155831066:0')
ring=b['footprint_xz']; center=[sum(p[i] for p in ring)/len(ring) for i in (0,1)]
a,z=ring[:2]; delta=[z[i]-a[i] for i in (0,1)]; length=math.hypot(*delta); d=[v/length for v in delta]; n=[-d[1],d[0]]
local=lambda p:[p[i]-center[i] for i in (0,1)]
poly=Polygon(ring,b.get('holes_xz',[])); towers=[]
for along in (2.5,length-2.5):
    point=[a[i]+d[i]*along+n[i]*2.5 for i in (0,1)]
    cornice=Polygon([(point[0]+d[0]*u+n[0]*v,point[1]+d[1]*u+n[1]*v) for u,v in [(-2.1,-2.1),(2.1,-2.1),(2.1,2.1),(-2.1,2.1)]])
    assert poly.covers(cornice), 'Tower/cornice exceeds original footprint'
    towers.append(local(point))
mid=[(a[i]+z[i])/2 for i in (0,1)]
cut=LineString([(mid[0]+n[0]*t,mid[1]+n[1]*t) for t in [-200,200]])
def roof_point(p):
    across=(p[0]-mid[0])*d[0]+(p[1]-mid[1])*d[1]
    q=local(p);return [q[0],10+2.4*max(0,1-abs(across)/(length/2)),q[1]]
roof=[]
for part in split(poly,cut).geoms:
    roof.extend([[roof_point(v) for v in list(t.exterior.coords)[:3]] for t in constrained_delaunay_triangles(part).geoms])
wall_ring=[]
for p,q in zip(ring,ring[1:]+ring[:1]):
    wall_ring.append(p)
    ap=sum((p[i]-mid[i])*d[i] for i in (0,1)); aq=sum((q[i]-mid[i])*d[i] for i in (0,1))
    if ap*aq<0:
        ratio=ap/(ap-aq); wall_ring.append([p[i]+(q[i]-p[i])*ratio for i in (0,1)])
source='''extends Node3D
# Original simplified geometry. Reference: Cultura MX-SC-DGSMPC-EM-03-001004.
# Arches, oculus, four tower stages, gable and pyramid/cross silhouette are referenced.
# Every dimension/detail placement is illustrative, not surveyed. No imported artwork.
const Builder = preload("res://scripts/world/BuildingBuilder.gd")
const RING = %s
const ROOF = %s
const TOWERS = %s
const FRONT = %s
const SIDE = Vector3(%s,0,%s)
const INWARD = Vector3(%s,0,%s)
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
		var q: Array=RING[(i+1)%%RING.size()]
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
			var b: Vector3=corners[(i+1)%%4]
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
''' % (json.dumps([roof_point(p) for p in wall_ring]),json.dumps(roof),json.dumps(towers),json.dumps(local(mid)),d[0],d[1],n[0],n[1])
(ROOT/'scenes/landmarks/Cathedral.gd').write_text(source,encoding='utf-8')
print('Cathedral rebuilt: original footprint; contained cornices; single mesh; illustrative heights')

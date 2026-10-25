"""Original simplified silhouette using existing OSM footprint; dimensions estimated."""
import json, math
from pathlib import Path
from shapely.geometry import Polygon
ROOT=Path(__file__).resolve().parents[1]
manifest=json.loads((ROOT/'data/processed/urban/city_manifest.json').read_text())
b=next(b for c in manifest['chunks'] for b in json.loads((ROOT/'data/processed/urban'/c['file']).read_text(encoding='utf-8'))['buildings'] if b['id']=='osm:155831066:0')
ring=b['footprint_xz']; center=[sum(p[i] for p in ring)/len(ring) for i in (0,1)]
a,z=ring[:2]; delta=[z[i]-a[i] for i in (0,1)]; length=math.hypot(*delta); d=[v/length for v in delta]; n=[-d[1],d[0]]
towers=[]
for along in (2.5,length-2.5):
    point=[a[i]+d[i]*along+n[i]*2.5 for i in (0,1)]
    square=Polygon([(point[0]+d[0]*u+n[0]*v,point[1]+d[1]*u+n[1]*v) for u,v in [(-2,-2),(2,-2),(2,2),(-2,2)]])
    assert Polygon(ring).covers(square), 'Tower exceeds original footprint'
    towers.append([point[i]-center[i] for i in (0,1)])
local=lambda p:[p[i]-center[i] for i in (0,1)]
source='''extends Node3D
# Reference: Mexican Ministry of Culture, monograph MX-SC-DGSMPC-EM-03-001004.
# OSM footprint retained. Heights 10/18/21 m are illustrative estimates, not surveys.
const Builder = preload("res://scripts/world/BuildingBuilder.gd")
const RING = %s
const ROOF = %s
const TOWERS = %s
const ANGLE = %s
func _ready() -> void:
	var out := {"vertices":PackedVector3Array(),"normals":PackedVector3Array(),"colors":PackedColorArray()}
	var color := Color("c4a28e")
	for tri in ROOF:
		Builder.triangle(out,Vector3(tri[0][0],10,tri[0][1]),Vector3(tri[1][0],10,tri[1][1]),Vector3(tri[2][0],10,tri[2][1]),Vector3.UP,color.darkened(0.2))
	for i in range(RING.size()):
		var a := Vector3(RING[i][0],0,RING[i][1])
		var b := Vector3(RING[(i+1)%%RING.size()][0],0,RING[(i+1)%%RING.size()][1])
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
''' % (json.dumps([local(p) for p in ring]),json.dumps([[local(p) for p in tri] for tri in b['roof_triangles_xz']]),json.dumps(towers),math.atan2(-d[1],d[0]))
(ROOT/'scenes/landmarks/Cathedral.gd').write_text(source,encoding='utf-8')
(ROOT/'scenes/landmarks/Cathedral.tscn').write_text('[gd_scene load_steps=2 format=3]\n[ext_resource type="Script" path="res://scenes/landmarks/Cathedral.gd" id="1"]\n[node name="CathedralSilhouette" type="Node3D"]\nscript = ExtResource("1")\n',encoding='utf-8')
print('Cathedral silhouette generated; two tower footprints within source polygon')

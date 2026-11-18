extends RefCounted
# Bake local GLB node transforms once, merge by material, then instance by sector.
const SOURCES:={
	"big_palm":preload("res://assets/3D/BigPalm.glb"),
	"palm":preload("res://assets/3D/Palm.glb"),
	"chair":preload("res://assets/3D/Chair.glb"),
	"lamp":preload("res://assets/3D/LightPole.glb")}
const HEIGHTS:={"big_palm":13.0,"palm":9.5,"chair":1.15,"lamp":9.0}
var meshes:={}
var bounds:={}

func prepare() -> void:
	for kind in SOURCES:
		var root: Node3D=SOURCES[kind].instantiate()
		var pieces: Array=[]
		collect(root,Transform3D.IDENTITY,pieces)
		var box: AABB=pieces[0]["transform"]*pieces[0]["mesh"].get_aabb()
		for piece in pieces:box=box.merge(piece["transform"]*piece["mesh"].get_aabb())
		var scale_factor: float=HEIGHTS[kind]/box.size.y
		var normalize:=Transform3D(Basis.IDENTITY.scaled(Vector3.ONE*scale_factor),Vector3(0,-box.position.y*scale_factor,0))
		var groups:={}
		for piece in pieces:
			var mesh: Mesh=piece["mesh"]
			for surface in range(mesh.get_surface_count()):
				var mat: Material=mesh.surface_get_material(surface)
				var key:=mat.get_instance_id() if mat!=null else 0
				if not groups.has(key):
					var tool:=SurfaceTool.new();tool.begin(Mesh.PRIMITIVE_TRIANGLES)
					var material: Material=mat.duplicate() if mat!=null else StandardMaterial3D.new()
					var emitter:=mat!=null and mat.resource_name.begins_with("LightsFront")
					if emitter and material is StandardMaterial3D:
						material.emission=Color("ff70d7");material.albedo_color=Color("ffc4ed")
						material.emission_energy_multiplier=1.4
					tool.set_material(material)
					groups[key]={"tool":tool,"emitter":emitter}
				groups[key]["tool"].append_from(mesh,surface,normalize*piece["transform"])
		meshes[kind]=[]
		for group in groups.values():
			var mesh: ArrayMesh=group["tool"].commit()
			meshes[kind].append({"mesh":mesh,"emitter":group["emitter"]})
		bounds[kind]=normalize*box
		root.free()

func collect(node: Node, parent_transform: Transform3D, pieces: Array) -> void:
	var transform:=parent_transform
	if node is Node3D:transform=parent_transform*node.transform
	if node is MeshInstance3D and node.mesh!=null:pieces.append({"mesh":node.mesh,"transform":transform})
	for child in node.get_children():collect(child,transform,pieces)

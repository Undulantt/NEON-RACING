extends RefCounted
const Builder=preload("res://scripts/world/BuildingBuilder.gd")
const HEIGHT:=.16
var manifest:={}
var entries:={}
var valid:=false
var pavement: StandardMaterial3D
var neon: StandardMaterial3D

func configure() -> void:
	var path:="res://data/processed/streetscape/manifest.json"
	if not FileAccess.file_exists(path):push_error("Faltan banquetas: ejecutar tools/build_streetscape.py");return
	manifest=JSON.parse_string(FileAccess.get_file_as_string(path))
	for source in ["data/processed/la_paz_map.json","data/processed/arcade_layout.json","data/processed/urban/city_manifest.json","data/processed/urban/sf3_recovery/manifest.json"]:
		if manifest["sources_sha256"].has(source) and FileAccess.get_sha256("res://"+source)!=manifest["sources_sha256"][source]:
			push_error("Banquetas desactualizadas: "+source);return
	for entry in manifest["chunks"]:entries[entry["id"]]=entry
	pavement=StandardMaterial3D.new();pavement.albedo_color=Color("766b8c")
	pavement.vertex_color_use_as_albedo=true;pavement.roughness=.95
	pavement.cull_mode=BaseMaterial3D.CULL_DISABLED
	neon=StandardMaterial3D.new();neon.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	neon.vertex_color_use_as_albedo=true;neon.cull_mode=BaseMaterial3D.CULL_DISABLED
	valid=true

func read_sector(id: String) -> Dictionary:
	if not valid or not entries.has(id):return {}
	var entry: Dictionary=entries[id]
	var path: String="res://data/processed/streetscape/"+entry["file"]
	if FileAccess.get_sha256(path)!=entry["sha256"]:push_error("Sector de banquetas inválido: "+id);return {}
	var bytes:=FileAccess.get_file_as_bytes(path).decompress_dynamic(32000000,FileAccess.COMPRESSION_GZIP)
	return JSON.parse_string(bytes.get_string_from_utf8())

func geometry() -> Dictionary:
	return {"vertices":PackedVector3Array(),"normals":PackedVector3Array(),"colors":PackedColorArray()}

func ground(world: Node3D, p: Array, cache: Dictionary) -> Vector3:
	var key:=Vector2(p[0],p[1])
	if not cache.has(key):cache[key]=world.player.surface_height(key.x,key.y)
	return Vector3(key.x,cache[key],key.y)

func build(parent: Node3D, data: Dictionary, world: Node3D) -> void:
	if data.is_empty():return
	var started:=Time.get_ticks_usec();var cache:={}
	var surface:=geometry();var rim:=geometry()
	for tri in data["triangles_xz"]:
		if Time.get_ticks_usec()-started>1500:
			if not is_instance_valid(parent) or not parent.is_inside_tree() or parent.is_queued_for_deletion():return
			await parent.get_tree().process_frame
			if not is_instance_valid(parent) or not parent.is_inside_tree() or parent.is_queued_for_deletion():return
			started=Time.get_ticks_usec()
		var a:=ground(world,tri[0],cache);var b:=ground(world,tri[1],cache);var c:=ground(world,tri[2],cache)
		if not a.is_finite() or not b.is_finite() or not c.is_finite():continue
		var normal:=(c-a).cross(b-a).normalized()
		if absf(normal.y)<.85:continue
		Builder.triangle(surface,a+Vector3.UP*HEIGHT,b+Vector3.UP*HEIGHT,c+Vector3.UP*HEIGHT,Vector3.UP,Color.WHITE)
	for edge in data["edges_xz"]:
		if Time.get_ticks_usec()-started>1500:
			if not is_instance_valid(parent) or not parent.is_inside_tree() or parent.is_queued_for_deletion():return
			await parent.get_tree().process_frame
			if not is_instance_valid(parent) or not parent.is_inside_tree() or parent.is_queued_for_deletion():return
			started=Time.get_ticks_usec()
		var a:=ground(world,edge[0],cache);var b:=ground(world,edge[1],cache)
		if not a.is_finite() or not b.is_finite():continue
		var direction:=(b-a).normalized();var side:=Vector3(-direction.z,0,direction.x)*.035
		Builder.quad(surface,a,b,b+Vector3.UP*HEIGHT,a+Vector3.UP*HEIGHT,side.normalized(),Color("413650"))
		# Narrow cyan edge, matte violet pavement; restrained retrofuturist accents.
		Builder.quad(rim,a+Vector3.UP*(HEIGHT+.004)-side,b+Vector3.UP*(HEIGHT+.004)-side,b+Vector3.UP*(HEIGHT+.004)+side,a+Vector3.UP*(HEIGHT+.004)+side,Vector3.UP,Color("49c9d6"))
	var root:=Node3D.new();root.name="Sidewalks";parent.add_child(root)
	world.night_style.mesh(root,surface,pavement);world.night_style.mesh(root,rim,neon)
	for node in root.get_children():node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.set_meta("placement","derived_estimated_no_physics")
	root.set_meta("area_m2",data["sidewalk_area_m2"])

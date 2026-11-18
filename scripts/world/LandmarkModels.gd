extends Node3D
# Geographic/model presentation is independent of passport progress and car physics.
const CONTENT:="res://data/passport/landmark_models.json"
const LOAD_RADIUS:=900.0
const UNLOAD_RADIUS:=1150.0
var world: Node3D
var manifest:={}
var loaded:={}
var timer:=0.0

static func read_valid() -> Dictionary:
	if not FileAccess.file_exists(CONTENT):return {}
	var data=JSON.parse_string(FileAccess.get_file_as_string(CONTENT))
	if not data is Dictionary or data.get("schema_version")!=1:return {}
	if data.get("map_sha256")!=FileAccess.get_sha256("res://data/processed/la_paz_map.json") or data.get("arcade_sha256")!=FileAccess.get_sha256("res://data/processed/arcade_layout.json"):
		push_error("Hitos desactualizados: ejecutar tools/build_passport_landmarks.py");return {}
	for entry in data["models"]:
		# Exported PCKs may contain the imported scene/remap instead of raw GLB.
		if FileAccess.file_exists(entry["scene"]) and FileAccess.get_sha256(entry["scene"])!=entry["model_sha256"]:
			push_error("Modelo de hito modificado: "+entry["scene"]);return {}
		if not ResourceLoader.exists(entry["scene"]):push_error("Falta modelo de hito: "+entry["scene"]);return {}
	return data

func configure(target: Node3D) -> void:
	world=target;manifest=read_valid();refresh()

func blocked(point: Vector2, margin:=0.0) -> bool:
	for entry in manifest.get("models",[]):
		var polygon:=PackedVector2Array()
		for p in entry["footprint_xz"]:polygon.append(Vector2(p[0],p[1]))
		if Geometry2D.is_point_in_polygon(point,polygon):return true
		if margin>0:
			for i in range(polygon.size()):
				if point.distance_to(Geometry2D.get_closest_point_to_segment(point,polygon[i],polygon[(i+1)%polygon.size()]))<margin:return true
	return false

func refresh() -> void:
	if manifest.is_empty():return
	var enabled: bool=world.city_manager==null or world.city_manager.city_enabled
	for entry in manifest["models"]:
		var p:=Vector2(entry["position_xz"][0],entry["position_xz"][1])
		var distance:=p.distance_to(Vector2(world.player.position.x,world.player.position.z))
		var id: String=entry["id"]
		if loaded.has(id) and distance>UNLOAD_RADIUS:
			loaded[id].queue_free();loaded.erase(id)
		if not loaded.has(id) and distance<LOAD_RADIUS:build(entry)
		if loaded.has(id):
			loaded[id].visible=enabled
			for child in loaded[id].get_children():
				if child is StaticBody3D:child.collision_layer=4 if enabled and distance<240 else 0

func build(entry: Dictionary) -> void:
	var scene: PackedScene=load(entry["scene"])
	var model: Node3D=scene.instantiate()
	# Plaza/lamps/trees exported with the kiosk are omitted: their coordinates
	# would cross the widened road. The actual kiosk and stair meshes remain.
	for node_name in entry["exclude_nodes"]:
		var node=model.find_child(node_name,true,false)
		if node!=null:node.free()
	var root:=Node3D.new();root.name=entry["id"]
	root.set_meta("poi_id",entry["poi_id"]);root.set_meta("identity_confidence",entry["identity_confidence"])
	var low:=Vector3(entry["source_bounds_min"][0],entry["source_bounds_min"][1],entry["source_bounds_min"][2])
	var high:=Vector3(entry["source_bounds_max"][0],entry["source_bounds_max"][1],entry["source_bounds_max"][2])
	var at: Array=entry["position_xz"]
	var base: float=world.player.surface_height(at[0],at[1]);var lowest:=base
	for point in entry["footprint_xz"]:
		var y: float=world.player.surface_height(point[0],point[1])
		if not is_finite(y):model.free();root.free();return
		base=maxf(base,y);lowest=minf(lowest,y)
	if not is_finite(base):model.free();root.free();return
	add_child(root)
	var placement:=Node3D.new();placement.name="ModelPlacement";root.add_child(placement)
	placement.transform=Transform3D(Basis(Vector3.UP,entry["yaw"]).scaled(Vector3.ONE*entry["scale"]),Vector3(at[0],base+.02,at[1]))
	model.name="ImportedModel";placement.add_child(model)
	model.position=Vector3(-(low.x+high.x)*.5,-low.y,-(low.z+high.z)*.5)
	for visual in model.find_children("*","GeometryInstance3D",true,false):visual.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# One conservative box per landmark, already proven outside playable asphalt.
	var size: Vector3=(high-low)*float(entry["scale"])
	var body:=StaticBody3D.new();body.name="LandmarkCollision";body.collision_layer=0;body.collision_mask=0
	root.add_child(body);body.position=Vector3(at[0],base+.02+size.y*.5,at[1]);body.rotation.y=entry["yaw"]
	var shape:=BoxShape3D.new();shape.size=size
	var collider:=CollisionShape3D.new();collider.shape=shape;body.add_child(collider)
	if base-lowest>.08:
		var foundation:=MeshInstance3D.new();var mesh:=BoxMesh.new()
		mesh.size=Vector3(size.x,base-lowest+.04,size.z);foundation.mesh=mesh
		foundation.position=Vector3(at[0],lowest+(base-lowest)*.5,at[1]);foundation.rotation.y=entry["yaw"]
		var mat:=StandardMaterial3D.new();mat.albedo_color=Color("534b69");mat.roughness=.9
		foundation.material_override=mat;foundation.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(foundation)
	loaded[entry["id"]]=root

func _process(delta: float) -> void:
	timer+=delta
	if timer>=.25:timer=0;refresh()

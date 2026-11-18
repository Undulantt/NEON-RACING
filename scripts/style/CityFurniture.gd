extends RefCounted
# Deterministic decorative placement, never a claim about surveyed street assets.
const Builder=preload("res://scripts/world/BuildingBuilder.gd")
var world: Node3D
var roads := {}
var assets := {}
var library:=preload("res://scripts/style/UrbanAssetLibrary.gd").new()
var sidewalks:=preload("res://scripts/style/SidewalkBuilder.gd").new()
var sectors := {}
var lights: Array[OmniLight3D]=[] # No per-street dynamic lights; kept for diagnostic compatibility.
var street_pools:=PackedVector4Array()
var collision_shapes := {}

func configure(target: Node3D) -> void:
	world=target
	for road in world.map_data["roads"]:
		var a:=point(road["points_xz"][0]);var b:=point(road["points_xz"][-1])
		var low:=a.min(b)-Vector2.ONE*40;var high:=a.max(b)+Vector2.ONE*40
		for x in range(floori(low.x/256),floori(high.x/256)+1):
			for z in range(floori(low.y/256),floori(high.y/256)+1):
				var cell:=Vector2i(x,z)
				if not roads.has(cell): roads[cell]=[]
				roads[cell].append(road)
	library.prepare()
	assets=library.meshes
	assets["tree"]=[{"mesh":make_tree_asset(),"emitter":false}]
	sidewalks.configure()
	for kind in assets:
		if kind=="chair":
			var shape:=BoxShape3D.new();shape.size=Vector3(2.45,1.15,.85)
			collision_shapes[kind]=shape
		else:
			var shape:=CapsuleShape3D.new();shape.radius=.2 if kind=="lamp" else .38
			shape.height=8.5 if kind=="lamp" else 3.5 if kind=="tree" else 5.0
			collision_shapes[kind]=shape
	street_pools.resize(4)

func point(p: Array) -> Vector2: return Vector2(p[0],p[1])
func roads_for(cell: Vector2i) -> Array: return roads.get(cell,[])
func geometry() -> Dictionary:
	return {"vertices":PackedVector3Array(),"normals":PackedVector3Array(),"colors":PackedColorArray()}
func tube(data: Dictionary,a: Vector3,b: Vector3,radius: float,color: Color) -> void:
	var up:=(b-a).normalized()
	var side:=up.cross(Vector3.FORWARD).normalized()
	if side.length_squared()<0.1: side=Vector3.RIGHT
	var across:=up.cross(side).normalized()
	for i in range(6):
		var d:=(side*cos(TAU*i/6)+across*sin(TAU*i/6))*radius
		var e:=(side*cos(TAU*(i+1)/6)+across*sin(TAU*(i+1)/6))*radius
		Builder.quad(data,a+d,a+e,b+e,b+d,d.normalized(),color)
func make_tree_asset() -> ArrayMesh:
	var data:=geometry()
	tube(data,Vector3.ZERO,Vector3(0,3.5,0),0.24,Color("685475"))
	for i in range(3):
		var branch:=Vector3(cos(i*TAU/3)*1.25,4.0,sin(i*TAU/3)*1.25)
		tube(data,Vector3(0,2.3,0),branch,0.10,Color("685475"))
	# Faceted crown; original geometry, no transparent foliage or extra lights.
	for ring in range(3):
		var y0:=3.0+ring*1.05;var y1:=y0+1.05
		var r0: float=[1.0,2.1,1.8][ring];var r1: float=[2.1,1.8,0.2][ring]
		for i in range(7):
			var a:=Vector3(cos(i*TAU/7),0,sin(i*TAU/7))
			var b:=Vector3(cos((i+1)*TAU/7),0,sin((i+1)*TAU/7))
			Builder.quad(data,a*r0+Vector3.UP*y0,b*r0+Vector3.UP*y0,b*r1+Vector3.UP*y1,a*r1+Vector3.UP*y1,a,Color("326b72") if i%2==0 else Color("274858"))
	var arrays:=[];arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=data["vertices"];arrays[Mesh.ARRAY_NORMAL]=data["normals"];arrays[Mesh.ARRAY_COLOR]=data["colors"]
	var mesh:=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var mat:=StandardMaterial3D.new();mat.vertex_color_use_as_albedo=true
	mat.roughness=0.85;mat.cull_mode=BaseMaterial3D.CULL_DISABLED
	mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color=Color(0.5,0.6,0.7)
	mesh.surface_set_material(0,mat)
	return mesh

func build(parent: Node3D, id: String) -> void:
	var data:=sidewalks.read_sector(id)
	if data.is_empty():return
	# Banquetas first: the prepared positions are owned by this same sector.
	await sidewalks.build(parent,data,world)
	if not is_instance_valid(parent) or not parent.is_inside_tree() or parent.is_queued_for_deletion():return
	var transforms:={"lamp":[],"palm":[],"big_palm":[],"tree":[],"chair":[]}
	var light_positions: Array[Vector3]=[]
	var slice_start:=Time.get_ticks_usec()
	var records: Array=[]
	for item in data["furniture"]:
		if Time.get_ticks_usec()-slice_start>1500:
			if not is_instance_valid(parent) or not parent.is_inside_tree() or parent.is_queued_for_deletion():return
			world.night_style.record_work("fixture_slice",slice_start)
			await parent.get_tree().process_frame
			if not is_instance_valid(parent) or not parent.is_inside_tree() or parent.is_queued_for_deletion():return
			slice_start=Time.get_ticks_usec()
		var p:=point(item["position_xz"])
		if world.landmark_models!=null and world.landmark_models.blocked(p,1.0):continue
		# Offline footprint/exclusion validation; runtime also requires loaded terrain.
		var height: float=world.player.surface_height(p.x,p.y)
		if not is_finite(height):continue
		var ray:=PhysicsRayQueryParameters3D.create(Vector3(p.x,height+30,p.y),Vector3(p.x,height-30,p.y),3)
		var hit:=world.get_world_3d().direct_space_state.intersect_ray(ray)
		if hit.is_empty() or hit["collider"].collision_layer!=2 or hit["normal"].y<.92:continue
		var kind: String=item["kind"]
		var foot:=Vector3(p.x,height+.16,p.y)
		var pose:=Transform3D(Basis(Vector3.UP,float(item["yaw"])),foot)
		transforms[kind].append(pose);records.append(item)
		if kind=="lamp":light_positions.append(foot+Vector3.UP*7.8)
	var uploading:=Time.get_ticks_usec()
	var body:=StaticBody3D.new();body.name="StreetFurnitureCollision"
	body.collision_layer=0;body.collision_mask=0;body.set_meta("street_furniture",true)
	parent.get_parent().add_child(body)
	for kind in transforms:
		for pose in transforms[kind]:
			var collision:=CollisionShape3D.new();collision.shape=collision_shapes[kind]
			var center: float=4.25 if kind=="lamp" else .575 if kind=="chair" else 1.75 if kind=="tree" else 2.5
			collision.transform=pose*Transform3D(Basis.IDENTITY,Vector3.UP*center)
			collision.set_meta("fixture_kind",kind);body.add_child(collision)
		if transforms[kind].is_empty():continue
		for part in assets[kind]:
			var batch:=MultiMesh.new();batch.transform_format=MultiMesh.TRANSFORM_3D
			batch.mesh=part["mesh"];batch.instance_count=transforms[kind].size()
			for i in range(batch.instance_count):batch.set_instance_transform(i,transforms[kind][i])
			var visual:=MultiMeshInstance3D.new()
			visual.name=kind.capitalize()+("EmitterBatch" if part["emitter"] else "Batch")
			visual.multimesh=batch;visual.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			visual.visibility_range_end=360 if kind=="lamp" else 280
			visual.set_meta("sf3_lamp_emitter",bool(part["emitter"]))
			visual.set_meta("source_model",kind)
			parent.add_child(visual)
	parent.set_meta("furniture_counts",{"lamps":transforms["lamp"].size(),"palms":transforms["palm"].size(),"big_palms":transforms["big_palm"].size(),"trees":transforms["tree"].size(),"chairs":transforms["chair"].size()})
	parent.set_meta("furniture_records",records)
	world.night_style.record_work("fixtures_upload",uploading)
	sectors[id]={"owner":weakref(parent),"lights":light_positions}
	var manager=world.city_manager
	if manager.loaded.has(id):
		manager.set_collisions(parent.get_parent(),manager.city_enabled and manager.distance_to(manager.loaded[id]["source"])<=float(manager.manifest["settings"]["collision_radius_m"]))

func update_lights() -> void:
	var positions: Array[Vector3]=[]
	for id in sectors.keys():
		if not is_instance_valid(sectors[id]["owner"].get_ref()): sectors.erase(id);continue
		for p in sectors[id]["lights"]:
			if p.distance_squared_to(world.player.position)<70*70: positions.append(p)
	positions.sort_custom(func(a,b): return a.distance_squared_to(world.player.position)<b.distance_squared_to(world.player.position))
	for i in range(4):
		street_pools[i]=Vector4.ZERO
		if world.city_manager.city_enabled and not "--no-street-lights" in OS.get_cmdline_user_args() and i<positions.size():
			var p:=positions[i]
			street_pools[i]=Vector4(p.x,p.y,p.z,1)

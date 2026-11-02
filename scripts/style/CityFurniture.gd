extends RefCounted
# Deterministic decorative placement, never a claim about surveyed street assets.
const Builder=preload("res://scripts/world/BuildingBuilder.gd")
var world: Node3D
var roads := {}
var building_cache := {}
var assets := {}
var sectors := {}
var lights: Array[OmniLight3D]=[]
var placed := {}

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
	for kind in ["lamp","palm","tree"]: assets[kind]=make_asset(kind)
	for i in range(4):
		var light:=OmniLight3D.new()
		light.omni_range=20;light.light_energy=1.4
		light.light_color=Color("f0a2db");light.shadow_enabled=false;light.visible=false
		world.night_style.add_child(light);lights.append(light)

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
func make_asset(kind: String) -> ArrayMesh:
	var data:=geometry()
	if kind=="lamp":
		tube(data,Vector3.ZERO,Vector3(0,6,0),0.12,Color("5b6085"))
		tube(data,Vector3(0,6,0),Vector3(0,7,-0.8),0.1,Color("70608c"))
		tube(data,Vector3(0,7,-0.8),Vector3(0,7,-2.2),0.1,Color("70608c"))
		Builder.quad(data,Vector3(-0.45,6.95,-2.4),Vector3(0.45,6.95,-2.4),Vector3(0.45,6.95,-1.5),Vector3(-0.45,6.95,-1.5),Vector3.DOWN,Color("ff88df"))
	elif kind=="palm":
		for i in range(7):
			tube(data,Vector3(0.012*i*i,i*1.15,0),Vector3(0.012*(i+1)*(i+1),(i+1)*1.15,0),0.23-i*0.015,Color("65506d"))
		var crown:=Vector3(0.588,8.05,0)
		for leaf in range(9):
			var direction:=Vector3(cos(leaf*TAU/9),0,sin(leaf*TAU/9))
			var side:=Vector3(-direction.z,0,direction.x)
			for part in range(6):
				var t:=float(part)/6;var u:=float(part+1)/6
				var a:=crown+direction*t*3.2+Vector3.UP*(sin(t*PI)*0.8-t*t*1.6)
				var b:=crown+direction*u*3.2+Vector3.UP*(sin(u*PI)*0.8-u*u*1.6)
				for sign in [-1,1]:
					Builder.triangle(data,a,b,a+side*(1-t)*0.65*sign-direction*0.2,Vector3.UP,Color("29616b"))
	else:
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
	if kind=="lamp": mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.surface_set_material(0,mat)
	return mesh

func building_clear(p: Vector2, radius: float) -> bool:
	var manager=world.city_manager
	var seen:={}
	for x in range(floori((p.x-radius)/256),floori((p.x+radius)/256)+1):
		for z in range(floori((p.y-radius)/256),floori((p.y+radius)/256)+1):
			for entry in manager.spatial_index.get(Vector2i(x,z),[]): seen[entry["id"]]=entry
	for id in seen:
		if not building_cache.has(id):
			var data=JSON.parse_string(FileAccess.get_file_as_string(manager.data_root+str(seen[id]["file"])))
			manager.apply_arcade_layout(data)
			var rings: Array=[]
			for building in data["buildings"]:
				if building.get("disabled",false): continue
				var polygon:=PackedVector2Array()
				for vertex in building["footprint_xz"]: polygon.append(point(vertex))
				rings.append(polygon)
			building_cache[id]=rings
		for polygon in building_cache[id]:
			if Geometry2D.is_point_in_polygon(p,polygon): return false
			for i in range(polygon.size()):
				if p.distance_to(Geometry2D.get_closest_point_to_segment(p,polygon[i],polygon[(i+1)%polygon.size()]))<radius: return false
	return true

func support(p: Vector2, radius: float, nearby: Array) -> float:
	for road in nearby:
		var a:=point(road["points_xz"][0]);var b:=point(road["points_xz"][-1])
		if p.distance_to(Geometry2D.get_closest_point_to_segment(p,a,b))<float(road["width_m"])*0.5+0.8: return NAN
	if not building_clear(p,radius): return NAN
	var height: float=world.player.surface_height(p.x,p.y)
	if not is_finite(height): return NAN
	var query:=PhysicsRayQueryParameters3D.create(Vector3(p.x,height+30,p.y),Vector3(p.x,height-30,p.y),3)
	var hit:=world.get_world_3d().direct_space_state.intersect_ray(query)
	# Real terrain support only: no asphalt, no sea, no guesses outside loaded ground.
	if hit.is_empty() or hit["collider"].collision_layer!=2 or hit["normal"].y<0.92: return NAN
	for offset in [Vector2(0.7,0),Vector2(-0.7,0),Vector2(0,0.7),Vector2(0,-0.7)]:
		var h: float=world.player.surface_height(p.x+offset.x,p.y+offset.y)
		if not is_finite(h) or absf(h-height)>0.5: return NAN
	return hit["position"].y

func build(parent: Node3D, id: String) -> void:
	var cell:=Vector2i(int(id.split("_")[0]),int(id.split("_")[1]))
	var area:=Rect2(Vector2(cell)*256,Vector2(256,256))
	var nearby:=roads_for(cell)
	var transforms:={"lamp":[],"palm":[],"tree":[]}
	var light_positions: Array[Vector3]=[]
	var occupied: Array[Vector2]=[]
	var candidates:=nearby.duplicate()
	candidates.sort_custom(func(a,b): return str(a["id"])<str(b["id"]))
	for road in candidates:
		if road.get("highway","") in ["footway","path","steps","cycleway","service","track"]: continue
		var a:=point(road["points_xz"][0]);var b:=point(road["points_xz"][-1])
		var length:=a.distance_to(b);var half:=float(road["width_m"])*0.5
		var margin:=maxf(10,half+3)
		if length<margin*2: continue
		var direction:=(b-a).normalized();var side:=Vector2(direction.y,-direction.x)
		var count:=maxi(1,floori(length/38))
		for index in range(count):
			var center:=a.lerp(b,(index+0.5)/count)
			if center.distance_to(a)<margin or center.distance_to(b)<margin: continue
			for kind in ["lamp","vegetation"]:
				if transforms["lamp"].size()>=24 and kind=="lamp": continue
				if transforms["palm"].size()+transforms["tree"].size()>=14 and kind=="vegetation": continue
				var seed:=absi((str(road["id"])+str(index)).hash())
				var sign:=1 if seed%2==0 else -1
				if kind=="vegetation": sign=-sign
				var p:=center+side*(half+(1.8 if kind=="lamp" else 4.2))*sign
				if not area.has_point(p): continue
				var radius:=0.9 if kind=="lamp" else 3.6
				var clear:=true
				for other in occupied:
					if p.distance_to(other)<10: clear=false;break
				# Globally owned 12m cells prevent duplicate fixtures across sectors.
				var slot:=Vector2i(floori(p.x/12),floori(p.y/12))
				for dx in range(-1,2):
					for dz in range(-1,2):
						var other_slot:=slot+Vector2i(dx,dz)
						if placed.has(other_slot) and is_instance_valid(placed[other_slot]["owner"].get_ref()) and p.distance_to(placed[other_slot]["point"])<10: clear=false
				if not clear: continue
				var y:=support(p,radius,nearby)
				if not is_finite(y): continue
				var foot:=Vector3(p.x,y,p.y)
				var inward:=-side*sign
				var yaw:=atan2(-inward.x,-inward.y)
				var type: String=kind
				if kind=="vegetation":
					type="palm" if str(road["osm_way_id"])==str(world.night_config["promenade_way_id"]) or (y<5 and seed%3==0) else "tree"
				transforms[type].append(Transform3D(Basis(Vector3.UP,yaw),foot))
				if type=="lamp": light_positions.append(foot+Vector3.UP*6.8+Vector3(inward.x,0,inward.y)*1.6)
				occupied.append(p);placed[slot]={"owner":weakref(parent),"point":p}
	for kind in transforms:
		if transforms[kind].is_empty(): continue
		var batch:=MultiMesh.new();batch.transform_format=MultiMesh.TRANSFORM_3D
		batch.mesh=assets[kind];batch.instance_count=transforms[kind].size()
		for i in range(batch.instance_count): batch.set_instance_transform(i,transforms[kind][i])
		var visual:=MultiMeshInstance3D.new();visual.name=kind.capitalize()+"Batch"
		visual.multimesh=batch;visual.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		visual.visibility_range_end=360 if kind=="lamp" else 280
		parent.add_child(visual)
	parent.set_meta("furniture_counts",{"lamps":transforms["lamp"].size(),"palms":transforms["palm"].size(),"trees":transforms["tree"].size()})
	sectors[id]={"owner":weakref(parent),"lights":light_positions}
	if building_cache.size()>48: building_cache.clear()

func update_lights() -> void:
	var positions: Array[Vector3]=[]
	for id in sectors.keys():
		if not is_instance_valid(sectors[id]["owner"].get_ref()): sectors.erase(id);continue
		for p in sectors[id]["lights"]:
			if p.distance_squared_to(world.player.position)<70*70: positions.append(p)
	positions.sort_custom(func(a,b): return a.distance_squared_to(world.player.position)<b.distance_squared_to(world.player.position))
	for i in range(lights.size()):
		lights[i].visible=world.city_manager.city_enabled and i<positions.size()
		if i<positions.size(): lights[i].position=positions[i]
	for slot in placed.keys():
		if not is_instance_valid(placed[slot]["owner"].get_ref()): placed.erase(slot)

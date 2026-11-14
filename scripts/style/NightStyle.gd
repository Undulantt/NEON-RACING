extends Node3D

const Builder = preload("res://scripts/world/BuildingBuilder.gd")
var world: Node3D
var settings: Dictionary
var timer := 0.0
var decorated := 0
var decorating := false
var work_log: Array=[]
var facade_material: StandardMaterial3D
var window_count := 0
var sign_count := 0
var storefront_count := 0
var lamps: Array[Light3D] = []
var audio: CanvasLayer
var pilot: Node3D
var emission: StandardMaterial3D
var furniture: RefCounted
var solid: StandardMaterial3D
var clouds: Node3D

func material(color: Color, luminous := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.78
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if luminous:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m

func configure(target: Node3D, config: Dictionary) -> void:
	world = target
	settings = config
	if settings.get("citywide",false):
		furniture=preload("res://scripts/style/CityFurniture.gd").new()
		furniture.configure(world)
	emission = material(Color.WHITE,true)
	solid = material(Color("687c98"))
	facade_material=material(Color("8460a8"))
	for node in world.get_children():
		if world.night_visuals: continue
		if node is WorldEnvironment:
			var env: Environment = node.environment
			env.background_color = Color("070d24")
			env.ambient_light_color = Color("839ed8")
			env.ambient_light_energy = 0.28

		if node is DirectionalLight3D:
			node.light_color = Color("8aafff")
			node.light_energy = 0.24
			node.shadow_enabled = false
			node.rotation_degrees = Vector3(-48,-22,0)
	for x in [0.0]:
		var head := SpotLight3D.new()
		head.position = Vector3(x,0.25,-1.7)
		head.rotation.x = deg_to_rad(-8)
		head.light_color = Color("d4edff")
		head.light_energy = 2.3
		head.spot_range = 42
		head.spot_angle = 38
		head.spot_attenuation = 0.6
		head.shadow_enabled = false
		world.player.visual_root.add_child(head)
	audio = preload("res://scripts/style/NightAudio.gd").new()
	add_child(audio)
	audio.configure(world,settings)
	audio.music.stop()
	var retro := preload("res://scripts/style/RetroLook.gd").new()
	add_child(retro)
	retro.configure(world)
	clouds = preload("res://scripts/style/NeonClouds.gd").new()
	clouds.name = "NeonClouds"
	add_child(clouds)
	clouds.configure(world)
	world.follow_camera.experiment_panel.bind_city_clouds(clouds)
	world.follow_camera.speed_feedback.environment_feedback.bind_world(world,retro.road_material,furniture)
	refresh()

func geometry() -> Dictionary:
	return {"vertices":PackedVector3Array(),"normals":PackedVector3Array(),"colors":PackedColorArray()}

func mesh(parent: Node3D, data: Dictionary, mat: Material) -> void:
	if data["vertices"].is_empty():
		return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = data["vertices"]
	arrays[Mesh.ARRAY_NORMAL] = data["normals"]
	arrays[Mesh.ARRAY_COLOR] = data["colors"]
	var resource := ArrayMesh.new()
	resource.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var instance := MeshInstance3D.new()
	instance.mesh = resource
	instance.material_override = mat
	parent.add_child(instance)

func facade_edge(ring: Array) -> int:
	# Cosmetic facade choice is bounded even for very complex footprints.
	var candidates: Array=[];var center:=Vector2.ZERO
	for index in range(ring.size()):
		var a:=Vector2(ring[index][0],ring[index][1])
		var b:=Vector2(ring[(index+1)%ring.size()][0],ring[(index+1)%ring.size()][1])
		center+=a
		if a.distance_squared_to(b)>=16: candidates.append({"index":index,"mid":(a+b)*0.5,"length":a.distance_squared_to(b)})
	center/=maxi(1,ring.size())
	candidates.sort_custom(func(a,b): return a["length"]>b["length"])
	var streets: Array=[]
	for road in nearby_roads:
		var p:=Vector2(road["points_xz"][0][0],road["points_xz"][0][1])
		var q:=Vector2(road["points_xz"][-1][0],road["points_xz"][-1][1])
		streets.append({"p":p,"q":q,"distance":center.distance_squared_to(Geometry2D.get_closest_point_to_segment(center,p,q))})
	streets.sort_custom(func(a,b): return a["distance"]<b["distance"])
	var best:=INF;var chosen:=0
	for edge in candidates.slice(0,24):
		for road in streets.slice(0,16):
			var distance: float=edge["mid"].distance_squared_to(Geometry2D.get_closest_point_to_segment(edge["mid"],road["p"],road["q"]))
			if distance<best: best=distance;chosen=edge["index"]
	return chosen

var nearby_roads: Array = []
func ground(p: Vector2) -> float:
	return world.player.surface_height(p.x,p.y)

func refresh() -> void:
	if decorating: return
	if settings.get("citywide",false):
		var ids: Array=world.city_manager.loaded.keys()
		ids.sort_custom(func(a,b): return world.city_manager.distance_to(world.city_manager.loaded[a]["source"])<world.city_manager.distance_to(world.city_manager.loaded[b]["source"]))
		for id in ids:
			if not world.city_manager.loaded[id]["node"].has_meta("night_decorated"):
				decorating=true
				await decorate(str(id))
				decorating=false
				break
	else:
		decorate(str(settings["sector"]))

func decorate(id: String) -> void:
	var manager = world.city_manager
	if not manager.loaded.has(id):
		return
	var entry: Dictionary = manager.loaded[id]
	var chunk: Node3D = entry["node"]
	if chunk.has_meta("night_decorated"):
		return
	chunk.set_meta("night_decorated",true)
	decorated += 1
	window_count = 0
	sign_count = 0
	storefront_count = 0
	if not settings.get("citywide",false): lamps.clear()
	pilot = Node3D.new()
	pilot.name = "NightPilotDecor"
	chunk.add_child(pilot)
	var reading:=Time.get_ticks_usec()
	var data: Dictionary = manager.read_chunk(entry["source"])
	if data.is_empty() or not manager.apply_arcade_layout(data): return
	record_work("facade_data",reading)
	var lit := geometry()
	var storefronts := geometry()
	var tint := facade_material
	if not world.night_visuals:
		for visual in chunk.find_children("*","MeshInstance3D",true,false):
			visual.material_override = tint
	nearby_roads=[]
	var cell := Vector2(float(id.split("_")[0]),float(id.split("_")[1]))*256
	if furniture!=null:
		nearby_roads=furniture.roads_for(Vector2i(cell/256))
	else:
		var area := Rect2(cell,Vector2(256,256)).grow(40)
		for road in world.map_data["roads"]:
			var p := Vector2(road["points_xz"][0][0],road["points_xz"][0][1])
			if area.has_point(p): nearby_roads.append(road)
	var slice_start:=Time.get_ticks_usec()
	for b in data["buildings"]:
		if furniture!=null and Time.get_ticks_usec()-slice_start>1500:
			record_work("facade_slice",slice_start)
			await get_tree().process_frame
			if not is_instance_valid(chunk) or chunk.is_queued_for_deletion(): return
			slice_start=Time.get_ticks_usec()
		if b.get("disabled",false):
			continue
		var ring: Array = b["footprint_xz"]
		var edges: Array[int] = [int(b["facade_edge_index"]) if b.has("facade_edge_index") else facade_edge(ring)]
		for index in range(ring.size()):
			if edges.size() >= 3:
				break
			var p := Vector2(ring[index][0],ring[index][1])
			var q := Vector2(ring[(index+1)%ring.size()][0],ring[(index+1)%ring.size()][1])
			if p.distance_to(q) > 8 and not index in edges:
				edges.append(index)
		for edge in edges:
			var a := Vector2(ring[edge][0],ring[edge][1])
			var z := Vector2(ring[(edge+1)%ring.size()][0],ring[(edge+1)%ring.size()][1])
			var direction := (z-a).normalized()
			var normal := Vector3(direction.y,0,-direction.x)
			var tangent := Vector3(direction.x,0,direction.y)
			var length := a.distance_to(z)
			var count := mini(6,floori(length/3))
			var height := float(b["height_m"])
			var base := float(b.get("base_y_m",0))
			var category: String = b.get("category","unknown")
			var commercial := category in ["commercial","restaurant","hotel","cultural"]
			if manager.facades_enabled and length > 3:
				# A shallow base strip and one door, merged into the existing solid
				# batch. Artistic details; never alter the geographic collider.
				var plinth := Vector3(a.x,base+0.03,a.y)+normal*0.045
				Builder.quad(storefronts,plinth,plinth+tangent*length,plinth+tangent*length+Vector3.UP*0.38,plinth+Vector3.UP*0.38,normal,Color("55516c"))
				if edge == edges[0] and not commercial:
					var door := plinth+tangent*minf(1.0,length*0.2)+normal*0.02
					Builder.quad(storefronts,door,door+tangent*0.9,door+tangent*0.9+Vector3.UP*minf(2.2,height-0.4),door+Vector3.UP*minf(2.2,height-0.4),normal,Color("192635"))
			if commercial and edge == edges[0] and length > 6 and storefront_count < 10:
				var start := Vector3(a.x,base,a.y)+tangent*0.5+normal*0.10
				var span := minf(6.0,length-1.0)
				var top := minf(2.6,height-0.3)
				Builder.quad(storefronts,start,start+tangent*span,start+tangent*span+Vector3.UP*top,start+Vector3.UP*top,normal,Color("162c3b"))
				# One door, glazed bay, mullions and shallow awning; cosmetics only.
				var door := start+tangent*0.12+normal*0.02
				Builder.quad(storefronts,door,door+tangent*0.95,door+tangent*0.95+Vector3.UP*(top-0.15),door+Vector3.UP*(top-0.15),normal,Color("0c1526"))
				for column in range(1,4):
					var frame := start+tangent*(span*column/4)+normal*0.025
					Builder.quad(storefronts,frame,frame+tangent*0.07,frame+tangent*0.07+Vector3.UP*top,frame+Vector3.UP*top,normal,Color("71949e"))
				var canopy := start+Vector3.UP*(top+0.12)
				Builder.quad(storefronts,canopy,canopy+tangent*span,canopy+tangent*span+normal*0.6,canopy+normal*0.6,Vector3.UP,Color("67587e"))
				Builder.quad(storefronts,canopy+normal*0.6,canopy+tangent*span+normal*0.6,canopy+tangent*span+normal*0.6-Vector3.UP*0.18,canopy+normal*0.6-Vector3.UP*0.18,normal,Color("67587e"))
				storefront_count += 1
			if length > 8:
				var cornice := Vector3(a.x,base+height-0.2,a.y)+normal*0.07
				Builder.quad(lit,cornice,cornice+tangent*length,cornice+tangent*length+Vector3.UP*0.10,cornice+Vector3.UP*0.10,normal,Color("6854b9"))
			for floor_index in range(mini(3,maxi(1,floori(height/3)))):
				for i in range(count):
					if (i+floor_index+int(b["palette_index"]))%3 == 0:
						continue
					var p := Vector3(a.x,base+1.1+floor_index*3,a.y)+tangent*(1.0+i*length/maxi(count,1))+normal*0.065
					var color := Color("dcb080") if not commercial else Color("e6a3c9") if i%2 == 0 else Color("70cad6")
					var unlit: bool = manager.facades_enabled and (i+floor_index+int(b["palette_index"]))%4 == 0
					Builder.quad(storefronts if unlit else lit,p,p+tangent*1.1,p+tangent*1.1+Vector3.UP,p+Vector3.UP,normal,Color("172e42") if unlit else color)
					window_count += 1
			if commercial and length > 5 and sign_count < 8:
				var p := Vector3(a.x,base+minf(3,height-0.4),a.y)+tangent*0.6+normal*0.085
				var color := Color("ff2cd8") if sign_count%2 == 0 else Color("30f4ff")
				Builder.quad(lit,p,p+tangent*minf(7,length-1.2),p+tangent*minf(7,length-1.2)+Vector3.UP*0.18,p+Vector3.UP*0.18,normal,color)

				sign_count += 1
	var uploading:=Time.get_ticks_usec()
	mesh(pilot,lit,emission)
	mesh(pilot,storefronts,solid)
	record_work("facade_upload",uploading)
	if furniture!=null:
		await furniture.build(pilot,id)
	else:
		street_furniture()

func street_furniture() -> void:
	var body:=StaticBody3D.new();body.name="StreetFurnitureCollision"
	body.collision_layer=4;body.collision_mask=0
	body.set_meta("street_furniture",true)
	pilot.get_parent().add_child(body)
	var poles := geometry()
	var lights := geometry()
	var positions: Array[Vector2] = []
	var id: String = settings["sector"]
	var cell := Vector2(float(id.split("_")[0]),float(id.split("_")[1]))*256
	var area := Rect2(cell,Vector2(256,256))
	for road in nearby_roads:
		if str(road["osm_way_id"]) != str(settings["promenade_way_id"]):
			continue
		var a := Vector2(road["points_xz"][0][0],road["points_xz"][0][1])
		var b := Vector2(road["points_xz"][-1][0],road["points_xz"][-1][1])
		var direction := (b-a).normalized()
		var side := Vector2(direction.y,-direction.x)
		var half_width := float(road["width_m"])*0.5
		for index in range(maxi(1,ceili(a.distance_to(b)/24))):
			var center := a.lerp(b,(float(index)+0.5)/maxi(1,ceili(a.distance_to(b)/24)))
			var point := center+side*(half_width+1.4)
			if area.has_point(point) and positions.size()<int(settings["lamp_limit"]):
				positions.append(point)
		for index in range(maxi(1,ceili(a.distance_to(b)/2))):
			var center := a.lerp(b,(float(index)+0.5)/maxi(1,ceili(a.distance_to(b)/2)))
			if not area.has_point(center):
				continue
			for sign in [-1,1]:
				var point: Vector2 = center+side*(half_width-0.05)*sign
				var pos := Vector3(point.x,ground(point)+0.05,point.y)
				var along := Vector3(direction.x,0,direction.y)*1.05
				var across := Vector3(side.x,0,side.y)*0.16
				Builder.quad(lights,pos-along-across,pos+along-across,pos+along+across,pos-along+across,Vector3.UP,Color("3ceeff"))
	for p in positions:
		var y := ground(p)
		var foot := Vector3(p.x,y,p.y)
		add_fixture_capsule(body,foot+Vector3.UP*3,0.16,6,"lamp")
		for section in range(3):
			var level:=float(section)*2.66+1.33
			var at:=foot-Vector3(3,0,1)+Vector3(0.035*level*level,level*1.15,0)
			add_fixture_capsule(body,at,0.3,3.4,"palm")
		Builder.quad(poles,foot-Vector3.RIGHT*0.16,foot+Vector3.RIGHT*0.16,foot+Vector3.RIGHT*0.16+Vector3.UP*6,foot-Vector3.RIGHT*0.16+Vector3.UP*6,Vector3.FORWARD,Color("53708a"))
		var top := foot+Vector3.UP*6
		var elbow := top+Vector3(0.8,1.1,0)
		var end := elbow+Vector3(1.6,0,0)
		Builder.quad(poles,top,top+Vector3(0.16,0,0),elbow+Vector3(0.16,0,0),elbow,Vector3.FORWARD,Color("503054"))
		Builder.quad(poles,elbow,end,end+Vector3.UP*0.16,elbow+Vector3.UP*0.16,Vector3.FORWARD,Color("503054"))
		top=end
		Builder.quad(lights,top-Vector3(0.5,0,0.3),top+Vector3(0.5,0,-0.3),top+Vector3(0.5,0,0.3),top+Vector3(-0.5,0,0.3),Vector3.DOWN,Color("ff66e5"))
		var lamp := OmniLight3D.new()
		lamp.position = top
		lamp.light_color = Color("ff39cf")
		lamp.light_energy = 2.2
		lamp.omni_range = 24
		lamp.omni_attenuation = 1.3
		lamp.shadow_enabled = false
		lamp.visible = false
		pilot.add_child(lamp)
		lamps.append(lamp)
		# Original curved low-poly palm; no external texture or model.
		var trunk := foot-Vector3(3,0,1)
		for level in range(8):
			var low := trunk+Vector3(0.035*level*level,level*1.15,0)
			var high := trunk+Vector3(0.035*(level+1)*(level+1),(level+1)*1.15,0)
			var r := 0.22-level*0.012
			for face in range(6):
				var d := Vector3(cos(face*TAU/6),0,sin(face*TAU/6))*r
				var e := Vector3(cos((face+1)*TAU/6),0,sin((face+1)*TAU/6))*r
				Builder.quad(poles,low+d,low+e,high+e*0.92,high+d*0.92,d.normalized(),Color("503054"))
		var crown := trunk+Vector3(2.24,9.2,0)
		for leaf in range(10):
			var d := Vector3(cos(leaf*TAU/10),0,sin(leaf*TAU/10))
			var across := Vector3(-d.z,0,d.x)
			for part in range(8):
				var t := float(part)/8
				var u := float(part+1)/8
				var p0 := crown+d*t*4.4+Vector3.UP*(sin(t*PI)*0.9-t*t*2)
				var p1 := crown+d*u*4.4+Vector3.UP*(sin(u*PI)*0.9-u*u*2)
				var span := sin((t*0.8+0.1)*PI)*(1-t)*0.9
				for side in [-1,1]:
					Builder.triangle(poles,p0,p1,p0+across*span*side-d*0.45,Vector3.UP,Color("183e4b"))

	mesh(pilot,poles,solid)
	mesh(pilot,lights,emission)

func _process(delta: float) -> void:
	timer += delta
	if timer >= 0.25:
		timer = 0
		refresh()
		var nearby: bool = world.player.position.distance_to(Vector3(128,world.player.position.y,-128)) < 500
		var active: Array[Light3D] = []
		for lamp in lamps:
			if is_instance_valid(lamp):
				active.append(lamp)
		active.sort_custom(func(a: Light3D,b: Light3D): return a.global_position.distance_squared_to(world.player.position)<b.global_position.distance_squared_to(world.player.position))
		for index in range(active.size()):
			active[index].visible = index < 2 and nearby and world.city_manager.city_enabled
		if furniture!=null: furniture.update_lights()
		if audio != null and audio.ambience != null:
			audio.ambience.volume_db = -28 if nearby else -60

func add_fixture_capsule(body: StaticBody3D, at: Vector3, radius: float, height: float, kind: String) -> void:
	var shape:=CapsuleShape3D.new();shape.radius=radius;shape.height=height
	var collision:=CollisionShape3D.new();collision.shape=shape;collision.position=at
	collision.set_meta("fixture_kind",kind);body.add_child(collision)

func record_work(stage: String, started: int) -> void:
	var elapsed:=(Time.get_ticks_usec()-started)/1000.0
	if elapsed>4:
		work_log.append({"stage":stage,"ms":elapsed})
		if work_log.size()>32: work_log.pop_front()

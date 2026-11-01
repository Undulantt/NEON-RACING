extends Node3D

const Builder = preload("res://scripts/world/BuildingBuilder.gd")
var world: Node3D
var settings: Dictionary
var timer := 0.0
var decorated := 0
var window_count := 0
var sign_count := 0
var lamps: Array[Light3D] = []
var audio: CanvasLayer
var pilot: Node3D
var emission: StandardMaterial3D
var solid: StandardMaterial3D

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
	emission = material(Color.WHITE,true)
	solid = material(Color("687c98"))
	for node in world.get_children():
		if node is WorldEnvironment:
			var env: Environment = node.environment
			env.background_color = Color("070d24")
			env.ambient_light_color = Color("839ed8")
			env.ambient_light_energy = 0.28
			var sky := Sky.new()
			var sky_material := ProceduralSkyMaterial.new()
			sky_material.sky_top_color = Color("030718")
			sky_material.sky_horizon_color = Color("202746")
			sky_material.ground_bottom_color = Color("070b1a")
			sky_material.ground_horizon_color = Color("202746")
			sky.sky_material = sky_material
			env.sky = sky
			env.background_mode = Environment.BG_SKY
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
	var best := INF
	var chosen := 0
	for index in range(ring.size()):
		var a := Vector2(ring[index][0],ring[index][1])
		var b := Vector2(ring[(index+1)%ring.size()][0],ring[(index+1)%ring.size()][1])
		if a.distance_to(b) < 4:
			continue
		var midpoint := (a+b)*0.5
		for road in nearby_roads:
			var p := Vector2(road["points_xz"][0][0],road["points_xz"][0][1])
			var q := Vector2(road["points_xz"][-1][0],road["points_xz"][-1][1])
			var distance := midpoint.distance_to(Geometry2D.get_closest_point_to_segment(midpoint,p,q))
			if distance < best:
				best = distance
				chosen = index
	return chosen

var nearby_roads: Array = []
func ground(p: Vector2) -> float:
	return world.player.surface_height(p.x,p.y)

func refresh() -> void:
	var manager = world.city_manager
	var id: String = settings["sector"]
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
	lamps.clear()
	pilot = Node3D.new()
	pilot.name = "NightPilotDecor"
	chunk.add_child(pilot)
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(manager.data_root+str(entry["source"]["file"])))
	manager.apply_arcade_layout(data)
	var lit := geometry()
	var tint := material(Color("7284aa"))
	for visual in chunk.find_children("*","MeshInstance3D",true,false):
		visual.material_override = tint
	nearby_roads.clear()
	var cell := Vector2(float(id.split("_")[0]),float(id.split("_")[1]))*256
	var area := Rect2(cell,Vector2(256,256)).grow(40)
	for road in world.map_data["roads"]:
		var p := Vector2(road["points_xz"][0][0],road["points_xz"][0][1])
		if area.has_point(p):
			nearby_roads.append(road)
	for b in data["buildings"]:
		if b.get("disabled",false):
			continue
		var ring: Array = b["footprint_xz"]
		var edges: Array[int] = [int(b.get("facade_edge_index",facade_edge(ring)))]
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
			for floor_index in range(mini(3,maxi(1,floori(height/3)))):
				for i in range(count):
					if (i+floor_index+int(b["palette_index"]))%3 == 0:
						continue
					var p := Vector3(a.x,base+1.1+floor_index*3,a.y)+tangent*(1.0+i*length/maxi(count,1))+normal*0.065
					var color := Color("ffc27a") if not commercial or i%2 == 0 else Color("70dbe7")
					Builder.quad(lit,p,p+tangent*1.1,p+tangent*1.1+Vector3.UP,p+Vector3.UP,normal,color)
					window_count += 1
			if commercial and length > 5 and sign_count < 8:
				var p := Vector3(a.x,base+minf(3,height-0.4),a.y)+tangent*0.6+normal*0.085
				var color := Color("f65eac") if sign_count%2 == 0 else Color("3bdcfa")
				Builder.quad(lit,p,p+tangent*minf(7,length-1.2),p+tangent*minf(7,length-1.2)+Vector3.UP*0.18,p+Vector3.UP*0.18,normal,color)
				if sign_count < 3:
					var label := Label3D.new()
					label.text = ["BAHÍA  ·  24H","CAFÉ / LA PAZ","NOCHE AZUL"][sign_count]
					label.font_size = 48
					label.pixel_size = 0.025
					label.modulate = color
					label.no_depth_test = false
					label.position = p+tangent*3.0+Vector3.UP*0.8+normal*0.02
					pilot.add_child(label)
					label.look_at(label.global_position+normal)
					label.visibility_range_end = 160
				sign_count += 1
	mesh(pilot,lit,emission)
	street_furniture()

func street_furniture() -> void:
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
		for index in range(maxi(1,ceili(a.distance_to(b)/30))):
			var center := a.lerp(b,(float(index)+0.5)/maxi(1,ceili(a.distance_to(b)/30)))
			var point := center+side*(half_width+1.4)
			if area.has_point(point) and positions.size()<int(settings["lamp_limit"]):
				positions.append(point)
		for index in range(maxi(1,ceili(a.distance_to(b)/8))):
			var center := a.lerp(b,(float(index)+0.5)/maxi(1,ceili(a.distance_to(b)/8)))
			if not area.has_point(center):
				continue
			for sign in [-1,1]:
				var point: Vector2 = center+side*(half_width-0.2)*sign
				var pos := Vector3(point.x,ground(point)+0.05,point.y)
				var along := Vector3(direction.x,0,direction.y)*0.7
				var across := Vector3(side.x,0,side.y)*0.09
				Builder.quad(lights,pos-along-across,pos+along-across,pos+along+across,pos-along+across,Vector3.UP,Color("63b6c2"))
	for p in positions:
		var y := ground(p)
		var foot := Vector3(p.x,y,p.y)
		Builder.quad(poles,foot-Vector3.RIGHT*0.09,foot+Vector3.RIGHT*0.09,foot+Vector3.RIGHT*0.09+Vector3.UP*6,foot-Vector3.RIGHT*0.09+Vector3.UP*6,Vector3.FORWARD,Color("53708a"))
		var top := foot+Vector3.UP*6
		Builder.quad(lights,top-Vector3(0.5,0,0.3),top+Vector3(0.5,0,-0.3),top+Vector3(0.5,0,0.3),top+Vector3(-0.5,0,0.3),Vector3.DOWN,Color("ffe0a3"))
		var lamp := OmniLight3D.new()
		lamp.position = top
		lamp.light_color = Color("ffc888")
		lamp.light_energy = 1.4
		lamp.omni_range = 24
		lamp.omni_attenuation = 1.3
		lamp.shadow_enabled = false
		lamp.visible = false
		pilot.add_child(lamp)
		lamps.append(lamp)
		# Stylized promenade palms, explicitly decorative rather than surveyed trees.
		var trunk := foot-Vector3(3,0,1)
		Builder.quad(poles,trunk-Vector3.RIGHT*0.2,trunk+Vector3.RIGHT*0.2,trunk+Vector3(0.2,7,0),trunk+Vector3(-0.2,7,0),Vector3.FORWARD,Color("846854"))
		for leaf in range(6):
			var d := Vector3(cos(leaf*TAU/6),0,sin(leaf*TAU/6))
			var side := Vector3(-d.z,0,d.x)*0.6
			Builder.triangle(poles,trunk+Vector3.UP*7+side,trunk+Vector3.UP*7-side,trunk+Vector3.UP*5.7+d*3.3,Vector3.UP,Color("307b78"))
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
		if audio != null and audio.ambience != null:
			audio.ambience.volume_db = -28 if nearby else -60

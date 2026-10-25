extends RefCounted

const PALETTE := [Color("dfc8a7"), Color("e6d9bd"), Color("cb866b"), Color("a9c1bf"), Color("e5cd8b"), Color("f0e4d2")]

static func triangle(out: Dictionary, a: Vector3, b: Vector3, c: Vector3, normal: Vector3, color: Color) -> void:
	if (b - a).cross(c - a).dot(normal) > 0:
		var temp := b
		b = c
		c = temp
	out["vertices"].append_array(PackedVector3Array([a, b, c]))
	out["normals"].append_array(PackedVector3Array([normal, normal, normal]))
	out["colors"].append_array(PackedColorArray([color, color, color]))

static func quad(out: Dictionary, a: Vector3, b: Vector3, c: Vector3, d: Vector3, normal: Vector3, color: Color) -> void:
	triangle(out, a, b, c, normal, color)
	triangle(out, a, c, d, normal, color)

static func build(parent: Node3D, data: Dictionary) -> Dictionary:
	var groups := {}
	for building in data["buildings"]:
		if building.get("disabled", false):
			continue
		var ring: Array = building["footprint_xz"]
		var center := Vector2.ZERO
		for p in ring:
			center += Vector2(p[0], p[1])
		center /= ring.size()
		var cell := Vector2i(floori(center.x / 256), floori(center.y / 256))
		if data.has("chunk_cell"):
			cell = Vector2i(data["chunk_cell"][0], data["chunk_cell"][1])
		if not groups.has(cell):
			groups[cell] = {"vertices": PackedVector3Array(), "normals": PackedVector3Array(), "colors": PackedColorArray(), "physics": PackedVector3Array()}
		var output: Dictionary = groups[cell]
		var origin := Vector3(cell.x * 256, 0, cell.y * 256)
		var height: float = building["height_m"]
		var color: Color = PALETTE[int(building["palette_index"]) % PALETTE.size()]
		var category: String = building.get("category", "unknown")
		var category_colors := {"commercial": Color("e0c89c"), "restaurant": Color("dba480"), "hotel": Color("d6e4df"), "institutional": Color("c5cfda"), "cultural": Color("d9b877"), "industrial": Color("a5aaa9"), "residential": Color("ead7bb")}
		if category_colors.has(category):
			color = color.lerp(category_colors[category], 0.65)
		var begin: int = output["vertices"].size()
		for tri in building["roof_triangles_xz"]:
			triangle(output, Vector3(tri[0][0], height, tri[0][1]) - origin, Vector3(tri[1][0], height, tri[1][1]) - origin, Vector3(tri[2][0], height, tri[2][1]) - origin, Vector3.UP, color.darkened(0.12))
		var wall_rings: Array = [ring]
		wall_rings.append_array(building.get("holes_xz", []))
		for wall_ring in wall_rings:
			for i in range(wall_ring.size()):
				var p: Array = wall_ring[i]
				var q: Array = wall_ring[(i + 1) % wall_ring.size()]
				var a := Vector3(p[0], -0.1, p[1]) - origin
				var b := Vector3(q[0], -0.1, q[1]) - origin
				var direction := (b - a).normalized()
				var normal := Vector3(direction.z, 0, -direction.x)
				quad(output, a, b, b + Vector3.UP * (height + 0.1), a + Vector3.UP * (height + 0.1), normal, color)
		# Static collision includes walls/roofs, never the cosmetic windows.
		if building.get("collision_enabled", true):
			output["physics"].append_array(output["vertices"].slice(begin))
		if building.has("model_path"):
			var resource = load(str(building["model_path"]))
			if resource is PackedScene:
				var custom = resource.instantiate()
				if custom is Node3D and not custom is CollisionObject3D and custom.find_children("*", "CollisionObject3D", true, false).is_empty():
					parent.add_child(custom)
					custom.position = Vector3(center.x, 0, center.y)
					custom.rotation_degrees.y = float(building.get("model_rotation_degrees", 0))
					custom.scale = Vector3.ONE * float(building.get("model_scale", 1))
					# Retain the validated geographic collision shell.
					for key in ["vertices", "normals", "colors"]:
						output[key].resize(begin)
					continue
				custom.free()
			push_warning("Invalid custom building scene; keeping procedural fallback")
		# Cosmetics share the sector mesh and never enter the physics mesh.
		# One facade per classified building keeps geometry growth bounded.
		if data.get("category_facades", false) and category != "unknown":
			var longest := 0.0
			var edge := 0
			for i in range(ring.size()):
				var length := Vector2(ring[i][0], ring[i][1]).distance_to(Vector2(ring[(i + 1) % ring.size()][0], ring[(i + 1) % ring.size()][1]))
				if length > longest:
					longest = length
					edge = i
			if longest > 3.0:
				var p: Array = ring[edge]
				var q: Array = ring[(edge + 1) % ring.size()]
				var a := Vector3(p[0], 0, p[1]) - origin
				var b := Vector3(q[0], 0, q[1]) - origin
				var direction := (b - a).normalized()
				var normal := Vector3(direction.z, 0, -direction.x)
				var start := a + direction * 0.6 + normal * 0.02
				var finish := b - direction * 0.6 + normal * 0.02
				var top := minf(height - 0.4, 2.7)
				var glass := Color("345a67")
				if category == "industrial":
					glass = Color("727b7d")
				if category == "residential":
					finish = start + direction * minf(1.4, longest - 1.2)
				quad(output, start + Vector3.UP * 0.2, finish + Vector3.UP * 0.2, finish + Vector3.UP * top, start + Vector3.UP * top, normal, glass)
				if category in ["commercial", "restaurant", "hotel", "cultural", "institutional"]:
					var accent := Color("a45337") if category == "restaurant" else color.darkened(0.28)
					quad(output, start + Vector3.UP * top, finish + Vector3.UP * top, finish + Vector3.UP * (top + 0.25), start + Vector3.UP * (top + 0.25), normal, accent)
		if not data.get("detail_windows", true):
			continue
		for i in range(ring.size()):
			var p: Array = ring[i]
			var q: Array = ring[(i + 1) % ring.size()]
			var a := Vector3(p[0], 0, p[1]) - origin
			var b := Vector3(q[0], 0, q[1]) - origin
			var direction := (b - a).normalized()
			var normal := Vector3(direction.z, 0, -direction.x)
			var length := a.distance_to(b)
			for floor_index in range(maxi(1, floori(height / 3.1))):
				for window_index in range(maxi(0, floori(length / 4.0))):
					var p0 := a + direction * (2.0 + window_index * 4.0) + Vector3.UP * (1.2 + floor_index * 3.1) + normal * 0.025
					quad(output, p0 - direction * 0.6, p0 + direction * 0.6, p0 + direction * 0.6 + Vector3.UP * 1.0, p0 - direction * 0.6 + Vector3.UP * 1.0, normal, Color("304e5b"))
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 0.9
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var triangle_count := 0
	for cell in groups:
		var group: Dictionary = groups[cell]
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = group["vertices"]
		arrays[Mesh.ARRAY_NORMAL] = group["normals"]
		arrays[Mesh.ARRAY_COLOR] = group["colors"]
		var mesh := ArrayMesh.new()
		if not group["vertices"].is_empty():
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			mesh.surface_set_material(0, material)
		var body := StaticBody3D.new()
		body.name = "Buildings_%d_%d" % [cell.x, cell.y]
		body.position = Vector3(cell.x * 256, 0, cell.y * 256)
		body.collision_layer = 4
		body.collision_mask = 0
		var visual := MeshInstance3D.new()
		visual.mesh = mesh
		body.add_child(visual)
		if not group["physics"].is_empty():
			var collider := CollisionShape3D.new()
			var shape := ConcavePolygonShape3D.new()
			shape.set_faces(group["physics"])
			shape.backface_collision = true
			collider.shape = shape
			body.add_child(collider)
		parent.add_child(body)
		triangle_count += group["vertices"].size() / 3
	return {"buildings": data["buildings"].size(), "building_chunks": groups.size(), "building_triangles": triangle_count}

static func solid_box(parent: Node3D, at: Vector3, size: Vector3, color: Color, layer: int, title: String) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = title
	body.position = at
	body.collision_layer = layer
	body.collision_mask = 0
	var visual := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	visual.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 1
	visual.material_override = material
	body.add_child(visual)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	parent.add_child(body)
	return body

static func build_limits(parent: Node3D, bounds: Array) -> void:
	var x0: float = bounds[0]
	var z0: float = bounds[1]
	var x1: float = bounds[2]
	var z1: float = bounds[3]
	solid_box(parent, Vector3((x0 + x1) / 2, -0.33, (z0 + z1) / 2), Vector3(x1 - x0, 0.5, z1 - z0), Color("b4a386"), 2, "NeutralSafetyPlatform")
	var color := Color("d88a50")
	solid_box(parent, Vector3(x0, 1.4, (z0 + z1) / 2), Vector3(2, 3, z1 - z0 + 2), color, 8, "WestLimit")
	solid_box(parent, Vector3(x1, 1.4, (z0 + z1) / 2), Vector3(2, 3, z1 - z0 + 2), color, 8, "EastLimit")
	solid_box(parent, Vector3((x0 + x1) / 2, 1.4, z0), Vector3(x1 - x0, 3, 2), color, 8, "NorthLimit")
	solid_box(parent, Vector3((x0 + x1) / 2, 1.4, z1), Vector3(x1 - x0, 3, 2), color, 8, "SouthLimit")

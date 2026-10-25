extends SceneTree

const World = preload("res://scripts/world/PhaseAWorld.gd")
var world: Node3D
var body: CharacterBody3D
var route := PackedVector3Array()
var distances := PackedFloat64Array()
var progress := 0.0
var frame := 0
var failures: Array[String] = []
var rays := 0
var junctions := 0
var ray_edge_points: Array[Vector3] = []
var edge_probes: Array[CharacterBody3D] = []
var route_junctions := 0
var minimum_y := 100.0
var maximum_y := -100.0

func _initialize() -> void:
	world = Node3D.new()
	world.set_script(World)
	root.add_child.call_deferred(world)

func fail(message: String) -> void:
	if failures.size() < 20:
		failures.append(message)

func sample_surface(p: Vector3, context: String) -> void:
	var query := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 2, p - Vector3.UP * 2, 1)
	var hit := world.get_world_3d().direct_space_state.intersect_ray(query)
	rays += 1
	if hit.is_empty():
		# A zero-width ray can miss a shared triangle edge in float32 Jolt.
		# Keep every miss and independently drop a physical body there.
		ray_edge_points.append(p)
		print("RAY_EDGE_CHECK ", context, " ", p)
	elif absf(hit.position.y) > 0.002:
		fail("Nonflat road: %s" % context)

func setup_probe() -> void:
	if world.map_data.is_empty():
		fail("Map did not load")
		finish()
		return
	var incidence := {}
	for road in world.map_data["roads"]:
		var p := Vector3(road["points_xz"][0][0], 0, road["points_xz"][0][1])
		var q := Vector3(road["points_xz"][-1][0], 0, road["points_xz"][-1][1])
		var side := (q - p).normalized().cross(Vector3.UP) * float(road["width_m"]) * 0.4
		var steps := maxi(1, ceili(p.distance_to(q) / 8.0))
		for i in range(steps + 1):
			var center := p.lerp(q, float(i) / steps)
			sample_surface(center, road["id"])
			sample_surface(center + side, road["id"] + " left")
			sample_surface(center - side, road["id"] + " right")
		for id in [road["from"], road["to"]]:
			incidence[id] = incidence.get(id, 0) + 1
	for node in world.map_data["nodes"]:
		if incidence.get(node["id"], 0) >= 3:
			junctions += 1
			sample_surface(Vector3(node["x"], 0, node["z"]), "junction " + node["id"])
	for id in world.map_data["verification_route"]["road_node_sequence"]:
		if incidence.get(id, 0) >= 3:
			route_junctions += 1
	if route_junctions < 5:
		fail("Route crosses fewer than five junctions")
	for p in world.map_data["verification_route"]["points_xz"]:
		route.append(Vector3(p[0], 0, p[1]))
	distances.append(0)
	for i in range(1, route.size()):
		distances.append(distances[-1] + route[i].distance_to(route[i - 1]))
	for p in ray_edge_points:
		var probe := CharacterBody3D.new()
		probe.collision_layer = 2
		probe.collision_mask = 1
		var collider := CollisionShape3D.new()
		var ball := SphereShape3D.new()
		ball.radius = 0.45
		collider.shape = ball
		probe.add_child(collider)
		world.add_child(probe)
		probe.position = p + Vector3.UP * 0.6
		edge_probes.append(probe)
	body = CharacterBody3D.new()
	body.collision_layer = 2
	body.collision_mask = 1
	body.floor_snap_length = 0.25
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.45
	shape.shape = sphere
	body.add_child(shape)
	world.add_child(body)
	body.position = route[0] + Vector3.UP * 0.46

func point_at(at: float) -> Vector3:
	var i := clampi(distances.bsearch(at) - 1, 0, route.size() - 2)
	return route[i].lerp(route[i + 1], clampf((at - distances[i]) / (distances[i + 1] - distances[i]), 0, 1))

func _physics_process(delta: float) -> bool:
	frame += 1
	if frame == 4:
		setup_probe()
	if frame < 5 or body == null:
		return false
	for probe in edge_probes:
		probe.velocity = Vector3(0, -9.8, 0)
		probe.move_and_slide()
		if frame > 20 and (not probe.is_on_floor() or absf(probe.position.y - 0.451) > 0.07):
			fail("Physical hole at ray edge %s" % probe.position)
	if frame > 20:
		progress = minf(progress + 30.0 * delta, distances[-1])
	var target := point_at(progress)
	body.velocity = Vector3((target.x - body.position.x) / delta, -9.8, (target.z - body.position.z) / delta)
	body.move_and_slide()
	minimum_y = minf(minimum_y, body.position.y)
	maximum_y = maxf(maximum_y, body.position.y)
	if frame > 20 and (not body.is_on_floor() or absf(body.position.y - 0.451) > 0.07):
		fail("Probe lost floor at %.2f m y=%.4f" % [progress, body.position.y])
	if body.position.y < -2 or frame > 20000 or progress >= distances[-1]:
		finish()
	return false

func finish() -> void:
	var report := {"passed": failures.is_empty(), "ray_samples": rays, "junctions": junctions, "route_junctions": route_junctions, "ray_edge_misses": ray_edge_points.size(), "independent_drop_probes": edge_probes.size(), "route_m": progress, "probe_min_y": minimum_y, "probe_max_y": maximum_y, "physics_frames": frame, "failures": failures, "mesh": world.stats}
	print("PHASE_A_REPORT ", JSON.stringify(report))
	var file := FileAccess.open("res://docs/godot_validation.json", FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(report, "  "))
	quit(0 if failures.is_empty() else 1)

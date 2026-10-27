extends SceneTree

var world: Node3D
var car: CharacterBody3D
var failures: Array[String] = []
var cases: Array = []

func _initialize() -> void:
	run.call_deferred()

func check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
		push_error(message)

func step(frames: int, throttle: float = 0) -> void:
	car.set_controls(throttle, 0)
	for i in range(frames):
		await physics_frame

func pose(point: Vector3, direction: Vector3) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, atan2(-direction.x, -direction.z)), point)

func run() -> void:
	world = preload("res://scenes/FlatWorld.tscn").instantiate()
	root.add_child(world)
	await physics_frame
	await physics_frame
	car = world.player
	car.external_control = true
	var ground: StaticBody3D = world.building_root.get_node_or_null("ClippedSafetyPlatform")
	if ground == null:
		ground = world.building_root.get_node_or_null("NeutralSafetyPlatform")
	check(ground != null, "Safety ground is required")
	if ground == null:
		quit(1)
		return
	var visible_ground := false
	var collider: CollisionShape3D
	for child in ground.get_children():
		if child is MeshInstance3D:
			visible_ground = visible_ground or child.visible
		elif child is CollisionShape3D:
			collider = child
	check(visible_ground, "Continuous fallback ground must stay visible")
	check(collider != null, "Safety ground must have collision")
	if collider == null:
		quit(1)
		return
	if collider.shape is BoxShape3D:
		check(absf(ground.position.y + collider.shape.size.y * 0.5) < 0.001, "Safety collision must be flush with asphalt")
	elif collider.shape is ConcavePolygonShape3D:
		for point in collider.shape.get_faces():
			check(absf(ground.position.y + point.y) < 0.001, "Clipped safety collision must be flush with asphalt")
	else:
		check(false, "Unsupported safety collider")
	var playable := PackedVector2Array()
	for p in world.environment_data.get("playable_boundary_xz", []):
		playable.append(Vector2(p[0],p[1]))
	var candidates: Array = world.map_data["roads"].duplicate()
	candidates.sort_custom(func(a: Dictionary, b: Dictionary): return segment_length(a) > segment_length(b))
	for road in candidates:
		if cases.size() >= 6:
			break
		var a := Vector3(road["points_xz"][0][0], 0.67, road["points_xz"][0][1])
		var b := Vector3(road["points_xz"][-1][0], 0.67, road["points_xz"][-1][1])
		if a.distance_to(b) < 50:
			continue
		var center := a.lerp(b, 0.5)
		var tangent := (b - a).normalized()
		for sign_value in [-1.0, 1.0]:
			if cases.size() >= 6:
				break
			var side: Vector3 = tangent.cross(Vector3.UP) * sign_value
			var width: float = road["width_m"]
			car.global_transform = pose(center, side)
			car.velocity = Vector3.ZERO
			car.steering = 0
			await step(30)
			var end: Vector3 = center + side * (width * 0.5 + 6.0)
			if not playable.is_empty() and not Geometry2D.is_point_in_polygon(Vector2(end.x + side.x * 10, end.z + side.z * 10), playable):
				continue
			if car.road_hit(end) or not car.road_hit(center):
				continue
			var clear := true
			for i in range(31):
				var point := center.lerp(end, float(i) / 30.0)
				if not car.clear_of_obstacles(pose(point, side)) or not car.world_bounds.grow(-4).has_point(Vector2(point.x, point.z)):
					clear = false
					break
			if not clear:
				continue
			var recoveries: int = car.recovery_count
			var contacts: int = car.wall_contacts
			var min_y := car.position.y
			var max_y := car.position.y
			var frames := 0
			while (car.position - center).dot(side) < width * 0.5 + 5 and frames < 240:
				await step(1, 1)
				min_y = minf(min_y, car.position.y)
				max_y = maxf(max_y, car.position.y)
				frames += 1
			check(not car.on_asphalt and frames < 240, "Car must exit road freely: " + road["id"])
			# Turn around in the clear shoulder; do not teleport back onto asphalt.
			car.rotation.y += PI
			car.velocity = Vector3.ZERO
			frames = 0
			while (car.position - center).dot(side) > 0 and frames < 240:
				await step(1, 1)
				min_y = minf(min_y, car.position.y)
				max_y = maxf(max_y, car.position.y)
				frames += 1
			check(frames < 240 and car.on_asphalt, "Car must reenter asphalt under its own power: " + road["id"])
			check(car.wall_contacts == contacts and car.recovery_count == recoveries, "Edge crossing must not hit walls or recover")
			check(max_y - min_y < 0.025 and car.is_on_floor(), "Road/ground transition must stay supported and level")
			cases.append({"road": road["id"], "side": sign_value, "width_m": width, "source_width_m": road["source_width_m"], "height_range_m": max_y - min_y, "return_frames": frames})
	check(cases.size() == 6, "Need six actual clear road exit/reentry cases")
	var report := {"passed": failures.is_empty(), "failures": failures, "cases": cases, "layout": world.arcade_layout["statistics"]}
	var output := FileAccess.open("res://docs/road_edges_validation.json", FileAccess.WRITE)
	output.store_string(JSON.stringify(report, "  "))
	print("ROAD_EDGES_REPORT ", JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)

func segment_length(road: Dictionary) -> float:
	var a := Vector2(road["points_xz"][0][0], road["points_xz"][0][1])
	var b := Vector2(road["points_xz"][-1][0], road["points_xz"][-1][1])
	return a.distance_squared_to(b)

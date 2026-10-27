extends Node3D

const Builder = preload("res://scripts/world/RoadBuilder.gd")
const LOAD_RADIUS := 1100.0
const UNLOAD_RADIUS := 1400.0
const PRIME_RADIUS := 300.0
var target: CharacterBody3D
var entries: Dictionary = {}
var loaded: Dictionary = {}
var pending: Array = []
var anchor := Vector3.ZERO
var previous_anchor := Vector3.ZERO
var timer := 0.0
var max_loaded := 0
var total_loads := 0
var total_unloads := 0
var max_build_ms := 0
var surface_layer := 1
var failed_chunks: Array[String] = []

func configure(data: Dictionary, initial_position: Vector3) -> Dictionary:
	process_physics_priority = -100
	anchor = initial_position
	var triangles := 0
	for entry in data["chunks"]:
		var origin: Array = entry["origin_xz"]
		entries[Vector2i(roundi(float(origin[0]) / 256), roundi(float(origin[1]) / 256))] = entry
		triangles += int(entry.get("triangles_count", entry.get("triangles_xz", []).size()))
	refresh(true)
	return {"chunks": entries.size(), "triangles": triangles}

func distance_to(entry: Dictionary) -> float:
	var origin: Array = entry["origin_xz"]
	var rect := Rect2(float(origin[0]), float(origin[1]), 256, 256)
	var point := Vector2(anchor.x, anchor.z)
	return point.distance_to(point.clamp(rect.position, rect.end))

func refresh(prime: bool = false) -> void:
	previous_anchor = anchor
	pending.clear()
	for cell in loaded.keys():
		if distance_to(entries[cell]) > UNLOAD_RADIUS and not recovery_cell(cell):
			loaded[cell].queue_free()
			loaded.erase(cell)
			total_unloads += 1
	var center := Vector2i(floori(anchor.x / 256), floori(anchor.z / 256))
	var extent := ceili(LOAD_RADIUS / 256) + 1
	for x in range(center.x - extent, center.x + extent + 1):
		for z in range(center.y - extent, center.y + extent + 1):
			var cell := Vector2i(x, z)
			if not entries.has(cell) or loaded.has(cell):
				continue
			var distance := distance_to(entries[cell])
			if distance <= LOAD_RADIUS:
				pending.append({"cell": cell, "distance": distance})
	pending.sort_custom(func(a: Dictionary, b: Dictionary): return a["distance"] < b["distance"])
	if prime:
		var immediate: Array = pending.duplicate()
		for entry in immediate:
			if float(entry["distance"]) <= PRIME_RADIUS:
				load_chunk(entry["cell"])

func recovery_cell(cell: Vector2i) -> bool:
	if target == null:
		return false
	var rect := Rect2(Vector2(cell) * 256.0, Vector2(256, 256))
	for at in [target.spawn_transform.origin, target.safe_transform.origin]:
		var point := Vector2(at.x, at.z)
		if point.distance_to(point.clamp(rect.position, rect.end)) <= PRIME_RADIUS:
			return true
	return false

func ensure_recovery_support() -> void:
	if target == null:
		return
	# Recovery performs immediate raycasts. Keep only these two small collision
	# neighbourhoods resident even when their roads are far from the camera.
	for at in [target.spawn_transform.origin, target.safe_transform.origin]:
		var center := Vector2i(floori(at.x / 256), floori(at.z / 256))
		for x in range(center.x - 2, center.x + 3):
			for z in range(center.y - 2, center.y + 3):
				var cell := Vector2i(x, z)
				if entries.has(cell) and not loaded.has(cell) and recovery_cell(cell):
					load_chunk(cell)

func load_chunk(cell: Vector2i) -> void:
	if loaded.has(cell) or str(entries[cell]["id"]) in failed_chunks:
		return
	var node := Node3D.new()
	add_child(node)
	var start := Time.get_ticks_msec()
	var result := Builder.build(node, {"chunks": [entries[cell]], "layer": surface_layer})
	if result.has("error"):
		failed_chunks.append(str(entries[cell]["id"]))
		if target != null:
			target.driving_enabled = false
			target.velocity = Vector3.ZERO
		node.queue_free()
		return
	max_build_ms = maxi(max_build_ms, Time.get_ticks_msec() - start)
	loaded[cell] = node
	max_loaded = maxi(max_loaded, loaded.size())
	total_loads += 1

func _physics_process(delta: float) -> void:
	if target != null:
		anchor = target.global_position
	timer += delta
	if timer >= 0.12 or anchor.distance_squared_to(previous_anchor) > 4096:
		timer = 0
		refresh(true)
		ensure_recovery_support()
	for i in range(mini(2, pending.size())):
		load_chunk(pending.pop_front()["cell"])

func status() -> Dictionary:
	return {"loaded_chunks": loaded.size(), "total_chunks": entries.size(), "max_loaded_chunks": max_loaded, "chunk_loads": total_loads, "chunk_unloads": total_unloads, "max_chunk_build_ms": max_build_ms, "failed_chunks": failed_chunks}

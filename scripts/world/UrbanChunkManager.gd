extends Node3D

const Builder = preload("res://scripts/world/BuildingBuilder.gd")
const DATA_ROOT := "res://data/processed/urban/"
var manifest: Dictionary = {}
var baseline_b6 := false
var target: CharacterBody3D
var loaded: Dictionary = {}
var pending: Array = []
var city_enabled := true
var refresh_timer := 0.0
var max_loaded_chunks := 0
var max_chunk_build_ms := 0
var loaded_buildings := 0
var total_chunk_loads := 0
var total_chunk_unloads := 0
var failed_chunks: Array[String] = []

func configure(data: Dictionary, player: CharacterBody3D) -> void:
	manifest = data
	target = player
	process_physics_priority = -50
	# Prime only the immediate collision neighbourhood before driving starts.
	refresh(true)
	var nearby: Array = pending.duplicate()
	for entry in nearby:
		if float(entry["distance"]) <= 220.0:
			load_chunk(entry["chunk"])
	refresh(false)

func rectangle(entry: Dictionary) -> Rect2:
	var b: Array = entry["bounds_xz"]
	return Rect2(b[0], b[1], b[2] - b[0], b[3] - b[1])

func distance_to(entry: Dictionary) -> float:
	var r := rectangle(entry)
	var p := Vector2(target.global_position.x, target.global_position.z)
	var nearest := p.clamp(r.position, r.end)
	return p.distance_to(nearest)

func refresh(_prime: bool = false) -> void:
	pending.clear()
	var settings: Dictionary = manifest["settings"]
	for chunk in manifest["chunks"]:
		var id: String = chunk["id"]
		var distance := distance_to(chunk)
		if loaded.has(id):
			if distance > float(settings["visual_unload_radius_m"]):
				var item: Dictionary = loaded[id]
				item["node"].queue_free()
				loaded_buildings -= int(item["count"])
				loaded.erase(id)
				total_chunk_unloads += 1
			else:
				set_collisions(loaded[id]["node"], city_enabled and distance <= float(settings["collision_radius_m"]))
		elif distance <= float(settings["visual_load_radius_m"]) and not id in failed_chunks:
			pending.append({"distance": distance, "chunk": chunk})
	pending.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["distance"] < b["distance"])

func set_collisions(node: Node3D, active: bool) -> void:
	for body in node.get_children():
		if body is StaticBody3D:
			body.collision_layer = 4 if active else 0

func load_chunk(entry: Dictionary) -> void:
	var id: String = entry["id"]
	if loaded.has(id):
		return
	var path := DATA_ROOT + str(entry["file"])
	var bytes := FileAccess.get_file_as_bytes(path)
	var hasher := HashingContext.new()
	hasher.start(HashingContext.HASH_SHA256)
	hasher.update(bytes)
	if hasher.finish().hex_encode() != entry["sha256"]:
		push_error("Urban chunk hash mismatch: " + path)
		failed_chunks.append(id)
		return
	var data = JSON.parse_string(bytes.get_string_from_utf8())
	if not data is Dictionary or data.get("schema_version") != 1:
		push_error("Invalid urban chunk schema: " + path)
		failed_chunks.append(id)
		return
	if baseline_b6:
		data["category_facades"] = false
		for building in data["buildings"]:
			building.erase("category")
			building.erase("model_path")
			if building.has("automatic_height_m"):
				building["height_m"] = building["automatic_height_m"]
	var start := Time.get_ticks_msec()
	var node := Node3D.new()
	node.name = "Urban_" + id
	add_child(node)
	var info: Dictionary = Builder.build(node, data)
	node.visible = city_enabled
	set_collisions(node, city_enabled and distance_to(entry) <= float(manifest["settings"]["collision_radius_m"]))
	loaded[id] = {"node": node, "count": int(entry["building_count"]), "info": info}
	loaded_buildings += int(entry["building_count"])
	total_chunk_loads += 1
	max_loaded_chunks = maxi(max_loaded_chunks, loaded.size())
	max_chunk_build_ms = maxi(max_chunk_build_ms, Time.get_ticks_msec() - start)

func set_city_enabled(active: bool) -> bool:
	# Re-enabling hidden collision is allowed only on fully supported road, whose
	# clearance was verified offline, so a facade cannot materialize inside a car.
	if active and not target.safe_road_transform(target.global_transform):
		return false
	city_enabled = active
	for id in loaded:
		var entry: Dictionary = loaded[id]
		entry["node"].visible = active
		set_collisions(entry["node"], false)
	if active:
		refresh()
	return true

func status() -> Dictionary:
	return {"enabled": city_enabled, "loaded_chunks": loaded.size(), "loaded_buildings": loaded_buildings, "max_loaded_chunks": max_loaded_chunks, "max_chunk_build_ms": max_chunk_build_ms, "chunk_loads": total_chunk_loads, "chunk_unloads": total_chunk_unloads, "failed_chunks": failed_chunks}

func fixture_buildings() -> Array:
	# Test-only inspection of currently streamed data, not a global runtime load.
	for chunk in manifest["chunks"]:
		if loaded.has(chunk["id"]) and distance_to(chunk) < 160:
			var data = JSON.parse_string(FileAccess.get_file_as_string(DATA_ROOT + str(chunk["file"])))
			var result: Array = []
			for building in data["buildings"]:
				if building.get("collision_enabled", false):
					var center := Vector2.ZERO
					for p in building["footprint_xz"]:
						center += Vector2(p[0], p[1])
					center /= building["footprint_xz"].size()
					if center.distance_to(Vector2(target.position.x, target.position.z)) < 140:
						result.append(building)
			if not result.is_empty():
				return result
	return []

func _physics_process(delta: float) -> void:
	if target == null or manifest.is_empty() or not city_enabled:
		return
	refresh_timer += delta
	if refresh_timer >= 0.12:
		refresh_timer = 0
		refresh()
	for i in range(mini(int(manifest["settings"]["max_chunks_per_frame"]), pending.size())):
		var entry: Dictionary = pending.pop_front()
		load_chunk(entry["chunk"])

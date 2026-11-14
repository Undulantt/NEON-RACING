extends Node3D

const Builder = preload("res://scripts/world/BuildingBuilder.gd")
const DATA_ROOT := "res://data/processed/urban/"
var data_root := DATA_ROOT
var flatten_elevation := false
var manifest: Dictionary = {}
var spatial_index: Dictionary = {}
var last_refresh_position := Vector3.ZERO
var baseline_b6 := false
var night_visuals := false
var building_overrides: Dictionary = {}
var chunk_overrides: Dictionary = {}
var defer_prime := false
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
var facades_enabled := false
var recovery_chunks: Dictionary = {}
var recovery_buildings := 0

func configure(data: Dictionary, player: CharacterBody3D) -> void:
	manifest = data.duplicate(true)
	target = player
	configure_city_life()
	spatial_index.clear()
	for entry in manifest["chunks"]:
		var bounds: Array = entry["bounds_xz"]
		for x in range(floori(float(bounds[0]) / 256), floori(float(bounds[2]) / 256) + 1):
			for z in range(floori(float(bounds[1]) / 256), floori(float(bounds[3]) / 256) + 1):
				var cell := Vector2i(x, z)
				if not spatial_index.has(cell):
					spatial_index[cell] = []
				spatial_index[cell].append(entry)
	process_physics_priority = -50
	# Prime only the immediate collision neighbourhood before driving starts.
	refresh(true)
	var nearby: Array = pending.duplicate()
	for entry in nearby:
		if not defer_prime and float(entry["distance"]) <= 220.0:
			load_chunk(entry["chunk"])
	refresh(false)
	if defer_prime: set_physics_process(false)

func configure_city_life() -> void:
	recovery_chunks.clear()
	recovery_buildings = 0
	facades_enabled = false
	var config_path := "res://config/sf3_city_life.json"
	if not FileAccess.file_exists(config_path): return
	var settings = JSON.parse_string(FileAccess.get_file_as_string(config_path))
	if not settings is Dictionary: return
	facades_enabled = not baseline_b6 and settings.get("facades_enabled",false) and not "--sf3-facades-original" in OS.get_cmdline_user_args()
	# Archived B.6 and the limited relief pilot remain reproducible baselines.
	if baseline_b6 or (data_root != DATA_ROOT and not "/relief/world/" in data_root): return
	if not settings.get("recovery_enabled",false) or "--sf3-no-recovery" in OS.get_cmdline_user_args(): return
	var path: String = settings.get("recovery_manifest", "")
	if not FileAccess.file_exists(path): return
	var supplement = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not supplement is Dictionary or supplement.get("schema_version") != 1: return
	if supplement.get("map_sha256") != manifest.get("map_sha256") or supplement.get("arcade_sha256") != FileAccess.get_sha256("res://data/processed/arcade_layout.json"):
		push_warning("SF.3 recovery is stale; run tools/build_sf3_recovery.py")
		return
	if supplement.get("source_hashes",{}).get("data/processed/urban/city_manifest.json") != FileAccess.get_sha256(DATA_ROOT+"city_manifest.json"):
		push_warning("SF.3 recovery city changed; run tools/build_sf3_recovery.py")
		return
	var by_id := {}
	for entry in manifest["chunks"]: by_id[entry["id"]] = entry
	for entry in supplement["chunks"]:
		var id: String = entry["id"]
		recovery_chunks[id] = entry
		recovery_buildings += int(entry["building_count"])
		if by_id.has(id):
			var base: Dictionary = by_id[id]
			base["building_count"] += int(entry["building_count"])
			base["collision_count"] += int(entry["collision_count"])
			var a: Array = base["bounds_xz"]
			var b: Array = entry["bounds_xz"]
			base["bounds_xz"] = [minf(a[0],b[0]),minf(a[1],b[1]),maxf(a[2],b[2]),maxf(a[3],b[3])]
		else:
			var added: Dictionary = entry.duplicate(true)
			added["recovery_only"] = true
			manifest["chunks"].append(added)

func read_verified_chunk(entry: Dictionary, path: String) -> Dictionary:
	var bytes := FileAccess.get_file_as_bytes(path)
	var hasher := HashingContext.new()
	hasher.start(HashingContext.HASH_SHA256)
	hasher.update(bytes)
	var parsed = JSON.parse_string(bytes.get_string_from_utf8())
	if hasher.finish().hex_encode() != entry["sha256"] or not parsed is Dictionary or parsed.get("schema_version") != 1:
		push_error("Invalid urban chunk/hash: " + path)
		if not str(entry["id"]) in failed_chunks: failed_chunks.append(str(entry["id"]))
		return {}
	return parsed

func read_chunk(entry: Dictionary) -> Dictionary:
	var path: String = entry["file"]
	if not path.begins_with("res://"): path = data_root+path
	var data := read_verified_chunk(entry,path)
	if data.is_empty(): return {}
	var id: String = entry["id"]
	if recovery_chunks.has(id) and not entry.get("recovery_only",false):
		var extra: Dictionary = recovery_chunks[id]
		var recovered := read_verified_chunk(extra,str(extra["file"]))
		if recovered.is_empty(): return {}
		data["buildings"].append_array(recovered["buildings"])
	for building in data["buildings"]:
		if not building.get("sf3_recovered",false): continue
		var highest := -INF
		var lowest := INF
		for sample in building["elevation_samples_xz"]:
			var y: float = target.surface_height(float(sample[0]),float(sample[1]))
			highest = maxf(highest,y)
			lowest = minf(lowest,y)
		building["base_y_m"] = highest
		building["foundation_min_y_m"] = lowest-0.2
		building["elevation_source"] = "shared vehicle terrain samples; level foundation"
	data["sf3_life_enabled"] = facades_enabled
	return data

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
	last_refresh_position = target.global_position
	var nearby: Dictionary = {}
	var extent := ceili(float(settings["visual_load_radius_m"]) / 256) + 1
	var center := Vector2i(floori(target.position.x / 256), floori(target.position.z / 256))
	for x in range(center.x - extent, center.x + extent + 1):
		for z in range(center.y - extent, center.y + extent + 1):
			for entry in spatial_index.get(Vector2i(x, z), []):
				nearby[entry["id"]] = entry
	# Always audit currently loaded sectors for unloading, even after a teleport.
	for id in loaded:
		nearby[id] = loaded[id]["source"]
	for chunk in nearby.values():
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
	var data := read_chunk(entry)
	if data.is_empty(): return
	if not apply_arcade_layout(data):
		return
	if flatten_elevation:
		for building in data["buildings"]:
			building.erase("base_y_m")
			building.erase("foundation_min_y_m")
	if baseline_b6:
		data["category_facades"] = false
		for building in data["buildings"]:
			building.erase("category")
			building.erase("model_path")
			if building.has("automatic_height_m"):
				building["height_m"] = building["automatic_height_m"]
	if night_visuals:
		data["category_facades"]=false
		data["detail_windows"]=false
		data["night_visuals"]=true
	var start := Time.get_ticks_msec()
	var node := Node3D.new()
	node.name = "Urban_" + id
	add_child(node)
	var info: Dictionary = Builder.build(node, data)
	node.visible = city_enabled
	set_collisions(node, city_enabled and distance_to(entry) <= float(manifest["settings"]["collision_radius_m"]))
	loaded[id] = {"source": entry, "node": node, "count": int(entry["building_count"]), "info": info}
	loaded_buildings += int(entry["building_count"])
	total_chunk_loads += 1
	max_loaded_chunks = maxi(max_loaded_chunks, loaded.size())
	max_chunk_build_ms = maxi(max_chunk_build_ms, Time.get_ticks_msec() - start)

func apply_arcade_layout(data: Dictionary) -> bool:
	var overrides := building_overrides
	var chunk_id: String = str(data.get("id", ""))
	if chunk_overrides.has(chunk_id):
		var entry: Dictionary = chunk_overrides[chunk_id]
		var bytes := FileAccess.get_file_as_bytes("res://" + str(entry["file"]))
		var hashing := HashingContext.new()
		hashing.start(HashingContext.HASH_SHA256)
		hashing.update(bytes)
		var parsed = JSON.parse_string(bytes.get_string_from_utf8())
		if hashing.finish().hex_encode() != entry["sha256"] or not parsed is Dictionary or parsed.size() != int(entry["buildings"]):
			push_error("Arcade facade sector invalid: " + chunk_id)
			if chunk_id not in failed_chunks:
				failed_chunks.append(chunk_id)
			return false
		overrides = parsed
	for building in data["buildings"]:
		var id: String = building.get("id", "")
		if overrides.has(id):
			building.merge(overrides[id], true)
			# Indices and custom model dimensions refer to the original footprint.
			building.erase("facade_edge_index")
			building.erase("model_path")
	return true

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
	return {"enabled": city_enabled, "loaded_chunks": loaded.size(), "loaded_buildings": loaded_buildings, "max_loaded_chunks": max_loaded_chunks, "max_chunk_build_ms": max_chunk_build_ms, "chunk_loads": total_chunk_loads, "chunk_unloads": total_chunk_unloads, "failed_chunks": failed_chunks, "sf3_recovered_buildings": recovery_buildings, "sf3_facades": facades_enabled}

func fixture_buildings() -> Array:
	# Test-only inspection of currently streamed data, not a global runtime load.
	for chunk in manifest["chunks"]:
		if loaded.has(chunk["id"]) and distance_to(chunk) < 160:
			var data := read_chunk(chunk)
			if data.is_empty(): return []
			if not apply_arcade_layout(data):
				return []
			var result: Array = []
			for building in data["buildings"]:
				if building.get("collision_enabled", false) and not building.get("disabled", false):
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
	var jumped := target.global_position.distance_squared_to(last_refresh_position) > 4096.0
	if refresh_timer >= 0.12 or jumped:
		refresh_timer = 0
		refresh()
		if jumped:
			# Prime collision neighbours before the car's next physics step.
			var immediate: Array = pending.duplicate()
			for entry in immediate:
				if float(entry["distance"]) <= float(manifest["settings"]["collision_radius_m"]):
					load_chunk(entry["chunk"])
	for i in range(mini(int(manifest["settings"]["max_chunks_per_frame"]), pending.size())):
		var entry: Dictionary = pending.pop_front()
		load_chunk(entry["chunk"])

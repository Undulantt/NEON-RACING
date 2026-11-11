extends RefCounted
# Only file IO, hashes, JSON and an isolated graph. Never touches the scene tree.
func run() -> Dictionary:
	var json: Dictionary = {}
	var hashes: Dictionary = {}
	var paths: Array = ["res://data/processed/la_paz_map.json","res://data/processed/la_paz_environment.json","res://data/processed/arcade_layout.json","res://data/processed/expansion_manifest.json","res://config/expansion_config.json","res://config/arcade_roads.json","res://data/processed/urban/city_manifest.json","res://data/processed/urban/landmarks.json","res://data/processed/night_roads/manifest.json"]
	var relief_path := "res://data/processed/relief/world/manifest.json"
	if "--relief-pilot" in OS.get_cmdline_user_args(): relief_path = "res://data/processed/relief/pilot/manifest.json"
	if FileAccess.file_exists(relief_path):
		var relief = JSON.parse_string(FileAccess.get_file_as_string(relief_path))
		if relief is Dictionary:
			json[relief_path] = relief
			paths.append(relief_path)
			for key in ["heightfield_file","water_file"]: paths.append("res://"+str(relief[key]))
			paths.append("res://"+str(relief["city_root"])+"city_manifest.json")
			for source in relief["sources"]: paths.append("res://"+str(source))
	for path in paths:
		if hashes.has(path) or not FileAccess.file_exists(path): continue
		hashes[path] = FileAccess.get_sha256(path)
		if str(path).ends_with(".json") and not json.has(path):
			var value = JSON.parse_string(FileAccess.get_file_as_string(path))
			if value is Dictionary: json[path] = value
	var graph := preload("res://scripts/racing/RoadGraph.gd").new()
	if json.has("res://data/processed/la_paz_map.json"):
		graph.build(json["res://data/processed/la_paz_map.json"],hashes["res://data/processed/la_paz_map.json"])
	if json.has(relief_path) and not "--flat-world" in OS.get_cmdline_user_args():
		graph.configure_navigation(json[relief_path].get("road_ids",[]))
	return {"json":json,"hashes":hashes,"graph":graph}

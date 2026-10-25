extends RefCounted

static func load_map(path: String = "res://data/processed/la_paz_map.json") -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("Missing offline map: %s. Run tools/fetch_osm.py and tools/build_map.py." % path)
		return {}
	var parser := JSON.new()
	var error := parser.parse(FileAccess.get_file_as_string(path))
	if error != OK or not parser.data is Dictionary:
		push_error("Invalid map JSON: %s line %d" % [parser.get_error_message(), parser.get_error_line()])
		return {}
	var data: Dictionary = parser.data
	if data.get("schema_version") != 1 or data.get("metadata", {}).get("units") != "meters" or data.get("roads", []).is_empty() or data.get("chunks", []).is_empty():
		push_error("Map schema/units/geometry mismatch")
		return {}
	return data

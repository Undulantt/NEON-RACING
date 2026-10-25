extends Node3D

const Builder = preload("res://scripts/world/BuildingBuilder.gd")
var labels: Array[Label3D] = []

func configure(manifest: Dictionary) -> bool:
	var datasets := {}
	for filename in manifest.get("b6_files", {}):
		var path: String = "res://data/processed/urban/" + filename
		var bytes := FileAccess.get_file_as_bytes(path)
		var hash := HashingContext.new()
		hash.start(HashingContext.HASH_SHA256)
		hash.update(bytes)
		if hash.finish().hex_encode() != manifest["b6_files"][filename]:
			push_error("B6 data hash mismatch: " + filename)
			return false
		datasets[filename] = JSON.parse_string(bytes.get_string_from_utf8())
	if not datasets.has("urban_geography.json"):
		return false
	# One mesh for all mapped open surfaces; no extra physics bodies.
	var out := {"vertices": PackedVector3Array(), "normals": PackedVector3Array(), "colors": PackedColorArray()}
	for surface in datasets["urban_geography.json"]["surfaces"]:
		var color := Color(str(surface["color"]))
		var y: float = surface["y"]
		for tri in surface["triangles_xz"]:
			Builder.triangle(out, Vector3(tri[0][0], y, tri[0][1]), Vector3(tri[1][0], y, tri[1][1]), Vector3(tri[2][0], y, tri[2][1]), Vector3.UP, color)
	if not out["vertices"].is_empty():
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = out["vertices"]
		arrays[Mesh.ARRAY_NORMAL] = out["normals"]
		arrays[Mesh.ARRAY_COLOR] = out["colors"]
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var material := StandardMaterial3D.new()
		material.vertex_color_use_as_albedo = true
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		material.roughness = 0.9
		mesh.surface_set_material(0, material)
		var visual := MeshInstance3D.new()
		visual.mesh = mesh
		add_child(visual)
	for landmark in datasets["landmarks.json"]["landmarks"]:
		var label := Label3D.new()
		label.text = landmark["name"]
		label.position = Vector3(landmark["position_xz"][0], 14, landmark["position_xz"][1])
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.font_size = 48
		label.pixel_size = 0.025
		label.visibility_range_end = 450
		label.visible = false
		add_child(label)
		labels.append(label)
	return true

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F9:
		for label in labels:
			label.visible = not label.visible

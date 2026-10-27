extends RefCounted

var grid: Dictionary = {}
var heights := PackedFloat32Array()
var quality := PackedByteArray()

func configure(data: Dictionary) -> bool:
	grid = data
	var height_bytes := FileAccess.get_file_as_bytes("res://" + str(data["heights_file"]))
	quality = FileAccess.get_file_as_bytes("res://" + str(data["quality_file"]))
	if FileAccess.get_sha256("res://" + str(data["heights_file"])) != data["heights_sha256"] or FileAccess.get_sha256("res://" + str(data["quality_file"])) != data["quality_sha256"]:
		grid.clear()
		return false
	heights = height_bytes.to_float32_array()
	if heights.size() != int(grid["width"])*int(grid["depth"]) or quality.size() != heights.size():
		grid.clear()
		return false
	return true

func sample_height(x: float, z: float) -> Dictionary:
	if grid.is_empty():
		return {"valid": false, "reason": "no_grid"}
	var u := (x - float(grid["origin_xz"][0])) / float(grid["step_m"])
	var v := (z - float(grid["origin_xz"][1])) / float(grid["step_m"])
	var width := int(grid["width"])
	var depth := int(grid["depth"])
	if u < 0 or v < 0 or u > width - 1 or v > depth - 1:
		return {"valid": false, "reason": "outside_coverage"}
	var ix := mini(floori(u), width - 2)
	var iz := mini(floori(v), depth - 2)
	var a := u - ix
	var b := v - iz
	var i := iz * width + ix
	var h := heights
	var height: float
	if b <= a:
		height = float(h[i]) + a * (float(h[i+1])-float(h[i])) + b * (float(h[i+width+1])-float(h[i+1]))
	else:
		height = float(h[i]) + a * (float(h[i+width+1])-float(h[i+width])) + b * (float(h[i+width])-float(h[i]))
	var estimated := false
	for index in [i, i+1, i+width, i+width+1]:
		estimated = estimated or int(quality[index]) != 0
	return {"valid": true, "height_m": height, "estimated": estimated, "adjusted": true}

func get_height_at(x: float, z: float) -> float:
	var result := sample_height(x, z)
	return float(result["height_m"]) if result["valid"] else NAN

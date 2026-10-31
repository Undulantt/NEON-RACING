extends Control

# North stays at the top. Roads come from the same geographic segments as physics.
const METERS_TO_PIXELS := 0.65
var car: CharacterBody3D
var nearby: Array = []
var refresh_time := 0.0

func _process(delta: float) -> void:
	if car == null:
		return
	refresh_time -= delta
	if refresh_time <= 0:
		refresh_time = 0.2
		nearby.clear()
		var seen := {}
		var p := car.global_position
		for x in range(floori((p.x - 240) / 256), floori((p.x + 240) / 256) + 1):
			for z in range(floori((p.z - 240) / 256), floori((p.z + 240) / 256) + 1):
				for road in car.road_cells.get(Vector2i(x, z), []):
					var key: String = str(road.get("id", road["points_xz"]))
					if not seen.has(key):
						seen[key] = true
						nearby.append(road)
	queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.035, 0.065, 0.08, 0.93))
	if car == null:
		return
	var center := size * 0.5
	var position_xz := Vector2(car.global_position.x, car.global_position.z)
	for road in nearby:
		var points: Array = road["points_xz"]
		for i in range(points.size() - 1):
			var a := center + (Vector2(points[i][0], points[i][1]) - position_xz) * METERS_TO_PIXELS
			var b := center + (Vector2(points[i+1][0], points[i+1][1]) - position_xz) * METERS_TO_PIXELS
			draw_line(a, b, Color("63757d"), maxf(3, float(road.get("width_m", 7)) * METERS_TO_PIXELS), true)
	var arrow := PackedVector2Array()
	for point in [Vector2(0, -10), Vector2(6, 7), Vector2(0, 4), Vector2(-6, 7)]:
		arrow.append(center + point.rotated(-car.rotation.y))
	draw_colored_polygon(arrow, Color("ffca42"))
	draw_string(ThemeDB.fallback_font, Vector2(size.x - 20, 18), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("b5c8d0"))

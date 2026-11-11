extends Control

# North stays at the top. Roads come from the same geographic segments as physics.
const METERS_TO_PIXELS := 0.65
var car: CharacterBody3D
var world: Node3D
var drawn_checkpoint_indices: Array[int] = []
var race_marker_visible := false
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
	_draw_navigation(center,position_xz)
	var arrow := PackedVector2Array()
	for point in [Vector2(0, -10), Vector2(6, 7), Vector2(0, 4), Vector2(-6, 7)]:
		arrow.append(center + point.rotated(-car.rotation.y))
	draw_colored_polygon(arrow, Color("ffca42"))
	draw_string(ThemeDB.fallback_font, Vector2(size.x - 20, 18), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("b5c8d0"))

func screen(at: Vector2, center: Vector2, position_xz: Vector2) -> Vector2:
	return center+(at-position_xz)*METERS_TO_PIXELS

func _draw_navigation(center: Vector2, position_xz: Vector2) -> void:
	drawn_checkpoint_indices.clear()
	race_marker_visible = false
	if world == null: return
	var activity = world.get("race_activity")
	var path: Array = []
	var active_race: bool = activity != null and activity.session != null
	if active_race: path = activity.definition["points_xz"]
	elif world.get("navigation") != null: path = world.get("navigation").points
	var line := PackedVector2Array()
	for p in path: line.append(screen(Vector2(p[0],p[1]),center,position_xz))
	if line.size()>1:
		draw_polyline(line,Color(1,0.4,0.05,0.2),7,true)
		draw_polyline(line,Color("ff891c"),3,true)
	var bounds := Rect2(Vector2.ZERO,size)
	if active_race:
		var session = activity.session
		var candidates: Array = []
		for i in range(session.next_checkpoint,activity.definition["checkpoints"].size()):
			var p: Array = activity.definition["checkpoints"][i]["position_xz"]
			var at := screen(Vector2(p[0],p[1]),center,position_xz)
			if bounds.grow(-7).has_point(at): candidates.append({"index":i,"point":at,"distance":at.distance_squared_to(center)})
		candidates.sort_custom(func(a,b):return a["distance"]<b["distance"])
		for item in candidates.slice(0,5):
			drawn_checkpoint_indices.append(int(item["index"]))
			draw_circle(item["point"],5.5,Color.WHITE)
			draw_circle(item["point"],3.8,Color("218cff"))
			if item["index"] == session.next_checkpoint: draw_circle(item["point"],7,Color("8addff"),false,1.5)
	elif activity != null and not activity.default_race.is_empty():
		var p: Array = activity.default_race["start"]["position_xz"]
		var at := screen(Vector2(p[0],p[1]),center,position_xz)
		if bounds.grow(-7).has_point(at):
			race_marker_visible = true
			draw_circle(at,6,Color("ff43b3"))
			draw_line(at+Vector2(0,-10),at+Vector2(0,5),Color.WHITE,1.5)
			draw_colored_polygon(PackedVector2Array([at+Vector2(0,-10),at+Vector2(8,-7),at+Vector2(0,-3)]),Color("ffacd9"))
	if not active_race and world.get("navigation") != null and not world.get("navigation").destination_id.is_empty():
		var at := screen(world.get("navigation").destination,center,position_xz)
		if bounds.grow(-7).has_point(at):
			draw_circle(at,5,Color("ff9eda"))
			draw_circle(at,7,Color.WHITE,false,1.5)

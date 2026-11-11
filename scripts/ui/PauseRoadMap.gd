extends Control
var world: Node3D
var center := Vector2.ZERO
var zoom := 0.12
var dragging := false

func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP

func recenter() -> void:
	center = Vector2(world.player.position.x,world.player.position.z)
	queue_redraw()

func screen(at: Vector2) -> Vector2:
	return (at-center)*zoom+size*0.5

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO,size),Color("12191e"))
	var flow := get_node_or_null("/root/GameFlow")
	if world == null or flow == null or flow.road_graph == null: return
	var view := Rect2(Vector2.ZERO,size).grow(80)
	for road in world.map_data["roads"]:
		var p: Vector2 = flow.road_graph.nodes[str(road["from"])]
		var q: Vector2 = flow.road_graph.nodes[str(road["to"])]
		var a := screen(p)
		var b := screen(q)
		if Rect2(a,b-a).abs().grow(1).intersects(view):
			draw_line(a,b,Color("647078"),clampf(float(road["width_m"])*zoom,1.2,9),true)
	var navigation = world.navigation
	if navigation != null:
		var path := PackedVector2Array()
		for p in navigation.points: path.append(screen(Vector2(p[0],p[1])))
		if path.size()>1: draw_polyline(path,Color("ff860f"),4,true)
		if not navigation.destination_id.is_empty():
			var destination := screen(navigation.destination)
			draw_circle(destination,9,Color("ff65bd"))
			draw_circle(destination,11,Color.WHITE,false,2)
	var activity = world.race_activity
	if activity != null and not activity.default_race.is_empty():
		var p: Array = activity.default_race["start"]["position_xz"]
		var start := screen(Vector2(p[0],p[1]))
		draw_circle(start,7,Color("ff48b3"))
		draw_string(ThemeDB.fallback_font,start+Vector2(12,5),"Carrera",HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color("ffa2d8"))
	var player := screen(Vector2(world.player.position.x,world.player.position.z))
	var triangle := PackedVector2Array()
	for p in [Vector2(0,-10),Vector2(7,8),Vector2(0,4),Vector2(-7,8)]: triangle.append(player+p.rotated(-world.player.rotation.y))
	draw_colored_polygon(triangle,Color("ffe091"))
	draw_string(ThemeDB.fallback_font,Vector2(size.x-27,24),"N",HORIZONTAL_ALIGNMENT_LEFT,-1,18,Color.WHITE)

func select_at(local_position: Vector2) -> bool:
	var at := (local_position-size*0.5)/zoom+center
	var result: bool = world.navigation.set_destination(at)
	queue_redraw()
	return result

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_MIDDLE or event.button_index == MOUSE_BUTTON_RIGHT: dragging = event.pressed
		if not event.pressed: return
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
			var before: Vector2 = (event.position-size*0.5)/zoom+center
			zoom = clampf(zoom*(1.2 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0/1.2),0.035,2.0)
			center = before-(event.position-size*0.5)/zoom
		if event.button_index == MOUSE_BUTTON_LEFT: select_at(event.position)
		queue_redraw()
	elif event is InputEventMouseMotion and dragging:
		center -= event.relative/zoom
		queue_redraw()

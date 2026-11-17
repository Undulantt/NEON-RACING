extends Control
var main:=true

func _ready() -> void:mouse_filter=Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
	if main:
		var points:=PackedVector2Array()
		var center:=Vector2(1012.468,-353+1293.918*.5)
		for p in [Vector2(-395.229,-532.2565),Vector2(395.229,-532.2565),Vector2(395.229,532.2565),Vector2(-395.229,532.2565)]:points.append(p.rotated(deg_to_rad(-23.99))+center)
		draw_colored_polygon(points,Color(0,0,0,.5));points.append(points[0]);draw_polyline(points,Color("00e5ee"),8,true)
	else:
		draw_rect(Rect2(224,-18,1064.513,790.458),Color(0,0,0,.5))
		draw_rect(Rect2(224,-18,1064.513,790.458),Color("00e5ee"),false,8)

extends Control
# The preview uses the same saved OSM route as the playable race.
var definition: Dictionary={}
func _ready() -> void:mouse_filter=Control.MOUSE_FILTER_IGNORE;resized.connect(queue_redraw)
func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO,size),Color(.025,.035,.07,.85))
	var points: Array=definition.get("points_xz",[])
	if points.size()<2:return
	var bounds:=Rect2(Vector2(points[0][0],points[0][1]),Vector2.ZERO)
	for p in points:bounds=bounds.expand(Vector2(p[0],p[1]))
	var factor:=minf((size.x-60)/maxf(1,bounds.size.x),(size.y-50)/maxf(1,bounds.size.y))
	var line:=PackedVector2Array()
	for p in points:line.append((Vector2(p[0],p[1])-bounds.get_center())*factor+size*.5)
	draw_polyline(line,Color("ff891c"),3,true)
	draw_circle(line[0],6,Color("5affcb"));draw_circle(line[-1],6,Color("ff6cc4"))
	draw_string(ThemeDB.fallback_font,Vector2(12,20),"SALIDA",HORIZONTAL_ALIGNMENT_LEFT,-1,13,Color("5affcb"))
	draw_string(ThemeDB.fallback_font,Vector2(size.x-60,20),"META",HORIZONTAL_ALIGNMENT_LEFT,-1,13,Color("ff6cc4"))

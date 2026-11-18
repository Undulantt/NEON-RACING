extends Button
var direction:=1
func _ready() -> void:
	var clear:=StyleBoxEmpty.new()
	for state in ["normal","hover","pressed","focus"]:add_theme_stylebox_override(state,clear)
	for event in [mouse_entered,mouse_exited,focus_entered,focus_exited,button_down,button_up]:event.connect(queue_redraw)
	resized.connect(queue_redraw)
func _draw() -> void:
	var color:=Color("ff28c4") if is_hovered() or is_pressed() else Color("00e5ee")
	var center:=size*.5
	draw_colored_polygon(PackedVector2Array([center+Vector2(direction*14,0),center+Vector2(-direction*12,-16),center+Vector2(-direction*12,16)]),color)
	if has_focus():draw_line(Vector2(12,size.y-4),Vector2(size.x-12,size.y-4),Color.WHITE,1.5)

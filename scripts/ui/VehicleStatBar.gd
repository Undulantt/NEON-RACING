extends Control
var caption:=""
var value:=0
func _ready() -> void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE;custom_minimum_size=Vector2(550,46)
func _draw() -> void:
	var font=preload("res://scripts/ui/NeonButton.gd").arial()
	var italic=preload("res://scripts/ui/NeonButton.gd").arial(true)
	draw_string(font,Vector2(0,14),caption,HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color("e7faff"))
	var width:=size.x-65;var y:=23.0;var height:=17.0;var slant:=22.0
	var outline:=PackedVector2Array([Vector2(0,y),Vector2(width,y),Vector2(width-slant,y+height),Vector2(0,y+height)])
	draw_colored_polygon(outline,Color(0,.04,.07,.65))
	var filled: float=clampf(value/10.0,0,1)*(width-slant-4)
	if filled>0:draw_colored_polygon(PackedVector2Array([Vector2(2,y+2),Vector2(filled+slant*.8,y+2),Vector2(filled,y+height-2),Vector2(2,y+height-2)]),Color.WHITE)
	outline.append(outline[0]);draw_polyline(outline,Color("00e5ee"),1.5,true)
	draw_string(italic,Vector2(size.x-48,y+15),"%d/10" % value,HORIZONTAL_ALIGNMENT_LEFT,-1,18,Color.WHITE)

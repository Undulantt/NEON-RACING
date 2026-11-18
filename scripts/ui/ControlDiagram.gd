extends Control
# Original vector artwork; no external images, textures, or trademarked controller artwork.
var gamepad := false
const CYAN=Color("00e5ee")
const PINK=Color("ff46c2")
var font: Font=preload("res://scripts/ui/NeonButton.gd").arial(true)

func label(value: String, at: Vector2, point_size:=16, tint:=Color.WHITE) -> void:
	draw_string(font,at,value,HORIZONTAL_ALIGNMENT_LEFT,-1,point_size,tint)

func cap(rect: Rect2, value: String, tint:=CYAN) -> void:
	var style:=StyleBoxFlat.new();style.bg_color=Color("100c27");style.border_color=tint
	style.set_border_width_all(2);style.set_corner_radius_all(5)
	draw_style_box(style,rect)
	var width:=font.get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,16).x
	label(value,rect.position+Vector2((rect.size.x-width)*.5,rect.size.y*.5+6),16,tint)

func _draw() -> void:
	if gamepad:
		label("MANDO ESTÁNDAR",Vector2(22,27),21)
		# Two grips, central bridge and familiar physical button positions.
		draw_colored_polygon(PackedVector2Array([Vector2(50,122),Vector2(87,86),Vector2(215,86),Vector2(251,122),Vector2(278,245),Vector2(249,259),Vector2(207,210),Vector2(96,210),Vector2(53,259),Vector2(25,245)]),Color("17152c"))
		draw_polyline(PackedVector2Array([Vector2(50,122),Vector2(87,86),Vector2(215,86),Vector2(251,122),Vector2(278,245),Vector2(249,259),Vector2(207,210),Vector2(96,210),Vector2(53,259),Vector2(25,245),Vector2(50,122)]),CYAN,2,true)
		cap(Rect2(45,48,60,30),"LT / L2")
		cap(Rect2(196,48,60,30),"RT / R2")
		cap(Rect2(196,88,60,27),"RB / R1")
		draw_circle(Vector2(86,143),27,Color("060a1c"));draw_arc(Vector2(86,143),27,0,TAU,32,CYAN,2,true)
		label("L",Vector2(80,149),18,CYAN)
		cap(Rect2(104,181,25,42),"↕");cap(Rect2(96,190,42,25),"↔")
		cap(Rect2(140,125,35,25),"☰")
		draw_circle(Vector2(180,210),17,Color("060a1c"));draw_arc(Vector2(180,210),17,0,TAU,24,CYAN,2,true);label("R",Vector2(174,216),16,CYAN)
		for entry in [[Vector2(222,188),"A",CYAN],[Vector2(247,164),"B",PINK],[Vector2(197,164),"X",CYAN],[Vector2(222,140),"Y",PINK]]:
			var at: Vector2=entry[0];draw_circle(at,13,Color("080a1e"));draw_arc(at,13,0,TAU,24,entry[2],1.5,true);label(entry[1],at+Vector2(-5,6),16,entry[2])
		label("A / ✕     B / ○",Vector2(52,296),18)
		label("X / □     Y / △",Vector2(52,322),18)
		label("Nombres Xbox / PlayStation",Vector2(21,356),15,CYAN)
	else:
		label("TECLADO + RATÓN",Vector2(18,27),21)
		cap(Rect2(22,49,62,35),"ESC",PINK)
		cap(Rect2(98,99,47,42),"W / ↑")
		cap(Rect2(43,149,47,42),"A / ←")
		cap(Rect2(98,149,47,42),"S / ↓")
		cap(Rect2(153,149,47,42),"D / →")
		cap(Rect2(22,207,82,36),"SHIFT",PINK)
		cap(Rect2(112,207,164,36),"ESPACIO")
		for i in range(4):cap(Rect2(22+i*65,263,55,35),["R","E","P","V"][i])
		label("WASD o flechas para conducir",Vector2(18,334),16,CYAN)
		label("Marchas automáticas",Vector2(18,360),16)

extends Control

const CYAN := Color("17bad8")
const GOLD := Color("ffbf35")
var car: CharacterBody3D
var minimap: Control

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	minimap = Control.new()
	minimap.set_script(preload("res://scripts/ui/DrivingMinimap.gd"))
	minimap.position = Vector2(24, 20)
	minimap.size = Vector2(216, 216)
	minimap.clip_contents = true
	minimap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(minimap)

func _process(_delta: float) -> void:
	minimap.car = car
	queue_redraw()

func wedge(at: Vector2, width: float, fill: float, color: Color) -> void:
	var outline := PackedVector2Array([at, at + Vector2(18, -28), at + Vector2(width, -28), at + Vector2(width - 18, 0)])
	draw_colored_polygon(outline, Color(0.025, 0.05, 0.07, 0.8))
	if fill > 0.001:
		var length := (width - 18) * clampf(fill, 0, 1)
		draw_colored_polygon(PackedVector2Array([at, at + Vector2(18, -28), at + Vector2(18 + length, -28), at + Vector2(length, 0)]), color)

func _draw() -> void:
	if car == null:
		return
	draw_rect(Rect2(22, 18, 220, 220), CYAN, false, 2)
	var origin := Vector2(size.x - 330, size.y)
	wedge(origin + Vector2(40, -312), 236, car.turbo_charge, CYAN)
	wedge(origin + Vector2(40, -264), 236, car.drift_boost_time / float(car.config["drift_bonus_duration_s"]) if car.drift_boost_active else car.drift_charge, GOLD)
	var center := origin + Vector2(155, -122)
	draw_circle(center, 145, Color(0.02, 0.035, 0.045, 0.20))
	var font := ThemeDB.fallback_font
	for i in range(61):
		var angle := deg_to_rad(155.0 + i * 4.0)
		var ray := Vector2(cos(angle), sin(angle))
		var major := i % 5 == 0
		var color := Color("ff4455") if i >= 56 else GOLD if i >= 51 else CYAN
		draw_line(center + ray * (123 if major else 133), center + ray * 143, color, 2 if major else 1, true)
		if major:
			var text_value := str(i * 4)
			var text_size := font.get_string_size(text_value, HORIZONTAL_ALIGNMENT_LEFT, -1, 13)
			draw_string(font, center + ray * 105 - text_size * 0.5 + Vector2(0, 9), text_value, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, color)
	var needle_angle := deg_to_rad(155 + clampf(car.speed_mps * 3.6 / 240.0, 0, 1) * 240)
	var needle := Vector2(cos(needle_angle), sin(needle_angle))
	draw_colored_polygon(PackedVector2Array([center + needle.orthogonal() * 3, center + needle * 117, center - needle.orthogonal() * 3]), CYAN)
	draw_circle(center, 4, CYAN)
	draw_string(font, origin + Vector2(222, -32), "KM/H", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color.WHITE)
	if car.signed_speed < -0.2:
		draw_string(font, origin + Vector2(80, -32), "R", HORIZONTAL_ALIGNMENT_LEFT, -1, 24, GOLD)

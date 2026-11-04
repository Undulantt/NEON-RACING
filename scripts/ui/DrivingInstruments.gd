extends Control

const CYAN := Color("35d5eb")
const GOLD := Color("ffbf35")
const START_ANGLE := 160.0
const SWEEP := 240.0
var car: CharacterBody3D
var minimap: Control
var needle_rpm := 900.0
var needle_angle := deg_to_rad(START_ANGLE)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	minimap = Control.new()
	minimap.set_script(preload("res://scripts/ui/DrivingMinimap.gd"))
	minimap.position = Vector2(24,20)
	minimap.size = Vector2(216,216)
	minimap.clip_contents = true
	minimap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(minimap)

func gauge_center() -> Vector2:
	var viewport := get_viewport_rect().size
	return Vector2(viewport.x-166,viewport.y-150)

func _process(delta: float) -> void:
	minimap.car = car
	if car != null and not get_tree().paused:
		needle_rpm = lerpf(needle_rpm,car.powertrain.rpm,1.0-exp(-22.0*delta))
		needle_angle = rpm_angle(needle_rpm)
	queue_redraw()

func rpm_angle(value: float) -> float:
	var redline := float(car.powertrain.settings["redline_rpm"])
	return deg_to_rad(START_ANGLE + clampf(value/redline,0,1)*SWEEP)

func wedge(at: Vector2, width: float, fill: float, color: Color) -> void:
	var outline := PackedVector2Array([at,at+Vector2(18,-24),at+Vector2(width,-24),at+Vector2(width-18,0)])
	draw_colored_polygon(outline,Color(0.025,0.05,0.07,0.8))
	if fill > 0.001:
		var length := (width-18)*clampf(fill,0,1)
		draw_colored_polygon(PackedVector2Array([at,at+Vector2(18,-24),at+Vector2(18+length,-24),at+Vector2(length,0)]),color)

func centered_text(font: Font, at: Vector2, value: String, font_size: int, color: Color) -> void:
	var extent := font.get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size)
	draw_string(font,at-Vector2(extent.x*0.5,0),value,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,color)

func _draw() -> void:
	if car == null:
		return
	draw_rect(Rect2(22,18,220,220),CYAN,false,2)
	var viewport := get_viewport_rect().size
	var origin := Vector2(viewport.x-330,viewport.y)
	wedge(origin+Vector2(40,-292),236,car.drift_boost_time/float(car.config["drift_bonus_duration_s"]) if car.drift_boost_active else car.drift_charge,GOLD)
	var ability = car.abilities
	var burst_fill: float = ability.burst_bonus/float(car.config["burst_max_bonus"]) if ability.burst_state==2 else ability.arming_time/float(car.config["burst_arming_time_s"])
	wedge(origin+Vector2(40,-400),236,burst_fill,Color("e878ed"))
	draw_tachometer()

func draw_tachometer() -> void:
	var center := gauge_center()
	var font := ThemeDB.fallback_font
	var settings: Dictionary = car.powertrain.settings
	var redline := float(settings["redline_rpm"])
	var warning := float(settings["warning_rpm"])
	var start := deg_to_rad(START_ANGLE)
	var end := deg_to_rad(START_ANGLE+SWEEP)
	var warning_angle := rpm_angle(warning)
	draw_circle(center,116,Color(0.025,0.04,0.055,0.30))
	draw_arc(center,130,start,end,100,Color(0.04,0.06,0.08,0.7),7,true)
	draw_arc(center,130,start,warning_angle,80,Color("eff4f6"),3,true)
	draw_arc(center,130,warning_angle,end,24,Color("f45646"),6,true)
	for i in range(33):
		var revs := redline*float(i)/32.0
		var angle := rpm_angle(revs)
		var direction := Vector2(cos(angle),sin(angle))
		var major := i%4==0
		var color := Color("ff6654") if revs>=warning else Color("e5edf0")
		draw_line(center+direction*(119 if major else 125),center+direction*132,color,1.5 if major else 1.0,true)
		if i%8==0:
			centered_text(font,center+direction*146+Vector2(0,5),str(roundi(revs/1000.0)),15,color)
	# Turbo is the inner arc of this dial, using the same reserve as the controller.
	draw_arc(center,106,start,end,90,Color(0.08,0.12,0.15,0.9),8,true)
	if car.turbo_charge > 0.001:
		var fill_end := lerpf(start,end,clampf(car.turbo_charge,0,1))
		draw_arc(center,106,start,fill_end,90,CYAN if car.turbo_charge>=float(car.config["turbo_min_charge"]) else Color(CYAN,0.42),7,true)
		if car.turbo_active:
			draw_arc(center,106,start,fill_end,90,Color("d9fbff"),2,true)
	var bolt := center+Vector2(-85,27)
	draw_colored_polygon(PackedVector2Array([bolt+Vector2(0,-9),bolt+Vector2(-5,1),bolt+Vector2(0,1),bolt+Vector2(-2,10),bolt+Vector2(6,-2),bolt+Vector2(1,-2)]),CYAN)
	centered_text(font,center+Vector2(0,-63),"RPM ×1000",11,Color("b9c9cf"))
	centered_text(font,center+Vector2(-18,33),"KM/H",12,Color("e8eef1"))
	draw_line(center+Vector2(39,-23),center+Vector2(39,29),Color("d4dfe4"),1,true)
	centered_text(font,center+Vector2(65,33),"MARCHA",9,Color("b9c9cf"))
	var direction := Vector2(cos(needle_angle),sin(needle_angle))
	var perpendicular := direction.orthogonal()
	draw_line(center+direction*61,center+direction*126,Color(0.01,0.02,0.03,0.9),6,true)
	draw_colored_polygon(PackedVector2Array([center+direction*59+perpendicular*1.8,center+direction*129,center+direction*59-perpendicular*1.8]),Color("ffb34c") if needle_rpm>=warning else Color.WHITE)

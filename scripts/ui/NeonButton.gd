@tool
extends Button
# Native Button semantics (focus, shortcuts, gamepad, toggles) with Figma artwork.
const ART="res://assets/ui/menu/components/"
const BAR=preload(ART+"bar.svg")
const BAR_ACTIVE=preload(ART+"bar_selected.svg")
const LINE_ACTIVE=preload(ART+"line_selected.svg")
const TERMINAL_ACTIVE=preload(ART+"terminal_selected.svg")
static var cached_fonts: Dictionary={}
@export var compact:=false:
	set(value):compact=value;_configure();queue_redraw()
@export var tab_style:=false:
	set(value):tab_style=value;queue_redraw()
var pressing:=false

static func arial(italic:=false) -> SystemFont:
	if cached_fonts.has(italic):return cached_fonts[italic]
	var font:=SystemFont.new();font.font_names=PackedStringArray(["Arial","Liberation Sans","DejaVu Sans"])
	font.font_italic=italic;font.font_weight=700 if italic else 400
	font.fallbacks=[ThemeDB.fallback_font]
	cached_fonts[italic]=font
	return font

func _ready() -> void:
	_configure()
	if not Engine.is_editor_hint():
		add_to_group("neon_buttons")
		get_tree().call_group("ui_feedback","bind_button",self)
	button_down.connect(func():pressing=true;queue_redraw())
	button_up.connect(func():pressing=false;queue_redraw())
	for event in [mouse_entered,mouse_exited,focus_entered,focus_exited,button_down,button_up]:event.connect(queue_redraw)
	toggled.connect(func(_value: bool):queue_redraw())
	resized.connect(queue_redraw)

func _configure() -> void:
	var empty:=StyleBoxEmpty.new()
	empty.content_margin_left=40 if compact else 64
	empty.content_margin_right=12 if compact else 43
	empty.content_margin_bottom=14 if compact else 18
	for state in ["normal","hover","pressed","hover_pressed","disabled","focus"]:add_theme_stylebox_override(state,empty)
	add_theme_font_override("font",arial(true));add_theme_font_size_override("font_size",17 if compact else 24)
	for state in ["font_color","font_hover_color","font_pressed_color","font_focus_color","font_hover_pressed_color"]:add_theme_color_override(state,Color("f8f7fb"))
	add_theme_color_override("font_disabled_color",Color("918c9a"))
	alignment=HORIZONTAL_ALIGNMENT_LEFT;text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	clip_text=true
	custom_minimum_size.y=48 if compact else 68
	focus_mode=Control.FOCUS_ALL

func highlighted() -> bool:
	return not disabled and (is_hovered() or pressing)

func _draw() -> void:
	var active:=highlighted()
	var unit:=.65 if compact else 1.0
	var tint:=Color(1,1,1,.32) if disabled else Color.WHITE
	var y:=minf(size.y-12,43*unit)
	var start:=52*unit
	var right:=7.0 if tab_style else 43*unit
	var end:=maxf(start+5,size.x-right)
	for i in range(3):
		var bar: Texture2D=BAR_ACTIVE if active and i==2 else BAR
		draw_texture_rect(bar,Rect2(Vector2((7+i*15)*unit,14*unit),Vector2(24,26)*unit),false,tint)
	if active:draw_texture_rect(LINE_ACTIVE,Rect2(start,y,end-start,4*unit),false,tint)
	else:draw_rect(Rect2(start,y,end-start,4*unit),Color(Color("00e5ee"),tint.a))
	var terminal_width: float=(31 if tab_style and not active else 36)*unit
	if active:draw_texture_rect(TERMINAL_ACTIVE,Rect2(end-terminal_width,y,terminal_width,11*unit),false,tint)
	else:
		var terminal:=PackedVector2Array([Vector2(end-terminal_width,y),Vector2(end,y),Vector2(end-8*unit,y+11*unit),Vector2(end-terminal_width+8*unit,y+11*unit)])
		draw_colored_polygon(terminal,Color(Color("00e5ee"),tint.a))
	if not Engine.is_editor_hint() and has_focus() and not active:
		var feedback:=get_tree().get_first_node_in_group("ui_feedback")
		if feedback==null or feedback.using_navigation:
			draw_line(Vector2(start,y+7*unit),Vector2(end,y+7*unit),Color.WHITE,unit,true)

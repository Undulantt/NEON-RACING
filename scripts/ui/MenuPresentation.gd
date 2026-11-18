extends Control
const Neon=preload("res://scripts/ui/NeonButton.gd")
const BACKGROUND=preload("res://assets/ui/menu/backgorunds/Fondo main menu.png")
const LOGO=preload("res://assets/ui/menu/logos/TITULO.png")
var shell: Control
var canvas: Control
var backdrop: Control
var logo: TextureRect
var scroll: ScrollContainer
var panel: TextureRect
var header_line: TextureRect
var header_terminal: TextureRect
var tabs: Array=[]

func picture(texture: Texture2D, rect: Rect2, parent: Control) -> TextureRect:
	var image:=TextureRect.new();image.texture=texture;image.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode=TextureRect.STRETCH_SCALE;image.mouse_filter=Control.MOUSE_FILTER_IGNORE
	image.position=rect.position;image.size=rect.size;parent.add_child(image);return image

func configure(target: Control) -> void:
	shell=target;set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	var theme_resource:=Theme.new();theme_resource.default_font=Neon.arial();theme_resource.default_font_size=20
	var field:=StyleBoxFlat.new();field.bg_color=Color(0,0,0,0);field.border_color=Color("008e99");field.set_border_width_all(1);field.set_corner_radius_all(3)
	field.content_margin_left=12;field.content_margin_right=30;field.content_margin_top=7;field.content_margin_bottom=7
	var field_hover: StyleBoxFlat=field.duplicate();field_hover.border_color=Color("00ebf1")
	var field_focus: StyleBoxFlat=field.duplicate();field_focus.bg_color=Color(0,0,0,0);field_focus.border_color=Color.WHITE;field_focus.set_border_width_all(2)
	for state in ["normal","disabled"]:theme_resource.set_stylebox(state,"OptionButton",field)
	for state in ["hover","pressed"]:theme_resource.set_stylebox(state,"OptionButton",field_hover)
	theme_resource.set_stylebox("focus","OptionButton",field_focus)
	var track:=StyleBoxFlat.new();track.bg_color=Color("254751");track.content_margin_top=3;track.content_margin_bottom=3;track.set_corner_radius_all(3)
	var fill: StyleBoxFlat=track.duplicate();fill.bg_color=Color("00d4e3")
	theme_resource.set_stylebox("slider","HSlider",track)
	for state in ["grabber_area","grabber_area_highlight"]:theme_resource.set_stylebox(state,"HSlider",fill)
	shell.theme=theme_resource
	var outside:=ColorRect.new();outside.color=Color("09040f");outside.mouse_filter=Control.MOUSE_FILTER_IGNORE
	outside.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);add_child(outside)
	canvas=Control.new();canvas.size=Vector2(1280,720);canvas.clip_contents=true;canvas.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(canvas)
	picture(BACKGROUND,Rect2(-18,-10,1315,740),canvas)
	backdrop=preload("res://scripts/ui/MenuBackdrop.gd").new();backdrop.size=canvas.size;canvas.add_child(backdrop)
	panel=picture(preload("res://assets/ui/menu/components/frame.svg"),Rect2(256,156,1000,500),canvas)
	logo=picture(LOGO,Rect2(674,40,600,200),canvas)
	shell.heading=Label.new();shell.heading.grow_vertical=Control.GROW_DIRECTION_END;shell.heading.add_theme_font_override("font",Neon.arial(true));shell.heading.add_theme_font_size_override("font_size",24);canvas.add_child(shell.heading)
	header_line=picture(preload("res://assets/ui/menu/components/header_line.svg"),Rect2(256,63,357,4),canvas)
	header_terminal=picture(preload("res://assets/ui/menu/components/header_terminal.svg"),Rect2(577,63,36,11),canvas)
	scroll=ScrollContainer.new();scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;canvas.add_child(scroll)
	shell.body=VBoxContainer.new();shell.body.size_flags_horizontal=Control.SIZE_EXPAND_FILL;shell.body.add_theme_constant_override("separation",12);scroll.add_child(shell.body)
	shell.back_button=Neon.new();shell.back_button.text="REGRESAR";shell.back_button.pressed.connect(GameFlow.go_back);canvas.add_child(shell.back_button)
	shell.status=Label.new();shell.status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;shell.status.add_theme_color_override("font_color",Color("ffd38c"));canvas.add_child(shell.status)
	resized.connect(fit);fit()

func fit() -> void:
	if canvas==null:return
	var factor:=minf(size.x/1280.0,size.y/720.0)
	canvas.scale=Vector2.ONE*factor;canvas.position=(size-Vector2(1280,720)*factor)*.5

func set_view(state: StringName) -> void:
	var main: bool=state==&"main_menu"
	var credits: bool=state==&"credits"
	var options: bool=state==&"options"
	var vehicles: bool=state==&"vehicle_select"
	backdrop.main=main;backdrop.queue_redraw()
	logo.visible=main or credits
	logo.position=Vector2(674,40) if main else Vector2(606,38)
	logo.size=Vector2(600,200) if main else Vector2(300,100)
	panel.visible=not main and not vehicles
	shell.heading.visible=not main
	shell.heading.position=Vector2(276,177) if credits else Vector2(256,26)
	shell.heading.size=Vector2(950,40)
	header_line.visible=not main;header_terminal.visible=not main
	header_line.position=Vector2(276,214) if credits else Vector2(256,63)
	header_terminal.position=header_line.position+Vector2(321,0)
	scroll.position=Vector2(778,240) if main else (Vector2(281,233) if credits else Vector2(280,178))
	scroll.size=Vector2(400,440) if main else (Vector2(950,330) if credits else Vector2(950,440))
	if vehicles:scroll.position=Vector2(256,116);scroll.size=Vector2(1000,526)
	if state==&"how_to_play":scroll.position=Vector2(280,100);scroll.size=Vector2(950,530)
	scroll.scroll_vertical=0
	scroll.vertical_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED if main or vehicles else ScrollContainer.SCROLL_MODE_AUTO
	shell.body.add_theme_constant_override("separation",20 if main else 12)
	shell.back_button.position=Vector2(575,588) if credits else Vector2(256,656)
	shell.back_button.size=Vector2(400,68)
	shell.status.position=Vector2(778,680) if main else Vector2(280,630)
	shell.status.size=Vector2(950 if not main else 400,42)
	for tab in tabs:tab.queue_free()
	tabs.clear()
	if options:
		for i in range(3):
			var tab:=Neon.new();tab.tab_style=true;tab.toggle_mode=true;tab.text=["SONIDO","GRÁFICOS","PANTALLA"][i]
			tab.position=Vector2([256,596,937][i],88);tab.size=Vector2(319,68)
			canvas.add_child(tab);tab.pressed.connect(shell.show_options_page.bind(i));tabs.append(tab)

func select_tab(index: int) -> void:
	for i in range(tabs.size()):tabs[i].set_pressed_no_signal(i==index);tabs[i].queue_redraw()

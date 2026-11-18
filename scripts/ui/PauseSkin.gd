extends RefCounted
const Neon=preload("res://scripts/ui/NeonButton.gd")

static func backdrop(parent: Node) -> Control:
	var root:=Control.new();root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);parent.add_child(root)
	var picture:=TextureRect.new();picture.texture=preload("res://assets/ui/menu/backgorunds/Fondo main menu.png")
	picture.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;picture.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_COVERED
	picture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);picture.mouse_filter=Control.MOUSE_FILTER_IGNORE;root.add_child(picture)
	var shade:=ColorRect.new();shade.color=Color(.025,.008,.045,.76);shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);shade.mouse_filter=Control.MOUSE_FILTER_IGNORE;root.add_child(shade)
	root.mouse_filter=Control.MOUSE_FILTER_IGNORE
	return root

static func theme() -> Theme:
	var result:=Theme.new();result.default_font=Neon.arial();result.default_font_size=18
	result.set_color("font_color","Label",Color("e7fbff"))
	var field:=StyleBoxFlat.new();field.bg_color=Color("140c28");field.border_color=Color("00e5ee");field.set_border_width_all(1)
	field.content_margin_left=12;field.content_margin_right=25;field.content_margin_top=8;field.content_margin_bottom=8
	for state in ["normal","hover","pressed","focus"]:result.set_stylebox(state,"OptionButton",field)
	return result

static func panel_style() -> StyleBoxFlat:
	var style:=StyleBoxFlat.new();style.bg_color=Color(.025,.01,.055,.9);style.border_color=Color("00e5ee");style.set_border_width_all(2)
	style.content_margin_left=28;style.content_margin_right=28;style.content_margin_top=24;style.content_margin_bottom=24
	return style

static func button(caption: String, action: Callable) -> Button:
	var result:=Neon.new();result.compact=true;result.text=caption;result.pressed.connect(action)
	return result

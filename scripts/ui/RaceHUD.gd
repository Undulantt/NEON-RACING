extends Control
# Figma frame 39:2. Presentation reads the official session/standings only.
const FontSource=preload("res://scripts/ui/NeonButton.gd")
var activity: Node3D
var flow: Node
var block: Control
var time_label: Label
var lap_label: Label
var position_label: Label

func label_at(at: Vector2, width: float) -> Label:
	var label:=Label.new();label.position=at;label.size=Vector2(width,34)
	label.mouse_filter=Control.MOUSE_FILTER_IGNORE;label.clip_text=true
	label.add_theme_font_override("font",FontSource.arial(true))
	label.add_theme_font_size_override("font_size",24)
	label.add_theme_color_override("font_color",Color("f8f7fb"))
	block.add_child(label);return label

func picture(texture: Texture2D, at: Vector2, dimensions: Vector2) -> void:
	var image:=TextureRect.new();image.texture=texture
	image.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;image.position=at;image.size=dimensions
	image.mouse_filter=Control.MOUSE_FILTER_IGNORE;block.add_child(image)

func configure(target: Node3D) -> void:
	activity=target;name="RaceHUD";process_mode=Node.PROCESS_MODE_ALWAYS
	flow=get_node("/root/GameFlow")
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	block=Control.new();block.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(block)
	block.anchor_left=1;block.anchor_right=1;block.offset_left=-246;block.offset_right=0
	block.offset_top=0;block.offset_bottom=160
	time_label=label_at(Vector2(0,20),246)
	picture(preload("res://assets/ui/race/time_underline.svg"),Vector2(0,57),Vector2(357,4))
	picture(preload("res://assets/ui/race/time_terminal.svg"),Vector2(-2,61),Vector2(36,11))
	lap_label=label_at(Vector2(56,73),190)
	position_label=label_at(Vector2(56,112),190)
	refresh()

static func format_time(seconds: float) -> String:
	var hundredths:=maxi(0,floori(seconds*100.0)) if is_finite(seconds) else 0
	return "%02d.%02d.%02d"%[hundredths/6000,(hundredths/100)%60,hundredths%100]

func refresh() -> void:
	visible=is_instance_valid(activity) and activity.session!=null and flow.current_state==&"race" and not get_tree().paused
	if not visible:return
	var session=activity.session
	time_label.text="Tiempo: "+format_time(session.elapsed)
	lap_label.text="Vuelta:  %d/%d"%[session.current_lap(),session.total_laps] if int(activity.definition.get("laps",0))>0 else "Sin vueltas"
	var competition=activity.competition
	position_label.text="Pos: %d/%d"%[competition.player_place(),competition.racers.size()] if is_instance_valid(competition) and not competition.racers.is_empty() else "Pos: —"

func _process(_delta: float) -> void:refresh()

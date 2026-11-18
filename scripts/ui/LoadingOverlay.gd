extends CanvasLayer
var settle_ms := 0
var message: Label
var activity: Label
var frames := 0
var ticks := 0.0
var max_gap_ms := 0
var previous_ms := 0

func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	var background := ColorRect.new()
	background.color = Color("101a24")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var artwork:=TextureRect.new()
	artwork.texture=preload("res://assets/ui/menu/backgorunds/Pantalla de carga.png")
	artwork.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	artwork.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_COVERED
	artwork.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);background.add_child(artwork)
	var shade:=ColorRect.new();shade.color=Color(0,0,0,.62)
	shade.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE);shade.offset_top=-128;background.add_child(shade)
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	box.offset_left=42;box.offset_right=-42;box.offset_top=-116;box.offset_bottom=-12
	background.add_child(box)
	message = Label.new()
	message.add_theme_font_size_override("font_size",28)
	message.text = "Preparando La Paz…"
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(message)
	activity = Label.new()
	activity.add_theme_font_size_override("font_size",24)
	box.add_child(activity)
	previous_ms = Time.get_ticks_msec()

func _process(delta: float) -> void:
	frames += 1
	ticks += delta
	activity.text = ["◴","◷","◶","◵"][int(ticks*8)%4] + "  Cargando"
	var now := Time.get_ticks_msec()
	max_gap_ms = maxi(max_gap_ms,now-previous_ms)
	previous_ms = now

func stage(value: String) -> void:
	message.text = value

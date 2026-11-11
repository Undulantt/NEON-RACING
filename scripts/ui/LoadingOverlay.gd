extends CanvasLayer
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
	var box := VBoxContainer.new()
	box.position = Vector2(100,250)
	box.size = Vector2(1080,250)
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

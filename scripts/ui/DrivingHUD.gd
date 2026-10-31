extends CanvasLayer

var instruments: Control
var help_label: Label
var credits_label: Label
var car: CharacterBody3D
var world: Node3D
var speed_label: Label
var street_label: Label
var notice: Label
var pause_panel: PanelContainer
var pause_label: Label
var toast_time := 0.0
var menu_open := false
var turbo_bar: ProgressBar
var driving_label: Label
var drift_bar: ProgressBar
var drift_label: Label
var buttons: Array[Button] = []

func label(text_value: String, at: Vector2, size: int, color: Color = Color.WHITE) -> Label:
	var item := Label.new()
	item.text = text_value
	item.position = at
	item.add_theme_font_size_override("font_size", size)
	item.add_theme_color_override("font_color", color)
	item.add_theme_color_override("font_shadow_color", Color("101820"))
	item.add_theme_constant_override("shadow_offset_x", 2)
	item.add_theme_constant_override("shadow_offset_y", 2)
	add_child(item)
	return item

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	instruments = Control.new()
	instruments.set_script(preload("res://scripts/ui/DrivingInstruments.gd"))
	instruments.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(instruments)
	street_label = label("Sector de La Paz", Vector2(24, 244), 17)
	street_label.size = Vector2(260, 28)
	street_label.clip_text = true
	street_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	notice = label("", Vector2(24, 280), 16, Color("ffd38f"))
	speed_label = label("000", Vector2.ZERO, 46)
	driving_label = label("TURBO LISTO · SHIFT", Vector2.ZERO, 14, Color("36c5e2"))
	drift_label = label("ESPACIO · DERRAPE", Vector2.ZERO, 14, Color("ffd17a"))
	turbo_bar = ProgressBar.new()
	turbo_bar.max_value = 1.0
	turbo_bar.hide()
	add_child(turbo_bar)
	drift_bar = ProgressBar.new()
	drift_bar.max_value = 1.0
	drift_bar.hide()
	add_child(drift_bar)
	help_label = label("WASD / flechas conducir   ESPACIO derrape   SHIFT turbo   R recuperar   ESC pausa", Vector2.ZERO, 13, Color("c5ced2"))
	credits_label = label("© OpenStreetMap · Overture Maps Foundation · INEGI | Fuentes y licencias en créditos", Vector2.ZERO, 11, Color("b1bcc2"))
	pause_panel = PanelContainer.new()
	pause_panel.position = Vector2(430, 190)
	pause_panel.custom_minimum_size = Vector2(420, 290)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("152833")
	style.content_margin_left = 28
	style.content_margin_right = 28
	style.content_margin_top = 24
	style.content_margin_bottom = 24
	pause_panel.add_theme_stylebox_override("panel", style)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	pause_label = Label.new()
	pause_label.text = "PAUSA"
	pause_label.add_theme_font_size_override("font_size", 28)
	column.add_child(pause_label)
	var controls := Label.new()
	controls.text = "V cámara · C inspección · M sonido\nT prueba de velocidad ×2 · F8 ciudad\nF9 lugares · R recuperar vehículo"
	controls.add_theme_font_size_override("font_size", 14)
	column.add_child(controls)
	for entry in [["Continuar conduciendo", "resume"], ["Recuperar vehículo", "recover"], ["Volver al menú", "menu"]]:
		var button := Button.new()
		button.text = entry[0]
		button.custom_minimum_size.y = 42
		button.pressed.connect(_button.bind(entry[1]))
		column.add_child(button)
		buttons.append(button)
	pause_panel.add_child(column)
	add_child(pause_panel)
	pause_panel.hide()

func attach(target: CharacterBody3D, level: Node3D) -> void:
	car = target
	world = level
	instruments.car = car
	var effects := Control.new()
	effects.set_script(preload("res://scripts/ui/SpeedEffects.gd"))
	effects.car = car
	add_child(effects)
	move_child(effects, 0)
	car.recovered.connect(func(reason: String): show_notice("Vehículo recuperado · " + reason))

func show_notice(message: String) -> void:
	notice.text = message
	toast_time = 3.0

func set_pause(active: bool) -> void:
	get_tree().paused = active
	pause_panel.visible = active
	pause_label.text = "LA PAZ · MODO LIBRE" if menu_open else "PAUSA"
	buttons[0].text = "Continuar conduciendo"
	buttons[1].text = "Conducir desde inicio" if menu_open else "Recuperar vehículo"
	buttons[2].text = "Salir del juego" if menu_open else "Volver al menú"

func _button(action: String) -> void:
	match action:
		"resume":
			menu_open = false
			set_pause(false)
		"recover":
			if menu_open:
				car.safe_transform = car.spawn_transform
			menu_open = false
			set_pause(false)
			car.recover()
		"menu":
			if menu_open:
				get_tree().quit()
			else:
				menu_open = true
				set_pause(true)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		menu_open = false
		set_pause(not get_tree().paused)
		get_viewport().set_input_as_handled()
	if event.is_action_pressed("interact") and not get_tree().paused:
		show_notice("Modo libre · explora La Paz")

func _process(delta: float) -> void:
	if car == null:
		return
	var viewport_size := get_viewport().get_visible_rect().size
	var right := viewport_size.x - 330.0
	speed_label.position = Vector2(right + 122, viewport_size.y - 72)
	driving_label.position = Vector2(right + 40, viewport_size.y - 366)
	drift_label.position = Vector2(right + 40, viewport_size.y - 318)
	help_label.position = Vector2(24, viewport_size.y - 53)
	credits_label.position = Vector2(24, viewport_size.y - 30)
	pause_panel.position = (viewport_size - pause_panel.size) * 0.5
	speed_label.text = "%03d" % roundi(car.speed_mps * 3.6)
	turbo_bar.value = car.turbo_charge
	if car.drift_boost_active:
		drift_label.text = "IMPULSO · +%.1f km/h" % (float(car.config["drift_bonus_mps"]) * car.drift_boost_strength * 3.6)
		drift_bar.value = car.drift_boost_strength * car.drift_boost_time / float(car.config["drift_bonus_duration_s"])
	else:
		drift_bar.value = car.drift_charge
		if car.drift_charge >= float(car.config["drift_min_charge"]):
			drift_label.text = "LISTO %d%% · +%.1f km/h" % [roundi(car.drift_charge * 100), float(car.config["drift_bonus_mps"]) * car.drift_charge * 3.6]
		else:
			drift_label.text = "CARGANDO %d %%" % roundi(car.drift_charge * 100) if car.drift_tracking else "DERRAPA PARA CARGAR"
	driving_label.text = "TURBO ACTIVO" if car.turbo_active else "DERRAPE · %d°" % roundi(rad_to_deg(absf(car.slip_angle))) if car.drift_amount > 0.15 else "TURBO LISTO · SHIFT" if car.turbo_charge >= float(car.config["turbo_min_charge"]) else "TURBO RECARGANDO"
	if car.debug_speed_enabled:
		driving_label.text += " · PRUEBA ×2 · T"
	if car.turbo_exhausted:
		driving_label.text += " · suelta SHIFT"
	if car.feedback.muted:
		driving_label.text += " · M sonido apagado"
	street_label.text = car.street_name if not car.street_name.is_empty() else "Sector de La Paz"
	if not get_tree().paused:
		toast_time = maxf(0, toast_time - delta)
		if toast_time <= 0:
			notice.text = ""

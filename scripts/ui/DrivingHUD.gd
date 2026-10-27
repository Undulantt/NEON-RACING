extends CanvasLayer

var car: CharacterBody3D
var world: Node3D
var speed_label: Label
var street_label: Label
var notice: Label
var city_label: Label
var heading_label: Label
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
	for rect in [Rect2(12, 12, 470, 268), Rect2(12, 566, 850, 145)]:
		var background := ColorRect.new()
		background.position = rect.position
		background.size = rect.size
		background.color = Color(0.035, 0.065, 0.085, 0.82)
		background.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(background)
	heading_label = label("LA PAZ / CONDUCCIÓN LIBRE", Vector2(24, 20), 24)
	street_label = label("Paseo Álvaro Obregón", Vector2(24, 54), 18, Color("e2dcc9"))
	street_label.size = Vector2(446, 26)
	street_label.clip_text = true
	street_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	city_label = label("Ciudad B.6", Vector2(24, 86), 14, Color("d7d5ce"))
	speed_label = label("000 km/h", Vector2(24, 110), 42)
	notice = label("", Vector2(24, 170), 18, Color("ffd38f"))
	label("W / ↑ acelerar   S / ↓ frenar y reversa   A D / ← → girar", Vector2(24, 580), 16)
	label("ESPACIO derrape   SHIFT turbo   R recuperar   ESC pausa", Vector2(24, 610), 16)
	label("V cámara   C inspección   M silenciar   T velocidad/aceleración ×2", Vector2(24, 638), 15)
	driving_label = label("TURBO LISTO", Vector2(24, 205), 18, Color("72e0ff"))
	turbo_bar = ProgressBar.new()
	turbo_bar.position = Vector2(24, 240)
	turbo_bar.size = Vector2(320, 12)
	turbo_bar.max_value = 1.0
	turbo_bar.show_percentage = false
	turbo_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color("55d9ff")
	fill.corner_radius_top_left = 4
	fill.corner_radius_bottom_left = 4
	fill.corner_radius_top_right = 4
	fill.corner_radius_bottom_right = 4
	turbo_bar.add_theme_stylebox_override("fill", fill)
	add_child(turbo_bar)
	build_drift_meter()
	label("© OpenStreetMap contributors · Overture Maps Foundation · INEGI", Vector2(24, 666), 13, Color("d7d5ce"))
	label("C · conducción arcade · alturas estimadas · datos abiertos · fuentes y licencias en créditos", Vector2(24, 690), 13, Color("d7d5ce"))
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

func build_drift_meter() -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	panel.offset_left = -370
	panel.offset_right = -12
	panel.offset_top = 12
	panel.offset_bottom = 150
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.065, 0.085, 0.9)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	panel.add_theme_stylebox_override("panel", style)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 6)
	var title := Label.new()
	title.text = "DERRAPE → IMPULSO"
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color("ffd17a"))
	column.add_child(title)
	drift_label = Label.new()
	drift_label.add_theme_font_size_override("font_size", 18)
	column.add_child(drift_label)
	drift_bar = ProgressBar.new()
	drift_bar.max_value = 1.0
	drift_bar.show_percentage = false
	drift_bar.custom_minimum_size = Vector2(320, 16)
	drift_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color("ffbb55")
	drift_bar.add_theme_stylebox_override("fill", fill)
	var track := StyleBoxFlat.new()
	track.bg_color = Color("263743")
	track.border_color = Color("7d6444")
	track.set_border_width_all(1)
	drift_bar.add_theme_stylebox_override("background", track)
	column.add_child(drift_bar)
	var hint := Label.new()
	hint.text = "Sostén el derrape y endereza al salir"
	hint.add_theme_font_size_override("font_size", 14)
	column.add_child(hint)
	panel.add_child(column)
	add_child(panel)

func attach(target: CharacterBody3D, level: Node3D) -> void:
	car = target
	world = level
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
	if world != null and world.city_manager != null:
		city_label.text = "Ciudad: %s · %d/%d sectores · F8 · F9 lugares" % ["ACTIVA" if world.city_manager.city_enabled else "DESACTIVADA", world.city_manager.loaded.size(), world.city_manager.manifest["chunks"].size()]
	else:
		city_label.text = "Ciudad: referencia de fase B"
	heading_label.text = "LA PAZ / " + world.current_block_name()
	speed_label.text = "%03d km/h%s" % [roundi(car.speed_mps * 3.6), "  R" if car.signed_speed < -0.2 else ""]
	turbo_bar.value = car.turbo_charge
	if car.drift_boost_active:
		drift_label.text = "IMPULSO DE SALIDA · +%.1f km/h" % (float(car.config["drift_bonus_mps"]) * car.drift_boost_strength * 3.6)
		drift_bar.value = car.drift_boost_strength * car.drift_boost_time / float(car.config["drift_bonus_duration_s"])
	else:
		drift_bar.value = car.drift_charge
		if car.drift_charge >= float(car.config["drift_min_charge"]):
			drift_label.text = "LISTO %d %% · +%.1f km/h" % [roundi(car.drift_charge * 100), float(car.config["drift_bonus_mps"]) * car.drift_charge * 3.6]
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
			notice.text = "Superficie de prueba · velocidad reducida" if not car.on_asphalt else ""

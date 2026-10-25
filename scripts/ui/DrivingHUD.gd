extends CanvasLayer

var car: CharacterBody3D
var world: Node3D
var speed_label: Label
var street_label: Label
var notice: Label
var city_label: Label
var pause_panel: PanelContainer
var pause_label: Label
var toast_time := 0.0
var menu_open := false
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
	for rect in [Rect2(12, 12, 470, 205), Rect2(12, 566, 850, 145)]:
		var background := ColorRect.new()
		background.position = rect.position
		background.size = rect.size
		background.color = Color(0.035, 0.065, 0.085, 0.82)
		background.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(background)
	label("LA PAZ / CONDUCCIÓN LIBRE", Vector2(24, 20), 24)
	street_label = label("Paseo Álvaro Obregón", Vector2(24, 54), 18, Color("e2dcc9"))
	city_label = label("Ciudad B.6", Vector2(24, 86), 14, Color("d7d5ce"))
	speed_label = label("000 km/h", Vector2(24, 110), 42)
	notice = label("", Vector2(24, 170), 18, Color("ffd38f"))
	label("W / ↑ acelerar   S / ↓ frenar y reversa   A D / ← → girar", Vector2(24, 580), 16)
	label("ESPACIO freno de mano   R recuperar   ESC pausa   C inspección aérea", Vector2(24, 610), 16)
	label("© OpenStreetMap contributors · Overture Maps Foundation · INEGI", Vector2(24, 658), 13, Color("d7d5ce"))
	label("B.6 · alturas estimadas · datos abiertos · fuentes y licencias en créditos", Vector2(24, 686), 13, Color("d7d5ce"))
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

func attach(target: CharacterBody3D, level: Node3D) -> void:
	car = target
	world = level
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
	speed_label.text = "%03d km/h%s" % [roundi(car.speed_mps * 3.6), "  R" if car.signed_speed < -0.2 else ""]
	street_label.text = car.street_name if not car.street_name.is_empty() else "Sector de La Paz"
	if not get_tree().paused:
		toast_time = maxf(0, toast_time - delta)
		if toast_time <= 0:
			notice.text = "Superficie de prueba · velocidad reducida" if not car.on_asphalt else ""

extends Control

const Profiles = preload("res://scripts/driving/VehicleProfiles.gd")
const STAT_LABELS := {"speed": "Velocidad máxima", "acceleration": "Aceleración", "handling": "Manejo", "braking": "Frenado", "drift": "Derrape", "turbo": "Turbo", "drift_boost": "Impulso de derrape", "burst": "BURST"}
var body: VBoxContainer
var heading: Label
var status: Label
var back_button: Button
var buttons: Dictionary = {}
var vehicle_buttons: Dictionary = {}
var stat_values: Dictionary = {}
var sliders: Dictionary = {}
var volume_labels: Dictionary = {}
var display_choice: OptionButton
var size_choice: OptionButton
var current_view: StringName

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var theme_resource := Theme.new()
	theme_resource.default_font_size = 18
	theme = theme_resource
	var background := ColorRect.new()
	background.color = Color("101a24")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 32)
	add_child(margin)
	var frame := VBoxContainer.new()
	frame.add_theme_constant_override("separation", 18)
	margin.add_child(frame)
	var header := HBoxContainer.new()
	frame.add_child(header)
	heading = Label.new()
	heading.add_theme_font_size_override("font_size", 32)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(heading)
	back_button = Button.new()
	back_button.text = "Volver"
	back_button.custom_minimum_size = Vector2(130, 44)
	back_button.pressed.connect(GameFlow.go_back)
	header.add_child(back_button)
	status = Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.add_theme_color_override("font_color", Color("e9bc7d"))
	frame.add_child(status)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	frame.add_child(scroll)
	body = VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 14)
	scroll.add_child(body)
	var footer := Label.new()
	footer.text = "NEON RACING LP  ·  La Paz, B.C.S."
	footer.add_theme_font_size_override("font_size", 13)
	footer.add_theme_color_override("font_color", Color("9faeb8"))
	frame.add_child(footer)
	GameFlow.state_changed.connect(render)
	GameFlow.vehicle_changed.connect(_refresh_vehicle_selection)
	GameFlow.settings_changed.connect(_sync_options)
	render(GameFlow.current_state)

func text(value: String, parent: Node = null, font_size := 18) -> Label:
	var item := Label.new()
	item.text = value
	item.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	item.add_theme_font_size_override("font_size", font_size)
	(parent if parent != null else body).add_child(item)
	return item

func button(id: String, caption: String, action: Callable, parent: Node = null) -> Button:
	var item := Button.new()
	item.name = id
	item.text = caption
	item.custom_minimum_size.y = 48
	item.pressed.connect(action)
	(parent if parent != null else body).add_child(item)
	buttons[id] = item
	return item

func render(state: StringName) -> void:
	current_view = state
	for node in body.get_children():
		body.remove_child(node)
		node.queue_free()
	buttons.clear()
	vehicle_buttons.clear()
	stat_values.clear()
	sliders.clear()
	volume_labels.clear()
	display_choice = null
	size_choice = null
	status.text = GameFlow.navigation_error
	status.visible = not status.text.is_empty()
	back_button.visible = state not in [&"main_menu", &"loading"]
	back_button.disabled = GameFlow.transition_busy
	match state:
		&"main_menu":
			heading.text = GameFlow.definition["title"]
			text("Carreras arcade en La Paz", null, 24)
			button("play", "Jugar", GameFlow.show_screen.bind(&"play_menu"))
			button("how", "Cómo jugar", GameFlow.show_screen.bind(&"how_to_play"))
			button("options", "Opciones", GameFlow.show_screen.bind(&"options"))
			button("credits", "Créditos", GameFlow.show_screen.bind(&"credits"))
			var quit := button("quit", "Salir", GameFlow.quit_game)
			quit.visible = not OS.has_feature("web")
		&"play_menu":
			heading.text = "Jugar"
			button("free_drive", "Modo libre", GameFlow.choose_mode.bind(&"free_drive"))
			button("race", "Modo carrera", GameFlow.choose_mode.bind(&"race"))
			text("Elige un modo y después tu vehículo. El modo carrera inicia el recorrido predeterminado en solitario.")
		&"vehicle_select": _vehicles()
		&"how_to_play": _how_to_play()
		&"options": _options()
		&"credits": _credits()
		&"race_pending":
			heading.text = "Modo carrera · pendiente de D.2"
			text("Todavía no hay una carrera jugable. La selección está preparada para el sistema de carreras.", null, 24)
			text("Vehículo: " + GameFlow.selected_vehicle_id)
			if GameFlow.race_origin == &"menu":
				button("change_vehicle", "Cambiar vehículo", GameFlow.show_screen.bind(&"vehicle_select"))
			button("activity_return", "Volver al modo libre" if GameFlow.return_destination == &"free_drive" else "Volver al menú principal", GameFlow.cancel_activity)
		&"results": _results()
		&"loading":
			heading.text = "Cargando"
			text("Preparando el sector de La Paz…", null, 26)
			text("Vehículo: " + GameFlow.selected_vehicle_id)
		_:
			heading.text = GameFlow.definition["title"]
	if not buttons.is_empty():
		_focus_first.call_deferred()

func _focus_first() -> void:
	# A view can be replaced again before a deferred focus request executes.
	if not is_inside_tree() or is_queued_for_deletion() or buttons.is_empty():
		return
	var first: Button = buttons.values()[0]
	if is_instance_valid(first) and first.is_inside_tree() and first.is_visible_in_tree():
		first.grab_focus()

func _vehicles() -> void:
	heading.text = "Seleccionar vehículo · " + ("Modo libre" if GameFlow.selected_mode == &"free_drive" else "Modo carrera")
	text("Compara los perfiles actuales de la beta. Índices 1–10 calculados desde los parámetros de conducción.")
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 5)
	body.add_child(grid)
	var stat_header := text("Estadística", grid, 20)
	stat_header.custom_minimum_size.x = 180
	stat_header.autowrap_mode = TextServer.AUTOWRAP_OFF
	for id in Profiles.IDS:
		var profile: Dictionary = Profiles.load_profile(id)
		var column := VBoxContainer.new()
		column.custom_minimum_size.x = 180
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(column)
		text(id + " · " + str(profile["role"]), column, 21)
		text("%.0f km/h · 0–100: %.1f s\nObjetivo de configuración" % [float(profile["config"]["max_forward_speed_mps"]) * 3.6, profile["config"]["target_0_100_s"]], column, 14)
		var choose := button("vehicle_" + id, "Elegir " + id, GameFlow.select_vehicle.bind(id), column)
		choose.toggle_mode = true
		vehicle_buttons[id] = choose
	for key in STAT_LABELS:
		var stat_label := text(STAT_LABELS[key], grid, 17)
		stat_label.custom_minimum_size.x = 180
		stat_label.autowrap_mode = TextServer.AUTOWRAP_OFF
		for id in Profiles.IDS:
			var value: int = Profiles.load_profile(id)["stats"][key]
			stat_values[id + ":" + key] = value
			var cell := text("%d / 10" % value, grid, 18)
			cell.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text("Los tres perfiles utilizan por ahora la carrocería compartida del prototipo.", null, 15)
	button("continue", "Entrar al modo libre" if GameFlow.selected_mode == &"free_drive" else "Continuar a modo carrera", GameFlow.start_selected)
	_refresh_vehicle_selection(GameFlow.selected_vehicle_id)

func _refresh_vehicle_selection(id: String) -> void:
	if current_view != &"vehicle_select":
		return
	for key in vehicle_buttons:
		var item: Button = vehicle_buttons[key]
		item.set_pressed_no_signal(key == id)
		item.text = ("Seleccionado: " if key == id else "Elegir ") + key

func _how_to_play() -> void:
	heading.text = "Cómo jugar"
	text("Conducción", null, 24)
	text("W / ↑: acelerar\nS / ↓: frenar y, al detenerte, reversa\nA, D / ←, →: girar\nEspacio: freno de mano y derrape\nShift: turbo\nR: recuperar el vehículo tras 3 segundos (último checkpoint en carrera)\nEsc: pausa; en modo libre abre el mapa para elegir destino\nV: cámara cerca/lejos · C: inspección aérea\nM: silenciar motor y efectos del coche · F7: mezcla de audio")
	text("Mando", null, 24)
	text("RT acelerar · LT frenar · stick izquierdo girar · A derrape · X turbo · Y recuperar · Start pausa. En los menús: dirección, aceptar y volver.")
	text("Mecánicas disponibles", null, 24)
	text("Derrapa con suficiente velocidad y termina una salida limpia para recibir impulso de derrape. El turbo consume su reserva y se recarga. BURST se prepara manteniendo la aceleración cerca de la velocidad base; el indicador muestra su entrada y recuperación. El cambio de marchas es automático.")
	text("Puedes explorar el mundo en modo libre. E / mando B junto a la salida permite confirmar una carrera. Sigue los controles en orden y completa las vueltas indicadas en los circuitos; Esc permite reiniciar o abandonar. Los rivales se integrarán en D.3; las interacciones turísticas de Pasaporte La Paz en D.4.", null, 16)
	if preload("res://scripts/racing/RaceEditor.gd").available(): text("Desarrollo: Ctrl + Alt + E abre el editor de sprints desde modo libre.", null, 16)

func _options() -> void:
	heading.text = "Opciones"
	text("Audio", null, 24)
	for bus in ["Master", "Music", "Engine", "Effects"]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 20)
		body.add_child(row)
		var title := text({"Master":"General", "Music":"Música", "Engine":"Motor", "Effects":"Efectos y ambiente"}[bus], row)
		title.custom_minimum_size.x = 210
		var slider := HSlider.new()
		slider.min_value = 0
		slider.max_value = 1
		slider.step = 0.01
		slider.custom_minimum_size = Vector2(240, 40)
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.value = GameFlow.volumes[bus]
		row.add_child(slider)
		sliders[bus] = slider
		var percentage := text("%d%%" % roundi(slider.value * 100), row)
		percentage.custom_minimum_size = Vector2(64, 40)
		percentage.autowrap_mode = TextServer.AUTOWRAP_OFF
		percentage.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		percentage.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		volume_labels[bus] = percentage
		slider.value_changed.connect(func(value: float): GameFlow.set_volume(bus, value))
	text("Los cambios de volumen se guardan y se comparten con la mezcla F7 del juego.", null, 15)
	text("Pantalla", null, 24)
	display_choice = OptionButton.new()
	for title in ["Ventana", "Ventana sin bordes", "Pantalla completa"]:
		display_choice.add_item(title)
	display_choice.select(["windowed", "borderless", "fullscreen"].find(GameFlow.screen_mode))
	display_choice.item_selected.connect(func(index: int): GameFlow.set_display(["windowed", "borderless", "fullscreen"][index], GameFlow.window_size))
	body.add_child(display_choice)
	text("Tamaño de ventana", null, 17)
	size_choice = OptionButton.new()
	for size in [Vector2i(1280,720), Vector2i(1600,900), Vector2i(1920,1080)]:
		size_choice.add_item("%d × %d" % [size.x, size.y])
	size_choice.select([Vector2i(1280,720),Vector2i(1600,900),Vector2i(1920,1080)].find(GameFlow.window_size))
	size_choice.item_selected.connect(func(index: int): GameFlow.set_display(GameFlow.screen_mode, [Vector2i(1280,720),Vector2i(1600,900),Vector2i(1920,1080)][index]))
	body.add_child(size_choice)
	if DisplayServer.get_name() == "headless":
		text("La configuración de pantalla requiere una ejecución con ventana.", null, 15)
	_sync_options()

func _sync_options() -> void:
	if current_view != &"options":
		return
	for bus in sliders:
		sliders[bus].set_value_no_signal(GameFlow.volumes[bus])
		volume_labels[bus].text = "%d%%" % roundi(float(GameFlow.volumes[bus]) * 100)
	if is_instance_valid(display_choice):
		display_choice.select(["windowed", "borderless", "fullscreen"].find(GameFlow.screen_mode))
		size_choice.select([Vector2i(1280,720),Vector2i(1600,900),Vector2i(1920,1080)].find(GameFlow.window_size))
		display_choice.disabled = DisplayServer.get_name() == "headless"
		size_choice.disabled = DisplayServer.get_name() == "headless" or GameFlow.screen_mode == "fullscreen"

func _credits() -> void:
	heading.text = "Créditos"
	var data: Dictionary = GameFlow.definition["credits"]
	text(data["project"], null, 25)
	text(data["description"])
	for person in data.get("contributors", []):
		text(str(person.get("name", "")) + " · " + str(person.get("contribution", "")))
	text("Fuentes, atribuciones y licencias", null, 23)
	var source := str(data["licenses_file"])
	var licenses := RichTextLabel.new()
	licenses.bbcode_enabled = false
	licenses.fit_content = true
	licenses.scroll_active = false
	licenses.text = FileAccess.get_file_as_string(source) if FileAccess.file_exists(source) else "No se pudo abrir la información de licencias."
	licenses.add_theme_font_size_override("normal_font_size", 15)
	body.add_child(licenses)

func _results() -> void:
	heading.text = "Resultados"
	text("Vehículo: " + GameFlow.selected_vehicle_id, null, 23)
	var result: Dictionary = GameFlow.activity_result
	if result.has("summary"):
		text(str(result["summary"]))
	if result.has("position"):
		text("Posición: " + str(result["position"]))
	if result.has("elapsed_seconds"):
		text("Tiempo: %.3f s" % float(result["elapsed_seconds"]))
	button("activity_return", "Volver al modo libre" if GameFlow.return_destination == &"free_drive" else "Volver al menú principal", GameFlow.return_from_activity)

func _unhandled_input(event: InputEvent) -> void:
	if (event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause")) and not event.is_echo():
		GameFlow.go_back()
		get_viewport().set_input_as_handled()

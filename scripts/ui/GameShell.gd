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
var presentation: Control
var option_pages: Array=[]
var options_page:=0
var graphic_controls: Dictionary={}
var licenses_open:=false
var current_view: StringName

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	presentation=preload("res://scripts/ui/MenuPresentation.gd").new()
	add_child(presentation);presentation.configure(self)
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
	var item := preload("res://scripts/ui/NeonButton.gd").new()
	item.compact=parent!=null
	item.name = id
	item.text = caption.to_upper()
	item.custom_minimum_size.y = 48 if parent!=null else 68
	item.pressed.connect(action)
	(parent if parent != null else body).add_child(item)
	buttons[id] = item
	return item

func render(state: StringName) -> void:
	current_view = state
	presentation.set_view(state)
	option_pages.clear();graphic_controls.clear()
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
			text("Elige un modo y después tu vehículo. El modo carrera inicia un circuito de dos vueltas con cinco rivales.")
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
	_focus_first.call_deferred()
	if is_instance_valid(GameFlow.menu_audio):
		GameFlow.menu_audio.bind_tree(self)
		GameFlow.menu_audio.bind_shell(self)

func _focus_first() -> void:
	# A view can be replaced again before a deferred focus request executes.
	if not is_inside_tree() or is_queued_for_deletion():
		return
	if current_view==&"options" and not presentation.tabs.is_empty():
		presentation.tabs[options_page].grab_focus();return
	for first in buttons.values():
		if is_instance_valid(first) and first.is_inside_tree() and first.is_visible_in_tree():
			first.grab_focus();return
	if back_button.visible:back_button.grab_focus()

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
	text("COMET utiliza el modelo 3D del equipo; VECTOR y APEX conservan la carrocería del prototipo.", null, 15)
	if GameFlow.selected_mode==&"race":
		text("Dificultad de los rivales",null,20)
		var difficulty:=OptionButton.new()
		difficulty.name="RivalDifficulty"
		difficulty.add_item("Estándar")
		difficulty.add_item("Experto")
		difficulty.select(1 if GameFlow.rival_difficulty=="expert" else 0)
		difficulty.item_selected.connect(func(index: int):GameFlow.set_rival_difficulty("expert" if index==1 else "standard"))
		body.add_child(difficulty)
		text("Experto: mayor ritmo y frenadas más exigentes. Estándar: más margen para aprender el circuito.",null,15)
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
	text("Puedes explorar el mundo en modo libre. E / mando B junto a la salida permite confirmar una carrera. Sigue los controles en orden y completa las vueltas indicadas en los circuitos; Esc permite reiniciar o abandonar. Compite contra cinco rivales con distintas personalidades. En modo libre, P abre Pasaporte La Paz; E registra los lugares al detenerte en su aproximación vial.", null, 16)
	if preload("res://scripts/racing/RaceEditor.gd").available(): text("Desarrollo: Ctrl + Alt + E abre el editor de recorridos desde modo libre.", null, 16)

func _options() -> void:
	heading.text="OPCIONES"
	for i in range(3):
		var page:=VBoxContainer.new();page.add_theme_constant_override("separation",12);body.add_child(page);option_pages.append(page)
	_audio_options(option_pages[0]);_graphics_options(option_pages[1]);_display_options(option_pages[2])
	show_options_page(options_page);_sync_options()

func show_options_page(index: int) -> void:
	options_page=clampi(index,0,2)
	for i in range(option_pages.size()):option_pages[i].visible=i==options_page
	presentation.select_tab(options_page)

func _audio_options(parent: VBoxContainer) -> void:
	text("Audio", parent, 24)
	for bus in ["Master", "Music", "Engine", "Effects"]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 20)
		parent.add_child(row)
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
	text("Los cambios de volumen se guardan y se comparten con la mezcla F7 del juego.", parent, 15)

func _display_options(parent: VBoxContainer) -> void:
	text("Pantalla", parent, 24)
	display_choice = OptionButton.new()
	for title in ["Ventana", "Ventana sin bordes", "Pantalla completa"]:
		display_choice.add_item(title)
	display_choice.select(["windowed", "borderless", "fullscreen"].find(GameFlow.screen_mode))
	display_choice.item_selected.connect(func(index: int): GameFlow.set_display(["windowed", "borderless", "fullscreen"][index], GameFlow.window_size))
	parent.add_child(display_choice)
	text("Tamaño de ventana", parent, 17)
	size_choice = OptionButton.new()
	for size in [Vector2i(1280,720), Vector2i(1600,900), Vector2i(1920,1080)]:
		size_choice.add_item("%d × %d" % [size.x, size.y])
	size_choice.select([Vector2i(1280,720),Vector2i(1600,900),Vector2i(1920,1080)].find(GameFlow.window_size))
	size_choice.item_selected.connect(func(index: int): GameFlow.set_display(GameFlow.screen_mode, [Vector2i(1280,720),Vector2i(1600,900),Vector2i(1920,1080)][index]))
	parent.add_child(size_choice)
	if DisplayServer.get_name() == "headless":
		text("La configuración de pantalla requiere una ejecución con ventana.", parent, 15)

func _graphics_options(parent: VBoxContainer) -> void:
	text("Ajusta los efectos según el rendimiento de tu equipo.",parent,20)
	for entry in [["optical_mode","Reflejos y referencias de velocidad",["Desactivados","Reducidos","Completos"]],["smoke_quality","Cantidad de humo y huellas",["Baja","Normal","Alta"]]]:
		var row:=HBoxContainer.new();parent.add_child(row)
		var title:=text(entry[1],row);title.custom_minimum_size.x=480
		var choice:=OptionButton.new();choice.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		for caption in entry[2]:choice.add_item(caption)
		row.add_child(choice);graphic_controls[entry[0]]=choice
		var key: String=entry[0]
		choice.item_selected.connect(func(index: int):GameFlow.set_graphics(key,["original","partial","full"][index] if key=="optical_mode" else index))
	for entry in [["clouds_enabled","Nubes neón"],["smoke_enabled","Humo de derrape"],["marks_enabled","Huellas de neumáticos"],["burst_enabled","Carrocería y estelas BURST"]]:
		var toggle:=CheckBox.new();toggle.text=entry[1];toggle.custom_minimum_size.y=36;parent.add_child(toggle);graphic_controls[entry[0]]=toggle
		var key: String=entry[0]
		toggle.toggled.connect(func(value: bool):GameFlow.set_graphics(key,value))
	text("Los cambios se guardan automáticamente. Reducir efectos puede mejorar el rendimiento; la conducción permanece igual.",parent,16)
	button("graphics_reset","Restaurar gráficos",GameFlow.reset_graphics,parent)

func _sync_options() -> void:
	if current_view != &"options":
		return
	for key in graphic_controls:
		var control=graphic_controls[key]
		if control is CheckBox:control.set_pressed_no_signal(GameFlow.graphics[key])
		elif key=="optical_mode":control.select(["original","partial","full"].find(GameFlow.graphics[key]))
		else:control.select(GameFlow.graphics[key])
	for bus in sliders:
		sliders[bus].set_value_no_signal(GameFlow.volumes[bus])
		volume_labels[bus].text = "%d%%" % roundi(float(GameFlow.volumes[bus]) * 100)
	if is_instance_valid(display_choice):
		display_choice.select(["windowed", "borderless", "fullscreen"].find(GameFlow.screen_mode))
		size_choice.select([Vector2i(1280,720),Vector2i(1600,900),Vector2i(1920,1080)].find(GameFlow.window_size))
		display_choice.disabled = DisplayServer.get_name() == "headless"
		size_choice.disabled = DisplayServer.get_name() == "headless" or GameFlow.screen_mode == "fullscreen"

func _credits() -> void:
	heading.text="CRÉDITOS"
	var data: Dictionary=GameFlow.definition["credits"]
	if licenses_open:
		var licenses:=RichTextLabel.new();licenses.fit_content=true;licenses.scroll_active=false
		licenses.text=FileAccess.get_file_as_string(data["licenses_file"]);licenses.add_theme_font_size_override("normal_font_size",15);body.add_child(licenses)
	else:
		var lines: Array[String]=[]
		for person in data.get("contributors",[]):lines.append(str(person["contribution"])+"\n"+str(person["name"]))
		var names:=text("\n\n".join(lines),null,24)
		names.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		names.add_theme_font_override("font",preload("res://scripts/ui/NeonButton.gd").arial(true));names.custom_minimum_size.y=280
	var link:=LinkButton.new();link.text="Volver a colaboradores" if licenses_open else "Fuentes, atribuciones y licencias"
	link.add_theme_font_size_override("font_size",15);body.add_child(link)
	link.pressed.connect(func():licenses_open=not licenses_open;render(&"credits"))

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

extends CanvasLayer
var world: Node3D
var hud: CanvasLayer
var frame: Control
var map: Control
var destination_label: Label
var menu_buttons: Dictionary = {}

func configure(target: Node3D, driving_hud: CanvasLayer) -> void:
	world = target
	hud = driving_hud
	layer = 60
	process_mode = Node.PROCESS_MODE_ALWAYS
	frame = Control.new()
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(frame)
	var background := ColorRect.new()
	background.color = Color(0.025,0.035,0.045,1.0)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left","right","top","bottom"]: margin.add_theme_constant_override("margin_"+side,28)
	frame.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation",14)
	margin.add_child(column)
	var title := Label.new()
	title.text = "NEON RACING LP     /     MODO LIBRE — PAUSA"
	title.add_theme_font_size_override("font_size",28)
	column.add_child(title)
	var tabs := Label.new()
	tabs.text = "MAPA     /     DESTINO"
	tabs.add_theme_font_size_override("font_size",20)
	tabs.add_theme_color_override("font_color",Color("49c8ff"))
	column.add_child(tabs)
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation",22)
	column.add_child(row)
	map = preload("res://scripts/ui/PauseRoadMap.gd").new()
	map.world = world
	map.custom_minimum_size = Vector2(580,390)
	map.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_child(map)
	var sidebar := VBoxContainer.new()
	sidebar.custom_minimum_size.x = 285
	sidebar.add_theme_constant_override("separation",12)
	row.add_child(sidebar)
	destination_label = Label.new()
	destination_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	destination_label.custom_minimum_size.y = 95
	sidebar.add_child(destination_label)
	for entry in [["resume","Continuar",hud._button.bind("resume")],["center","Centrar en jugador",map.recenter],["race","Destino: salida de carrera",_race_destination],["clear","Borrar destino",_clear],["recover","Recuperar · 3 segundos",hud._button.bind("recover")],["menu","Menú principal",hud._button.bind("menu")]]:
		var button := Button.new()
		button.text = entry[1]
		button.custom_minimum_size.y = 43
		button.pressed.connect(entry[2])
		sidebar.add_child(button)
		menu_buttons[entry[0]] = button
	var legend := Label.new()
	legend.text = "Clic: elegir destino   ·   Rueda: zoom   ·   Arrastrar con botón central/derecho: mover   ·   Esc / Start / B: continuar\nNorte arriba · Amarillo: jugador · Rosa: carrera / destino · Naranja: ruta vial · © OpenStreetMap"
	legend.add_theme_font_size_override("font_size",14)
	column.add_child(legend)
	hide()

func open() -> void:
	show()
	map.recenter()
	_update_status()
	menu_buttons["resume"].grab_focus()

func _update_status() -> void:
	if world.navigation == null: return
	destination_label.text = world.navigation.status
	if not world.navigation.destination_id.is_empty():
		destination_label.text += "\nDestino X %.0f · Z %.0f m" % [world.navigation.destination.x,world.navigation.destination.y]
	menu_buttons["race"].disabled = world.race_activity == null or world.race_activity.default_race.is_empty()

func _process(_delta: float) -> void:
	if visible: _update_status()

func _race_destination() -> void:
	var start: Array = world.race_activity.default_race["start"]["position_xz"]
	world.navigation.set_destination(Vector2(start[0],start[1]))
	map.queue_redraw()

func _clear() -> void:
	world.navigation.clear_destination()
	map.queue_redraw()

func _input(event: InputEvent) -> void:
	if visible and (event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel")) and not event.is_echo():
		hud.set_pause(false)
		get_viewport().set_input_as_handled()

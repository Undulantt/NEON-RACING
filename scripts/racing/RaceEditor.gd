extends Control
const Store = preload("res://scripts/racing/RaceStore.gd")
var world: Node3D
var graph: RefCounted
var anchors: Array = []
var draft: Dictionary = {}
var center := Vector2.ZERO
var zoom := 0.6
var id_field: LineEdit
var title_field: LineEdit
var spacing: SpinBox
var exception: CheckBox
var selected: SpinBox
var edit_mode: OptionButton
var notice: Label
var race_kind: OptionButton
var laps_count: SpinBox
var draft_error := ""
var write_buttons: Array[Button] = []
var dragging := false

static func available() -> bool:
	return OS.has_feature("editor") and OS.is_debug_build()

func _ready() -> void:
	if not available():
		queue_free()
		return
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	center = Vector2(world.player.position.x,world.player.position.z)
	world.player.driving_enabled = false
	var panel := PanelContainer.new()
	panel.position = Vector2(12,12)
	panel.size = Vector2(1256,255)
	add_child(panel)
	var column := VBoxContainer.new()
	panel.add_child(column)
	var heading := Label.new()
	heading.text = "CREAR CARRERA · Ctrl + Alt + E cerrar · rueda: zoom · botón central: desplazar"
	column.add_child(heading)
	var help := Label.new()
	help.text = "1. Elige tipo y nombre.  2. Haz clic sobre las calles para colocar puntos.  3. Guarda o prueba cuando el trazado aparezca en cian.\nSin vueltas: salida → pasos → meta. Con vueltas: al menos 3 puntos; el editor conecta el último con la salida."
	help.add_theme_font_size_override("font_size",15)
	column.add_child(help)
	var fields := HBoxContainer.new()
	column.add_child(fields)
	id_field = LineEdit.new()
	id_field.placeholder_text = "identificador_unico"
	id_field.text = "carrera_"+Crypto.new().generate_random_bytes(8).hex_encode()
	id_field.custom_minimum_size.x = 230
	fields.add_child(id_field)
	title_field = LineEdit.new()
	title_field.text = "Nueva carrera"
	title_field.placeholder_text = "Nombre de la carrera"
	title_field.custom_minimum_size.x = 240
	fields.add_child(title_field)
	spacing = SpinBox.new()
	spacing.min_value = 10
	spacing.max_value = 80
	spacing.value = 30
	spacing.suffix = "m entre controles"
	spacing.custom_minimum_size.x = 220
	fields.add_child(spacing)
	spacing.value_changed.connect(func(_v): rebuild())
	exception = CheckBox.new()
	exception.text = "Excepción ficticia: contrasentido"
	fields.add_child(exception)
	exception.toggled.connect(func(_v): rebuild())
	var format_row := HBoxContainer.new()
	column.add_child(format_row)
	race_kind = OptionButton.new()
	race_kind.add_item("Sin vueltas · Sprint A → B")
	race_kind.add_item("Con vueltas · Circuito cerrado")
	format_row.add_child(race_kind)
	laps_count = SpinBox.new()
	laps_count.min_value = 1
	laps_count.max_value = 99
	laps_count.value = 3
	laps_count.suffix = "vueltas"
	laps_count.editable = false
	laps_count.custom_minimum_size.x = 150
	laps_count.tooltip_text = "Sólo se aplica a circuitos. Un sprint termina en la meta, sin repetir vueltas."
	format_row.add_child(laps_count)
	var actions := HBoxContainer.new()
	column.add_child(actions)
	edit_mode = OptionButton.new()
	for title in ["Añadir salida / paso / meta","Mover punto seleccionado","Eliminar punto seleccionado"]: edit_mode.add_item(title)
	actions.add_child(edit_mode)
	selected = SpinBox.new()
	selected.min_value = 0
	selected.max_value = 999
	selected.suffix = "índice de punto"
	selected.custom_minimum_size.x = 170
	actions.add_child(selected)
	for entry in [["Deshacer último",undo],["Eliminar seleccionado",delete_selected]]:
		var button := Button.new()
		button.text = entry[0]
		button.pressed.connect(entry[1])
		actions.add_child(button)
	var files := HBoxContainer.new()
	column.add_child(files)
	for entry in [["Guardar local",save_local],["Cargar ID",load_draft],["Publicar contenido",publish],["Probar",test_drive],["Cerrar",close]]:
		var button := Button.new()
		button.text = entry[0]
		button.pressed.connect(entry[1])
		files.add_child(button)
		if entry[0] in ["Guardar local","Publicar contenido","Probar"]: write_buttons.append(button)
	notice = Label.new()
	notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	notice.custom_minimum_size.x = 1150
	for field in [id_field,title_field]: field.text_changed.connect(func(_v): rebuild())
	race_kind.item_selected.connect(func(index):
		laps_count.editable = index == 1
		rebuild())
	laps_count.value_changed.connect(func(_v): rebuild())
	column.add_child(notice)
	rebuild()

func screen(p: Vector2) -> Vector2:
	return (p-center)*zoom+size*Vector2(0.5,0.62)

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO,size),Color("101a24"))
	if graph == null: return
	for road in graph.roads.values():
		var a: Vector2 = graph.nodes[str(road["from"])]
		var b: Vector2 = graph.nodes[str(road["to"])]
		var p := screen(a)
		var q := screen(b)
		if Rect2(Vector2.ZERO,size).grow(100).has_point(p) or Rect2(Vector2.ZERO,size).grow(100).has_point(q):
			draw_line(p,q,Color("475866"),1,true)
	if not draft.is_empty():
		var points: Array = draft["points_xz"]
		for i in range(points.size()-1): draw_line(screen(Vector2(points[i][0],points[i][1])),screen(Vector2(points[i+1][0],points[i+1][1])),Color.CYAN,3,true)
		for gate in draft["checkpoints"]:
			var p := Vector2(gate["position_xz"][0],gate["position_xz"][1])
			var f := Vector2(gate["forward_xz"][0],gate["forward_xz"][1]).orthogonal()*preload("res://scripts/racing/RaceGeometry.gd").half_width(gate)
			draw_line(screen(p-f),screen(p+f),Color("ff90b5"),2)
	for i in range(anchors.size()):
		if not graph.nodes.has(anchors[i]): continue
		var p: Vector2 = graph.nodes[anchors[i]]
		draw_circle(screen(p),7,Color.GREEN if i == 0 else (Color.RED if race_kind.selected == 0 and i == anchors.size()-1 else Color.YELLOW))
		draw_string(ThemeDB.fallback_font,screen(p)+Vector2(9,-9),str(i),HORIZONTAL_ALIGNMENT_LEFT,-1,18)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_MIDDLE: dragging = event.pressed
		if not event.pressed: return
		if event.button_index == MOUSE_BUTTON_WHEEL_UP: zoom = minf(4,zoom*1.2)
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN: zoom = maxf(0.025,zoom/1.2)
		if event.button_index == MOUSE_BUTTON_LEFT:
			var p: Vector2 = (event.position-size*Vector2(0.5,0.62))/zoom+center
			add_map_point(p)
		queue_redraw()
	elif event is InputEventMouseMotion and dragging:
		center -= event.relative/zoom
		queue_redraw()

func add_map_point(p: Vector2) -> void:
	var node: String = graph.nearest(p,80.0)
	if node.is_empty():
		notice.text = "No hay nodo vial cercano. Acércate con zoom a la carretera."
		return
	var index := int(selected.value)
	match edit_mode.selected:
		0: anchors.append(node)
		1:
			if index < anchors.size(): anchors[index] = node
		2:
			if index < anchors.size(): anchors.remove_at(index)
	rebuild()

func rebuild() -> void:
	var type := "circuit" if race_kind.selected == 1 else "sprint"
	var laps := int(laps_count.value) if type == "circuit" else 0
	var built := Store.build(graph,anchors,id_field.text.strip_edges(),title_field.text.strip_edges(),spacing.value,exception.button_pressed,type,laps)
	draft = built["data"]
	draft_error = built["error"]
	if draft_error.is_empty():
		var distance_label := "%.0f m por vuelta · %.0f m total" % [draft["lap_distance_m"],draft["distance_m"]] if type == "circuit" else "%.0f m total" % draft["distance_m"]
		notice.text = "%s · %d puntos · %s · %d controles%s · %s" % [Store.format_label(draft),anchors.size(),distance_label,draft["checkpoints"].size()," por vuelta" if type == "circuit" else "","contrasentido autorizado" if exception.button_pressed else "sentidos OSM"]
		notice.modulate = Color("a4efc0")
	else:
		notice.text = draft_error
		notice.modulate = Color("ffcc88")
	for button in write_buttons:
		button.disabled = not draft_error.is_empty()
		button.tooltip_text = draft_error
	queue_redraw()

func delete_selected() -> void:
	var index := int(selected.value)
	if index < anchors.size(): anchors.remove_at(index)
	rebuild()

func undo() -> void:
	if not anchors.is_empty(): anchors.pop_back()
	rebuild()

func save_local() -> void:
	rebuild()
	if not draft_error.is_empty(): return
	var error := Store.save(draft,graph)
	notice.text = "Guardado en user://races/" if error.is_empty() else error

func publish() -> void:
	rebuild()
	if not draft_error.is_empty(): return
	var error := Store.save(draft,graph,true)
	notice.text = "Publicado en data/races/; incluir JSON en la exportación." if error.is_empty() else error

func load_draft() -> void:
	var data := Store.load_id(id_field.text.strip_edges())
	# Changed maps require explicit regeneration from surviving anchor identifiers.
	if data.is_empty():
		notice.text = "No se encontró la carrera."
		return
	if not data.get("anchors") is Array or not data.get("settings") is Dictionary or data.get("type") not in ["sprint","circuit"]:
		notice.text = "El archivo no contiene una carrera reconocible. El borrador actual se conserva."
		return
	anchors = data["anchors"].duplicate()
	race_kind.select(1 if data["type"] == "circuit" else 0)
	laps_count.editable = race_kind.selected == 1
	laps_count.set_value_no_signal(int(data.get("laps",3)) if race_kind.selected == 1 else 3)
	title_field.text = data.get("name","")
	spacing.set_value_no_signal(data.get("settings",{}).get("checkpoint_spacing_m",30))
	exception.set_pressed_no_signal(data.get("settings",{}).get("allow_wrong_way",false))
	rebuild()
	var error := Store.validate(data,graph)
	if not error.is_empty(): notice.text = error+" Revisar y guardar de nuevo."

func test_drive() -> void:
	rebuild()
	if not draft_error.is_empty(): return
	var error := Store.save(draft,graph)
	if not error.is_empty():
		notice.text = error
		return
	var id: String = draft["id"]
	close()
	world.request_race(id)

func close() -> void:
	world.player.driving_enabled = true
	queue_free()

extends Control
var passport: Node3D
var list: ItemList
var detail: VBoxContainer
var heading: Label
var selection:=0

func button(text: String, action: Callable, parent: Node) -> Button:
	var b:=Button.new();b.text=text;b.custom_minimum_size.y=38;b.pressed.connect(action);parent.add_child(b);return b

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var backdrop:=ColorRect.new();backdrop.color=Color(.015,.025,.07,1);backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);add_child(backdrop)
	var margin:=MarginContainer.new();margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left","right","top","bottom"]:margin.add_theme_constant_override("margin_"+side,40)
	add_child(margin)
	var column:=VBoxContainer.new();column.add_theme_constant_override("separation",16);margin.add_child(column)
	heading=Label.new();heading.add_theme_font_size_override("font_size",28);heading.add_theme_color_override("font_color",Color("6ce5e0"));column.add_child(heading)
	var row:=HBoxContainer.new();row.size_flags_vertical=Control.SIZE_EXPAND_FILL;row.add_theme_constant_override("separation",24);column.add_child(row)
	list=ItemList.new();list.custom_minimum_size.x=410;row.add_child(list)
	var scroll:=ScrollContainer.new();scroll.size_flags_horizontal=Control.SIZE_EXPAND_FILL;row.add_child(scroll)
	detail=VBoxContainer.new();detail.size_flags_horizontal=Control.SIZE_EXPAND_FILL;detail.add_theme_constant_override("separation",14);scroll.add_child(detail)
	list.item_selected.connect(func(index: int):selection=index;show_detail())
	var actions:=HBoxContainer.new();column.add_child(actions)
	button("Volver · P / Esc",passport.close_book,actions)
	if passport.developer_available():button("Editor de POI · Ctrl+Alt+I",passport.open_editor,actions)
	refresh()
	list.grab_focus.call_deferred()

func refresh() -> void:
	heading.text="PASAPORTE LA PAZ · %d/%d"%[passport.count(),passport.active.size()]
	list.clear()
	for poi in passport.active:list.add_item(("✓ " if passport.store.discovered.has(poi["id"]) else "◇ ")+str(poi["name"])+(" · descubierto" if passport.store.discovered.has(poi["id"]) else " · desconocido"))
	selection=clampi(selection,0,maxi(0,passport.active.size()-1))
	if not passport.active.is_empty():list.select(selection)
	show_detail()

func text(value: String, size:=19) -> void:
	var label:=Label.new();label.text=value;label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;label.add_theme_font_size_override("font_size",size);detail.add_child(label)

func show_detail() -> void:
	for node in detail.get_children():node.queue_free()
	if passport.active.is_empty():return
	var poi: Dictionary=passport.active[selection]
	text(poi["name"],26);text(poi["category"],18)
	text("Descubierto" if passport.store.discovered.has(poi["id"]) else "Desconocido",16)
	if passport.store.discovered.has(poi["id"]):
		text(poi["description"])
		text("Registrado: "+str(passport.store.discovered[poi["id"]]),14)
		for source in poi["references"]:
			var link:=LinkButton.new();link.text=source.get("title","Fuente")+" · "+str(source["url"])
			link.pressed.connect(func():OS.shell_open(source["url"]));detail.add_child(link)
	else:text("Lugar todavía no registrado. Acércate al marcador turquesa sobre la calle, reduce a menos de 11 km/h y pulsa E / mando B para descubrirlo. No es necesario subir a una banqueta.")
	button("Marcar aproximación en el GPS",func():passport.world.navigation.set_destination(poi["interaction_xz"]);passport.world.hud.show_notice("Destino: "+poi["name"]),detail)

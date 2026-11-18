extends Control
const Store=preload("res://scripts/passport/PassportStore.gd")
var passport: Node3D
var draft: Dictionary={}
var selection:=0
var list: OptionButton
var fields: Dictionary={}
var latitude: LineEdit
var longitude: LineEdit
var description: TextEdit
var reference: LineEdit
var source_ref: LineEdit
var enabled: CheckBox
var verified: CheckBox
var radius: SpinBox
var speed: SpinBox
var notice: Label
var map: Control
var zone: Dictionary={}

func action(text: String, method: Callable, parent: Node) -> Button:
	var b:=Button.new();b.text=text;b.custom_minimum_size.y=33;b.pressed.connect(method);parent.add_child(b);return b

func input(caption: String, parent: Node) -> LineEdit:
	var label:=Label.new();label.text=caption;label.add_theme_font_size_override("font_size",13);parent.add_child(label)
	var field:=LineEdit.new();parent.add_child(field);return field

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg:=ColorRect.new();bg.color=Color(.015,.025,.06,1);bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);add_child(bg)
	var margin:=MarginContainer.new();margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left","right","top","bottom"]:margin.add_theme_constant_override("margin_"+side,20)
	add_child(margin)
	var column:=VBoxContainer.new();margin.add_child(column)
	var title:=Label.new();title.text="EDITOR PASAPORTE · Ctrl+Alt+I / Esc cerrar · F8 no se utiliza";title.add_theme_color_override("font_color",Color("68eddf"));column.add_child(title)
	var body:=HBoxContainer.new();body.size_flags_vertical=Control.SIZE_EXPAND_FILL;column.add_child(body)
	var scroll:=ScrollContainer.new();scroll.custom_minimum_size.x=430;scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;body.add_child(scroll)
	var form:=VBoxContainer.new();form.size_flags_horizontal=Control.SIZE_EXPAND_FILL;scroll.add_child(form)
	list=OptionButton.new();form.add_child(list)
	list.item_selected.connect(func(index: int):
		if collect():select(index)
		else:list.select(selection))
	for caption in ["ID estable (no se renombra)","Nombre oficial","Categoría"]:fields[caption]=input(caption,form)
	fields["ID estable (no se renombra)"].editable=false
	latitude=input("Latitud geográfica verificada",form);longitude=input("Longitud geográfica verificada",form)
	source_ref=input("Referencia de coordenadas: ID OSM / ficha oficial",form)
	reference=input("Fuente informativa HTTPS",form)
	var desc_label:=Label.new();desc_label.text="Descripción propia respaldada por la fuente";form.add_child(desc_label)
	description=TextEdit.new();description.wrap_mode=TextEdit.LINE_WRAPPING_BOUNDARY;description.custom_minimum_size.y=100;form.add_child(description)
	verified=CheckBox.new();verified.text="He contrastado coordenadas y fuentes";form.add_child(verified)
	latitude.text_changed.connect(func(_value: String):verified.button_pressed=false)
	longitude.text_changed.connect(func(_value: String):verified.button_pressed=false)
	enabled=CheckBox.new();enabled.text="Activo (máximo %d lugares)"%Store.MAX_ACTIVE;form.add_child(enabled)
	radius=SpinBox.new();radius.min_value=4;radius.max_value=15;radius.suffix="m de radio";form.add_child(radius)
	speed=SpinBox.new();speed.min_value=0;speed.max_value=3;speed.step=.1;speed.suffix="m/s máximo para descubrir";form.add_child(speed)
	var mode:=CheckBox.new();mode.text="Clic coloca lugar; apagado: aproximación vial";form.add_child(mode)
	map=preload("res://scripts/passport/PassportEditorMap.gd").new();map.editor=self;map.world=passport.world
	map.size_flags_horizontal=Control.SIZE_EXPAND_FILL;map.size_flags_vertical=Control.SIZE_EXPAND_FILL;body.add_child(map)
	mode.toggled.connect(func(value: bool):map.place_mode=value)
	var first:=HBoxContainer.new();column.add_child(first)
	for entry in [["Nuevo borrador",new_draft],["Quitar borrador",remove_selected],["Zona en mi coche",use_car],["Probar zona",test_zone],["GPS a la zona",navigate]]:action(entry[0],entry[1],first)
	var files:=HBoxContainer.new();column.add_child(files)
	for entry in [["Guardar borrador",save_draft],["Cargar borrador",load_draft],["Aplicar local",apply_local],["Publicar proyecto",publish],["Cerrar",passport.close_editor]]:action(entry[0],entry[1],files)
	notice=Label.new();notice.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;notice.add_theme_font_size_override("font_size",13);column.add_child(notice)
	draft=passport.catalog.duplicate(true);reload_list();select(0);map.recenter()
	notice.text="Rosa: lugar real. Turquesa: zona vial. Guarda borradores incompletos; prueba la aproximación antes de aplicar. No se otorgan descubrimientos desde el editor."

func reload_list() -> void:
	list.clear()
	for poi in draft["pois"]:list.add_item(str(poi["id"])+" · "+str(poi.get("name","Sin nombre")))

func select(index: int) -> void:
	selection=index;list.select(index)
	var poi: Dictionary=draft["pois"][selection]
	fields["ID estable (no se renombra)"].text=poi["id"];fields["Nombre oficial"].text=poi.get("name","");fields["Categoría"].text=poi.get("category","")
	latitude.text=str(poi.get("latitude",""));longitude.text=str(poi.get("longitude",""));description.text=poi.get("description","")
	reference.text=str(poi.get("references",[{}])[0].get("url","")) if not poi.get("references",[]).is_empty() else ""
	source_ref.text=poi.get("coordinate_evidence",{}).get("source_ref","");verified.button_pressed=poi.get("coordinate_evidence",{}).get("verified",false)
	enabled.button_pressed=poi.get("enabled",false);zone=poi.get("activation",{}).duplicate(true)
	radius.value=zone.get("radius_m",9);speed.value=zone.get("max_speed_mps",3);map.queue_redraw()

func collect() -> bool:
	if not latitude.text.is_valid_float() or not longitude.text.is_valid_float():notice.text="Escribe latitud y longitud numéricas.";return false
	var poi: Dictionary=draft["pois"][selection]
	var changed: bool=float(poi.get("latitude",0))!=float(latitude.text) or float(poi.get("longitude",0))!=float(longitude.text)
	poi.merge({"name":fields["Nombre oficial"].text.strip_edges(),"category":fields["Categoría"].text.strip_edges(),"latitude":float(latitude.text),"longitude":float(longitude.text),"description":description.text.strip_edges(),"references":[{"title":"Fuente","url":reference.text.strip_edges()}],"enabled":enabled.button_pressed},true)
	var evidence: Dictionary=poi.get("coordinate_evidence",{}).duplicate(true)
	evidence["verified"]=verified.button_pressed;evidence["source_ref"]=source_ref.text.strip_edges()
	if changed or not evidence.has("method"):evidence["method"]="manual author review; not automatically verified online"
	poi["coordinate_evidence"]=evidence
	var p:=Store.world_point(poi["latitude"],poi["longitude"],passport.world.map_data["metadata"]);poi["position_xz"]=[p.x,p.y]
	if not zone.is_empty():zone["radius_m"]=radius.value;zone["max_speed_mps"]=speed.value
	poi["activation"]=zone.duplicate(true)
	return true

func new_draft() -> void:
	if not collect():return
	draft["pois"].append({"id":"poi_custom_"+Crypto.new().generate_random_bytes(5).hex_encode(),"name":"","category":"","latitude":0,"longitude":0,"description":"","references":[],"enabled":false,"coordinate_evidence":{"verified":false},"activation":{}})
	reload_list();select(draft["pois"].size()-1)

func remove_selected() -> void:
	if draft["pois"].size()<=1:notice.text="Conserva al menos un borrador.";return
	draft["pois"].remove_at(selection);reload_list();select(0)

func use_car() -> void:
	zone=Store.snap(Vector2(passport.world.player.position.x,passport.world.player.position.z),GameFlow.road_graph,50)
	if zone.is_empty():notice.text="No hay calle transitable cerca del coche.";return
	test_zone();map.queue_redraw()

func test_zone() -> bool:
	if zone.is_empty():notice.text="Selecciona una calle primero.";return false
	var p:=Store.approach({"activation":zone},GameFlow.road_graph)
	var car=passport.world.player
	if p.distance_to(Vector2(car.position.x,car.position.z))>80:notice.text="Acércate a menos de 80 m para comprobar colisiones cargadas; usa GPS a la zona.";return false
	var road: Dictionary=GameFlow.road_graph.roads[str(zone["road_id"])]
	var a: Vector2=GameFlow.road_graph.nodes[str(road["from"])];var b: Vector2=GameFlow.road_graph.nodes[str(road["to"])]
	var yaw:=atan2(-(b.x-a.x),-(b.y-a.y))
	var pose:=Transform3D(Basis(Vector3.UP,yaw),Vector3(p.x,car.supported_pose_height(p.x,p.y,yaw),p.y))
	var safe: bool=car.safe_road_transform(pose)
	zone["validated"]=safe;zone["validation_map_sha256"]=GameFlow.road_graph.map_hash;zone["validation_method"]="stationary car collision footprint and asphalt probes; no teleport"
	notice.text="Zona válida: coche completo sobre asfalto libre." if safe else "Zona no válida: falta apoyo o hay una colisión. Elige otro punto de la calle."
	return safe

func navigate() -> void:
	if zone.is_empty():return
	passport.world.navigation.set_destination(Store.approach({"activation":zone},GameFlow.road_graph))
	notice.text="Destino marcado. Cierra el editor y conduce hasta la zona para probarla."

func save_draft() -> void:
	if collect():notice.text=Store.write(passport.draft_path,draft);if_empty("Borrador guardado; no cambia el catálogo activo.")

func if_empty(message: String) -> void:
	if notice.text.is_empty():notice.text=message

func load_draft() -> void:
	var data:=Store.read(passport.draft_path)
	if data.get("schema_version")!=1 or not data.get("pois") is Array or data["pois"].is_empty():notice.text="No hay un borrador compatible.";return
	for poi in data["pois"]:
		if not poi is Dictionary or not Store.safe_id(str(poi.get("id",""))) or not poi.get("activation",{}) is Dictionary or not poi.get("coordinate_evidence",{}) is Dictionary or not poi.get("references",[]) is Array:notice.text="Borrador dañado o incompatible.";return
		for source in poi.get("references",[]):
			if not source is Dictionary:notice.text="Fuente de borrador incompatible.";return
	draft=Store.upgrade_catalog(data,Store.read(Store.CONTENT));reload_list();select(0);notice.text="Borrador cargado. Aplicar valida el catálogo completo."

func commit(path: String) -> bool:
	if not collect():return false
	var error:=Store.validate(draft,GameFlow.road_graph,passport.world.map_data["metadata"])
	if not error.is_empty():notice.text=error;return false
	error=Store.write(path,draft)
	if not error.is_empty():notice.text=error;return false
	passport.apply_catalog(draft);notice.text="Catálogo aplicado. El progreso existente se conserva por ID."
	return true

func apply_local() -> void:commit(passport.local_catalog_path)

func publish() -> void:
	if not passport.developer_available():notice.text="Publicación solo en desarrollo.";return
	commit(Store.CONTENT)

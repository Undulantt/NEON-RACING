extends Node3D
const Store=preload("res://scripts/passport/PassportStore.gd")
var store:=Store.new()
var world: Node3D
var catalog: Dictionary={}
var active: Array=[]
var layer: CanvasLayer
var badge: Label
var book: Control
var editor: Control
var markers: Array=[]
var candidate: Dictionary={}
var status:=""
var local_catalog_path:=Store.LOCAL
var draft_path:=Store.DRAFT
var book_was_paused:=false
var editor_was_paused:=false
var editor_returns_book:=false
var marker_refresh:=0.0

static func developer_available() -> bool:
	return OS.has_feature("editor") and OS.is_debug_build()

func configure(target: Node3D) -> void:
	world=target;process_mode=Node.PROCESS_MODE_ALWAYS
	if OS.is_debug_build() and "--passport-test" in OS.get_cmdline_user_args():
		store.progress_path="user://tests/d4/progress.json";local_catalog_path="user://tests/d4/catalog.json";draft_path="user://tests/d4/draft.json"
	store.load_progress()
	layer=CanvasLayer.new();layer.layer=75;add_child(layer)
	badge=Label.new();badge.position=Vector2(24,330);badge.add_theme_font_size_override("font_size",15)
	badge.add_theme_color_override("font_color",Color("6eeae7"));badge.add_theme_color_override("font_outline_color",Color.BLACK);badge.add_theme_constant_override("outline_size",4)
	layer.add_child(badge)
	var shipped:=Store.read(Store.CONTENT)
	var selected:=Store.upgrade_catalog(Store.read(local_catalog_path),shipped)
	var local_error:=Store.validate(selected,GameFlow.road_graph,world.map_data["metadata"])
	if selected.is_empty() or not local_error.is_empty():
		if FileAccess.file_exists(local_catalog_path):world.hud.show_notice("Catálogo local descartado: "+local_error)
		selected=shipped
	apply_catalog(selected)
	if not store.warning.is_empty():world.hud.show_notice(store.warning)

func allowed() -> bool:
	return GameFlow.current_state==&"free_drive" and not GameFlow.transition_busy

func busy() -> bool:
	return is_instance_valid(book) or is_instance_valid(editor) or world.race_activity.prompting or is_instance_valid(world.race_activity.editor)

func count() -> int:
	var result:=0
	for poi in active:
		if store.discovered.has(poi["id"]):result+=1
	return result

func apply_catalog(data: Dictionary) -> bool:
	var error:=Store.validate(data,GameFlow.road_graph,world.map_data["metadata"])
	if not error.is_empty():status=error;return false
	catalog=data.duplicate(true);active.clear();candidate={}
	for marker in markers:marker.queue_free()
	markers.clear()
	for poi in catalog["pois"]:
		if not poi.get("enabled",false):continue
		poi["interaction_xz"]=Store.approach(poi,GameFlow.road_graph)
		active.append(poi)
		var marker:=MeshInstance3D.new();var mesh:=PrismMesh.new();mesh.size=Vector3(.65,.9,.65);marker.mesh=mesh
		marker.name="Passport_"+str(poi["id"])
		marker.set_meta("poi_id",poi["id"]);marker.set_meta("model_id",poi.get("model_id",""))
		var mat:=StandardMaterial3D.new();mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;mat.albedo_color=Color("49d4d2")
		marker.material_override=mat;marker.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var p: Vector2=poi["interaction_xz"];marker.position=Vector3(p.x,world.player.surface_height(p.x,p.y)+3.8,p.y)
		add_child(marker);marker.hide();markers.append(marker)
	return true

func eligible(poi: Dictionary, full_check:=false) -> bool:
	if not allowed() or busy() or get_tree().paused or not world.player.driving_enabled:return false
	if world.race_activity.recovering or not world.race_activity.info.text.is_empty():return false
	var car=world.player
	if car.speed_mps>float(poi["activation"]["max_speed_mps"]) or not car.is_on_floor() or not car.on_asphalt:return false
	if Vector2(car.position.x,car.position.z).distance_to(poi["interaction_xz"])>float(poi["activation"]["radius_m"]):return false
	return not full_check or car.safe_road_transform(car.global_transform)

func discover(id: String) -> bool:
	for poi in active:
		if poi["id"]!=id:continue
		if not eligible(poi,true):return false
		if store.discovered.has(id):world.hud.show_notice("Este lugar ya está en tu pasaporte.");return false
		var error:=store.register(id)
		if not error.is_empty():world.hud.show_notice(error);return false
		world.hud.show_notice("PASAPORTE · "+str(poi["name"])+" · %d/%d"%[count(),active.size()])
		return true
	return false

func open_book() -> bool:
	if not allowed() or busy():return false
	book_was_paused=get_tree().paused;get_tree().paused=true
	book=preload("res://scripts/passport/PassportBook.gd").new();book.passport=self;layer.add_child(book)
	return true

func close_book() -> void:
	if not is_instance_valid(book):return
	book.queue_free();book=null;get_tree().paused=book_was_paused
	if book_was_paused and is_instance_valid(world.hud.free_pause):
		world.hud.free_pause.menu_buttons["passport"].grab_focus.call_deferred()

func open_editor() -> bool:
	if not developer_available() or not allowed() or is_instance_valid(editor) or world.race_activity.prompting or is_instance_valid(world.race_activity.editor):return false
	editor_was_paused=get_tree().paused;editor_returns_book=is_instance_valid(book)
	if editor_returns_book:book.hide()
	get_tree().paused=true
	editor=preload("res://scripts/passport/PassportEditor.gd").new();editor.passport=self;layer.add_child(editor)
	return true

func close_editor() -> void:
	if not is_instance_valid(editor):return
	editor.queue_free();editor=null;get_tree().paused=editor_was_paused
	if editor_returns_book and is_instance_valid(book):book.show();book.refresh()

func _process(delta: float) -> void:
	if world==null:return
	marker_refresh-=delta
	var visible_world:=allowed() and not busy()
	badge.visible=visible_world and not get_tree().paused
	candidate={}
	for i in range(active.size()):
		var poi: Dictionary=active[i]
		markers[i].visible=visible_world and Vector2(world.player.position.x,world.player.position.z).distance_to(poi["interaction_xz"])<180
		if markers[i].visible and marker_refresh<=0:
			var p: Vector2=poi["interaction_xz"]
			markers[i].position.y=world.player.surface_height(p.x,p.y)+3.8
		if eligible(poi):candidate=poi
	if marker_refresh<=0:marker_refresh=.25
	badge.text="PASAPORTE LA PAZ · %d/%d · P / pausa: abrir"%[count(),active.size()]
	if not candidate.is_empty():badge.text+="\nE / mando B: "+("Consultar " if store.discovered.has(candidate["id"]) else "Registrar ")+str(candidate["name"])

func _input(event: InputEvent) -> void:
	# Consume modal cancel/pause before the underlying driving HUD, including gamepads.
	if not event.is_echo() and (event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel")):
		if is_instance_valid(editor):close_editor();get_viewport().set_input_as_handled();return
		if is_instance_valid(book):close_book();get_viewport().set_input_as_handled();return
	if not event is InputEventKey or not event.pressed or event.echo:return
	var key: int=event.physical_keycode if event.physical_keycode!=0 else event.keycode
	if key==KEY_I and event.ctrl_pressed and event.alt_pressed:
		if is_instance_valid(editor):close_editor();get_viewport().set_input_as_handled()
		elif open_editor():get_viewport().set_input_as_handled()
	elif (key==KEY_ESCAPE or key==KEY_P) and is_instance_valid(editor):
		if key==KEY_ESCAPE:close_editor();get_viewport().set_input_as_handled()
	elif key==KEY_ESCAPE and is_instance_valid(book):close_book();get_viewport().set_input_as_handled()
	elif key==KEY_P and not event.ctrl_pressed and not event.alt_pressed and not event.meta_pressed:
		if is_instance_valid(book):close_book();get_viewport().set_input_as_handled()
		elif open_book():get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact") and not event.is_echo() and not candidate.is_empty():
		if store.discovered.has(candidate["id"]):open_book()
		else:discover(candidate["id"])
		get_viewport().set_input_as_handled()

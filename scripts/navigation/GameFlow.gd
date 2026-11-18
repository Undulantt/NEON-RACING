extends Node

# One session owner. Views only issue commands and observe these signals.
signal state_changed(state: StringName)
signal vehicle_changed(id: String)
signal race_changed(id: String)
signal settings_changed
signal race_requested(context: Dictionary)

const Profiles = preload("res://scripts/driving/VehicleProfiles.gd")
const Graphics = preload("res://scripts/ui/GraphicsPreferences.gd")
const MENU_STATES := [&"main_menu", &"play_menu", &"vehicle_select", &"race_select", &"how_to_play", &"options", &"credits", &"race_pending", &"results"]
var definition: Dictionary = {}
var current_state: StringName = &"main_menu"
var current_scene_path := ""
var selected_mode: StringName = &""
var selected_vehicle_id := "COMET"
var selected_race_id := ""
var rival_difficulty := "expert"
var race_origin: StringName = &""
var return_destination: StringName = &"main_menu"
var activity_id := ""
var activity_result: Dictionary = {}
var return_context: Dictionary = {}
var launch_context: Dictionary = {}
var transition_busy := false
var navigation_error := ""
var settings_path := "user://game_settings.cfg"
var volumes: Dictionary = {}
var screen_mode := "windowed"
var window_size := Vector2i(1280, 720)
var graphics: Dictionary = {}
var graphics_configured := false
var intro_shown := false
var driving_music: Node
var menu_audio: Node
var quitting:=false
var _world: WeakRef
var prepared_world: Dictionary = {}
var road_graph: RefCounted
var loading_overlay: CanvasLayer
var last_loading_metrics: Dictionary = {}
const RaceStore = preload("res://scripts/racing/RaceStore.gd")
var active_race: Dictionary = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	definition = JSON.parse_string(FileAccess.get_file_as_string("res://config/game_flow.json"))
	selected_vehicle_id = definition["default_vehicle"]
	current_scene_path = definition["menu_scene"]
	load_settings()
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--ai-difficulty="):
			var requested:=argument.trim_prefix("--ai-difficulty=")
			if requested in preload("res://scripts/racing/RivalDifficulty.gd").IDS: rival_difficulty=requested
	preload("res://scripts/driving/DrivingInput.gd").install_gamepad_bindings()
	_install_menu_bindings()
	menu_audio=preload("res://scripts/ui/MenuAudio.gd").new()
	add_child(menu_audio);menu_audio.configure(self)
	driving_music=preload("res://scripts/ui/DrivingMusic.gd").new()
	add_child(driving_music);driving_music.configure(self)
	get_tree().auto_accept_quit=false
	get_tree().root.close_requested.connect(quit_game)

func _install_menu_bindings() -> void:
	for binding in [["ui_accept", JOY_BUTTON_A], ["ui_cancel", JOY_BUTTON_B], ["ui_up", JOY_BUTTON_DPAD_UP], ["ui_down", JOY_BUTTON_DPAD_DOWN], ["ui_left", JOY_BUTTON_DPAD_LEFT], ["ui_right", JOY_BUTTON_DPAD_RIGHT]]:
		var event := InputEventJoypadButton.new()
		event.device = -1
		event.button_index = binding[1]
		if not InputMap.action_has_event(binding[0], event):
			InputMap.action_add_event(binding[0], event)
	for binding in [["ui_up", JOY_AXIS_LEFT_Y, -1.0], ["ui_down", JOY_AXIS_LEFT_Y, 1.0], ["ui_left", JOY_AXIS_LEFT_X, -1.0], ["ui_right", JOY_AXIS_LEFT_X, 1.0]]:
		var event := InputEventJoypadMotion.new()
		event.device = -1
		event.axis = binding[1]
		event.axis_value = binding[2]
		if not InputMap.action_has_event(binding[0], event):
			InputMap.action_add_event(binding[0], event)

func _set_state(next: StringName) -> void:
	current_state = next
	state_changed.emit(next)

func show_screen(next: StringName) -> bool:
	if transition_busy or next not in MENU_STATES or current_state == &"free_drive":
		return false
	_set_state(next)
	return true

func choose_mode(mode: StringName) -> bool:
	if transition_busy or mode not in [&"free_drive", &"race"] or current_state not in [&"play_menu", &"vehicle_select"]:
		return false
	selected_mode = mode
	navigation_error = ""
	_set_state(&"vehicle_select")
	return true

func select_vehicle(id: String) -> bool:
	if transition_busy or current_state != &"vehicle_select" or id not in Profiles.IDS:
		return false
	selected_vehicle_id = id
	vehicle_changed.emit(id)
	_save_settings()
	return true

func set_rival_difficulty(id: String) -> bool:
	if transition_busy or current_state not in [&"vehicle_select",&"options"] or id not in preload("res://scripts/racing/RivalDifficulty.gd").IDS: return false
	rival_difficulty=id
	_save_settings()
	settings_changed.emit()
	return true

func go_back() -> void:
	if transition_busy:
		return
	match current_state:
		&"race_select": _set_state(&"vehicle_select")
		&"vehicle_select": _set_state(&"play_menu")
		&"play_menu", &"how_to_play", &"options", &"credits": _set_state(&"main_menu")
		&"race_pending": cancel_activity()
		&"results": return_from_activity()

func start_selected() -> bool:
	if transition_busy or current_state != &"vehicle_select" or selected_vehicle_id not in Profiles.IDS:
		return false
	if selected_mode == &"free_drive":
		race_origin = &""
		return_context.clear()
		launch_context = {"vehicle_id": selected_vehicle_id, "spawn": definition["free_drive_spawn"].duplicate(true)}
		_switch_scene(definition["world_scene"], &"free_drive")
		return true
	if selected_mode == &"race":
		if selected_race_id not in menu_race_ids():selected_race_id=str(definition["default_race_id"])
		_set_state(&"race_select")
		return true
	return false

func menu_race_ids() -> Array:
	var ids: Array=definition.get("menu_race_ids",[definition["default_race_id"]]).duplicate()
	var default_id:=str(definition["default_race_id"])
	if default_id not in ids:ids.push_front(default_id)
	return ids

func select_race(id: String) -> bool:
	if transition_busy or current_state!=&"race_select" or id not in menu_race_ids():return false
	selected_race_id=id;navigation_error="";race_changed.emit(id);return true

func launch_selected_race() -> bool:
	if transition_busy or current_state!=&"race_select" or selected_mode!=&"race" or selected_race_id not in menu_race_ids() or selected_vehicle_id not in Profiles.IDS:return false
	_begin_race(&"menu",selected_race_id);return true

func pending_world_launch() -> Dictionary:
	return launch_context.duplicate(true) if transition_busy and not launch_context.is_empty() else {}

func world_instance() -> Node3D:
	return _world.get_ref() as Node3D if _world != null else null

func request_race_from_free_drive(id: String = "") -> bool:
	var world := world_instance()
	if transition_busy or current_state != &"free_drive" or world == null:
		return false
	var car = world.player
	selected_vehicle_id = car.vehicle_profile
	var pose: Transform3D = car.global_transform if car.safe_road_transform(car.global_transform) else car.safe_transform
	return_context = {"pose": pose, "vehicle_id": selected_vehicle_id, "turbo_charge": car.turbo_charge}
	_begin_race(&"free_drive", id)
	return true

func _begin_race(origin: StringName, id: String) -> void:
	race_origin = origin
	return_destination = &"free_drive" if origin == &"free_drive" else &"main_menu"
	activity_id = id
	activity_result.clear()
	active_race = RaceStore.load_id(id)
	if active_race.is_empty():
		navigation_error = "No se encontró la carrera configurada."
		if origin == &"free_drive":
			world_instance().hud.show_notice(navigation_error)
			world_instance().player.driving_enabled = true
			_set_state(&"free_drive")
		else: _set_state(&"race_pending")
		return
	race_requested.emit(activity_context())
	if origin == &"free_drive":
		_prepare_existing_race()
	else:
		launch_context = {"vehicle_id":selected_vehicle_id,"spawn":active_race["start"].duplicate(true)}
		_switch_scene(definition["world_scene"],&"race")

func restart_race() -> void:
	if transition_busy or current_state not in [&"race",&"results"] or active_race.is_empty() or world_instance() == null: return
	get_tree().paused = false
	_prepare_existing_race()

func _prepare_existing_race() -> void:
	var error := RaceStore.validate(active_race,road_graph)
	if not error.is_empty():
		navigation_error = error
		world_instance().hud.show_notice(error)
		return
	transition_busy = true
	get_tree().paused = false
	world_instance().hud.set_pause(false)
	# Remove finished rivals before checking the new grid for occupied space.
	world_instance().race_activity.release_competition()
	var needs_loading: bool = not world_instance().initial_support_ready(active_race["start"])
	if needs_loading:
		_show_loading("Preparando salida y colisiones de la carrera")
		_set_state(&"loading")
		await world_instance().prepare_at(active_race["start"])
	else: world_instance().place_at(active_race["start"])
	if not world_instance().player.safe_road_transform(world_instance().player.global_transform): world_instance().runtime_error = "No hay una aparición segura para este recorrido."
	if not world_instance().runtime_error.is_empty():
		navigation_error = world_instance().runtime_error
		transition_busy = false
		_hide_loading()
		return_to_main_menu()
		return
	if needs_loading:await _settle_world(world_instance())
	world_instance().race_activity.start(active_race)
	if not world_instance().runtime_error.is_empty():
		navigation_error=world_instance().runtime_error;transition_busy=false
		_hide_loading();return_to_main_menu();return
	transition_busy = false
	_set_state(&"race")
	_hide_loading()

func activity_context() -> Dictionary:
	return {"mode": "race", "vehicle_id": selected_vehicle_id, "activity_id": activity_id, "origin": String(race_origin), "return_destination": String(return_destination), "return_context": return_context.duplicate(true)}

func finish_activity(result: Dictionary) -> bool:
	# The race session supplies measured results.
	if transition_busy or race_origin.is_empty() or result.is_empty() or current_state not in [&"race_pending", &"race"]:
		return false
	activity_result = result.duplicate(true)
	if world_instance() != null or current_scene_path == definition["menu_scene"]:
		_set_state(&"results")
	else:
		_switch_scene(definition["menu_scene"], &"results")
	return true

func cancel_activity() -> void:
	if not transition_busy:
		return_from_activity()

func return_from_activity() -> void:
	if transition_busy:
		return
	if return_destination == &"free_drive" and world_instance() != null:
		var world := world_instance()
		get_tree().paused = false
		world.hud.set_pause(false)
		world.race_activity.leave()
		selected_mode = &"free_drive"
		transition_busy = true
		var destination: Dictionary = active_race.get("start",definition["free_drive_spawn"])
		if not world.initial_support_ready(destination):
			_show_loading("Regresando al punto de salida")
			_set_state(&"loading")
			await world.prepare_at(destination)
		if not world.runtime_error.is_empty():
			navigation_error = world.runtime_error
			transition_busy = false
			return_to_main_menu()
			return
		if is_instance_valid(loading_overlay):await _settle_world(world)
		world.place_at(destination)
		world.player.turbo_charge = float(return_context.get("turbo_charge",1.0))
		world.player.driving_enabled = true
		transition_busy = false
		race_origin = &""
		activity_result.clear()
		_set_state(&"free_drive")
		_hide_loading()
	else:
		return_to_main_menu()

func return_to_main_menu() -> void:
	if transition_busy:
		return
	selected_mode = &""
	race_origin = &""
	activity_id = ""
	return_destination = &"main_menu"
	return_context.clear()
	launch_context.clear()
	activity_result.clear()
	active_race = {}
	get_tree().paused = false
	if get_tree().current_scene != null and get_tree().current_scene.scene_file_path == definition["menu_scene"]:
		_set_state(&"main_menu")
	else:
		_switch_scene(definition["menu_scene"], &"main_menu")

func _switch_scene(path: String, destination: StringName) -> void:
	transition_busy = true
	get_tree().paused = false
	_show_loading("Preparando contenido")
	_set_state(&"loading")
	_perform_transition.call_deferred(path, destination)

func _perform_transition(path: String, destination: StringName) -> void:
	await get_tree().process_frame
	if destination in [&"free_drive", &"race"]:
		loading_stage("Leyendo y validando datos geográficos offline")
		var worker := Thread.new()
		var preparation := preload("res://scripts/navigation/WorldPreparation.gd").new()
		var started := worker.start(preparation.run)
		if started != OK:
			navigation_error = "No se pudo iniciar la preparación de datos."
			transition_busy = false
			_set_state(&"main_menu")
			_hide_loading()
			return
		while worker.is_alive(): await get_tree().process_frame
		prepared_world = worker.wait_to_finish()
		road_graph = prepared_world["graph"]
		if destination == &"race":
			var validation := RaceStore.validate(active_race,road_graph)
			if not validation.is_empty():
				navigation_error = validation
				prepared_world = {}
				transition_busy = false
				_set_state(&"race_pending")
				_hide_loading()
				return
	var error := get_tree().change_scene_to_file(path)
	if error != OK:
		transition_busy = false
		navigation_error = "No se pudo abrir la escena: %s (error %d)." % [path,error]
		launch_context.clear()
		prepared_world = {}
		_set_state(&"main_menu")
		_hide_loading()
		return
	await get_tree().scene_changed
	current_scene_path = path
	_world = null
	if destination in [&"free_drive",&"race"]:
		var world = get_tree().current_scene
		while not world.world_ready and world.runtime_error.is_empty(): await get_tree().process_frame
		if not world.runtime_error.is_empty():
			navigation_error = world.runtime_error
			transition_busy = false
			launch_context.clear()
			_switch_scene(definition["menu_scene"],&"main_menu")
			return
		_world = weakref(world)
		loading_stage("Sincronizando física y preparando actividad")
		await get_tree().physics_frame
		await get_tree().physics_frame
		if not world.player.safe_road_transform(world.player.global_transform) or (world.city_manager != null and not world.city_manager.failed_chunks.is_empty()):
			navigation_error = "No están preparadas las colisiones de aparición."
			transition_busy = false
			_switch_scene(definition["menu_scene"],&"main_menu")
			return
		await _settle_world(world)
		world.attach_racing()
		if destination == &"race": world.race_activity.start(active_race)
		else: world.player.driving_enabled = true
		if not world.runtime_error.is_empty():
			navigation_error=world.runtime_error;transition_busy=false;launch_context.clear()
			_switch_scene(definition["menu_scene"],&"main_menu");return
		apply_graphics(world)
		world.prepared = {}
	prepared_world = {}
	launch_context.clear()
	transition_busy = false
	_set_state(destination)
	_hide_loading()

func _settle_world(world: Node3D) -> void:
	world.player.driving_enabled=false
	var player_mode: int=world.player.process_mode
	world.player.process_mode=Node.PROCESS_MODE_DISABLED
	loading_stage("Preparando iluminación, banquetas y decorado cercano")
	if "presentation_ready" in world:
		while not world.presentation_ready:await get_tree().process_frame
	if "night_style" in world and world.night_style!=null:
		await world.night_style.prewarm_loaded()
	apply_graphics(world)
	loading_stage("Terminando de preparar La Paz")
	# Real time, independent of FPS/time_scale. Driving/countdown starts only afterwards.
	var started:=Time.get_ticks_msec()
	while Time.get_ticks_msec()-started<2000:await get_tree().process_frame
	if is_instance_valid(loading_overlay):loading_overlay.settle_ms=Time.get_ticks_msec()-started
	await get_tree().physics_frame
	await get_tree().physics_frame
	world.player.process_mode=player_mode

func _show_loading(message: String) -> void:
	if not is_instance_valid(loading_overlay):
		loading_overlay = preload("res://scripts/ui/LoadingOverlay.gd").new()
		add_child(loading_overlay)
	loading_stage(message)

func loading_stage(message: String) -> void:
	if is_instance_valid(loading_overlay): loading_overlay.stage(message)

func _hide_loading() -> void:
	if is_instance_valid(loading_overlay):
		last_loading_metrics = {"frames":loading_overlay.frames,"max_gap_ms":loading_overlay.max_gap_ms,"settle_ms":loading_overlay.settle_ms}
		loading_overlay.queue_free()
	loading_overlay = null

func set_volume(bus: String, value: float, persist := true) -> bool:
	if not volumes.has(bus) or not is_finite(value):
		return false
	volumes[bus] = clampf(value, 0.0, 1.0)
	_apply_volume(bus)
	if persist:
		_save_settings()
	settings_changed.emit()
	return true

func _apply_volume(bus: String) -> void:
	var index := AudioServer.get_bus_index(bus)
	if index < 0:
		AudioServer.add_bus()
		index = AudioServer.bus_count - 1
		AudioServer.set_bus_name(index, bus)
		AudioServer.set_bus_send(index, "Master")
	var value: float = volumes[bus]
	AudioServer.set_bus_volume_db(index, linear_to_db(maxf(value, 0.0001)))
	AudioServer.set_bus_mute(index, value <= 0.0)

func load_settings() -> void:
	var defaults: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://config/night_pilot.json"))["default_volumes"]
	volumes = {"Master": 1.0, "Music": defaults["Music"], "Engine": defaults["Engine"], "Effects": defaults["Effects"]}
	var legacy := ConfigFile.new()
	legacy.load("user://night_audio.cfg")
	var saved := ConfigFile.new()
	saved.load(settings_path)
	graphics=Graphics.effective_defaults()
	graphics_configured=saved.has_section("graphics")
	for key in Graphics.DEFAULTS:
		var value=saved.get_value("graphics",key,graphics[key])
		if Graphics.valid(key,value):graphics[key]=value
	Graphics.apply(null,graphics)
	for bus in volumes:
		var value = saved.get_value("volume", bus, legacy.get_value("volume", bus, volumes[bus]))
		volumes[bus] = clampf(float(value), 0.0, 1.0) if (value is float or value is int) and is_finite(float(value)) else volumes[bus]
		_apply_volume(bus)
	var id := str(saved.get_value("session", "vehicle", definition["default_vehicle"]))
	selected_vehicle_id = id if id in Profiles.IDS else definition["default_vehicle"]
	var difficulty:=str(saved.get_value("race","difficulty","expert"))
	rival_difficulty=difficulty if difficulty in preload("res://scripts/racing/RivalDifficulty.gd").IDS else "expert"
	screen_mode = str(saved.get_value("display", "mode", "windowed"))
	if screen_mode not in ["windowed", "borderless", "fullscreen"]:
		screen_mode = "windowed"
	var size = saved.get_value("display", "window_size", Vector2i(1280, 720))
	window_size = size if size in [Vector2i(1280,720),Vector2i(1600,900),Vector2i(1920,1080)] else Vector2i(1280,720)
	_apply_display()
	settings_changed.emit()

func set_display(mode: String, size: Vector2i) -> bool:
	if mode not in ["windowed", "borderless", "fullscreen"] or size not in [Vector2i(1280,720),Vector2i(1600,900),Vector2i(1920,1080)]:
		return false
	if DisplayServer.get_name() == "headless":
		return false
	screen_mode = mode
	window_size = size
	_apply_display()
	_save_settings()
	settings_changed.emit()
	return true

func _apply_display() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var window := get_tree().root
	if screen_mode == "fullscreen":
		window.mode = Window.MODE_FULLSCREEN
	else:
		window.mode = Window.MODE_WINDOWED
		window.borderless = screen_mode == "borderless"
		window.size = window_size

func set_graphics(key: String, value: Variant) -> bool:
	if not Graphics.valid(key,value):return false
	graphics[key]=value;graphics_configured=true
	apply_graphics(world_instance())
	_save_settings();settings_changed.emit()
	return true

func apply_graphics(world: Node3D) -> void:
	Graphics.apply_quality(world,graphics)
	if graphics_configured:Graphics.apply(world,graphics)

func reset_graphics() -> void:
	graphics=Graphics.DEFAULTS.duplicate();graphics_configured=true
	apply_graphics(world_instance());_save_settings();settings_changed.emit()

func _save_settings() -> void:
	var saved := ConfigFile.new()
	for bus in volumes:
		saved.set_value("volume", bus, volumes[bus])
	saved.set_value("display", "mode", screen_mode)
	saved.set_value("display", "window_size", window_size)
	saved.set_value("session", "vehicle", selected_vehicle_id)
	saved.set_value("race","difficulty",rival_difficulty)
	if graphics_configured:
		for key in Graphics.DEFAULTS:saved.set_value("graphics",key,graphics[key])
	var error := saved.save(settings_path)
	if error != OK:
		navigation_error = "No se pudieron guardar las opciones (error %d)." % error

func quit_game() -> void:
	if OS.has_feature("web") or quitting:
		return
	quitting=true
	transition_busy=true
	if is_instance_valid(menu_audio):await menu_audio.shutdown()
	get_tree().paused = false
	get_tree().quit()

extends Node3D
const Store = preload("res://scripts/racing/RaceStore.gd")
var world: Node3D
var session: RefCounted
var definition: Dictionary = {}
var default_race: Dictionary = {}
var visuals: Node3D
var marker: MeshInstance3D
var overlay: CanvasLayer
var info: Label
var panel: PanelContainer
var panel_column: VBoxContainer
var editor: Control
var previous := Vector2.ZERO
var prompting := false
var recovery_remaining := 0.0
var recovering := false
var recovery_finishing := false
var recovery_generation := 0
var last_checkpoint: Dictionary = {}
var recovery_spawn: Dictionary = {}
var recovery_owns_transition := false

func configure(target: Node3D) -> void:
	world = target
	world.player.recovery_handler = request_recovery
	default_race = Store.load_id(str(GameFlow.definition.get("default_race_id","")))
	if not default_race.is_empty() and not Store.validate(default_race,GameFlow.road_graph).is_empty(): default_race = {}
	overlay = CanvasLayer.new()
	overlay.layer = 15
	add_child(overlay)
	info = Label.new()
	info.position = Vector2(330,75)
	info.add_theme_font_size_override("font_size",22)
	info.add_theme_color_override("font_color",Color("b9f9ff"))
	info.add_theme_color_override("font_outline_color",Color.BLACK)
	info.add_theme_constant_override("outline_size",5)
	overlay.add_child(info)
	panel = PanelContainer.new()
	panel.position = Vector2(350,190)
	panel.size = Vector2(580,300)
	overlay.add_child(panel)
	panel_column = VBoxContainer.new()
	panel_column.add_theme_constant_override("separation",14)
	panel.add_child(panel_column)
	panel.hide()
	if not default_race.is_empty():
		marker = MeshInstance3D.new()
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = 4
		cylinder.bottom_radius = 4
		cylinder.height = 5
		cylinder.cap_top = false
		cylinder.cap_bottom = false
		marker.mesh = cylinder
		marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var material := ShaderMaterial.new()
		material.shader = preload("res://shaders/race_start.gdshader")
		material.set_shader_parameter("neon_color",Color(1.0,0.02,0.5,1.0))
		marker.material_override = material
		add_child(marker)
		var p: Array = default_race["start"]["position_xz"]
		marker.position = Vector3(p[0],world.player.surface_height(p[0],p[1])+2.5,p[1])

func add_text(value: String) -> void:
	var label := Label.new()
	label.text = value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size",23)
	panel_column.add_child(label)

func add_button(caption: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = caption
	button.custom_minimum_size.y = 45
	button.pressed.connect(action)
	panel_column.add_child(button)
	return button

func clear_panel() -> void:
	for child in panel_column.get_children():
		panel_column.remove_child(child)
		child.queue_free()
	panel.show()

func confirm_start() -> void:
	if default_race.is_empty() or GameFlow.current_state != &"free_drive": return
	prompting = true
	world.player.driving_enabled = false
	clear_panel()
	add_text(str(default_race["name"]))
	add_text("%s · %.0f m\nRecorrido ficticio sobre vías OSM" % [Store.format_label(default_race),default_race["distance_m"]])
	add_button("Iniciar carrera",func():
		prompting = false
		panel.hide()
		world.request_race(default_race["id"])).grab_focus()
	add_button("Cancelar",cancel_prompt)

func cancel_prompt() -> void:
	prompting = false
	panel.hide()
	world.player.driving_enabled = true

func start(data: Dictionary) -> void:
	cancel_recovery()
	definition = data
	last_checkpoint = data["start"].duplicate(true)
	if is_instance_valid(visuals):
		remove_child(visuals)
		visuals.queue_free()
	visuals = preload("res://scripts/racing/RaceVisuals.gd").new()
	add_child(visuals)
	visuals.configure(world,data)
	session = preload("res://scripts/racing/RaceSession.gd").new()
	session.begin(data)
	session.completed.connect(_completed)
	session.checkpoint_passed.connect(_checkpoint_passed)
	panel.hide()
	prompting = false
	var car = world.player
	car.driving_enabled = false
	car.velocity = Vector3.ZERO
	var p: Array = data["start"]["position_xz"]
	var f: Array = data["start"]["forward_xz"]
	var yaw := atan2(-float(f[0]),-float(f[1]))
	car.global_transform = Transform3D(Basis(Vector3.UP,yaw),Vector3(p[0],car.supported_pose_height(p[0],p[1],yaw),p[1]))
	car.spawn_transform = car.global_transform
	car.safe_transform = car.global_transform
	car.reset_surface_motion()
	car.abilities.reset("race_restart")
	previous = Vector2(car.position.x,car.position.z)
	if marker != null: marker.hide()

func _completed(result: Dictionary) -> void:
	world.player.driving_enabled = false
	GameFlow.finish_activity(result)
	clear_panel()
	add_text("Resultados · "+str(definition["name"]))
	add_text("Tiempo: %.3f s\nDistancia: %.0f m\n%s" % [result["elapsed_seconds"],definition["distance_m"],result["summary"]])
	if definition.get("type") == "circuit": add_text("Vueltas completadas: %d / %d" % [result["laps"],definition["laps"]])
	add_button("Reiniciar carrera",GameFlow.restart_race).grab_focus()
	add_button("Volver al modo libre" if GameFlow.race_origin == &"free_drive" else "Volver al menú principal",GameFlow.return_from_activity)

func leave() -> void:
	cancel_recovery()
	session = null
	definition = {}
	panel.hide()
	if is_instance_valid(visuals):
		remove_child(visuals)
		visuals.queue_free()
	visuals = null
	if marker != null: marker.show()
	info.text = ""

func _physics_process(delta: float) -> void:
	if world == null or (GameFlow.transition_busy and not recovery_finishing): return
	var car = world.player
	var p := Vector2(car.position.x,car.position.z)
	if recovering:
		if session != null: session.tick_without_progress(delta)
		if not recovery_finishing:
			recovery_remaining = maxf(0,recovery_remaining-delta)
			if recovery_remaining <= 0: _finish_recovery()
		info.text = "Preparando colisiones…" if recovery_finishing else "Recuperando en %d…" % ceili(recovery_remaining)
		return
	if session != null:
		if get_tree().paused: return
		var ground: float = car.surface_height(p.x,p.y)
		session.advance(previous,p,delta,absf(car.position.y-ground) < 3.5)
		previous = p
		car.driving_enabled = session.phase == "running"
		if session.phase == "countdown":
			info.text = "%s · %d" % [definition["name"],ceili(session.countdown)]
		else:
			info.text = "%.2f s · %sControl %d/%d · Restan %.0f m" % [session.elapsed,"Vuelta %d/%d · " % [session.current_lap(),session.total_laps] if definition.get("type") == "circuit" else "",session.next_checkpoint,definition["checkpoints"].size(),session.remaining()]
			visuals.show_gate(session.next_checkpoint)
	elif GameFlow.current_state == &"free_drive" and not default_race.is_empty() and not prompting:
		var start: Array = default_race["start"]["position_xz"]
		info.text = "E / mando B · %s · %.0f m" % [default_race["name"],default_race["distance_m"]] if p.distance_to(Vector2(start[0],start[1])) < 24 and car.speed_mps < 3 else ""

func _unhandled_input(event: InputEvent) -> void:
	if GameFlow.transition_busy: return
	if GameFlow.current_state == &"free_drive" and not info.text.is_empty() and not is_instance_valid(editor) and ((event is InputEventKey and event.pressed and event.keycode == KEY_E and not event.ctrl_pressed and not event.alt_pressed) or (event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_B)):
		confirm_start()
		get_viewport().set_input_as_handled()

func toggle_editor() -> bool:
	if GameFlow.transition_busy or get_tree().paused or GameFlow.current_state != &"free_drive" or prompting or not preload("res://scripts/racing/RaceEditor.gd").available(): return false
	if is_instance_valid(editor): editor.close()
	else:
		editor = preload("res://scripts/racing/RaceEditor.gd").new()
		editor.world = world
		editor.graph = GameFlow.road_graph
		overlay.add_child(editor)
	return true

func _input(event: InputEvent) -> void:
	# Handle before GUI so the toggle also closes a focused LineEdit.
	# F8 is reserved by the Godot editor to stop the running project.
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_E and event.ctrl_pressed and event.alt_pressed and not event.shift_pressed and not event.meta_pressed:
		if toggle_editor(): get_viewport().set_input_as_handled()
		return
	if not event.is_action_pressed("ui_cancel") and not event.is_action_pressed("pause"): return
	if GameFlow.transition_busy:
		get_viewport().set_input_as_handled()
	elif prompting:
		cancel_prompt()
		get_viewport().set_input_as_handled()
	elif is_instance_valid(editor):
		editor.close()
		get_viewport().set_input_as_handled()
	elif GameFlow.current_state == &"results":
		GameFlow.return_from_activity()
		get_viewport().set_input_as_handled()

func _checkpoint_passed(index: int, _lap: int) -> void:
	var gate: Dictionary = definition["checkpoints"][index]
	last_checkpoint = {"position_xz":gate["position_xz"].duplicate(),"forward_xz":gate["forward_xz"].duplicate()}

func request_recovery(_reason: String = "manual") -> bool:
	if recovering: return true
	if GameFlow.transition_busy or prompting or is_instance_valid(editor) or GameFlow.current_state not in [&"race",&"free_drive"]: return false
	if session != null:
		if session.phase != "running": return true
		recovery_spawn = last_checkpoint.duplicate(true)
	else:
		var pose: Transform3D = world.player.safe_transform
		var f := -pose.basis.z
		recovery_spawn = {"position_xz":[pose.origin.x,pose.origin.z],"forward_xz":[f.x,f.z]}
	recovering = true
	recovery_remaining = 3.0
	recovery_finishing = false
	world.player.driving_enabled = false
	world.player.velocity = Vector3.ZERO
	world.player.speed_mps = 0.0
	world.player.signed_speed = 0.0
	world.player.forward_plane_speed = 0.0
	world.player.abilities.reset("recovery_pending")
	world.player.powertrain.reset()
	world.player.set_physics_process(false)
	return true

func cancel_recovery() -> void:
	if recovery_owns_transition: GameFlow.transition_busy = false
	recovery_owns_transition = false
	recovery_generation += 1
	recovering = false
	recovery_finishing = false
	recovery_remaining = 0
	if world != null: world.player.set_physics_process(true)

func _finish_recovery() -> void:
	recovery_finishing = true
	recovery_owns_transition = true
	GameFlow.transition_busy = true
	var generation := recovery_generation
	var next_before: int = session.next_checkpoint if session != null else -1
	await world.prepare_at(recovery_spawn)
	if not is_inside_tree() or generation != recovery_generation: return
	if not world.runtime_error.is_empty():
		GameFlow.navigation_error = world.runtime_error
		cancel_recovery()
		GameFlow.return_to_main_menu()
		return
	var car = world.player
	var valid: bool = car.apply_recovery_pose(car.global_transform,"último checkpoint" if session != null else "punto seguro")
	previous = Vector2(car.position.x,car.position.z)
	recovering = false
	recovery_finishing = false
	if recovery_owns_transition: GameFlow.transition_busy = false
	recovery_owns_transition = false
	car.set_physics_process(true)
	car.driving_enabled = valid and (session == null or session.phase == "running")
	if session != null: assert(session.next_checkpoint == next_before)

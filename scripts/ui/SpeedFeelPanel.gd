extends CanvasLayer
const Controller = preload("res://scripts/feedback/SpeedFeedbackController.gd")
const AudioController = preload("res://scripts/feedback/SpeedAudioController.gd")
const VisualController=preload("res://scripts/feedback/SpeedVisualFeedback.gd")
const ENV_LABELS:={
	"base_visibility":"Visibilidad mínima (detenido)","intensity":"Intensidad SF.3","asphalt_strength":"Detalle asfalto","markings_strength":"Lectura de marcas",
	"edges_strength":"Referencias de borde","lamps_strength":"Farolas y reflejos",
	"start_kmh":"Inicio (km/h)","full_speed_ratio":"Ratio para máxima normal",
	"normal_response_per_s":"Respuesta velocidad / s","turbo_response_per_s":"Respuesta TURBO / s",
	"burst_response_per_s":"Respuesta BURST / s","release_per_s":"Salida / s",
	"turbo_contribution":"Aporte TURBO","burst_contribution":"Aporte BURST",
	"radius_m":"Radio local (m)","reference_spacing_m":"Espaciado de referencias (m)",
	"reflection_stretch":"Alargamiento de reflejos"
}
const AUDIO_LABELS := {
	"engine_coast_db":"Motor base / retención (dB)","engine_load_db":"Motor bajo carga (dB)","engine_body_db":"Cuerpo grave (dB)",
	"engine_pitch_scale":"Tono motor ×","engine_body_pitch_scale":"Tono grave ×","engine_pitch_max":"Límite de tono motor",
	"engine_lift_drop_rpm":"Caída acústica al soltar (RPM)","engine_response_per_s":"Respuesta tono / s","load_response_per_s":"Respuesta carga / s",
	"wind_gain_db":"Viento (dB)","wind_start_kmh":"Inicio viento (km/h)","wind_exponent":"Curva de presión viento",
	"wind_overcap_gain":"Presión extra sobre máxima","wind_pitch_base":"Tono base viento ×","wind_pitch_add":"Incremento tono viento",
	"wind_response_per_s":"Respuesta viento / s","ab_response_per_s":"Respuesta A/B audio / s"
}
const LABELS := {
	"base_fov_deg":"FOV base (vertical)","speed_fov_add_deg":"Velocidad: incremento FOV",
	"turbo_fov_add_deg":"TURBO: incremento FOV","burst_fov_add_deg":"BURST: incremento FOV",
	"max_fov_deg":"Límite normal / BURST","fov_response_per_s":"Respuesta FOV / s",
	"spatial_response_per_s":"Respuesta posición / s","heading_response_per_s":"Respuesta giro / s",
	"distance_m":"Distancia cercana (m)","height_m":"Altura deseada (m)","pitch_deg":"Inclinación hacia abajo (°)",
	"acceleration_pull_m":"Retraso al acelerar (m)","brake_push_m":"Avance al frenar (m)",
	"turbo_pull_m":"Retraso TURBO (m)","burst_pull_m":"Retraso BURST (m)",
	"drift_shift_m":"Desplazamiento derrape (m)","drift_yaw_deg":"Giro máximo derrape (°)",
	"turbo_fov_max_deg":"Límite FOV TURBO SF.1.1",
	"turbo_fov_attack_per_s":"Entrada FOV TURBO / s","turbo_fov_release_per_s":"Salida FOV TURBO / s"
}
var rig: Node3D
var feedback: Node
var panel: PanelContainer
var badge: Label
var telemetry_label: Label
var status_label: Label
var sliders: Dictionary = {}
var numbers: Dictionary = {}
var toggles: Dictionary = {}
var buttons: Dictionary = {}
var audio_sliders: Dictionary = {}
var audio_toggles: Dictionary = {}
var audio_numbers: Dictionary = {}
var audio_telemetry: Label
var audio_status: Label
var tabs: TabContainer
var environment_sliders: Dictionary={}
var environment_toggles: Dictionary={}
var environment_numbers: Dictionary={}
var environment_telemetry: Label
var environment_status: Label
var environment_preview: CheckBox
var open_requested := false
var vehicle_vfx_status: Label
var refresh_timer := 0.0

func configure(target: Node3D) -> void:
	rig = target
	feedback = rig.speed_feedback
	layer = 40
	process_mode = Node.PROCESS_MODE_ALWAYS
	badge = Label.new()
	badge.position = Vector2(276,50)
	badge.add_theme_font_size_override("font_size",14)
	badge.add_theme_color_override("font_outline_color",Color.BLACK)
	badge.add_theme_constant_override("outline_size",4)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(badge)
	panel = PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035,0.05,0.065,0.96)
	for side in [SIDE_LEFT,SIDE_RIGHT,SIDE_TOP,SIDE_BOTTOM]: style.set_content_margin(side,12)
	panel.add_theme_stylebox_override("panel",style)
	add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation",8)
	panel.add_child(column)
	var heading := Label.new()
	heading.text = "SPEED FEEL · LABORATORIO"
	heading.add_theme_font_size_override("font_size",16)
	column.add_child(heading)
	telemetry_label = Label.new()
	telemetry_label.add_theme_font_size_override("font_size",13)
	telemetry_label.custom_minimum_size = Vector2(340,110)
	column.add_child(telemetry_label)
	var modes := HBoxContainer.new()
	column.add_child(modes)
	add_button("original","Cámara A (previa)",func(): feedback.set_experimental(false),modes)
	add_button("experimental","Cámara B (SF.1)",func(): feedback.set_experimental(true),modes)
	tabs=TabContainer.new()
	tabs.size_flags_vertical=Control.SIZE_EXPAND_FILL
	column.add_child(tabs)
	tabs.get_tab_bar().focus_mode=Control.FOCUS_NONE
	var scroll := ScrollContainer.new()
	scroll.name="Cámara"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(scroll)
	var fields := VBoxContainer.new()
	fields.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fields.add_theme_constant_override("separation",7)
	scroll.add_child(fields)
	var preset_title:=Label.new()
	preset_title.text="SF.1.1 · FOV de TURBO"
	preset_title.add_theme_font_size_override("font_size",14)
	fields.add_child(preset_title)
	var presets:=HBoxContainer.new()
	fields.add_child(presets)
	for percent in [0,10,15,25]:
		add_button("turbo_%d"%percent,"+%d%%"%percent,func(): feedback.set_setting("turbo_fov_percent",percent),presets)
	var reference:=Label.new()
	reference.text="0% = SF.1 aprobado · referencia 78° a máxima"
	reference.add_theme_font_size_override("font_size",12)
	fields.add_child(reference)
	for entry in [["experimental_enabled","Usar nueva cámara (B)"],["fov_enabled","FOV dinámico experimental"],["position_enabled","Posición baja experimental"],["motion_enabled","Reacción a acelerar / frenar"],["drift_enabled","Movimiento suave en derrape"]]:
		var toggle := CheckBox.new()
		toggle.text = entry[1]
		toggle.focus_mode = Control.FOCUS_NONE
		fields.add_child(toggle)
		toggles[entry[0]] = toggle
		toggle.toggled.connect(func(value: bool): feedback.set_setting(entry[0],value))
	for key in LABELS:
		var group := VBoxContainer.new()
		fields.add_child(group)
		var row := HBoxContainer.new()
		group.add_child(row)
		var label := Label.new()
		label.text = LABELS[key]
		label.add_theme_font_size_override("font_size",13)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		var value := Label.new()
		value.add_theme_font_size_override("font_size",13)
		row.add_child(value)
		numbers[key] = value
		var slider := HSlider.new()
		slider.min_value = Controller.RANGES[key][0]
		slider.max_value = Controller.RANGES[key][1]
		slider.step = 0.01 if key.ends_with("_m") else 0.1
		slider.focus_mode = Control.FOCUS_NONE
		slider.scrollable = false
		slider.custom_minimum_size.y = 18
		group.add_child(slider)
		sliders[key] = slider
		slider.value_changed.connect(func(v: float): feedback.set_setting(key,v))
	build_audio_tab()
	build_environment_tab()
	build_vehicle_vfx_tab()
	var files := HBoxContainer.new()
	column.add_child(files)
	add_button("defaults","Restab. cámara",feedback.reset_experiment,files)
	add_button("save","Guardar cámara",feedback.save_trial,files)
	add_button("load","Cargar cámara",feedback.load_trial,files)
	status_label = Label.new()
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.add_theme_font_size_override("font_size",12)
	status_label.custom_minimum_size = Vector2(340,34)
	column.add_child(status_label)
	feedback.settings_changed.connect(sync)
	sync()
	panel.hide()

func add_button(id: String, caption: String, action: Callable, parent: Node) -> void:
	var button := Button.new()
	button.text = caption
	button.add_theme_font_size_override("font_size",13)
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size.y = 30
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(action)
	parent.add_child(button)
	buttons[id] = button

func sync() -> void:
	for key in toggles: toggles[key].set_pressed_no_signal(feedback.settings[key])
	for key in sliders:
		sliders[key].set_value_no_signal(feedback.settings[key])
		numbers[key].text = "%.2f" % float(feedback.settings[key])
	status_label.text = feedback.status

func can_use() -> bool:
	if rig == null or rig.car == null or not rig.camera.current or not rig.car.driving_enabled or get_tree().paused: return false
	var flow := get_node_or_null("/root/GameFlow")
	return flow == null or (not flow.transition_busy and flow.current_state in [&"free_drive",&"race"])

func _input(event: InputEvent) -> void:
	if not can_use() or not event is InputEventKey or not event.pressed or event.echo: return
	if not event.ctrl_pressed or not event.alt_pressed or event.shift_pressed or event.meta_pressed: return
	if event.keycode == KEY_B:
		feedback.set_experimental(not feedback.settings["experimental_enabled"])
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_O:
		var audio: Node=feedback.audio_feedback
		audio.set_experimental(not audio.settings["experimental_enabled"])
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_L:
		var environment: Node=feedback.environment_feedback
		var modes:=["original","partial","full"]
		environment.set_mode(modes[(modes.find(environment.mode())+1)%3])
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_P:
		open_requested = not open_requested
		get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	if panel == null: return
	var allowed := can_use()
	badge.visible = allowed
	panel.visible = allowed and open_requested
	if not allowed: return
	badge.text = "Cámara %s · Audio %s · SF.3 %s · Ctrl+Alt+P: ajustes · Ctrl+Alt+L: modo" % ["B" if feedback.settings["experimental_enabled"] else "A","B" if feedback.audio_feedback.settings["experimental_enabled"] else "A",feedback.environment_feedback.mode()]
	var view := get_viewport().get_visible_rect().size
	panel.position = Vector2(view.x-388,64)
	panel.size = Vector2(364,maxf(380,minf(660,view.y-88)))
	refresh_timer -= delta
	if not panel.visible or refresh_timer > 0: return
	refresh_timer = 0.1
	if vehicle_vfx_status!=null:
		vehicle_vfx_status.text=feedback.vehicle_feedback.diagnostic()+"\n%d FPS · %.2f ms/frame aprox."%[Engine.get_frames_per_second(),1000.0/maxi(1,Engine.get_frames_per_second())]
	var audio: Node=feedback.audio_feedback
	audio_telemetry.text="RPM reales %.0f · marcha %s · carga %.0f%%\nTono %.2f× → %.2f× · banco alto %.0f%%\nViento %.0f%% · %.1f dB · CPU %d µs"%[rig.car.powertrain.rpm,rig.car.powertrain.gear_text(),audio.engine_load*100,audio.engine_pitch,audio.engine_pitch_target,audio.high_bank_mix*100,audio.wind_intensity*100,linear_to_db(maxf(audio.gains["wind"],0.00001)),audio.last_update_us]
	var environment: Node=feedback.environment_feedback
	var v: Dictionary=feedback.visual_state
	if not v.is_empty():
		environment_telemetry.text="%s · %.0f km/h · aplicado %.0f%%\nBURST real %.0f%% · enlaces %d/96\n%s"%[environment.mode(),environment.last_speed_kmh,(environment.applied_gain()*100 if environment.road_material!=null and is_instance_valid(environment.world) else 0.0),v["burst_ratio"]*100,environment.bindings.size(),environment.diagnostic()]
	var t: Dictionary = feedback.telemetry
	if t.is_empty(): return
	var states := ["NORMAL","PREPARANDO","BURST","RECUPERANDO"]
	var half_height: float = rig.car.collision_shape.size.y*0.5+rig.car.safe_margin
	var height: float = rig.camera.global_position.y-(rig.car.global_position.y-half_height)
	telemetry_label.text = "Real %.1f km/h · normal %.1f km/h%s\na %+.2f m/s² · TURBO %s\n%s · progresión BURST %.0f%%\nFOV %.2f° · objetivo B %.2f° (vertical)\nCámara: %.2f m atrás · %.2f m alto\n%d FPS · frame %.2f ms · cámara %d µs" % [t["speed_mps"]*3.6,t["normal_cap_mps"]*3.6," · T ×2" if rig.car.debug_speed_enabled else "",t["acceleration_mps2"],"ON" if t["turbo_active"] else "OFF",states[t["burst_state"]],t["burst_progress"]*100,rig.camera.fov,t["fov_target"],rig.arm.get_hit_length(),height,Engine.get_frames_per_second(),delta*1000,rig.sf1_camera_us]

func build_audio_tab() -> void:
	var audio: Node=feedback.audio_feedback
	var scroll:=ScrollContainer.new()
	scroll.name="Audio"
	scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(scroll)
	var fields:=VBoxContainer.new()
	fields.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	fields.add_theme_constant_override("separation",7)
	scroll.add_child(fields)
	audio_telemetry=Label.new()
	audio_telemetry.add_theme_font_size_override("font_size",12)
	fields.add_child(audio_telemetry)
	var modes:=HBoxContainer.new()
	fields.add_child(modes)
	add_button("audio_original","Audio A · anterior",func(): audio.set_experimental(false),modes)
	add_button("audio_experimental","Audio B · SF.2.1",func(): audio.set_experimental(true),modes)
	for entry in [["experimental_enabled","Audio experimental (B)"],["engine_enabled","Motor continuo"],["wind_enabled","Viento reactivo"]]:
		var toggle:=CheckBox.new()
		toggle.text=entry[1]
		toggle.focus_mode=Control.FOCUS_NONE
		fields.add_child(toggle)
		audio_toggles[entry[0]]=toggle
		toggle.toggled.connect(func(value: bool): audio.set_setting(entry[0],value))
	for key in AUDIO_LABELS:
		var row:=HBoxContainer.new()
		fields.add_child(row)
		var label:=Label.new()
		label.text=AUDIO_LABELS[key]
		label.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		label.add_theme_font_size_override("font_size",12)
		row.add_child(label)
		var number:=Label.new()
		number.add_theme_font_size_override("font_size",12)
		row.add_child(number)
		audio_numbers[key]=number
		var slider:=HSlider.new()
		slider.min_value=AudioController.RANGES[key][0]
		slider.max_value=AudioController.RANGES[key][1]
		slider.step=1.0 if key.ends_with("rpm") else 0.01
		slider.focus_mode=Control.FOCUS_NONE
		slider.scrollable=false
		slider.custom_minimum_size.y=18
		fields.add_child(slider)
		audio_sliders[key]=slider
		slider.value_changed.connect(func(value: float): audio.set_setting(key,value))
	var files:=HBoxContainer.new()
	fields.add_child(files)
	add_button("audio_reset","Restablecer audio",audio.reset_experiment,files)
	add_button("audio_save","Guardar",audio.save_trial,files)
	add_button("audio_load","Cargar",audio.load_trial,files)
	audio_status=Label.new()
	audio_status.add_theme_font_size_override("font_size",12)
	audio_status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	fields.add_child(audio_status)
	audio.settings_changed.connect(sync_audio)
	sync_audio()

func sync_audio() -> void:
	var audio: Node=feedback.audio_feedback
	for key in audio_toggles: audio_toggles[key].set_pressed_no_signal(audio.settings[key])
	for key in audio_sliders:
		audio_sliders[key].set_value_no_signal(audio.settings[key])
		audio_numbers[key].text="%.2f"%float(audio.settings[key])
	audio_status.text=audio.status

func build_environment_tab() -> void:
	var environment: Node=feedback.environment_feedback
	var scroll:=ScrollContainer.new()
	scroll.name="Entorno"
	scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(scroll)
	var fields:=VBoxContainer.new()
	fields.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	fields.add_theme_constant_override("separation",7)
	scroll.add_child(fields)
	environment_telemetry=Label.new()
	environment_telemetry.add_theme_font_size_override("font_size",12)
	environment_telemetry.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	fields.add_child(environment_telemetry)
	var modes:=HBoxContainer.new()
	fields.add_child(modes)
	for entry in [["original","Original"],["partial","Parcial"],["full","Completo"]]:
		add_button("sf3_"+entry[0],entry[1],func(): environment.set_mode(entry[0]),modes)
		buttons["sf3_"+entry[0]].toggle_mode=true
	add_button("sf3_reset_visible","Restablecer SF.3",environment.reset_experiment,fields)
	environment_preview=CheckBox.new()
	environment_preview.text="Vista previa estática (sin conducir)"
	environment_preview.focus_mode=Control.FOCUS_NONE
	fields.add_child(environment_preview)
	environment_preview.toggled.connect(environment.set_preview)
	for entry in [["enabled","Activar SF.3"],["asphalt_enabled","Asfalto"],["markings_enabled","Marcas viales existentes"],["edges_enabled","Referencias en bordes"],["lamps_enabled","Farolas / reflejos cercanos"]]:
		var toggle:=CheckBox.new()
		toggle.text=entry[1]
		toggle.focus_mode=Control.FOCUS_NONE
		fields.add_child(toggle)
		environment_toggles[entry[0]]=toggle
		toggle.toggled.connect(func(value: bool): environment.set_setting(entry[0],value))
	for key in ENV_LABELS:
		var row:=HBoxContainer.new()
		fields.add_child(row)
		var label:=Label.new()
		label.text=ENV_LABELS[key]
		label.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		label.add_theme_font_size_override("font_size",12)
		row.add_child(label)
		var number:=Label.new()
		number.add_theme_font_size_override("font_size",12)
		row.add_child(number)
		environment_numbers[key]=number
		var slider:=HSlider.new()
		slider.min_value=VisualController.RANGES[key][0]
		slider.max_value=VisualController.RANGES[key][1]
		slider.step=0.01
		slider.focus_mode=Control.FOCUS_NONE
		slider.scrollable=false
		slider.custom_minimum_size.y=18
		fields.add_child(slider)
		environment_sliders[key]=slider
		slider.value_changed.connect(func(value: float): environment.set_setting(key,value))
	var files:=HBoxContainer.new()
	fields.add_child(files)
	add_button("sf3_reset","Restablecer entorno",environment.reset_experiment,files)
	add_button("sf3_save","Guardar",environment.save_trial,files)
	add_button("sf3_load","Cargar",environment.load_trial,files)
	environment_status=Label.new()
	environment_status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	environment_status.add_theme_font_size_override("font_size",12)
	fields.add_child(environment_status)
	environment.settings_changed.connect(sync_environment)
	sync_environment()

func build_vehicle_vfx_tab() -> void:
	var fx: Node=feedback.vehicle_feedback
	var scroll:=ScrollContainer.new();scroll.name="SF4"
	scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(scroll)
	tabs.set_tab_title(tabs.get_tab_count()-1,"SF.4")
	var fields:=VBoxContainer.new();fields.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	scroll.add_child(fields)
	vehicle_vfx_status=Label.new();vehicle_vfx_status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	vehicle_vfx_status.add_theme_font_size_override("font_size",12);fields.add_child(vehicle_vfx_status)
	var row:=HBoxContainer.new();fields.add_child(row)
	add_button("sf4_original","A · Original",func():fx.set_setting("experimental_enabled",false),row)
	add_button("sf4_new","B · SF.4",func():fx.set_setting("experimental_enabled",true),row)
	buttons["sf4_original"].toggle_mode=true;buttons["sf4_new"].toggle_mode=true
	var sync_modes:=func():
		buttons["sf4_original"].set_pressed_no_signal(not fx.settings["experimental_enabled"])
		buttons["sf4_new"].set_pressed_no_signal(fx.settings["experimental_enabled"])
	fx.settings_changed.connect(sync_modes);sync_modes.call()
	for item in [["smoke_enabled","Humo ilustrado lavanda / rosa"],["marks_enabled","Marcas oscuras de neumáticos"],["burst_enabled","Transformación BURST"]]:
		var toggle:=CheckBox.new();toggle.text=item[1];toggle.focus_mode=Control.FOCUS_NONE
		toggle.button_pressed=fx.settings[item[0]];fields.add_child(toggle)
		toggle.toggled.connect(func(value: bool):fx.set_setting(item[0],value))
		fx.settings_changed.connect(func():toggle.set_pressed_no_signal(fx.settings[item[0]]))
	for item in [["smoke_density","Densidad de humo / rueda"],["smoke_lifetime_s","Duración humo (s)"],["smoke_size_m","Tamaño humo (m)"],["smoke_max","Máximo de partículas"],["marks_max","Límite de segmentos"],["marks_lifetime_s","Duración marcas (s)"],["burst_strength","Intensidad de carrocería"],["burst_attack_per_s","Respuesta BURST / s"],["burst_release_s","Salida BURST (s)"]]:
		var label:=Label.new();label.add_theme_font_size_override("font_size",12);fields.add_child(label)
		var slider:=HSlider.new();slider.min_value=fx.RANGES[item[0]][0];slider.max_value=fx.RANGES[item[0]][1]
		slider.step=1 if item[0] in ["smoke_max","marks_max"] else 0.01
		slider.focus_mode=Control.FOCUS_NONE;slider.scrollable=false;slider.value=fx.settings[item[0]]
		label.text=item[1]+" · %.2f"%slider.value
		fields.add_child(slider)
		slider.value_changed.connect(func(value: float):fx.set_setting(item[0],value))
		fx.settings_changed.connect(func():slider.set_value_no_signal(fx.settings[item[0]]);label.text=item[1]+" · %.2f"%slider.value)
	var preview:=CheckBox.new();preview.text="Previsualizar BURST (solo visual)";preview.focus_mode=Control.FOCUS_NONE
	fields.add_child(preview);preview.toggled.connect(func(value: bool):fx.preview_enabled=value)
	fx.settings_changed.connect(func():preview.set_pressed_no_signal(fx.preview_enabled))
	var caption:=Label.new();caption.text="Porcentaje de prueba: 0%";fields.add_child(caption)
	var amount:=HSlider.new();amount.min_value=0;amount.max_value=1;amount.step=.01;amount.focus_mode=Control.FOCUS_NONE;amount.scrollable=false
	fields.add_child(amount);amount.value_changed.connect(func(value: float):fx.preview_burst=value;caption.text="Porcentaje de prueba: %.0f%%"%(value*100))
	fx.settings_changed.connect(func():amount.set_value_no_signal(fx.preview_burst);caption.text="Porcentaje de prueba: %.0f%%"%(fx.preview_burst*100))
	var files:=HBoxContainer.new();fields.add_child(files)
	add_button("sf4_reset","Restablecer",fx.reset_experiment,files)
	add_button("sf4_save","Guardar prueba",fx.save_trial,files)
	add_button("sf4_load","Cargar prueba",fx.load_trial,files)

func bind_city_clouds(clouds: Node) -> void:
	var toggle := CheckBox.new()
	toggle.name = "NeonCloudToggle"
	toggle.text = "Nubes 2D rosa neón · Ctrl+Alt+C"
	toggle.focus_mode = Control.FOCUS_NONE
	toggle.button_pressed = clouds.enabled
	environment_preview.get_parent().add_child(toggle)
	environment_preview.get_parent().move_child(toggle,environment_preview.get_index()+1)
	toggle.toggled.connect(clouds.set_enabled)
	clouds.enabled_changed.connect(func(value: bool): toggle.set_pressed_no_signal(value))

func sync_environment() -> void:
	var environment: Node=feedback.environment_feedback
	environment_preview.set_pressed_no_signal(environment.preview_enabled)
	for mode in ["original","partial","full"]: buttons["sf3_"+mode].set_pressed_no_signal(environment.mode()==mode)
	for key in environment_toggles: environment_toggles[key].set_pressed_no_signal(environment.settings[key])
	for key in environment_sliders:
		environment_sliders[key].set_value_no_signal(environment.settings[key])
		environment_numbers[key].text="%.2f"%float(environment.settings[key])
	environment_status.text=environment.status

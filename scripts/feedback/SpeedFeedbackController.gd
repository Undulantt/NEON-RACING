extends Node
# Presentation telemetry only. No vehicle controls, forces or ability setters.
signal settings_changed
signal telemetry_updated(snapshot: Dictionary)
signal visual_state_updated(state: Dictionary)
const DEFAULT_PATH := "res://config/sf1_camera_experimental.json"
const RANGES := {
	"base_fov_deg":[55.0,85.0],"speed_fov_add_deg":[0.0,15.0],
	"turbo_fov_add_deg":[0.0,12.0],"burst_fov_add_deg":[0.0,20.0],
	"max_fov_deg":[60.0,100.0],"fov_response_per_s":[0.5,15.0],
	"spatial_response_per_s":[1.0,20.0],"heading_response_per_s":[3.0,20.0],
	"distance_m":[4.5,8.0],"height_m":[1.2,3.0],"pitch_deg":[0.0,12.0],
	"acceleration_pull_m":[0.0,0.5],"brake_push_m":[0.0,0.4],
	"turbo_pull_m":[0.0,0.5],"burst_pull_m":[0.0,0.65],
	"drift_shift_m":[0.0,0.25],"drift_yaw_deg":[0.0,4.0],
	"turbo_fov_percent":[0.0,25.0],"turbo_fov_max_deg":[82.0,115.0],
	"turbo_fov_attack_per_s":[5.0,20.0],"turbo_fov_release_per_s":[2.0,12.0]
}
var car: CharacterBody3D
var settings: Dictionary = {}
var settings_path := "user://sf1_camera_experimental.cfg"
var telemetry: Dictionary = {}
var acceleration_mps2 := 0.0
var turbo_intensity := 0.0
var burst_intensity := 0.0
var fov_target := 70.0
var turbo_fov_blend := 0.0
var fov_response_rate := 5.0
var audio_feedback: Node
var environment_feedback: Node
var vehicle_feedback: Node3D
var visual_state: Dictionary = {}
var previous_speed := 0.0
var previous_position := Vector3.ZERO
var initialized := false
var status := "Configuración experimental SF.1"
var last_sample_us := 0
var total_sample_us := 0
var samples := 0

static func defaults() -> Dictionary:
	var result: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(DEFAULT_PATH))
	result.merge(JSON.parse_string(FileAccess.get_file_as_string("res://config/sf11_turbo_fov.json")))
	return result

func configure(target: CharacterBody3D) -> void:
	car = target
	settings = defaults()
	if FileAccess.file_exists(settings_path): load_trial()
	if "--sf1-original" in OS.get_cmdline_user_args(): settings["experimental_enabled"] = false
	if "--sf1-experimental" in OS.get_cmdline_user_args(): settings["experimental_enabled"] = true
	car.recovered.connect(func(_reason): reset_telemetry())
	car.vehicle_profile_changed.connect(func(_id): reset_telemetry())
	reset_telemetry()
	audio_feedback=preload("res://scripts/feedback/SpeedAudioController.gd").new()
	add_child(audio_feedback)
	audio_feedback.configure(self)
	environment_feedback=preload("res://scripts/feedback/SpeedVisualFeedback.gd").new()
	add_child(environment_feedback)
	environment_feedback.configure(self)
	vehicle_feedback=preload("res://scripts/feedback/VehicleVFXController.gd").new()
	add_child(vehicle_feedback)
	vehicle_feedback.configure(car)

func set_setting(key: String, value: Variant) -> bool:
	if not settings.has(key) or key == "schema_version": return false
	if key=="turbo_fov_percent":
		if not (value is float or value is int) or float(value) not in [0.0,10.0,15.0,25.0]: return false
	if settings[key] is bool:
		if not value is bool: return false
		settings[key] = value
	elif RANGES.has(key):
		if not (value is float or value is int) or not is_finite(float(value)): return false
		settings[key] = clampf(float(value),RANGES[key][0],RANGES[key][1])
	else: return false
	if settings["base_fov_deg"] > settings["max_fov_deg"]:
		if key == "max_fov_deg": settings["base_fov_deg"] = settings["max_fov_deg"]
		else: settings["max_fov_deg"] = settings["base_fov_deg"]
	settings_changed.emit()
	return true

func set_experimental(enabled: bool) -> void:
	status = "B · Experimental SF.1" if enabled else "A · Cámara original"
	set_setting("experimental_enabled",enabled)

func reset_experiment() -> void:
	settings = defaults()
	status = "Valores iniciales de cámara restaurados."
	settings_changed.emit()

func save_trial() -> bool:
	var file := ConfigFile.new()
	file.set_value("sf1","settings",settings)
	var error := file.save(settings_path)
	status = "Prueba guardada en user://sf1_camera_experimental.cfg" if error == OK else "No se pudo guardar la prueba (%d)." % error
	settings_changed.emit()
	return error == OK

func load_trial() -> bool:
	var file := ConfigFile.new()
	if file.load(settings_path) != OK:
		status = "No hay una configuración de prueba guardada."
		settings_changed.emit()
		return false
	var data = file.get_value("sf1","settings",{})
	if not data is Dictionary or data.get("schema_version") != 1:
		status = "Configuración SF.1 no compatible."
		settings_changed.emit()
		return false
	for key in data:
		if key != "schema_version": set_setting(key,data[key])
	status = "Configuración experimental cargada."
	settings_changed.emit()
	return true

func reset_telemetry() -> void:
	previous_speed = car.forward_plane_speed if car != null else 0.0
	previous_position = car.global_position if car != null and car.is_inside_tree() else Vector3.ZERO
	acceleration_mps2 = 0
	turbo_intensity = 0
	burst_intensity = 0
	turbo_fov_blend = 0
	initialized = false

func sample(delta: float) -> void:
	var started := Time.get_ticks_usec()
	if car == null or delta <= 0: return
	var speed: float = maxf(0,car.forward_plane_speed)
	var teleported: bool = car.global_position.distance_to(previous_position)>12.0
	var raw_accel := (speed-previous_speed)/delta if initialized and not teleported else 0.0
	acceleration_mps2 = lerpf(acceleration_mps2,clampf(raw_accel,-15,15),1.0-exp(-6.0*delta))
	previous_speed = speed
	previous_position = car.global_position
	initialized = true
	var normal_cap: float = maxf(1.0,car.base_speed_cap)
	var speed_ratio := clampf(speed/normal_cap,0,1)
	var burst_state: int = car.abilities.burst_state
	var bursting: bool = burst_state == 2 and car.driving_enabled
	var burst_progress := clampf(car.abilities.burst_bonus/maxf(0.001,float(car.config["burst_max_bonus"])),0,1) if bursting else 0.0
	var response := 1.0-exp(-float(settings["fov_response_per_s"])*delta)
	turbo_intensity = lerpf(turbo_intensity,1.0 if car.turbo_active and car.driving_enabled else 0.0,response)
	var burst_target := 0.12+0.88*smoothstep(0,1,burst_progress) if bursting else 0.0
	burst_intensity = lerpf(burst_intensity,burst_target,response)
	var normal := float(settings["base_fov_deg"])+float(settings["speed_fov_add_deg"])*smoothstep(0,1,speed_ratio)
	var turbo := normal+float(settings["turbo_fov_add_deg"])*turbo_intensity
	var burst := normal+float(settings["burst_fov_add_deg"])*burst_intensity
	fov_target = clampf(maxf(normal,maxf(turbo,burst)),float(settings["base_fov_deg"]),float(settings["max_fov_deg"]))
	var turbo_on: bool=car.turbo_active and car.driving_enabled
	var turbo_rate:=float(settings["turbo_fov_attack_per_s"] if turbo_on else settings["turbo_fov_release_per_s"])
	turbo_fov_blend=lerpf(turbo_fov_blend,1.0 if turbo_on else 0.0,1-exp(-turbo_rate*delta))
	var percent:=float(settings["turbo_fov_percent"])/100.0
	var turbo_reference:=normal+float(settings["turbo_fov_add_deg"])
	var turbo_peak:=minf(float(settings["turbo_fov_max_deg"]),turbo_reference*(1+percent))
	if percent>0: fov_target=maxf(fov_target,lerpf(normal,turbo_peak,turbo_fov_blend))
	fov_response_rate=float(settings["turbo_fov_attack_per_s"]) if percent>0 and turbo_on else float(settings["fov_response_per_s"])
	telemetry = {"speed_mps":car.speed_mps,"forward_mps":speed,"normal_cap_mps":normal_cap,"acceleration_mps2":acceleration_mps2,"turbo_active":car.turbo_active,"turbo_intensity":turbo_intensity,"burst_state":burst_state,"burst_progress":burst_progress,"burst_intensity":burst_intensity,"burst_bonus":car.abilities.burst_bonus,"drift_amount":car.drift_amount,"slip_angle":car.slip_angle,"brake_input":car.brake_input,"fov_target":fov_target}
	telemetry.merge({"rpm":car.powertrain.rpm,"gear":car.powertrain.gear,"engine_load":car.powertrain.load,"shift_gain":car.powertrain.shift_load_multiplier(),"throttle":car.throttle_input,"idle_rpm":car.powertrain.settings["idle_rpm"],"redline_rpm":car.powertrain.settings["redline_rpm"],"audio_reference_rpm":car.powertrain.settings["audio_reference_rpm"],"burst_max_bonus":car.config["burst_max_bonus"],"grounded":car.is_on_floor(),"turbo_fov_percent":settings["turbo_fov_percent"]})
	telemetry.merge({"delta":delta,"speed_ratio":maxf(0,car.speed_mps)/normal_cap,"forward_speed_ratio":speed/normal_cap,"burst_active":bursting,"burst_ratio":burst_progress})
	telemetry_updated.emit(telemetry)
	last_sample_us = Time.get_ticks_usec()-started
	total_sample_us += last_sample_us
	samples += 1

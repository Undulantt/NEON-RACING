extends Node
# SF.2.1: presentation only. Future ability/tire consumers can use the same snapshot.
signal settings_changed
const DEFAULT_PATH := "res://config/sf21_audio_experimental.json"
const RANGES := {
	"engine_coast_db":[-40.0,-12.0],"engine_load_db":[-40.0,-12.0],"engine_body_db":[-40.0,-12.0],
	"engine_pitch_scale":[0.7,1.3],"engine_body_pitch_scale":[0.35,0.75],"engine_pitch_max":[2.0,3.0],
	"engine_lift_drop_rpm":[0.0,900.0],"engine_response_per_s":[3.0,25.0],"load_response_per_s":[3.0,20.0],
	"wind_gain_db":[-45.0,-20.0],"wind_start_kmh":[20.0,100.0],"wind_exponent":[1.0,4.0],
	"wind_overcap_gain":[0.0,0.5],"wind_pitch_base":[0.6,1.1],"wind_pitch_add":[0.0,0.5],
	"wind_response_per_s":[1.0,12.0],"ab_response_per_s":[2.0,20.0]
}
var feedback: Node
var legacy: Node
var car: CharacterBody3D
var settings := {}
var settings_path := "user://sf21_audio_experimental.cfg"
var status := "Audio B · motor y viento experimentales"
var snapshot := {}
var voices := {}
var gains := {"coast":0.0,"load":0.0,"body":0.0,"wind":0.0}
var engine_pitch := 0.3
var engine_pitch_target := 0.3
var engine_load := 0.0
var wind_intensity := 0.0
var wind_target := 0.0
var wind_pitch := 0.85
var blend := 0.0
var engine_assets: Dictionary = {}
var high_bank_mix := 0.0
var last_update_us := 0

static func defaults() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(DEFAULT_PATH))

func configure(source: Node) -> void:
	feedback=source
	car=feedback.car
	legacy=car.feedback
	engine_assets=JSON.parse_string(FileAccess.get_file_as_string("res://config/combustion_audio_assets.json"))
	settings=defaults()
	if FileAccess.file_exists(settings_path): load_trial()
	if "--sf2-original" in OS.get_cmdline_user_args(): settings["experimental_enabled"]=false
	if "--sf2-experimental" in OS.get_cmdline_user_args(): settings["experimental_enabled"]=true
	# Run after DrivingFeedback, which writes fresh absolute legacy gains each frame.
	# This keeps its algorithm, cues and target telemetry byte-for-byte unchanged.
	process_priority=100
	feedback.telemetry_updated.connect(func(value: Dictionary): snapshot=value)
	car.recovered.connect(func(_why): reset_history())
	car.vehicle_profile_changed.connect(func(_id): reset_history())
	reset_history()
	if DisplayServer.get_name()=="headless" and not "--capture-engine-audio" in OS.get_cmdline_user_args(): return
	for bus in ["Engine","Effects"]:
		if AudioServer.get_bus_index(bus)<0:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count-1,bus)
			AudioServer.set_bus_send(AudioServer.bus_count-1,"Master")
	for id in ["coast","load","load_high","body","wind"]:
		var voice:=AudioStreamPlayer.new()
		voice.bus="Effects" if id=="wind" else "Engine"
		if id=="wind":
			var stream:=AudioStreamWAV.load_from_file("res://assets/audio/sf21_wind_placeholder.wav")
			stream.loop_mode=AudioStreamWAV.LOOP_FORWARD
			stream.loop_end=stream.data.size()/2
			voice.stream=stream
		else:
			var stream:=AudioStreamWAV.load_from_file(engine_assets[id])
			stream.loop_mode=AudioStreamWAV.LOOP_FORWARD
			stream.loop_end=stream.data.size()/2
			voice.stream=stream
		voice.volume_db=-80
		add_child(voice)
		voice.play()
		voices[id]=voice

func reset_history() -> void:
	engine_pitch=car.powertrain.rpm/float(car.powertrain.settings["audio_reference_rpm"])
	engine_load=0
	high_bank_mix=0
	wind_intensity=0
	for id in gains: gains[id]=0.0

func set_setting(key: String, value: Variant) -> bool:
	if not settings.has(key) or key=="schema_version": return false
	if settings[key] is bool:
		if not value is bool: return false
		settings[key]=value
	elif RANGES.has(key):
		if not (value is float or value is int) or not is_finite(float(value)): return false
		settings[key]=clampf(float(value),RANGES[key][0],RANGES[key][1])
	else: return false
	settings_changed.emit()
	return true

func set_experimental(value: bool) -> void:
	status="Audio B · motor/viento SF.2.1" if value else "Audio A · mezcla anterior"
	set_setting("experimental_enabled",value)

func reset_experiment() -> void:
	settings=defaults()
	status="Valores de audio B restaurados."
	settings_changed.emit()

func save_trial() -> bool:
	var file:=ConfigFile.new()
	file.set_value("sf21","settings",settings)
	var error:=file.save(settings_path)
	status="Audio guardado en user://sf21_audio_experimental.cfg" if error==OK else "No se pudo guardar audio."
	settings_changed.emit()
	return error==OK

func load_trial() -> bool:
	var file:=ConfigFile.new()
	var error:=file.load(settings_path)
	var value: Variant=file.get_value("sf21","settings",{}) if error==OK else {}
	if not value is Dictionary or value.get("schema_version")!=1:
		status="No hay configuración de audio SF.2.1 compatible."
		settings_changed.emit()
		return false
	for key in value:
		if key!="schema_version": set_setting(key,value[key])
	status="Configuración de audio cargada."
	settings_changed.emit()
	return true

func _process(delta: float) -> void:
	if snapshot.is_empty() or delta<=0: return
	var started:=Time.get_ticks_usec()
	var s:=settings
	blend=lerpf(blend,1.0 if s["experimental_enabled"] else 0.0,1-exp(-float(s["ab_response_per_s"])*delta))
	if blend<0.0001 and not s["experimental_enabled"]: blend=0
	if blend>0.9999 and s["experimental_enabled"]: blend=1
	var rpm: float=snapshot["rpm"]
	var idle: float=snapshot["idle_rpm"]
	var reference: float=snapshot["audio_reference_rpm"]
	var load_value: float=snapshot["engine_load"]
	engine_load=lerpf(engine_load,load_value,1-exp(-float(s["load_response_per_s"])*delta))
	# Acoustic lift-off offset, never a write to RPM or transmission state.
	var acoustic_rpm:=maxf(idle,rpm-(1-engine_load)*float(s["engine_lift_drop_rpm"])*smoothstep(idle,idle+1000,rpm))
	engine_pitch_target=clampf(acoustic_rpm/reference*float(s["engine_pitch_scale"]),0.2,float(s["engine_pitch_max"]))
	engine_pitch=lerpf(engine_pitch,engine_pitch_target,1-exp(-float(s["engine_response_per_s"])*delta))
	# Two RPM reference banks retain exhaust texture through the seven real gears.
	var bank_target:=smoothstep(float(engine_assets["high_bank_start_rpm"]),float(engine_assets["high_bank_full_rpm"]),rpm)
	high_bank_mix=lerpf(high_bank_mix,bank_target,1-exp(-float(s["engine_response_per_s"])*delta))
	var normalized_rpm:=clampf((rpm-idle)/maxf(1,float(snapshot["redline_rpm"])-idle),0,1)
	var acceleration:=clampf(float(snapshot["acceleration_mps2"])/8,0,1)
	var shift: float=snapshot["shift_gain"]
	var cap: float=maxf(1,float(snapshot["normal_cap_mps"]))
	var speed: float=snapshot["speed_mps"]
	var start:=minf(float(s["wind_start_kmh"])/3.6,cap*0.9)
	var pressure:=pow(smoothstep(start,cap,speed),float(s["wind_exponent"]))
	var overcap:=clampf((speed/cap-1)/maxf(0.01,float(snapshot["burst_max_bonus"])),0,1)
	wind_target=pressure+overcap*float(s["wind_overcap_gain"])
	wind_intensity=lerpf(wind_intensity,wind_target,1-exp(-float(s["wind_response_per_s"])*delta))
	wind_pitch=float(s["wind_pitch_base"])+minf(speed/cap,1.5)*float(s["wind_pitch_add"])
	var targets:={
		"coast":db_to_linear(float(s["engine_coast_db"]))*(0.46+0.16*normalized_rpm)*(0.7+0.3*shift),
		"load":db_to_linear(float(s["engine_load_db"]))*(0.03+0.90*engine_load+0.12*acceleration)*shift,
		"body":db_to_linear(float(s["engine_body_db"]))*(0.30+0.45*engine_load)*(1-0.15*normalized_rpm),
		"wind":db_to_linear(float(s["wind_gain_db"]))*wind_intensity
	}
	var low_bank_pitch:=engine_pitch*reference/float(engine_assets["low_reference_rpm"])
	var audible: bool=car.driving_enabled and not legacy.muted
	for id in gains:
		var enabled: bool=s["wind_enabled"] if id=="wind" else s["engine_enabled"]
		gains[id]=lerpf(gains[id],targets[id] if enabled else 0.0,1-exp(-float(s["wind_response_per_s"] if id=="wind" else s["load_response_per_s"])*delta))
		if voices.has(id):
			var voice: AudioStreamPlayer=voices[id]
			voice.pitch_scale=wind_pitch if id=="wind" else low_bank_pitch*float(s["engine_body_pitch_scale"]) if id=="body" else low_bank_pitch
			voice.volume_linear=gains[id]*blend*(sqrt(1-high_bank_mix) if id=="load" else 1.0) if audible else 0.0
	if voices.has("load_high"):
		var high: AudioStreamPlayer=voices["load_high"]
		high.pitch_scale=engine_pitch*reference/float(engine_assets["high_reference_rpm"])
		high.volume_linear=gains["load"]*sqrt(high_bank_mix)*blend if audible else 0.0
	# Only crossfade the two legacy continuous motor loops. Shift/tire/boost stay intact.
	if blend>0:
		for voice in [legacy.engine,legacy.engine_load]:
			if voice!=null: voice.volume_linear*=1-blend
	last_update_us=Time.get_ticks_usec()-started

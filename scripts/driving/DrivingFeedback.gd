extends Node

# Original combustion loops cached once; RPM comes from the same gearbox as the dial.
static var tone_cache: Dictionary = {}
var car: CharacterBody3D
var engine: AudioStreamPlayer
var engine_load: AudioStreamPlayer
var shift_player: AudioStreamPlayer
var tires: AudioStreamPlayer
var boost: AudioStreamPlayer
var muted := false
var engine_pitch := 0.3
var engine_pitch_target := 0.3
var throttle_blend := 0.0
var downshift_blip := 0.0

func tone(kind: int) -> AudioStreamWAV:
	if tone_cache.has(kind):
		return tone_cache[kind]
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = 22050
	var cue := kind >= 4
	var count := int(22050 * (0.10 if kind == 4 else 0.14)) if cue else 22050
	stream.loop_mode = AudioStreamWAV.LOOP_DISABLED if cue else AudioStreamWAV.LOOP_FORWARD
	stream.loop_end = count
	var bytes := PackedByteArray()
	bytes.resize(count * 2)
	var random := RandomNumberGenerator.new()
	random.seed = 37 + kind
	for i in range(count):
		var t := float(i) / 22050.0
		var sample := 0.0
		var phase := TAU * 100.0 * t + 0.10 * sin(TAU * 50.0 * t)
		match kind:
			0: sample = sin(phase)*0.38 + sin(phase*2)*0.12 + sin(phase*3)*0.04 + sin(phase*5)*0.015
			1: sample = random.randf_range(-0.5,0.5)*0.6 + sin(TAU*880*t)*0.12
			2: sample = random.randf_range(-0.5,0.5)*0.5 + sin(TAU*220*t)*0.1
			3:
				sample = sin(phase)*0.36 + sin(phase*2)*0.21 + sin(phase*3)*0.13 + sin(phase*5)*0.06 + sin(phase*7)*0.025
				sample += (sin(TAU*991*t)+sin(TAU*723*t))*0.012*(0.5+0.5*sin(phase))
			4,5:
				var envelope := sin(PI*float(i)/float(count)) * exp(-t*18.0)
				sample = (sin(TAU*(70 if kind==4 else 110)*t)*0.22 + random.randf_range(-0.15,0.15))*envelope
		bytes.encode_s16(i*2,clampi(int(sample*24500),-32767,32767))
	stream.data = bytes
	tone_cache[kind] = stream
	return stream

func player(kind: int, autoplay := true) -> AudioStreamPlayer:
	var audio := AudioStreamPlayer.new()
	audio.stream = tone(kind)
	audio.volume_db = -60
	add_child(audio)
	if autoplay:
		audio.play()
	return audio

func attach(target: CharacterBody3D) -> void:
	car = target
	engine_pitch = car.powertrain.rpm / float(car.powertrain.settings["audio_reference_rpm"])
	car.powertrain.gear_changed.connect(_on_gear_changed)
	# Telemetry and gain targets still run without creating audio streams in tests.
	if DisplayServer.get_name() == "headless" and not "--capture-engine-audio" in OS.get_cmdline_user_args():
		return
	engine = player(0)
	engine_load = player(3)
	shift_player = player(4,false)
	tires = player(1)
	boost = player(2)

func engine_players() -> Array:
	return [engine,engine_load,shift_player]

func _on_gear_changed(previous: int, current: int) -> void:
	if previous <= 0 or current <= 0:
		return
	if current < previous:
		downshift_blip = 1.0
	if shift_player != null and not muted and car.driving_enabled:
		shift_player.stream = tone(4 if current > previous else 5)
		shift_player.volume_db = -27
		shift_player.play()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("audio_toggle") and not event.is_echo():
		muted = not muted
		if muted and shift_player != null:
			shift_player.stop()

func _process(delta: float) -> void:
	if car == null:
		return
	var mix := 1.0-exp(-14.0*delta)
	engine_pitch_target = clampf(car.powertrain.rpm / float(car.powertrain.settings["audio_reference_rpm"]),0.25,3.0)
	engine_pitch = lerpf(engine_pitch,engine_pitch_target,mix)
	throttle_blend = lerpf(throttle_blend,car.powertrain.load,mix)
	downshift_blip = maxf(0,downshift_blip-delta*7.0)
	if engine == null:
		return
	var audible: bool = not muted and car.driving_enabled
	var shift_gain: float = car.powertrain.shift_load_multiplier()
	engine.pitch_scale = engine_pitch
	engine_load.pitch_scale = engine_pitch
	var coast_gain := (0.68 - throttle_blend*0.25) * (0.65+0.35*shift_gain)
	var load_gain := (throttle_blend*0.85+downshift_blip*0.26) * shift_gain
	engine.volume_db = -23.0 + linear_to_db(maxf(coast_gain,0.001)) if audible else -60.0
	engine_load.volume_db = -21.0 + linear_to_db(maxf(load_gain,0.001)) if audible else -60.0
	if not audible:
		shift_player.volume_db = -60
	tires.volume_db = lerpf(tires.volume_db,-27.0+car.drift_amount*10.0 if audible and car.drift_amount>0.12 else -60.0,mix)
	boost.volume_db = lerpf(boost.volume_db,-22.0 if audible and car.turbo_active else -28.0 if audible and car.drift_boost_active else -60.0,mix)

extends Node

# Original procedural placeholder audio. Loops are built once, never per frame.
var car: CharacterBody3D
var engine: AudioStreamPlayer
var tires: AudioStreamPlayer
var boost: AudioStreamPlayer
var muted := false

func tone(kind: int) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = 22050
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_end = 22050
	var bytes := PackedByteArray()
	bytes.resize(22050 * 2)
	var random := RandomNumberGenerator.new()
	random.seed = 37 + kind
	for i in range(22050):
		var t := float(i) / 22050.0
		var sample := 0.0
		match kind:
			0: sample = sin(TAU * 55 * t) * 0.45 + sin(TAU * 110 * t) * 0.2 + sin(TAU * 165 * t) * 0.08
			1: sample = random.randf_range(-0.5, 0.5) * 0.6 + sin(TAU * 880 * t) * 0.12
			2: sample = random.randf_range(-0.5, 0.5) * 0.5 + sin(TAU * 220 * t) * 0.1
		bytes.encode_s16(i * 2, int(sample * 24000))
	stream.data = bytes
	return stream

func player(kind: int) -> AudioStreamPlayer:
	var audio := AudioStreamPlayer.new()
	audio.stream = tone(kind)
	audio.volume_db = -60
	add_child(audio)
	audio.play()
	return audio

func attach(target: CharacterBody3D) -> void:
	car = target
	# Automated headless runs do not need audio synthesis.
	if DisplayServer.get_name() == "headless":
		return
	engine = player(0)
	tires = player(1)
	boost = player(2)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("audio_toggle") and not event.is_echo():
		muted = not muted

func _process(delta: float) -> void:
	if engine == null:
		return
	var audible: bool = not muted and car.driving_enabled
	var mix := 1.0 - exp(-8.0 * delta)
	engine.pitch_scale = lerpf(engine.pitch_scale, 0.8 + car.speed_mps / 15.0 + maxf(car.throttle_input, 0) * 0.18, mix)
	engine.volume_db = lerpf(engine.volume_db, (-25.0 + maxf(car.throttle_input, 0) * 6.0) if audible else -60.0, mix)
	tires.volume_db = lerpf(tires.volume_db, -27.0 + car.drift_amount * 10.0 if audible and car.drift_amount > 0.12 else -60.0, mix)
	boost.volume_db = lerpf(boost.volume_db, -22.0 if audible and car.turbo_active else -28.0 if audible and car.drift_boost_active else -60.0, mix)

extends SceneTree
# Real physical acceleration, lift-off and braking. No fabricated RPM in this test.
var car: CharacterBody3D
var rig: Node3D
var capture: AudioEffectCapture
var samples: Array=[]
var states: Array=[]
var results: Array=[]
var failures: Array=[]
func _initialize() -> void: run.call_deferred()
func drain() -> void:
	var count:=capture.get_frames_available()
	if count>0: samples.append(capture.get_buffer(count))
func wait_frames(count: int) -> void:
	for i in range(count):
		await car.physics_updated
		drain()
func check(value: bool, text: String) -> void:
	if not value: failures.append(text);push_error(text)
func run() -> void:
	var prefix:="sf21r" if "--combustion-review" in OS.get_cmdline_user_args() else "sf21"
	var level:=Node3D.new()
	root.add_child(level)
	var floor_body:=StaticBody3D.new()
	var floor_shape:=CollisionShape3D.new()
	var box:=BoxShape3D.new()
	box.size=Vector3(200,1,10000)
	floor_shape.shape=box
	floor_body.position.y=-0.5
	floor_body.add_child(floor_shape)
	level.add_child(floor_body)
	car=preload("res://scenes/cars/PlayerCar.tscn").instantiate()
	level.add_child(car)
	car.external_control=true
	car.configure({"roads":[{"points_xz":[[0,4000],[0,-4000]],"oneway":false,"street_name":"AUDIO PHYSICS TEST FIXTURE, NOT MAP"}]},{"bounds_xz":[-90,-4500,90,4500],"spawn":{"position_xz":[0,0],"forward_xz":[0,-1]}})
	rig=preload("res://scripts/driving/FollowCamera.gd").new()
	level.add_child(rig)
	rig.attach(car)
	var audio: Node=rig.speed_feedback.audio_feedback
	audio.reset_experiment()
	check(audio.voices.size()==5 and car.feedback.engine!=null,"Actual stream players created with capture flag")
	for bus in ["Master","Engine","Effects"]:
		var index:=AudioServer.get_bus_index(bus)
		AudioServer.set_bus_volume_db(index,0)
		AudioServer.set_bus_mute(index,false)
	for voice in car.feedback.engine_players(): voice.bus="Engine"
	car.feedback.tires.bus="Effects"
	car.feedback.boost.bus="Effects"
	capture=AudioEffectCapture.new()
	capture.buffer_length=2.0
	AudioServer.add_bus_effect(0,capture)
	if "--cleanup-smoke" in OS.get_cmdline_user_args():
		await wait_frames(30)
		await close_audio_fixture(level,audio)
		print("COMBUSTION_CLEANUP_OK")
		quit(0)
		return
	for mode in ([true] if "--new-only" in OS.get_cmdline_user_args() else [false,true]):
		car.apply_vehicle_profile("VECTOR")
		car.global_transform=car.spawn_transform
		car.velocity=Vector3.ZERO
		car.speed_mps=0;car.signed_speed=0
		car.reset_surface_motion()
		car.abilities.configure(car.config)
		car.powertrain.reset()
		car.set_controls(0,0)
		var starting_ups: int=car.powertrain.upshifts
		var starting_downs: int=car.powertrain.downshifts
		audio.set_experimental(mode)
		await wait_frames(90)
		# Drain continuously, including warmup; never clear a live recording buffer.
		samples.clear()
		states.clear()
		for stage in [["idle",1.0,0.0],["acceleration",20.0,1.0],["lift",2.0,0.0],["braking",6.0,-1.0]]:
			car.set_controls(stage[2],0)
			var peak:=0.0
			var max_wind:=0.0
			var min_pitch:=10.0
			var max_pitch:=0.0
			for i in range(roundi(stage[1]*60)):
				await wait_frames(1)
				peak=maxf(peak,car.speed_mps*3.6)
				max_wind=maxf(max_wind,audio.wind_intensity)
				min_pitch=minf(min_pitch,audio.engine_pitch)
				max_pitch=maxf(max_pitch,audio.engine_pitch)
			states.append({"stage":stage[0],"peak_kmh":peak,"rpm_end":car.powertrain.rpm,"gear_end":car.powertrain.gear,"wind_peak":max_wind,"pitch_min":min_pitch,"pitch_max":max_pitch})
		var frames:=0
		var peak_sample:=0.0
		var energy:=0.0
		for chunk in samples: frames+=chunk.size()
		var bytes:=PackedByteArray()
		bytes.resize(frames*4)
		var offset:=0
		for chunk in samples:
			for sample_value: Vector2 in chunk:
				peak_sample=maxf(peak_sample,maxf(absf(sample_value.x),absf(sample_value.y)))
				energy+=(sample_value.x*sample_value.x+sample_value.y*sample_value.y)*0.5
				bytes.encode_s16(offset,clampi(roundi(sample_value.x*32767),-32767,32767))
				bytes.encode_s16(offset+2,clampi(roundi(sample_value.y*32767),-32767,32767))
				offset+=4
		var stream:=AudioStreamWAV.new()
		stream.stereo=true;stream.mix_rate=int(AudioServer.get_mix_rate());stream.format=AudioStreamWAV.FORMAT_16_BITS;stream.data=bytes
		var mode_name:="B" if mode else "A"
		stream.save_to_wav("res://docs/evidence/%s_audio_%s.wav"%[prefix,mode_name])
		check(frames>AudioServer.get_mix_rate()*25 and peak_sample>0.005 and peak_sample<0.95,"Mode "+mode_name+" contains audio without clipping")
		check(car.powertrain.upshifts-starting_ups>=5 and car.powertrain.downshifts-starting_downs>0,"Physical gear changes are exercised")
		var value:={"mode":mode_name,"frames":frames,"duration_s":frames/AudioServer.get_mix_rate(),"peak":peak_sample,"rms":sqrt(energy/maxi(frames,1)),"states":states.duplicate(true),"upshifts":car.powertrain.upshifts-starting_ups,"downshifts":car.powertrain.downshifts-starting_downs}
		results.append(value)
		print("SF21_CAPTURE_MODE ",JSON.stringify(value))
	# These checks exercise real audible stream gain/routing, not only target numbers.
	car.set_controls(0,0)
	car.feedback.muted=true
	await wait_frames(3)
	var muted:=true
	for voice in audio.voices.values(): muted=muted and voice.volume_linear==0
	check(muted,"Legacy car mute also mutes all new layers")
	car.feedback.muted=false
	car.driving_enabled=false
	await wait_frames(3)
	var stopped:=true
	for voice in audio.voices.values(): stopped=stopped and voice.volume_linear==0
	check(stopped,"Disabled driving silences new layers")
	car.driving_enabled=true
	paused=true
	await process_frame
	await process_frame
	var paused_streams:=true
	for voice in audio.voices.values(): paused_streams=paused_streams and voice.stream_paused
	check(paused_streams,"Scene pause pauses actual audio streams")
	paused=false
	check(capture.get_discarded_frames()==0,"Audio capture buffer did not overflow")
	var report:={"passed":failures.is_empty(),"failures":failures,"scenario":"Real VECTOR physics at 60 Hz: idle, 20 seconds acceleration, 2 seconds lift and 6 seconds brake; A/B only affects presentation; Master bus capture without music; synthetic flat fixture, not city FPS","sample_rate":AudioServer.get_mix_rate(),"discarded_frames":capture.get_discarded_frames(),"counter_semantics":"per-pass deltas; pitch ranges describe the experimental controller even when audio A is selected","samples":results}
	FileAccess.open("res://docs/%s_audio_capture.json"%prefix,FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("SF21_AUDIO_CAPTURE ",JSON.stringify({"passed":failures.is_empty(),"failures":failures}))
	await close_audio_fixture(level,audio)
	quit(0 if failures.is_empty() else 1)

func close_audio_fixture(level: Node3D, audio: Node) -> void:
	for voice in audio.voices.values(): voice.stop()
	for voice in car.feedback.engine_players()+[car.feedback.tires,car.feedback.boost]: voice.stop()
	AudioServer.remove_bus_effect(0,AudioServer.get_bus_effect_count(0)-1)
	level.queue_free()
	for i in range(6): await process_frame

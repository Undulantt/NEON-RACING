extends "res://tests/benchmark_burst_balance.gd"

var recording := false
var finishing := false
var elapsed := 0.0
var capture_flags := {}
var engine_record: AudioEffectCapture
var audio_chunks: Array = []
var engine_bus := -1
var telemetry: Array = []

func snapshot(name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://docs/evidence/tachometer_"+name+".png")

func drain_audio() -> void:
	if engine_record != null:
		var available := engine_record.get_frames_available()
		if available > 0:
			audio_chunks.append(engine_record.get_buffer(available))

func _process(_delta: float) -> bool:
	if recording:
		drain_audio()
	if not recording or finishing or car==null:
		return false
	var gearbox=car.powertrain
	if gearbox.gear==1 and gearbox.rpm>6800 and not capture_flags.has("before_shift"):
		capture_flags["before_shift"]=true
		snapshot.call_deferred("before_shift")
	if gearbox.gear==2 and gearbox.rpm<5800 and not capture_flags.has("after_shift"):
		capture_flags["after_shift"]=true
		snapshot.call_deferred("after_shift")
	if gearbox.gear==7 and gearbox.rpm>6500 and not capture_flags.has("top_gear"):
		capture_flags["top_gear"]=true
		snapshot.call_deferred("top_gear")
	return false

func step(frames: int) -> void:
	for i in range(frames):
		if recording and elapsed>=22.0:
			car.set_controls(-1,car.command_steer)
		await car.physics_updated
		if recording:
			elapsed += car.get_physics_process_delta_time()
			telemetry.append({"t":elapsed,"gear":car.powertrain.gear,"rpm":car.powertrain.rpm,"pitch":car.feedback.engine_pitch,"speed_kmh":car.speed_mps*3.6,"turbo":car.turbo_charge})
			if elapsed>23 and car.signed_speed<0.5 and not finishing:
				finishing=true
				finish.call_deferred()

func finish() -> void:
	recording=false
	car.set_controls(0,0,true)
	car.set_physics_process(false)
	drain_audio()
	var discarded_frames := engine_record.get_discarded_frames()
	var engine_routing := true
	for player in car.feedback.engine_players():
		engine_routing = engine_routing and player != null and player.bus == &"Engine"
	var frame_count := 0
	for chunk in audio_chunks:
		frame_count += chunk.size()
	var data := PackedByteArray()
	data.resize(frame_count*4)
	var index := 0
	for chunk in audio_chunks:
		for frame: Vector2 in chunk:
			data.encode_s16(index,clampi(roundi(frame.x*32767),-32767,32767))
			data.encode_s16(index+2,clampi(roundi(frame.y*32767),-32767,32767))
			index += 4
	var audio := AudioStreamWAV.new()
	audio.format = AudioStreamWAV.FORMAT_16_BITS
	audio.stereo = true
	audio.mix_rate = int(AudioServer.get_mix_rate())
	audio.data = data
	var audio_bytes := data.size()
	audio.save_to_wav("res://docs/evidence/engine_gear_changes.wav")
	await snapshot("braking")
	var shifts_up:int=car.powertrain.upshifts
	var shifts_down:int=car.powertrain.downshifts
	var passed:bool=shifts_up==6 and shifts_down==6 and audio_bytes>22050 and capture_flags.size()==3 and engine_routing and discarded_frames==0
	var report:={"passed":passed,"scenario":"Real standing start and braking on existing C2 street, VECTOR, render limited to 60 FPS, Engine bus recording with no music/effects","elapsed_s":elapsed,"upshifts":shifts_up,"downshifts":shifts_down,"audio_bytes":audio_bytes,"discarded_audio_frames":discarded_frames,"engine_bus_routing":engine_routing,"screenshots":capture_flags,"telemetry":telemetry}
	FileAccess.open("res://docs/powertrain_capture_validation.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("POWERTRAIN_CAPTURE ",JSON.stringify({"passed":passed,"duration":elapsed,"audio_bytes":audio_bytes,"upshifts":shifts_up,"downshifts":shifts_down,"screenshots":capture_flags}))
	world.queue_free()
	for i in range(4):await process_frame
	quit(0 if passed else 1)

func run() -> void:
	root.size=Vector2i(1280,720)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	world=preload("res://scenes/Main.tscn").instantiate()
	root.add_child(world)
	car=world.player
	car.external_control=true
	await step(90)
	engine_bus=AudioServer.get_bus_index("Engine")
	AudioServer.set_bus_mute(engine_bus,false)
	AudioServer.set_bus_volume_db(engine_bus,0)
	engine_record=AudioEffectCapture.new()
	engine_record.buffer_length=2.0
	AudioServer.add_bus_effect(engine_bus,engine_record)
	var data:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tracks/extension_C2.json"))
	var geometry:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://docs/burst_route_geometry.json"))
	var span:Dictionary=geometry["extension_C2"]["longest_runs"][0]
	build_path(data["points_xz"].slice(int(span["first_point_index"]),int(span["last_point_index"])+1))
	engine_record.clear_buffer()
	recording=true
	var result:Dictionary=await route("VECTOR",9000)
	if not finishing:
		print("POWERTRAIN_CAPTURE_FAILED ",JSON.stringify(result))
		quit(1)

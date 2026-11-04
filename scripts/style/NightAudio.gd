extends CanvasLayer

var music: AudioStreamPlayer
var ambience: AudioStreamPlayer
var panel: PanelContainer
var config: Dictionary
var state := ""
var streams: Dictionary = {}
var gains: Dictionary = {}

func configure(world: Node3D, settings: Dictionary) -> void:
	config = settings
	process_mode = Node.PROCESS_MODE_ALWAYS
	var saved := ConfigFile.new()
	saved.load("user://night_audio.cfg")
	for bus in ["Music", "Engine", "Effects"]:
		if AudioServer.get_bus_index(bus) < 0:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count-1,bus)
			AudioServer.set_bus_send(AudioServer.bus_count-1,"Master")
		gains[bus] = float(saved.get_value("volume",bus,config["default_volumes"][bus]))
		set_gain(bus,gains[bus],false)
	var feedback = world.player.feedback
	if feedback.engine != null:
		for voice in feedback.engine_players():
			voice.bus = "Engine"
		feedback.tires.bus = "Effects"
		feedback.boost.bus = "Effects"
	music = AudioStreamPlayer.new()
	music.bus = "Music"
	music.volume_db = -10
	music.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(music)
	music.finished.connect(func(): music.play())
	for key in config["music"]:
		var path: String = config["music"][key]
		streams[key] = AudioStreamWAV.load_from_file(path) if path.ends_with(".wav") else load(path)
	set_music_state("free_drive")
	ambience = AudioStreamPlayer.new()
	ambience.bus = "Effects"
	ambience.volume_db = -28
	ambience.stream = AudioStreamWAV.load_from_file("res://assets/audio/malecon_surf.wav")
	ambience.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(ambience)
	ambience.finished.connect(func(): ambience.play())
	ambience.play()
	var hint := Label.new()
	hint.text = "LA PAZ / NEON COAST"
	hint.position = Vector2(270,24)
	hint.add_theme_color_override("font_color",Color("67e5ef"))
	add_child(hint)
	panel = PanelContainer.new()
	panel.position = Vector2(440,180)
	panel.custom_minimum_size = Vector2(360,220)
	panel.visible = false
	add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	var title := Label.new()
	title.text = "MEZCLA NOCTURNA · F7 cerrar"
	box.add_child(title)
	for bus in ["Music", "Engine", "Effects"]:
		var label := Label.new()
		label.text = {"Music":"Música", "Engine":"Motor", "Effects":"Efectos y ambiente"}[bus]
		box.add_child(label)
		var slider := HSlider.new()
		slider.min_value = 0
		slider.max_value = 1
		slider.step = 0.01
		slider.value = gains[bus]
		slider.value_changed.connect(func(value: float): set_gain(bus,value))
		box.add_child(slider)

func set_gain(bus: String, value: float, save := true) -> void:
	gains[bus] = clampf(value,0,1)
	var index := AudioServer.get_bus_index(bus)
	AudioServer.set_bus_volume_db(index,linear_to_db(maxf(gains[bus],0.0001)))
	AudioServer.set_bus_mute(index,gains[bus] <= 0)
	if save:
		var file := ConfigFile.new()
		for key in gains:
			file.set_value("volume",key,gains[key])
		file.save("user://night_audio.cfg")

func set_music_state(next: String) -> void:
	if not streams.has(next) or next == state:
		return
	state = next
	if music.stream != streams[next]:
		music.stream = streams[next]
		music.play()

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F7:
		panel.visible = not panel.visible
		get_viewport().set_input_as_handled()

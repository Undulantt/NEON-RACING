extends Node
# A single playlist survives free-drive / race transitions, independently of the world.
const TRACKS = [preload("res://assets/audio/VENDABAL.mp3"),preload("res://assets/audio/PHEAT TWO.mp3"),preload("res://assets/audio/HEART.mp3")]
var player: AudioStreamPlayer
var index := 0

func configure(flow: Node) -> void:
	process_mode=Node.PROCESS_MODE_ALWAYS
	player=AudioStreamPlayer.new();player.name="DrivingPlaylist";player.bus="Music";player.volume_db=-10
	add_child(player);player.finished.connect(_advance)
	flow.state_changed.connect(set_state)
	set_state(flow.current_state)

func _advance() -> void:
	index=(index+1)%TRACKS.size()
	_play()

func _play() -> void:
	var stream: AudioStreamMP3=TRACKS[index].duplicate()
	stream.loop=false;player.stream=stream;player.play()

func set_state(state: StringName) -> void:
	if state in [&"free_drive",&"race"]:
		player.stream_paused=false
		if not player.playing:_play()
	elif state in [&"loading",&"results"]:
		player.stream_paused=true
	else:
		player.stop();player.stream_paused=false

func _exit_tree() -> void:
	if is_instance_valid(player):player.stop()

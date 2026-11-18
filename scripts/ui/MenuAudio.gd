extends Node
# One persistent owner: menu navigation keeps the same song and click tails.
const MUSIC_STATES: Array[StringName]=[&"main_menu",&"credits",&"how_to_play",&"play_menu",&"vehicle_select",&"race_select",&"options"]
const SONG=preload("res://assets/audio/Main menu.mp3")
const CLICK=preload("res://assets/audio/Button-Notification.wav")
const FADE_IN_SECONDS:=1.5
const FADE_OUT_SECONDS:=.45
var music: AudioStreamPlayer
var clicks: AudioStreamPlayer
var click_players: Array[AudioStreamPlayer]=[]
var next_click:=0
var fade: Tween
var cinematic_active:=false
var wants_music:=false
var shutting_down:=false
var using_navigation:=false
var click_count:=0
var music_starts:=0
var flow: Node
var menu_owner: WeakRef
var gain:=0.0:
	set(value):
		gain=clampf(value,0,1)
		if is_instance_valid(music):music.volume_db=-8.0+linear_to_db(maxf(.00001,gain))

func configure(owner: Node) -> void:
	flow=owner
	process_mode=Node.PROCESS_MODE_ALWAYS
	add_to_group("ui_feedback")
	music=AudioStreamPlayer.new();music.name="MainMenuMusic";music.bus="Music"
	var song: AudioStreamMP3=SONG.duplicate();song.loop=true;music.stream=song
	add_child(music);gain=0
	for i in range(4):
		var player:=AudioStreamPlayer.new();player.name="ButtonFeedback%d"%i;player.bus="Effects"
		player.stream=CLICK;player.volume_db=-12;add_child(player);click_players.append(player)
	clicks=click_players[0]
	flow.state_changed.connect(set_state)
	set_state(flow.current_state)

func bind_shell(shell: Control) -> void:
	if menu_owner!=null and menu_owner.get_ref()==shell:return
	menu_owner=weakref(shell)
	set_state(flow.current_state)

func bind_button(button: BaseButton) -> void:
	if not button.button_down.is_connected(play_click):button.button_down.connect(play_click)
	if button is OptionButton:
		var popup: PopupMenu=button.get_popup()
		if not popup.id_pressed.is_connected(_popup_click):popup.id_pressed.connect(_popup_click)

func bind_tree(node: Node) -> void:
	if node is BaseButton:bind_button(node)
	for child in node.get_children():bind_tree(child)

func _popup_click(_id: int) -> void:play_click()

func play_click() -> void:
	if shutting_down:return
	click_count+=1;clicks=click_players[next_click];next_click=(next_click+1)%click_players.size()
	clicks.stop();clicks.play()

func set_state(state: StringName) -> void:
	if shutting_down:return
	var shell=menu_owner.get_ref() if menu_owner!=null else null
	var next_music: bool=not cinematic_active and state in MUSIC_STATES and is_instance_valid(shell) and shell.is_inside_tree()
	if next_music and wants_music and music.playing:return
	wants_music=next_music
	if fade!=null and fade.is_valid():fade.kill()
	if wants_music:
		if not music.playing:
			gain=0;music.play();music_starts+=1
		fade=create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		fade.tween_property(self,"gain",1.0,FADE_IN_SECONDS).set_trans(Tween.TRANS_SINE)
	else:
		fade=create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		fade.tween_property(self,"gain",0.0,FADE_OUT_SECONDS).set_trans(Tween.TRANS_SINE)
		fade.tween_callback(func():
			if not wants_music:music.stop())

func set_cinematic(value: bool) -> void:
	cinematic_active=value
	if value:
		if fade!=null and fade.is_valid():fade.kill()
		wants_music=false;gain=0;music.stop()
	else:set_state(flow.current_state)

func shutdown() -> void:
	if shutting_down:return
	set_state(&"closing")
	shutting_down=true
	await fade.finished
	for player in click_players:player.stop()
	# Let the audio mixer release any overlapping WAV voices before closing the tree.
	await get_tree().create_timer(.05,true,false,true).timeout

func _exit_tree() -> void:
	if fade!=null and fade.is_valid():fade.kill()
	if is_instance_valid(music):music.stop()
	for player in click_players:
		if is_instance_valid(player):player.stop()

func _input(event: InputEvent) -> void:
	var navigation:=using_navigation
	if event is InputEventMouseMotion or event is InputEventMouseButton:navigation=false
	elif event.is_action_pressed("ui_up") or event.is_action_pressed("ui_down") or event.is_action_pressed("ui_left") or event.is_action_pressed("ui_right") or event.is_action_pressed("ui_accept"):navigation=true
	if navigation!=using_navigation:
		using_navigation=navigation;get_tree().call_group("neon_buttons","queue_redraw")

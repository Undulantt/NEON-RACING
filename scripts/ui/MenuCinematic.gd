extends CanvasLayer
# Presentation only: the navigation state remains main_menu while the attract video plays.
const IDLE_SECONDS := 15.0
const CLIP=preload("res://assets/ui/menu/backgorunds/Cinematica inicial.ogv")
var shell: Control
var video: VideoStreamPlayer
var surface: Control
var idle_seconds := 0.0
var active := false
var starts := 0

func configure(owner_shell: Control) -> void:
	shell=owner_shell;layer=110;process_mode=Node.PROCESS_MODE_ALWAYS
	GameFlow.state_changed.connect(_state_changed)
	if not GameFlow.intro_shown:
		GameFlow.intro_shown=true
		if not "--skip-intro" in OS.get_cmdline_user_args():play.call_deferred()

func _state_changed(_state: StringName) -> void:
	idle_seconds=0
	if GameFlow.current_state!=&"main_menu":dismiss()

func eligible() -> bool:
	return is_instance_valid(shell) and shell.is_inside_tree() and GameFlow.current_state==&"main_menu" and not GameFlow.transition_busy

func _process(delta: float) -> void:
	if active or not eligible():return
	idle_seconds+=delta
	if idle_seconds>=IDLE_SECONDS:play()

func play() -> void:
	if active or not eligible():return
	active=true;starts+=1;idle_seconds=0
	GameFlow.menu_audio.set_cinematic(true)
	surface=Control.new();surface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);add_child(surface)
	var black:=ColorRect.new();black.color=Color.BLACK;black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);surface.add_child(black)
	video=VideoStreamPlayer.new();video.stream=CLIP;video.expand=true;video.bus="Music"
	# Keep the original 16:9 frame intact on every display (letterboxing).
	var aspect:=AspectRatioContainer.new();aspect.ratio=16.0/9.0;aspect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	aspect.stretch_mode=AspectRatioContainer.STRETCH_FIT;surface.add_child(aspect);aspect.add_child(video)
	var hint:=Label.new();hint.text="ENTER / ESC · Clic · A: continuar";hint.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE);hint.offset_top=-46;hint.offset_bottom=-16;surface.add_child(hint)
	video.finished.connect(dismiss);video.play()

func dismiss() -> void:
	idle_seconds=0
	if not active:return
	active=false;video.stop();surface.queue_free();video=null;surface=null
	GameFlow.menu_audio.set_cinematic(false)

func _input(event: InputEvent) -> void:
	var meaningful:=event is InputEventKey or event is InputEventMouseButton or event is InputEventMouseMotion or event is InputEventJoypadButton
	if event is InputEventJoypadMotion:meaningful=absf(event.axis_value)>.3
	if meaningful:idle_seconds=0
	if not active:return
	# Consume the dismissing press so it cannot also activate a button behind the video.
	if (event is InputEventKey or event is InputEventMouseButton or event is InputEventJoypadButton) and event.is_pressed() and not event.is_echo():dismiss()
	get_viewport().set_input_as_handled()

func _exit_tree() -> void:
	if active:GameFlow.menu_audio.set_cinematic(false)

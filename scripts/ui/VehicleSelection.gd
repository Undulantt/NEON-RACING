extends Control
const Profiles=preload("res://scripts/driving/VehicleProfiles.gd")
var shell: Control
var showroom: SubViewportContainer
var name_label: Label
var bars: Dictionary={}
var difficulty: OptionButton
func configure(target: Control) -> void:
	shell=target;custom_minimum_size=Vector2(990,520)
	showroom=preload("res://scripts/ui/CarShowroom.gd").new();showroom.position=Vector2(0,0);showroom.size=Vector2(360,430);add_child(showroom);showroom.configure()
	var frame:=PanelContainer.new();frame.position=Vector2(385,0);frame.size=Vector2(605,430)
	var style:=StyleBoxFlat.new();style.bg_color=Color(.015,.008,.035,.52);style.border_color=Color("00e5ee");style.set_border_width_all(2)
	style.content_margin_left=16;style.content_margin_right=12;style.content_margin_top=8;style.content_margin_bottom=8
	frame.add_theme_stylebox_override("panel",style);add_child(frame)
	var list:=VBoxContainer.new();list.add_theme_constant_override("separation",4);frame.add_child(list)
	for key in shell.STAT_LABELS:
		var bar:=preload("res://scripts/ui/VehicleStatBar.gd").new();bar.caption=shell.STAT_LABELS[key];bar.size_flags_horizontal=Control.SIZE_EXPAND_FILL;list.add_child(bar);bars[key]=bar
	for direction in [-1,1]:
		var arrow:=preload("res://scripts/ui/VehicleCycleButton.gd").new();arrow.direction=direction;arrow.position=Vector2(0 if direction<0 else 298,442);arrow.size=Vector2(62,52)
		arrow.tooltip_text="Vehículo anterior" if direction<0 else "Siguiente vehículo"
		arrow.pressed.connect(cycle.bind(direction));add_child(arrow);shell.buttons["vehicle_previous" if direction<0 else "vehicle_next"]=arrow
	name_label=Label.new();name_label.position=Vector2(62,447);name_label.size=Vector2(236,40);name_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_override("font",preload("res://scripts/ui/NeonButton.gd").arial(true));name_label.add_theme_font_size_override("font_size",25);add_child(name_label)
	var hint:=Label.new();hint.text="Arrastra para girar · Rueda: zoom";hint.position=Vector2(18,498);hint.add_theme_font_size_override("font_size",14);hint.add_theme_color_override("font_color",Color("b8dbe2"));add_child(hint)
	if GameFlow.selected_mode==&"race":
		var title:=Label.new();title.text="Dificultad de rivales";title.position=Vector2(398,451);title.add_theme_font_size_override("font_size",15);add_child(title)
		difficulty=OptionButton.new();difficulty.name="RivalDifficulty";difficulty.position=Vector2(398,474);difficulty.size=Vector2(210,40)
		difficulty.add_item("Estándar");difficulty.add_item("Experto");difficulty.select(1 if GameFlow.rival_difficulty=="expert" else 0)
		difficulty.item_selected.connect(func(index: int):GameFlow.set_rival_difficulty("expert" if index==1 else "standard"));add_child(difficulty)
	else:
		var note:=Label.new();note.text="Estadísticas del perfil\nEscala 1–10";note.position=Vector2(400,461);note.add_theme_font_size_override("font_size",16);add_child(note)
	var continue_button: Button=shell.button("continue","Continuar",GameFlow.start_selected,self)
	continue_button.position=Vector2(652,453);continue_button.size=Vector2(338,64);continue_button.compact=false
	set_selected(GameFlow.selected_vehicle_id)

func cycle(direction: int) -> void:
	var index:=Profiles.IDS.find(GameFlow.selected_vehicle_id)
	GameFlow.select_vehicle(Profiles.IDS[posmod(index+direction,Profiles.IDS.size())])

func set_selected(id: String) -> void:
	showroom.select_model(id);name_label.text=id
	var stats: Dictionary=Profiles.load_profile(id)["stats"]
	for key in bars:bars[key].value=stats[key];bars[key].queue_redraw()

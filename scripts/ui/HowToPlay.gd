extends VBoxContainer
const Neon=preload("res://scripts/ui/NeonButton.gd")
# Only player controls. Every claimed binding is checked by godot_player_controls.gd.
const CONTROLS=[
	["W / ↑","RT / R2","Acelerar","Mantén pulsado. En mando, el gatillo regula la aceleración.","accelerate"],
	["S / ↓","LT / L2","Frenar / reversa","Frena primero; mantén pulsado una vez detenido para retroceder.","brake_reverse"],
	["A, D / ←, →","Stick izquierdo","Girar","Inclina a izquierda o derecha. El stick permite graduar el giro.","steer_left"],
	["ESPACIO","A / ✕","Derrapar","Combina dirección y freno de mano con velocidad; suelta y endereza para salir.","handbrake"],
	["SHIFT","X / □","TURBO","Mantén pulsado con reserva disponible. Al soltarlo, la reserva vuelve a cargarse tras una espera.","turbo"],
	["R","Y / △","Recuperar vehículo","Espera 3 segundos más la preparación del terreno. En carrera regresas al último checkpoint.","recover"],
	["ESC","Start / Options / +","Pausa / mapa","En modo libre abre el mapa. En carrera permite continuar, recuperar, reiniciar o abandonar.","pause"],
	["E","B / ○","Interactuar","Reduce la velocidad junto a una salida de carrera o un lugar del Pasaporte y sigue su aviso.","interact"],
	["V","RB / R1","Cambiar cámara","Alterna la cámara de persecución cercana y lejana.","driving_camera"],
	["P","Pausa → Pasaporte","Pasaporte La Paz","Disponible en modo libre. En mando: abre pausa, selecciona Pasaporte y confirma con A / ✕.",""],
	["M","Opciones → Sonido","Audio del vehículo","M silencia o reactiva los sonidos del coche. Los volúmenes generales se ajustan en Opciones.","audio_toggle"]
]
var page:=0
var tabs: Array[Button]=[]
var content: VBoxContainer
var status: Label
var connection_text:=""

func configure() -> void:
	size_flags_horizontal=Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation",14)
	var header:=HBoxContainer.new();header.add_theme_constant_override("separation",8);add_child(header)
	for i in range(3):
		var tab:=Neon.new();tab.compact=true;tab.tab_style=true;tab.text=["TECLADO","MANDO","MECÁNICAS"][i]
		tab.size_flags_horizontal=Control.SIZE_EXPAND_FILL;tab.pressed.connect(show_page.bind(i));header.add_child(tab);tabs.append(tab)
	content=VBoxContainer.new();content.add_theme_constant_override("separation",12);add_child(content)
	show_page(0)
	Input.joy_connection_changed.connect(_connection_changed)

func text(value: String,parent: Node,point_size:=17,tint:=Color.WHITE) -> Label:
	var item:=Label.new();item.text=value;item.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	item.add_theme_font_size_override("font_size",point_size);item.add_theme_color_override("font_color",tint)
	parent.add_child(item);return item

func show_page(index: int) -> void:
	page=index;status=null
	for child in content.get_children():content.remove_child(child);child.queue_free()
	for i in range(tabs.size()):tabs[i].text=("› " if i==index else "")+["TECLADO","MANDO","MECÁNICAS"][i]
	get_parent().get_parent().set_deferred("scroll_vertical",0)
	text("LB / RB: cambiar pestaña · Stick derecho ↑↓: desplazar guía · B / Esc: volver",content,15,Color("b8dbe2"))
	if page==2:
		mechanics();return
	var row:=HBoxContainer.new();row.add_theme_constant_override("separation",24);content.add_child(row)
	var visual:=VBoxContainer.new();visual.custom_minimum_size.x=300;row.add_child(visual)
	var diagram:=preload("res://scripts/ui/ControlDiagram.gd").new();diagram.gamepad=page==1
	diagram.custom_minimum_size=Vector2(300,376);diagram.mouse_filter=Control.MOUSE_FILTER_IGNORE;visual.add_child(diagram)
	if page==1:
		status=text("",visual,16,Color("8aebee"));_connection_changed(0,false)
		text("Cruceta / stick: navegar\nA / ✕: aceptar\nB / ○: volver\nStart / Options / +: pausa",visual,17)
	else:
		text("Menús: flechas, Enter y Esc.\nTambién puedes hacer clic.\nDesplázate hacia abajo para ver todos los controles.",visual,17,Color("b8dbe2"))
	var list:=VBoxContainer.new();list.size_flags_horizontal=Control.SIZE_EXPAND_FILL;list.add_theme_constant_override("separation",8);row.add_child(list)
	for control in CONTROLS:
		var tile:=PanelContainer.new();tile.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		var style:=StyleBoxFlat.new();style.bg_color=Color(.025,.015,.06,.8);style.border_color=Color("007c8b");style.border_width_left=2
		style.content_margin_left=12;style.content_margin_right=12;style.content_margin_top=8;style.content_margin_bottom=8;tile.add_theme_stylebox_override("panel",style)
		list.add_child(tile)
		var stack:=VBoxContainer.new();tile.add_child(stack)
		text(control[page]+"  /  "+control[2],stack,18,Color("00e5ee"))
		text(control[3],stack,16)
	if page==1:text("Mapa: con mando puedes elegir una salida de carrera desde la lista de destinos. Para señalar cualquier punto del mapa, hacer zoom o desplazarlo, usa el ratón. La rotación manual del coche en el selector también utiliza ratón.",content,16,Color("b8dbe2"))
	else:text("Mapa en pausa: clic izquierdo = destino; rueda = zoom; arrastrar con botón central o derecho = mover. En el selector, arrastra el coche para girarlo y usa la rueda para acercarlo.",content,16,Color("b8dbe2"))

func _unhandled_input(event: InputEvent) -> void:
	if GameFlow.current_state!=&"how_to_play":return
	if event is InputEventJoypadButton and event.pressed and event.button_index in [JOY_BUTTON_LEFT_SHOULDER,JOY_BUTTON_RIGHT_SHOULDER]:
		show_page(posmod(page+(-1 if event.button_index==JOY_BUTTON_LEFT_SHOULDER else 1),3))
		tabs[page].grab_focus();get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	if GameFlow.current_state!=&"how_to_play":return
	for device in Input.get_connected_joypads():
		var direction:=Input.get_joy_axis(device,JOY_AXIS_RIGHT_Y)
		if absf(direction)>.25:
			var scroll: ScrollContainer=get_parent().get_parent()
			scroll.scroll_vertical+=roundi(direction*600*delta)
			break

func _connection_changed(_device: int,_connected: bool) -> void:
	if not is_instance_valid(status):return
	var devices:=Input.get_connected_joypads()
	connection_text="Sin mando detectado. Puedes conectarlo por USB o Bluetooth."
	if not devices.is_empty():
		var device: int=devices[0]
		connection_text="Detectado: "+Input.get_joy_name(device)+("\nMapeo estándar reconocido." if Input.is_joy_known(device) else "\nMapeo no reconocido: los botones pueden variar.")
	status.text=connection_text

func mechanics() -> void:
	for entry in [
		["01  /  DERRAPE → IMPULSO","Toma una curva con velocidad y mantén dirección + freno de mano (Espacio / A). Suelta el freno de mano y recupera el agarre. Una salida válida concede un impulso breve; chocar o perder el control puede invalidarlo."],
		["02  /  TURBO","Mantén Shift / X mientras haya reserva. Consumes carga durante su uso; al dejar de usarlo se recarga después de una espera. Un derrape válido también puede devolver parte de la reserva."],
		["03  /  BURST AUTOMÁTICO","No tiene una tecla propia. Mantén el acelerador cerca de la velocidad base durante el tiempo de preparación de tu coche. Al activarse, el límite aumenta progresivamente. Soltar el acelerador, frenar, derrapar o perder demasiada velocidad lo cancela. Sigue el indicador BURST."],
		["04  /  CARRERAS","Elige carrera desde el menú o detente junto al cilindro rosa en modo libre y pulsa E / B. Cruza los aros en orden; completa las vueltas indicadas si es circuito, o llega a la meta si es de punto a punto. Compites contra cinco rivales y sales en la última posición."],
		["05  /  EXPLORACIÓN Y RECUPERACIÓN","Los lugares del Pasaporte son opcionales: acércate a su marcador turquesa por la calle, reduce la velocidad y pulsa E / B cuando aparezca el aviso. Si quedas atorado, R / Y solicita recuperación; espera la cuenta de 3 segundos y la preparación del terreno."]
	]:
		text(entry[0],content,20,Color("00e5ee"));text(entry[1],content,18)
	text("Las marchas cambian automáticamente. La velocidad, la preparación de BURST y la duración del TURBO dependen del vehículo seleccionado.",content,17,Color("b8dbe2"))

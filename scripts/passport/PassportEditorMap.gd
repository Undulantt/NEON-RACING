extends "res://scripts/ui/PauseRoadMap.gd"
var editor: Control
var place_mode:=false

func select_at(local_position: Vector2) -> bool:
	var at: Vector2=(local_position-size*.5)/zoom+center
	if place_mode:
		var geo:=preload("res://scripts/passport/PassportStore.gd").geographic(at,world.map_data["metadata"])
		editor.latitude.text="%.8f"%geo.x;editor.longitude.text="%.8f"%geo.y;editor.verified.button_pressed=false
	else:
		var zone:=preload("res://scripts/passport/PassportStore.gd").snap(at,GameFlow.road_graph,80)
		if zone.is_empty():editor.notice.text="Haz clic a menos de 80 m de una calle transitable.";return false
		editor.zone=zone;editor.notice.text="Zona seleccionada en "+str(zone["street"])+". Acércate y pulsa Probar zona."
	queue_redraw();return true

func _draw() -> void:
	super._draw()
	if editor==null:return
	if editor.latitude.text.is_valid_float() and editor.longitude.text.is_valid_float():
		var at:=preload("res://scripts/passport/PassportStore.gd").world_point(float(editor.latitude.text),float(editor.longitude.text),world.map_data["metadata"])
		draw_circle(screen(at),7,Color("ff89d4"))
	if not editor.zone.is_empty():
		var at: Vector2=preload("res://scripts/passport/PassportStore.gd").approach({"activation":editor.zone},GameFlow.road_graph)
		draw_circle(screen(at),maxf(5,float(editor.radius.value)*zoom),Color(.15,.9,.9,.4));draw_circle(screen(at),4,Color("61fff4"))

extends SceneTree
var failures: Array[String] = []
func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)
func _initialize() -> void:
	run.call_deferred()
func frames(count: int) -> void:
	for i in range(count):
		await physics_frame
func run() -> void:
	root.size=Vector2i(1280,720)
	var world=load("res://scenes/NightPilot.tscn").instantiate()
	root.add_child(world)
	var car=world.player
	car.external_control=true
	await frames(120)
	var trail: Node
	for node in world.find_children("*","Node",true,false):
		if node.get_script()==load("res://scripts/style/TurboTrail.gd"):
			trail=node
	check(trail!=null,"Missing trail")
	if trail==null:
		quit(1)
		return
	car.set_controls(1,0)
	await frames(110)
	car.set_controls(1,0,false,true)
	await frames(55)
	check(car.turbo_active and trail.history.size()>2,"Turbo must emit a continuous ribbon")
	check(trail.history.size()<=trail.MAX_SAMPLES,"History budget exceeded")
	check(trail.mesh.get_surface_count()==1,"Expected one batched ribbon surface")
	var peak_samples: int=trail.history.size()
	var look=trail.get_parent()
	check(look.blur_amount>0.9,"Turbo peripheral blur not engaged")
	check(world.night_style.pilot.find_children("*","Label3D",true,false).is_empty(),"Invented business labels remain")
	var borders=world.road_root.loaded[Vector2i(0,-1)].find_children("RoadEdgeNeon","MeshInstance3D",true,false)
	check(not borders.is_empty(),"Missing elevated road borders")
	var screen=trail.screen_effects
	check(screen.retro_profile,"Existing speed overlay should use retro profile")
	check(world.night_style.storefront_count>0,"No commercial facade modules")
	var frozen: float=trail.clock
	paused=true
	for i in range(5):
		await process_frame
	check(trail.clock==frozen,"Paused trail should freeze")
	paused=false
	car.set_controls(0,0)
	await frames(35)
	check(trail.history.is_empty(),"Released boost must fade out")
	check(look.blur_amount<0.02,"Released boost blur must fade")
	car.set_controls(1,0,false,true)
	await frames(12)
	car.position+=Vector3(20,0,0)
	await frames(2)
	check(trail.history.size()<=2,"Teleport must not leave a bridge")
	car.recovered.emit("test")
	check(trail.history.is_empty() and screen.intensity==0,"Recovery must clear motion effects")
	for expected in [0.4,0.0,1.0]:
		var event:=InputEventKey.new()
		event.keycode=KEY_F4
		event.pressed=true
		trail._unhandled_key_input(event)
		await frames(2)
		check(is_equal_approx(trail.strength,expected),"F4 strength cycle")
		if expected==0:
			check(trail.history.is_empty() and not car.visuals["exhaust"][0].visible,"Disabled effects remain visible")
	var report:={"passed":failures.is_empty(),"failures":failures,"peak_samples":peak_samples,"storefronts":world.night_style.storefront_count,"checks":["turbo emission","bounded mesh","pause","fade","teleport","recovery","F4 modes","peripheral blur","no invented labels","elevated borders"]}
	FileAccess.open("res://docs/phase_e_motion_validation.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("PHASE_E_MOTION ",JSON.stringify(report))
	world.queue_free()
	for i in range(8):
		await process_frame
	quit(0 if failures.is_empty() else 1)

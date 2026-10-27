extends SceneTree

var world: Node3D
var car: CharacterBody3D
var failures: Array[String] = []

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var capture := "--capture-slope" in OS.get_cmdline_user_args() and DisplayServer.get_name()!="headless"
	world=preload("res://scenes/Main.tscn").instantiate()
	root.add_child(world)
	await physics_frame
	await physics_frame
	car=world.player
	car.external_control=true
	# Measured from the prepared surface on real OSM way 28531909:0.
	# It is a small urban crest, in addition to the deliberately larger fixture.
	var start:=Vector2(621.1965806142975,-681.0958648259649)
	var direction:=Vector3(0.7927683786002249,0,0.6095230085005574)
	var yaw:=atan2(-direction.x,-direction.z)
	car.global_transform=Transform3D(Basis(Vector3.UP,yaw),Vector3(start.x,car.supported_pose_height(start.x,start.y,yaw),start.y))
	car.velocity=Vector3.ZERO
	car.reset_surface_motion()
	world.follow_camera.snap()
	car.set_controls(0,0,true)
	for i in range(30):await physics_frame
	var recoveries: int=car.recovery_count
	var contacts: int=car.wall_contacts
	var takeoffs: int=car.crest_takeoffs
	car.velocity=direction*32
	car.set_controls(1,0)
	var airborne:=0
	var peak:=0.0
	var landed:=false
	var min_visual_clearance:=INF
	var previous_airborne:=false
	for i in range(100):
		await physics_frame
		if not car.is_on_floor():
			airborne+=1
			if capture and airborne==9:
				await process_frame
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png("res://docs/evidence/slope_real_crest_airborne.png")
			for pivot in car.visuals["pivots"]:
				var p: Vector3=pivot.global_position
				var h: float=world.elevation.get_height_at(p.x,p.z)
				min_visual_clearance=minf(min_visual_clearance,p.y-0.34-h)
			var support: float=car.predicted_support_height(car.position)
			if is_finite(support):peak=maxf(peak,car.position.y-support)
		elif previous_airborne:
			landed=true
			if capture:
				await process_frame
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png("res://docs/evidence/slope_real_crest_landed.png")
		previous_airborne=not car.is_on_floor()
	if airborne<2 or peak<0.015 or not landed:failures.append("Real urban crest did not produce and land a small hop")
	if car.recovery_count!=recoveries or car.wall_contacts!=contacts:failures.append("Real crest required recovery or hit an obstacle")
	if not car.on_asphalt or not car.is_on_floor():failures.append("Real crest did not return to supported asphalt")
	if min_visual_clearance < -0.005:failures.append("Airborne visual tire penetrated the road")
	var report:={"passed":failures.is_empty(),"failures":failures,"controller_sha256":FileAccess.get_sha256("res://scripts/driving/ArcadeCar.gd"),"street":"Calle Miguel Hidalgo y Costilla","osm_road_id":"28531909:0","airborne_frames":airborne,"peak_clearance_m":peak,"minimum_visual_tire_clearance_m":min_visual_clearance,"landed":landed,"takeoffs":car.crest_takeoffs-takeoffs,"wall_contacts":car.wall_contacts-contacts,"recoveries":car.recovery_count-recoveries}
	var file:=FileAccess.open("res://docs/slope_real_crest_render_validation.json" if capture else "res://docs/slope_real_crest_validation.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	print("REAL_CREST_REPORT ",JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)

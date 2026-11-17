extends SceneTree
func _initialize() -> void: run.call_deferred()
func run() -> void:
	await process_frame
	var scene:=Node3D.new()
	root.add_child(scene)
	current_scene=scene
	var floor_body:=StaticBody3D.new()
	floor_body.collision_layer=1
	var collision:=CollisionShape3D.new()
	var box:=BoxShape3D.new()
	box.size=Vector3(800,1,800)
	collision.shape=box
	floor_body.add_child(collision)
	floor_body.position=Vector3(0,-0.5,-150)
	scene.add_child(floor_body)
	var car=preload("res://scenes/cars/PlayerCar.tscn").instantiate()
	car.external_control=true
	scene.add_child(car)
	car.configure({"roads":[{"points_xz":[[0,200],[0,-500]],"width_m":600,"oneway":true,"street_name":"Drift control"}]},{"bounds_xz":[-350,-500,350,200],"spawn":{"position_xz":[0,0],"forward_xz":[0,-1]}})
	car.apply_vehicle_profile("APEX")
	var trace: Array=[]
	var valid_frames:=0
	var boost_frames:=0
	var slip_peak:=0.0
	var charge_peak:=0.0
	for frame in range(540):
		var drifting:=frame>=240 and frame<324
		car.set_controls(1.0,0.5 if drifting else 0.0,drifting)
		await physics_frame
		if car.abilities.drift_quality>0: valid_frames+=1
		if car.abilities.drift_boost_active and car.throttle_input>0 and car.speed_mps<car.current_speed_cap: boost_frames+=1
		slip_peak=maxf(slip_peak,absf(rad_to_deg(car.slip_angle)))
		charge_peak=maxf(charge_peak,car.abilities.drift_charge)
		if drifting: trace.append({"position":car.position,"velocity":car.velocity,"quality":car.abilities.drift_quality})
	# Replay only measured physical positions against the production trigger.
	# The control manoeuvre uses scripted inputs, not the NPC controller.
	var direction: Vector2=Vector2(trace[40]["velocity"].x,trace[40]["velocity"].z).normalized()
	var at: Vector3=trace[40]["position"]+Vector3(direction.x,0,direction.y)*2.0
	var session=preload("res://scripts/racing/RaceSession.gd").new()
	session.begin({"id":"physical_drift","type":"sprint","distance_m":40.0,"points_xz":[[trace[0]["position"].x,trace[0]["position"].z],[at.x,at.z]],"settings":{"countdown_s":0},"checkpoints":[{"position_xz":[at.x,at.z],"forward_xz":[direction.x,direction.y],"half_width_m":5.0/1.3,"distance_m":40.0,"edge_index":0}]})
	session.phase="running"
	var early_contact:=false
	var contact_drifting:=false
	for index in range(1,trace.size()):
		var a: Vector3=trace[index-1]["position"]
		var b: Vector3=trace[index]["position"]
		session.advance(Vector2(a.x,a.z),Vector2(b.x,b.z),1.0/60,true,a.y,b.y)
		if session.phase=="finished":
			early_contact=Vector2(b.x-at.x,b.z-at.z).dot(direction)<0
			contact_drifting=trace[index]["quality"]>0
			break
	var report:={"passed":car.drift_rewards>0 and boost_frames>0 and session.phase=="finished" and early_contact and contact_drifting,"fixture":"Positive control: scripted APEX throttle/steering/handbrake on flat asphalt; real physics, no injected speed or reward. Not an NPC driving test.","drift_valid_seconds":valid_frames/60.0,"drift_charge_peak":charge_peak,"drift_rewards":car.drift_rewards,"drift_boost_with_acceleration_seconds":boost_frames/60.0,"slip_peak_degrees":slip_peak,"checkpoint_passed":session.phase=="finished","contact_before_plane":early_contact,"contact_during_valid_drift":contact_drifting,"recoveries":car.recovery_count,"wall_contacts":car.wall_contacts}
	FileAccess.open("res://.local/artifacts/checkpoint_physical_drift_validation.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("CHECKPOINT_PHYSICAL_DRIFT ",JSON.stringify(report))
	quit(0 if report["passed"] else 1)

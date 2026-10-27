extends SceneTree

const Main = preload("res://scenes/FlatWorld.tscn")
var world: Node3D
var car: CharacterBody3D
var failures: Array[String] = []
var metrics := {}

func _initialize() -> void:
	run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("URBAN_TEST: " + message)

func wait_frames(count: int) -> void:
	for i in range(count):
		await physics_frame

func tap_f8() -> void:
	var event := InputEventKey.new()
	event.physical_keycode = KEY_F8
	event.keycode = KEY_F8
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	event = InputEventKey.new()
	event.physical_keycode = KEY_F8
	event.keycode = KEY_F8
	event.pressed = false
	Input.parse_input_event(event)
	await wait_frames(3)

func drive_case(pose: Transform3D) -> Dictionary:
	car.global_transform = pose
	car.velocity = Vector3.ZERO
	car.speed_mps = 0
	car.signed_speed = 0
	car.steering = 0
	car.set_controls(0,0)
	await wait_frames(20)
	car.set_controls(1,0)
	await wait_frames(180)
	car.set_controls(-1,0)
	await wait_frames(80)
	car.set_controls(0,0)
	return {"position":car.position,"velocity":car.velocity,"recoveries":car.recovery_count,"wall_contacts":car.wall_contacts}

func run() -> void:
	world = Main.instantiate()
	root.add_child(world)
	await wait_frames(60)
	if world.city_manager == null:
		check(false,"Urban manager did not initialize")
		finish()
		return
	car = world.player
	car.external_control = true
	var manager: Node3D = world.city_manager
	metrics["spawn_streaming"] = manager.status()
	check(manager.loaded.size() < manager.manifest["chunks"].size(),"Entire city loaded at spawn")
	check(manager.loaded_buildings < int(manager.manifest["statistics"]["buildings"]),"All building data instantiated at spawn")
	check(manager.failed_chunks.is_empty(),"Corrupt or missing sector")
	# Relocate to the same authenticated long straight used by phase B tests.
	var road: Dictionary = {}
	for r in world.map_data["roads"]:
		if r["id"] == "24503430:18": road=r
	var a := Vector3(road["points_xz"][0][0],0.67,road["points_xz"][0][1])
	var b := Vector3(road["points_xz"][-1][0],0.67,road["points_xz"][-1][1])
	var direction := (b-a).normalized()
	var pose := Transform3D(Basis(Vector3.UP,atan2(-direction.x,-direction.z)),a+direction*15)
	var on: Dictionary = await drive_case(pose)
	car.global_transform = pose
	car.velocity=Vector3.ZERO
	await wait_frames(20)
	await tap_f8()
	check(not manager.city_enabled,"F8 did not disable city")
	var hidden := true
	var no_collision := true
	for id in manager.loaded:
		var node: Node3D = manager.loaded[id]["node"]
		hidden = hidden and not node.visible
		for child in node.get_children():
			if child is StaticBody3D: no_collision = no_collision and child.collision_layer==0
	check(hidden and no_collision,"Disabled city left geometry or building collisions enabled")
	var off: Dictionary = await drive_case(pose)
	metrics["city_on_off_position_difference_m"] = on["position"].distance_to(off["position"])
	metrics["city_on_off_velocity_difference_mps"] = on["velocity"].distance_to(off["velocity"])
	check(on["position"].distance_to(off["position"]) < 0.002,"City changed driving on clear asphalt")
	check(on["velocity"].distance_to(off["velocity"]) < 0.002,"City changed acceleration/braking")
	car.global_transform=car.spawn_transform
	car.velocity=Vector3.ZERO
	car.set_controls(0,0)
	await wait_frames(20)
	await tap_f8()
	check(manager.city_enabled,"F8 did not restore city on clear asphalt")
	await wait_frames(60)
	var disabled_distant := 0
	var active_near := 0
	for chunk in manager.manifest["chunks"]:
		if manager.loaded.has(chunk["id"]):
			var distance: float = manager.distance_to(chunk)
			for body in manager.loaded[chunk["id"]]["node"].get_children():
				if body is StaticBody3D:
					if distance>float(manager.manifest["settings"]["collision_radius_m"]) and body.collision_layer==0: disabled_distant+=1
					if distance<=float(manager.manifest["settings"]["collision_radius_m"]) and body.collision_layer==4: active_near+=1
	check(disabled_distant>0 and active_near>0,"Near/far collision staging failed")
	metrics["inactive_distant_collision_bodies"]=disabled_distant
	metrics["active_near_collision_bodies"]=active_near
	var loads_before: int = manager.total_chunk_loads
	# Moving to a different real road node must unload old and load new sectors.
	var point: Array = world.map_data["verification_route"]["points_xz"][-8]
	car.position=Vector3(point[0],0.67,point[1])
	car.velocity=Vector3.ZERO
	await wait_frames(100)
	check(manager.total_chunk_loads>loads_before and manager.total_chunk_unloads>0,"Sector movement did not stream data")
	check(manager.failed_chunks.is_empty(),"A sector failed integrity checks")
	metrics["final_streaming"]=manager.status()
	finish()

func finish() -> void:
	var report := {"passed":failures.is_empty(),"failures":failures,"metrics":metrics}
	var file := FileAccess.open("res://docs/phase_b5_runtime_validation.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	print("PHASE_B5_RUNTIME ",JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)

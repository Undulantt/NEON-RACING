extends "res://tests/godot_relief_world.gd"

var misses := []

func observe() -> void:
	if car == null or not car.is_on_floor() or car.on_asphalt or car.speed_mps<2:
		return
	var at := car.position
	var hit := world.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(at+Vector3.UP*1.13,at-Vector3.UP*2.5,3))
	var item := {"position":[at.x,at.y,at.z],"velocity":[car.velocity.x,car.velocity.y,car.velocity.z],"floor":str(car.get_floor_normal()),"hit_position":str(hit.get("position")),"collider":str(hit.get("collider")),"hit_layer":hit["collider"].collision_layer if not hit.is_empty() else 0,"previous_position":[at.x-car.velocity.x/60,at.z-car.velocity.z/60]}
	misses.append(item)
	print("ROAD_CONTACT_PROBE ",JSON.stringify(item))

func _run() -> void:
	if "--full-world" in OS.get_cmdline_user_args():
		physics_frame.connect(observe)
		await super._run()
		return
	world=preload("res://scenes/Main.tscn").instantiate()
	root.add_child(world)
	await physics_frame
	await physics_frame
	car=world.player
	car.external_control=true
	await step(60)
	physics_frame.connect(observe)
	world.environment_data["driving_test_route"]=JSON.parse_string(FileAccess.get_file_as_string("res://tracks/c5_south_hospital.json"))
	route_frame_limit=90000
	await drive_route()
	var file:=FileAccess.open("res://docs/map_extension_contact_probe.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"passed":failures.is_empty(),"metrics":metrics,"misses":misses},"  "))
	quit(0 if failures.is_empty() else 1)

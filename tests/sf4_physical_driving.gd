extends "res://tests/godot_sf21.gd"
# Synthetic asphalt fixture, unchanged production controller and actual inputs.
func ticks(n: int) -> void:
	for i in range(n):await physics_frame

func run() -> void:
	var level:=Node3D.new();root.add_child(level)
	var road:=StaticBody3D.new();road.collision_layer=1;level.add_child(road)
	var shape:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=Vector3(400,.2,400)
	shape.shape=box;shape.position.y=-.1;road.add_child(shape)
	car=preload("res://scenes/cars/PlayerCar.tscn").instantiate();level.add_child(car);car.external_control=true
	rig=preload("res://scripts/driving/FollowCamera.gd").new();level.add_child(rig);rig.attach(car)
	var fx: Node3D=rig.speed_feedback.vehicle_feedback
	var config:={"roads":[{"points_xz":[[0,180],[0,-180]],"oneway":false,"street_name":"SYNTHETIC DRIFT TEST ONLY"}]}
	var environment:={"bounds_xz":[-180,-180,180,180],"spawn":{"position_xz":[0,0],"forward_xz":[0,-1]}}
	for id in Profiles.IDS:
		car.apply_vehicle_profile(id);car.configure(config,environment);fx.clear_effects()
		check(car.apply_recovery_pose(car.spawn_transform,"sf4_profile_fixture_reset"),id+" reset fixture with the real recovery API")
		var straight_before: int=fx.total_emitted
		car.set_controls(1,0)
		await ticks(330)
		check(fx.total_emitted==straight_before,id+" straight acceleration produces no drift smoke")
		var before: int=fx.total_emitted
		car.set_controls(1,.85,true)
		var max_slip:=0.0;var max_particles:=0;var max_marks:=0;var max_cpu:=0
		for i in range(100):
			await physics_frame
			max_slip=maxf(max_slip,absf(car.slip_angle));max_particles=maxi(max_particles,fx.smoke.size());max_marks=maxi(max_marks,fx.marks.size());max_cpu=maxi(max_cpu,fx.last_update_us)
		check(fx.total_emitted>before and max_particles>0,id+" real handbrake drift emits illustrated smoke")
		check(max_marks>0,id+" real rear wheel path produces tire marks")
		check(max_particles<=fx.settings["smoke_max"] and max_marks<=fx.settings["marks_max"],id+" actual driving obeys resource limits")
		metrics[id]={"maximum_slip_radians":max_slip,"peak_particles":max_particles,"peak_marks":max_marks,"max_vfx_update_us":max_cpu}
		fx.total_emitted=0
		car.set_controls(0,0,false,false,1)
		await ticks(45)
	var report:={"passed":failures.is_empty(),"checks":checks,"failures":failures,"metrics":metrics,"scenario":"Actual accelerate/handbrake inputs, unchanged production physics, synthetic asphalt contact fixture; all three beta profiles. No injected slip/BURST state in this test."}
	FileAccess.open("res://docs/sf4_physical_driving.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("SF4_PHYSICS_REPORT ",JSON.stringify(report))
	level.queue_free();await process_frame;quit(0 if failures.is_empty() else 1)

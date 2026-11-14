extends "res://tests/godot_sf21.gd"
var vfx: Node3D
var stage:=1
var road: StaticBody3D

func ticks(n: int) -> void:
	for i in range(n):await physics_frame

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--stage="):stage=int(arg.trim_prefix("--stage="))
	var level:=Node3D.new();root.add_child(level)
	road=StaticBody3D.new();road.collision_layer=1;level.add_child(road)
	var collider:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=Vector3(120,.2,120)
	collider.shape=box;collider.position.y=-.1;road.add_child(collider)
	car=preload("res://scenes/cars/PlayerCar.tscn").instantiate();level.add_child(car)
	car.external_control=true
	car.configure({"roads":[{"points_xz":[[0,60],[0,-60]],"oneway":false,"street_name":"SYNTHETIC SF4 CONTACT TEST"}]},{"bounds_xz":[-60,-60,60,60],"spawn":{"position_xz":[0,0],"forward_xz":[0,-1]}})
	rig=preload("res://scripts/driving/FollowCamera.gd").new();level.add_child(rig);rig.attach(car)
	vfx=rig.speed_feedback.vehicle_feedback
	await ticks(12)
	car.set_physics_process(false);rig.set_physics_process(false);vfx.set_physics_process(false)
	var physical: Array=[car.velocity,car.config.duplicate(true),car.abilities.burst_state,car.abilities.burst_bonus]
	var slide:={"driving":true,"grounded":true,"speed":30.0,"slip":0.65,"drift":1.0,"grip":0.35}
	for id in Profiles.IDS:
		car.apply_vehicle_profile(id)
		check(vfx.evaluate_slide(slide)>0.4,id+" real slide signal is strong")
		for field in ["slip","speed","drift"]:
			var quiet: Dictionary=slide.duplicate();quiet[field]=0.0
			check(vfx.evaluate_slide(quiet)==0,id+" no smoke for zero "+field)
		var air: Dictionary=slide.duplicate();air["grounded"]=false
		check(vfx.evaluate_slide(air)==0,id+" no airborne slip emission")
		vfx.clear_effects()
		for i in range(90):vfx.advance(1.0/60,slide)
		check(vfx.smoke.size()>0 and vfx.smoke.size()<=vfx.settings["smoke_max"],id+" bounded world-space smoke at real road contacts")
		check(not vfx.contacts[0].is_empty() and not vfx.contacts[1].is_empty(),id+" rear anchors touch asphalt")
	var original: Vector3=vfx.smoke[0]["p"]
	car.position.x+=0.2;vfx.advance(0,slide)
	check(vfx.smoke[0]["p"].distance_to(original)<.001,"Existing puffs remain in world when vehicle moves")
	road.collision_layer=4
	await ticks(2)
	var before: int=vfx.total_emitted
	for i in range(60):vfx.advance(1.0/60,slide)
	check(vfx.total_emitted==before,"Building/non-road surface cannot emit tire smoke")
	road.collision_layer=1
	await ticks(2)
	vfx.set_setting("smoke_max",16)
	for i in range(300):vfx.advance(1.0/60,slide)
	check(vfx.smoke.size()<=16,"Pool obeys configured particle cap")
	if stage>=2:
		vfx.clear_effects();car.position.x=0
		for i in range(100):
			car.position.z-=0.12
			vfx.advance(1.0/60,slide)
		check(vfx.marks.size()>4,"Both rear trajectories leave persistent marks")
		var mark: Vector3=vfx.marks[0]["p"]
		var count: int=vfx.marks.size()
		var quiet: Dictionary=slide.duplicate();quiet["slip"]=0
		car.position.x+=1;vfx.advance(.1,quiet)
		check(vfx.marks.size()==count and Vector3(vfx.marks[0]["p"]).distance_to(mark)<.001,"Marks stay fixed after recovering grip and moving away")
		vfx.advance(float(vfx.settings["marks_lifetime_s"])+.1,quiet)
		check(vfx.marks.is_empty(),"Marks expire within configured lifetime")
		var missing: Dictionary={"position":Vector3(400,0,400),"normal":Vector3.UP}
		check(not vfx.append_mark(missing,{"position":Vector3(401,0,400),"normal":Vector3.UP}),"No marks across unsupported road gap")
		road.rotation.z=deg_to_rad(8)
		await ticks(2)
		var p0: Dictionary=vfx.road_probe(Vector3(-1,0,0))
		var p1: Dictionary=vfx.road_probe(Vector3(0,0,0))
		check(not p0.is_empty() and not p1.is_empty() and vfx.append_mark(p0,p1),"Marks align with an actual inclined road collider")
	if stage>=3:
		var mechanical: Array=[car.abilities.burst_state,car.abilities.burst_bonus,car.velocity,car.config.duplicate(true)]
		vfx.preview_enabled=true
		var values:=[]
		for value in [0.0,.15,.45,.75,1.0]:
			vfx.preview_burst=value
			for i in range(120):vfx.advance(1.0/60)
			values.append(vfx.burst_value)
			check(absf(vfx.burst_value-value)<.001,"Continuous BURST preview "+str(value))
		check(values[1]<values[2] and values[2]<values[3],"Transformation is progressive, not binary")
		check(mechanical==[car.abilities.burst_state,car.abilities.burst_bonus,car.velocity,car.config],"Preview changes no BURST physics or car values")
		check(vfx.body_bindings.size()>=2,"Painted body pieces bind independently of wheels/glass")
		vfx.preview_enabled=false
		for id in Profiles.IDS:
			car.apply_vehicle_profile(id)
			car.abilities.burst_state=2
			car.abilities.burst_bonus=float(car.config["burst_max_bonus"])*.5
			for i in range(120):vfx.advance(1.0/60)
			check(absf(vfx.real_burst_ratio-.5)<.001 and absf(vfx.burst_value-.5)<.001,id+" actual bonus normalized using its own profile cap")
			car.abilities.reset("sf4_test_cancel")
			check(car.abilities.burst_state==0 and car.abilities.burst_bonus==0,id+" physical reset is immediate")
			for i in range(22):vfx.advance(1.0/60)
			check(vfx.burst_value==0,id+" visual cancel tail is bounded")
		vfx.preview_enabled=false
		for i in range(22):vfx.advance(1.0/60)
		check(vfx.burst_value==0,"Cancelled BURST leaves no body transformation after 0.35s")
		for binding in vfx.body_bindings:check(binding["node"].material_overlay==binding["original"],"Original material overlay restored")
		vfx.set_setting("experimental_enabled",false)
		check(car.drift_particles.is_physics_processing(),"A/B Original restores legacy smoke")
		vfx.set_setting("experimental_enabled",true)
		check(not car.drift_particles.is_physics_processing(),"New effects replace legacy smoke without duplication")
		vfx.settings_path="res://tests/.sf4_trial.cfg"
		vfx.set_setting("smoke_density",32)
		check(vfx.save_trial(),"Trial settings save independently")
		vfx.set_setting("smoke_density",12)
		check(vfx.load_trial() and vfx.settings["smoke_density"]==32,"Trial settings round trip")
		DirAccess.remove_absolute(ProjectSettings.globalize_path(vfx.settings_path))
	if stage>=4:
		road.rotation=Vector3.ZERO
		await ticks(2)
		vfx.set_setting("marks_max",64)
		for i in range(100):
			var p0: Dictionary=vfx.road_probe(Vector3(0,0,i*.3))
			var p1: Dictionary=vfx.road_probe(Vector3(0,0,i*.3+.3))
			vfx.append_mark(p0,p1)
		check(vfx.marks.size()==64,"Mark pool evicts oldest segments at configured capacity")
		vfx.preview_enabled=true;vfx.preview_burst=1
		for i in range(100):vfx.advance(1.0/60)
		var visual_value: float=vfx.burst_value
		vfx.set_setting("smoke_density",33)
		check(vfx.burst_value==visual_value,"Smoke tuning never resets independent BURST transformation")
		vfx.set_setting("marks_enabled",false)
		check(vfx.burst_value==visual_value and vfx.marks.is_empty(),"Disabling marks leaves body transformation intact")
		vfx.reset_experiment()
		check(not vfx.preview_enabled and vfx.preview_burst==0 and vfx.marks.is_empty(),"Restore defaults clears preview and all retained marks")
		check(rig.experiment_panel.tabs.get_tab_title(3)=="SF.4","Dedicated SF.4 panel is available")
		rig.experiment_panel.buttons["sf4_original"].pressed.emit()
		check(not vfx.settings["experimental_enabled"] and rig.experiment_panel.buttons["sf4_original"].button_pressed,"Original selection is explicit in the panel")
		rig.experiment_panel.buttons["sf4_new"].pressed.emit()
		check(vfx.settings["experimental_enabled"] and rig.experiment_panel.buttons["sf4_new"].button_pressed,"New selection is explicit in the panel")
	car.global_position.x+=20;vfx.advance(0,slide)
	check(vfx.smoke.is_empty(),"Teleport clears detached effects")
	check(car.config==Profiles.load_profile("APEX")["config"],"VFX never changes profile physics")
	var baseline: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://docs/sf4_baseline.json"))
	for path in baseline["sha256"]:check(FileAccess.get_sha256("res://"+path)==baseline["sha256"][path],"Protected "+path)
	var result:={"passed":failures.is_empty(),"checks":checks,"failures":failures,"stage":stage,"note":"Synthetic contact/telemetry fixtures; real wheel raycasts, all 3 production profiles; physics/config/map hashes unchanged."}
	FileAccess.open("res://docs/sf4_stage_%d_validation.json"%stage,FileAccess.WRITE).store_string(JSON.stringify(result,"  "))
	print("SF4_REPORT ",JSON.stringify(result))
	level.queue_free();await process_frame;quit(0 if failures.is_empty() else 1)

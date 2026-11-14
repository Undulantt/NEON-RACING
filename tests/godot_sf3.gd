extends "res://tests/godot_sf21.gd"

func run() -> void:
	var level:=Node3D.new()
	root.add_child(level)
	car=preload("res://scenes/cars/PlayerCar.tscn").instantiate()
	level.add_child(car)
	car.external_control=true
	car.configure({"roads":[{"points_xz":[[0,1000],[0,-1000]],"oneway":false,"street_name":"SYNTHETIC TELEMETRY TEST"}]},{"bounds_xz":[-900,-1500,900,1500],"spawn":{"position_xz":[0,0],"forward_xz":[0,-1]}})
	rig=preload("res://scripts/driving/FollowCamera.gd").new()
	level.add_child(rig)
	rig.attach(car)
	audio=rig.speed_feedback.audio_feedback
	car.set_physics_process(false);rig.set_physics_process(false);audio.set_process(false)
	var environment: Node=rig.speed_feedback.environment_feedback
	for id in Profiles.IDS:
		car.apply_vehicle_profile(id)
		environment.reset_experiment()
		var cap: float=car.base_speed_cap
		var values:=[]
		for test in [[0.0,false,-1.0,0.0],[cap,false,-1.0,0.45],[cap,true,-1.0,0.75],[cap,false,0.0,0.483],[cap,false,0.5,0.7415],[cap,false,1.0,1.0],[cap,true,1.0,1.0]]:
			settle(6500,1,test[0],test[1],test[2])
			var value: float=rig.speed_feedback.visual_state["combined_intensity"]
			values.append(value)
			check(absf(value-test[3])<0.001,id+" visual envelope "+str(test))
		frame(6500,1,cap,false)
		check(rig.speed_feedback.visual_state["burst_ratio"]==0 and rig.speed_feedback.visual_state["burst_intensity"]>0,id+" physical progress resets immediately, visual tail stays smooth")
		var camera_settings: Dictionary=rig.speed_feedback.settings.duplicate(true)
		var audio_settings: Dictionary=audio.settings.duplicate(true)
		environment.set_mode("original")
		settle(6500,1,cap,false,1)
		check(environment.visual_gain==0 and rig.speed_feedback.visual_state["burst_ratio"]==1 and rig.speed_feedback.visual_state["combined_intensity"]>0.99,id+" SF.4 state survives Original environment without city")
		check(camera_settings==rig.speed_feedback.settings and audio_settings==audio.settings,id+" environment mode leaves camera/audio unchanged")
		environment.set_mode("partial")
		check(environment.settings["asphalt_enabled"] and environment.settings["markings_enabled"] and not environment.settings["edges_enabled"] and not environment.settings["lamps_enabled"],id+" partial is asphalt/paint only")
		environment.set_mode("full")
		check(environment.mode()=="full",id+" full restores all sublayers")
		metrics[id]={"combined_samples":values}

	# Regression: SF.3 was invisible while stationary and had no static preview.
	environment.reset_experiment()
	settle(900,0,0)
	check(environment.applied_gain()>0.19,"Enabled SF.3 has a visible stationary baseline")
	var physics_before: Array=[car.global_transform,car.velocity,car.powertrain.rpm,car.abilities.burst_state,car.abilities.burst_bonus]
	rig.experiment_panel.environment_preview.button_pressed=true
	check(environment.preview_enabled and environment.applied_gain()==environment.settings["intensity"],"Static preview applies full visual gain")
	check(rig.speed_feedback.visual_state["burst_ratio"]==0,"Preview never invents physical BURST progress for SF.4")
	check(physics_before==[car.global_transform,car.velocity,car.powertrain.rpm,car.abilities.burst_state,car.abilities.burst_bonus],"Preview leaves vehicle physics and transmission unchanged")
	environment.set_mode("original")
	check(environment.applied_gain()==0,"Original defeats preview immediately")
	check(rig.experiment_panel.buttons["sf3_original"].button_pressed and not rig.experiment_panel.buttons["sf3_full"].button_pressed,"Mode selection is unambiguous in the panel")
	environment.set_mode("full")
	environment.set_setting("intensity",0)
	check("Intensidad=0" in environment.diagnostic() or "SIN ADAPTADOR" in environment.diagnostic(),"Diagnostic reports blocked effect instead of a silent mode label")
	environment.reset_experiment()
	check(not environment.preview_enabled,"Preview is transient and resettable")
	var response:=[]
	var t: Dictionary=rig.speed_feedback.telemetry.duplicate(true)
	t["speed_mps"]=car.base_speed_cap;t["turbo_active"]=true;t["burst_state"]=2;t["burst_progress"]=0.6
	for hz in [30,60,120]:
		environment.reset_history()
		for i in range(hz*2): environment.advance(t,1.0/hz)
		response.append(environment.visual_state["combined_intensity"])
	check(absf(response[0]-response[2])<0.00001,"Visual envelope agrees at 30/60/120 Hz")
	metrics["response_by_hz"]=response
	environment.settings_path="res://tests/.sf3_trial.cfg"
	environment.set_setting("asphalt_strength",0.4)
	check(environment.save_trial(),"SF.3 saves independently")
	environment.set_setting("asphalt_strength",0.9)
	check(environment.load_trial() and environment.settings["asphalt_strength"]==0.4,"SF.3 round trip")
	check(not environment.set_setting("radius_m",NAN) and not environment.set_setting("speed",200),"Invalid values and physics fields are rejected")
	rig.experiment_panel.environment_sliders["intensity"].value=0.6
	check(absf(environment.settings["intensity"]-0.6)<0.001,"Live environment slider")
	rig.experiment_panel.buttons["sf3_original"].pressed.emit()
	check(environment.mode()=="original","Original preset button")
	rig.experiment_panel.buttons["sf3_reset"].pressed.emit()
	check(environment.settings==environment.defaults(),"Reset restores environmental baseline")
	var no_focus:=true
	for widget in rig.experiment_panel.environment_sliders.values()+rig.experiment_panel.environment_toggles.values()+rig.experiment_panel.buttons.values(): no_focus=no_focus and widget.focus_mode==Control.FOCUS_NONE
	check(no_focus,"New controls do not capture driving keyboard focus")
	root.get_node("GameFlow").current_state=&"free_drive"
	var event:=InputEventKey.new()
	event.keycode=KEY_L;event.pressed=true;event.ctrl_pressed=true;event.alt_pressed=true
	rig.experiment_panel._input(event)
	check(environment.mode()=="original","Ctrl+Alt+L cycles full to original")
	# Exercise real MeshInstance and MultiMesh overrides without changing resources.
	var mesh:=ArrayMesh.new()
	var arrays:=[];arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=PackedVector3Array([Vector3.ZERO,Vector3.RIGHT,Vector3.FORWARD])
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var source:=StandardMaterial3D.new();source.albedo_color=Color("38e9ff")
	mesh.surface_set_material(0,source)
	var visual:=MeshInstance3D.new();visual.mesh=mesh
	level.add_child(visual)
	var lamp:=MultiMeshInstance3D.new()
	var batch:=MultiMesh.new();batch.transform_format=MultiMesh.TRANSFORM_3D;batch.mesh=mesh;batch.instance_count=1
	batch.set_instance_transform(0,Transform3D.IDENTITY)
	lamp.multimesh=batch;level.add_child(lamp)
	environment.lamp_material=ShaderMaterial.new();environment.lamp_material.shader=load("res://shaders/sf3_reference.gdshader")
	environment.register_mesh(visual,false);environment.register_mesh(lamp,true)
	check(visual.mesh==mesh and mesh.surface_get_material(0)==source,"Shared geometry/material resources remain untouched")
	check(visual.get_surface_override_material(0) is ShaderMaterial and lamp.material_override is ShaderMaterial,"Mesh and MultiMesh adapters use instance overrides")
	check(batch.get_instance_transform(0)==Transform3D.IDENTITY,"Lamp placement stays unchanged")
	environment.restore_bindings()
	check(visual.get_surface_override_material(0)==null and visual.material_override==null and lamp.material_override==null,"Original per-instance overrides restore exactly")
	environment.register_mesh(visual,false)
	visual.free()
	environment.restore_bindings()
	check(environment.bindings.is_empty(),"Sector unload / expired weak references are safe")
	var baseline: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://docs/sf3_baseline.json"))
	for path in baseline["sha256"]: check(FileAccess.get_sha256("res://"+path)==baseline["sha256"][path],"Protected: "+path)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(environment.settings_path))
	var report:={"passed":failures.is_empty(),"checks":checks,"failures":failures,"metrics":metrics,"scenario":"Presentation telemetry, real instance override/restoration and protected production file hashes; synthetic geometry is test-only"}
	FileAccess.open("res://docs/sf3_validation.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("SF3_REPORT ",JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)

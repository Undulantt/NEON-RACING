extends "res://tests/sf1_city.gd"
var sf4_stage:=1

func benchmark() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--stage="):sf4_stage=int(arg.trim_prefix("--stage="))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	car.set_physics_process(false);world.follow_camera.set_physics_process(false)
	var vfx: Node3D=world.follow_camera.speed_feedback.vehicle_feedback
	vfx.set_physics_process(false)
	var slide:={"driving":true,"grounded":true,"speed":30.0,"slip":0.65,"drift":1.0,"grip":0.35}
	var until:=Time.get_ticks_msec()+2500
	while Time.get_ticks_msec()<until:await render_frame()
	for i in range(120):
		var at:=sample(3+i*0.25)
		var ahead:=sample(4+i*0.25)
		car.rotation.y=atan2(-(ahead.x-at.x),-(ahead.z-at.z))
		car.global_position=Vector3(at.x,car.supported_pose_height(at.x,at.z,car.rotation.y),at.z)
		car.align_visual_to_surface()
		vfx.advance(1.0/60,slide)
		await render_frame()
	world.follow_camera.snap();world.follow_camera.set_physics_process(false)
	await render_frame()
	if sf4_stage>=3:
		root.get_texture().get_image().save_png("res://docs/evidence/sf4_drift.png")
		vfx.preview_enabled=true
		for amount in [0.0,.25,.6,1.0]:
			vfx.preview_burst=amount
			for i in range(60):vfx.advance(1.0/60)
			await render_frame()
			root.get_texture().get_image().save_png("res://docs/evidence/sf4_burst_%03d.png"%roundi(amount*100))
		for i in range(90):
			var at:=sample(33+i*.25);var ahead:=sample(34+i*.25)
			car.rotation.y=atan2(-(ahead.x-at.x),-(ahead.z-at.z))
			car.global_position=Vector3(at.x,car.supported_pose_height(at.x,at.z,car.rotation.y),at.z)
			car.align_visual_to_surface();vfx.advance(1.0/60,slide)
			await render_frame()
		world.follow_camera.snap();world.follow_camera.set_physics_process(false)
		await render_frame()
	root.get_texture().get_image().save_png("res://docs/evidence/sf4_stage_%d.png"%sf4_stage)
	# Finish and freeze background city decoration equally in all samples.
	until=Time.get_ticks_msec()+3500
	while Time.get_ticks_msec()<until:await render_frame()
	while world.night_style.decorating:await render_frame()
	world.night_style.set_process(false)
	for child in world.night_style.get_children():
		if child.get_script()==preload("res://scripts/style/RetroLook.gd"):
			while child.road_busy:await render_frame()
			child.set_process(false)
	world.city_manager.set_physics_process(false)
	if "--capture-only" in OS.get_cmdline_user_args():
		await capture_panel(vfx)
		cleanup();quit();return
	var samples:=[]
	for active in [false,true,true,false]:
		vfx.smoke_batch.visible=active
		if sf4_stage>=2:vfx.mark_batch.visible=active
		if sf4_stage>=3:
			vfx.energy_visual.visible=active
			for binding in vfx.body_bindings:binding["node"].material_overlay=vfx.burst_material if active else binding["original"]
		until=Time.get_ticks_msec()+2000
		while Time.get_ticks_msec()<until:await render_frame()
		var ms: Array[float]=[];var previous:=Time.get_ticks_usec()
		for i in range(600):
			await render_frame()
			var now:=Time.get_ticks_usec();ms.append((now-previous)/1000.0);previous=now
		ms.sort()
		samples.append({"active":active,"median_ms":ms[300],"p95_ms":ms[570],"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)})
	if sf4_stage>=3:
		await capture_panel(vfx)
	var report:={"stage":sf4_stage,"gpu":RenderingServer.get_video_adapter_name(),"samples":samples,"particles":vfx.smoke.size(),"marks":vfx.marks.size(),"note":"Existing OSM avenue. VFX supplied slide telemetry for visual QA, frozen car physics; same scene current stage batches A/B/B/A. Not real driving FPS."}
	FileAccess.open("res://docs/sf4_stage_%d_render.json"%sf4_stage,FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("SF4_RENDER ",JSON.stringify(report))
	cleanup();quit()

func capture_panel(vfx: Node3D) -> void:
	vfx.smoke_batch.visible=true;vfx.mark_batch.visible=true;vfx.energy_visual.visible=true
	for binding in vfx.body_bindings:binding["node"].material_overlay=vfx.burst_material
	world.follow_camera.experiment_panel.open_requested=true
	world.follow_camera.experiment_panel.tabs.current_tab=3
	await render_frame();await render_frame()
	root.get_texture().get_image().save_png("res://docs/evidence/sf4_panel.png")

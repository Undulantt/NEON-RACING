extends "res://tests/sf3_city.gd"

func difference(a: Image, b: Image) -> float:
	var total:=0.0
	var count:=0
	# Two asphalt-only ROIs, excluding car, HUD, sky and mode labels.
	for left in [300,800]:
		for y in range(440,620,2):
			for x in range(left,left+140,2):
				var first:=a.get_pixel(x,y)
				var second:=b.get_pixel(x,y)
				total+=absf(first.r-second.r)+absf(first.g-second.g)+absf(first.b-second.b)
				count+=3
	return total/maxi(1,count)

func benchmark() -> void:
	car.set_physics_process(false)
	car.velocity=Vector3.ZERO
	car.speed_mps=0;car.forward_plane_speed=0;car.signed_speed=0
	car.abilities.turbo_active=false;car.abilities.burst_state=0;car.abilities.burst_bonus=0
	var rig: Node3D=world.follow_camera
	rig.set_physics_process(false);rig.camera.fov=75
	var environment: Node=rig.speed_feedback.environment_feedback
	environment.reset_experiment()
	var until:=Time.get_ticks_msec()+5500
	while Time.get_ticks_msec()<until: await render_frame()
	while world.night_style.decorating: await render_frame()
	world.night_style.set_process(false)
	var material: ShaderMaterial=environment.road_material
	var fixtures: RefCounted=environment.furniture
	environment.world=null;environment.road_material=null
	environment.try_bind_world()
	check_sf3(environment.world==world and environment.road_material==material and environment.furniture==fixtures,"Missing explicit adapter link recovers automatically without losing existing lights")
	var physics_before: Array=[car.global_transform,car.velocity,car.powertrain.rpm,car.abilities.burst_state,car.abilities.burst_bonus]
	var images:=[]
	var values:=[]
	for stage in ["original","original_repeat","stationary","preview"]:
		environment.set_mode("original" if stage in ["original","original_repeat"] else "full")
		environment.set_preview(stage=="preview")
		until=Time.get_ticks_msec()+1800
		while Time.get_ticks_msec()<until: await render_frame()
		var captured:=root.get_texture().get_image()
		captured.save_png("res://docs/evidence/sf3_fix_%s.png"%stage)
		images.append(captured)
		values.append({"stage":stage,"applied_gain":environment.applied_gain(),"shader_asphalt":environment.road_material.get_shader_parameter("sf3_asphalt"),"bindings":environment.bindings.size(),"speed_kmh":environment.last_speed_kmh,"diagnostic":environment.diagnostic()})
	var noise_difference:=difference(images[0],images[1])
	var base_difference:=difference(images[0],images[2])
	var preview_difference:=difference(images[0],images[3])
	check_sf3(base_difference>noise_difference+0.002,"Stationary SF.3 changes actual asphalt pixels")
	check_sf3(preview_difference>noise_difference+0.01,"Static preview has a clearly measurable asphalt change")
	check_sf3(values[0]["applied_gain"]==0 and values[0]["bindings"]==0,"Original still restores materials")
	check_sf3(values[3]["shader_asphalt"]>0.6 and values[3]["bindings"]>0,"Preview reaches the real road shader and existing markings")
	check_sf3(physics_before==[car.global_transform,car.velocity,car.powertrain.rpm,car.abilities.burst_state,car.abilities.burst_bonus],"Comparison does not simulate motion, RPM or BURST")
	check_sf3(rig.speed_feedback.visual_state["burst_ratio"]==0,"SF.4 sees real BURST progress even in preview")
	rig.experiment_panel.open_requested=true
	rig.experiment_panel.tabs.current_tab=2
	until=Time.get_ticks_msec()+500
	while Time.get_ticks_msec()<until: await render_frame()
	rig.experiment_panel.refresh_timer=0
	await render_frame()
	root.get_texture().get_image().save_png("res://docs/evidence/sf3_fix_panel.png")
	var report:={"passed":sf3_failures.is_empty(),"failures":sf3_failures,"scenario":"Real city, stationary car, same pose/camera and frozen decoration. GPU-rendered pixel comparison in two ground ROIs excluding HUD/car. Preview is visual only.","original_repeat_rgb_difference":noise_difference,"asphalt_mean_abs_rgb_difference":base_difference,"preview_mean_abs_rgb_difference":preview_difference,"stages":values}
	FileAccess.open("res://docs/sf3_visibility_validation.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("SF3_VISIBILITY_REPORT ",JSON.stringify(report))
	cleanup()
	quit(0 if sf3_failures.is_empty() else 1)

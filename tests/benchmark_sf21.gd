extends "res://tests/sf1_city.gd"
# Same real city and camera, only audio A/B changes. No physics writes in production.
func benchmark() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	car.set_physics_process(false)
	car.speed_mps=50;car.forward_plane_speed=50;car.signed_speed=50
	car.powertrain.rpm=6500;car.powertrain.gear=7;car.powertrain.load=0.9
	var rig: Node3D=world.follow_camera
	rig.speed_feedback.reset_experiment()
	var audio: Node=rig.speed_feedback.audio_feedback
	audio.reset_experiment()
	for mode in [false,true,true,false]:
		audio.set_experimental(mode)
		var until:=Time.get_ticks_msec()+3000
		while Time.get_ticks_msec()<until: await render_frame()
		var intervals: Array[float]=[]
		var audio_us:=0.0
		var previous:=Time.get_ticks_usec()
		for i in range(600):
			await render_frame()
			var now:=Time.get_ticks_usec()
			intervals.append(float(now-previous)/1000)
			previous=now
			audio_us+=audio.last_update_us
		intervals.sort()
		var total:=0.0
		for v in intervals: total+=v
		var value:={"audio_mode":"B" if mode else "A","mean_ms":total/600,"median_ms":intervals[300],"p95_ms":intervals[570],"audio_mean_us":audio_us/600}
		sf1_results.append(value)
		print("SF21_BENCH_SAMPLE ",JSON.stringify(value))
	audio.set_experimental(true)
	rig.experiment_panel.open_requested=true
	rig.experiment_panel.tabs.current_tab=1
	for i in range(60): await render_frame()
	root.get_texture().get_image().save_png("res://docs/evidence/sf21_audio_panel.png")
	rig.experiment_panel.tabs.current_tab=0
	car.abilities.turbo_active=true
	var until:=Time.get_ticks_msec()+1500
	while Time.get_ticks_msec()<until: await render_frame()
	root.get_texture().get_image().save_png("res://docs/evidence/sf11_turbo_panel.png")
	var a: float=(sf1_results[0]["mean_ms"]+sf1_results[3]["mean_ms"])*0.5
	var b: float=(sf1_results[1]["mean_ms"]+sf1_results[2]["mean_ms"])*0.5
	var passed:=b-a<=maxf(1.0,a*0.15)
	var output:={"passed":passed,"scenario":"1280x720 full existing city; Compatibility, VSync off, same camera and frozen synthetic 180 km/h telemetry, 6500 RPM; audio A/B/B/A, 3 seconds warmup and 600 rendered samples; NOT city-traversal FPS","gpu":RenderingServer.get_video_adapter_name(),"samples":sf1_results,"B_minus_A_ms":b-a,"B_overhead_percent":(b/a-1)*100}
	FileAccess.open("res://docs/sf21_benchmark.json",FileAccess.WRITE).store_string(JSON.stringify(output,"  "))
	print("SF21_BENCHMARK ",JSON.stringify(output))
	cleanup()
	quit(0 if passed else 1)

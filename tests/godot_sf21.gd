extends SceneTree
const Profiles=preload("res://scripts/driving/VehicleProfiles.gd")
var car: CharacterBody3D
var rig: Node3D
var audio: Node
var failures: Array[String]=[]
var checks:=0
var metrics:={}
func _initialize() -> void: run.call_deferred()
func check(value: bool, message: String) -> void:
	checks+=1
	if not value: failures.append(message);push_error(message)
func frame(rpm: float, load_value: float, speed: float, turbo:=false, burst: float=-1) -> void:
	car.powertrain.rpm=rpm
	car.powertrain.load=load_value
	car.throttle_input=load_value
	car.speed_mps=speed
	car.forward_plane_speed=speed
	car.abilities.turbo_active=turbo
	car.abilities.burst_state=2 if burst>=0 else 0
	car.abilities.burst_bonus=maxf(0,burst)*float(car.config["burst_max_bonus"])
	rig._physics_process(1.0/60)
	audio._process(1.0/60)
func settle(rpm: float, load_value: float, speed: float, turbo:=false, burst: float=-1) -> void:
	for i in range(360): frame(rpm,load_value,speed,turbo,burst)
func run() -> void:
	var level:=Node3D.new()
	root.add_child(level)
	car=preload("res://scenes/cars/PlayerCar.tscn").instantiate()
	level.add_child(car)
	car.external_control=true
	car.configure({"roads":[{"points_xz":[[0,1000],[0,-1000]],"oneway":false,"street_name":"SYNTHETIC TELEMETRY FIXTURE"}]},{"bounds_xz":[-900,-1500,900,1500],"spawn":{"position_xz":[0,0],"forward_xz":[0,-1]}})
	rig=preload("res://scripts/driving/FollowCamera.gd").new()
	level.add_child(rig)
	rig.attach(car)
	audio=rig.speed_feedback.audio_feedback
	car.set_physics_process(false)
	rig.set_physics_process(false)
	audio.set_process(false)
	for id in Profiles.IDS:
		car.apply_vehicle_profile(id)
		rig.speed_feedback.reset_experiment()
		audio.reset_experiment()
		var cap: float=car.base_speed_cap
		var fovs:=[]
		for percent in [0,10,15,25]:
			rig.experiment_panel.buttons["turbo_%d"%percent].pressed.emit()
			check(is_equal_approx(float(rig.speed_feedback.settings["turbo_fov_percent"]),percent),id+" integer preset button "+str(percent))
			settle(6500,1,cap,true)
			fovs.append(rig.camera.fov)
			check(absf(rig.camera.fov-78*(1+float(percent)/100))<0.01,id+" literal TURBO FOV "+str(percent))
		settle(6500,1,cap,true,1)
		check(absf(rig.camera.fov-97.5)<0.01,id+" TURBO and BURST use maximum, not sum")
		rig.speed_feedback.set_setting("turbo_fov_max_deg",88)
		settle(6500,1,cap,true,1)
		check(absf(rig.camera.fov-88)<0.01,id+" configurable TURBO cap")
		rig.speed_feedback.reset_experiment()
		settle(6500,1,cap,false)
		check(absf(rig.camera.fov-75)<0.01,id+" approved normal FOV preserved")
		var previous: float=rig.camera.fov
		var max_step:=0.0
		for i in range(30):
			frame(6500,1,cap,true)
			max_step=maxf(max_step,absf(rig.camera.fov-previous))
			previous=rig.camera.fov
		check(rig.camera.fov>96 and max_step<2,id+" rapid smooth TURBO onset")
		frame(6500,1,cap,false)
		check(rig.camera.fov<previous and rig.camera.fov>90,id+" gradual TURBO release")
		settle(6500,1,cap,false,1)
		check(absf(rig.camera.fov-82)<0.01,id+" pure BURST remains approved SF.1")
		settle(900,0,0)
		check(absf(audio.engine_pitch-0.3)<0.001 and audio.wind_intensity<0.001,id+" idle motor and silent wind")
		check(audio.high_bank_mix<0.001,id+" idle uses low RPM bank")
		var pitches:=[]
		for rpm in [2500,4500,7300]:
			settle(rpm,1,cap*0.7)
			pitches.append(audio.engine_pitch)
		check(pitches[0]<pitches[1] and pitches[1]<pitches[2],id+" motor follows real RPM")
		check(audio.high_bank_mix>0.999,id+" high RPM reaches roar bank")
		var before: float=audio.engine_pitch
		for i in range(12): frame(5500,1,cap*0.7)
		check(audio.engine_pitch<before-0.4,id+" upshift RPM drop is audible in target pitch")
		check(audio.high_bank_mix<0.8 and audio.high_bank_mix>0.6,id+" upshift smoothly returns toward low RPM timbre")
		settle(5000,1,cap)
		var loaded_gain: float=audio.gains["load"]
		var loaded_pitch: float=audio.engine_pitch
		settle(5000,0,cap)
		check(audio.gains["load"]<loaded_gain*0.15 and audio.engine_pitch<loaded_pitch-0.1,id+" lift-off changes load and acoustic pitch")
		check(car.powertrain.rpm==5000,id+" acoustic lift does not modify mechanical RPM")
		settle(20000,1,cap*3)
		check(audio.engine_pitch<=audio.settings["engine_pitch_max"]+0.0001,id+" pitch never increases indefinitely")
		var winds:=[]
		for speed in [5.0,cap,cap*(1+float(car.config["burst_max_bonus"])),cap*3]:
			settle(6500,1,speed)
			winds.append(audio.wind_intensity)
		check(winds[0]<0.001 and absf(winds[1]-1)<0.001 and winds[2]>winds[1] and absf(winds[2]-winds[3])<0.001,id+" wind follows actual speed and saturates above BURST cap")
		settle(6500,1,0,false,1)
		check(audio.wind_intensity<0.001,id+" a BURST state alone cannot invent wind speed")
		audio.set_setting("engine_enabled",false)
		settle(6500,1,cap)
		check(audio.gains["load"]<0.0001 and audio.gains["wind"]>0.01,id+" wind is independent of engine toggle")
		audio.set_setting("engine_enabled",true)
		audio.set_setting("wind_enabled",false)
		settle(6500,1,cap)
		check(audio.gains["load"]>0.01 and audio.gains["wind"]<0.0001,id+" engine is independent of wind toggle")
		audio.reset_experiment()
		var camera_settings: Dictionary=rig.speed_feedback.settings.duplicate(true)
		audio.set_experimental(false)
		settle(6500,1,cap)
		check(audio.blend==0 and rig.speed_feedback.settings==camera_settings,id+" audio A does not change camera")
		audio.set_experimental(true)
		metrics[id]={"fov_presets":fovs,"pitch_by_rpm":pitches,"wind_by_speed":winds,"max_fov_step_deg":max_step}

	# Test the larger default TURBO lens against a rear wall at 21:9.
	car.global_position=Vector3(0,0.49,0)
	root.size=Vector2i(2520,1080)
	settle(6500,1,car.base_speed_cap,true,1)
	var wall:=StaticBody3D.new()
	wall.position=Vector3(0,2,3)
	var shape:=CollisionShape3D.new()
	var box:=BoxShape3D.new()
	box.size=Vector3(8,4,0.3)
	shape.shape=box
	wall.add_child(shape)
	level.add_child(wall)
	rig.set_physics_process(true)
	for i in range(40): await physics_frame
	var view:=root.get_visible_rect().size
	var corner: float=rig.camera.near*tan(deg_to_rad(rig.camera.fov)/2)*sqrt(1+pow(view.x/view.y,2))
	check(rig.arm.shape.radius>corner,"97.5 degree lens protects ultrawide near-plane corners")
	check(rig.camera.global_position.z+rig.arm.shape.radius<2.85,"Expanded TURBO lens clears rear wall")
	check(rig.camera.global_position.y-rig.arm.shape.radius>car.global_position.y+0.728,"Expanded TURBO lens stays above own roof when retracted")
	wall.queue_free()
	rig.set_physics_process(false)
	root.size=Vector2i(1280,720)
	audio.settings_path="res://tests/.sf21_settings.cfg"
	audio.set_setting("wind_gain_db",-31)
	check(audio.save_trial(),"Audio saves separately from camera and profiles")
	audio.set_setting("wind_gain_db",-35)
	check(audio.load_trial() and audio.settings["wind_gain_db"]==-31,"Audio trial round trip")
	check(not audio.set_setting("wind_gain_db",NAN) and not audio.set_setting("speed",50),"Reject invalid audio values and physics writes")
	check(not rig.speed_feedback.set_setting("turbo_fov_percent",12),"Only approved TURBO presets are accepted")
	rig.experiment_panel.audio_sliders["wind_gain_db"].value=-33
	check(audio.settings["wind_gain_db"]==-33,"Live audio slider works")
	var no_focus: bool=rig.experiment_panel.tabs.get_tab_bar().focus_mode==Control.FOCUS_NONE
	for widget in rig.experiment_panel.audio_sliders.values()+rig.experiment_panel.audio_toggles.values()+rig.experiment_panel.buttons.values(): no_focus=no_focus and widget.focus_mode==Control.FOCUS_NONE
	check(no_focus,"Audio controls preserve driving keyboard focus")
	root.get_node("GameFlow").current_state=&"free_drive"
	var event:=InputEventKey.new()
	event.keycode=KEY_O;event.pressed=true;event.ctrl_pressed=true;event.alt_pressed=true
	rig.experiment_panel._input(event)
	check(not audio.settings["experimental_enabled"],"Independent audio A/B shortcut")
	paused=true
	check(not rig.experiment_panel.can_use(),"Pause hides extended debug UI")
	paused=false
	var manifest: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://docs/sf21_baseline.json"))
	for path in manifest["sha256"]: check(FileAccess.get_sha256("res://"+path)==manifest["sha256"][path],"Unchanged protected file: "+path)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(audio.settings_path))
	var report:={"passed":failures.is_empty(),"checks":checks,"failures":failures,"metrics":metrics,"scenario":"Synthetic read-only presentation telemetry; actual controller/gearbox replay is independently covered by godot_sf1 and powertrain suites"}
	FileAccess.open("res://docs/sf21_validation.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("SF21_REPORT ",JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)

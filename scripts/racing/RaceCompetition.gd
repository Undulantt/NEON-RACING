extends Node3D
const Driver = preload("res://scripts/racing/RivalDriver.gd")
const Session = preload("res://scripts/racing/RaceSession.gd")
var racers: Array = []
var rivals: Array = []
var world: Node3D
var debug_enabled := false
var debug_label: Label
var debug_mesh: MeshInstance3D
var finish_order := 0
var observe := -1
var grid_columns := 1
var trajectory: RefCounted
var difficulty := "standard"

func prepare(target: Node3D, data: Dictionary, player_session: RefCounted) -> void:
	world=target
	difficulty=world.get_node("/root/GameFlow").rival_difficulty
	trajectory=preload("res://scripts/racing/RaceTrajectory.gd").new()
	trajectory.corner_radius_m=18.0 if difficulty=="expert" else 12.0
	trajectory.configure(data,world.player)
	var settings: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://config/rivals.json"))
	var count:=clampi(int(settings["rival_count"]),0,5)
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--rivals="): count=clampi(int(argument.trim_prefix("--rivals=")),0,5)
	racers.append({"name":"Tú","car":world.player,"session":player_session,"previous":Vector2(world.player.position.x,world.player.position.z),"finish":0,"driver":null})
	# Use two columns where the road and physical support permit it. Narrow
	# starts retain longitudinal spacing; every slot stays before gate one.
	var points: Array=data["points_xz"]
	var a:=Vector2(points[-2][0],points[-2][1]) if data["type"]=="circuit" else Vector2(points[0][0],points[0][1])
	var b:=Vector2(points[0][0],points[0][1])
	var incoming:=(b-a).normalized()
	var start_forward:=Vector2(data["start"]["forward_xz"][0],data["start"]["forward_xz"][1])
	var start_at:=Vector2(data["start"]["position_xz"][0],data["start"]["position_xz"][1])
	var grid_right:=Vector2(-start_forward.y,start_forward.x)
	if count>0 and minf(float(data["checkpoints"][0]["half_width_m"]),float(data["finish"]["half_width_m"]))>=4.8:
		var player_pose:=grid_pose(world.player,start_at-grid_right*2.2,start_forward)
		if world.player.safe_road_transform(player_pose):
			grid_columns=2
			world.player.global_transform=player_pose
			world.player.spawn_transform=player_pose
			world.player.safe_transform=player_pose
			world.player.reset_surface_motion()
	for index in range(count):
		var entry: Dictionary=settings["lineup"][index%settings["lineup"].size()]
		var car=preload("res://scenes/cars/PlayerCar.tscn").instantiate()
		car.external_control=true
		car.vehicle_profile=entry["vehicle"]
		car.driving_enabled=false
		world.add_child(car)
		car.elevation=world.player.elevation
		car.configure(world.map_data,world.environment_data)
		car.apply_vehicle_profile(entry["vehicle"])
		car.feedback.muted=true
		car.feedback.set_process_unhandled_input(false)
		if world.night_visuals: preload("res://scripts/style/RetroCar.gd").build(car)
		var p:=b-incoming*(6.0+index*6.0)
		var direction:=incoming
		if data["type"]!="circuit":
			p=start_at-start_forward*(6+index*6)
			direction=start_forward
		if grid_columns==2:
			var slot:=index+1
			var row:=slot/2
			var lateral:=2.2 if slot%2==1 else -2.2
			p=start_at+grid_right*lateral if row==0 else b-incoming*(row*7.0)+Vector2(-incoming.y,incoming.x)*lateral
			direction=start_forward if row==0 else incoming
			if data["type"]!="circuit":
				p=start_at-start_forward*(row*7.0)+grid_right*lateral
				direction=start_forward
		var pose:=grid_pose(car,p,direction)
		if not car.safe_road_transform(pose):
			p=start_at-start_forward*(12+index*7)
			pose=grid_pose(car,p,start_forward)
		car.global_transform=pose
		car.spawn_transform=car.global_transform
		car.safe_transform=car.global_transform
		car.reset_surface_motion()
		var nameplate:=Label3D.new()
		nameplate.text=entry["name"]+" · "+entry["vehicle"]
		nameplate.position=Vector3(0,2.5,0)
		nameplate.font_size=32
		nameplate.pixel_size=0.008
		nameplate.billboard=BaseMaterial3D.BILLBOARD_ENABLED
		car.add_child(nameplate)
		var progress=Session.new()
		progress.begin(data)
		progress.checkpoint_heights=player_session.checkpoint_heights.duplicate()
		var driver=Driver.new()
		driver.configure(car,progress,entry["personality"],preload("res://scripts/racing/RivalDifficulty.gd").settings(settings["profiles"][entry["personality"]],difficulty),trajectory)
		driver.preferred_lane=float(entry.get("line_preference_m",0))
		var racer:={"name":entry["name"],"car":car,"session":progress,"previous":p,"previous_y":car.position.y,"finish":0,"driver":driver}
		racers.append(racer)
		rivals.append(car)
	for racer in racers:
		if racer["driver"]!=null: racer["driver"].participants=[world.player]+rivals
	for manager in [world.road_root,world.terrain_root,world.limit_root,world.city_manager]:
		if manager!=null: manager.race_targets=rivals
	debug_label=Label.new()
	debug_label.position=Vector2(10,430)
	debug_label.add_theme_font_size_override("font_size",15)
	world.race_activity.overlay.add_child(debug_label)
	debug_mesh=MeshInstance3D.new()
	add_child(debug_mesh)

func grid_pose(car: CharacterBody3D, at: Vector2, direction: Vector2) -> Transform3D:
	var yaw:=atan2(-direction.x,-direction.y)
	return Transform3D(Basis(Vector3.UP,yaw),Vector3(at.x,car.supported_pose_height(at.x,at.y,yaw),at.y))

func step(delta: float) -> void:
	for racer in racers:
		var car=racer["car"]
		var progress=racer["session"]
		car.set_meta("race_competing",progress.phase=="running")
		if car!=world.player:
			var p:=Vector2(car.position.x,car.position.z)
			progress.advance(racer["previous"],p,delta,is_finite(car.surface_height(p.x,p.y)),float(racer["previous_y"]),car.position.y)
			racer["previous"]=p
			racer["previous_y"]=car.position.y
			car.driving_enabled=progress.phase=="running"
			racer["driver"].update(delta)
		if progress.phase=="finished" and racer["finish"]==0:
			finish_order+=1
			racer["finish"]=finish_order
		if progress.phase=="finished":
			if car==world.player:
				car.set_controls(0,0,false,false,1)
				car.driving_enabled=false
			else:
				clear_finish_lane(racer)
	if debug_enabled:
		var lines:=PackedStringArray()
		for racer in racers:
			if racer["driver"]!=null: lines.append(racer["name"]+" "+racer["driver"].telemetry())
		debug_label.text="F6 depuración · Ctrl+Alt+O observar\n"+"\n".join(lines)
		draw_debug()
	else:
		debug_label.text="Observando: "+racers[observe+1]["name"]+" · Ctrl+Alt+O cambiar" if observe>=0 else ""
		debug_mesh.mesh=null
	if observe>=0 and observe<rivals.size():
		world.follow_camera.car=rivals[observe]

func clear_finish_lane(racer: Dictionary) -> void:
	var car: CharacterBody3D=racer["car"]
	var official: RefCounted=racer["session"]
	if racer.get("parked",false) or official.definition["type"]!="circuit":
		racer["driver"].state="parked"
		racer["driver"].target_speed=0.0
		car.set_controls(0,0,true)
		car.driving_enabled=false
		return
	var p:=Vector2(car.position.x,car.position.z)
	if not racer.has("parking_driver"):
		# Private navigation progress after finishing: never change the official
		# lap count, placing or final time. Continue with the same physical AI.
		var progress=Session.new()
		progress.begin(official.definition)
		progress.checkpoint_heights=official.checkpoint_heights.duplicate()
		progress.phase="running"
		var driver=Driver.new()
		driver.configure(car,progress,racer["driver"].personality_id,racer["driver"].personality,trajectory)
		driver.participants=[world.player]+rivals
		var arrival: Dictionary=trajectory.project(p,racer["driver"].nav_s)
		# Retire on the nearest shoulder; crossing the whole road here can
		# box a finisher between cars that have already stopped on the side.
		driver.preferred_lane=3.5 if float(arrival["lateral"])>=0 else -3.5
		driver.lane=float(arrival["lateral"])
		driver.cruise_speed_limit=8.0
		driver.allow_abilities=false
		driver.validate_gates=false
		driver.prefer_full_lane=true
		# Queue behind cars already retired on the shoulder instead of passing
		# them and circulating indefinitely after the official finish.
		driver.allow_passing=false
		racer["parking_driver"]=driver
		racer["parking_session"]=progress
		racer["parking_previous"]=p
		racer["parking_previous_y"]=car.position.y
	var progress: RefCounted=racer["parking_session"]
	var driver: RefCounted=racer["parking_driver"]
	progress.advance(racer["parking_previous"],p,get_physics_process_delta_time(),is_finite(car.surface_height(p.x,p.y)),float(racer["parking_previous_y"]),car.position.y)
	racer["parking_previous"]=p
	racer["parking_previous_y"]=car.position.y
	if progress.phase=="finished":
		progress.begin(official.definition)
		progress.checkpoint_heights=official.checkpoint_heights.duplicate()
		progress.phase="running"
		driver.nav_s=-INF
		driver.best_nav_s=-INF
	var frame: Dictionary=trajectory.project(p,driver.nav_s)
	var local_s:=fposmod(float(frame["s"]),trajectory.length)
	var stop_after:=15.0+5.0*(int(racer["finish"])-1)
	var aligned: float=Vector2(-car.global_basis.z.x,-car.global_basis.z.z).dot(frame["forward"])
	var room:=true
	for other in [world.player]+rivals:
		if other!=car and is_instance_valid(other) and car.position.distance_squared_to(other.position)<49:
			var relative:=Vector2(other.position.x-car.position.x,other.position.z-car.position.z)
			if relative.dot(frame["forward"])>-2: room=false
	var first_at:=Vector2(official.definition["points_xz"][0][0],official.definition["points_xz"][0][1])
	var first_end:=Vector2(official.definition["points_xz"][1][0],official.definition["points_xz"][1][1])
	var street_forward: Vector2=(first_end-first_at).normalized()
	var street_side: float=(p-first_at).dot(Vector2(-street_forward.y,street_forward.x))
	var side_clear: bool=absf(street_side)>2.2 and aligned>0.97
	var queued_on_side: bool=car.speed_mps<0.7 and local_s>7 and local_s<72
	var can_stop: bool=side_clear and ((local_s>=stop_after and local_s<72 and room) or queued_on_side)
	if racer.get("parking_braking",false) or can_stop:
		racer["parking_braking"]=true
		car.set_controls(0,0,true)
		car.driving_enabled=false
		if car.speed_mps<0.4: racer["parked"]=true
	else:
		car.driving_enabled=true
		driver.update(get_physics_process_delta_time())
	racer["driver"].state="parking"
	racer["driver"].target=driver.target
	racer["driver"].target_speed=driver.target_speed

func standings() -> Array:
	var order:=racers.duplicate()
	order.sort_custom(func(a: Dictionary,b: Dictionary):
		if a["finish"]>0 or b["finish"]>0:
			if a["finish"]==0: return false
			if b["finish"]==0: return true
			if not is_equal_approx(a["session"].elapsed,b["session"].elapsed): return a["session"].elapsed<b["session"].elapsed
			return a["finish"]<b["finish"]
		var x=a["session"]
		var y=b["session"]
		if x.completed_laps!=y.completed_laps: return x.completed_laps>y.completed_laps
		if x.next_checkpoint!=y.next_checkpoint: return x.next_checkpoint>y.next_checkpoint
		return x.progress_m>y.progress_m)
	return order

func table(results := false) -> String:
	var rows:=PackedStringArray()
	var place:=0
	for racer in standings():
		place+=1
		var s=racer["session"]
		var timing:="%.2f s" % s.elapsed if s.phase=="finished" else ("En carrera" if results else "V%d CP%d" % [s.current_lap(),s.next_checkpoint+1])
		var best:=" · mejor %.2f" % s.lap_times.min() if results and not s.lap_times.is_empty() else ""
		rows.append("%d. %s · %s · %s%s" % [place,racer["name"],racer["car"].vehicle_profile,timing,best])
	return "\n".join(rows)

func player_place() -> int:
	var place:=0
	for racer in standings():
		place+=1
		if racer["car"]==world.player: return place
	return place

func draw_debug() -> void:
	var mesh:=ImmediateMesh.new()
	var material:=StandardMaterial3D.new()
	material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo=true
	mesh.surface_begin(Mesh.PRIMITIVE_LINES,material)
	for racer in racers:
		if racer["driver"]==null: continue
		mesh.surface_set_color(Color.CYAN)
		mesh.surface_add_vertex(racer["car"].position+Vector3.UP)
		mesh.surface_add_vertex(racer["driver"].target+Vector3.UP)
	for i in range(trajectory.points.size()-1):
		for p in [trajectory.points[i],trajectory.points[i+1]]:
			mesh.surface_set_color(Color(1,0.2,0.8))
			mesh.surface_add_vertex(Vector3(p.x,world.player.surface_height(p.x,p.y)+0.3,p.y))
	mesh.surface_end()
	debug_mesh.mesh=mesh

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode==KEY_F6: debug_enabled=not debug_enabled
		if event.keycode==KEY_O and event.ctrl_pressed and event.alt_pressed:
			observe+=1
			if observe>=rivals.size():
				observe=-1
				world.follow_camera.car=world.player
			world.follow_camera.snap()

func result_rows() -> Array:
	var rows: Array=[]
	for racer in standings():
		var s=racer["session"]
		rows.append({"position":rows.size()+1,"name":racer["name"],"vehicle":racer["car"].vehicle_profile,"finished":s.phase=="finished","elapsed_seconds":s.elapsed if s.phase=="finished" else null,"lap_times":s.lap_times.duplicate(),"best_lap":s.lap_times.min() if not s.lap_times.is_empty() else null})
	return rows

func dispose() -> void:
	if is_instance_valid(world):
		world.follow_camera.car=world.player
		for manager in [world.road_root,world.terrain_root,world.limit_root,world.city_manager]:
			if manager!=null: manager.race_targets=[]
	for car in rivals:
		if is_instance_valid(car):
			car.get_parent().remove_child(car)
			car.queue_free()
	rivals.clear()
	if is_instance_valid(debug_label): debug_label.queue_free()
	queue_free()

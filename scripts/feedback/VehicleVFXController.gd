extends Node3D
# SF.4 presentation only. Reads car state and rear wheel anchors; never controls it.
signal settings_changed
const CONFIG := "res://config/sf4_vehicle_vfx.json"
const RANGES := {"smoke_density":[4.0,55.0],"smoke_lifetime_s":[0.3,1.8],"smoke_size_m":[0.6,2.4],"smoke_max":[16,128],"marks_max":[64,1024],"marks_lifetime_s":[3.0,30.0],"burst_strength":[0.0,1.0],"burst_attack_per_s":[3.0,25.0],"burst_release_s":[0.15,0.35]}
var car: CharacterBody3D
var settings: Dictionary
var smoke: Array=[]
var smoke_batch: MultiMeshInstance3D
var clock:=0.0
var slide_seconds:=0.0
var slide_intensity:=0.0
var credits:=[0.0,0.0]
var rng:=RandomNumberGenerator.new()
var previous_position:=Vector3.ZERO
var last_update_us:=0
var total_emitted:=0
var contacts: Array=[]
var phase:=4
var marks: Array=[]
var mark_batch: MultiMeshInstance3D
var mark_material: ShaderMaterial
var previous_contacts: Array=[{},{}]
var mark_origin:=Vector3.ZERO
var marks_dirty:=true
var ray_queries:=0
var burst_material: ShaderMaterial
var body_bindings: Array=[]
var burst_value:=0.0
var real_burst_ratio:=0.0
var preview_enabled:=false
var preview_burst:=0.0
var turbo_flash:=0.0
var turbo_was_active:=false
var energy_history: Array=[]
var energy_mesh:=ImmediateMesh.new()
var energy_visual: MeshInstance3D
var hud: CanvasLayer
var bind_timer:=0.0
var settings_path:="user://sf4_vehicle_vfx.cfg"
var legacy_turbo_trail: Node3D

func configure(target: CharacterBody3D) -> void:
	car=target
	top_level=true
	physics_interpolation_mode=Node.PHYSICS_INTERPOLATION_MODE_OFF
	settings=JSON.parse_string(FileAccess.get_file_as_string(CONFIG))
	rng.seed=20261113
	process_physics_priority=130
	previous_position=car.global_position
	var mat:=ShaderMaterial.new();mat.shader=preload("res://shaders/sf4_smoke.gdshader")
	mat.set_shader_parameter("illustrated_smoke",preload("res://assets/textures/sf4_smoke.png"))
	smoke_batch=make_batch(128,QuadMesh.new(),mat)
	smoke_batch.name="IllustratedSmoke"
	mark_material=ShaderMaterial.new();mark_material.shader=preload("res://shaders/sf4_tire_marks.gdshader")
	var plane:=PlaneMesh.new();plane.size=Vector2.ONE
	mark_batch=make_batch(1024,plane,mark_material)
	mark_batch.name="PersistentTireMarks"
	mark_batch.top_level=true
	mark_origin=car.global_position
	mark_batch.global_position=mark_origin
	mark_batch.multimesh.custom_aabb=AABB(Vector3(-800,-300,-800),Vector3(1600,600,1600))
	burst_material=ShaderMaterial.new();burst_material.shader=preload("res://shaders/sf4_burst_body.gdshader")
	var energy_material:=StandardMaterial3D.new()
	energy_material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	energy_material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	energy_material.blend_mode=BaseMaterial3D.BLEND_MODE_ADD
	energy_material.vertex_color_use_as_albedo=true
	energy_material.cull_mode=BaseMaterial3D.CULL_DISABLED
	energy_visual=MeshInstance3D.new();energy_visual.name="BurstEnergyRibbons"
	energy_visual.mesh=energy_mesh;energy_visual.material_override=energy_material
	energy_visual.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(energy_visual)
	refresh_body_bindings()
	car.recovered.connect(func(_reason): clear_effects())
	car.vehicle_profile_changed.connect(func(_id): clear_effects())
	sync_legacy()
	if FileAccess.file_exists(settings_path):load_trial()
	if "--sf4-original" in OS.get_cmdline_user_args():set_setting("experimental_enabled",false)

func make_batch(limit: int, mesh: Mesh, mat: Material) -> MultiMeshInstance3D:
	var mm:=MultiMesh.new();mm.transform_format=MultiMesh.TRANSFORM_3D;mm.use_custom_data=true
	mm.mesh=mesh;mm.instance_count=limit;mm.visible_instance_count=0
	mm.custom_aabb=AABB(Vector3(-300,-100,-300),Vector3(600,200,600))
	var node:=MultiMeshInstance3D.new();node.multimesh=mm;node.material_override=mat
	node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	return node

func set_setting(key: String, value: Variant) -> void:
	if not settings.has(key): return
	if settings[key] is bool:
		if not value is bool: return
		settings[key]=value
	elif RANGES.has(key) and (value is float or value is int) and is_finite(float(value)):
		settings[key]=clampf(float(value),RANGES[key][0],RANGES[key][1])
	else: return
	if key=="experimental_enabled":clear_effects()
	if key=="smoke_enabled" and not value:
		smoke.clear();credits=[0.0,0.0];smoke_batch.multimesh.visible_instance_count=0
	if key=="smoke_max":
		while smoke.size()>int(settings["smoke_max"]):smoke.pop_front()
	if key=="marks_enabled" and not value:
		marks.clear();previous_contacts=[{},{}];marks_dirty=true;mark_batch.multimesh.visible_instance_count=0
	if key=="marks_max":
		while marks.size()>int(settings["marks_max"]):marks.pop_front()
		marks_dirty=true
	if key=="burst_enabled" and not value:clear_energy()
	if key in ["experimental_enabled","burst_enabled"]:sync_legacy()
	settings_changed.emit()

func reset_experiment() -> void:
	settings=JSON.parse_string(FileAccess.get_file_as_string(CONFIG))
	preview_enabled=false;preview_burst=0
	clear_effects();sync_legacy();settings_changed.emit()

func sync_legacy() -> void:
	if car==null or car.drift_particles==null: return
	car.drift_particles.set_physics_process(not settings["experimental_enabled"])
	car.drift_particles.clear_trail()
	if is_instance_valid(hud):
		var original: bool=not (settings["experimental_enabled"] and settings["burst_enabled"])
		hud.ground_flames.set_physics_process(original)
		hud.ground_flames.clear_trail()
		hud.speed_effects.sf4_burst_progress=-1.0 if original else burst_value

func clear_effects() -> void:
	smoke.clear();credits=[0.0,0.0];slide_seconds=0;slide_intensity=0
	if smoke_batch!=null:smoke_batch.multimesh.visible_instance_count=0
	marks.clear();previous_contacts=[{},{}];marks_dirty=true
	if mark_batch!=null:
		mark_batch.multimesh.visible_instance_count=0
		mark_origin=car.global_position;mark_batch.global_position=mark_origin
	clear_energy()

func clear_energy() -> void:
	burst_value=0;real_burst_ratio=0;turbo_flash=0;turbo_was_active=false
	energy_history.clear();energy_mesh.clear_surfaces()
	if burst_material!=null:burst_material.set_shader_parameter("progress",0.0);burst_material.set_shader_parameter("turbo_flash",0.0)
	for binding in body_bindings:
		if is_instance_valid(binding["node"]):binding["node"].material_overlay=binding["original"]

func wheel_contacts() -> Array:
	var result: Array=[]
	if car.visuals["pivots"].size()<4:return [{},{}]
	for i in [2,3]:
		var p: Vector3=car.visuals["pivots"][i].global_position
		var query:=PhysicsRayQueryParameters3D.create(p+Vector3.UP*0.2*car.vehicle_scale,p-Vector3.UP*0.65*car.vehicle_scale,1)
		query.exclude=[car.get_rid()]
		var hit:=get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty() and Vector3(hit["normal"]).dot(Vector3.UP)<0.45:hit={}
		result.append(hit)
	return result

func snapshot() -> Dictionary:
	return {"driving":car.driving_enabled,"grounded":car.is_on_floor(),"speed":car.speed_mps,"slip":absf(car.slip_angle),"drift":car.drift_amount,"grip":car.grip_blend}

func evaluate_slide(data: Dictionary) -> float:
	if not data["driving"] or not data["grounded"] or data["speed"]<settings["minimum_speed_mps"] or data["slip"]<=settings["slip_threshold_rad"] or data["drift"]<=0.3:return 0.0
	var slip:=clampf(inverse_lerp(settings["slip_threshold_rad"],0.7,float(data["slip"])),0,1)
	var loss:=maxf(slip,clampf(1.0-float(data["grip"]),0,1))
	return clampf((0.12+loss*0.88)*clampf(float(data["speed"])/maxf(1,car.base_speed_cap*0.7),0.15,1),0,1)

func advance(delta: float, supplied: Dictionary={}) -> void:
	var start:=Time.get_ticks_usec()
	clock+=delta
	if car.global_position.distance_to(previous_position)>12 or not car.driving_enabled: clear_effects()
	previous_position=car.global_position
	global_position=car.global_position
	var data:=snapshot() if supplied.is_empty() else supplied
	var gain:=clampf(float(hud.speed_effects.effect_strength),0,1) if is_instance_valid(hud) else 1.0
	var intensity:=evaluate_slide(data)*gain if settings["experimental_enabled"] else 0.0
	if gain<=0:clear_effects()
	slide_seconds=slide_seconds+delta if intensity>0 else 0.0
	slide_intensity=intensity*(0.2+0.8*minf(1,slide_seconds/0.65))
	contacts=wheel_contacts() if intensity>0 else [{},{}]
	if settings["smoke_enabled"]:
		for wheel in range(2):
			if contacts[wheel].is_empty():credits[wheel]=0;continue
			credits[wheel]+=float(settings["smoke_density"])*slide_intensity*delta
			while credits[wheel]>=1:
				credits[wheel]-=1
				if smoke.size()>=int(settings["smoke_max"]):smoke.pop_front()
				smoke.append({"p":Vector3(contacts[wheel]["position"])+Vector3.UP*0.13,"v":Vector3(rng.randf_range(-.35,.35),rng.randf_range(.5,1.2),rng.randf_range(-.35,.35)),"born":clock,"life":float(settings["smoke_lifetime_s"])*rng.randf_range(.8,1.1),"size":float(settings["smoke_size_m"])*rng.randf_range(.75,1.15),"angle":rng.randf()})
				total_emitted+=1
	var alive: Array=[]
	for puff in smoke:
		var age: float=(clock-puff["born"])/puff["life"]
		if age>=1:continue
		puff["p"]+=puff["v"]*delta
		var i:=alive.size()
		smoke_batch.multimesh.set_instance_transform(i,Transform3D(Basis.IDENTITY,puff["p"]-global_position))
		smoke_batch.multimesh.set_instance_custom_data(i,Color(age,puff["angle"],puff["size"],0.78))
		alive.append(puff)
	smoke=alive
	smoke_batch.multimesh.visible_instance_count=smoke.size()
	update_marks(intensity)
	update_burst(delta)
	last_update_us=Time.get_ticks_usec()-start

func road_probe(at: Vector3) -> Dictionary:
	ray_queries+=1
	var query:=PhysicsRayQueryParameters3D.create(at+Vector3.UP*0.45,at-Vector3.UP*0.45,1)
	return get_world_3d().direct_space_state.intersect_ray(query)

func append_mark(start: Dictionary, finish: Dictionary) -> bool:
	var a: Vector3=start["position"];var b: Vector3=finish["position"]
	var delta:=b-a;var length:=delta.length()
	if length<0.05 or length>3.0 or Vector3(start["normal"]).dot(finish["normal"])<0.985:return false
	var normal: Vector3=(Vector3(start["normal"])+Vector3(finish["normal"])).normalized()
	var direction: Vector3=delta.slide(normal).normalized()
	var side:=normal.cross(direction).normalized()
	var width: float=float(settings["marks_width_m"])*car.vehicle_scale
	# Edges and midpoint must still be supported by asphalt. Do not bridge an
	# intersection gap, curb, ramp discontinuity or open terrain with a ribbon.
	for p in [a-side*width*.5,a+side*width*.5,b-side*width*.5,b+side*width*.5,(a+b)*.5]:
		var hit:=road_probe(p)
		if hit.is_empty() or Vector3(hit["normal"]).dot(normal)<0.985 or Vector3(hit["position"]).distance_to(p)>.045:return false
	marks.append({"p":(a+b)*.5+normal*.025,"basis":Basis(side*width,normal,direction*(length+.012)),"born":clock,"strength":clampf(.35+slide_intensity*.65,0,1),"seed":rng.randf()})
	if marks.size()>int(settings["marks_max"]):marks.pop_front()
	marks_dirty=true
	return true

func update_marks(intensity: float) -> void:
	if not settings["experimental_enabled"] or not settings["marks_enabled"] or intensity<=0:
		previous_contacts=[{},{}]
	else:
		for i in range(2):
			var hit: Dictionary=contacts[i]
			if hit.is_empty():previous_contacts[i]={};continue
			var prior: Dictionary=previous_contacts[i]
			if not prior.is_empty():
				if Vector3(prior["position"]).distance_to(hit["position"])<settings["marks_spacing_m"]:continue
				append_mark(prior,hit)
			previous_contacts[i]=hit.duplicate()
	var kept: Array=[]
	for mark in marks:
		if clock-float(mark["born"])<float(settings["marks_lifetime_s"]) and Vector3(mark["p"]).distance_to(car.global_position)<float(settings["marks_radius_m"]):kept.append(mark)
	if kept.size()!=marks.size():marks_dirty=true
	marks=kept
	if marks_dirty:
		# Re-anchor the bounded local batch without changing retained world points.
		mark_origin=car.global_position;mark_batch.global_position=mark_origin
		for i in range(marks.size()):
			var mark: Dictionary=marks[i]
			mark_batch.multimesh.set_instance_transform(i,Transform3D(mark["basis"],mark["p"]-mark_origin))
			mark_batch.multimesh.set_instance_custom_data(i,Color(fposmod(mark["born"],64),mark["strength"],mark["seed"],0))
		mark_batch.multimesh.visible_instance_count=marks.size()
		marks_dirty=false
	mark_material.set_shader_parameter("clock_mod",fposmod(clock,64))
	mark_material.set_shader_parameter("lifetime_s",settings["marks_lifetime_s"])

func bind_world_effects(interface: CanvasLayer, turbo_ribbons: Node3D=null) -> void:
	hud=interface
	legacy_turbo_trail=turbo_ribbons
	refresh_body_bindings();sync_legacy()

func refresh_body_bindings() -> void:
	for binding in body_bindings:
		if is_instance_valid(binding["node"]):binding["node"].material_overlay=binding["original"]
	body_bindings.clear()
	for node in car.visual_root.find_children("*","MeshInstance3D",true,false):
		if not node.is_visible_in_tree():continue
		var mat: Material=node.material_override
		if mat!=null and mat.get_meta("sf4_body",false):body_bindings.append({"node":node,"original":node.material_overlay})

func update_burst(delta: float) -> void:
	bind_timer+=delta
	if bind_timer>.5:bind_timer=0;refresh_body_bindings()
	var enabled: bool=settings["experimental_enabled"] and settings["burst_enabled"]
	var active: bool=car.driving_enabled and car.abilities.burst_state==2
	real_burst_ratio=clampf(car.abilities.burst_bonus/maxf(.001,float(car.config["burst_max_bonus"])),0,1) if active else 0.0
	var goal:=preview_burst if preview_enabled else real_burst_ratio
	var gain:=clampf(float(hud.speed_effects.effect_strength),0,1) if is_instance_valid(hud) else 1.0
	if not enabled or not car.driving_enabled or gain<=0:goal=0;burst_value=0
	if goal>burst_value:burst_value=lerpf(burst_value,goal,1-exp(-float(settings["burst_attack_per_s"])*delta))
	else:burst_value=move_toward(burst_value,goal,delta/float(settings["burst_release_s"]))
	var turbo: bool=enabled and car.driving_enabled and car.turbo_active
	if turbo and not turbo_was_active:turbo_flash=1.0
	turbo_was_active=turbo
	turbo_flash=move_toward(turbo_flash,0,delta/.18) if enabled else 0.0
	burst_material.set_shader_parameter("progress",burst_value)
	burst_material.set_shader_parameter("strength",float(settings["burst_strength"])*gain)
	burst_material.set_shader_parameter("clock",fposmod(clock,64))
	burst_material.set_shader_parameter("turbo_flash",turbo_flash)
	for binding in body_bindings:
		if is_instance_valid(binding["node"]):binding["node"].material_overlay=burst_material if enabled and gain>0 and (burst_value>.001 or turbo_flash>.001) else binding["original"]
	if is_instance_valid(hud):hud.speed_effects.sf4_burst_progress=burst_value if enabled else -1.0
	if is_instance_valid(legacy_turbo_trail):legacy_turbo_trail.sf4_energy_active=enabled and burst_value>.3 and gain>0
	var life:=lerpf(.18,.55,burst_value)
	if enabled and gain>0 and (active or preview_enabled) and burst_value>.30:
		energy_history.append({"born":clock,"left":car.visual_root.to_global(Vector3(-.88,.12,1.8)),"right":car.visual_root.to_global(Vector3(.88,.12,1.8)),"side":car.global_basis.x})
	while not energy_history.is_empty() and (clock-float(energy_history[0]["born"])>life or energy_history.size()>40):energy_history.pop_front()
	energy_mesh.clear_surfaces()
	if energy_history.size()<2:return
	energy_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(1,energy_history.size()):
		var a: Dictionary=energy_history[i-1];var b: Dictionary=energy_history[i]
		var fade_a:=maxf(0,1-(clock-a["born"])/life);var fade_b:=maxf(0,1-(clock-b["born"])/life)
		for key in ["left","right"]:
			var width: float=lerpf(.018,.11,burst_value)*car.vehicle_scale
			var sa: Vector3=a["side"]*width;var sb: Vector3=b["side"]*width
			var color:=Color("ff239f") if key=="left" else Color("38dcff")
			for item in [[a[key]-sa,fade_a],[a[key]+sa,fade_a],[b[key]+sb,fade_b],[a[key]-sa,fade_a],[b[key]+sb,fade_b],[b[key]-sb,fade_b]]:
				energy_mesh.surface_set_color(Color(color,float(item[1])*burst_value*gain*.62))
				energy_mesh.surface_add_vertex(Vector3(item[0])-global_position)
	energy_mesh.surface_end()

func save_trial() -> bool:
	var file:=ConfigFile.new();file.set_value("sf4","settings",settings)
	return file.save(settings_path)==OK

func load_trial() -> bool:
	var file:=ConfigFile.new()
	if file.load(settings_path)!=OK:return false
	var data=file.get_value("sf4","settings",{})
	if not data is Dictionary or data.get("schema_version")!=1:return false
	for key in data:
		if key!="schema_version":set_setting(key,data[key])
	return true

func _exit_tree() -> void:
	for binding in body_bindings:
		if is_instance_valid(binding["node"]):binding["node"].material_overlay=binding["original"]
	if is_instance_valid(car) and is_instance_valid(car.drift_particles):car.drift_particles.set_physics_process(true)
	if is_instance_valid(hud):
		if is_instance_valid(hud.speed_effects):hud.speed_effects.sf4_burst_progress=-1.0
		if is_instance_valid(hud.ground_flames):hud.ground_flames.set_physics_process(true)
	if is_instance_valid(legacy_turbo_trail):legacy_turbo_trail.sf4_energy_active=false

func _physics_process(delta: float) -> void: advance(delta)

func diagnostic() -> String:
	return "%s · humo %d/%d · marcas %d/%d\nDerrape %.0f%% · BURST real %.0f%% / visual %.0f%%\n%s · CPU %d µs"%["B · SF.4" if settings["experimental_enabled"] else "A · Original",smoke.size(),settings["smoke_max"],marks.size(),settings["marks_max"],slide_intensity*100,real_burst_ratio*100,burst_value*100,"PREVISUALIZACIÓN" if preview_enabled else "Telemetría real",last_update_us]

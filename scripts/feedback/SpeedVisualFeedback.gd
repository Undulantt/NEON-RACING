extends Node
# Common visual envelope + optional environment adapter. Never writes car physics.
signal settings_changed
const PATH := "res://config/sf3_environment_experimental.json"
const RANGES := {
	"base_visibility":[0.0,0.4],"intensity":[0.0,1.4],"asphalt_strength":[0.0,1.0],"markings_strength":[0.0,1.0],
	"edges_strength":[0.0,1.0],"lamps_strength":[0.0,1.0],"start_kmh":[30.0,140.0],
	"full_speed_ratio":[0.6,1.3],"normal_response_per_s":[2.0,15.0],
	"turbo_response_per_s":[3.0,20.0],"burst_response_per_s":[1.0,12.0],
	"release_per_s":[2.0,15.0],"turbo_contribution":[0.0,0.5],"burst_contribution":[0.0,0.7],
	"radius_m":[35.0,120.0],"reference_spacing_m":[3.0,10.0],"reflection_stretch":[1.0,4.0]
}
var feedback: Node
var settings := {}
var settings_path := "user://sf3_environment.cfg"
var status := "SF.3 · Completo"
var visual_state := {}
var speed_intensity := 0.0
var turbo_intensity := 0.0
var burst_intensity := 0.0
var visual_gain := 0.0
var preview_enabled := false
var samples_received := 0
var last_speed_kmh := 0.0
var world: Node3D
var road_material: ShaderMaterial
var furniture: RefCounted
var paint_materials := {}
var lamp_material: ShaderMaterial
var bindings := {}
var registration_timer := 0.0
var direction := Vector2(0,-1)
var last_update_us := 0
var last_registration_us := 0

static func defaults() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(PATH))

func configure(source: Node) -> void:
	feedback=source
	settings=defaults()
	if FileAccess.file_exists(settings_path): load_trial()
	if "--sf3-original" in OS.get_cmdline_user_args(): set_mode("original")
	if "--sf3-partial" in OS.get_cmdline_user_args(): set_mode("partial")
	if "--sf3-full" in OS.get_cmdline_user_args(): set_mode("full")
	feedback.telemetry_updated.connect(sample)
	feedback.car.recovered.connect(func(_reason): reset_history())
	feedback.car.vehicle_profile_changed.connect(func(_id): reset_history())

func reset_history() -> void:
	speed_intensity=0;turbo_intensity=0;burst_intensity=0;visual_gain=0
	registration_timer=0

func set_setting(key: String, value: Variant) -> bool:
	if not settings.has(key) or key=="schema_version": return false
	if settings[key] is bool:
		if not value is bool: return false
		settings[key]=value
	elif RANGES.has(key):
		if not (value is float or value is int) or not is_finite(float(value)): return false
		settings[key]=clampf(float(value),RANGES[key][0],RANGES[key][1])
	else: return false
	registration_timer=0
	settings_changed.emit()
	return true

func mode() -> String:
	if not settings["enabled"]: return "original"
	return "full" if settings["asphalt_enabled"] and settings["markings_enabled"] and settings["edges_enabled"] and settings["lamps_enabled"] else "partial"

func set_mode(value: String) -> void:
	if value not in ["original","partial","full"]: return
	settings["enabled"]=value!="original"
	if value!="original":
		settings["asphalt_enabled"]=true;settings["markings_enabled"]=true
		settings["edges_enabled"]=value=="full";settings["lamps_enabled"]=value=="full"
	status="SF.3 · "+{"original":"Original","partial":"Parcial","full":"Completo"}[value]
	registration_timer=0
	settings_changed.emit()

func reset_experiment() -> void:
	preview_enabled=false
	settings=defaults();status="Valores SF.3 restaurados."
	registration_timer=0
	settings_changed.emit()

func save_trial() -> bool:
	var file:=ConfigFile.new()
	file.set_value("sf3","settings",settings)
	var error:=file.save(settings_path)
	status="SF.3 guardado en user://sf3_environment.cfg" if error==OK else "No se pudo guardar SF.3."
	settings_changed.emit()
	return error==OK

func load_trial() -> bool:
	var file:=ConfigFile.new()
	var error:=file.load(settings_path)
	var value: Variant=file.get_value("sf3","settings",{}) if error==OK else {}
	if not value is Dictionary or value.get("schema_version")!=1:
		status="No hay configuración SF.3 compatible."
		settings_changed.emit()
		return false
	for key in value:
		if key!="schema_version": set_setting(key,value[key])
	status="Configuración SF.3 cargada."
	settings_changed.emit()
	return true

func sample(t: Dictionary) -> void:
	var delta: float=t.get("delta",feedback.get_physics_process_delta_time())
	advance(t,delta)

func advance(t: Dictionary, delta: float) -> void:
	if delta<=0: return
	samples_received+=1
	last_speed_kmh=float(t["speed_mps"])*3.6
	var eligible: bool=feedback.car.driving_enabled
	var cap:=maxf(1,float(t["normal_cap_mps"]))
	var ratio:=maxf(0,float(t["speed_mps"])/cap)
	var finish:=cap*float(settings["full_speed_ratio"])
	var start:=minf(float(settings["start_kmh"])/3.6,finish-0.5)
	var target:=smoothstep(start,finish,float(t["speed_mps"])) if eligible else 0.0
	speed_intensity=lerpf(speed_intensity,target,1-exp(-float(settings["normal_response_per_s"])*delta))
	var turbo: bool=t["turbo_active"] and eligible
	var burst: bool=t["burst_state"]==2 and eligible
	var progress:=clampf(float(t["burst_progress"]),0,1) if burst else 0.0
	turbo_intensity=lerpf(turbo_intensity,1.0 if turbo else 0.0,1-exp(-float(settings["turbo_response_per_s"] if turbo else settings["release_per_s"])*delta))
	var burst_target:=0.06+0.94*smoothstep(0,1,progress) if burst else 0.0
	burst_intensity=lerpf(burst_intensity,burst_target,1-exp(-float(settings["burst_response_per_s"] if burst else settings["release_per_s"])*delta))
	var combined:=clampf(speed_intensity*0.45+maxf(turbo_intensity*float(settings["turbo_contribution"]),burst_intensity*float(settings["burst_contribution"])),0,1)
	# Common state stays available in Original mode and without a bound city (SF.4).
	visual_state={"speed_ratio":ratio,"speed_intensity":speed_intensity,"turbo_active":turbo,"turbo_intensity":turbo_intensity,"burst_active":burst,"burst_ratio":progress,"burst_intensity":burst_intensity,"combined_intensity":combined}
	feedback.visual_state=visual_state
	feedback.visual_state_updated.emit(visual_state)
	var visible:=lerpf(float(settings["base_visibility"]),1.0,combined)
	var goal:=visible*float(settings["intensity"]) if settings["enabled"] and eligible else 0.0
	visual_gain=lerpf(visual_gain,goal,1-exp(-float(settings["release_per_s"])*delta))
	if visual_gain<0.001 and goal==0: visual_gain=0

func bind_world(target: Node3D, material: ShaderMaterial, fixtures: RefCounted) -> void:
	world=target;road_material=material;furniture=fixtures
	if lamp_material==null:
		lamp_material=ShaderMaterial.new()
		lamp_material.shader=preload("res://shaders/sf3_reference.gdshader")
		lamp_material.set_shader_parameter("lamp",true)
	registration_timer=0

func set_preview(value: bool) -> void:
	preview_enabled=value
	status="VISTA PREVIA: fuerza visual máxima, sin simular velocidad/BURST." if value else "Respuesta real del vehículo."
	settings_changed.emit()

func applied_gain() -> float:
	if not settings["enabled"] or not feedback.car.driving_enabled: return visual_gain if not preview_enabled else 0.0
	return float(settings["intensity"]) if preview_enabled else visual_gain

func diagnostic() -> String:
	if not is_instance_valid(world) or road_material==null: return "SIN ADAPTADOR nocturno."
	if samples_received==0: return "SIN DATOS del vehículo."
	if not settings["enabled"]: return "Original · mejoras apagadas."
	if float(settings["intensity"])==0: return "Intensidad=0 · restablecer SF.3."
	var active_layers:=0
	for pair in [["asphalt_enabled","asphalt_strength"],["markings_enabled","markings_strength"],["edges_enabled","edges_strength"],["lamps_enabled","lamps_strength"]]:
		if settings[pair[0]] and float(settings[pair[1]])>0: active_layers+=1
	if active_layers==0: return "Sin capas activas · restablecer SF.3."
	if preview_enabled: return "VISTA PREVIA · solo materiales."
	return "Base visible · crece al acelerar."

func try_bind_world() -> void:
	var parent: Node3D=feedback.car.get_parent() as Node3D
	if parent==null: return
	var roads=parent.get_node_or_null("RoadChunks")
	if roads==null: return
	var material: Material=roads.visual_material
	if material is ShaderMaterial and material.shader!=null and material.shader.resource_path=="res://shaders/retro_road.gdshader":
		var fixtures: RefCounted=null
		if furniture!=null and is_instance_valid(furniture.world) and furniture.world==parent: fixtures=furniture
		bind_world(parent,material,fixtures)

func _process(delta: float) -> void:
	if not is_instance_valid(world) or road_material==null: try_bind_world()
	if not is_instance_valid(world) or road_material==null: return
	var started:=Time.get_ticks_usec()
	var car: CharacterBody3D=feedback.car
	var velocity:=Vector2(car.velocity.x,car.velocity.z)
	var heading:=Vector2(-car.global_basis.z.x,-car.global_basis.z.z)
	var goal_direction:=velocity.normalized() if velocity.length()>2 else heading
	direction=direction.lerp(goal_direction,1-exp(-6*delta))
	direction=direction.normalized() if direction.length_squared()>0.001 else goal_direction
	var gain:=applied_gain()
	var anchor: Vector3=car.global_position
	var asphalt:=gain*float(settings["asphalt_strength"]) if settings["asphalt_enabled"] else 0.0
	var lamps:=gain*float(settings["lamps_strength"]) if settings["lamps_enabled"] else 0.0
	road_material.set_shader_parameter("sf3_anchor",anchor)
	road_material.set_shader_parameter("sf3_radius",settings["radius_m"])
	road_material.set_shader_parameter("sf3_direction",direction)
	road_material.set_shader_parameter("sf3_asphalt",asphalt)
	road_material.set_shader_parameter("sf3_lamps",lamps)
	road_material.set_shader_parameter("sf3_stretch",settings["reflection_stretch"])
	registration_timer-=delta
	if gain==0:
		if not bindings.is_empty(): restore_bindings()
	elif registration_timer<=0:
		register_nearby()
		registration_timer=0.5
	if gain>0:
		for mat in paint_materials.values(): update_reference(mat,anchor)
		update_reference(lamp_material,anchor)
	last_update_us=Time.get_ticks_usec()-started

func update_reference(mat: ShaderMaterial, anchor: Vector3) -> void:
	mat.set_shader_parameter("anchor",anchor)
	mat.set_shader_parameter("radius_m",settings["radius_m"])
	mat.set_shader_parameter("spacing_m",settings["reference_spacing_m"])
	mat.set_shader_parameter("paint_gain",applied_gain()*float(settings["markings_strength"]) if settings["markings_enabled"] else 0.0)
	mat.set_shader_parameter("edge_gain",applied_gain()*float(settings["edges_strength"]) if settings["edges_enabled"] else 0.0)
	mat.set_shader_parameter("lamp_gain",applied_gain()*float(settings["lamps_strength"]) if settings["lamps_enabled"] else 0.0)

func reference_material(source: Material) -> ShaderMaterial:
	var color: Color=source.albedo_color if source is StandardMaterial3D else Color.WHITE
	var id: String=color.to_html()
	if not paint_materials.has(id):
		var mat:=ShaderMaterial.new()
		mat.shader=preload("res://shaders/sf3_reference.gdshader")
		mat.set_shader_parameter("base_color",color)
		mat.set_shader_parameter("edge",color.g>color.r*1.8)
		paint_materials[id]=mat
	return paint_materials[id]

func register_mesh(visual: GeometryInstance3D, lamp: bool) -> void:
	var id:=visual.get_instance_id()
	if bindings.has(id): return
	if bindings.size()>=96: return
	var saved:={"node":weakref(visual),"override":visual.material_override,"surfaces":[]}
	if lamp: visual.material_override=lamp_material
	else:
		for surface in range(visual.mesh.get_surface_count()):
			var original: Material=visual.get_surface_override_material(surface)
			saved["surfaces"].append(original)
			var source: Material=visual.material_override if visual.material_override!=null else original if original!=null else visual.mesh.surface_get_material(surface)
			visual.set_surface_override_material(surface,reference_material(source))
		visual.material_override=null
	bindings[id]=saved

func restore_one(saved: Dictionary) -> void:
	var visual=saved["node"].get_ref()
	if not is_instance_valid(visual): return
	visual.material_override=saved["override"]
	for i in range(saved["surfaces"].size()): visual.set_surface_override_material(i,saved["surfaces"][i])

func restore_bindings() -> void:
	for saved in bindings.values(): restore_one(saved)
	bindings.clear()

func register_nearby() -> void:
	var started:=Time.get_ticks_usec()
	var wanted:={}
	var at:=Vector2(feedback.car.position.x,feedback.car.position.z)
	for cell in world.road_root.loaded:
		if not settings["markings_enabled"] and not settings["edges_enabled"]: break
		var bounds:=Rect2(Vector2(cell)*256,Vector2(256,256))
		if at.distance_to(at.clamp(bounds.position,bounds.end))>float(settings["radius_m"]): continue
		for visual in world.road_root.loaded[cell].find_children("RoadEdgeNeon","MeshInstance3D",true,false):
			wanted[visual.get_instance_id()]=true
			register_mesh(visual,false)
	if furniture!=null and settings["lamps_enabled"]:
		for sector_id in furniture.sectors:
			var entry: Dictionary=furniture.sectors[sector_id]
			var owner=entry["owner"].get_ref()
			if not is_instance_valid(owner): continue
			var visual=owner.get_node_or_null("LampBatch")
			if visual==null: continue
			# Sector ownership is stable; fragment radius bounds the actual response.
			var parts:=str(sector_id).split("_")
			var cell:=Vector2(int(parts[0]),int(parts[1]))*256
			if at.distance_to(at.clamp(cell,cell+Vector2(256,256)))>float(settings["radius_m"])+256: continue
			wanted[visual.get_instance_id()]=true
			register_mesh(visual,true)
	for id in bindings.keys():
		if not wanted.has(id) or not is_instance_valid(bindings[id]["node"].get_ref()):
			restore_one(bindings[id]);bindings.erase(id)
	last_registration_us=Time.get_ticks_usec()-started

func _exit_tree() -> void:
	restore_bindings()
	if is_instance_valid(road_material):
		road_material.set_shader_parameter("sf3_asphalt",0.0)
		road_material.set_shader_parameter("sf3_lamps",0.0)

extends Node3D
# Bounded world-space ribbons, independent of car mesh/model and physics.
const MAX_SAMPLES := 24
const LIFETIME := 0.20
var car: CharacterBody3D
var screen_effects: Control
var hud: CanvasLayer
var history: Array = []
var mesh := ImmediateMesh.new()
var clock := 0.0
var last_position := Vector3.ZERO
var initialized := false
var effect_mode := 0
var strength := 1.0
var flame_length := 0.0
var visual: MeshInstance3D
var sf4_energy_active:=false

func attach(target: CharacterBody3D, screen: Control, interface: CanvasLayer) -> void:
	car=target;screen_effects=screen;hud=interface
	process_physics_priority=100
	visual=MeshInstance3D.new()
	visual.mesh=mesh
	visual.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := StandardMaterial3D.new()
	material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode=BaseMaterial3D.BLEND_MODE_ADD
	material.vertex_color_use_as_albedo=true
	material.cull_mode=BaseMaterial3D.CULL_DISABLED
	material.no_depth_test=false
	visual.material_override=material
	add_child(visual)
	car.recovered.connect(func(_reason: String): clear_trail())
	var flame := exhaust_mesh()
	for emitter in car.visuals["exhaust"]:
		emitter.mesh=flame
		emitter.material_override=material

func exhaust_mesh() -> ArrayMesh:
	var vertices := PackedVector3Array()
	var colors := PackedColorArray()
	for ring in range(2):
		var z0 := float(ring)*0.65
		var z1 := float(ring+1)*0.65
		var r0 := 0.12 if ring==0 else 0.085
		var r1 := 0.085 if ring==0 else 0.005
		for i in range(8):
			var a := TAU*float(i)/8
			var b := TAU*float(i+1)/8
			var p := Vector3(cos(a)*r0,sin(a)*r0,z0-0.25)
			var q := Vector3(cos(b)*r0,sin(b)*r0,z0-0.25)
			var r := Vector3(cos(b)*r1,sin(b)*r1,z1-0.25)
			var s := Vector3(cos(a)*r1,sin(a)*r1,z1-0.25)
			vertices.append_array(PackedVector3Array([p,q,r,p,r,s]))
			var near := Color(0.65,0.95,1,0.75) if ring==0 else Color(0.2,0.7,1,0.45)
			var far := Color(0.2,0.7,1,0.45) if ring==0 else Color(0.65,0.2,1,0)
			colors.append_array(PackedColorArray([near,near,far,near,far,far]))
	var arrays := [];arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=vertices;arrays[Mesh.ARRAY_COLOR]=colors
	var resource := ArrayMesh.new();resource.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	return resource

func clear_trail() -> void:
	history.clear();mesh.clear_surfaces();initialized=false;flame_length=0
	if screen_effects != null:
		screen_effects.intensity=0
		screen_effects.queue_redraw()

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode==KEY_F4:
		effect_mode=(effect_mode+1)%3
		strength=[1.0,0.4,0.0][effect_mode]
		screen_effects.effect_strength=strength
		if strength==0:
			clear_trail()
		hud.show_notice("Efectos: "+["completos","sutiles","desactivados"][effect_mode])
		get_viewport().set_input_as_handled()

func _physics_process(delta: float) -> void:
	clock+=delta
	if initialized and car.global_position.distance_to(last_position)>12:
		clear_trail()
	last_position=car.global_position;initialized=true
	var active: bool = car.driving_enabled and car.speed_mps>8 and (car.turbo_active or car.drift_boost_active) and strength>0
	if not car.driving_enabled:
		clear_trail()
	var desired := (1.0 if car.turbo_active else 0.55) if active else 0.0
	flame_length=lerpf(flame_length,desired,1-exp(-12*delta))
	for emitter in car.visuals["exhaust"]:
		emitter.visible=car.driving_enabled and flame_length>0.02 and strength>0
		emitter.scale.z=flame_length*(0.96+sin(clock*TAU*3)*0.04)
	if active and not sf4_energy_active:
		var left: Vector3=car.visual_root.to_global(Vector3(-0.62,-0.15,2.4))
		var right: Vector3=car.visual_root.to_global(Vector3(0.62,-0.15,2.4))
		history.append({"time":clock,"left":left,"right":right,"side":car.global_basis.x,"drift":car.drift_boost_active and not car.turbo_active})
	while history.size()>MAX_SAMPLES or (not history.is_empty() and clock-history[0]["time"]>LIFETIME):
		history.pop_front()
	redraw()

func vertex(p: Vector3, color: Color) -> void:
	mesh.surface_set_color(color);mesh.surface_add_vertex(to_local(p))
func redraw() -> void:
	mesh.clear_surfaces()
	if history.size()<2:
		return
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(1,history.size()):
		var a: Dictionary=history[i-1];var b: Dictionary=history[i]
		var age_a := clampf((clock-float(a["time"]))/LIFETIME,0,1)
		var age_b := clampf((clock-float(b["time"]))/LIFETIME,0,1)
		for key in ["left","right"]:
			for layer in range(2):
				var width := (0.14 if layer==0 else 0.035)*strength
				var ca := Color("779fff").lerp(Color("49eaff"),1-age_a)
				var cb := Color("779fff").lerp(Color("49eaff"),1-age_b)
				if b["drift"]:
					ca=ca.lerp(Color("d58aff"),0.55);cb=cb.lerp(Color("d58aff"),0.55)
				ca.a=pow(1-age_a,1.7)*(0.16 if layer==0 else 0.55)*strength
				cb.a=pow(1-age_b,1.7)*(0.16 if layer==0 else 0.55)*strength
				var wa: Vector3=a["side"]*width*(1-age_a*0.85)
				var wb: Vector3=b["side"]*width*(1-age_b*0.85)
				vertex(a[key]-wa,ca);vertex(a[key]+wa,ca);vertex(b[key]+wb,cb)
				vertex(a[key]-wa,ca);vertex(b[key]+wb,cb);vertex(b[key]-wb,cb)
	mesh.surface_end()

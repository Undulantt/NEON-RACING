extends Node3D

var car: CharacterBody3D
var smoke: Array[CPUParticles3D] = []

func attach(target: CharacterBody3D) -> void:
	car = target
	# A procedural soft disc keeps smoke readable without external textures.
	var disc := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	for y in range(32):
		for x in range(32):
			var radius := Vector2(x - 15.5, y - 15.5).length() / 15.5
			disc.set_pixel(x, y, Color(1, 1, 1, pow(maxf(0.0, 1.0 - radius), 1.7)))
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.vertex_color_use_as_albedo = true
	material.albedo_texture = ImageTexture.create_from_image(disc)
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mesh := QuadMesh.new()
	mesh.size = Vector2(1.6, 1.6)
	mesh.material = material
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.12, 0.65, 1.0])
	fade.colors = PackedColorArray([Color(0.75, 0.77, 0.8, 0), Color(0.75, 0.77, 0.8, 0.85), Color(0.65, 0.68, 0.72, 0.45), Color(0.6, 0.63, 0.67, 0)])
	for x in [-0.9, 0.9]:
		var emitter := CPUParticles3D.new()
		emitter.position = Vector3(x, -0.43, 1.3)
		emitter.amount = 48
		emitter.lifetime = 0.85
		emitter.local_coords = false
		emitter.mesh = mesh
		emitter.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		emitter.color_ramp = fade
		emitter.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		emitter.emission_sphere_radius = 0.12
		emitter.direction = Vector3(0, 0.45, 1)
		emitter.spread = 45
		emitter.gravity = Vector3(0, 0.65, 0)
		emitter.initial_velocity_min = 0.4
		emitter.initial_velocity_max = 1.8
		emitter.scale_amount_min = 0.4
		emitter.scale_amount_max = 0.9
		emitter.scale_amount_curve = growth_curve()
		emitter.emitting = false
		add_child(emitter)
		smoke.append(emitter)

func growth_curve() -> Curve:
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.3))
	curve.add_point(Vector2(1, 1))
	return curve

func _physics_process(_delta: float) -> void:
	var active: bool = car.driving_enabled and car.on_asphalt and car.is_on_floor() and car.drift_amount > 0.3
	for emitter in smoke:
		emitter.emitting = active
		emitter.initial_velocity_max = 1.2 + car.drift_amount * 1.7

func clear_trail() -> void:
	for emitter in smoke:
		emitter.restart()
		emitter.emitting = false

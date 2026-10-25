extends Node3D

var car: CharacterBody3D
var arm: SpringArm3D
var camera: Camera3D
var initialized := false

func _ready() -> void:
	arm = SpringArm3D.new()
	arm.spring_length = 7.5
	arm.margin = 0.3
	arm.collision_mask = 15
	var shape := SphereShape3D.new()
	shape.radius = 0.25
	arm.shape = shape
	arm.rotation.x = deg_to_rad(-14)
	add_child(arm)
	camera = Camera3D.new()
	camera.fov = 70
	camera.near = 0.15
	camera.far = 4000
	arm.add_child(camera)
	camera.current = true

func attach(target: CharacterBody3D) -> void:
	car = target
	arm.add_excluded_object(car.get_rid())
	arm.spring_length = float(car.config["camera_distance_m"])
	car.recovered.connect(_on_recovered)
	snap()

func snap() -> void:
	if car == null:
		return
	global_position = car.global_position + Vector3.UP * 1.25
	rotation.y = car.rotation.y
	initialized = true

func _on_recovered(_reason: String) -> void:
	snap()

func _physics_process(delta: float) -> void:
	if car == null:
		return
	# Position follows exactly to prevent lagging into geometry; heading is smoothed.
	global_position = car.global_position + Vector3.UP * 1.25
	rotation.y = lerp_angle(rotation.y, car.rotation.y, 1.0 - exp(-7.0 * delta))
	camera.fov = lerpf(camera.fov, 70.0 + minf(car.speed_mps / 32.0, 1.0) * 7.0, 3.0 * delta)

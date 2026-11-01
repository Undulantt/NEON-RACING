extends "res://scripts/world/World.gd"

@export var night_enabled := true
var night_style: Node3D
var night_config: Dictionary

func _ready() -> void:
	super._ready()
	if not runtime_error.is_empty():
		return
	night_config = JSON.parse_string(FileAccess.get_file_as_string("res://config/night_pilot.json"))
	var p: Array = night_config["spawn_xz"]
	var yaw := float(night_config["heading_radians"])
	player.position = Vector3(p[0], player.supported_pose_height(p[0],p[1],yaw), p[1])
	player.rotation.y = yaw
	player.spawn_transform = player.global_transform
	player.safe_transform = player.global_transform
	player.reset_surface_motion()
	follow_camera.snap()
	if night_enabled:
		night_style = preload("res://scripts/style/NightStyle.gd").new()
		add_child(night_style)
		night_style.configure(self, night_config)

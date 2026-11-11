extends "res://scripts/world/World.gd"
var night_style: Node3D
var night_config: Dictionary
func _ready() -> void:
	night_visuals=not "--day-world" in OS.get_cmdline_user_args()
	await super._ready()
	if not runtime_error.is_empty() or city_manager==null or "--day-world" in OS.get_cmdline_user_args(): return
	night_config=JSON.parse_string(FileAccess.get_file_as_string("res://config/night_pilot.json"))
	night_config["citywide"]=true
	await get_tree().physics_frame
	if not is_inside_tree(): return
	await get_tree().physics_frame
	if not is_inside_tree(): return
	night_style=preload("res://scripts/style/NightStyle.gd").new()
	add_child(night_style)
	night_style.configure(self,night_config)

extends RefCounted
# Player-facing subset of the existing SF.3 / SF.4 developer settings.
const DEFAULTS={"optical_mode":"full","clouds_enabled":true,"smoke_enabled":true,"smoke_quality":1,"marks_enabled":true,"burst_enabled":true,"fps_limit":0,"water_effects":true,"enhanced_graphics":true}

static func valid(key: String, value: Variant) -> bool:
	if key=="fps_limit":return value is int and value in [0,30,60,90]
	if key=="optical_mode":return value is String and value in ["original","partial","full"]
	if key=="smoke_quality":return value is int and value>=0 and value<=2
	return key in DEFAULTS and DEFAULTS[key] is bool and value is bool

static func effective_defaults() -> Dictionary:
	var result: Dictionary=DEFAULTS.duplicate()
	var saved:=ConfigFile.new()
	if saved.load("user://sf3_environment.cfg")==OK:
		var data=saved.get_value("sf3","settings",{})
		if data is Dictionary:
			result["optical_mode"]="original" if not data.get("enabled",true) else ("full" if data.get("edges_enabled",true) and data.get("lamps_enabled",true) else "partial")
	if saved.load("user://sf4_vehicle_vfx.cfg")==OK:
		var data=saved.get_value("sf4","settings",{})
		if data is Dictionary:
			for key in ["smoke_enabled","marks_enabled","burst_enabled"]:
				if data.get(key) is bool:result[key]=data[key]
			var density: float=float(data.get("smoke_density",26))
			result["smoke_quality"]=0 if density<19 else (2 if density>33 else 1)
	return result

static func apply_quality(world: Node3D, settings: Dictionary) -> void:
	if world==null or not "night_style" in world or world.night_style==null:return
	var quality=world.get_node_or_null("EnhancedGraphics")
	if quality==null:
		quality=preload("res://scripts/style/EnhancedGraphics.gd").new();quality.name="EnhancedGraphics"
		world.add_child(quality);quality.configure(world)
	quality.set_enabled(bool(settings.get("enhanced_graphics",true)))

static func apply(world: Node3D, settings: Dictionary) -> void:
	Engine.max_fps=int(settings.get("fps_limit",0))
	apply_quality(world,settings)
	if world!=null and world.get("coast_water")!=null:world.coast_water.set_effects(bool(settings.get("water_effects",true)))
	if world==null or world.follow_camera==null:return
	var feedback=world.follow_camera.speed_feedback
	feedback.environment_feedback.set_mode(settings["optical_mode"])
	var fx=feedback.vehicle_feedback
	fx.player_burst_allowed=settings["burst_enabled"]
	fx.set_setting("experimental_enabled",true)
	for key in ["smoke_enabled","marks_enabled","burst_enabled"]:fx.set_setting(key,settings[key])
	var quality: int=settings["smoke_quality"]
	fx.set_setting("smoke_density",[12.0,26.0,40.0][quality])
	fx.set_setting("smoke_max",[32,96,128][quality])
	fx.set_setting("marks_max",[128,512,1024][quality])
	if "night_style" in world and world.night_style!=null and world.night_style.clouds!=null:world.night_style.clouds.set_enabled(settings["clouds_enabled"])

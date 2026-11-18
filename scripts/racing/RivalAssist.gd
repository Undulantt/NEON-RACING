extends RefCounted
# Deliberate arcade advantages, scoped to each production NPC. The shared
# vehicle controller and player profile resources are never edited.
var car: CharacterBody3D
var driver: RefCounted
var base: Dictionary
var settings: Dictionary
var speed_bonus:=0.0
var gap_m:=0.0
var peak_bonus:=0.0

func configure(vehicle: CharacterBody3D, pilot: RefCounted, options: Dictionary, difficulty: String) -> void:
	car=vehicle;driver=pilot;base=car.config.duplicate(true);settings=options.duplicate(true)
	if not bool(settings.get("enabled",false)):return
	if difficulty=="standard":
		settings["catchup_speed_bonus"]=float(settings["catchup_speed_bonus"])*.7
		settings["maximum_speed_bonus"]=float(settings["maximum_speed_bonus"])*.8
	car.config=base.duplicate(true)
	for pair in [["braking_mps2","braking_multiplier"],["lateral_grip_per_second","grip_multiplier"],["steering_response_per_second","steering_response_multiplier"],["steering_sensitivity","steering_sensitivity_multiplier"],["max_yaw_rate_radians","yaw_rate_multiplier"],["burst_growth_per_second","burst_growth_multiplier"],["turbo_recharge_s","turbo_recharge_multiplier"]]:
		car.config[pair[0]]=float(base[pair[0]])*float(settings[pair[1]])
	car.config["burst_arming_time_s"]=minf(float(base["burst_arming_time_s"]),float(settings["burst_arming_time_s"]))
	car.config["burst_arming_speed_ratio"]=minf(float(base["burst_arming_speed_ratio"]),float(settings["burst_arming_speed_ratio"]))
	car.abilities.config=car.config
	driver.arcade=true

func update(delta: float, player_session: RefCounted) -> void:
	if not bool(settings.get("enabled",false)):return
	gap_m=float(player_session.progress_m)-float(driver.session.progress_m)
	var catching:=inverse_lerp(float(settings["catchup_start_m"]),float(settings["catchup_full_m"]),gap_m)
	catching=clampf(catching,0,1) if player_session.phase=="running" and driver.session.phase=="running" else 0.0
	var passing:=float(settings["overtake_speed_bonus"]) if is_instance_valid(driver.passing_car) and driver.session.phase=="running" else 0.0
	var wanted:=minf(float(settings["maximum_speed_bonus"]),catching*float(settings["catchup_speed_bonus"])+passing)
	speed_bonus=move_toward(speed_bonus,wanted,delta*float(settings["transition_per_second"]))
	peak_bonus=maxf(peak_bonus,speed_bonus)
	car.config["max_forward_speed_mps"]=float(base["max_forward_speed_mps"])*(1+speed_bonus)
	car.config["acceleration_mps2"]=float(base["acceleration_mps2"])*(1+float(settings["acceleration_bonus"])*catching+passing)

func restore() -> void:
	car.config=base.duplicate(true);car.abilities.config=car.config
	driver.arcade=false;speed_bonus=0;settings["enabled"]=false

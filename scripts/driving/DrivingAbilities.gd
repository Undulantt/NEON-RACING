extends RefCounted

signal burst_started
signal burst_ended(reason: String)
signal drift_boost_triggered(strength: float)
signal turbo_changed(active: bool, charge: float)

enum BurstState { NORMAL, PREPARATION, BURST, RECOVERY }
var config: Dictionary
var burst_state := BurstState.NORMAL
var arming_time := 0.0
var burst_time := 0.0
var burst_bonus := 0.0
var airborne_time := 0.0
var base_speed_cap := 0.0
var surface_multiplier := 1.0
var turbo_consumed_this_tick := false
var current_speed_cap := 0.0
var last_end_reason := ""
var turbo_charge := 1.0
var turbo_active := false
var turbo_exhausted := false
var turbo_cooldown := 0.0
var drift_charge := 0.0
var drift_quality := 0.0
var drift_tracking := false
var drift_valid_time := 0.0
var drift_exit_time := 0.0
var drift_settle_time := 0.0
var drift_boost_time := 0.0
var drift_boost_strength := 0.0
var drift_boost_active := false
var drift_rewards := 0
var drift_cooldown := 0.0

func configure(settings: Dictionary) -> void:
	config = settings
	reset("profile")

func reset(reason: String) -> void:
	cancel_burst(reason, 0.0)
	base_speed_cap = float(config["max_forward_speed_mps"])
	current_speed_cap = base_speed_cap
	airborne_time = 0.0
	var was_turbo_active := turbo_active
	turbo_active = false
	turbo_consumed_this_tick = false
	turbo_exhausted = false
	if was_turbo_active:
		turbo_changed.emit(false, turbo_charge)
	drift_cooldown = 0.0
	clear_drift()

func cancel_burst(reason: String, forward_speed: float) -> void:
	var was_active := burst_state == BurstState.BURST
	burst_state = BurstState.RECOVERY if forward_speed > base_speed_cap * surface_multiplier + 0.01 else BurstState.NORMAL
	arming_time = 0.0
	burst_time = 0.0
	burst_bonus = 0.0
	current_speed_cap = base_speed_cap * surface_multiplier
	if was_active:
		last_end_reason = reason
		burst_ended.emit(reason)

func tick(delta: float, throttle: float, brake: float, handbrake: bool, turbo_requested: bool, forward_speed: float, grounded: bool, enabled: bool, asphalt: bool, multiplier: float) -> void:
	base_speed_cap = float(config["max_forward_speed_mps"]) * multiplier
	# Terrain keeps C.6's mild penalty, without disabling any ability.
	surface_multiplier = 1.0 if asphalt else float(config["offroad_speed_multiplier"])
	airborne_time = 0.0 if grounded else airborne_time + delta
	var reason := ""
	if not enabled:
		reason = "disabled"
	elif brake > float(config["burst_brake_threshold"]) or handbrake:
		reason = "brake"
	elif throttle < float(config["burst_throttle_threshold"]):
		reason = "throttle"
	elif forward_speed <= 0:
		reason = "reverse_or_stop"
	elif burst_state == BurstState.BURST and forward_speed < base_speed_cap * surface_multiplier * float(config["burst_maintain_speed_ratio"]):
		reason = "speed_loss"
	elif airborne_time > float(config["burst_airborne_cancel_s"]):
		reason = "airborne"
	if not reason.is_empty():
		cancel_burst(reason, forward_speed)
	elif burst_state == BurstState.RECOVERY:
		if forward_speed <= base_speed_cap * surface_multiplier + 0.01:
			burst_state = BurstState.NORMAL
	elif burst_state == BurstState.BURST:
		if grounded:
			burst_time += delta
		burst_bonus = minf(float(config["burst_max_bonus"]), float(config["burst_growth_per_second"]) * burst_time)
	elif grounded and forward_speed >= base_speed_cap * surface_multiplier * float(config["burst_arming_speed_ratio"]):
		burst_state = BurstState.PREPARATION
		arming_time += delta
		if arming_time + 0.000001 >= float(config["burst_arming_time_s"]):
			burst_state = BurstState.BURST
			arming_time = 0.0
			burst_time = 0.0
			burst_started.emit()
	else:
		burst_state = BurstState.NORMAL
		arming_time = 0.0
	current_speed_cap = base_speed_cap * (1.0 + burst_bonus) * surface_multiplier
	var eligible := enabled and grounded and throttle > 0.0 and brake <= 0.0 and forward_speed > 2.0 and not handbrake
	update_turbo(delta, turbo_requested, eligible, enabled)
	# Independent rewards may overlap; all acceleration obeys the same speed cap.
	if not eligible:
		drift_boost_time = 0.0
	drift_boost_time = maxf(0.0, drift_boost_time - delta)
	drift_boost_active = drift_boost_time > 0.0
	drift_cooldown = maxf(0.0, drift_cooldown - delta)

func after_motion(forward_speed: float) -> void:
	# Read collision-modified velocity before the HUD sees this physics step.
	if burst_state == BurstState.BURST and forward_speed < base_speed_cap * surface_multiplier * float(config["burst_maintain_speed_ratio"]):
		cancel_burst("speed_loss", forward_speed)
	elif burst_state == BurstState.PREPARATION and forward_speed < base_speed_cap * surface_multiplier * float(config["burst_arming_speed_ratio"]):
		cancel_burst("speed_loss", forward_speed)

func update_turbo(delta: float, requested: bool, eligible: bool, enabled: bool) -> void:
	turbo_consumed_this_tick = false
	var old_active := turbo_active
	var old_charge := turbo_charge
	if not requested:
		turbo_exhausted = false
	turbo_active = requested and eligible and not turbo_exhausted and (turbo_charge > 0 if old_active else turbo_charge >= float(config["turbo_min_charge"]))
	if turbo_active:
		turbo_consumed_this_tick = true
		turbo_charge = maxf(0, turbo_charge - delta / float(config["turbo_duration_s"]))
		turbo_cooldown = float(config["turbo_recharge_delay_s"])
		if turbo_charge <= 0:
			turbo_exhausted = true
			turbo_active = false
	else:
		turbo_cooldown = maxf(0, turbo_cooldown - delta)
		if turbo_cooldown <= 0 and enabled:
			turbo_charge = minf(1, turbo_charge + delta / float(config["turbo_recharge_s"]))
	if old_active != turbo_active or not is_equal_approx(old_charge, turbo_charge):
		turbo_changed.emit(turbo_active, turbo_charge)

func extra_acceleration() -> float:
	var extra := float(config["turbo_extra_acceleration_mps2"]) if turbo_active else 0.0
	if drift_boost_active:
		extra += float(config["drift_extra_acceleration_mps2"]) * drift_boost_strength
	return extra

func clear_drift() -> void:
	drift_charge = 0.0
	drift_quality = 0.0
	drift_tracking = false
	drift_valid_time = 0.0
	drift_exit_time = 0.0
	drift_settle_time = 0.0
	drift_boost_time = 0.0
	drift_boost_strength = 0.0
	drift_boost_active = false

func update_drift(delta: float, handbrake: bool, hit_wall: bool, enabled: bool, grounded: bool, forward_speed: float, throttle: float, brake: float, slip: float, steering: float) -> void:
	if not enabled or not grounded or forward_speed < float(config["drift_min_speed_mps"]) or brake > 0.0 or hit_wall:
		clear_drift()
		return
	var degrees := absf(rad_to_deg(slip))
	drift_quality = 0.0
	if handbrake and drift_cooldown <= 0:
		drift_exit_time = 0.0
		drift_settle_time = 0.0
		if degrees >= float(config["drift_min_angle_degrees"]) and degrees <= float(config["drift_max_angle_degrees"]) and absf(steering) > 0.12:
			var angle_quality := clampf((degrees - 8.0) / 12.0, 0.35, 1.0)
			var speed_quality := clampf(forward_speed / 25.0, 0.5, 1.0)
			drift_quality = angle_quality * speed_quality
			drift_tracking = true
			drift_valid_time += delta
			drift_charge = minf(1.0, drift_charge + drift_quality * delta / float(config["drift_charge_time_s"]))
		elif drift_tracking:
			drift_charge = maxf(0.0, drift_charge - delta * 0.3)
			# Spinning cannot bank time through an uncontrolled section.
			if degrees > 60:
				clear_drift()
	elif drift_tracking and not handbrake:
		drift_exit_time += delta
		drift_settle_time = drift_settle_time + delta if degrees < 10.0 else 0.0
		if drift_settle_time >= 0.1:
			var earned := drift_charge if drift_charge >= float(config["drift_min_charge"]) and drift_valid_time >= float(config["drift_min_duration_s"]) else 0.0
			clear_drift()
			if earned > 0 and throttle > 0:
				drift_boost_strength = earned
				drift_boost_time = float(config["drift_bonus_duration_s"])
				drift_boost_active = true
				drift_cooldown = float(config["drift_reward_cooldown_s"])
				drift_rewards += 1
				if not turbo_consumed_this_tick:
					turbo_charge = minf(1, turbo_charge + float(config["drift_turbo_recharge"]) * earned)
					turbo_changed.emit(false, turbo_charge)
				drift_boost_triggered.emit(earned)
		elif drift_exit_time > float(config["drift_exit_timeout_s"]):
			clear_drift()

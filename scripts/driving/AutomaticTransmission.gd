extends RefCounted

# Automatic transmission telemetry shared by the HUD and engine audio.
# Ratios map the existing arcade road motion to engine RPM; they do not add force.
signal gear_changed(previous: int, current: int)
var settings: Dictionary
var gear := 0
var rpm := 900.0
var shaft_rpm := 0.0
var load := 0.0
var shift_remaining := 0.0
var shift_cooldown := 0.0
var shift_from_rpm := 900.0
var rev_match_remaining := 0.0
var shift_target_rpm := 900.0
var last_shift_direction := 0
var final_drive := 4.0
var wheel_circumference := 1.7
var upshifts := 0
var downshifts := 0

func configure(profile: Dictionary) -> void:
	settings = JSON.parse_string(FileAccess.get_file_as_string("res://config/powertrain_config.json"))
	wheel_circumference = TAU * float(settings["wheel_radius_m"]) * float(profile["vehicle_scale"])
	var cap: float = float(profile["max_forward_speed_mps"]) * (1.0 + float(profile["burst_max_bonus"]))
	var top_ratio: float = settings["ratios"][-1]
	final_drive = float(settings["top_gear_rpm_at_burst_cap"]) * wheel_circumference / (cap * 60.0 * top_ratio)
	upshifts = 0
	downshifts = 0
	reset()

func reset() -> void:
	gear = 0
	rpm = float(settings["idle_rpm"])
	shaft_rpm = 0.0
	load = 0.0
	shift_remaining = 0.0
	shift_cooldown = 0.0
	shift_from_rpm = rpm
	rev_match_remaining = 0.0
	shift_target_rpm = rpm
	last_shift_direction = 0

func ratio(for_gear: int) -> float:
	if for_gear < 0:
		return float(settings["reverse_ratio"])
	return float(settings["ratios"][clampi(for_gear-1,0,settings["ratios"].size()-1)])

func rpm_for_speed(speed: float, for_gear: int) -> float:
	return absf(speed) * 60.0 / wheel_circumference * final_drive * ratio(for_gear)

func change_gear(next: int, shifting: bool = true) -> void:
	if gear == next:
		return
	var previous := gear
	gear = next
	if shifting and previous > 0 and next > 0:
		shift_from_rpm = rpm
		shift_remaining = float(settings["shift_duration_s"])
		shift_cooldown = float(settings["shift_cooldown_s"])
		last_shift_direction = 1 if next > previous else -1
		rev_match_remaining = float(settings["rev_match_duration_s"]) if next < previous else 0.0
		shift_target_rpm = minf(float(settings["redline_rpm"])-300.0, maxf(rpm*ratio(next)/ratio(previous),rpm+float(settings["downshift_blip_rpm"])))
		if next > previous:
			upshifts += 1
		else:
			downshifts += 1
	else:
		shift_remaining = 0.0
		last_shift_direction = 0
	gear_changed.emit(previous,next)

func update(delta: float, forward_speed: float, throttle: float, brake: float, grounded: bool, enabled: bool) -> void:
	var idle := float(settings["idle_rpm"])
	var redline := float(settings["redline_rpm"])
	shift_cooldown = maxf(0,shift_cooldown-delta)
	shift_remaining = maxf(0,shift_remaining-delta)
	rev_match_remaining = maxf(0,rev_match_remaining-delta)
	load = clampf(-throttle if gear < 0 else throttle,0,1) if enabled else 0.0
	if forward_speed < -0.45:
		change_gear(-1,false)
	elif absf(forward_speed) < 0.45 and throttle <= 0.03:
		change_gear(0,false)
	elif gear <= 0:
		change_gear(1,false)
	if gear > 0 and grounded and shift_cooldown <= 0 and shift_remaining <= 0:
		var mechanical := rpm_for_speed(forward_speed,gear)
		if mechanical >= float(settings["upshift_rpm"]) and gear < settings["ratios"].size():
			change_gear(gear+1)
		elif gear > 1:
			var down_threshold := lerpf(float(settings["downshift_rpm"]),float(settings["loaded_downshift_rpm"]),load)
			down_threshold += brake * 250.0
			if mechanical < down_threshold and rpm_for_speed(forward_speed,gear-1) < float(settings["upshift_rpm"]) - 650.0:
				change_gear(gear-1)
	shaft_rpm = rpm_for_speed(forward_speed,gear) if gear != 0 else 0.0
	var target := maxf(idle,shaft_rpm)
	if gear == 0:
		target = idle
	elif not grounded and enabled:
		target = clampf(rpm + (load * 2400.0 - (1.0-load) * 1400.0) * delta,idle,redline*0.98)
	else:
		var clutch_slip := 1.0 - smoothstep(2.0,10.0,absf(forward_speed))
		target = maxf(target,idle + load * float(settings["launch_slip_rpm"]) * clutch_slip)
	if shift_remaining > 0:
		var progress := 1.0 - shift_remaining / float(settings["shift_duration_s"])
		if last_shift_direction < 0:
			target = maxf(target,shift_target_rpm)
		target = lerpf(shift_from_rpm,target,smoothstep(0,1,progress))
	elif rev_match_remaining > 0 and last_shift_direction < 0:
		var clutch_settle := maxf(0.01,float(settings["rev_match_duration_s"])-float(settings["shift_duration_s"]))
		target = lerpf(target,maxf(target,shift_target_rpm),clampf(rev_match_remaining/clutch_settle,0,1))
	target = clampf(target,idle,redline)
	var slew := float(settings["rpm_rise_per_second"] if target > rpm else settings["rpm_fall_per_second"])
	rpm = move_toward(rpm,target,slew*delta)

func gear_text() -> String:
	return "R" if gear < 0 else "N" if gear == 0 else str(gear)

func shift_load_multiplier() -> float:
	if shift_remaining <= 0:
		return 1.0
	var progress := 1.0-shift_remaining/float(settings["shift_duration_s"])
	return 1.0 - sin(progress*PI) * 0.72

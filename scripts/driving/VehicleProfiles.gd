extends RefCounted

const IDS := ["VECTOR", "COMET", "APEX"]

static func load_profile(id: String) -> Dictionary:
	if id not in IDS:
		return {}
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://config/vehicles/%s.json" % id.to_lower()))
	var settings: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://config/driving_config.json"))
	settings.merge(data["physics"], true)
	settings.merge(data["abilities"], true)
	return {"id": data["id"], "role": data["role"], "config": settings, "stats": statistics(settings)}

static func score(value: float, minimum: float, maximum: float) -> int:
	return clampi(roundi(1.0 + 9.0 * inverse_lerp(minimum, maximum, value)), 1, 10)

static func tier(value: float, thresholds: Array) -> int:
	var rating := 0
	for threshold in thresholds:
		if value + 0.001 >= float(threshold):
			rating += 1
	return clampi(rating, 1, 10)

static func statistics(c: Dictionary) -> Dictionary:
	# Scores are projections of explicit physical parameters, never driving inputs.
	var kmh := float(c["max_forward_speed_mps"]) * 3.6
	var speed_score := 0
	for threshold in [100, 125, 140, 150, 160, 175, 185, 192, 198, 205]:
		if kmh >= float(threshold) - 0.01:
			speed_score = mini(10, speed_score + 1)
	speed_score = maxi(1, speed_score)
	var turbo_impulse := float(c["turbo_extra_acceleration_mps2"]) * float(c["turbo_duration_s"])
	var drift_impulse := float(c["drift_extra_acceleration_mps2"]) * float(c["drift_bonus_duration_s"])
	var burst_index := kmh * (1.0 + float(c["burst_max_bonus"])) + float(c["burst_growth_per_second"]) * 100.0 - float(c["burst_arming_time_s"]) * 5.0
	return {
		"speed": speed_score,
		"acceleration": score(-float(c["target_0_100_s"]), -8, -4),
		"handling": score(float(c["steering_sensitivity"]), 0.35, 1.35),
		"braking": score(float(c["braking_mps2"]), 5, 13),
		"drift": clampi(roundi(float(c["drift_grip_recovery_per_second"]) * 2.5 - 0.5), 1, 10),
		"turbo": tier(turbo_impulse, [0, 2, 4, 6, 8.4, 10.5, 12.5, 16.8, 20, 24]),
		"drift_boost": score(drift_impulse, -0.5, 5),
		"burst": score(burst_index, 130, 285)
	}

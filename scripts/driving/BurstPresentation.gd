extends RefCounted

static var cached: Dictionary = {}

static func settings() -> Dictionary:
	if cached.is_empty():
		cached = JSON.parse_string(FileAccess.get_file_as_string("res://config/burst_effects.json"))
	return cached

static func preparation_progress(car: CharacterBody3D) -> float:
	if car.abilities.burst_state != 1:
		return 0.0
	return clampf(car.abilities.arming_time / float(car.config["burst_arming_time_s"]), 0, 1)

static func countdown(car: CharacterBody3D) -> int:
	if car.abilities.burst_state != 1:
		return 0
	var remaining: float = float(car.config["burst_arming_time_s"]) - car.abilities.arming_time
	if remaining > 3.000001:
		return 0
	return clampi(ceili(remaining - 0.000001), 1, 3)

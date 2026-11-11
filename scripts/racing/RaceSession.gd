extends RefCounted
signal completed(result: Dictionary)
signal checkpoint_passed(index: int, lap: int)
const Geometry = preload("res://scripts/racing/RaceGeometry.gd")
var definition: Dictionary = {}
var phase := "idle"
var countdown := 3.0
var elapsed := 0.0
var next_checkpoint := 0
var progress_m := 0.0
var invalid_crossings := 0
var completed_laps := 0
var total_laps := 1
var lap_distance_m := 0.0
var lap_times: Array[float] = []
var last_lap_elapsed := 0.0

func begin(data: Dictionary) -> void:
	definition = data
	phase = "countdown"
	countdown = float(data["settings"].get("countdown_s",3.0))
	elapsed = 0
	next_checkpoint = 0
	progress_m = 0
	invalid_crossings = 0
	completed_laps = 0
	total_laps = int(data["laps"]) if data.get("type") == "circuit" else 1
	lap_distance_m = float(data.get("lap_distance_m",data["distance_m"]))
	lap_times.clear()
	last_lap_elapsed = 0.0

func advance(previous: Vector2, current: Vector2, delta: float, height_valid := true) -> void:
	if phase == "countdown":
		countdown -= delta
		if countdown <= 0: phase = "running"
		return
	if phase != "running": return
	elapsed += delta
	# Swept gates handle fast driving; reject teleports/recovery and invalid height.
	if not height_valid or previous.distance_to(current) > 150.0*delta+2.0:
		invalid_crossings += 1
		return
	var gates: Array = definition["checkpoints"]
	var last_fraction := -1.0
	var crossings := 0
	while next_checkpoint < gates.size() and crossings <= gates.size():
		var gate: Dictionary = gates[next_checkpoint]
		var center := Vector2(gate["position_xz"][0],gate["position_xz"][1])
		var forward := Vector2(gate["forward_xz"][0],gate["forward_xz"][1])
		var a := (previous-center).dot(forward)
		var b := (current-center).dot(forward)
		if a >= 0 or b < 0: break
		var fraction := -a/(b-a)
		var cross := previous.lerp(current,fraction)
		if fraction < last_fraction or absf((cross-center).cross(forward)) > Geometry.half_width(gate):
			invalid_crossings += 1
			break
		last_fraction = fraction
		checkpoint_passed.emit(next_checkpoint,completed_laps)
		progress_m = completed_laps*lap_distance_m+float(gate["distance_m"])
		next_checkpoint += 1
		crossings += 1
		if next_checkpoint == gates.size():
			completed_laps += 1
			lap_times.append(elapsed-last_lap_elapsed)
			last_lap_elapsed = elapsed
			if completed_laps == total_laps:
				phase = "finished"
				completed.emit({"race_id":definition["id"],"summary":"Circuito completado en solitario" if definition.get("type") == "circuit" else "Sprint completado en solitario","elapsed_seconds":elapsed,"distance_m":definition["distance_m"],"checkpoints":gates.size()*total_laps,"laps":completed_laps if definition.get("type") == "circuit" else 0,"lap_times":lap_times.duplicate() if definition.get("type") == "circuit" else []})
				break
			# Rearm the same ordered gates. Re-crossing just the finish never
			# awards another lap; all mandatory gates must be passed again.
			next_checkpoint = 0
	if phase == "running":
		var gate: Dictionary = gates[next_checkpoint]
		var center := Vector2(gate["position_xz"][0],gate["position_xz"][1])
		var forward := Vector2(gate["forward_xz"][0],gate["forward_xz"][1])
		if absf((current-center).cross(forward)) <= Geometry.half_width(gate):
			var passed := float(gates[next_checkpoint-1]["distance_m"]) if next_checkpoint > 0 else 0.0
			progress_m = completed_laps*lap_distance_m+clampf(float(gate["distance_m"])+(current-center).dot(forward),passed,float(gate["distance_m"]))

func current_lap() -> int:
	return mini(completed_laps+1,total_laps)

func tick_without_progress(delta: float) -> void:
	if phase == "running": elapsed += delta

func remaining() -> float:
	return maxf(0,float(definition.get("distance_m",0))-progress_m)

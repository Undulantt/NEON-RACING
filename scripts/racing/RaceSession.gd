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
var checkpoint_heights := PackedFloat32Array()

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
	checkpoint_heights.clear()
	for gate in data["checkpoints"]:
		checkpoint_heights.append(float(gate.get("ground_height_m",0.0))+Geometry.CENTER_HEIGHT_M)

func set_surface_heights(sample_height: Callable) -> void:
	for index in range(definition["checkpoints"].size()):
		var p: Array=definition["checkpoints"][index]["position_xz"]
		checkpoint_heights[index]=float(sample_height.call(p[0],p[1]))+Geometry.CENTER_HEIGHT_M

func advance(previous: Vector2, current: Vector2, delta: float, height_valid := true, previous_y := NAN, current_y := NAN) -> void:
	if phase == "countdown":
		countdown -= delta
		if countdown <= 0: phase = "running"
		return
	if phase != "running": return
	elapsed += delta
	# Runtime callers supply world heights; 2D geometry fixtures run through
	# each sphere's horizontal centre. Reject recovery/teleport displacement.
	var vertical_travel:=current_y-previous_y if is_finite(previous_y) and is_finite(current_y) else 0.0
	if not height_valid or Vector3(current.x-previous.x,vertical_travel,current.y-previous.y).length() > 150.0*delta+2.0:
		invalid_crossings += 1
		return
	var gates: Array = definition["checkpoints"]
	var last_fraction := -1.0
	var crossings := 0
	while next_checkpoint < gates.size() and crossings <= gates.size():
		var gate: Dictionary = gates[next_checkpoint]
		var center := Vector2(gate["position_xz"][0],gate["position_xz"][1])
		var forward := Vector2(gate["forward_xz"][0],gate["forward_xz"][1])
		var movement:=current-previous
		# Sideways drift is valid. Reverse travel and sitting in a sphere are not.
		if movement.length_squared()<0.00000001 or movement.dot(forward)<-0.00001: break
		var center_y: float=checkpoint_heights[next_checkpoint]
		var from:=Vector3(previous.x,previous_y if is_finite(previous_y) else center_y,previous.y)
		var to:=Vector3(current.x,current_y if is_finite(current_y) else center_y,current.y)
		var start_fraction:=maxf(0,last_fraction)
		var hit:=Geometry.sphere_fraction(from.lerp(to,start_fraction),to,Vector3(center.x,center_y,center.y),Geometry.half_width(gate))
		if hit<0: break
		var fraction:=lerpf(start_fraction,1.0,hit)
		last_fraction = fraction
		checkpoint_passed.emit(next_checkpoint,completed_laps)
		progress_m = completed_laps*lap_distance_m+float(gate["distance_m"])
		next_checkpoint += 1
		crossings += 1
		if next_checkpoint == gates.size():
			completed_laps += 1
			var crossing_time := elapsed-delta*(1.0-fraction)
			lap_times.append(crossing_time-last_lap_elapsed)
			last_lap_elapsed = crossing_time
			if completed_laps == total_laps:
				phase = "finished"
				elapsed = crossing_time
				var numbered: bool=int(definition.get("laps",0))>0
				completed.emit({"race_id":definition["id"],"summary":"Circuito completado" if definition.get("type") == "circuit" else "Recorrido completado" if numbered else "Sprint completado","elapsed_seconds":elapsed,"distance_m":definition["distance_m"],"checkpoints":gates.size()*total_laps,"laps":completed_laps if numbered else 0,"lap_times":lap_times.duplicate() if numbered else []})
				break
			# Rearm the same ordered gates. Re-crossing just the finish never
			# awards another lap; all mandatory gates must be passed again.
			next_checkpoint = 0
			# Do not consume another lap from overlapping volumes in one step.
			break
	if phase == "running":
		var gate: Dictionary = gates[next_checkpoint]
		var center := Vector2(gate["position_xz"][0],gate["position_xz"][1])
		var forward := Vector2(gate["forward_xz"][0],gate["forward_xz"][1])
		if absf((current-center).cross(forward)) <= Geometry.half_width(gate):
			var passed := float(gates[next_checkpoint-1]["distance_m"]) if next_checkpoint > 0 else 0.0
			var points: Array = definition["points_xz"]
			var edge := int(gate["edge_index"])
			var a := Vector2(points[edge][0],points[edge][1])
			var b := Vector2(points[edge+1][0],points[edge+1][1])
			var closest := Geometry2D.get_closest_point_to_segment(current,a,b)
			var along := float(gate["distance_m"])+(closest-center).dot(forward)
			progress_m = completed_laps*lap_distance_m+clampf(along,passed,float(gate["distance_m"]))

func current_lap() -> int:
	return mini(completed_laps+1,total_laps)

func tick_without_progress(delta: float) -> void:
	if phase == "running": elapsed += delta

func remaining() -> float:
	return maxf(0,float(definition.get("distance_m",0))-progress_m)

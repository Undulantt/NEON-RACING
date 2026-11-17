extends SceneTree
const Measure=preload("res://tests/RivalPassMeasurement.gd")
var checks:=0
var failures: Array=[]
func _initialize() -> void:
	var event:=fresh()
	for frame in range(29): Measure.sample(event,108,100,true)
	check(not event["measured_completed"],"Brief lead is insufficient")
	Measure.sample(event,108,100,true)
	check(event["measured_completed"],"Positive control: sustained physical progress reversal is detected")
	event=fresh()
	for frame in range(60): Measure.sample(event,106,100,true)
	check(not event["measured_completed"],"Side-by-side or small lead is insufficient")
	event=fresh()
	for frame in range(60): Measure.sample(event,108,100,false)
	check(not event["measured_completed"],"Passing an already finished car is excluded")
	event=fresh()
	event["driver_reported_completed"]=true
	for frame in range(60): Measure.sample(event,90,100,true)
	check(not event["measured_completed"],"False driver counter cannot certify a pass while attacker remains behind")
	event=fresh()
	event["initial_gap_m"]=1
	for frame in range(60): Measure.sample(event,108,100,true)
	check(not event["measured_completed"],"An initially leading car cannot claim a new pass")
	event=fresh()
	for frame in range(20): Measure.sample(event,108,100,true)
	Measure.sample(event,100,100,true)
	for frame in range(20): Measure.sample(event,108,100,true)
	check(not event["measured_completed"],"Losing the lead resets the required uninterrupted interval")
	var report:={"passed":failures.is_empty(),"checks":checks,"failures":failures,"fixture":"Audit oracle calibration with explicit progress values, not an NPC capability demonstration"}
	FileAccess.open("res://.local/artifacts/rival_acceptance_measurement_validation.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("PASS_MEASUREMENT ",JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
func fresh() -> Dictionary:
	return {"initial_gap_m":-10.0,"measured_lead_peak_m":-INF,"lead_frames":0,"measured_completed":false}
func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok: failures.append(label);push_error(label)

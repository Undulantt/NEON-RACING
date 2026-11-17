extends RefCounted
# Independent audit of a requested manoeuvre; never trust the driver's own
# completed_passes counter or project a distant target in another car's window.
static func sample(event: Dictionary, attacker_s: float, defender_s: float, both_racing: bool) -> void:
	var gap:=attacker_s-defender_s
	event["measured_lead_peak_m"]=maxf(event["measured_lead_peak_m"],gap)
	event["lead_frames"]=int(event["lead_frames"])+1 if both_racing and gap>7 and float(event["initial_gap_m"])<0 else 0
	if event["lead_frames"]>=30: event["measured_completed"]=true

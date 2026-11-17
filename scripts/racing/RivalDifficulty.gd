extends RefCounted
const IDS := ["standard","expert"]

static func settings(base: Dictionary, id: String) -> Dictionary:
	var result:=base.duplicate(true)
	result["expert"]=id=="expert"
	if id=="expert":
		# Decision limits only. Never merge these values into car.config.
		result["anticipation"]=maxf(1.0,float(base["anticipation"])*0.82)
		result["throttle"]=lerpf(float(base["throttle"]),1.0,0.85)
		result["lateral_accel_mps2"]=float(base["lateral_accel_mps2"])*1.2
		result["lane_change_mps"]=float(base["lane_change_mps"])*1.1
		result["turbo_reserve"]=maxf(0.12,float(base["turbo_reserve"])-0.15)
	return result

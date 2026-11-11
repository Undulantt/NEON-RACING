extends RefCounted
const CHECKPOINT_SCALE := 1.3

static func half_width(gate: Dictionary) -> float:
	return float(gate["half_width_m"])*CHECKPOINT_SCALE

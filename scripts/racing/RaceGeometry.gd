extends RefCounted
const CHECKPOINT_SCALE := 1.3
const CENTER_HEIGHT_M := 0.75

static func half_width(gate: Dictionary) -> float:
	return float(gate["half_width_m"])*CHECKPOINT_SCALE

# Swept point/sphere trigger. Starting inside is accepted when the caller
# has verified motion and race direction; the car need not cross a plane.
static func sphere_fraction(previous: Vector3, current: Vector3, center: Vector3, radius: float) -> float:
	var relative:=previous-center
	var c:=relative.length_squared()-radius*radius
	if c<=0: return 0.0
	var movement:=current-previous
	var a:=movement.length_squared()
	if a<0.00000001: return -1.0
	var b:=relative.dot(movement)
	var discriminant:=b*b-a*c
	if discriminant<0: return -1.0
	var fraction:=(-b-sqrt(discriminant))/a
	return fraction if fraction>=0 and fraction<=1 else -1.0

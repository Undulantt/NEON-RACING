extends Control

var car: CharacterBody3D
var intensity := 0.0
var elapsed := 0.0
var drift_tint := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func _process(delta: float) -> void:
	if car == null or get_tree().paused:
		return
	elapsed += delta
	var active: bool = car.driving_enabled
	var target: float = clampf((car.speed_mps - 24.0) / 22.0, 0.0, 0.22)
	if car.turbo_active:
		target = 1.0
	elif car.drift_boost_active:
		target = 0.5
	if not active:
		target = 0.0
	var mix := 1.0 - exp(-9.0 * delta)
	intensity = lerpf(intensity, target, mix)
	drift_tint = lerpf(drift_tint, 1.0 if car.drift_boost_active and not car.turbo_active else 0.0, mix)
	queue_redraw()

func _draw() -> void:
	if intensity < 0.01:
		return
	var viewport := get_viewport_rect().size
	var center := viewport * 0.5
	var hue := Color("70e5ff").lerp(Color("ffd17a"), drift_tint)
	# Ray/rectangle intersection places streaks INSIDE the screen perimeter.
	# Keep the center clear so the road and vehicle remain readable.
	for i in range(64):
		var angle := TAU * float(i) / 64.0
		var direction := Vector2(cos(angle), sin(angle))
		var edge_distance := minf(center.x / maxf(absf(direction.x), 0.001), center.y / maxf(absf(direction.y), 0.001))
		var phase := fposmod(elapsed * (1.1 + intensity) + float(i) * 0.618, 1.0)
		var head := center + direction * edge_distance * (0.62 + phase * 0.53)
		var length := lerpf(25.0, 145.0, phase) * intensity
		var tail := head - direction * length
		var opacity := intensity * (0.35 + 0.45 * sin(phase * PI))
		draw_line(head, tail, Color(hue, opacity * 0.2), 7.0, true)
		draw_line(head, tail, Color(hue.lerp(Color.WHITE, 0.45), opacity), 2.5, true)
	for i in range(12):
		var tint := Color(hue, intensity * 0.16 * (1.0 - float(i) / 12.0))
		draw_rect(Rect2(i * 3, 0, 3, viewport.y), tint)
		draw_rect(Rect2(viewport.x - (i + 1) * 3, 0, 3, viewport.y), tint)

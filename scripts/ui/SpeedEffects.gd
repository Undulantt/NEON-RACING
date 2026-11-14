extends Control

var retro_profile := false
var effect_strength := 1.0
var car: CharacterBody3D
var intensity := 0.0
var elapsed := 0.0
var drift_tint := 0.0
var burst_blend := 0.0
var sf4_burst_progress := -1.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func _process(delta: float) -> void:
	if car == null or get_tree().paused:
		return
	elapsed += delta
	var active: bool = car.driving_enabled
	var target: float = clampf((car.speed_mps - 24.0) / 22.0, 0.0, 0.22)
	var bursting: bool = car.abilities.burst_state == 2
	burst_blend = lerpf(burst_blend, 1.0 if bursting and active else 0.0, 1.0 - exp(-10.0 * delta))
	if sf4_burst_progress>=0:burst_blend=sf4_burst_progress if active else 0.0
	if bursting:
		target = lerpf(0.22,1.4,sf4_burst_progress) if sf4_burst_progress>=0 else 2.0
	elif car.turbo_active:
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
	if intensity * effect_strength < 0.01:
		return
	if retro_profile or burst_blend > 0.1:
		draw_retro()
		return
	var viewport := get_viewport_rect().size
	var center := viewport * 0.5
	var hue := Color("70e5ff").lerp(Color("ffd17a"), drift_tint).lerp(Color("ff72db"), burst_blend)
	# Ray/rectangle intersection places streaks INSIDE the screen perimeter.
	# Keep the center clear so the road and vehicle remain readable.
	var streak_count := 144 if burst_blend > 0.2 else 64
	for i in range(streak_count):
		var angle := TAU * float(i) / float(streak_count)
		var direction := Vector2(cos(angle), sin(angle))
		var edge_distance := minf(center.x / maxf(absf(direction.x), 0.001), center.y / maxf(absf(direction.y), 0.001))
		var phase := fposmod(elapsed * (1.1 + intensity) + float(i) * 0.618, 1.0)
		var head := center + direction * edge_distance * (0.62 + phase * 0.53)
		var length := lerpf(25.0, 145.0, phase) * intensity * effect_strength
		var tail := head - direction * length
		var opacity := minf(0.95, intensity * effect_strength * (0.35 + 0.45 * sin(phase * PI)))
		draw_line(head, tail, Color(hue, opacity * 0.2), 7.0, true)
		draw_line(head, tail, Color(hue.lerp(Color.WHITE, 0.45), opacity), 2.5, true)
	for i in range(12):
		var tint := Color(hue, intensity * 0.16 * (1.0 - float(i) / 12.0))
		draw_rect(Rect2(i * 3, 0, 3, viewport.y), tint)
		draw_rect(Rect2(viewport.x - (i + 1) * 3, 0, 3, viewport.y), tint)

# Sparse peripheral streaks; no central flash or full-height edge curtains.
func retro_segments(viewport: Vector2) -> Array:
	var result: Array = []
	var focus := viewport * Vector2(0.5,0.43)
	var gain := intensity*effect_strength
	if gain < 0.01:
		return result
	if burst_blend > 0.1:
		return burst_segments(viewport)
	var minimap := Rect2(0,0,260,280)
	var gauges := Rect2(viewport.x-350,viewport.y-500,350,500)
	var center_safe := Rect2(viewport*Vector2(0.27,0.16),viewport*Vector2(0.46,0.75))
	for side in [-1,1]:
		for i in range(10):
			var edge := Vector2(-12 if side<0 else viewport.x+12,viewport.y*(0.10+float(i)*0.075))
			var phase := fposmod(elapsed*(0.8+gain*0.75)+float(i)*0.618+float(side)*0.13,1.0)
			var head := focus.lerp(edge,0.78+phase*0.34)
			var direction := (edge-focus).normalized()
			var tail := head-direction*viewport.y*(0.035+phase*0.055)*gain
			if head.y > viewport.y-60 or tail.y > viewport.y-60:
				continue
			var blocked := false
			for protected in [minimap,gauges,center_safe]:
				# AABB rejection also protects the entire segment, not just its ends.
				if protected.intersects(Rect2(head.min(tail),head.max(tail)-head.min(tail)).grow(4)):
					blocked = true
			if not blocked:
				result.append({"head":head,"tail":tail,"alpha":sin(phase*PI)*gain*0.68,"accent":i%4==0})
	return result

func burst_segments(viewport: Vector2) -> Array:
	var result: Array = []
	var gain := intensity * effect_strength * burst_blend
	var focus := viewport * Vector2(0.5, 0.43)
	var protected := [Rect2(0, 0, 260, 280), Rect2(viewport.x-350, viewport.y-500, 350, 500), Rect2(viewport * Vector2(0.30, 0.23), viewport * Vector2(0.40, 0.69)), Rect2(0, viewport.y-60, viewport.x, 60)]
	for i in range(144):
		var angle := TAU * i / 144.0
		var direction := Vector2(cos(angle), sin(angle))
		var edge_x := (viewport.x-focus.x if direction.x >= 0 else focus.x) / maxf(absf(direction.x), 0.001)
		var edge_y := (viewport.y-focus.y if direction.y >= 0 else focus.y) / maxf(absf(direction.y), 0.001)
		var distance := minf(edge_x, edge_y)
		var phase := fposmod(elapsed * 3.8 + float(i) * 0.618, 1.0)
		var head := focus + direction * distance * (0.83 + phase * 0.30)
		var length := minf(viewport.y * (0.09 + phase * 0.13) * gain, head.distance_to(focus) * 0.25)
		var tail := head - direction * length
		var blocked := false
		for rect in protected:
			if rect.intersects(Rect2(head.min(tail), head.max(tail)-head.min(tail)).grow(5)):
				blocked = true
		if not blocked:
			result.append({"head": head, "tail": tail, "alpha": minf(0.94, (0.4 + sin(phase * PI) * 0.5) * gain), "accent": i % 3 == 0})
	return result

func draw_retro() -> void:
	for streak in retro_segments(get_viewport_rect().size):
		var color := Color("ed80d5") if streak["accent"] else Color("92ecff")
		color=color.lerp(Color("bba4ff"),drift_tint*0.5).lerp(Color("ff7edb"),burst_blend*0.65)
		draw_line(streak["head"],streak["tail"],Color(color,streak["alpha"]*0.18),lerpf(5.0, 10.0, burst_blend),true)
		draw_line(streak["head"],streak["tail"],Color(color.lerp(Color.WHITE,0.4),streak["alpha"]),lerpf(1.8, 3.2, burst_blend),true)

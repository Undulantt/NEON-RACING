extends SceneTree

const Main = preload("res://scenes/FlatWorld.tscn")
var world: Node3D
var started := 0
var measured := 0
var previous := 0
var intervals: Array[float] = []
var draw_calls := 0.0
var primitives := 0.0

func _initialize() -> void:
	setup.call_deferred()

func setup() -> void:
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1920, 1080)
	world = Main.instantiate()
	root.add_child(world)
	started = Time.get_ticks_usec()
	previous = started

func _process(_delta: float) -> bool:
	if started == 0:
		return false
	var now := Time.get_ticks_usec()
	if now - started < 2000000:
		previous = now
		return false
	if measured == 0:
		measured = now
	intervals.append(float(now - previous) / 1000.0)
	previous = now
	draw_calls += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	primitives += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
	if now - measured >= 10000000:
		intervals.sort()
		var count := intervals.size()
		var report := {"scenario": "Static spawn, normal renderer, 2s warmup + 10s sample; not a full driving benchmark", "elapsed_s": float(now - measured) / 1000000.0, "frames": count, "average_fps": float(count) * 1000000.0 / float(now - measured), "p95_frame_ms": intervals[int(count * 0.95)], "max_frame_ms": intervals[-1], "mean_draw_calls": draw_calls / count, "mean_primitives": primitives / count, "viewport_texture_px": [root.get_texture().get_width(), root.get_texture().get_height()], "node_count": Performance.get_monitor(Performance.OBJECT_NODE_COUNT), "world": world.stats}
		var file := FileAccess.open("res://docs/phase_b_benchmark.json", FileAccess.WRITE)
		file.store_string(JSON.stringify(report, "  "))
		root.get_texture().get_image().save_png("res://docs/evidence/phase_b_spawn_final.png")
		print("PHASE_B_BENCHMARK ", JSON.stringify(report))
		quit()
	return false

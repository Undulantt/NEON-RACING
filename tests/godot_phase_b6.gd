extends SceneTree
const Builder = preload("res://scripts/world/BuildingBuilder.gd")
var failures: Array = []
func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
func _initialize() -> void:
	var b := {"id":"fixture", "footprint_xz":[[0,0],[10,0],[10,10],[0,10]], "roof_triangles_xz":[[[0,0],[10,0],[10,10]],[[0,0],[10,10],[0,10]]], "height_m":6.2, "palette_index":0, "category":"restaurant"}
	var parent := Node3D.new()
	root.add_child(parent)
	var stats := Builder.build(parent, {"buildings":[b], "category_facades":true, "detail_windows":false})
	check(stats["building_triangles"] == 20, "bounded facade triangles")
	var body := parent.get_child(0) as StaticBody3D
	var shell := (body.get_child(1) as CollisionShape3D).shape as ConcavePolygonShape3D
	check(shell.get_faces().size() == 30, "facades excluded from physics")
	parent.free()
	parent = Node3D.new()
	root.add_child(parent)
	b["model_path"] = "res://tests/fixtures/building_model.tscn"
	stats = Builder.build(parent, {"buildings":[b], "detail_windows":false})
	check(stats["building_triangles"] == 0, "custom scene replaces procedural visual")
	check(parent.get_child_count() == 2, "custom visual plus geographic physics shell")
	parent.free()
	var cathedral = load("res://scenes/landmarks/Cathedral.tscn").instantiate()
	root.add_child(cathedral)
	# _ready runs after initialization when the tree begins processing.
	cathedral._ready()
	check(cathedral.get_child_count() == 1, "cathedral details stay in one mesh")
	cathedral.free()
	var f := FileAccess.open("res://docs/phase_b6_runtime.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"passed":failures.is_empty(),"failures":failures},"  "))
	print("B6_RUNTIME ", failures)
	quit(0 if failures.is_empty() else 1)

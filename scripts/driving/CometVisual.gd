extends RefCounted
# Compatibility entry point; all beta cars use the shared presentation adapter.
const Adapter=preload("res://scripts/driving/ImportedCarVisual.gd")
const MODEL=preload("res://assets/autos/Not1965FordMustangHoonicorn.glb")
const MODEL_SCALE=Adapter.MODEL_SCALE
const MODEL_OFFSET=Adapter.MODEL_OFFSET
const WHEELS=Adapter.WHEELS

static func apply(parent: Node3D, visuals: Dictionary) -> void:
	Adapter.apply(parent,visuals,MODEL,"COMET")

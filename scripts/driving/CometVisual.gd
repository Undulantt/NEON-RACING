extends RefCounted
# Presentation adapter for the supplied GLB. Never adds physics bodies.
const MODEL=preload("res://assets/autos/Not1965FordMustangHoonicorn.glb")
const MODEL_SCALE:=0.65
const MODEL_OFFSET:=Vector3(0,-0.585,0.13)
const WHEELS:=["WheelFrontLeft","WheelFronRight","WheelBackLeft","WheelBackRright"]

static func apply(parent: Node3D, visuals: Dictionary) -> void:
	for child in parent.get_children():
		if child is MeshInstance3D and child not in visuals["exhaust"]:child.hide()
	for wheel in visuals["wheels"]:wheel.hide()
	var model: Node3D=MODEL.instantiate()
	model.name="CometModel"
	model.transform=Transform3D(Basis(Vector3.UP,PI).scaled(Vector3.ONE*MODEL_SCALE),MODEL_OFFSET)
	parent.add_child(model)
	# This part has no material assigned in the supplied GLB.
	var support: MeshInstance3D=model.find_child("SpoilerBase",true,false)
	var support_material:=StandardMaterial3D.new()
	support_material.albedo_color=Color("25232e")
	support_material.metallic=.3;support_material.roughness=.65
	support.material_override=support_material
	support.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var spins: Array[MeshInstance3D]=[]
	for i in range(4):
		var wheel: MeshInstance3D=model.find_child(WHEELS[i],true,false)
		assert(wheel!=null,"The supplied COMET model must retain its four named wheels")
		var pivot: Node3D=visuals["pivots"][i]
		pivot.position=parent.to_local(wheel.global_position)
		var spin:=MeshInstance3D.new()
		spin.name="CometWheelSpin%d"%i
		# The driving presentation spins all wheels about the same local Y axis.
		# A carrier preserves the GLB's mirrored left/right wheel orientations.
		spin.rotation.z=PI/2
		pivot.add_child(spin)
		wheel.reparent(spin,true)
		spins.append(spin)
	visuals["wheels"]=spins
	var tail: MeshInstance3D=model.find_child("HeadlightBack",true,false)
	var brake: StandardMaterial3D=tail.get_active_material(0).duplicate()
	tail.material_override=brake
	visuals["brake_material"]=brake
	for name in ["Body","Motor","Spoiler","Turbos"]:
		var node:=model.find_child(name,true,false)
		if node!=null:node.set_meta("sf4_body",true)

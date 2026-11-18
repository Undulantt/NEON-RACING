extends RefCounted
# Shared presentation adapter for the three supplied Blender exports.
const MODEL_SCALE:=0.65
const MODEL_OFFSET:=Vector3(0,-0.585,0.13)
const WHEELS:=["WheelFrontLeft","WheelFronRight","WheelBackLeft","WheelBackRright"]

static func apply(parent: Node3D, visuals: Dictionary, scene: PackedScene, profile: String) -> bool:
	var model: Node3D=scene.instantiate()
	model.name=profile.capitalize()+"Model"
	model.transform=Transform3D(Basis(Vector3.UP,PI).scaled(Vector3.ONE*MODEL_SCALE),MODEL_OFFSET)
	parent.add_child(model)
	var imported_wheels: Array[MeshInstance3D]=[]
	for prefix in WHEELS:
		var wheel:=model.find_child(prefix+"*",true,false) as MeshInstance3D
		if wheel==null:
			model.free();push_error("Modelo %s: falta rueda %s"%[profile,prefix]);return false
		imported_wheels.append(wheel)
	for child in parent.get_children():
		if child is MeshInstance3D and child not in visuals["exhaust"]:child.hide()
	for wheel in visuals["wheels"]:wheel.hide()
	var support:=model.find_child("SpoilerBase*",true,false) as MeshInstance3D
	if support!=null:
		var material:=StandardMaterial3D.new();material.albedo_color=Color("25232e")
		material.metallic=.3;material.roughness=.65;support.material_override=material
		support.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var brake: StandardMaterial3D
	for node in model.find_children("*","MeshInstance3D",true,false):
		var painted:=false
		for surface in range(node.mesh.get_surface_count()):
			var material: Material=node.get_active_material(surface)
			if material==null:continue
			if material.resource_name.begins_with("LightBack"):
				if brake==null:brake=material.duplicate()
				node.set_surface_override_material(surface,brake)
			if material.resource_name.begins_with("Metallic"):painted=true
		if painted and (str(node.name).begins_with("Body") or str(node.name).begins_with("Motor") or str(node.name).begins_with("Spoiler") or str(node.name).begins_with("Turbos")):node.set_meta("sf4_body",true)
	if brake!=null:visuals["brake_material"]=brake
	var spins: Array[MeshInstance3D]=[]
	for i in range(4):
		var wheel: MeshInstance3D=imported_wheels[i]
		var pivot: Node3D=visuals["pivots"][i]
		pivot.position=parent.to_local(wheel.global_position)
		var spin:=MeshInstance3D.new();spin.name="%sWheelSpin%d"%[profile.capitalize(),i]
		spin.rotation.z=PI/2;pivot.add_child(spin)
		wheel.reparent(spin,true);spins.append(spin)
	visuals["wheels"]=spins
	parent.set_meta("imported_vehicle_model",profile)
	return true

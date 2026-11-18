extends Node
# Compatibility-renderer quality tier. Capture the baseline once, then restore exactly.
var world: Node3D
var viewport: Viewport
var baseline_msaa: int
var snapshots: Array[Dictionary]=[]
var accents: Array[OmniLight3D]=[]
var enabled := false

func configure(target: Node3D) -> void:
	world=target;viewport=world.get_viewport();baseline_msaa=viewport.msaa_3d
	for node in world.get_children():
		if node is DirectionalLight3D:
			snapshots.append({"node":node,"shadow_enabled":node.shadow_enabled,"light_energy":node.light_energy,"directional_shadow_max_distance":node.directional_shadow_max_distance})
		elif node is WorldEnvironment:
			var env: Environment=node.environment
			snapshots.append({"node":env,"ambient_light_energy":env.ambient_light_energy})
	for light in world.player.visual_root.find_children("*","SpotLight3D",true,false):
		snapshots.append({"node":light,"shadow_enabled":light.shadow_enabled,"light_energy":light.light_energy})
	for entry in [[Color("02d9ff"),Vector3(-1.7,1.1,0)],[Color("ff38b6"),Vector3(1.7,1.1,.8)]]:
		var light:=OmniLight3D.new();light.light_color=entry[0];light.position=entry[1]
		light.light_energy=.7;light.omni_range=7;light.shadow_enabled=false
		world.player.visual_root.add_child(light);accents.append(light);light.hide()

func set_enabled(value: bool) -> void:
	enabled=value
	viewport.msaa_3d=Viewport.MSAA_4X if enabled else baseline_msaa
	for record in snapshots:
		var node: Object=record["node"]
		for key in record:
			if key!="node":node.set(key,record[key])
		if enabled:
			if node is DirectionalLight3D:
				node.shadow_enabled=true;node.directional_shadow_max_distance=90;node.light_energy=float(record["light_energy"])*1.25
			elif node is SpotLight3D:
				node.shadow_enabled=true;node.light_energy=float(record["light_energy"])*1.2
			elif node is Environment:node.ambient_light_energy=float(record["ambient_light_energy"])*1.12
	for light in accents:light.visible=enabled

func _exit_tree() -> void:
	if is_instance_valid(viewport):viewport.msaa_3d=baseline_msaa

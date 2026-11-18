extends SceneTree
func _initialize() -> void:run.call_deferred()
func scan(node: Node, parent_transform: Transform3D, rows: Array) -> void:
	var transform:=parent_transform
	if node is Node3D:transform=transform*node.transform
	if node is MeshInstance3D and node.mesh!=null:
		var aabb: AABB=transform*node.mesh.get_aabb()
		rows.append({"name":str(node.name),"min":[aabb.position.x,aabb.position.y,aabb.position.z],"max":[aabb.end.x,aabb.end.y,aabb.end.z]})
	for child in node.get_children():scan(child,transform,rows)
func walk(path: String, output: Dictionary) -> void:
	for directory in DirAccess.get_directories_at(path):walk(path+"/"+directory,output)
	for filename in DirAccess.get_files_at(path):
		if not filename.ends_with(".glb"):continue
		var scene: PackedScene=load(path+"/"+filename)
		var node:=scene.instantiate();var rows: Array=[];scan(node,Transform3D.IDENTITY,rows)
		output[path+"/"+filename]=rows;node.free()
func run() -> void:
	var output:={};walk("res://assets/3D/Edificios",output)
	FileAccess.open("res://.local/artifacts/landmark_model_bounds.json",FileAccess.WRITE).store_string(JSON.stringify(output,"  "))
	print("LANDMARK_MODELS_INSPECTED ",output.size());quit()

extends SceneTree
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var manifest=JSON.parse_string(FileAccess.get_file_as_string("res://data/processed/relief/world/manifest.json"))
	var output:="res://data/processed/night_roads/"
	DirAccess.make_dir_recursive_absolute(output)
	var index:={"generator_sha256":FileAccess.get_file_as_string("res://scripts/style/RoadNeon.gd").replace("\r\n","\n").sha256_text(),"entries":{}}
	var count:=0
	for entry in manifest["roads"]:
		var node=load("res://"+str(entry["scene_file"])).instantiate();root.add_child(node)
		var files: Array[String]=[]
		for road in node.find_children("*","MeshInstance3D",true,false):
			await preload("res://scripts/style/RoadNeon.gd").build(road)
			var neon=road.get_node_or_null("RoadEdgeNeon")
			var path:=""
			if neon!=null:
				path=output+str(entry["id"])+"_"+str(files.size())+".res"
				neon.mesh.surface_set_material(0,neon.material_override)
				var error:=ResourceSaver.save(neon.mesh,path,ResourceSaver.FLAG_COMPRESS)
				if error!=OK: push_error("Neon save failed");quit(1);return
			files.append(path)
		index["entries"][str(entry["id"])]={"scene_sha256":entry["scene_sha256"],"files":files}
		node.free();count+=1
		if count%100==0: print("NEON_BAKE ",count)
	FileAccess.open(output+"manifest.json",FileAccess.WRITE).store_string(JSON.stringify(index))
	print("NEON_BAKE_COMPLETE ",count)
	quit()

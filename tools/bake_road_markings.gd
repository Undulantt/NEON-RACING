extends SceneTree
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var source:="res://.godot-local-profile/road_markings/"
	var geometry=JSON.parse_string(FileAccess.get_file_as_string("res://data/processed/relief/world/manifest.json"))
	var paint_index=JSON.parse_string(FileAccess.get_file_as_string(source+"manifest.json"))
	var output:="res://data/processed/night_roads/"
	var manifest=JSON.parse_string(FileAccess.get_file_as_string(output+"manifest.json"))
	var count:=0;var painted:=0;var total_vertices:=0
	for entry in geometry["roads"]:
		var polygons: Array=JSON.parse_string(FileAccess.get_file_as_string(source+str(entry["id"])+".json"))
		var node=load("res://"+str(entry["scene_file"])).instantiate();root.add_child(node)
		var index:=0;var painted_vertices:=0
		for road in node.find_children("*","MeshInstance3D",true,false):
			var path: String=manifest["entries"][str(entry["id"])] ["files"][index]
			var result:=ArrayMesh.new()
			if not path.is_empty():
				var neon=load(path)
				if neon.get_surface_count()>0:
					result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,neon.surface_get_arrays(0))
					result.surface_set_material(0,neon.surface_get_material(0))
			var paint=preload("res://tools/project_road_markings.gd").project(road,polygons)
			if paint.get_surface_count()>0:
				var arrays=paint.surface_get_arrays(0)
				painted_vertices+=arrays[Mesh.ARRAY_VERTEX].size()
				var surface:=result.get_surface_count()
				result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
				result.surface_set_material(surface,paint.surface_get_material(0))
			if result.get_surface_count()>0:
				if path.is_empty(): path=output+str(entry["id"])+"_"+str(index)+".res"
				if ResourceSaver.save(result,path,ResourceSaver.FLAG_COMPRESS)!=OK: push_error("Markings save failed");quit(1);return
				manifest["entries"][str(entry["id"])]["files"][index]=path
			index+=1
		manifest["entries"][str(entry["id"])]["marking_vertices"]=painted_vertices
		if painted_vertices>0: painted+=1
		total_vertices+=painted_vertices
		node.free();count+=1
		if count%100==0: print("MARKINGS_BAKE ",count)
	manifest["markings"]=paint_index
	manifest["markings"].erase("tiles")
	manifest["markings"]["painted_sectors"]=painted
	manifest["markings"]["vertices"]=total_vertices
	FileAccess.open(output+"manifest.json",FileAccess.WRITE).store_string(JSON.stringify(manifest))
	print("MARKINGS_COMPLETE sectors=",count," painted=",painted," vertices=",total_vertices)
	quit()

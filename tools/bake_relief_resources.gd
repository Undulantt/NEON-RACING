extends SceneTree

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var mode := "pilot"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--mode="):
			mode = argument.trim_prefix("--mode=")
	if mode not in ["pilot","world"]:
		quit(1)
		return
	var path := "res://data/processed/relief/" + mode + "/manifest.json"
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	var start := Time.get_ticks_msec()
	var total_bytes := 0
	var count := 0
	var kinds: Array = ["roads","terrain"]
	if manifest.has("limits"):
		kinds.append("limits")
	for kind in kinds:
		var directory: String = "res://data/processed/relief/" + mode + "/native/" + str(kind)
		DirAccess.make_dir_recursive_absolute(directory)
		for entry in manifest[kind]:
			var source: Dictionary = entry.duplicate()
			source.erase("scene_file")
			source.erase("scene_sha256")
			var holder := Node3D.new()
			var result := preload("res://scripts/world/RoadBuilder.gd").build(holder,{"chunks":[source],"layer":{"roads":1,"terrain":2,"limits":8}[kind]})
			if result.has("error") or holder.get_child_count()!=1:
				push_error("Cannot cache relief sector: "+str(source["id"]))
				holder.free()
				quit(1)
				return
			var body := holder.get_child(0)
			for child in body.get_children():
				child.owner = body
			var packed := PackedScene.new()
			var target: String = directory+"/"+str(entry["id"])+".scn"
			if packed.pack(body)!=OK or ResourceSaver.save(packed,target,ResourceSaver.FLAG_COMPRESS)!=OK:
				push_error("Cannot save relief cache")
				holder.free()
				quit(1)
				return
			holder.free()
			entry["scene_file"] = target.trim_prefix("res://")
			entry["scene_sha256"] = FileAccess.get_sha256(target)
			total_bytes += FileAccess.get_file_as_bytes(target).size()
			count += 1
			if count%100==0:
				print("RELIEF_CACHE ",count)
	manifest["native_cache"]={"engine":Engine.get_version_info()["string"],"scenes":count,"bytes":total_bytes,"build_ms":Time.get_ticks_msec()-start,"note":"Derived optional runtime cache; regenerate from binary triangle sources when changing Godot version"}
	var file := FileAccess.open(path,FileAccess.WRITE)
	file.store_string(JSON.stringify(manifest))
	file.flush()
	var bake_path := "res://docs/phase_b7r_"+mode+"_bake.json"
	if FileAccess.file_exists(bake_path):
		var bake_report: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(bake_path))
		bake_report["published_manifest_sha256"] = FileAccess.get_sha256(path)
		var bake_file := FileAccess.open(bake_path,FileAccess.WRITE)
		bake_file.store_string(JSON.stringify(bake_report,"  "))
	var report := FileAccess.open("res://docs/phase_b7r_"+mode+"_native_cache.json",FileAccess.WRITE)
	report.store_string(JSON.stringify(manifest["native_cache"],"  "))
	print("RELIEF_CACHE_READY ",manifest["native_cache"])
	quit(0)

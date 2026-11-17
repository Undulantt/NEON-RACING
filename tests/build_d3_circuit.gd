extends SceneTree
func _initialize() -> void:
	var map = JSON.parse_string(FileAccess.get_file_as_string("res://data/processed/la_paz_map.json"))
	var graph = preload("res://scripts/racing/RoadGraph.gd").new()
	graph.build(map,FileAccess.get_sha256("res://data/processed/la_paz_map.json"))
	var store = preload("res://scripts/racing/RaceStore.gd")
	var data = store.create(graph,["6195649062","313407104","313407631"],"centro_circuit_d3","Centro LP · Copa neón",20.0,false,"circuit",2)
	print(store.validate(data,graph))
	FileAccess.open("res://data/races/centro_circuit_d3.json",FileAccess.WRITE).store_string(JSON.stringify(data,"  "))
	print("CIRCUIT ",data.get("lap_distance_m")," edges ",data.get("edges",[]).size())
	quit()

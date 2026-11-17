extends SceneTree
var checks:=0
var failures:Array=[]
func _initialize() -> void: run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures.append(label);push_error(label)
func run() -> void:
	var map: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/processed/la_paz_map.json"))
	var graph=preload("res://scripts/racing/RoadGraph.gd").new()
	graph.build(map,FileAccess.get_sha256("res://data/processed/la_paz_map.json"))
	var store=preload("res://scripts/racing/RaceStore.gd")
	var anchors:Array=["6195649062","313407104","313407631"]
	var dense:Dictionary=store.create(graph,anchors,"test_dense","Dense",10,false,"circuit",2)
	var sparse:Dictionary=store.create(graph,anchors,"test_sparse","Sparse",60,false,"circuit",2)
	var path=preload("res://scripts/racing/RaceTrajectory.gd").new()
	var second=preload("res://scripts/racing/RaceTrajectory.gd").new()
	path.configure(dense)
	second.configure(sparse)
	check(dense["checkpoints"].size()!=sparse["checkpoints"].size(),"Fixture changes only mandatory gate density")
	check(path.points==second.points and path.curvature==second.curvature and path.left_limits==second.left_limits and path.right_limits==second.right_limits,"Driving trajectory is independent of checkpoint density")
	check(path.rounded_corners>=4,"Closed road geometry produces rounded intersections")
	check(path.sample(path.length)["position"].distance_to(path.sample(0)["position"])<0.001,"Circuit samples join at seam")
	check(absf(path.project(path.points[0],path.length-1)["s"]-path.length)<0.01,"Projection preserves unwrapped lap at seam")
	for pair in [[dense,0.0],[sparse,0.0],[dense,-3.5],[dense,3.5],[sparse,-3.5],[sparse,3.5]]:
		var data: Dictionary=pair[0]
		var offset: float=pair[1]
		var session=preload("res://scripts/racing/RaceSession.gd").new()
		session.begin(data)
		session.phase="running"
		var previous:Vector2=path.sample(0,offset)["position"]
		for lap in range(2):
			for index in range(path.points.size()):
				var point: Vector2=path.sample(path.distances[index],offset)["position"]
				session.advance(previous,point,1.0/30)
				previous=point
		# Offset lines cross the finish plane a few centimetres before/after
		# the centreline seam. Continue physically past it instead of equating
		# spline wrapping with a valid finish.
		if session.phase!="finished": session.advance(previous,path.sample(0.5,offset)["position"],1.0/30)
		check(session.phase=="finished" and session.completed_laps==2,"Continuous path crosses every mandatory gate in order: "+data["id"]+" offset "+str(offset))
	var sharpest:=0.0
	for value in path.curvature: sharpest=maxf(sharpest,absf(value))
	check(sharpest<0.4,"Trajectory avoids ninety-degree heading discontinuities")
	var report:={"passed":failures.is_empty(),"checks":checks,"failures":failures,"length_m":path.length,"samples":path.points.size(),"rounded_corners":path.rounded_corners,"max_curvature":sharpest,"dense_gates":dense["checkpoints"].size(),"sparse_gates":sparse["checkpoints"].size()}
	FileAccess.open("res://.local/artifacts/d3_trajectory_geometry.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("D3_TRAJECTORY_GEOMETRY ",JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)

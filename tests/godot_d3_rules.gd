extends SceneTree
const Session=preload("res://scripts/racing/RaceSession.gd")
var failures: Array=[]
var checks:=0
func _initialize() -> void: run.call_deferred()
func check(value: bool, message: String) -> void:
	checks+=1
	if not value: failures.append(message);push_error(message)
func cross_gate(s: RefCounted, index: int, backwards:=false) -> void:
	var gate: Dictionary=s.definition["checkpoints"][index]
	var p:=Vector2(gate["position_xz"][0],gate["position_xz"][1])
	var f:=Vector2(gate["forward_xz"][0],gate["forward_xz"][1])
	s.advance(p+f*0.1 if backwards else p-f*0.1,p-f*0.1 if backwards else p+f*0.1,1.0/60)
func run() -> void:
	var data: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/races/centro_circuit_d3.json"))
	var s=Session.new()
	s.begin(data)
	s.advance(Vector2.ZERO,Vector2.ZERO,3.1)
	cross_gate(s,0,true)
	check(s.next_checkpoint==0,"Reverse crossing rejected")
	cross_gate(s,data["checkpoints"].size()-1)
	check(s.completed_laps==0 and s.next_checkpoint==0,"Finish shortcut rejected")
	var gate: Dictionary=data["checkpoints"][0]
	var p:=Vector2(gate["position_xz"][0],gate["position_xz"][1])
	var f:=Vector2(gate["forward_xz"][0],gate["forward_xz"][1])
	s.advance(p-f*100,p+f*100,1.0/60)
	check(s.next_checkpoint==0,"Teleport rejected")
	s.advance(p-f,p+f,1.0/60,false)
	check(s.next_checkpoint==0,"Invalid height rejected")
	cross_gate(s,1)
	check(s.next_checkpoint==0,"Missing mandatory gate rejected")
	for lap in range(2):
		for i in range(data["checkpoints"].size()): cross_gate(s,i)
		check(s.completed_laps==lap+1,"Ordered lap counted exactly once")
		if lap==0:
			cross_gate(s,data["checkpoints"].size()-1)
			check(s.completed_laps==1 and s.next_checkpoint==0,"Repeated finish does not award lap")
	check(s.phase=="finished" and s.lap_times.size()==2,"Two laps finish and record two measured times")
	var elapsed: float=s.elapsed
	cross_gate(s,0)
	check(s.elapsed==elapsed,"Finished time immutable")
	var competition=preload("res://scripts/racing/RaceCompetition.gd").new()
	for i in range(6):
		var progress=Session.new()
		progress.begin(data)
		progress.phase="running"
		progress.completed_laps=i/3
		progress.next_checkpoint=i%3
		progress.progress_m=i*10
		competition.racers.append({"name":str(i),"session":progress,"finish":0})
	check(competition.standings()[0]["name"]=="5","Ranking uses lap then mandatory gates then path")
	competition.racers[0]["session"].phase="finished"
	competition.racers[0]["session"].elapsed=100
	competition.racers[0]["finish"]=1
	check(competition.standings()[0]["name"]=="0","Finish outranks unfinished progress")
	competition.free()
	var report:={"passed":failures.is_empty(),"checks":checks,"failures":failures}
	FileAccess.open("res://.local/artifacts/d3_rules_validation.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("D3_RULES ",JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)

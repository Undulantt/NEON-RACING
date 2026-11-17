extends SceneTree
const Session=preload("res://scripts/racing/RaceSession.gd")
const Geometry=preload("res://scripts/racing/RaceGeometry.gd")
var checks:=0
var failures: Array=[]
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok: failures.append(label);push_error(label)
func fixture() -> RefCounted:
	var s=Session.new()
	s.begin({"id":"sphere_test","type":"sprint","distance_m":20.0,"points_xz":[[0,20],[0,0]],"settings":{"countdown_s":0},"checkpoints":[{"position_xz":[0,0],"forward_xz":[0,-1],"half_width_m":5.0/Geometry.CHECKPOINT_SCALE,"distance_m":20.0,"edge_index":0}]})
	s.set_surface_heights(func(_x: float,_z: float):return 10.0)
	s.phase="running"
	return s
func run() -> void:
	var y:=10.0+Geometry.CENTER_HEIGHT_M
	var s=fixture()
	s.advance(Vector2(-8,3),Vector2(-3,3),0.1,true,y,y)
	check(s.phase=="finished","Sideways corner drift enters sphere without crossing checkpoint plane")
	check(absf(s.elapsed-0.08)<0.0001,"Finish time interpolates first sphere contact")
	s=fixture()
	s.advance(Vector2(-8,0),Vector2(8,0),0.1,true,y,y)
	check(s.phase=="finished","Swept sphere catches fast pass with both endpoints outside")
	check(absf(s.elapsed-0.01875)<0.0001,"Fast swept contact has exact fractional time")
	s=fixture()
	s.advance(Vector2(-1,0),Vector2(1,0),0.1,true,y+6,y+6)
	check(s.next_checkpoint==0,"Passing above sphere is rejected even with height_valid true")
	s.advance(Vector2(4,1),Vector2(4,-1),0.1,true,y+4,y+4)
	check(s.next_checkpoint==0,"Combined horizontal/vertical distance uses sphere, not cylinder")
	s.advance(Vector2(-1,0),Vector2(1,0),0.1,true,y+4.5,y+4.5)
	check(s.phase=="finished","Supported hop inside sphere is accepted")
	s=fixture()
	s.advance(Vector2(0,-8),Vector2(0,8),0.1,true,y,y)
	check(s.next_checkpoint==0,"Reverse traversal does not count")
	s.advance(Vector2.ZERO,Vector2.ZERO,0.1,true,y,y)
	check(s.next_checkpoint==0,"Stationary car inside sphere does not count")
	s.advance(Vector2(0,100),Vector2(0,-100),0.016,true,y,y)
	check(s.next_checkpoint==0 and s.invalid_crossings==1,"Teleport through sphere is rejected")
	s.advance(Vector2(0,1),Vector2(0,-1),0.1,false,y,y)
	check(s.next_checkpoint==0,"Recovery/unsupported height guard remains effective")
	s=fixture()
	var second: Dictionary=s.definition["checkpoints"][0].duplicate(true)
	second["position_xz"]=[0,-2]
	second["distance_m"]=22.0
	s.definition["checkpoints"].append(second)
	s.checkpoint_heights.append(y)
	s.advance(Vector2(0,6),Vector2(0,-1),0.1,true,y,y)
	check(s.phase=="finished" and s.next_checkpoint==2,"Overlapping spheres advance in order in the same physical step")
	s=fixture()
	second=s.definition["checkpoints"][0].duplicate(true)
	second["position_xz"]=[0,-40]
	s.definition["checkpoints"].append(second)
	s.checkpoint_heights.append(y)
	s.advance(Vector2(0,-39),Vector2(0,-41),0.1,true,y,y)
	check(s.next_checkpoint==0,"Entering a later sphere cannot skip the mandatory checkpoint")
	var report:={"passed":failures.is_empty(),"checks":checks,"failures":failures,"trigger":"swept 3D sphere","radius_m":5.0}
	FileAccess.open("res://.local/artifacts/checkpoint_spheres_validation.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("CHECKPOINT_SPHERES ",JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)

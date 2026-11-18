extends Node3D
# Cosmetic water over the existing OSM-derived triangles. The same boundary
# supplies physical coastal walls; no new shoreline or bathymetry is inferred.
var world: Node3D
var visual: MeshInstance3D
var barrier: StaticBody3D
var particles: CPUParticles3D
var triangles: Array[PackedVector2Array]=[]
var triangle_bounds: Array[Rect2]=[]
var boundary: Array=[]
var effects_enabled:=true
var flat: StandardMaterial3D
var animated: ShaderMaterial
var timer:=0.0
var last_anchor:=Vector2(INF,INF)
var rng:=RandomNumberGenerator.new()
var boundary_count:=0

func edge_key(p: Vector2) -> String:return "%.5f,%.5f" % [p.x,p.y]

func configure(target: Node3D, data: Dictionary) -> void:
	world=target;rng.seed=937
	var vertices:=PackedVector3Array();var normals:=PackedVector3Array();var edges: Dictionary={}
	for surface in data["surfaces"]:
		for tri in surface["triangles_xz"]:
			var polygon:=PackedVector2Array()
			for at in tri:
				var p:=Vector2(at[0],at[1]);polygon.append(p)
				vertices.append(Vector3(p.x,float(surface["y"]),p.y));normals.append(Vector3.UP)
			triangles.append(polygon)
			var rect:=Rect2(polygon[0],Vector2.ZERO)
			for p in polygon:rect=rect.expand(p)
			triangle_bounds.append(rect.grow(.001))
			for i in range(3):
				var a:=polygon[i];var b:=polygon[(i+1)%3];var ka:=edge_key(a);var kb:=edge_key(b)
				var key:=ka+"|"+kb if ka<kb else kb+"|"+ka
				if edges.has(key):edges[key]["count"]+=1
				else:edges[key]={"a":a,"b":b,"count":1}
	if vertices.is_empty():return
	var arrays:=[];arrays.resize(Mesh.ARRAY_MAX);arrays[Mesh.ARRAY_VERTEX]=vertices;arrays[Mesh.ARRAY_NORMAL]=normals
	var mesh:=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	visual=MeshInstance3D.new();visual.name="WaterSurface";visual.mesh=mesh;visual.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;add_child(visual)
	animated=ShaderMaterial.new();animated.shader=preload("res://shaders/coast_water.gdshader")
	flat=StandardMaterial3D.new();flat.albedo_color=Color("397f99");flat.cull_mode=BaseMaterial3D.CULL_DISABLED
	barrier=StaticBody3D.new();barrier.name="CoastalBarrier";barrier.collision_layer=8;barrier.collision_mask=16;add_child(barrier)
	var rails:=PackedVector3Array()
	for entry in edges.values():
		if entry["count"]!=1:continue
		var a: Vector2=entry["a"];var b: Vector2=entry["b"]
		if a.distance_to(b)<.02:continue
		boundary.append([a,b]);boundary_count+=1
		var side:=Vector2(-(b-a).y,(b-a).x).normalized()
		var mid: Vector2=(a+b)*.5
		if not contains_water(mid+side*.5):side=-side
		var center: Vector2=mid+side*.25
		var collision:=CollisionShape3D.new();var shape:=BoxShape3D.new()
		shape.size=Vector3(.5,520,a.distance_to(b)+.02);collision.shape=shape
		collision.position=Vector3(center.x,252,center.y);collision.rotation.y=atan2((b-a).x,(b-a).y);barrier.add_child(collision)
		# A low neon rail makes the otherwise invisible safety boundary readable.
		for h in [.85,1.10]:
			var lo:=Vector3(a.x,h,a.y);var hi:=Vector3(b.x,h,b.y)
			var up:=Vector3.UP*.055
			rails.append_array(PackedVector3Array([lo,hi,hi+up,lo,hi+up,lo+up]))
	var rail_arrays:=[];rail_arrays.resize(Mesh.ARRAY_MAX);rail_arrays[Mesh.ARRAY_VERTEX]=rails
	var rail_mesh:=ArrayMesh.new();rail_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,rail_arrays)
	var rail:=MeshInstance3D.new();rail.mesh=rail_mesh;rail.name="CoastalNeonRail";rail.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat:=StandardMaterial3D.new();mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;mat.albedo_color=Color("21cde0");mat.cull_mode=BaseMaterial3D.CULL_DISABLED;rail.material_override=mat;add_child(rail)
	particles=CPUParticles3D.new();particles.name="WaterSparkles";particles.amount=48;particles.lifetime=2.4;particles.gravity=Vector3.ZERO
	particles.emission_shape=CPUParticles3D.EMISSION_SHAPE_POINTS;particles.direction=Vector3.UP;particles.spread=20;particles.initial_velocity_min=.03;particles.initial_velocity_max=.12
	particles.local_coords=false;particles.scale_amount_min=.65;particles.scale_amount_max=1.4
	var quad:=QuadMesh.new();quad.size=Vector2(.14,.14)
	var glint:=StandardMaterial3D.new();glint.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;glint.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA;glint.billboard_mode=BaseMaterial3D.BILLBOARD_ENABLED
	glint.vertex_color_use_as_albedo=true;glint.albedo_color=Color("a3ffff");quad.material=glint;particles.mesh=quad
	var fade:=Gradient.new();fade.set_color(0,Color(1,1,1,0));fade.set_color(1,Color(1,1,1,0));fade.add_point(.25,Color(1,1,1,.7));particles.color_ramp=fade
	particles.emitting=false;add_child(particles);set_effects(true)

func contains_water(p: Vector2) -> bool:
	for i in range(triangles.size()):
		if triangle_bounds[i].has_point(p) and Geometry2D.is_point_in_polygon(p,triangles[i]):return true
	return false

func set_effects(enabled: bool) -> void:
	effects_enabled=enabled
	if visual!=null:visual.material_override=animated if enabled else flat
	if particles!=null:particles.visible=enabled;particles.emitting=false
	last_anchor=Vector2(INF,INF)
	timer=0

func _process(delta: float) -> void:
	if not effects_enabled or world.player==null or particles==null:return
	timer-=delta
	if timer>0:return
	timer=.75
	var at:=Vector2(world.player.position.x,world.player.position.z)
	if at.distance_squared_to(last_anchor)<24*24:return
	last_anchor=at
	var nearest:=INF
	for edge in boundary:nearest=minf(nearest,at.distance_squared_to(Geometry2D.get_closest_point_to_segment(at,edge[0],edge[1])))
	if nearest>100*100 and not contains_water(at):particles.emitting=false;return
	var points:=PackedVector3Array()
	for i in range(96):
		var p:=at+Vector2(rng.randf_range(-55,55),rng.randf_range(-55,55))
		if contains_water(p):points.append(Vector3(p.x-at.x,.10,p.y-at.y))
	particles.position=Vector3(at.x,0,at.y);particles.emission_points=points;particles.emitting=not points.is_empty()

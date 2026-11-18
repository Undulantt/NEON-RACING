extends SubViewportContainer
var viewport: SubViewport
var pivot: Node3D
var camera: Camera3D
var top_light: SpotLight3D
var models: Dictionary={}
var selected_id:=""
var dragging:=false
var resume_delay:=0.0
var camera_distance:=9.7
var rotation_speed:=.14

func configure() -> void:
	stretch=true;mouse_filter=Control.MOUSE_FILTER_STOP
	tooltip_text="Arrastra para girar el coche · Rueda para acercar o alejar"
	viewport=SubViewport.new();viewport.size=Vector2i(540,630);viewport.own_world_3d=true
	viewport.transparent_bg=true;viewport.gui_disable_input=true;viewport.msaa_3d=Viewport.MSAA_2X
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;add_child(viewport)
	var stage:=Node3D.new();stage.name="VehicleShowroom";viewport.add_child(stage)
	var environment:=WorldEnvironment.new();var settings:=Environment.new()
	settings.background_mode=Environment.BG_CLEAR_COLOR;settings.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color=Color("a6b8e9");settings.ambient_light_energy=.55
	environment.environment=settings;stage.add_child(environment)
	pivot=Node3D.new();pivot.rotation.y=-.35;stage.add_child(pivot)
	var floor_mesh:=CylinderMesh.new();floor_mesh.top_radius=2.8;floor_mesh.bottom_radius=2.8;floor_mesh.height=.08;floor_mesh.radial_segments=64
	var floor_visual:=MeshInstance3D.new();floor_visual.mesh=floor_mesh;floor_visual.position.y=-.05
	var floor_mat:=StandardMaterial3D.new();floor_mat.albedo_color=Color("141421");floor_mat.metallic=.35;floor_mat.roughness=.4
	floor_mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;floor_mat.albedo_color=Color("100c1c")
	floor_visual.material_override=floor_mat;stage.add_child(floor_visual)
	var ring:=MeshInstance3D.new();var ring_mesh:=TorusMesh.new();ring_mesh.inner_radius=2.55;ring_mesh.outer_radius=2.59;ring_mesh.rings=64;ring_mesh.ring_segments=8
	ring.mesh=ring_mesh;ring.position.y=.015
	var neon:=StandardMaterial3D.new();neon.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;neon.albedo_color=Color("00e5ee")
	neon.emission_enabled=true;neon.emission=Color("00e5ee");neon.emission_energy_multiplier=2
	ring.material_override=neon;stage.add_child(ring)
	var tube:=MeshInstance3D.new();var bar:=BoxMesh.new();bar.size=Vector3(3.6,.055,.09);tube.mesh=bar;tube.position=Vector3(0,2.8,0);tube.material_override=neon;stage.add_child(tube)
	top_light=SpotLight3D.new();top_light.name="OverheadNeon";top_light.position=Vector3(0,2.75,0);top_light.rotation.x=-PI/2
	top_light.light_color=Color("56e8ff");top_light.light_energy=2.2;top_light.spot_range=9;top_light.spot_angle=65;top_light.shadow_enabled=false;stage.add_child(top_light)
	var rim:=OmniLight3D.new();rim.position=Vector3(-3,1.6,2);rim.light_color=Color("ff38be");rim.light_energy=2.2;rim.omni_range=9;rim.shadow_enabled=false;stage.add_child(rim)
	var key:=DirectionalLight3D.new();key.rotation_degrees=Vector3(-40,-25,0);key.light_color=Color("dbedff");key.light_energy=.8;key.shadow_enabled=false;stage.add_child(key)
	camera=Camera3D.new();camera.fov=40;camera.near=.05;camera.far=40;stage.add_child(camera);_place_camera()
	visibility_changed.connect(_visibility_changed)
	get_window().focus_exited.connect(_release_drag)

func _release_drag() -> void:
	dragging=false;resume_delay=2.0

func _place_camera() -> void:
	camera.position=Vector3(5.7,3.1,-6.5).normalized()*camera_distance
	camera.look_at(Vector3(0,.75,0),Vector3.UP)

func select_model(id: String) -> void:
	if selected_id==id:return
	for model in models.values():model.hide()
	if not models.has(id):
		var model:=Node3D.new();model.name=id+"Preview";pivot.add_child(model)
		preload("res://scripts/driving/CarVisual.gd").build(model,id)
		var bounds:=AABB();var first:=true
		for visual in model.find_children("*","MeshInstance3D",true,false):
			if not visual.is_visible_in_tree() or visual.mesh==null:continue
			var local: Transform3D=model.global_transform.affine_inverse()*visual.global_transform
			var box: AABB=local*visual.get_aabb()
			bounds=box if first else bounds.merge(box);first=false
		var scale_factor:=4.8/maxf(.1,maxf(bounds.size.x,bounds.size.z))
		model.scale=Vector3.ONE*scale_factor
		model.position=Vector3(-bounds.get_center().x*scale_factor,-bounds.position.y*scale_factor+.055,-bounds.get_center().z*scale_factor)
		models[id]=model
	models[id].show();selected_id=id;dragging=false

func _process(delta: float) -> void:
	if not is_visible_in_tree() or pivot==null:return
	resume_delay=maxf(0,resume_delay-delta)
	if not dragging and resume_delay<=0:pivot.rotation.y+=rotation_speed*delta

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index in [MOUSE_BUTTON_LEFT,MOUSE_BUTTON_RIGHT]:
			dragging=event.pressed;resume_delay=2.0;accept_event()
		elif event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
			camera_distance=clampf(camera_distance+(-.45 if event.button_index==MOUSE_BUTTON_WHEEL_UP else .45),6.8,11.0);_place_camera();accept_event()
	elif event is InputEventMouseMotion and dragging:
		pivot.rotation.y+=event.relative.x*.012;resume_delay=2.0;accept_event()

func _visibility_changed() -> void:
	if viewport!=null:viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS if is_visible_in_tree() else SubViewport.UPDATE_DISABLED
	if not is_visible_in_tree():dragging=false

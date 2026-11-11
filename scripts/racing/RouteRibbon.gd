extends MeshInstance3D
# Metric-width ribbon instead of one-pixel GPU lines. No collision geometry.
const COLOR := Color("ff790f")
const WIDTH_M := 0.8

func configure(world: Node3D, points: Array, width := WIDTH_M) -> void:
	var vertices := PackedVector3Array()
	for i in range(points.size()-1):
		var a := Vector2(points[i][0],points[i][1])
		var b := Vector2(points[i+1][0],points[i+1][1])
		if a.distance_squared_to(b)<0.0001: continue
		var side := (b-a).normalized().orthogonal()*width*0.5
		var count := maxi(1,ceili(a.distance_to(b)/4.0))
		for j in range(count):
			var p := a.lerp(b,float(j)/count)
			var q := a.lerp(b,float(j+1)/count)
			var corners: Array[Vector3] = []
			for at in [p-side,p+side,q+side,q-side]:
				corners.append(Vector3(at.x,world.player.surface_height(at.x,at.y)+0.18,at.y))
			for index in [0,1,2,0,2,3]: vertices.append(corners[index])
	if vertices.is_empty(): return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	var ribbon := ArrayMesh.new()
	ribbon.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	mesh = ribbon
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = COLOR
	material.emission_enabled = true
	material.emission = COLOR
	material.emission_energy_multiplier = 2.0
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material_override = material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

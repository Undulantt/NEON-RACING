extends RefCounted
# Shared continuous geometry. Checkpoints are only mapped for validation/recovery;
# sampling, curvature and steering never advance from one gate to the next.
var points := PackedVector2Array()
var distances := PackedFloat32Array()
var widths := PackedFloat32Array()
var curvature := PackedFloat32Array()
var gate_distances := PackedFloat32Array()
var source_distances := PackedFloat32Array()
var source_route_distances := PackedFloat32Array()
var turnarounds: Array=[]
var turn_reservations: Dictionary={}
var left_limits := PackedFloat32Array()
var right_limits := PackedFloat32Array()
var road_portals: Array=[]
var unloaded_corridors: Dictionary={}
var length := 0.0
var closed := false
var rounded_corners := 0
var fallback_corners := 0
var max_static_checks := 0
var corner_radius_m := 12.0

func configure(data: Dictionary, probe: CharacterBody3D = null) -> void:
	points.clear()
	distances.clear()
	widths.clear()
	curvature.clear()
	gate_distances.clear()
	source_distances.clear();source_route_distances.clear()
	turnarounds.clear()
	turn_reservations.clear()
	left_limits.clear()
	right_limits.clear()
	road_portals.clear();unloaded_corridors.clear()
	length=0.0
	rounded_corners=0
	fallback_corners=0
	max_static_checks=0
	closed=data.get("type")=="circuit"
	var original: Array=data["points_xz"]
	var source: Array[Vector2]=[]
	var source_widths: Array[float]=[]
	for i in range(original.size()):
		source.append(Vector2(original[i][0],original[i][1]))
		source_distances.append(0.0 if i==0 else source_distances[-1]+source[-2].distance_to(source[-1]))
	for i in range(source.size()-1):
		var half:=3.5
		for gate in data["checkpoints"]:
			if int(gate.get("edge_index",0))==i:
				half=float(gate["half_width_m"])
				break
		source_widths.append(half)
		road_portals.append({"position":source[i+1],"forward":(source[i+1]-source[i]).normalized(),"half":half*preload("res://scripts/racing/RaceGeometry.gd").CHECKPOINT_SCALE-0.3})
	# Drop only effectively collinear OSM subdivision nodes; preserve bends.
	var i:=1
	while i<source.size()-1:
		var a: Vector2=(source[i]-source[i-1]).normalized()
		var b: Vector2=(source[i+1]-source[i]).normalized()
		if a.dot(b)>0.9998:
			source.remove_at(i)
			source_distances.remove_at(i)
			source_widths[i-1]=minf(source_widths[i-1],source_widths[i])
			source_widths.remove_at(i)
		else: i+=1
	if closed: source.remove_at(source.size()-1)
	var corners: Array=[]
	for index in range(source.size()):
		var v: Vector2=source[index]
		var simple:={"entry":v,"exit":v,"curve":PackedVector2Array([v])}
		if not closed and (index==0 or index==source.size()-1):
			corners.append(simple)
			continue
		var before: Vector2=source[posmod(index-1,source.size())]
		var after: Vector2=source[(index+1)%source.size()]
		var incoming: Vector2=(v-before).normalized()
		var outgoing: Vector2=(after-v).normalized()
		var angle:=acos(clampf(incoming.dot(outgoing),-1,1))
		if angle<0.045 or angle>2.6:
			corners.append(simple)
			continue
		var half:=minf(source_widths[posmod(index-1,source_widths.size())],source_widths[index%source_widths.size()])
		var outside:=minf(2.2,maxf(0,half-1.2))*smoothstep(0.25,1.0,angle)
		var side:=signf(incoming.cross(outgoing))
		var inward: Vector2=(Vector2(-incoming.y,incoming.x)+Vector2(-outgoing.y,outgoing.x)).normalized()*side
		var offset_vertex: Vector2=v-inward*(outside/maxf(0.2,cos(angle*0.5)))
		var radius:=minf(corner_radius_m,minf(v.distance_to(before),v.distance_to(after))*0.4/maxf(0.01,tan(angle*0.5)))
		var cut:=radius*tan(angle*0.5)
		var entry: Vector2=offset_vertex-incoming*cut
		var exit: Vector2=offset_vertex+outgoing*cut
		var handle:=4.0/3.0*radius*tan(angle*0.25)
		var c1: Vector2=entry+incoming*handle
		var c2: Vector2=exit-outgoing*handle
		var curve:=PackedVector2Array()
		var count:=maxi(4,ceili(radius*angle/1.5))
		for step in range(count+1):
			var t:=float(step)/count
			var u:=1.0-t
			curve.append(entry*u*u*u+c1*3*u*u*t+c2*3*u*t*t+exit*t*t*t)
		if probe!=null and not static_curve_safe(curve,probe):
			fallback_corners+=1
			corners.append(simple)
		else:
			rounded_corners+=1
			corners.append({"entry":entry,"exit":exit,"curve":curve})
	var edge_count:=source.size() if closed else source.size()-1
	append_point(corners[0]["exit"],source_widths[0])
	source_route_distances.append(length)
	for index in range(edge_count):
		var next: int=(index+1)%source.size()
		append_line(corners[index]["exit"],corners[next]["entry"],source_widths[index%source_widths.size()])
		var corner_width:=minf(source_widths[index%source_widths.size()],source_widths[next%source_widths.size()])
		var curve: PackedVector2Array=corners[next]["curve"]
		for step in range(1,curve.size()): append_point(curve[step],corner_width)
		source_route_distances.append(length)
	for index in range(points.size()):
		var previous:=posmod(index-1,points.size()-1) if closed else maxi(0,index-1)
		var next: int=(index+1)%(points.size()-1) if closed else mini(points.size()-1,index+1)
		var a: Vector2=(points[index]-points[previous]).normalized()
		var b: Vector2=(points[next]-points[index]).normalized()
		var span:=maxf(0.5,(points[previous].distance_to(points[index])+points[index].distance_to(points[next]))*0.5)
		curvature.append(a.angle_to(b)/span)
	build_corridors(probe)
	for gate in data["checkpoints"]:
		var p:=Vector2(gate["position_xz"][0],gate["position_xz"][1])
		var mapped: float
		if closed:mapped=project(p,-INF)["s"]
		else:
			var index:=source_index(float(gate["distance_m"]))
			# Original edge order disambiguates repeated streets and crossings.
			# Include the rounded corner before the edge's exit marker.
			mapped=project_interval(p,maxf(0,source_route_distances[index]-corner_radius_m*3),source_route_distances[index+1],map_progress(float(gate["distance_m"])),Vector2(gate["forward_xz"][0],gate["forward_xz"][1]))["s"]
		if closed and float(gate["distance_m"])>=float(data.get("lap_distance_m",data["distance_m"]))-0.01: mapped=length
		gate_distances.append(mapped)
	if not closed:
		for j in range(1,source.size()-1):
			var incoming: Vector2=(source[j]-source[j-1]).normalized()
			var outgoing: Vector2=(source[j+1]-source[j]).normalized()
			if incoming.dot(outgoing)<-.94:
				var at: float=source_route_distances[j]
				var retraced:=0.0
				# Reserve the complete shared access road, not just the turning
				# circle: oncoming cars otherwise meet nose-to-nose after exit.
				while retraced<minf(2000,minf(at,length-at)):
					if sample(at-retraced)["position"].distance_to(sample(at+retraced)["position"])>8:break
					retraced+=2
				turnarounds.append({"s":at,"source_s":source_distances[j],"position":source[j],"forward":outgoing,"approach_s":at-retraced-25,"clear_s":at+retraced+25})

func source_index(distance: float) -> int:
	return clampi(source_distances.bsearch(distance)-1,0,source_distances.size()-2)

func project_grid(p: Vector2) -> Dictionary:
	var frame:=sample(0)
	var offset: Vector2=p-points[0]
	var along: float=offset.dot(frame["forward"])
	if along>=0:return {}
	frame["s"]=along
	frame["lateral"]=offset.dot(Vector2(-frame["forward"].y,frame["forward"].x))
	frame["error"]=absf(frame["lateral"])
	return frame

func project_finish(p: Vector2) -> Dictionary:
	var frame:=sample(length)
	var offset: Vector2=p-points[-1]
	var along: float=offset.dot(frame["forward"])
	if along<=0:return {}
	frame["s"]=length+along
	frame["lateral"]=offset.dot(Vector2(-frame["forward"].y,frame["forward"].x))
	frame["error"]=absf(frame["lateral"])
	return frame

func map_progress(distance: float) -> float:
	var i:=source_index(distance)
	var t:=clampf((distance-source_distances[i])/maxf(.001,source_distances[i+1]-source_distances[i]),0,1)
	return lerpf(source_route_distances[i],source_route_distances[i+1],t)

func project_interval(p: Vector2, minimum: float, maximum: float, hint: float, direction:=Vector2.ZERO) -> Dictionary:
	var best:=INF;var best_s:=minimum;var best_point:=points[index_at(minimum)]
	for i in range(index_at(minimum),index_at(maximum)+1):
		var low:=maxf(minimum,distances[i]);var high:=minf(maximum,distances[i+1])
		if high<low:continue
		var a: Vector2=points[i].lerp(points[i+1],(low-distances[i])/maxf(.001,distances[i+1]-distances[i]))
		var b: Vector2=points[i].lerp(points[i+1],(high-distances[i])/maxf(.001,distances[i+1]-distances[i]))
		var at:=Geometry2D.get_closest_point_to_segment(p,a,b)
		var s:=low+a.distance_to(at)
		var score:=p.distance_squared_to(at)+absf(s-hint)*.0001
		if direction!=Vector2.ZERO and (points[i+1]-points[i]).normalized().dot(direction)<0:score+=1000
		if score<best:best=score;best_s=s;best_point=at
	var frame:=sample(best_s);frame["s"]=best_s;frame["error"]=p.distance_to(best_point)
	frame["lateral"]=(p-best_point).dot(Vector2(-frame["forward"].y,frame["forward"].x))
	return frame

func append_point(p: Vector2, half: float) -> void:
	if not points.is_empty():
		var step:=points[-1].distance_to(p)
		if step<0.001: return
		length+=step
	points.append(p)
	distances.append(length)
	widths.append(half)

func append_line(a: Vector2,b: Vector2,half: float) -> void:
	var count:=maxi(1,ceili(a.distance_to(b)/2.0))
	for index in range(1,count+1): append_point(a.lerp(b,float(index)/count),half)

func static_curve_safe(curve: PackedVector2Array, car: CharacterBody3D) -> bool:
	for index in range(curve.size()):
		var a: Vector2=curve[maxi(0,index-1)]
		var b: Vector2=curve[mini(curve.size()-1,index+1)]
		var direction: Vector2=(b-a).normalized()
		var p: Vector2=curve[index]
		var yaw:=atan2(-direction.x,-direction.y)
		var pose:=Transform3D(Basis(Vector3.UP,yaw),Vector3(p.x,car.supported_pose_height(p.x,p.y,yaw),p.y))
		var query:=PhysicsShapeQueryParameters3D.new()
		query.shape=car.collision_shape
		query.transform=pose
		query.collision_mask=12
		max_static_checks+=1
		if not car.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty(): return false
		for local in [Vector3.ZERO,Vector3(-0.85,0,-1.9),Vector3(0.85,0,-1.9),Vector3(-0.85,0,1.9),Vector3(0.85,0,1.9)]:
			if not car.road_hit(pose*(local*car.vehicle_scale)): return false
	return true

func corridor_limits(index: int, probe: CharacterBody3D) -> Array[float]:
	var next:=mini(index+1,points.size()-1)
	var previous:=maxi(0,index-1)
	var forward: Vector2=(points[next]-points[previous]).normalized()
	if forward.length_squared()<0.5: forward=(points[mini(1,points.size()-1)]-points[0]).normalized()
	var right:=Vector2(-forward.y,forward.x)
	var limits: Array[float]=[0.0,0.0]
	for side in [-1.0,1.0]:
		for amount in [0.5,1.0,1.5,2.0,2.5,3.0,3.5]:
			var offset: float=amount*side
			var q: Vector2=points[index]+right*offset
			if amount>float(widths[index])*preload("res://scripts/racing/RaceGeometry.gd").CHECKPOINT_SCALE-1.1 or (absf(curvature[index])>0.035 and amount>0.5): break
			var valid:=true
			# Road-segment end planes constrain legal corner entry; these
			# come from street geometry, independent of checkpoint spacing.
			for portal in road_portals:
				var relative: Vector2=q-portal["position"]
				if relative.length_squared()<196 and absf(relative.dot(portal["forward"]))<1.1 and absf(relative.cross(portal["forward"]))>float(portal["half"]):
					valid=false
					break
			if not valid: break
			if probe!=null:
				var yaw:=atan2(-forward.x,-forward.y)
				var pose:=Transform3D(Basis(Vector3.UP,yaw),Vector3(q.x,probe.supported_pose_height(q.x,q.y,yaw),q.y))
				var query:=PhysicsShapeQueryParameters3D.new()
				query.shape=probe.collision_shape
				query.transform=pose
				query.collision_mask=12
				query.margin=0.3
				max_static_checks+=1
				if not probe.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty(): break
				for local in [Vector3.ZERO,Vector3(-1.25,0,-2.2),Vector3(1.25,0,-2.2),Vector3(-1.25,0,2.2),Vector3(1.25,0,2.2)]:
					if not probe.road_hit(pose*(local*probe.vehicle_scale)):
						valid=false
						break
				if not valid: break
			limits[0 if side<0 else 1]=offset
	return limits

func build_corridors(probe: CharacterBody3D) -> void:
	for index in range(points.size()):
		var limits:=corridor_limits(index,probe)
		if probe!=null and not probe.road_hit(Vector3(points[index].x,probe.supported_pose_height(points[index].x,points[index].y,0),points[index].y)):unloaded_corridors[index]=true
		left_limits.append(limits[0])
		right_limits.append(limits[1])
	# Smooth conservative erosion: rounded transition envelopes stay within
	# every checked bound and avoid a kink when a lane narrows at a corner.
	var raw_left:=left_limits.duplicate()
	var raw_right:=right_limits.duplicate()
	for index in range(points.size()):
		for neighbor in range(points.size()):
			var gap:=absf(distances[index]-distances[neighbor])
			if closed: gap=minf(gap,length-gap)
			if gap>=25: continue
			var allowance:=1.75*(1.0-cos(PI*gap/25.0))
			left_limits[index]=maxf(left_limits[index],raw_left[neighbor]-allowance)
			right_limits[index]=minf(right_limits[index],raw_right[neighbor]+allowance)
	if closed:
		left_limits[-1]=left_limits[0]
		right_limits[-1]=right_limits[0]

func index_at(s: float) -> int:
	var value:=fposmod(s,length) if closed else clampf(s,0,length)
	var low:=0
	var high:=distances.size()-1
	while low<high:
		var middle: int=(low+high+1)/2
		if distances[middle]<=value: low=middle
		else: high=middle-1
	return mini(low,points.size()-2)

func refresh_streamed_corridors(s: float, probe: CharacterBody3D) -> void:
	if unloaded_corridors.is_empty():return
	var budget:=4
	for step in range(-6,73,2):
		var index:=index_at(s+step)
		if not unloaded_corridors.has(index):continue
		var p:=points[index]
		if not probe.road_hit(Vector3(p.x,probe.supported_pose_height(p.x,p.y,0),p.y)):continue
		var limits:=corridor_limits(index,probe)
		left_limits[index]=limits[0];right_limits[index]=limits[1]
		unloaded_corridors.erase(index);budget-=1
		if budget<=0:return

func sample(s: float, offset := 0.0) -> Dictionary:
	var requested_offset:=offset
	var value:=fposmod(s,length) if closed else clampf(s,0,length)
	var index:=index_at(value)
	var t:=clampf((value-distances[index])/maxf(0.001,distances[index+1]-distances[index]),0,1)
	var forward: Vector2=(points[index+1]-points[index]).normalized()
	var k: float=lerpf(curvature[index],curvature[index+1],t)
	# Alternative lines remain available through corners where the checked
	# road corridor allows them. Do not force every car back to one apex.
	var left:=lerpf(left_limits[index],left_limits[index+1],t)
	var right:=lerpf(right_limits[index],right_limits[index+1],t)
	var freedom:=maxf(absf(left),absf(right))
	offset=clampf(offset,left,right)
	var right_axis:=Vector2(-forward.y,forward.x)
	var p: Vector2=points[index].lerp(points[index+1],t)+right_axis*offset
	var before_offset:=clampf(offset,left_limits[index],right_limits[index])
	var after_offset:=clampf(offset,left_limits[index+1],right_limits[index+1])
	var derivative: float=(after_offset-before_offset)/maxf(0.1,distances[index+1]-distances[index])
	var scale:=maxf(0.35,1.0-k*offset)
	var line_forward: Vector2=(forward*scale+right_axis*derivative).normalized()
	var line_curvature:=k/scale
	if absf(requested_offset)>0.02:
		var before:=position_at(s-1.5,requested_offset)
		var after:=position_at(s+1.5,requested_offset)
		var a: Vector2=(p-before).normalized()
		var b: Vector2=(after-p).normalized()
		line_forward=(after-before).normalized()
		line_curvature=a.angle_to(b)/maxf(0.5,(before.distance_to(p)+p.distance_to(after))*0.5)
	return {"position":p,"forward":forward,"line_forward":line_forward,"curvature":line_curvature,"half_width":widths[index],"freedom":freedom,"left_limit":left,"right_limit":right,"offset":offset,"s":s}

func position_at(s: float, offset: float) -> Vector2:
	var value:=fposmod(s,length) if closed else clampf(s,0,length)
	var i:=index_at(value)
	var t:=clampf((value-distances[i])/maxf(0.001,distances[i+1]-distances[i]),0,1)
	var f: Vector2=(points[i+1]-points[i]).normalized()
	var allowed:=clampf(offset,lerpf(left_limits[i],left_limits[i+1],t),lerpf(right_limits[i],right_limits[i+1],t))
	return points[i].lerp(points[i+1],t)+Vector2(-f.y,f.x)*allowed

func project(p: Vector2, hint_s: float) -> Dictionary:
	var best:=INF
	var best_s:=0.0
	var best_point:=points[0]
	var index:=index_at(hint_s) if is_finite(hint_s) else 0
	var count:=points.size()-1
	var first:=index-22 if is_finite(hint_s) else 0
	var last:=index+35 if is_finite(hint_s) else count-1
	for raw in range(first,last+1):
		if not closed and (raw<0 or raw>=count): continue
		var i:=posmod(raw,count)
		var at:=Geometry2D.get_closest_point_to_segment(p,points[i],points[i+1])
		var error:=p.distance_squared_to(at)
		if error<best:
			best=error
			best_point=at
			best_s=distances[i]+points[i].distance_to(at)
	if closed and is_finite(hint_s): best_s+=roundf((hint_s-best_s)/length)*length
	var frame:=sample(best_s)
	frame["s"]=best_s
	frame["error"]=sqrt(best)
	frame["lateral"]=(p-best_point).dot(Vector2(-frame["forward"].y,frame["forward"].x))
	return frame

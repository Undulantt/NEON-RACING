extends RefCounted
const Trajectory = preload("res://scripts/racing/RaceTrajectory.gd")
var car: CharacterBody3D
var session: RefCounted
var trajectory: RefCounted
var personality: Dictionary
var personality_id := "balanced"
var target := Vector3.ZERO
var target_speed := 0.0
var state := "following"
var blocked_time := 0.0
var reverse_time := 0.0
var lane := 0.0
var participants: Array = []
var recovery_attempts := 0
var passing_car: CharacterBody3D
var pass_lane := 0.0
var nav_s := -INF
var best_nav_s := -INF
var no_progress_s := 0.0
var validation_recovery := false
var recovery_gate := -1
var recovery_approaching := true
var preferred_lane := 0.0
var steering_variation := 0.0
var previous_steer := 0.0
var sampled_frames := 0
var checkpoint_recoveries := 0
var route_error_peak := 0.0
var update_usec_total := 0
var update_usec_max := 0
var merge_hold_s := 0.0
var held_merges := 0
var completed_passes := 0
var merging_back := false
var cruise_speed_limit := INF
var allow_abilities := true
var validate_gates := true
var prefer_full_lane := false
var allow_passing := true
var expert := false
var pass_age := 0.0
var pass_lead_time := 0.0
var pass_cooldown := 0.0
var drift_phase := "ready"
var drift_elapsed := 0.0
var drift_cooldown := 0.0
var turnaround_index:=-1
var turnaround_done:=-1
var turnaround_reverse:=false
var turnaround_sign:=1.0
var turnaround_switch:=0.0
var turnarounds_completed:=0
var turnaround_stall:=0.0
var turnaround_position:=Vector2.ZERO
var arcade:=false
var tactics_rng:=RandomNumberGenerator.new()
var tactics_timer:=0.0
var line_choices:=0

func configure(vehicle: CharacterBody3D, progress: RefCounted, id: String, settings: Dictionary, shared: RefCounted = null) -> void:
	car=vehicle
	session=progress
	personality_id=id
	personality=settings
	expert=bool(settings.get("expert",false))
	car.set_meta("race_pilot",weakref(self))
	trajectory=shared
	if trajectory==null:
		trajectory=Trajectory.new()
		trajectory.configure(session.definition,car)
	if not trajectory.closed:
		# A grid car behind the starting line must not project onto a later
		# traversal of the same street. Official progress supplies the context.
		nav_s=trajectory.map_progress(session.progress_m)
		best_nav_s=nav_s
	car.external_control=true
	car.recovery_handler=func(_reason: String):
		reverse_time=2.0
		return true

func update(delta: float) -> void:
	if session.phase!="running":
		car.set_controls(0,0,false,false,1)
		return
	var started_usec:=Time.get_ticks_usec()
	var p:=Vector2(car.position.x,car.position.z)
	var frame: Dictionary
	if not trajectory.closed and is_finite(nav_s):
		var window:=maxf(3.0,car.speed_mps*delta*2+1.0)
		var lower: float=trajectory.turnarounds[turnaround_done]["s"]+.01 if turnaround_done>=0 else 0.0
		frame=trajectory.project_interval(p,maxf(lower,nav_s-window),maxf(lower,minf(trajectory.length,nav_s+window)),maxf(lower,nav_s))
		if turnaround_done<0 and nav_s<5:
			var grid: Dictionary=trajectory.project_grid(p)
			if not grid.is_empty():frame=grid
	else:frame=trajectory.project(p,nav_s)
	if not is_finite(nav_s):
		nav_s=frame["s"]
		if trajectory.closed and nav_s>trajectory.length*0.8 and p.distance_to(trajectory.points[0])<45: nav_s-=trajectory.length
		best_nav_s=nav_s
		frame=trajectory.project(p,nav_s)
	nav_s=frame["s"]
	route_error_peak=maxf(route_error_peak,float(frame["error"]))
	if not trajectory.closed and not car.road_hit(car.position) and float(frame["error"])>3:
		if rejoin_road(frame):return
	if drive_turnaround(delta,p,frame):return
	if arcade:update_tactics(delta,frame)
	var forward: Vector2=frame["forward"]
	var right:=Vector2(-forward.y,forward.x)
	var heading:=Vector2(-car.global_basis.z.x,-car.global_basis.z.z)
	var route_lateral: float=frame["lateral"]
	var straight_remaining:=straight_distance(nav_s)
	var desired_lane:=preferred_lane*float(frame["freedom"])/maxf(0.1,float(frame["half_width"])-1.2)
	if arcade:desired_lane=clampf(preferred_lane,float(frame["left_limit"]),float(frame["right_limit"]))
	if prefer_full_lane: desired_lane=clampf(preferred_lane,float(frame["left_limit"]),float(frame["right_limit"]))
	var obstacle_speed:=INF
	var yielding:=false
	state="racing_line"
	pass_cooldown=maxf(0,pass_cooldown-delta)
	if is_instance_valid(passing_car):
		var other_frame: Dictionary=traffic_frame(passing_car)
		var relative_s: float=other_frame["s"]-nav_s
		pass_age+=delta
		pass_lead_time=pass_lead_time+delta if relative_s< -7 and bool(passing_car.get_meta("race_competing",true)) else 0.0
		var confirmed:=pass_lead_time+0.000001>=0.5
		var unreachable:=car.position.distance_squared_to(passing_car.position)>3600 or (pass_age>8 and relative_s>20)
		if confirmed or unreachable or heading.dot(forward)<0.6:
			if confirmed: completed_passes+=1
			passing_car=null
			pass_cooldown=1.0
			merging_back=true
		else:
			desired_lane=pass_lane
			state="passing"
	for other in participants:
		if other==car or not is_instance_valid(other) or absf(other.position.y-car.position.y)>3: continue
		var other_p:=Vector2(other.position.x,other.position.z)
		if other_p.distance_squared_to(p)>pow(maxf(35,car.speed_mps*1.4),2): continue
		var other_frame: Dictionary=traffic_frame(other)
		var ahead: float=other_frame["s"]-nav_s
		var other_lateral: float=other_frame["lateral"]
		if ahead<=0 or ahead>maxf(25,car.speed_mps*1.2): continue
		if absf(other_lateral-route_lateral)>(1.8 if arcade else 2.1): continue
		var stopped: bool=other.speed_mps<1
		var gap:=3.8 if stopped else float(personality["gap"])
		var other_heading:=Vector2(-other.global_basis.z.x,-other.global_basis.z.z)
		if stopped and other_heading.dot(forward)<0.3 and ahead<9:
			gap=9.0
			yielding=true
			reverse_time=maxf(reverse_time,1.0)
		var following_speed:=maxf(0,other.speed_mps+(ahead-gap)*0.7)
		var passing_room:=1.8 if stopped or arcade else 2.4
		if allow_passing and pass_cooldown<=0 and (arcade or personality["overtake"] or stopped or (expert and car.speed_mps>other.speed_mps+2)) and straight_remaining>(12 if stopped else 22 if arcade else 35) and float(frame["freedom"])>passing_room and heading.dot(forward)>0.94 and not is_instance_valid(passing_car):
			var offset:=minf(3.5,float(frame["freedom"]))
			var best_score:=INF
			var selected:=0.0
			for candidate in [-offset,0.0,offset]:
				if absf(candidate-other_lateral)<(1.8 if stopped else 2.0 if arcade else 2.3): continue
				if lane_clear(candidate,p,nav_s):
					var score: float=absf(candidate-route_lateral)*0.4+absf(candidate-preferred_lane)*0.25
					if arcade:score+=tactics_rng.randf_range(0,.35)
					if score<best_score:
						best_score=score
						selected=candidate
			if is_finite(best_score):
				passing_car=other
				pass_age=0
				pass_lead_time=0
				pass_lane=selected
				desired_lane=selected
				state="passing"
		# A stationary obstacle needs forward motion to steer around it. Keeping
		# the normal following gap here deadlocks a car already committed to a
		# clear side corridor; collision/pose guards still constrain each step.
		if other==passing_car and ahead>2.0: following_speed=maxf(following_speed,2.5)
		if arcade and other==passing_car and ahead>maxf(8,car.speed_mps*.4):following_speed=maxf(following_speed,other.speed_mps+2.5)
		obstacle_speed=minf(obstacle_speed,following_speed)
	# Returning to a preferred line is optional: hold the current corridor if
	# an adjacent car occupies the merge, even after the original pass ended.
	if absf(route_lateral-preferred_lane)<0.4: merging_back=false
	merge_hold_s=maxf(0,merge_hold_s-delta)
	if merging_back and not is_instance_valid(passing_car) and absf(desired_lane-route_lateral)>0.4:
		if not merge_clear(desired_lane,route_lateral,nav_s):
			if merge_hold_s<=0: held_merges+=1
			merge_hold_s=0.6
		if merge_hold_s>0:
			desired_lane=route_lateral
			state="holding_line"
	lane=move_toward(lane,desired_lane,delta*float(personality.get("lane_change_mps",1.8)))
	var lookahead:=clampf(5.0+car.speed_mps*0.3,5.0,17.0)
	if straight_remaining<20: lookahead=minf(lookahead,8.0)
	if is_instance_valid(passing_car) and passing_car.speed_mps<1: lookahead=clampf(car.speed_mps*0.45,3.5,10.0)
	var used_lane: float=lane
	var aim_frame: Dictionary=trajectory.sample(nav_s+lookahead,used_lane)
	var aim: Vector2=aim_frame["position"]
	# A rounded racing line must still enter the next mandatory sphere. Blend
	# the final approach toward its centre before it becomes a missed gate.
	if not trajectory.closed and validate_gates:
		var gate: Dictionary=session.definition["checkpoints"][session.next_checkpoint]
		var gate_at:=Vector2(gate["position_xz"][0],gate["position_xz"][1])
		var gate_s: float=trajectory.gate_distances[session.next_checkpoint]
		if gate_s-nav_s>=-3 and gate_s-nav_s<lookahead+6:
			var gate_forward:=Vector2(gate["forward_xz"][0],gate["forward_xz"][1])
			var gate_side:=Vector2(-gate_forward.y,gate_forward.x)
			var allowance:=maxf(0,preload("res://scripts/racing/RaceGeometry.gd").half_width(gate)-1.2)
			aim=gate_at+gate_forward*1.0+gate_side*clampf(used_lane,-allowance,allowance)
	# Correct a missed mandatory gate only as an exceptional recovery. Normal
	# racing follows arc length even if checkpoint spacing/density changes.
	var gate_key: int=session.completed_laps*session.definition["checkpoints"].size()+session.next_checkpoint
	var expected: float=trajectory.gate_distances[session.next_checkpoint]+session.completed_laps*trajectory.length
	if validation_recovery and recovery_gate!=gate_key: validation_recovery=false
	if validate_gates and not validation_recovery and nav_s>expected+9.0:
		validation_recovery=true
		recovery_gate=gate_key
		recovery_approaching=true
		checkpoint_recoveries+=1
	if validation_recovery:
		if nav_s<=expected-3.5: recovery_approaching=false
		var recover_s:=maxf(expected-5.0,nav_s-lookahead) if recovery_approaching else nav_s+lookahead
		aim=trajectory.sample(recover_s)["position"]
		if recovery_approaching and heading.dot(forward)>0.5: reverse_time=maxf(reverse_time,0.25)
		state="checkpoint_recovery"
	target=Vector3(aim.x,car.position.y,aim.y)
	var local: Vector3=car.global_basis.inverse()*(target-car.position)
	var angle:=atan2(local.x,-local.z)
	var reduction:=lerpf(1.0,1.0-float(car.config["steering_reduction_at_high_speed"]),clampf(car.speed_mps/float(car.config["max_forward_speed_mps"]),0,1))
	var wheel_angle:=atan(2.0*float(car.config["wheelbase_m"])*local.x/maxf(1.0,Vector2(local.x,local.z).length_squared()))
	var steer:=clampf(wheel_angle/maxf(0.05,float(car.config["max_steer_radians"])*float(car.config["steering_sensitivity"])*reduction),-1,1)
	if absf(angle)>0.8 or (is_instance_valid(passing_car) and passing_car.speed_mps<1 and car.speed_mps<8): steer=clampf(angle*1.6,-1,1)
	target_speed=minf(planned_speed(nav_s,used_lane),cruise_speed_limit)
	if absf(angle)>1.4 or float(frame["error"])>8: target_speed=minf(target_speed,4.0)
	if validation_recovery: target_speed=minf(target_speed,4.0)
	if absf(route_lateral-float(aim_frame["offset"]))>2.0 and drift_phase=="ready": target_speed=minf(target_speed,10.0)
	if not arcade and not expert and absf(lane)>0.8 and not is_instance_valid(passing_car): target_speed=minf(target_speed,12.0)
	if is_instance_valid(passing_car) and passing_car.speed_mps<1: target_speed=minf(target_speed,12.0)
	target_speed=minf(target_speed,obstacle_speed)
	var ray:=PhysicsRayQueryParameters3D.create(car.position,car.position-car.global_basis.z*maxf(4,car.speed_mps*0.8),12,[car.get_rid()])
	if not car.get_world_3d().direct_space_state.intersect_ray(ray).is_empty(): target_speed=minf(target_speed,2.0)
	# A blocked lane is a traffic queue, not a loss of navigation. Never
	# reverse into following cars simply because the leader is stationary.
	if obstacle_speed<1 and car.speed_mps<.5 and not validation_recovery:
		blocked_time=0;no_progress_s=0;reverse_time=0
		state="waiting_traffic";car.set_controls(0,0,true);return
	if nav_s>best_nav_s+0.8:
		best_nav_s=nav_s
		no_progress_s=0
	else: no_progress_s+=delta
	if (absf(angle)>1.2 or float(frame["error"])>5) and car.speed_mps<8:
		var nose:=car.position-car.global_basis.z*2.5
		nose.y=car.supported_pose_height(nose.x,nose.z,car.rotation.y)
		if not car.road_hit(nose): reverse_time=maxf(reverse_time,1.0)
	if car.speed_mps<0.5: blocked_time+=delta
	else: blocked_time=0
	if blocked_time>4 or (no_progress_s>10 and absf(angle)>1.0):
		reverse_time=1.7
		blocked_time=0
		no_progress_s=0
		recovery_attempts+=1
	if reverse_time>0:
		reverse_time-=delta
		var behind:=car.position+car.global_basis.z*2.0
		behind.y=car.supported_pose_height(behind.x,behind.z,car.rotation.y)
		var rear_pose: Transform3D=car.global_transform
		rear_pose.origin+=car.global_basis.z*0.12
		if reverse_step_clear(rear_pose) and car.road_hit(behind):
			state="reversing"
			var back_steer:=clampf(atan2(local.x,local.z)*1.6,-1,1) if validation_recovery and recovery_approaching else -clampf(angle*1.6,-1,1)
			if car.signed_speed>.3 or car.speed_mps>2.5:car.set_controls(0,back_steer,true)
			else:car.set_controls(-0.55,back_steer)
		else:
			var front_pose: Transform3D=car.global_transform
			front_pose.origin-=car.global_basis.z*0.12
			var front:=car.position-car.global_basis.z*2.0
			front.y=car.supported_pose_height(front.x,front.z,car.rotation.y)
			if not yielding and reverse_step_clear(front_pose) and car.road_hit(front):
				state="forward_escape"
				car.set_controls(0.45,clampf(angle*1.6,-1,1))
			else:
				state="boxed_in"
				car.set_controls(0,0,true)
		return
	# Brake/reverse is one input in this arcade controller. Braking a vehicle
	# still rolling backwards would accelerate it backwards, not stop it.
	if car.signed_speed<-.2:
		state="stopping_reverse";car.set_controls(0,0,true);return
	if target_speed<0.1 and car.speed_mps<0.5:
		state="waiting"
		car.set_controls(0,0,true)
		return
	var throttle:=float(personality["throttle"]) if car.speed_mps<target_speed else 0.0
	if target_speed>=car.current_speed_cap-0.1 and obstacle_speed==INF:
		throttle=1.0 if car.speed_mps>car.base_speed_cap*0.9 else float(personality["throttle"])
	var brake:=clampf((car.speed_mps-target_speed)*0.85,0,1)
	# Sustain the real ability input through preparation instead of tapping
	# the brake at the nominal cap. Corner/traffic planning still has priority.
	if arcade and allow_abilities and obstacle_speed==INF and straight_remaining>car.speed_mps*.8+12 and target_speed>=car.base_speed_cap*.9 and absf(angle)<.12 and car.speed_mps<target_speed+1:
		throttle=1.0;brake=0.0
	var turbo: bool=allow_abilities and straight_remaining>car.speed_mps*2.0+18 and target_speed>car.speed_mps+4 and absf(angle)<0.12 and car.turbo_charge>float(personality["turbo_reserve"]) and obstacle_speed==INF
	var drift: bool=allow_abilities and personality_id=="aggressive" and absf(angle)>0.15 and absf(angle)<0.3 and car.speed_mps>float(car.config["drift_min_speed_mps"])+1 and target_speed>16 and float(frame["half_width"])>6
	if expert:
		var drift_input:=expert_drift(delta,frame,steer,obstacle_speed)
		drift=drift_input["handbrake"]
		steer=drift_input["steer"]
		if drift:
			throttle=1.0
			brake=0.0
			turbo=false
		elif drift_phase in ["settling","boost_exit"] and obstacle_speed==INF and float(frame["error"])<2.3 and car.speed_mps<target_speed+3:
			# A clean release must align the tyres before requesting the reward;
			# an avoidable brake tap here would discard genuinely earned charge.
			throttle=1.0
			brake=0.0
			turbo=false
	steering_variation+=absf(steer-previous_steer)
	previous_steer=steer
	sampled_frames+=1
	car.set_controls(throttle,steer,drift,turbo,brake)
	var cost:=Time.get_ticks_usec()-started_usec
	update_usec_total+=cost
	update_usec_max=maxi(update_usec_max,cost)

func straight_distance(at_s: float) -> float:
	for step in range(0,80,4):
		var frame: Dictionary=trajectory.sample(at_s+step)
		if absf(float(frame["curvature"]))>0.025: return float(step)
	return 80.0

func update_tactics(delta: float, frame: Dictionary) -> void:
	tactics_timer-=delta
	if tactics_timer>0 or is_instance_valid(passing_car) or validation_recovery:return
	tactics_timer=tactics_rng.randf_range(3.5,6.0)
	var options: Array=[-2.0,0.0,2.0]
	var first:=tactics_rng.randi_range(0,2)
	for i in range(3):
		var wanted: float=options[(first+i)%3]
		var candidate:=clampf(float(wanted),float(frame["left_limit"]),float(frame["right_limit"]))
		if absf(candidate-preferred_lane)<.7:continue
		if lane_clear(candidate,Vector2(car.position.x,car.position.z),nav_s):
			preferred_lane=candidate;line_choices+=1;return

func rejoin_road(frame: Dictionary) -> bool:
	var road: Vector2=frame["position"]
	var local: Vector3=car.global_basis.inverse()*(Vector3(road.x,car.position.y,road.y)-car.position)
	var angle:=atan2(local.x,-local.z)
	var direction:=1.0 if absf(angle)<1.4 else -1.0
	var steer:=clampf(angle*1.6,-1,1)*direction
	var pose:=car.global_transform
	pose.origin-=car.global_basis.z*.35*direction
	var distance:=Vector2(pose.origin.x,pose.origin.z).distance_to(road)
	# A car already outside the asphalt needs a bounded physical way back.
	# Do not require the current/off-road axle probes to magically be asphalt.
	if distance>float(frame["error"])+.4 or not car.world_bounds.grow(-3).has_point(Vector2(pose.origin.x,pose.origin.z)) or not is_finite(car.surface_height(pose.origin.x,pose.origin.z)) or not reverse_step_clear(pose):return false
	state="rejoining_road";reverse_time=0;blocked_time=0;no_progress_s=0
	if car.signed_speed*direction<-.2 or car.speed_mps>2.5:car.set_controls(0,steer,true)
	else:car.set_controls(.55*direction,steer)
	return true

func drive_turnaround(delta: float, p: Vector2, frame: Dictionary) -> bool:
	if trajectory.closed:return false
	# A three-point turn needs the whole narrow road. Queue before the
	# junction, leaving room for the owner to return along the incoming leg.
	for i in range(turnaround_done+1,trajectory.turnarounds.size()):
		var pending: Dictionary=trajectory.turnarounds[i]
		var distance: float=pending["s"]-nav_s
		if nav_s<float(pending["approach_s"]):break
		if distance< -15:continue
		var ref=trajectory.turn_reservations.get(i)
		var owner=ref.get_ref() if ref is WeakRef else null
		if owner!=null and (owner.session.phase!="running" or owner.nav_s>float(pending["clear_s"])):
			owner=null
		if owner==null:
			owner=self
			for other in participants:
				if not is_instance_valid(other):continue
				var other_ref=other.get_meta("race_pilot",null)
				var candidate=other_ref.get_ref() if other_ref is WeakRef else null
				if candidate!=null and candidate.trajectory==trajectory and candidate.session.phase=="running" and candidate.turnaround_done<i and candidate.nav_s>owner.nav_s and candidate.nav_s<float(pending["s"])+7:
					owner=candidate
			trajectory.turn_reservations[i]=weakref(owner)
		if owner!=self:
			state="turnaround_queue"
			blocked_time=0;no_progress_s=0;reverse_time=0
			if car.signed_speed>.5:car.set_controls(0,0,false,false,1)
			else:car.set_controls(0,0,true)
			return true
		break
	if turnaround_index<0:
		for i in range(turnaround_done+1,trajectory.turnarounds.size()):
			var turn: Dictionary=trajectory.turnarounds[i]
			var remaining: float=turn["s"]-nav_s
			if remaining>7:break
			if remaining< -15:continue
			var gate: Dictionary=session.definition["checkpoints"][session.next_checkpoint]
			if float(gate["distance_m"])<float(turn["source_s"])-1:break
			if car.speed_mps>4.0:
				car.set_controls(0,0,false,false,1);state="turnaround_braking";return true
			turnaround_index=i;turnaround_reverse=false;turnaround_sign=1.0
			turnaround_stall=0;turnaround_position=p
			# Prefer steering toward the centre of the available road corridor.
			if float(frame["lateral"])>.3:turnaround_sign=-1
			validation_recovery=false;passing_car=null;lane=0;reverse_time=0
			break
	if turnaround_index<0:return false
	var turn: Dictionary=trajectory.turnarounds[turnaround_index]
	if p.distance_to(turnaround_position)>.08:
		turnaround_position=p;turnaround_stall=0
	else:turnaround_stall+=delta
	# Predictive probes cannot guarantee motion across every curb contact.
	# Detect actual lack of displacement and try the opposite gear safely.
	if turnaround_stall>1.5:
		turnaround_reverse=not turnaround_reverse
		turnaround_sign=-turnaround_sign
		turnaround_stall=0;turnaround_switch=.35
	var heading:=Vector2(-car.global_basis.z.x,-car.global_basis.z.z)
	if heading.dot(turn["forward"])>.94:
		if car.signed_speed<-.2:
			car.set_controls(0,0,true);state="turnaround_stop_reverse";return true
		nav_s=float(turn["s"])+maxf(0,(p-turn["position"]).dot(turn["forward"]))
		best_nav_s=nav_s;no_progress_s=0;blocked_time=0
		turnaround_done=turnaround_index;turnaround_index=-1;turnarounds_completed+=1
		car.set_controls(.4,0);state="turnaround_exit";return true
	turnaround_switch=maxf(0,turnaround_switch-delta)
	var sign:= -1.0 if turnaround_reverse else 1.0
	if not maneuver_clear(sign,turnaround_sign*sign) and turnaround_switch<=0:
		turnaround_reverse=not turnaround_reverse;turnaround_switch=.35;sign=-sign
	if not maneuver_clear(sign,turnaround_sign*sign):
		car.set_controls(0,0,true);state="turnaround_wait";return true
	if car.signed_speed*sign<-.3:
		car.set_controls(0,0,true)
	elif car.speed_mps>2.5:car.set_controls(0,turnaround_sign*sign,true)
	else:car.set_controls(.55*sign,turnaround_sign*sign)
	state="turnaround_reverse" if turnaround_reverse else "turnaround_forward"
	return true

func maneuver_clear(direction: float, steer: float) -> bool:
	var step:=maxf(.45,car.speed_mps*.25)
	var yaw: float=car.rotation.y-direction*step/float(car.config["wheelbase_m"])*tan(steer*float(car.config["max_steer_radians"])*float(car.config["steering_sensitivity"]))
	var pose:=car.global_transform;pose.basis=Basis(Vector3.UP,yaw)
	pose.origin-=pose.basis.z*step*direction
	pose.origin.y=car.supported_pose_height(pose.origin.x,pose.origin.z,yaw)
	return car.safe_road_transform(pose)

func planned_speed(at_s: float, offset := 0.0) -> float:
	var result: float=car.current_speed_cap
	var grip:=float(personality.get("lateral_accel_mps2",9.0))
	var braking:=maxf(2.0,float(car.config["braking_mps2"])*(0.82 if expert else 0.75)/float(personality["anticipation"])-maxf(0,car.slope_acceleration))
	var horizon:=clampf(car.speed_mps*car.speed_mps/(2*braking)+25.0,65.0,180.0)
	var distance:=0.0
	while distance<=horizon:
		var frame: Dictionary=trajectory.sample(at_s+distance,offset)
		var k:=absf(float(frame["curvature"]))
		if k>0.002:
			var safe:=minf(sqrt(grip/k),float(car.config["max_yaw_rate_radians"])*(0.9 if expert else 0.85)/k)
			var needed:=atan(float(car.config["wheelbase_m"])*k)/(float(car.config["max_steer_radians"])*float(car.config["steering_sensitivity"]))
			var steer_speed:=float(car.config["max_forward_speed_mps"])*maxf(0.05,1.0-needed)/float(car.config["steering_reduction_at_high_speed"])
			safe=minf(safe,steer_speed)
			result=minf(result,sqrt(safe*safe+2*braking*maxf(0,distance-3)))
		distance+=3.0
	return maxf(2.5,result)

func expert_drift(delta: float, frame: Dictionary, steer: float, obstacle_speed: float) -> Dictionary:
	drift_cooldown=maxf(0,drift_cooldown-delta)
	var k: float=frame["curvature"]
	var clear: bool=allow_abilities and obstacle_speed==INF and not is_instance_valid(passing_car) and not validation_recovery and float(frame["error"])<2.3 and car.is_on_floor()
	if drift_phase=="ready" and drift_cooldown<=0 and personality_id=="aggressive" and clear:
		var a: float=trajectory.sample(nav_s+6)["curvature"]
		var b: float=trajectory.sample(nav_s+12)["curvature"]
		var broad_turn: bool=absf(k)>0.018 and absf(k)<0.035 and absf(a)>0.018 and absf(a)<0.035 and absf(b)>0.018 and absf(b)<0.035 and signf(k)==signf(a) and signf(a)==signf(b)
		if broad_turn and float(frame["half_width"])>6 and float(frame["error"])<0.7 and car.speed_mps>float(car.config["drift_min_speed_mps"])+5.0 and target_speed>float(car.config["drift_min_speed_mps"])+5.0:
			drift_phase="holding"
			drift_elapsed=0
	if drift_phase=="holding":
		drift_elapsed+=delta
		var earned: bool=car.abilities.drift_valid_time>=float(car.config["drift_min_duration_s"])+0.05 and car.abilities.drift_charge>=float(car.config["drift_min_charge"])+0.03
		if not clear or earned or drift_elapsed>1.6 or absf(rad_to_deg(car.slip_angle))>32 or car.speed_mps<float(car.config["drift_min_speed_mps"])+0.3:
			drift_phase="settling"
			drift_elapsed=0
		else:
			# Use the actual wheelbase, steering reduction and yaw cap. Holding
			# a controlled slip long enough is necessary to earn the real reward.
			var reduction:=lerpf(1,1-float(car.config["steering_reduction_at_high_speed"]),clampf(car.speed_mps/car.base_speed_cap,0,1))
			var yaw:=minf(float(car.config["max_yaw_rate_radians"])*0.8,clampf(car.speed_mps*absf(k)*1.6,0.8,1.0))
			var wheel:=atan(float(car.config["wheelbase_m"])*yaw/maxf(1,car.speed_mps))
			var floor_steer:=wheel/(float(car.config["max_steer_radians"])*float(car.config["steering_sensitivity"])*reduction)
			steer=signf(k)*floor_steer
			return {"handbrake":true,"steer":clampf(steer,-1,1)}
	if drift_phase=="settling":
		drift_elapsed+=delta
		if not car.abilities.drift_tracking or drift_elapsed>float(car.config["drift_exit_timeout_s"]):
			drift_phase="boost_exit" if car.abilities.drift_boost_active else "ready"
			drift_cooldown=5.0
	if drift_phase=="boost_exit" and (not clear or not car.abilities.drift_boost_active or car.speed_mps>target_speed+3):
		drift_phase="ready"
	return {"handbrake":false,"steer":steer}

func lane_clear(offset: float, p: Vector2, at_s: float) -> bool:
	for other in participants:
		if other==car or not is_instance_valid(other) or absf(other.position.y-car.position.y)>3: continue
		var other_frame: Dictionary=traffic_frame(other)
		var ahead: float=other_frame["s"]-at_s
		if ahead>-5 and ahead<17 and absf(float(other_frame["lateral"])-offset)<(1.8 if arcade or other.speed_mps<1 else 2.1): return false
	for ahead in [3.0,6.0,12.0]:
		var frame: Dictionary=trajectory.sample(at_s+ahead,offset)
		var point: Vector2=frame["position"]
		var forward: Vector2=frame["line_forward"]
		var yaw:=atan2(-forward.x,-forward.y)
		var pose:=Transform3D(Basis(Vector3.UP,yaw),Vector3(point.x,car.supported_pose_height(point.x,point.y,yaw),point.y))
		if not car.safe_road_transform(pose): return false
	return true

func merge_clear(wanted: float, current: float, at_s: float) -> bool:
	for other in participants:
		if other==car or not is_instance_valid(other) or absf(other.position.y-car.position.y)>3: continue
		var other_p:=Vector2(other.position.x,other.position.z)
		if other_p.distance_squared_to(Vector2(car.position.x,car.position.z))>625: continue
		var frame: Dictionary=traffic_frame(other)
		var ahead: float=frame["s"]-at_s+(other.signed_speed-car.signed_speed)*0.65
		if ahead>-6 and ahead<8 and float(frame["lateral"])>minf(current,wanted)-1.8 and float(frame["lateral"])<maxf(current,wanted)+1.8: return false
	return true

func traffic_frame(other: CharacterBody3D) -> Dictionary:
	var other_p:=Vector2(other.position.x,other.position.z)
	var reference=other.get_meta("race_pilot") if other.has_meta("race_pilot") else null
	if reference is WeakRef:
		var pilot=reference.get_ref()
		if pilot!=null and pilot.trajectory==trajectory and is_finite(pilot.nav_s):
			if not trajectory.closed:
				var exit: Dictionary=trajectory.project_finish(other_p) if pilot.nav_s>trajectory.length-50 else {}
				if not exit.is_empty():return exit
				var grid: Dictionary=trajectory.project_grid(other_p) if pilot.nav_s<5 else {}
				if not grid.is_empty():return grid
				return trajectory.project_interval(other_p,maxf(0,pilot.nav_s-2),minf(trajectory.length,pilot.nav_s+2),pilot.nav_s)
			return trajectory.project(other_p,pilot.nav_s)
	# Nearby human traffic must be mapped onto our current traversal too.
	# A global nearest point is ambiguous on an out-and-back access road.
	if not trajectory.closed:
		var exit: Dictionary=trajectory.project_finish(other_p) if nav_s>trajectory.length-50 else {}
		if not exit.is_empty():return exit
		return trajectory.project_interval(other_p,maxf(0,nav_s-80),minf(trajectory.length,nav_s+80),nav_s)
	var frame: Dictionary=trajectory.project(other_p,-INF)
	if trajectory.closed: frame["s"]+=roundf((nav_s-float(frame["s"]))/trajectory.length)*trajectory.length
	return frame

func reverse_step_clear(pose: Transform3D) -> bool:
	var query:=PhysicsShapeQueryParameters3D.new()
	query.shape=car.collision_shape
	query.collision_mask=28
	query.exclude=[car.get_rid()]
	query.transform=pose
	var space:=car.get_world_3d().direct_space_state
	var future:=space.intersect_shape(query,8)
	if future.is_empty(): return true
	query.transform=car.global_transform
	var current:=space.intersect_shape(query,8)
	var touches_static:=false
	for hit in future:
		var other=hit["collider"]
		# Contact margin may already overlap a neighbouring chassis. Allow
		# separating from that contact; still reject every new overlap.
		var already:=current.any(func(contact): return contact["collider"]==other)
		if not already:return false
		if other is CharacterBody3D:
			if pose.origin.distance_squared_to(other.global_position)<=car.position.distance_squared_to(other.global_position):return false
		else:touches_static=true
	if touches_static:
		# Existing contact margins must permit backing away from a wall.
		# Reject deeper penetration and all new colliders; do not disable solids.
		var before:=contact_depth(space.collide_shape(query,16))
		query.transform=pose
		if contact_depth(space.collide_shape(query,16))>=before-.0001:return false
	return true

func contact_depth(contacts: PackedVector3Array) -> float:
	var depth:=0.0
	for i in range(0,contacts.size()-1,2):depth=maxf(depth,contacts[i].distance_to(contacts[i+1]))
	return depth

func telemetry() -> String:
	return "%s %.1f/%.1f m/s gas %.1f brake %.1f %s turbo %s burst %s route %.1f lane %.1f recover %d gate_recover %d" % [personality_id,car.speed_mps,target_speed,car.command_throttle,car.command_brake,state,car.turbo_active,car.abilities.burst_state,nav_s,lane,recovery_attempts,checkpoint_recoveries]

extends Node
## Headless probe for the colony rover (D-065). Prints the key values over time and
## exits 1 if an invariant breaks.
##  A  RoverTimeline: unload (bed, gate, crates) and point turn (yaw, steer), full and
##     reduced: ends seated/closed/straight, yaw lands on 180 deg, no NaN, reduced
##     never overshoots.
##  B  A ColonyRover on a bumpy test road: pulls away, cruises, brakes to a stop.
##     Wheel spin matches ground speed, every wheel stays on its own ground (rocker-
##     bogie), the body pitches with weight and settles; reduced motion pitches less.
##  C  The real colony (fixture, default grown:viridia): rovers drive their roads at
##     a fixed 1/60 s step, stay in their lane, stop, unload, turn and come back; the
##     captain stepping in front makes the rover stop short of him and flash.
## A scene (not --script) so the autoloads exist for the colony part:
##   godot --headless --path . res://tools/rebuild/rover_probe.tscn [-- --setup=grown:viridia --step=200]

var step := 200.0
var setup := "grown:viridia"
var bad: Array = []


func _ready() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--step="):
			step = float(a.substr(7))
		elif a.begins_with("--setup="):
			setup = a.substr(8)
	_run.call_deferred()


func _nan(d: Dictionary, where: String) -> void:
	for k: String in d.keys():
		if d[k] is float and is_nan(float(d[k])):
			bad.append("NaN %s %s" % [k, where])


func _run() -> void:
	_timelines()
	await _test_road()
	await _colony()
	print("ROVER_PROBE %s %s" % ["PASS" if bad.is_empty() else "FAIL", str(bad)])
	get_tree().quit(0 if bad.is_empty() else 1)


func _timelines() -> void:
	for red: bool in [false, true]:
		print("UNLOAD %s  (seat %d ms, latch %d ms, end %d ms)" % ["REDUCED" if red else "FULL", int(RoverTimeline.U_SEAT), int(RoverTimeline.U_LATCH), int(RoverTimeline.U_END)])
		print("   t_ms   bed°  gate°  crate0  crate2   hop   jolt  beacon")
		var t := 0.0
		var max_bed := 0.0
		var max_gate := 0.0
		while t <= RoverTimeline.U_END + 1.0:
			var p := RoverTimeline.unload(t, red)
			_nan(p, "unload %d" % int(t))
			var cr: Array = p["crates"]
			max_bed = maxf(max_bed, float(p["bed"]))
			max_gate = maxf(max_gate, float(p["gate"]))
			print("%7d %6.2f %6.1f %7.3f %7.3f %5.3f %6.3f %6.2f" % [int(t), rad_to_deg(float(p["bed"])), rad_to_deg(float(p["gate"])), float(cr[0]), float(cr[2]), float(p["hop"]), float(p["jolt"]), float(p["beacon"])])
			t += step
		var e := RoverTimeline.unload(RoverTimeline.U_END, red)
		if absf(float(e["bed"])) > 0.003 or absf(float(e["gate"])) > 0.003 or absf(float((e["crates"] as Array)[0])) > 0.002:
			bad.append("unload end pose not seated (%s): %s" % [red, e])
		if red and (max_bed > RoverTimeline.BED_MAX + 0.0005 or max_gate > RoverTimeline.GATE_MAX + 0.0005):
			bad.append("reduced unload overshoots")
		print("TURN %s  (yaw %d..%d ms, end %d ms)" % ["REDUCED" if red else "FULL", int(RoverTimeline.T_YAW_A), int(RoverTimeline.T_YAW_B), int(RoverTimeline.T_END)])
		print("   t_ms  steer   yaw°   rate°/s")
		t = 0.0
		var max_yaw := 0.0
		var integ := 0.0
		while t <= RoverTimeline.T_END + 1.0:
			var p := RoverTimeline.turn(t, red)
			_nan(p, "turn %d" % int(t))
			max_yaw = maxf(max_yaw, float(p["yaw"]))
			print("%7d %6.3f %7.2f %8.2f" % [int(t), float(p["steer"]), rad_to_deg(float(p["yaw"])), rad_to_deg(float(p["rate"]))])
			t += step
		for k: int in 4700:
			integ += float(RoverTimeline.turn(float(k), red)["rate"]) * 0.001
		var e2 := RoverTimeline.turn(RoverTimeline.T_END, red)
		if absf(float(e2["yaw"]) - PI) > 0.004 or absf(float(e2["steer"])) > 0.003:
			bad.append("turn end pose wrong (%s): %s" % [red, e2])
		if absf(integ - PI) > 0.01:
			bad.append("turn rate does not integrate to the yaw (%.3f)" % integ)
		if red and max_yaw > PI + 0.0005:
			bad.append("reduced turn overshoots")


## A rover on a straight bumpy road, driven like ColonyRovers does (same limits).
func _test_road() -> void:
	for red: bool in [false, true]:
		var r := preload("res://scenes/colony/colony_rover.tscn").instantiate() as ColonyRover
		r.reduced = red
		add_child(r)
		await get_tree().process_frame
		var dt := 1.0 / 60.0
		var s := 0.0
		var v := 0.0
		var a := 0.0
		var g := PackedFloat32Array([0, 0, 0, 0, 0, 0])
		var max_pitch := 0.0
		var min_pitch := 0.0
		var max_contact := 0.0
		var max_spin_err := 0.0
		var stop_t := -1.0
		print("ROAD %s" % ("REDUCED" if red else "FULL"))
		print("    t_s     s      v      a  pitch°  roll°  chassis°  contact_cm  spin_err%")
		for k: int in 60 * 22:
			var t := k * dt
			var target := 4.2 if t < 9.0 else 0.0
			if t >= 9.0:
				target = sqrt(2.0 * ColonyRovers.A_BRAKE * maxf(60.0 - s, 0.0))
			var av := ColonyRovers.throttle(v, a, target, 60.0 - s if t >= 9.0 else INF, false, dt)
			a = av.x
			v = av.y
			s += v * dt
			if v < 0.01 and t > 9.0 and stop_t < 0.0:
				stop_t = t
			for w: int in 6:
				var o := ColonyRover.wheel_offset(w)
				var z := s + o.y
				g[w] = 0.06 * sin(z * 1.7 + (0.0 if w < 3 else 1.1)) + 0.025 * sin(z * 4.3 + o.x)
			r.position = Vector3(0, 0, s)
			var spin0 := float(r.spin[0])
			r.set_ground(g)
			r.drive(dt, v, a, 0.0)
			# Spin check: angle change * R == distance travelled.
			var dsp := wrapf(float(r.spin[0]) - spin0, -PI, PI) * ColonyRover.WHEEL_R
			if v > 0.5:
				max_spin_err = maxf(max_spin_err, absf(dsp - v * dt) / (v * dt))
			# Contact: each wheel's lowest point vs its ground (rocker-bogie solve).
			var worst := 0.0
			for w: int in 6:
				var hub := r.wheel_world(w)
				worst = maxf(worst, absf((hub.y - ColonyRover.WHEEL_R) - (r.position.y + g[w])))
			max_contact = maxf(max_contact, worst)
			max_pitch = maxf(max_pitch, r.pitch)
			min_pitch = minf(min_pitch, r.pitch)
			if k % int(step / 1000.0 * 60.0 * 2.5) == 0:
				var ch := (r.get_node("Chassis") as Node3D).rotation
				print("%7.2f %6.2f %6.2f %6.2f %7.3f %6.3f %8.3f %10.2f %10.2f" % [t, s, v, a, rad_to_deg(r.pitch), rad_to_deg(r.roll), rad_to_deg(ch.x), worst * 100.0, max_spin_err * 100.0])
		print("ROAD %s: stopped at %.2f s (s=%.2f), pitch range %.2f..%.2f deg, worst wheel contact %.1f cm, spin error %.2f %%" % [
			"reduced" if red else "full", stop_t, s, rad_to_deg(min_pitch), rad_to_deg(max_pitch), max_contact * 100.0, max_spin_err * 100.0])
		if max_contact > 0.03:
			bad.append("wheel leaves its ground by %.1f cm (%s)" % [max_contact * 100.0, red])
		if max_spin_err > 0.02:
			bad.append("wheel spin does not match ground speed (%.1f %%)" % (max_spin_err * 100.0))
		if not red and (max_pitch < 0.006 or min_pitch > -0.004):
			bad.append("body does not pitch with weight (%.3f..%.3f)" % [min_pitch, max_pitch])
		if absf(s - 60.0) > 0.3:
			bad.append("brakes short of / past the stop (%.2f)" % s)
		if absf(r.pitch) > 0.002:
			bad.append("body has not settled after the stop (%.4f)" % r.pitch)
		r.queue_free()
		await get_tree().process_frame


func _colony() -> void:
	DebugFixtures.prepare(setup)
	var col: Node = (load("res://scenes/colony/colony.tscn") as PackedScene).instantiate()
	add_child(col)
	for i: int in 10:
		await get_tree().process_frame
	var life: ColonyLife = col.get("_life")
	var rovers := life.rovers if life else null
	if rovers == null or rovers.count() == 0:
		bad.append("no rovers in the colony (%s)" % setup)
		return
	rovers.set_process(false)
	life.set_process(false)  # stepped by hand below: walkers, vehicles and rovers at 1/60 s
	var cap: Captain = col.get("captain")
	print("COLONY %s: %d rovers on %d roads" % [setup, rovers.count(), (col.get("_paths") as ColonyPaths).roads.size()])
	if not rovers.find_children("*", "CollisionObject3D", true, false).is_empty():
		bad.append("a rover has a collider")
	var dt := 1.0 / 60.0
	var states: Dictionary = {}
	var max_off := 0.0
	var paths: ColonyPaths = col.get("_paths")
	var trips := 0
	var last_dir := float(rovers.state_of(0)["dir"])
	print("   t_s  state    s      v      a")
	for k: int in 60 * 150:
		life._process(dt)
		rovers._process(dt)
		for i: int in rovers.count():
			var st := rovers.state_of(i)
			states[str(st["state"])] = true
			var n := rovers.rover(i)
			# Distance from the road's centre line (lane offset + slack).
			var best := INF
			for rd: PackedVector2Array in paths.roads:
				for j: int in range(1, rd.size()):
					var p := Vector2(n.position.x, n.position.z)
					best = minf(best, Geometry2D.get_closest_point_to_segment(p, rd[j - 1], rd[j]).distance_to(p))
			max_off = maxf(max_off, best)
		var s0 := rovers.state_of(0)
		if float(s0["dir"]) != last_dir:
			trips += 1
			last_dir = float(s0["dir"])
		if k % 300 == 0:
			print("%6.1f  %-7s %6.1f %6.2f %6.2f  %s" % [k * dt, str(s0["state"]), float(s0["s"]), float(s0["v"]), float(s0["a"]), str(s0["why"])])
	print("COLONY: states seen %s, rover 0 turned round %d times, max distance from the road's centre line %.2f m" % [states.keys(), trips, max_off])
	for want: String in ["drive", "settle", "unload", "turn"]:
		if not states.has(want):
			bad.append("never saw state " + want)
	if trips < 1:
		bad.append("rover 0 never turned round")
	if max_off > 2.6:
		bad.append("a rover left its road (%.2f m off the centre line)" % max_off)
	# Arrival close up: brake into the stop, settle, unload, turn (every 0.25 s).
	rovers.force(0, "arrive")
	var arrive_wait := 0.0
	print("ARRIVE   t_s  state     s      v      a  why")
	for k: int in 60 * 14:
		life._process(dt)
		rovers._process(dt)
		var st := rovers.state_of(0)
		if str(st["state"]) == "drive" and float(st["v"]) < 0.05 and k > 30 and arrive_wait >= 0.0:
			arrive_wait += dt
		elif str(st["state"]) != "drive":
			arrive_wait = -absf(arrive_wait) if arrive_wait != 0.0 else -0.0001
		if k % 15 == 0:
			print("ARRIVE %5.2f  %-7s %6.2f %6.2f %6.2f  %s" % [k * dt, str(st["state"]), float(st["s"]), float(st["v"]), float(st["a"]), str(st["why"])])
	print("ARRIVE: stood still %.2f s before its unload began" % absf(arrive_wait))
	if absf(arrive_wait) > 1.0:
		bad.append("rover dawdles %.1f s at its stop before unloading" % absf(arrive_wait))
	# Captain steps into rover 0's lane 9 m ahead: it must stop short of him.
	rovers.force(0, "mid")
	for k: int in 10:
		life._process(dt)
		rovers._process(dt)
	var r0 := rovers.rover(0)
	var at := rovers.lane_point(0, 11.0)
	cap.visible = true
	cap.global_position = at
	var closest := INF
	var flashed := false
	for k: int in 60 * 8:
		life._process(dt)
		rovers._process(dt)
		var yaw := float(rovers.state_of(0)["yaw"])
		var front := r0.position + Vector3(sin(yaw), 0, cos(yaw)) * ColonyRovers.FRONT
		closest = minf(closest, Vector2(front.x, front.z).distance_to(Vector2(at.x, at.z)))
		flashed = flashed or r0.head_glow > 1.0
	var v_end := float(rovers.state_of(0)["v"])
	print("CAPTAIN: rover 0 stopped with its bumper %.2f m from the captain (v=%.2f), lamps flashed %s" % [closest, v_end, flashed])
	if closest < 1.2 or v_end > 0.05:
		bad.append("rover does not stop for the captain (gap %.2f, v %.2f)" % [closest, v_end])
	if not flashed:
		bad.append("rover never flashed its lamps at the captain")
	cap.visible = false
	for k: int in 60 * 6:
		life._process(dt)
		rovers._process(dt)
	if float(rovers.state_of(0)["v"]) < 1.0:
		bad.append("rover does not drive on once the captain steps aside")
	col.queue_free()
	await get_tree().process_frame

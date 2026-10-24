class_name ColonyRovers
extends Node3D
## The colony's utility rovers (D-065), purely illustrative (never touches the
## domain): one at year 0, more as the colony grows (data life.rovers). Each rover
## shuttles along one of the dirt roads (ColonyPaths.roads) between the landing
## site and a district: it keeps to its lane, slows for curves, brakes smoothly
## into its stop, unloads (bed tips, crates shuffle), spins round on the spot and
## drives back. It gives way to the captain, to colonists on the road and to the
## rover ahead (stops, then flashes its lamps if someone keeps standing there),
## never has a collider and never leaves the road. Per frame it costs a few array
## lookups per rover: the road heights under both wheel tracks are sampled once per
## layout.

const STEP := 0.5           # route sample spacing (m)
const END_MARGIN := 9.0     # stops this far before a road's end (clear of the hover cars' turning spot)
const TAPER := 9.0          # lane offset fades to the centre line near the ends
const FRONT := 2.62         # front bumper ahead of the middle axle
const HALF_W := 1.32
const A_MAX := 1.3
const A_BRAKE := 1.15       # planned braking
const A_HARD := 3.2         # someone stepped in front
const JERK := 3.0
const A_LAT := 0.8          # curve speed limit (m/s^2 sideways)

var terrain: TerrainBuilder
var paths: ColonyPaths
var captain: Node3D
var life: ColonyLife

var _routes: Array = []   # per road: {pts, tan, kappa, len, h: {1: [L, R, C], -1: [...]}}
var _rovers: Array = []   # per rover: Dictionary (see _spawn)
var _cfg: Dictionary = {}
var _reduced := false
var _night := false
var _dusty := false
var _dust_color := Color(0.62, 0.55, 0.42)
var _rng := RandomNumberGenerator.new()
var _obstacles := PackedVector2Array()   # reused every frame (no per-frame allocation)
var _tmp := PackedFloat32Array([0, 0, 0, 0, 0, 0])


func _init() -> void:
	name = "Rovers"
	_rng.seed = 6501


func setup(world_id: String) -> void:
	_cfg = DictUtil.get_dict(DictUtil.get_dict(BuildingDressing.doc(), "life"), "rovers")
	_night = world_id in DictUtil.get_arr(_cfg, "night")
	var dust: Dictionary = DictUtil.get_dict(_cfg, "dust")
	_dusty = dust.has(world_id)
	if _dusty:
		_dust_color = Color(str(dust[world_id]))
	ColonyRover.async_bake = DisplayServer.get_name() != "headless"


## How many rovers this colony runs: data life.rovers (base + one per N active buildings).
static func wanted(cfg: Dictionary, active_buildings: int, roads: int) -> int:
	if roads == 0:
		return 0
	return clampi(DictUtil.get_int(cfg, "base", 1) + active_buildings / maxi(1, DictUtil.get_int(cfg, "per_buildings", 6)), 0, DictUtil.get_int(cfg, "max", 4))


## New layout: rebuild the route data and keep the rovers that already exist.
func relayout(new_paths: ColonyPaths, active_buildings: int) -> void:
	paths = new_paths
	_routes.clear()
	for ri: int in paths.roads.size():
		var r := _route(paths.roads[ri])
		if not r.is_empty():
			r["road"] = ri
			_routes.append(r)
	var want := wanted(_cfg, active_buildings, _routes.size())
	while _rovers.size() > want:
		var r: Dictionary = _rovers.pop_back()
		(r["node"] as Node).queue_free()
	while _rovers.size() < want:
		_spawn(_rovers.size())
	for i: int in _rovers.size():
		var rv: Dictionary = _rovers[i]
		rv["route"] = i % _routes.size()
		var rt: Dictionary = _routes[int(rv["route"])]
		rv["s"] = clampf(float(rv["s"]), END_MARGIN, float(rt["len"]) - END_MARGIN)
		if str(rv["state"]) == "turn":
			_end_turn(rv)
		_place(rv, 0.0)


func _spawn(i: int) -> void:
	var node := preload("res://scenes/colony/colony_rover.tscn").instantiate() as ColonyRover
	node.name = "Rover%d" % i
	add_child(node)
	node.reduced = _reduced
	node.set_world(_night, _dusty, _dust_color)
	var rt: Dictionary = _routes[i % _routes.size()]
	var length := float(rt["len"])
	# Spread them out: alternate directions, staggered along the road, mid-drive.
	var dir := 1.0 if i % 2 == 0 else -1.0
	var s := lerpf(END_MARGIN + 4.0, length - END_MARGIN - 4.0, fposmod(0.3 + 0.37 * i, 1.0))
	var rv := {"node": node, "route": i % _routes.size(), "s": s, "dir": dir, "v": DictUtil.get_float(_cfg, "speed", 4.0) * 0.8,
		"a": 0.0, "state": "drive", "t": 0.0, "yaw": 0.0, "yaw0": 0.0, "turn_dir": 1.0, "blocked": 0.0, "flash_at": 1.2,
		"cruise": DictUtil.get_float(_cfg, "speed", 4.0) * _rng.randf_range(0.9, 1.08), "seat_fired": false, "yaw_rate": 0.0, "dep": -1.0, "still": 0.0}
	_rovers.append(rv)


# ------------------------------------------------------------------ routes
## A smooth, evenly sampled copy of a road with tangents, curvature, the lane
## offset (pulled in where a building platform is close) and the ground heights
## under both wheel tracks for each direction (plus small ruts).
func _route(rd: PackedVector2Array) -> Dictionary:
	if rd.size() < 2:
		return {}
	var sm := ColonyPaths._chaikin(rd, 3)
	var total := 0.0
	for i: int in range(1, sm.size()):
		total += sm[i - 1].distance_to(sm[i])
	if total < END_MARGIN * 2.0 + 6.0:
		return {}
	var n := int(total / STEP) + 1
	var pts := PackedVector2Array()
	var acc := 0.0
	var seg := 1
	for k: int in n:
		var s := k * STEP
		while seg < sm.size() - 1 and acc + sm[seg - 1].distance_to(sm[seg]) < s:
			acc += sm[seg - 1].distance_to(sm[seg])
			seg += 1
		var l := maxf(sm[seg - 1].distance_to(sm[seg]), 0.0001)
		pts.append(sm[seg - 1].lerp(sm[seg], clampf((s - acc) / l, 0.0, 1.0)))
	var tan := PackedVector2Array()
	var kap := PackedFloat32Array()
	for k: int in n:
		var a := pts[maxi(k - 2, 0)]
		var b := pts[mini(k + 2, n - 1)]
		tan.append((b - a).normalized())
	for k: int in n:
		var t0 := tan[maxi(k - 2, 0)]
		var t1 := tan[mini(k + 2, n - 1)]
		var ds := STEP * float(mini(k + 2, n - 1) - maxi(k - 2, 0))
		kap.append(-t0.angle_to(t1) / maxf(ds, 0.001))  # + = heading turns toward local +X (yaw grows)
	var lane_w := DictUtil.get_float(_cfg, "lane", 1.35)
	var h := {}
	for dir: float in [1.0, -1.0]:
		var hl := PackedFloat32Array()
		var hr := PackedFloat32Array()
		var hc := PackedFloat32Array()
		var lane := PackedFloat32Array()
		var ph := _rng.randf() * 10.0
		for k: int in n:
			var s := k * STEP
			var off := lane_w * smoothstep(0.0, TAPER, s - END_MARGIN) * smoothstep(0.0, TAPER, (n - 1) * STEP - END_MARGIN - s)
			var side := tan[k].orthogonal() * dir  # the rover's local +X
			# Keep the body off building platforms: pull the lane in where the outer
			# edge would touch one.
			while off > 0.05 and paths.walk_clear.blocked(pts[k] - side * (off + HALF_W), 0.3, -1, true):
				off -= 0.25
			off = maxf(off, 0.0)
			var c := pts[k] - side * off
			var l := c + side * ColonyRover.TRACK
			var r := c - side * ColonyRover.TRACK
			lane.append(off)
			var rut_l := 0.012 * sin(s * 2.3 + ph) + 0.007 * sin(s * 5.9 + ph * 1.7) + 0.03 * pow(maxf(0.0, sin(s * 0.61 + ph)), 24.0)
			var rut_r := 0.012 * sin(s * 2.1 + ph * 0.6) + 0.007 * sin(s * 6.3 + ph) + 0.03 * pow(maxf(0.0, sin(s * 0.53 + ph * 2.1)), 24.0)
			hl.append(_ground(l) + rut_l)
			hr.append(_ground(r) + rut_r)
			hc.append(_ground(c))
		h[dir] = [hl, hr, hc, lane]
	return {"pts": pts, "tan": tan, "kappa": kap, "len": (n - 1) * STEP, "n": n, "h": h}


func _ground(p: Vector2) -> float:
	return ColonyPaths.surface_y(terrain, p.x, p.y) + 0.1


static func _sample(arr: PackedFloat32Array, s: float) -> float:
	var f := clampf(s / STEP, 0.0, float(arr.size() - 1))
	var i := mini(int(f), arr.size() - 2)
	return lerpf(arr[i], arr[i + 1], f - i)


# ------------------------------------------------------------------ per frame
func _process(delta: float) -> void:
	if terrain == null or _routes.is_empty():
		return
	delta = minf(delta, 0.1)
	var red := FxEffect.reduced_motion()
	if red != _reduced:
		_reduced = red
		for rv: Dictionary in _rovers:
			(rv["node"] as ColonyRover).reduced = red
	var cam := get_viewport().get_camera_3d()
	for rv: Dictionary in _rovers:
		match str(rv["state"]):
			"drive":
				_drive(rv, delta)
			"settle":
				rv["t"] = float(rv["t"]) + delta * 1000.0
				_coast(rv, delta)
				if float(rv["t"]) > 380.0:
					rv["state"] = "unload"
					rv["t"] = 0.0
					rv["seat_fired"] = false
					_sound(rv, "unload_start")
			"unload":
				rv["t"] = float(rv["t"]) + delta * 1000.0
				(rv["node"] as ColonyRover).pose_unload(float(rv["t"]))
				if not bool(rv["seat_fired"]) and float(rv["t"]) >= RoverTimeline.U_SEAT:
					rv["seat_fired"] = true
					_sound(rv, "unload_seat")
				_coast(rv, delta)
				if float(rv["t"]) >= RoverTimeline.U_END:
					_start_turn(rv)
			"turn":
				# Wait (frozen mid-turn) while anyone stands inside the swept circle.
				var paused := _someone_near(rv, 3.6)
				if not paused:
					rv["t"] = float(rv["t"]) + delta * 1000.0
				var t := float(rv["t"])
				var p := RoverTimeline.turn(t, _reduced)
				rv["yaw"] = float(rv["yaw0"]) + float(p["yaw"]) * float(rv["turn_dir"])
				rv["yaw_rate"] = 0.0 if paused else float(p["rate"]) * float(rv["turn_dir"])
				(rv["node"] as ColonyRover).pose_turn(t, float(rv["turn_dir"]), not paused)
				_place(rv, delta, true)
				if t >= RoverTimeline.T_END:
					_end_turn(rv)
		# Far from the camera: skip the per-wheel work (it is invisible there).
		var node: ColonyRover = rv["node"]
		node.visible = cam == null or cam.global_position.distance_squared_to(node.global_position) < 185.0 * 185.0


func _coast(rv: Dictionary, delta: float) -> void:
	rv["v"] = 0.0
	rv["a"] = 0.0
	_place(rv, delta)


func _drive(rv: Dictionary, delta: float) -> void:
	var rt: Dictionary = _routes[int(rv["route"])]
	var dir := float(rv["dir"])
	var s := float(rv["s"])
	var length := float(rt["len"])
	var stop_s := length - END_MARGIN if dir > 0.0 else END_MARGIN
	var to_stop := (stop_s - s) * dir
	var v := float(rv["v"])
	var cruise := float(rv["cruise"])
	# Curves ahead: slow to keep the sideways pull gentle.
	var kap: PackedFloat32Array = rt["kappa"]
	var v_curve := cruise
	for k: int in range(0, 24, 2):
		var ss := s + dir * (k * STEP)
		var kk := absf(_sample(kap, ss))
		if kk > 0.001:
			v_curve = minf(v_curve, maxf(1.2, sqrt(A_LAT / kk)) + k * STEP * 0.12)
	var v_stop := sqrt(2.0 * A_BRAKE * maxf(to_stop - 0.04, 0.0))
	# Someone or something in front: captain, colonists, the rover ahead.
	var gap := _obstacle_ahead(rv)
	var v_obs := INF
	var hard := false
	if gap < INF:
		v_obs = sqrt(2.0 * A_BRAKE * maxf(gap - 2.2, 0.0))
		hard = gap < 2.2 + v * v / (2.0 * A_BRAKE)
	var target := minf(minf(cruise, v_curve), minf(v_stop, v_obs))
	var node: ColonyRover = rv["node"]
	# Pull-away anticipation: after standing still, hold a beat while the body rocks
	# forward on its springs (the brakes let go), then squat back and move off.
	var dep := float(rv["dep"])
	if dep >= 0.0:
		dep += delta * 1000.0
		if dep > RoverTimeline.DEPART_MS:
			dep = -1.0
	if v < 0.05:
		rv["still"] = float(rv["still"]) + delta
	elif v > 0.3:
		rv["still"] = 0.0
	if dep < 0.0 and float(rv["still"]) >= 0.4 and target > 0.4:
		dep = 0.0
		rv["still"] = -60.0  # once per stop (re-armed when it is moving again)
	rv["dep"] = dep
	node.depart_ms = dep
	if dep >= 0.0 and dep < RoverTimeline.DEPART_MS * (0.0 if _reduced else 0.75):
		target = 0.0
	var stop_d := minf(to_stop, gap - 2.2 if gap < INF else INF)
	var av := throttle(v, float(rv["a"]), target, stop_d, hard, delta)
	v = av.y
	rv["a"] = av.x
	rv["v"] = v
	rv["s"] = clampf(s + dir * v * delta, 0.0, length)
	# Lamp flash when someone keeps blocking the road.
	if gap < 6.0 and v < 0.1:
		rv["blocked"] = float(rv["blocked"]) + delta
		if float(rv["blocked"]) >= float(rv["flash_at"]):
			rv["flash_at"] = float(rv["flash_at"]) + 6.0
			node.flash_lamps()
			_sound(rv, "horn")
	else:
		rv["blocked"] = 0.0
		rv["flash_at"] = 1.2
	_place(rv, delta)
	if to_stop < 0.6 and v < 0.05:
		rv["state"] = "settle"
		rv["t"] = 0.0


## The throttle: slow in and slow out (jerk-limited acceleration), braking planned so
## the rover comes to rest exactly at `stop_d` metres. Returns (accel, speed).
static func throttle(v: float, a: float, target: float, stop_d: float, hard: bool, dt: float) -> Vector2:
	var a_cmd := clampf((target - v) * 1.7, -(A_HARD if hard else A_BRAKE * 1.4), A_MAX)
	if stop_d < INF and v > 0.05:
		# Feed-forward: the deceleration that stops right at the mark (covers the jerk lag).
		var need := v * v / (2.0 * maxf(stop_d - v * 0.06, 0.02))
		if need > A_BRAKE * 0.85:
			a_cmd = minf(a_cmd, -minf(need, A_HARD))
	a += clampf(a_cmd - a, -JERK * dt * (3.0 if hard else 1.4), JERK * dt)
	v = maxf(v + a * dt, 0.0)
	if v <= 0.0 and a < 0.0:
		a = 0.0
	return Vector2(a, v)


## Distance from the front bumper to the nearest obstacle in the lane ahead (INF if none).
func _obstacle_ahead(rv: Dictionary) -> float:
	var node: ColonyRover = rv["node"]
	var c := Vector2(node.position.x, node.position.z)
	var yaw := float(rv["yaw"])
	var fwd := Vector2(sin(yaw), cos(yaw))
	var side := fwd.orthogonal()
	var look := FRONT + 4.0 + float(rv["v"]) * float(rv["v"]) / (2.0 * A_BRAKE) + 4.0
	var best := INF
	rv["why"] = ""
	_obstacles.clear()
	if is_instance_valid(captain) and captain.visible:
		_obstacles.append(Vector2(captain.global_position.x, captain.global_position.z))
	if life:
		life.walker_points(_obstacles)
	for p: Vector2 in _obstacles:
		var d := p - c
		var ahead := d.dot(fwd)
		if ahead > 0.0 and ahead < look and absf(d.dot(side)) < HALF_W + 0.55 and ahead - FRONT < best:
			best = ahead - FRONT
			rv["why"] = "person"
	# Hover cars drive only the roads without a rover and give way to rovers where
	# the roads meet (ColonyLife), so a rover never waits for one: no deadlocks.
	for other: Dictionary in _rovers:
		if other == rv:
			continue
		var on: Node3D = other["node"]
		var d := Vector2(on.position.x, on.position.z) - c
		var ahead := d.dot(fwd)
		var same := Vector2(sin(float(other["yaw"])), cos(float(other["yaw"]))).dot(fwd) > 0.0
		if (same or str(other["state"]) != "drive") and ahead > 0.0 and ahead < look + 4.0 and absf(d.dot(side)) < HALF_W * 2.0 and ahead - FRONT * 2.0 - 1.0 < best:
			best = ahead - FRONT * 2.0 - 1.0
			rv["why"] = "rover"
	return best


## Roads (indices into ColonyPaths.roads) that carry a rover: the hover cars keep off them.
func used_roads() -> Array:
	var out: Array = []
	for rv: Dictionary in _rovers:
		var ri := int((_routes[int(rv["route"])] as Dictionary)["road"])
		if not ri in out:
			out.append(ri)
	return out


## Is a rover in the box ahead of p (heading fwd, `look` m long, `lat` m to each side)?
## Hover vehicles ask this to give way.
func blocks(p: Vector2, fwd: Vector2, look: float, lat: float) -> bool:
	var side := fwd.orthogonal()
	for rv: Dictionary in _rovers:
		var n: Node3D = rv["node"]
		var d := Vector2(n.position.x, n.position.z) - p
		var ahead := d.dot(fwd)
		if ahead > 0.5 and ahead < look + FRONT and absf(d.dot(side)) < lat:
			return true
	return false


func _someone_near(rv: Dictionary, r: float) -> bool:
	var node: Node3D = rv["node"]
	var c := Vector2(node.position.x, node.position.z)
	if is_instance_valid(captain) and captain.visible and Vector2(captain.global_position.x, captain.global_position.z).distance_to(c) < r + 0.6:
		return true
	_obstacles.clear()
	if life:
		life.walker_points(_obstacles)
	for p: Vector2 in _obstacles:
		if p.distance_to(c) < r:
			return true
	return false


func _start_turn(rv: Dictionary) -> void:
	(rv["node"] as ColonyRover).end_beats()
	rv["state"] = "turn"
	rv["t"] = 0.0
	rv["yaw0"] = float(rv["yaw"])
	rv["turn_dir"] = 1.0 if _rng.randf() < 0.5 else -1.0
	_sound(rv, "turn")


func _end_turn(rv: Dictionary) -> void:
	(rv["node"] as ColonyRover).end_beats()
	rv["dir"] = -float(rv["dir"])
	rv["state"] = "drive"
	rv["t"] = 0.0
	rv["v"] = 0.0
	rv["a"] = 0.0


## Put the rover on its route: position, heading and the six wheel heights.
func _place(rv: Dictionary, delta: float, turning: bool = false) -> void:
	var rt: Dictionary = _routes[int(rv["route"])]
	var node: ColonyRover = rv["node"]
	var dir := float(rv["dir"])
	var s := float(rv["s"])
	var hh: Array = (rt["h"] as Dictionary)[dir]
	var pts: PackedVector2Array = rt["pts"]
	var tans: PackedVector2Array = rt["tan"]
	var f := clampf(s / STEP, 0.0, float(pts.size() - 1))
	var i := mini(int(f), pts.size() - 2)
	var fr := f - i
	var tan := tans[i].lerp(tans[i + 1], fr).normalized() * dir
	var side := tan.orthogonal()
	var off := _sample(hh[3], s)
	var c := pts[i].lerp(pts[i + 1], fr) - side * off
	var yc := _sample(hh[2], s)
	if not turning:
		rv["yaw"] = atan2(tan.x, tan.y)
		for w: int in 6:
			var o := ColonyRover.wheel_offset(w)
			var arr: PackedFloat32Array = hh[0] if w < 3 else hh[1]
			_tmp[w] = _sample(arr, s + dir * o.y) - yc
	else:
		var yaw := float(rv["yaw"])
		var b := Basis(Vector3.UP, yaw)
		for w: int in 6:
			var o := ColonyRover.wheel_offset(w)
			var p := b * Vector3(o.x, 0, o.y)
			_tmp[w] = _ground(c + Vector2(p.x, p.z)) - yc
	node.position = Vector3(c.x, yc, c.y)
	node.rotation = Vector3(0, float(rv["yaw"]), 0)
	if not node.visible:
		return
	node.set_ground(_tmp)
	if delta > 0.0:
		# Curvature along the rover's own travel: the reverse lane runs the road backwards.
		var kap := _sample(rt["kappa"], s) * dir if not turning else 0.0
		node.drive(delta, float(rv["v"]), float(rv["a"]), kap, float(rv["yaw_rate"]) if turning else INF)


func _sound(rv: Dictionary, what: String) -> void:
	var slots: Dictionary = DictUtil.get_dict(_cfg, "sounds")
	var cands: Array = DictUtil.get_arr(slots, what)
	for sl: Variant in cands:
		if AudioService.has_sound(str(sl)):
			var p := AudioService.play_at(str(sl), rv["node"] as Node3D, DictUtil.get_float(slots, what + "_db", -8.0), 45.0)
			if p:
				p.finished.connect(p.queue_free)
			return


# ------------------------------------------------------------------ evidence
func count() -> int:
	return _rovers.size()


func rover(i: int) -> ColonyRover:
	return (_rovers[clampi(i, 0, _rovers.size() - 1)]["node"] as ColonyRover) if not _rovers.is_empty() else null


func state_of(i: int) -> Dictionary:
	if _rovers.is_empty():
		return {}
	var rv: Dictionary = _rovers[clampi(i, 0, _rovers.size() - 1)]
	return {"state": rv["state"], "s": rv["s"], "v": rv["v"], "a": rv["a"], "dir": rv["dir"], "route": rv["route"], "t": rv["t"], "yaw": rv["yaw"], "why": rv.get("why", "")}


## Evidence: a point in rover i's lane `ahead` metres in front of it (on the ground).
func lane_point(i: int, ahead: float) -> Vector3:
	var rv: Dictionary = _rovers[clampi(i, 0, _rovers.size() - 1)]
	var rt: Dictionary = _routes[int(rv["route"])]
	var dir := float(rv["dir"])
	var s := clampf(float(rv["s"]) + dir * ahead, 0.0, float(rt["len"]))
	var hh: Array = (rt["h"] as Dictionary)[dir]
	var pts: PackedVector2Array = rt["pts"]
	var tans: PackedVector2Array = rt["tan"]
	var k := clampi(int(round(s / STEP)), 0, pts.size() - 1)
	var c := pts[k] - tans[k].orthogonal() * dir * _sample(hh[3], s)
	return Vector3(c.x, _sample(hh[2], s), c.y)


## Evidence: jump rover i straight to a beat ("unload", "turn") or to just before
## its stop ("arrive") so captures and probes do not wait for a whole road.
func force(i: int, what: String) -> void:
	if _rovers.is_empty():
		return
	var rv: Dictionary = _rovers[clampi(i, 0, _rovers.size() - 1)]
	var rt: Dictionary = _routes[int(rv["route"])]
	match what:
		"arrive":
			rv["state"] = "drive"
			rv["s"] = float(rt["len"]) - END_MARGIN - 14.0 if float(rv["dir"]) > 0.0 else END_MARGIN + 14.0
			rv["v"] = float(rv["cruise"])
		"unload":
			rv["s"] = float(rt["len"]) - END_MARGIN if float(rv["dir"]) > 0.0 else END_MARGIN
			rv["state"] = "unload"
			rv["t"] = 0.0
			rv["v"] = 0.0
		"turn":
			rv["s"] = float(rt["len"]) - END_MARGIN if float(rv["dir"]) > 0.0 else END_MARGIN
			rv["v"] = 0.0
			_place(rv, 0.0)
			_start_turn(rv)
		"mid":
			rv["state"] = "drive"
			rv["s"] = float(rt["len"]) * 0.5
			rv["v"] = float(rv["cruise"])
	_place(rv, 0.0)

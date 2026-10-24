class_name ColonyLife
extends Node3D
## The colony's moving life, purely illustrative (bible p.11: never changes
## population data). Colonists walk door to door along the walking grid
## (ColonyPaths) and play their walk/idle clips; work robots circle the
## construction sites; drones hop between rooftops; a few hover vehicles drive
## the dirt roads; at the market corners (ColonyStreets) a few colonists stand
## and browse, glancing around now and then. Counts follow the colony's size;
## pack files that are missing are skipped (the colonists fall back to their proxies).

const MAX_ROUTES_PER_FRAME := 3

var terrain: TerrainBuilder
var paths: ColonyPaths
var living_center := Vector2.ZERO

var _people: Array = []    # [{node, anim, robot, route, i, wait, speed, seed}]
var _drones: Array = []    # [{node, from, to, t, dur, wait, h, blink}]
var _vehicles: Array = []  # [{node, road, s, dir, speed, wait, hover, len}]
var _crowd: Array = []     # [{node, anim, yaw, look, t}] colonists standing at the market corners
var _rng := RandomNumberGenerator.new()
var _targets: Array = []   # Vector2 of construction sites
var _doors: Array = []     # [Vector2 door, bool living]
var _t := 0.0
var _blink_mat: StandardMaterial3D


func _init() -> void:
	name = "Life"
	_rng.seed = 7331


## Up to data life.walkers.max visible citizens illustrate the cohorts; robots
## show up at construction sites.
func sync_people(gs: GameState) -> void:
	var want_people := mini(DictUtil.get_int(_life_cfg("walkers"), "max", 40), gs.population.alive_count())
	_targets.clear()
	for b: Dictionary in gs.colony.buildings:
		if b["state"] == ColonyState.B_CONSTRUCTING:
			_targets.append(Vector2(float(b["x"]), float(b["z"])))
	var want := want_people + mini(_targets.size() * 2, 12)
	var kids_only := gs.population.count_stage("adult") == 0
	while _people.size() < want:
		var idx := _people.size()
		var is_robot := idx >= want_people
		var slot := "char.robot_worker" if is_robot else ("char.citizen_child" if kids_only or idx % 3 == 0 else "char.citizen_adult")
		var n := VisualSlot.make(slot)
		n.variant = idx
		var start := _random_door() if not _doors.is_empty() else living_center
		n.position = Vector3(start.x, terrain.height_at(start.x, start.y), start.y)
		add_child(n)
		var child := slot == "char.citizen_child"
		_people.append({"node": n, "anim": CharacterAnimator.for_slot(n), "robot": is_robot, "route": PackedVector2Array(), "i": 0,
			"wait": _rng.randf_range(0.0, 4.0), "speed": (1.05 if child else 1.35) * _rng.randf_range(0.9, 1.1), "seed": idx, "first": true})
	while _people.size() > want:
		var p: Dictionary = _people.pop_back()
		(p["node"] as Node).queue_free()


## New layout (buildings or roads changed): refresh destinations, drones and vehicles.
func relayout(gs: GameState, new_paths: ColonyPaths) -> void:
	paths = new_paths
	_doors.clear()
	var active: Array = []
	for b: Dictionary in gs.colony.buildings:
		if b["state"] != ColonyState.B_ACTIVE:
			continue
		active.append(b)
		var def := GameSession.content.building(str(b["def_id"]))
		var d := paths.door(b, living_center)
		if paths.walkable(d):
			_doors.append([d, str(def.get("district", "")) == "living" or str(b["def_id"]) in ["ark_core", "greenhouse", "clinic"]])
	for p: Dictionary in _people:
		p["route"] = PackedVector2Array()  # re-plan on the new grid
		p["wait"] = minf(float(p["wait"]), 0.5)
	_sync_drones(active)
	_sync_vehicles(active.size())


func _random_door() -> Vector2:
	if _doors.is_empty():
		return living_center
	# Mostly homes, the ark, greenhouse and clinic; sometimes anywhere.
	for i: int in 4:
		var d: Array = _doors[_rng.randi() % _doors.size()]
		if d[1] or _rng.randf() < 0.3:
			return d[0]
	return (_doors[_rng.randi() % _doors.size()] as Array)[0]


func _process(delta: float) -> void:
	if terrain == null:
		return
	_t += delta
	var planned := 0
	for p: Dictionary in _people:
		var n: VisualSlot = p["node"]
		if bool(p["robot"]):
			_robot(p, n)
			continue
		var route: PackedVector2Array = p["route"]
		if route.is_empty() or int(p["i"]) >= route.size():
			p["wait"] = float(p["wait"]) - delta
			(p["anim"] as CharacterAnimator).update("idle", 0.0)
			if float(p["wait"]) <= 0.0 and planned < MAX_ROUTES_PER_FRAME and paths != null:
				planned += 1
				var from := Vector2(n.position.x, n.position.z)
				var r := paths.route(from, _random_door())
				p["route"] = r
				p["i"] = 1
				p["wait"] = _rng.randf_range(2.0, 7.0)
				if bool(p["first"]) and r.size() > 2:
					# Start the colony mid-stride instead of everyone leaving home at once.
					p["first"] = false
					var k := _rng.randi_range(0, r.size() - 2)
					n.position = Vector3(r[k].x, terrain.height_at(r[k].x, r[k].y), r[k].y)
					p["i"] = k + 1
			continue
		var target: Vector2 = route[int(p["i"])]
		var pos := Vector2(n.position.x, n.position.z)
		var step := float(p["speed"]) * delta
		var to := target - pos
		if to.length() <= step:
			pos = target
			p["i"] = int(p["i"]) + 1
		else:
			pos += to.normalized() * step
		if to.length() > 0.01:
			n.rotation.y = lerp_angle(n.rotation.y, atan2(to.x, to.y), clampf(delta * 8.0, 0.0, 1.0))
		n.position = Vector3(pos.x, terrain.height_at(pos.x, pos.y), pos.y)
		(p["anim"] as CharacterAnimator).update("walk", float(p["speed"]))
	_move_drones(delta)
	_move_vehicles(delta)
	_idle_crowd(delta)


## Work robots circle their construction site (as before), now animated.
func _robot(p: Dictionary, n: VisualSlot) -> void:
	var s := float(int(p["seed"]))
	var center := living_center
	var rad := 14.0
	if not _targets.is_empty():
		center = _targets[int(s) % _targets.size()]
		rad = 5.0
	var ang := _t * (0.05 + fmod(s * 0.37, 0.1)) + s * 1.7
	var pt := center + Vector2(cos(ang), sin(ang * 0.8)) * rad * (0.4 + fmod(s * 0.13, 0.6))
	n.position = Vector3(pt.x, terrain.height_at(pt.x, pt.y), pt.y)
	n.rotation.y = -ang
	(p["anim"] as CharacterAnimator).update("walk", 1.0)


func _life_cfg(key: String) -> Dictionary:
	return DictUtil.get_dict(DictUtil.get_dict(BuildingDressing.doc(), "life"), key)


func _sync_drones(active: Array) -> void:
	var cfg := _life_cfg("drones")
	var mesh := str(cfg.get("mesh", ""))
	var want := mini(DictUtil.get_int(cfg, "max", 10), active.size() / maxi(1, DictUtil.get_int(cfg, "per_buildings", 4)))
	if BuildingDressing.parts(mesh).is_empty() or active.size() < 2:
		want = 0
	while _drones.size() > want:
		var d: Dictionary = _drones.pop_back()
		(d["node"] as Node).queue_free()
	var hs: Array = DictUtil.get_arr(cfg, "height")
	var tops: Array = []
	for b: Dictionary in active:
		tops.append(Vector2(float(b["x"]), float(b["z"])))
	while _drones.size() < want:
		var node := Node3D.new()
		var body := BuildingDressing.instance(mesh)
		if body == null:
			break
		body.scale = Vector3.ONE * 0.9
		node.add_child(body)
		node.add_child(_blinker())
		add_child(node)
		var a: Vector2 = tops[_rng.randi() % tops.size()]
		_drones.append({"node": node, "from": a, "to": a, "t": 1.0, "dur": 1.0, "wait": _rng.randf_range(0.0, 3.0),
			"h": _rng.randf_range(float(hs[0]) if hs.size() == 2 else 5.0, float(hs[1]) if hs.size() == 2 else 9.0), "seed": _drones.size()})
	for d: Dictionary in _drones:
		d["tops"] = tops


func _blinker() -> MeshInstance3D:
	if _blink_mat == null:
		_blink_mat = StandardMaterial3D.new()
		_blink_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_blink_mat.albedo_color = Color("#ff5a4a")
		_blink_mat.emission_enabled = true
		_blink_mat.emission = Color("#ff5a4a")
		_blink_mat.emission_energy_multiplier = 4.0
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.09
	sm.height = 0.18
	sm.radial_segments = 6
	sm.rings = 3
	mi.mesh = sm
	mi.material_override = _blink_mat
	mi.position.y = 0.55
	mi.name = "Blink"
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


func _move_drones(delta: float) -> void:
	var cfg := _life_cfg("drones")
	var speed := DictUtil.get_float(cfg, "speed", 5.0)
	for d: Dictionary in _drones:
		var node: Node3D = d["node"]
		var tops: Array = d.get("tops", [])
		if float(d["t"]) >= 1.0:
			d["wait"] = float(d["wait"]) - delta
			if float(d["wait"]) <= 0.0 and not tops.is_empty():
				d["from"] = d["to"]
				d["to"] = tops[_rng.randi() % tops.size()] + Vector2(_rng.randf_range(-3, 3), _rng.randf_range(-3, 3))
				d["t"] = 0.0
				d["dur"] = maxf(1.5, (d["from"] as Vector2).distance_to(d["to"]) / speed)
				d["wait"] = _rng.randf_range(1.0, 4.0)
		else:
			d["t"] = minf(1.0, float(d["t"]) + delta / float(d["dur"]))
		var k := smoothstep(0.0, 1.0, float(d["t"]))
		var p: Vector2 = (d["from"] as Vector2).lerp(d["to"], k)
		var s := float(int(d["seed"]))
		var arc := sin(float(d["t"]) * PI) * 2.0  # climb a little mid-hop
		var y := terrain.height_at(p.x, p.y) + float(d["h"]) + arc + sin(_t * 1.7 + s) * 0.25
		node.position = Vector3(p.x, y, p.y)
		var dir: Vector2 = (d["to"] as Vector2) - (d["from"] as Vector2)
		if dir.length() > 0.5 and float(d["t"]) < 1.0:
			node.rotation.y = lerp_angle(node.rotation.y, atan2(dir.x, dir.y), clampf(delta * 3.0, 0.0, 1.0))
			node.rotation.x = lerpf(node.rotation.x, 0.18 * sin(float(d["t"]) * PI), clampf(delta * 3.0, 0.0, 1.0))
		else:
			node.rotation.x = lerpf(node.rotation.x, 0.0, clampf(delta * 3.0, 0.0, 1.0))
		var bl := node.get_node_or_null("Blink")
		if bl:
			(bl as Node3D).visible = fmod(_t + s * 0.37, 1.2) < 0.15


func _sync_vehicles(active_count: int) -> void:
	var cfg := _life_cfg("vehicles")
	var meshes: Array = DictUtil.get_arr(cfg, "meshes")
	var hovers: Array = DictUtil.get_arr(cfg, "hover")
	for v: Dictionary in _vehicles:
		(v["node"] as Node).queue_free()
	_vehicles.clear()
	if paths == null or paths.roads.is_empty():
		return
	var want := mini(DictUtil.get_int(cfg, "max", 5), active_count / maxi(1, DictUtil.get_int(cfg, "per_buildings", 6)))
	var ps := DictUtil.get_float(BuildingDressing.doc(), "prop_scale", 0.72)
	for i: int in want:
		var mi := i % maxi(1, meshes.size())
		var body := BuildingDressing.instance(str(meshes[mi])) if not meshes.is_empty() else null
		if body == null:
			continue
		var node := Node3D.new()
		var box: AABB = BuildingDressing.parts(str(meshes[mi])).get("aabb", AABB())
		body.scale = Vector3.ONE * ps
		body.position = -Vector3(box.get_center().x, box.position.y, box.get_center().z) * ps
		node.add_child(body)
		add_child(node)
		var road: PackedVector2Array = paths.roads[i % paths.roads.size()]
		var length := 0.0
		for k: int in range(1, road.size()):
			length += road[k - 1].distance_to(road[k])
		_vehicles.append({"node": node, "road": road, "len": length, "s": _rng.randf() * length, "dir": 1.0 if i % 2 == 0 else -1.0,
			"speed": DictUtil.get_float(cfg, "speed", 4.0) * _rng.randf_range(0.8, 1.15), "wait": 0.0,
			"hover": float(hovers[mi]) if mi < hovers.size() else 0.0, "seed": i})


func _move_vehicles(delta: float) -> void:
	for v: Dictionary in _vehicles:
		var node: Node3D = v["node"]
		var length := float(v["len"])
		if float(v["wait"]) > 0.0:
			v["wait"] = float(v["wait"]) - delta
		else:
			var s := float(v["s"]) + float(v["dir"]) * float(v["speed"]) * delta
			if s <= 2.0 or s >= length - 2.0:
				# Turn around at the road's end after a short stop.
				s = clampf(s, 2.0, length - 2.0)
				v["dir"] = -float(v["dir"])
				v["wait"] = _rng.randf_range(2.0, 5.0)
			v["s"] = s
		var at := _along(v["road"], float(v["s"]))
		var p: Vector2 = at[0]
		var tan: Vector2 = (at[1] as Vector2) * float(v["dir"])
		p += tan.orthogonal() * -0.9  # keep to one side so oncoming traffic passes
		var hv := float(v["hover"])
		var y := terrain.height_at(p.x, p.y) + hv + (sin(_t * 2.1 + float(v["seed"])) * 0.06 if hv > 0.0 else 0.0)
		node.position = Vector3(p.x, y, p.y)
		node.rotation.y = lerp_angle(node.rotation.y, atan2(tan.x, tan.y), clampf(delta * 4.0, 0.0, 1.0))


## Colonists standing at the market corners (spots [Vector2, yaw] from
## ColonyDressing.crowd): as many as data life.crowd allows and the colony has
## adults; respawned only when the spots change. Purely illustrative.
func set_crowd(gs: GameState, spots: Array) -> void:
	for c: Dictionary in _crowd:
		(c["node"] as Node).queue_free()
	_crowd.clear()
	var cfg := _life_cfg("crowd")
	var want := mini(mini(spots.size(), DictUtil.get_int(cfg, "max", 24)), gs.population.alive_count() / maxi(1, DictUtil.get_int(cfg, "per_people", 8)))
	var kids_only := gs.population.count_stage("adult") == 0
	for i: int in want:
		var sp: Array = spots[i]
		var p: Vector2 = sp[0]
		var slot := "char.citizen_child" if kids_only or i % 5 == 4 else "char.citizen_adult"
		var n := VisualSlot.make(slot)
		n.variant = 100 + i
		n.position = Vector3(p.x, terrain.height_at(p.x, p.y), p.y)
		n.rotation.y = float(sp[1])
		add_child(n)
		_crowd.append({"node": n, "anim": CharacterAnimator.for_slot(n), "yaw": float(sp[1]), "look": 0.0, "t": _rng.randf_range(1.0, 6.0)})


func _idle_crowd(delta: float) -> void:
	for c: Dictionary in _crowd:
		c["t"] = float(c["t"]) - delta
		if float(c["t"]) <= 0.0:
			c["t"] = _rng.randf_range(2.5, 8.0)
			c["look"] = _rng.randf_range(-0.7, 0.7) if _rng.randf() < 0.6 else 0.0
		var n: Node3D = c["node"]
		n.rotation.y = lerp_angle(n.rotation.y, float(c["yaw"]) + float(c["look"]), clampf(delta * 2.0, 0.0, 1.0))
		(c["anim"] as CharacterAnimator).update("idle", 0.0)


## Evidence: where a colonist is walking right now (or any colonist).
func walker() -> Node3D:
	for p: Dictionary in _people:
		var r: PackedVector2Array = p["route"]
		if not bool(p["robot"]) and not r.is_empty() and int(p["i"]) < r.size() - 3:
			return p["node"]
	return (_people[0]["node"] as Node3D) if not _people.is_empty() else null


## Point and unit tangent at arc length s along a polyline.
static func _along(pts: PackedVector2Array, s: float) -> Array:
	var acc := 0.0
	for k: int in range(1, pts.size()):
		var seg := pts[k - 1].distance_to(pts[k])
		if acc + seg >= s or k == pts.size() - 1:
			var f := clampf((s - acc) / maxf(seg, 0.001), 0.0, 1.0)
			return [pts[k - 1].lerp(pts[k], f), (pts[k] - pts[k - 1]).normalized()]
		acc += seg
	return [pts[0], Vector2.UP]

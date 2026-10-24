class_name ColonyStreets
extends RefCounted
## Street life between and along the buildings, after the Synty Sci-Fi Worlds
## key art (D-045): market corners in the open courtyards of a district (a stall
## with its back to a wall, goods, signs, people sitting by it and spots where
## colonists stand and browse), billboards, sign towers and parked vehicles on
## the road shoulders near the districts, and on scavenger worlds smoking
## refinery silos and glowing toxic pools at the edge of the industrial area.
## Everything comes from the colony style's block in data/art/colony_dressing.json
## ("styles" -> markets, corners, yards, roadside, pools), so corporation,
## scavenger and explorer colonies read differently.
## World-space items in the BuildingDressing format; every item is tested
## against footprints, tubes, roads and the props that already stand.
## Presentation only; deterministic; missing pack files are skipped.


## clear: footprints/tubes/roads. taken: discs of the props already standing
## (grown as items are added). districts: [[key, Vector2 centre, radius]].
## roads: Array of PackedVector2Array. Returns {"items": [...], "crowd":
## [[Vector2, yaw]], "pools": [[Vector2 centre, Vector2 radii, yaw]]}.
static func plan(clear: ColonyClearance, taken: ColonyClearance, districts: Array, roads: Array) -> Dictionary:
	var out := {"items": [], "crowd": [], "pools": [], "counts": {}}
	if clear.rects().size() < 2:
		return out
	var ps := DictUtil.get_float(BuildingDressing.doc(), "prop_scale", 0.72)
	# Big market corners first (open courtyards), then small stall corners in the
	# tighter lanes, then work yards (smoking silos) in the industrial district.
	for sec: String in ["markets", "corners", "yards"]:
		_markets(out, clear, taken, districts, BuildingDressing.style_cfg(sec), ps, sec)
	_roadside(out, clear, taken, districts, roads, BuildingDressing.style_cfg("roadside"), ps)
	_pools(out, clear, taken, districts, BuildingDressing.style_cfg("pools"))
	return out


## Market corners: a seeded walk over a grid in each listed district; a spot
## that keeps spot_r clear and has a wall within "near" gets one kit, its back
## to the nearest wall, at least "spacing" from the last market.
static func _markets(out: Dictionary, clear: ColonyClearance, taken: ColonyClearance, districts: Array, cfg: Dictionary, ps: float, tag: String) -> void:
	var kits: Array = DictUtil.get_arr(cfg, "kits")
	if kits.is_empty():
		return
	var step := DictUtil.get_float(cfg, "step", 3.0)
	var spot_r := DictUtil.get_float(cfg, "spot_r", 2.2)
	var near := DictUtil.get_float(cfg, "near", 7.0)
	var spacing := DictUtil.get_float(cfg, "spacing", 9.0)
	for d: Array in districts:
		var dk := str(d[0])
		if not dk in DictUtil.get_arr(cfg, "districts"):
			continue
		var centre: Vector2 = d[1]
		var rad := float(d[2]) * DictUtil.get_float(cfg, "reach", 1.1)
		var cand: Array = []
		var n := int(rad * 2.0 / step) + 1
		for ix: int in n:
			for iz: int in n:
				var p := centre + Vector2(-rad + ix * step, -rad + iz * step)
				if p.distance_to(centre) <= rad:
					cand.append(p)
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(tag + "#" + dk)
		for i: int in range(cand.size() - 1, 0, -1):  # seeded shuffle: markets spread over the district
			var j := rng.randi_range(0, i)
			var t: Variant = cand[i]
			cand[i] = cand[j]
			cand[j] = t
		var placed: Array = []
		var cap := DictUtil.get_int(cfg, "max", 6)
		for p: Vector2 in cand:
			if placed.size() >= cap:
				break
			if clear.blocked(p, spot_r) or taken.blocked(p, spot_r):
				continue
			var hood := clear.rects_near(p, near)
			if hood.size() < DictUtil.get_int(cfg, "min_buildings", 1):
				continue
			var far := true
			for q: Vector2 in placed:
				if q.distance_to(p) < spacing:
					far = false
					break
			if not far:
				continue
			var kit: Dictionary = ColonyInfill._pick(kits, rng)
			if _place_kit(out, kit, p, _face_open(p, hood), clear, taken, rng, ps, dk):
				placed.append(p)
				out["counts"][tag] = int(out["counts"].get(tag, 0)) + 1


## Facing away from the nearest wall, snapped to quarter turns (planned, not random).
static func _face_open(p: Vector2, hood: Array) -> float:
	var bd := INF
	var cw := p + Vector2(0, -1)
	for r: Rect2 in hood:
		var c := Vector2(clampf(p.x, r.position.x, r.end.x), clampf(p.y, r.position.y, r.end.y))
		if c.distance_to(p) < bd:
			bd = c.distance_to(p)
			cw = c
	var away := (p - cw) if p.distance_to(cw) > 0.01 else Vector2(0, 1)
	return snappedf(atan2(away.x, away.y), PI * 0.5)


## One kit at p facing yaw: parts [set, across, forward, extra yaw deg, lift m]
## and crowd spots [across, forward, facing deg] (0 = looking back at the kit).
## The first part is the anchor: when it does not fit, nothing is placed.
static func _place_kit(out: Dictionary, kit: Dictionary, p: Vector2, yaw: float, clear: ColonyClearance, taken: ColonyClearance,
		rng: RandomNumberGenerator, ps: float, dk: String = "") -> bool:
	var mine: Array = []  # [Vector2, r] placed by this kit
	var first := true
	for part: Variant in DictUtil.get_arr(kit, "parts"):
		var pa: Array = part
		var items := BuildingDressing._set_items(str(pa[0]))
		if items.is_empty():
			if first:
				return false
			continue
		var it: Dictionary = items[rng.randi() % items.size()]
		var q := p + Vector2(float(pa[1]), float(pa[2])).rotated(-yaw)
		var rr := BuildingDressing._radius(it, ps)
		var fit := not clear.blocked(q, rr * 0.85) and not taken.blocked(q, rr * 0.85)
		if fit and not first:
			for m: Array in mine:
				if (m[0] as Vector2).distance_to(q) < (float(m[1]) + rr) * 0.55:
					fit = false
					break
		if not fit:
			if first:
				return false
			continue
		first = false
		var item := ColonyInfill._item(it, q, yaw + deg_to_rad(float(pa[3]) if pa.size() > 3 else 0.0), ps, float(pa[4]) if pa.size() > 4 else 0.0)
		item["kind"] = "street"
		(out["items"] as Array).append(item)
		mine.append([q, rr])
	for m: Array in mine:
		taken.add_segment(m[0], m[0], float(m[1]))
	_floor(out, kit, p, yaw, dk)
	for c: Variant in DictUtil.get_arr(kit, "crowd"):
		var ca: Array = c
		var q := p + Vector2(float(ca[0]), float(ca[1])).rotated(-yaw)
		if clear.blocked(q, 0.4) or taken.blocked(q, 0.3):
			continue
		(out["crowd"] as Array).append([q, yaw + PI + deg_to_rad(float(ca[2]) if ca.size() > 2 else 0.0)])
		taken.add_segment(q, q, 0.35)
	return true


## A paved patch under a market (kit "floor": [width, depth, forward offset] m):
## one platform tile from data "platform.tiles" in the market's district tint, so
## the stall stands on a plaza and not on bare ground. Never culled (radius 0).
static func _floor(out: Dictionary, kit: Dictionary, p: Vector2, yaw: float, dk: String) -> void:
	var fl: Array = DictUtil.get_arr(kit, "floor")
	var tiles: Array = BuildingDressing._tiles(false)
	if fl.size() < 2 or tiles.is_empty():
		return
	var t := str(tiles[0])
	var box: AABB = BuildingDressing.parts(t)["aabb"]
	var w := float(fl[0])
	var dep := float(fl[1])
	var c := p + Vector2(0, float(fl[2]) if fl.size() > 2 else 0.0).rotated(-yaw)
	var sc := Vector3(w / maxf(box.size.x, 0.01), DictUtil.get_float(BuildingDressing.doc(), "prop_scale", 0.72), dep / maxf(box.size.z, 0.01))
	var xf := Transform3D(Basis(Vector3.UP, yaw) * Basis.from_scale(sc), Vector3(c.x, 0.04, c.y)) * Transform3D(Basis.IDENTITY, -Vector3(box.get_center().x, box.end.y, box.get_center().z))
	var tc: Array = DictUtil.get_arr(DictUtil.get_dict(DictUtil.get_dict(BuildingDressing.doc(), "platform"), "tint"), dk)
	var tint := "%.3f,%.3f,%.3f" % [float(tc[0]), float(tc[1]), float(tc[2])] if tc.size() >= 3 else ""
	(out["items"] as Array).append({"mesh": t, "xf": xf, "r": 0.0, "light": "", "light_at": Vector3.ZERO, "top": 0.0, "build": true, "kind": "street", "tint": tint})


## Road shoulders near the districts: every "every" metres, alternating sides,
## one item from a weighted list; "face": "road" turns its front to the road,
## "along" parks it nose along the road.
static func _roadside(out: Dictionary, clear: ColonyClearance, taken: ColonyClearance, districts: Array, roads: Array, cfg: Dictionary, ps: float) -> void:
	var kinds: Array = DictUtil.get_arr(cfg, "kinds")
	if kinds.is_empty() or roads.is_empty():
		return
	var every := DictUtil.get_float(cfg, "every", 15.0)
	var half := DictUtil.get_float(DictUtil.get_dict(BuildingDressing.doc(), "roads"), "width", 3.0) * 0.5 + 0.3
	var reach := DictUtil.get_float(cfg, "reach", 1.6)
	var cap := DictUtil.get_int(cfg, "max", 20)
	var count := 0
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("roadside#%d" % roads.size())
	for ri: int in roads.size():
		var rd: PackedVector2Array = roads[ri]
		var length := 0.0
		for k: int in range(1, rd.size()):
			length += rd[k - 1].distance_to(rd[k])
		var s := every * 0.5
		var side := 1.0 if ri % 2 == 0 else -1.0
		while s < length - 2.0 and count < cap:
			var at := ColonyLife._along(rd, s)
			s += every * rng.randf_range(0.8, 1.2)
			side = -side
			var p: Vector2 = at[0]
			var tan: Vector2 = at[1]
			var in_town := false
			for d: Array in districts:
				if p.distance_to(d[1]) < float(d[2]) * reach:
					in_town = true
					break
			if not in_town:
				continue
			var kind: Dictionary = ColonyInfill._pick(kinds, rng)
			var items := BuildingDressing._set_items(str(kind.get("set", "")))
			if items.is_empty():
				continue
			var it: Dictionary = items[rng.randi() % items.size()]
			var nrm := tan.orthogonal() * side
			var box: AABB = BuildingDressing.parts(str(it["mesh"]))["aabb"]
			var sc := ps * DictUtil.get_float(it, "scale", 1.0)
			var along := str(kind.get("face", "road")) == "along"
			# Clearance across the road: half the depth for a sign, half the width for a parked car.
			var across := (minf(box.size.x, box.size.z) if along else box.size.z) * 0.5 * sc
			var q := p + nrm * (half + across + DictUtil.get_float(cfg, "gap", 0.5))
			# Test the long side as a row of discs along the road (a billboard or a car is long, not round).
			var span := maxf(0.0, (maxf(box.size.x, box.size.z) if along else box.size.x) * 0.5 * sc - across)
			var free := true
			for k: int in 3:
				var o := q + tan * span * float(k - 1)
				if clear.blocked(o, across + 0.2) or taken.blocked(o, across + 0.3):
					free = false
					break
			if not free:
				continue
			var yaw := atan2(tan.x, tan.y) + (PI if rng.randf() < 0.5 else 0.0) if along else atan2(-nrm.x, -nrm.y)
			var item := ColonyInfill._item(it, q, yaw, ps)
			item["kind"] = "street"
			(out["items"] as Array).append(item)
			taken.add_segment(q - tan * span, q + tan * span, across + 0.2)
			count += 1
			out["counts"][str(kind.get("set", ""))] = int(out["counts"].get(str(kind.get("set", "")), 0)) + 1


## Glowing pools in the given district's outskirts (scavenger refinery spill):
## [centre, radii, yaw] for ColonyDressing to draw; tested like any prop.
static func _pools(out: Dictionary, clear: ColonyClearance, taken: ColonyClearance, districts: Array, cfg: Dictionary) -> void:
	if cfg.is_empty():
		return
	var rs: Array = DictUtil.get_arr(cfg, "r")
	for d: Array in districts:
		if str(d[0]) != str(cfg.get("district", "resource")):
			continue
		var rng := RandomNumberGenerator.new()
		rng.seed = hash("pools#" + str(d[0]))
		var want := DictUtil.get_int(cfg, "n", 5)
		var placed := 0
		for i: int in 160:
			if placed >= want:
				break
			var ang := rng.randf() * TAU
			var dist := float(d[2]) * rng.randf_range(DictUtil.get_float(cfg, "from", 0.5), DictUtil.get_float(cfg, "to", 1.25))
			var c: Vector2 = (d[1] as Vector2) + Vector2.from_angle(ang) * dist
			var r := rng.randf_range(float(rs[0]) if rs.size() == 2 else 1.0, float(rs[1]) if rs.size() == 2 else 2.0)
			if clear.blocked(c, r + 0.4) or taken.blocked(c, r):
				continue
			var radii := Vector2(r, r * rng.randf_range(0.55, 0.85))
			(out["pools"] as Array).append([c, radii, rng.randf() * PI])
			taken.add_segment(c, c, r)
			placed += 1

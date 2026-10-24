class_name ColonyInfill
extends RefCounted
## Street furniture for the gaps between buildings (data/art/colony_dressing.json
## -> "infill"), so a dense year-40 district reads like a planned town instead of
## platforms with nothing between them: planters, benches, lamps, bins, signs and
## cargo in the lanes and small courtyards that are too tight for the per-building
## dressing. A regular grid (planned, not random) is tested against footprints,
## corridors, roads and the building props that already stand; each free spot
## that sits between at least two buildings gets one small kit chosen by the
## district it belongs to. World-space placements in the BuildingDressing item
## format ({"mesh", "xf", "r", "light", "light_at", "top", "kind"}). Presentation
## only; deterministic; missing pack files are skipped.


static func plan(clear: ColonyClearance, kept: Array, districts: Array) -> Array:
	var out: Array = []
	var cfg: Dictionary = DictUtil.get_dict(BuildingDressing.doc(), "infill")
	if cfg.is_empty() or clear.rects().size() < 4:
		return out
	var near := DictUtil.get_float(cfg, "near", 7.0)
	var spot_r := DictUtil.get_float(cfg, "spot_r", 0.9)
	var ps := DictUtil.get_float(BuildingDressing.doc(), "prop_scale", 0.72)
	var own: Dictionary = BuildingDressing.style_cfg("infill")  # the style's street furniture joins the shared kits
	var passes: Array = [[_merged(DictUtil.get_dict(cfg, "kits"), DictUtil.get_dict(own, "kits")), spot_r, 0.0],
		[_merged(DictUtil.get_dict(cfg, "lanes"), DictUtil.get_dict(own, "lanes")), DictUtil.get_float(cfg, "lane_r", 0.4), DictUtil.get_float(cfg, "step", 3.2) * 0.5]]
	# Props already standing (building dressing) plus everything placed here.
	var taken := ColonyClearance.new()
	for k: Array in kept:
		taken.add_segment(k[0], k[0], float(k[1]) * 0.85)
	var box := Rect2()
	for i: int in clear.rects().size():
		var r: Rect2 = clear.rects()[i][0]
		box = r if i == 0 else box.merge(r)
	box = box.grow(near * 0.5)
	for pass_cfg: Array in passes:
		_pass(out, clear, taken, districts, cfg, pass_cfg[0], float(pass_cfg[1]), float(pass_cfg[2]), box, ps)
	return out


## One sweep of the grid (offset by `shift`, e.g. half a step for the lanes).
static func _pass(out: Array, clear: ColonyClearance, taken: ColonyClearance, districts: Array, cfg: Dictionary, kits: Dictionary,
		spot_r: float, shift: float, box: Rect2, ps: float) -> void:
	if kits.is_empty():
		return
	var step := DictUtil.get_float(cfg, "step", 3.2)
	var near := DictUtil.get_float(cfg, "near", 7.0)
	var need := DictUtil.get_int(cfg, "min_buildings", 2)
	var x0 := snappedf(box.position.x, step) + shift
	var z0 := snappedf(box.position.y, step) + shift
	var nx := int(box.size.x / step) + 2
	var nz := int(box.size.y / step) + 2
	for ix: int in nx:
		for iz: int in nz:
			var p := Vector2(x0 + ix * step, z0 + iz * step)
			if clear.blocked(p, spot_r) or taken.blocked(p, spot_r):
				continue
			if shift > 0.0 and not clear.blocked(p, spot_r + 1.4):  # lane pass: only where it is really tight
				continue
			var hood := clear.rects_near(p, near)
			if hood.size() < need:
				continue
			var dk := _district(p, districts)
			var list: Array = DictUtil.get_arr(kits, dk) if kits.has(dk) else DictUtil.get_arr(kits, "_default")
			if list.is_empty():
				continue
			var rng := RandomNumberGenerator.new()
			rng.seed = hash(Vector2i(roundi(p.x * 10.0), roundi(p.y * 10.0)))
			if rng.randf() > DictUtil.get_float(cfg, "fill", 0.85):
				continue
			var kit: Dictionary = _pick(list, rng)
			# Face the open side: away from the nearest wall, snapped to the grid.
			var wall: Rect2 = hood[0]
			var bd := INF
			for r: Rect2 in hood:
				var c := Vector2(clampf(p.x, r.position.x, r.end.x), clampf(p.y, r.position.y, r.end.y))
				if c.distance_to(p) < bd:
					bd = c.distance_to(p)
					wall = r
			var cw := Vector2(clampf(p.x, wall.position.x, wall.end.x), clampf(p.y, wall.position.y, wall.end.y))
			var away := (p - cw) if p.distance_to(cw) > 0.01 else Vector2(0, 1)
			var yaw := snappedf(atan2(away.x, away.y), PI * 0.5)
			for part: Variant in DictUtil.get_arr(kit, "parts"):
				var pa: Array = part
				var items := BuildingDressing._set_items(str(pa[0]))
				if items.is_empty():
					continue
				var it: Dictionary = items[rng.randi() % items.size()]
				var off := Vector2(float(pa[1]), float(pa[2])).rotated(-yaw)
				var q := p + off
				var rr := BuildingDressing._radius(it, ps)
				if clear.blocked(q, rr) or taken.blocked(q, rr):
					continue
				out.append(_item(it, q, yaw + deg_to_rad(float(pa[3]) if pa.size() > 3 else 0.0), ps))
				taken.add_segment(q, q, rr)


## Kit lists per district: the shared ones plus the style's ("_replace": [keys]
## drops the shared list for those districts).
static func _merged(base: Dictionary, extra: Dictionary) -> Dictionary:
	if extra.is_empty():
		return base
	var out := base.duplicate()
	var drop: Array = DictUtil.get_arr(extra, "_replace")
	for k: String in extra.keys():
		if k.begins_with("_"):
			continue
		out[k] = (DictUtil.get_arr(extra, k) if k in drop else DictUtil.get_arr(base, k) + DictUtil.get_arr(extra, k))
	return out


static func _district(p: Vector2, districts: Array) -> String:
	var best := "_default"
	var bd := INF
	for d: Array in districts:  # [key, Vector2 centre, radius]
		var dd := p.distance_to(d[1]) / maxf(float(d[2]), 1.0)
		if dd < bd:
			bd = dd
			best = str(d[0])
	return best


static func _pick(list: Array, rng: RandomNumberGenerator) -> Dictionary:
	var total := 0.0
	for k: Dictionary in list:
		total += DictUtil.get_float(k, "w", 1.0)
	var t := rng.randf() * total
	for k: Dictionary in list:
		t -= DictUtil.get_float(k, "w", 1.0)
		if t <= 0.0:
			return k
	return list[0]


## One prop standing on the ground at p (bounds centred), world space at y = 0
## (+ lift metres). The set entry's "turn" (degrees) fixes a prefab whose front
## is not +Z, so "facing" in the kits always means the prop's front.
static func _item(it: Dictionary, p: Vector2, yaw: float, ps: float, lift: float = 0.0) -> Dictionary:
	var pr: Dictionary = BuildingDressing.parts(str(it["mesh"]))
	var box: AABB = pr["aabb"]
	var sc := ps * DictUtil.get_float(it, "scale", 1.0)
	var centre := Vector3(box.get_center().x, box.position.y, box.get_center().z)
	yaw += deg_to_rad(DictUtil.get_float(it, "turn", 0.0))
	var xf := Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * sc), Vector3(p.x, lift, p.y)) * Transform3D(Basis.IDENTITY, -centre)
	var la: Array = DictUtil.get_arr(it, "light_at")
	var lp := Vector3(float(la[0]), float(la[1]), float(la[2])) if la.size() == 3 else Vector3(box.get_center().x, box.end.y - box.size.y * 0.06, box.get_center().z)
	return {"mesh": str(it["mesh"]), "xf": xf, "r": maxf(box.size.x, box.size.z) * 0.5 * sc, "light": str(it.get("light", "")), "light_at": lp,
		"top": box.size.y * sc, "build": true, "kind": "infill", "glow": str(it.get("glow", "")), "glow_at": box.get_center(),
		"fx": str(it.get("fx", "")), "fx_scale": DictUtil.get_float(it, "fx_scale", 0.5), "fx_at": Vector3(box.get_center().x, box.end.y, box.get_center().z)}

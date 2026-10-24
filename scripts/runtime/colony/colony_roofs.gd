class_name ColonyRoofs
extends RefCounted
## Rooftop greebles (data/art/colony_dressing.json -> "roofs"): air units, vents,
## antennas and small dishes on the flat parts of a building's roof, so a dense
## district seen from above is not a field of bare tops. The roof is read from
## the model itself: its triangles are dropped onto a 0.5 m grid (highest hit per
## sample, bucketed by cell), and only spots whose neighbourhood is level within
## a few centimetres get a piece. Cached per building type; building-local items
## in the BuildingDressing format with kind "roof". Presentation only.

const CELL := 0.5

static var _maps: Dictionary = {}  # def_id -> {"spots": Array[Vector3]}


## Building-local roof items for one view (empty when the type has no roof spec).
static func plan(view: BuildingView) -> Array:
	var out: Array = []
	var cfg: Dictionary = DictUtil.get_dict(BuildingDressing.doc(), "roofs")
	var spec: Dictionary = DictUtil.get_dict(DictUtil.get_dict(cfg, "buildings"), view.def_id)
	if spec.is_empty():
		return out
	var spots: Array = _spots(view, cfg)
	if spots.is_empty():
		return out
	var ps := DictUtil.get_float(BuildingDressing.doc(), "prop_scale", 0.72)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("roof#%d" % view.building_id)
	var want := rng.randi_range(DictUtil.get_int(spec, "min", 1), DictUtil.get_int(spec, "max", 3))
	var used: Array[Vector3] = []
	var order := range(spots.size())
	for i: int in range(order.size() - 1, 0, -1):  # deterministic shuffle
		var j := rng.randi() % (i + 1)
		var t: int = order[i]
		order[i] = order[j]
		order[j] = t
	var sets: Array = DictUtil.get_arr(spec, "sets")
	for k: int in order:
		if used.size() >= want or sets.is_empty():
			break
		var p: Vector3 = spots[k]
		var it_list := BuildingDressing._set_items(str(sets[rng.randi() % sets.size()]))
		if it_list.is_empty():
			continue
		var it: Dictionary = it_list[rng.randi() % it_list.size()]
		var r := BuildingDressing._radius(it, ps)
		if r > DictUtil.get_float(cfg, "max_r", 0.7):
			continue
		var clash := false
		for u: Vector3 in used:
			if Vector2(u.x, u.z).distance_to(Vector2(p.x, p.z)) < r + 0.9:
				clash = true
		if clash or not _level(view.def_id, p, r):
			continue
		used.append(p)
		var item := ColonyInfill._item(it, Vector2(p.x, p.z), snappedf(rng.randf() * TAU, PI * 0.5), ps)
		var xf: Transform3D = item["xf"]
		xf.origin.y = p.y + xf.origin.y
		item["xf"] = xf
		item["kind"] = "roof"
		item["build"] = false
		out.append(item)
	return out


## Level roof samples (building-local, y = roof height) for this building type.
static func _spots(view: BuildingView, cfg: Dictionary) -> Array:
	if _maps.has(view.def_id):
		return (_maps[view.def_id] as Dictionary)["spots"]
	var tris := _triangles(view)
	if tris.is_empty():
		return []  # the model is not built yet; try again on the next layout
	var size: Vector2 = view.footprint()
	var buckets := {}
	for t: int in range(0, tris.size(), 3):
		var a: Vector3 = tris[t]
		var b: Vector3 = tris[t + 1]
		var c: Vector3 = tris[t + 2]
		var lo := Vector2i(floori(minf(a.x, minf(b.x, c.x)) / CELL), floori(minf(a.z, minf(b.z, c.z)) / CELL))
		var hi := Vector2i(floori(maxf(a.x, maxf(b.x, c.x)) / CELL), floori(maxf(a.z, maxf(b.z, c.z)) / CELL))
		if (hi.x - lo.x + 1) * (hi.y - lo.y + 1) > 400:
			continue
		for x: int in range(lo.x, hi.x + 1):
			for z: int in range(lo.y, hi.y + 1):
				var key := Vector2i(x, z)
				if not buckets.has(key):
					buckets[key] = []
				(buckets[key] as Array).append(t)
	var heights := {}
	var nx := int(size.x / CELL)
	var nz := int(size.y / CELL)
	for ix: int in nx:
		for iz: int in nz:
			var p := Vector2(-size.x * 0.5 + (ix + 0.5) * CELL, -size.y * 0.5 + (iz + 0.5) * CELL)
			var key := Vector2i(floori(p.x / CELL), floori(p.y / CELL))
			var top := -INF
			for t: int in buckets.get(key, []):
				var hit: Variant = Geometry3D.ray_intersects_triangle(Vector3(p.x, 60.0, p.y), Vector3.DOWN, tris[t], tris[t + 1], tris[t + 2])
				if hit != null:
					top = maxf(top, (hit as Vector3).y)
			heights[Vector2i(ix, iz)] = top
	var min_h := DictUtil.get_float(cfg, "min_height", 2.0)
	var flat := DictUtil.get_float(cfg, "flat", 0.06)
	var spots: Array = []
	for ix: int in range(1, nx - 1):
		for iz: int in range(1, nz - 1):
			var h := float(heights[Vector2i(ix, iz)])
			if h < min_h:
				continue
			var ok := true
			for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1)]:
				if absf(float(heights[Vector2i(ix, iz) + d]) - h) > flat:
					ok = false
					break
			if ok:
				spots.append(Vector3(-size.x * 0.5 + (ix + 0.5) * CELL, h, -size.y * 0.5 + (iz + 0.5) * CELL))
	_maps[view.def_id] = {"spots": spots, "heights": heights, "size": size}
	return spots


## True when the roof stays level under a piece of radius r at p.
static func _level(def_id: String, p: Vector3, r: float) -> bool:
	var m: Dictionary = _maps.get(def_id, {})
	var heights: Dictionary = m.get("heights", {})
	var size: Vector2 = m.get("size", Vector2.ZERO)
	var reach := int(ceil(r / CELL))
	var c := Vector2i(int((p.x + size.x * 0.5) / CELL), int((p.z + size.y * 0.5) / CELL))
	for dx: int in range(-reach, reach + 1):
		for dz: int in range(-reach, reach + 1):
			var k := c + Vector2i(dx, dz)
			if not heights.has(k) or absf(float(heights[k]) - p.y) > 0.12:
				return false
	return true


## The model's triangles in building space (the view's own transform removed).
static func _triangles(view: BuildingView) -> PackedVector3Array:
	var out := PackedVector3Array()
	var vis: Node = view.visual()
	if vis == null:
		return out
	var inv := view.global_transform.affine_inverse() if view.is_inside_tree() else Transform3D.IDENTITY
	for n: Node in vis.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null or not mi.is_inside_tree() or mi.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY:
			continue  # shadow twins (D-054) repeat their piece
		var xf := inv * mi.global_transform
		for v: Vector3 in mi.mesh.get_faces():
			out.append(xf * v)
	return out

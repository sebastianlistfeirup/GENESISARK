class_name PoiDressing
extends RefCounted
## Set dressing that makes the expedition's points of interest read as places
## (D-038): a landing camp around the lander, a dig at the main sample, an
## antenna site on the relay ridge, remains and growths in the hazard zones,
## marker poles along the safe route and warning clutter on the short one.
## Kits are data (data/art/surface_dressing.json), merged "any" + biome +
## planet + hazard id, and placed deterministically per site. Every piece keeps
## a clear radius around interactables, the lander and the route polylines, so
## nothing ever blocks a route or a prompt. Purely visual; missing pack files
## are skipped (fresh clone = bare markers). Flora scatter is GroundCover's job.

const PATH := "res://data/art/surface_dressing.json"
const MAP_HALF := 78.0

static var _info: Dictionary = {}  # prefab path -> {scene: PackedScene, aabb: AABB} or {}


static func build(terrain: TerrainBuilder, survey: Dictionary, planet: Dictionary, seed_value: int) -> Node3D:
	var root := Node3D.new()
	root.name = "PoiDressing"
	var d: Variant = DictUtil.load_json(PATH)
	if not d is Dictionary or terrain == null:
		return root
	var doc: Dictionary = d
	var ctx := {
		"terrain": terrain, "root": root, "placed": [],
		"biome": str(planet.get("biome_id", "green")), "planet": str(planet.get("id", "")),
		"clear": DictUtil.get_dict(doc, "clearance"), "points": [], "routes": [],
	}
	var pts: Dictionary = DictUtil.get_dict(survey, "points")
	(ctx["points"] as Array).append([Vector2.ZERO, float(ctx["clear"].get("lander", 5.5))])
	for k: String in pts.keys():
		if k != "lander":
			(ctx["points"] as Array).append([_pt(pts[k]), float(ctx["clear"].get("interactable", 4.0))])
	# Extra free spots relative to a point (e.g. the at_sample capture viewpoint).
	for kc: Variant in DictUtil.get_arr(doc, "keep_clear"):
		var c: Dictionary = kc
		if pts.has(str(c.get("anchor", ""))):
			var off: Array = DictUtil.get_arr(c, "offset")
			(ctx["points"] as Array).append([_pt(pts[str(c["anchor"])]) + Vector2(float(off[0]), float(off[1])), float(c.get("radius", 2.0))])
	for r: Dictionary in DictUtil.get_arr(survey, "routes"):
		var line: Array = [Vector2.ZERO]
		for w: Variant in DictUtil.get_arr(r, "waypoints"):
			var p := Vector2(float(w[0]), float(w[1]))
			if p.distance_to(line[-1]) > 0.1:
				line.append(p)
		(ctx["routes"] as Array).append(line)
	var kits: Dictionary = DictUtil.get_dict(doc, "kits")
	var rng := RandomNumberGenerator.new()
	# Order matters only for who gets the space first: camp, then the goals, then the rest.
	_kit(ctx, kits, "camp", Vector2.ZERO, 0.0, rng, seed_value + 11)
	for key: String in ["main_sample", "relay", "risk_sample"]:
		if pts.has(key):
			_kit(ctx, kits, key, _pt(pts[key]), 0.0, rng, seed_value + key.hash())
	for hz: Dictionary in DictUtil.get_arr(survey, "hazard_zones"):
		_kit(ctx, kits, "hazard_" + str(hz.get("hazard_id")), _pt(hz.get("center")), DictUtil.get_float(hz, "radius", 10.0), rng, seed_value + str(hz.get("hazard_id")).hash())
	var ri := 0
	for r: Dictionary in DictUtil.get_arr(survey, "routes"):
		_route_kit(ctx, kits, "route_" + str(r.get("id")), ctx["routes"][ri], rng, seed_value + 97 * (ri + 1))
		ri += 1
	MeshLod.apply_tree(root)  # D-054: LODs for pack meshes that ship without them
	return root


static func _pt(v: Variant) -> Vector2:
	var a: Array = v if v is Array else DictUtil.get_arr(v, "pos")
	return Vector2(float(a[0]), float(a[1])) if a.size() == 2 else Vector2.ZERO


## Entries of one kit: "any" + biome + planet (all optional).
static func _entries(ctx: Dictionary, kits: Dictionary, kit: String) -> Array:
	var k: Dictionary = DictUtil.get_dict(kits, kit)
	var out: Array = []
	for layer: String in ["any", str(ctx["biome"]), str(ctx["planet"])]:
		out.append_array(DictUtil.get_arr(k, layer))
	return out


static func _kit(ctx: Dictionary, kits: Dictionary, kit: String, anchor: Vector2, zone_r: float, rng: RandomNumberGenerator, seed_value: int) -> void:
	rng.seed = seed_value
	for e: Dictionary in _entries(ctx, kits, kit):
		var paths := _paths(e)
		if paths.is_empty():
			continue
		var ring: Array = DictUtil.get_arr(e, "ring")
		var rmin := float(ring[0]) if ring.size() == 2 else 0.0
		var rmax := float(ring[1]) if ring.size() == 2 else maxf(zone_r - 1.0, 1.0)
		if bool(e.get("in_zone", false)):
			rmax = maxf(rmin + 1.0, zone_r * float(e.get("zone_frac", 0.9)))
		var count := int(e.get("count", 1))
		var cl: Array = DictUtil.get_arr(e, "cluster")
		var phase := rng.randf() * TAU
		var placed := 0
		var tries := 0
		var miss := 0  # failed tries for the current piece
		while placed < count and tries < count * 30:
			tries += 1
			# Even spacing wobbles further on each failed try so a route crossing that sector cannot starve it.
			var jitter := minf(PI, 0.25 + 0.12 * miss)
			var ang := phase + TAU * placed / count + rng.randf_range(-jitter, jitter) if bool(e.get("even", false)) else rng.randf() * TAU
			var centre := anchor + Vector2.from_angle(ang) * rng.randf_range(rmin, rmax)
			var group := int(cl[0]) if cl.size() == 2 else 1
			var ok_any := false
			for gi: int in group:
				var p := centre if gi == 0 else centre + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.9, float(cl[1]))
				if _try_place(ctx, e, paths[rng.randi() % paths.size()], p, anchor, rng):
					ok_any = true
			if ok_any:
				placed += 1
				miss = 0
			else:
				miss += 1


## Pieces at a fixed spacing along a route, alternating sides, outside its clear corridor.
static func _route_kit(ctx: Dictionary, kits: Dictionary, kit: String, line: Array, rng: RandomNumberGenerator, seed_value: int) -> void:
	rng.seed = seed_value
	var clear := float(ctx["clear"].get("route", 2.6))
	for e: Dictionary in _entries(ctx, kits, kit):
		var paths := _paths(e)
		if paths.is_empty() or line.size() < 2:
			continue
		var every := float(e.get("every", 12.0))
		var off: Array = DictUtil.get_arr(e, "offset")
		var travelled := float(e.get("start", 8.0))
		var side := 1.0 if rng.randf() < 0.5 else -1.0
		var seg_start := 0.0
		for i: int in line.size() - 1:
			var a: Vector2 = line[i]
			var b: Vector2 = line[i + 1]
			var seg := b - a
			var length := seg.length()
			while travelled <= seg_start + length:
				var t := (travelled - seg_start) / maxf(length, 0.01)
				var n := Vector2(-seg.y, seg.x).normalized() * side
				var lateral := clear + rng.randf_range(float(off[0]) if off.size() == 2 else 0.4, float(off[1]) if off.size() == 2 else 1.0)
				var p := a + seg * t + n * lateral
				_try_place(ctx, e, paths[rng.randi() % paths.size()], p, a + seg * t, rng)
				if not bool(e.get("one_side", false)):
					side = -side
				travelled += every * rng.randf_range(0.85, 1.15)
			seg_start += length


static func _paths(e: Dictionary) -> Array:
	var raw: Array = DictUtil.get_arr(e, "meshes") if e.has("meshes") else [str(e.get("mesh", ""))]
	return raw.filter(func(p: Variant) -> bool: return not _source(str(p)).is_empty())


## Places one piece if it keeps every clearance; returns true when placed.
static func _try_place(ctx: Dictionary, e: Dictionary, path: String, p: Vector2, anchor: Vector2, rng: RandomNumberGenerator) -> bool:
	if absf(p.x) > MAP_HALF or absf(p.y) > MAP_HALF:
		return false
	var src := _source(path)
	var box: AABB = src["aabb"]
	var sz: Array = DictUtil.get_arr(e, "size")
	var s := float(e.get("scale", 1.0))
	if sz.size() == 2:
		s = rng.randf_range(float(sz[0]), float(sz[1])) / maxf(0.01, box.get_longest_axis_size())
	var foot := maxf(box.size.x, box.size.z) * s * 0.5 * float(e.get("footprint", 0.8))
	var ground := bool(e.get("ground", false))
	if not ground:
		for pt: Array in ctx["points"]:
			if p.distance_to(pt[0]) < float(pt[1]) + foot:
				return false
		var rc := float(ctx["clear"].get("route", 2.6))
		for line: Array in ctx["routes"]:
			for i: int in line.size() - 1:
				if _seg_dist(p, line[i], line[i + 1]) < rc + foot:
					return false
		var gap := float(ctx["clear"].get("spacing", 0.4))
		for q: Array in ctx["placed"]:
			if p.distance_to(q[0]) < float(q[1]) + foot + gap:
				return false
	var terrain: TerrainBuilder = ctx["terrain"]
	var inst: Node3D = (src["scene"] as PackedScene).instantiate()
	var holder := Node3D.new()
	holder.add_child(inst)
	var yaw := rng.randf() * TAU
	match str(e.get("face", "random")):
		"anchor":
			yaw = atan2(anchor.x - p.x, anchor.y - p.y) + rng.randf_range(-0.3, 0.3)
		"away":
			yaw = atan2(p.x - anchor.x, p.y - anchor.y) + rng.randf_range(-0.3, 0.3)
	var tilt := deg_to_rad(float(e.get("tilt", 0.0)))
	var basis := Basis(Vector3.UP, yaw)
	if tilt > 0.0:
		var ta := rng.randf() * TAU
		basis = basis * Basis(Vector3(cos(ta), 0, sin(ta)), rng.randf_range(0.3, 1.0) * tilt)
	var y := terrain.height_at(p.x, p.y) - box.position.y * s - box.size.y * s * float(e.get("sink_frac", 0.0)) - float(e.get("sink", 0.05))
	if e.has("flush_top"):  # flat pieces (pads): top surface just above the ground
		y = terrain.height_at(p.x, p.y) - box.end.y * s + float(e["flush_top"])
	holder.transform = Transform3D(basis.scaled(Vector3.ONE * s), Vector3(p.x, y, p.y))
	_style(inst, e)
	var root: Node3D = ctx["root"]
	root.add_child(holder)
	var top := box.end.y * s
	if e.has("lamp"):
		_lamp(holder, DictUtil.get_dict(e, "lamp"), top, s)
	if bool(e.get("collide", false)):
		var sb := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = maxf(0.3, foot * 0.75)
		cyl.height = maxf(0.5, box.size.y * s * (1.0 - float(e.get("sink_frac", 0.0))))
		cs.shape = cyl
		cs.position = Vector3(p.x, terrain.height_at(p.x, p.y) + cyl.height * 0.5, p.y)
		sb.add_child(cs)
		root.add_child(sb)
	if not ground:
		(ctx["placed"] as Array).append([p, foot])
	return true


static func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
	return p.distance_to(a + ab * t)


## Optional recolour (tint/glow) and distance culling on every mesh of a piece.
## Vendor colliders are dropped: collision belongs to the game (simple
## cylinders from "collide", placed outside every clear zone).
static func _style(inst: Node, e: Dictionary) -> void:
	for co: Node in inst.find_children("*", "CollisionObject3D", true, false):
		co.get_parent().remove_child(co)
		co.free()
	var mat: Material = null
	if e.has("tint"):
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(str(e["tint"]))
		m.roughness = float(e.get("roughness", 0.6))
		if e.has("glow"):
			m.emission_enabled = true
			m.emission = Color(str(e["tint"]))
			m.emission_energy_multiplier = float(e["glow"])
		mat = m
	var far := float(e.get("view", 170.0))
	var geos: Array = [inst] if inst is GeometryInstance3D else []
	geos.append_array(inst.find_children("*", "GeometryInstance3D", true, false))
	for g: Variant in geos:
		var gi := g as GeometryInstance3D
		gi.visibility_range_end = far
		if mat:
			gi.material_override = mat


## A glowing tip (emissive sphere) on top of a pole; optionally a real light.
static func _lamp(holder: Node3D, l: Dictionary, top: float, s: float) -> void:
	var col := Color(str(l.get("color", "#ffb347")))
	var tip := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = float(l.get("size", 0.14))
	sm.height = sm.radius * 2.0
	sm.radial_segments = 8
	sm.rings = 4
	tip.mesh = sm
	tip.material_override = AssetSlots.material(col.to_html(false), float(l.get("glow", 4.0)))
	tip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The holder is scaled; place the tip in world metres just above the top.
	tip.position = Vector3(0, top / s + float(l.get("above", 0.1)) / s, 0)
	tip.scale = Vector3.ONE / s
	holder.add_child(tip)
	if bool(l.get("omni", false)) and Quality.value("dressing_lights", 1.0) > 0.0:
		var o := OmniLight3D.new()
		o.light_color = col
		o.light_energy = float(l.get("energy", 2.0))
		o.omni_range = float(l.get("range", 7.0))
		o.shadow_enabled = false
		o.distance_fade_enabled = true
		o.distance_fade_begin = 60.0
		o.distance_fade_length = 20.0
		o.position = tip.position
		o.scale = Vector3.ONE / s
		holder.add_child(o)


static func _source(path: String) -> Dictionary:
	if _info.has(path):
		return _info[path]
	var out: Dictionary = {}
	if not path.is_empty() and ResourceLoader.exists(path):
		var ps := load(path) as PackedScene
		if ps:
			var inst := ps.instantiate()
			var box := AssetSlots.aabb_of(inst, Transform3D.IDENTITY)
			inst.free()
			if box.size.length() > 0.001:
				out = {"scene": ps, "aabb": box}
	_info[path] = out
	return out

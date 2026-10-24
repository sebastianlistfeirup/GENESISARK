class_name BuildingDressing
extends RefCounted
## Plans the set dressing around one colony building (data/art/colony_dressing.json):
## crates, barrels, power cells, antennas, dishes, lamps, planters, a parked
## vehicle, and a tiled Synty platform under the footprint. Everything is
## returned as building-local placements; ColonyDressing batches them into
## MultiMeshes for the whole colony and drops any that would touch a neighbour,
## a corridor or a road. Deterministic per building id. Props stand outside the
## footprint (plus the platform margin), so the building's pick collider and
## walkable body are never covered. Missing pack files are skipped silently.

const PATH := "res://data/art/colony_dressing.json"

static var _doc: Dictionary = {}
static var _loaded := false
static var _parts: Dictionary = {}  # resolved path -> {"parts": [[Mesh, Transform3D]], "aabb": AABB} or {}


static func doc() -> Dictionary:
	if not _loaded:
		_loaded = true
		var v: Variant = DictUtil.load_json(PATH) if FileAccess.file_exists(PATH) else null
		_doc = v if v is Dictionary else {}
	return _doc


## "W:Props/SM_Prop_Crate_03" -> res://assets/Synty/PolygonSciFiWorlds/Prefabs/Props/SM_Prop_Crate_03.tscn
static func resolve(short: String) -> String:
	var i := short.find(":")
	if i > 0 and i <= 2:
		var roots: Dictionary = DictUtil.get_dict(doc(), "roots")
		return str(roots.get(short.substr(0, i), "")) + short.substr(i + 1) + ".tscn"
	return short


## Every visible mesh of a prefab with its transform relative to the prefab root
## and the material overrides baked into a copy, plus the merged bounds.
## {} when the file is missing (fresh clone without the purchased packs).
static func parts(short: String) -> Dictionary:
	var path := resolve(short)
	if _parts.has(path):
		return _parts[path]
	var out := {}
	if not path.is_empty() and ResourceLoader.exists(path):
		var inst: Node = (load(path) as PackedScene).instantiate()
		var list: Array = []
		var box := AABB()
		var mis: Array = [inst] if inst is MeshInstance3D else []
		mis.append_array(inst.find_children("*", "MeshInstance3D", true, false))
		for n: Variant in mis:
			var mi := n as MeshInstance3D
			if mi == null or mi.mesh == null or not mi.visible:
				continue
			var mesh := mi.mesh
			var baked := false
			for s: int in mesh.get_surface_count():
				if mi.get_surface_override_material(s) != null or mi.material_override != null:
					baked = true
			if baked and mesh is ArrayMesh:
				mesh = mesh.duplicate() as ArrayMesh
				for s: int in mesh.get_surface_count():
					var mat := mi.material_override if mi.material_override else mi.get_surface_override_material(s)
					if mat:
						(mesh as ArrayMesh).surface_set_material(s, mat)
			var local := Transform3D.IDENTITY
			var cur: Node = mi
			while cur != null and cur != inst:
				if cur is Node3D:
					local = (cur as Node3D).transform * local
				cur = cur.get_parent()
			var b: AABB = local * mesh.get_aabb()
			box = b if list.is_empty() else box.merge(b)
			list.append([mesh, local])
		inst.free()
		if not list.is_empty():
			out = {"parts": list, "aabb": box}
	_parts[path] = out
	return out


## A movable copy of a prefab (drones, vehicles): collision bodies removed.
static func instance(short: String) -> Node3D:
	var path := resolve(short)
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	var inst := (load(path) as PackedScene).instantiate() as Node3D
	if inst == null:
		return null
	for b: Node in inst.find_children("*", "CollisionObject3D", true, false):
		b.get_parent().remove_child(b)
		b.free()
	return inst


## The colony's architecture family ("explorer", "corp", "scav"; AssetSlots.style).
static func style_key() -> String:
	return AssetSlots.style if not AssetSlots.style.is_empty() else "explorer"


## One section of this style's street look (data "styles" -> style -> section), {} when none.
static func style_cfg(section: String) -> Dictionary:
	return DictUtil.get_dict(DictUtil.get_dict(DictUtil.get_dict(doc(), "styles"), style_key()), section)


static func spec(def_id: String) -> Dictionary:
	var bs: Dictionary = DictUtil.get_dict(doc(), "buildings")
	return DictUtil.get_dict(bs, def_id) if bs.has(def_id) else DictUtil.get_dict(bs, "_default")


## How the ground under the building reads: "pad" (the plain grey slab, also the
## fresh-clone look), "skirt" (Synty platform tiles on a dark skirt) or "none".
static func pad_style(def_id: String) -> String:
	var mode := str(spec(def_id).get("platform", "pad"))
	if mode == "none":  # only once the packs are there; a fresh clone keeps its slab
		return "none" if not _tiles(false).is_empty() else "pad"
	if mode == "pad" or _tiles(mode == "landing").is_empty():
		return "pad"
	return "skirt"


static func _tiles(landing: bool) -> Array:
	var p: Dictionary = DictUtil.get_dict(doc(), "platform")
	var out: Array = []
	for s: Variant in DictUtil.get_arr(p, "landing" if landing else "tiles"):
		if not parts(str(s)).is_empty():
			out.append(str(s))
	return out


static func platform_margin() -> float:
	return DictUtil.get_float(DictUtil.get_dict(doc(), "platform"), "margin", 0.7)


## Building-local placements: [{"mesh", "xf", "r", "light", "top", "build", "kind"}].
## "kind" is "platform" for the floor tiles (inside the footprint, never culled).
## district: picks that district's platform tiles and paving tint.
static func plan(def_id: String, size: Vector2, building_id: int, district: String = "") -> Array:
	var out: Array = []
	if doc().is_empty():
		return out
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%s#%d" % [def_id, building_id])
	var sp := spec(def_id)
	var mode := str(sp.get("platform", "pad"))
	var margin := 0.0
	if pad_style(def_id) == "skirt":
		margin = platform_margin()
		_plan_platform(out, size, margin, mode == "landing", rng, district)
	var ps := DictUtil.get_float(doc(), "prop_scale", 0.72)
	for g: Variant in DictUtil.get_arr(sp, "groups"):
		var gd: Dictionary = g
		var set_items := _set_items(str(gd.get("set", "")))
		if set_items.is_empty():
			continue
		var kind := str(gd.get("kind", "cluster"))
		var build := bool(gd.get("build", false))
		match kind:
			"cluster":
				for i: int in DictUtil.get_int(gd, "n", 1):
					var cnt: Array = DictUtil.get_arr(gd, "count")
					var c := rng.randi_range(int(cnt[0]), int(cnt[1])) if cnt.size() == 2 else 2
					var at := _edge_point(rng, size, margin + 0.9)
					for k: int in c:
						var it: Dictionary = set_items[rng.randi() % set_items.size()]
						var off := (at[1] as Vector2).orthogonal() * rng.randf_range(-1.6, 1.6) + (at[1] as Vector2) * rng.randf_range(-0.2, 0.7)
						var p: Vector2 = (at[0] as Vector2) + (off if k > 0 else Vector2.ZERO)
						var yaw := snappedf(rng.randf() * TAU, PI * 0.25) + rng.randf_range(-0.2, 0.2)
						_add(out, it, p, yaw, ps, size, margin, build, kind)
			"corner":
				var corners: Array = [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]
				var start := rng.randi() % 4
				for i: int in mini(DictUtil.get_int(gd, "n", 1), 4):
					var cv: Vector2 = corners[(start + i * (2 if DictUtil.get_int(gd, "n", 1) == 2 else 1)) % 4]
					var it: Dictionary = set_items[rng.randi() % set_items.size()]
					var r := _radius(it, ps)
					var p := Vector2(cv.x * (size.x * 0.5 + margin + 0.35 + r), cv.y * (size.y * 0.5 + margin + 0.35 + r))
					_add(out, it, p, atan2(cv.x, cv.y), ps, size, margin, build, kind)
			"edge":
				for i: int in DictUtil.get_int(gd, "n", 1):
					var it: Dictionary = set_items[rng.randi() % set_items.size()]
					var at := _edge_point(rng, size, margin + 0.5 + _radius(it, ps))
					var nrm: Vector2 = at[1]
					_add(out, it, at[0], atan2(nrm.x, nrm.y), ps, size, margin, build, kind)
			"row":
				var it: Dictionary = set_items[rng.randi() % set_items.size()]
				var long_x := size.x >= size.y
				var side := 1.0 if rng.randf() < 0.5 else -1.0
				var n := DictUtil.get_int(gd, "count", 3)
				var r := _radius(it, ps)
				var span := (size.x if long_x else size.y) * 0.8
				for k: int in n:
					var t := (k + 0.5) / n - 0.5
					var p := Vector2(t * span, side * (size.y * 0.5 + margin + 0.4 + r * 0.6)) if long_x else Vector2(side * (size.x * 0.5 + margin + 0.4 + r * 0.6), t * span)
					_add(out, it, p, (0.0 if long_x else PI * 0.5), ps, size, margin, build, kind)
			"park":
				for i: int in DictUtil.get_int(gd, "n", 1):
					var it: Dictionary = set_items[rng.randi() % set_items.size()]
					var box: AABB = parts(str(it["mesh"]))["aabb"]
					var sc := ps * DictUtil.get_float(it, "scale", 1.0)
					var at := _edge_point(rng, size, margin + 0.8 + minf(box.size.x, box.size.z) * 0.5 * sc)
					var nrm: Vector2 = at[1]
					# Parked alongside the wall, nose along the edge.
					var yaw := atan2(nrm.x, nrm.y) + PI * 0.5 * (1.0 if rng.randf() < 0.5 else -1.0)
					_add(out, it, at[0], yaw, ps, size, margin, build, kind)
	return out


static func _set_items(name: String) -> Array:
	var out: Array = []
	for it: Variant in DictUtil.get_arr(DictUtil.get_dict(doc(), "sets"), name):
		if it is Dictionary and not parts(str((it as Dictionary).get("mesh", ""))).is_empty():
			out.append(it)
	return out


static func _radius(it: Dictionary, ps: float) -> float:
	var box: AABB = parts(str(it["mesh"]))["aabb"]
	return maxf(box.size.x, box.size.z) * 0.5 * ps * DictUtil.get_float(it, "scale", 1.0)


## A random point just outside the footprint edge (sides weighted by length)
## and that edge's outward normal: [Vector2 point, Vector2 normal].
static func _edge_point(rng: RandomNumberGenerator, size: Vector2, gap: float) -> Array:
	var hx := size.x * 0.5
	var hz := size.y * 0.5
	var pick := rng.randf() * (size.x + size.y)
	var t := rng.randf_range(-0.8, 0.8)
	var side := 1.0 if rng.randf() < 0.5 else -1.0
	if pick < size.x:
		return [Vector2(t * hx, side * (hz + gap)), Vector2(0, side)]
	return [Vector2(side * (hx + gap), t * hz), Vector2(side, 0)]


static func _add(out: Array, it: Dictionary, p: Vector2, yaw: float, ps: float, size: Vector2, margin: float, build: bool, kind: String) -> void:
	var pr: Dictionary = parts(str(it["mesh"]))
	var box: AABB = pr["aabb"]
	var sc := ps * DictUtil.get_float(it, "scale", 1.0)
	var r := maxf(box.size.x, box.size.z) * 0.5 * sc
	# Never inside the footprint (+ platform margin): push out along the nearest edge.
	var hx := size.x * 0.5 + margin + r * 0.8 + 0.15
	var hz := size.y * 0.5 + margin + r * 0.8 + 0.15
	if absf(p.x) < hx and absf(p.y) < hz:
		if hx - absf(p.x) < hz - absf(p.y):
			p.x = signf(p.x if p.x != 0.0 else 1.0) * hx
		else:
			p.y = signf(p.y if p.y != 0.0 else 1.0) * hz
	var basis := Basis(Vector3.UP, yaw).scaled(Vector3.ONE * sc)
	# Centre the prefab's bounds on the point and stand it on the ground.
	var centre := Vector3(box.get_center().x, box.position.y, box.get_center().z)
	var xf := Transform3D(basis, Vector3(p.x, 0, p.y)) * Transform3D(Basis.IDENTITY, -centre)
	# Where the lamp glows, in prefab space: "light_at" from the data, else the top.
	var la: Array = DictUtil.get_arr(it, "light_at")
	var lp := Vector3(float(la[0]), float(la[1]), float(la[2])) if la.size() == 3 else Vector3(box.get_center().x, box.end.y - box.size.y * 0.06, box.get_center().z)
	out.append({"mesh": str(it["mesh"]), "xf": xf, "r": r, "light": str(it.get("light", "")), "light_at": lp, "top": box.size.y * sc,
		"build": build, "kind": kind})


static func _plan_platform(out: Array, size: Vector2, margin: float, landing: bool, rng: RandomNumberGenerator, district: String = "") -> void:
	var tiles := _tiles(landing)
	var pcfg: Dictionary = DictUtil.get_dict(doc(), "platform")
	if not landing:
		var own: Array = []
		for s: Variant in DictUtil.get_arr(DictUtil.get_dict(pcfg, "district_tiles"), district):
			if not parts(str(s)).is_empty():
				own.append(str(s))
		if not own.is_empty():
			tiles = own
	var tint := ""
	var tc: Array = DictUtil.get_arr(DictUtil.get_dict(pcfg, "tint"), district)
	if tc.size() >= 3:
		tint = "%.3f,%.3f,%.3f" % [float(tc[0]), float(tc[1]), float(tc[2])]
	var tile_m := DictUtil.get_float(DictUtil.get_dict(doc(), "platform"), "tile_m", 3.6)
	var w := size.x + margin * 2.0
	var d := size.y + margin * 2.0
	var nx := maxi(1, roundi(w / tile_m))
	var nz := maxi(1, roundi(d / tile_m))
	for ix: int in nx:
		for iz: int in nz:
			var t := str(tiles[rng.randi() % tiles.size()])
			var box: AABB = parts(t)["aabb"]
			var sx := (w / nx) / maxf(box.size.x, 0.01)
			var sz := (d / nz) / maxf(box.size.z, 0.01)
			var sy := DictUtil.get_float(doc(), "prop_scale", 0.72)
			var c := Vector3(-w * 0.5 + (ix + 0.5) * w / nx, 0.04, -d * 0.5 + (iz + 0.5) * d / nz)
			var flip := PI if rng.randf() < 0.5 else 0.0
			var xf := Transform3D(Basis(Vector3.UP, flip).scaled(Vector3(sx, sy, sz)), c) * Transform3D(Basis.IDENTITY, -Vector3(box.get_center().x, box.end.y, box.get_center().z))
			out.append({"mesh": t, "xf": xf, "r": 0.0, "light": "", "top": 0.0, "build": true, "kind": "platform", "tint": tint})

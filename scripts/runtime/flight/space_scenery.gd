class_name SpaceScenery
extends Node3D
## Approach-flight look after the POLYGON Sci-Fi Space key art (D-038): Synty
## asteroid models for the hazard rocks (look only: flight_scene.gd keeps every
## position, radius and collision), plus non-colliding layers that make the
## corridor read as a place: distant asteroid fields (MultiMesh), drifting wreck
## debris, ships and a station passing, a ringed gas giant far away.
## Data: data/art/space_scenery.json. Missing pack files are skipped; with no
## asteroid models at all, has_rocks() is false and the flight keeps its slot.

const PATH := "res://data/art/space_scenery.json"
## Rock tints per destination biome: the same models read as rusty, icy or dusty fields.
const TINTS := {
	"desert": ["#4a3a33", "#57463c", "#3a2e2a"],
	"ice": ["#454a52", "#52575e", "#3a3f48"],
	"green": ["#46403a", "#524a42", "#38332f"],
}

static var _cache: Dictionary = {}  # path -> {parts: [[Mesh, Transform3D]], aabb: AABB}

var doc: Dictionary = {}
var rock_mats: Array[Material] = []
var atlas: Material
var _rock_paths: Array = []
var _debris_paths: Array = []
var _large_paths: Array = []
var _movers: Array = []  # [{node, vel, spin: Vector3, loop: float, origin: Vector3}]
var _reduced := false


func setup(biome: String, seed_value: int) -> SpaceScenery:
	name = "SpaceScenery"
	var d: Variant = DictUtil.load_json(PATH)
	doc = d if d is Dictionary else {}
	var mp := str(doc.get("material", ""))
	atlas = load(mp) if not mp.is_empty() and ResourceLoader.exists(mp) else null
	for hex: String in TINTS.get(biome, TINTS["green"]):
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(hex)
		m.roughness = 1.0
		m.metallic = 0.0
		m.metallic_specular = 0.15
		# Plain colour: the rock UVs land on busy atlas cells, the pack's key art reads as flat stone.
		rock_mats.append(m)
	_rock_paths = _usable(DictUtil.get_arr(doc, "hazard_asteroids"))
	_debris_paths = _usable(DictUtil.get_arr(doc, "debris_hazard"))
	_large_paths = _usable(DictUtil.get_arr(doc, "large_asteroids"))
	_reduced = FxEffect.reduced_motion()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + 4049
	_field_layers(rng)
	_drift_debris(rng)
	_ships()
	_gas_giant(biome)
	return self


func has_rocks() -> bool:
	return not _rock_paths.is_empty()


## One hazard asteroid normalised to radius 1 (the caller scales it by the
## gameplay radius). kind "debris" mixes in hull shells for debris fields.
func hazard_visual(rng: RandomNumberGenerator, kind: String, r: float) -> Node3D:
	var pool := _rock_paths
	if kind == "debris" and not _debris_paths.is_empty() and r < 3.0 and rng.randf() < 0.6:
		pool = _debris_paths
	elif r > 9.0 and not _large_paths.is_empty() and rng.randf() < 0.4:
		pool = _large_paths
	var path: String = pool[rng.randi() % pool.size()]
	var is_rock := pool != _debris_paths
	return _instance(path, rock_mats[rng.randi() % rock_mats.size()] if is_rock else atlas, 1.0)


func _process(delta: float) -> void:
	for m: Dictionary in _movers:
		var n: Node3D = m["node"]
		n.position += (m["vel"] as Vector3) * delta
		var loop := float(m["loop"])
		if loop > 0.0 and n.position.distance_to(m["origin"]) > loop:
			n.position = m["origin"]
		if not _reduced:
			var s: Vector3 = m["spin"]
			n.rotate_object_local(Vector3.UP, s.y * delta)
			if s.x != 0.0:
				n.rotate_object_local(Vector3.RIGHT, s.x * delta)


# --- layers ---------------------------------------------------------------

## Far asteroid fields beside, above and below the corridor: one MultiMesh per
## model and tint, no collision, culled by distance.
func _field_layers(rng: RandomNumberGenerator) -> void:
	if _rock_paths.is_empty():
		return
	var buckets: Dictionary = {}  # "path|mat" -> [Transform3D]
	for layer: Variant in DictUtil.get_arr(doc, "field_layers"):
		var l: Dictionary = layer
		var xr: Array = DictUtil.get_arr(l, "x")
		var yr: Array = DictUtil.get_arr(l, "y")
		var zr: Array = DictUtil.get_arr(l, "z")
		var sr: Array = DictUtil.get_arr(l, "size")
		var mirror := bool(l.get("mirror", true))
		var large_share := float(l.get("large_share", 0.0))
		for i: int in int(l.get("count", 0)):
			var x := rng.randf_range(float(xr[0]), float(xr[1]))
			if mirror:
				x *= -1.0 if rng.randf() < 0.5 else 1.0
			var pos := Vector3(x, rng.randf_range(float(yr[0]), float(yr[1])), rng.randf_range(float(zr[0]), float(zr[1])))
			var big := not _large_paths.is_empty() and rng.randf() < large_share
			var path: String = (_large_paths if big else _rock_paths)[rng.randi() % (_large_paths if big else _rock_paths).size()]
			var size := rng.randf_range(float(sr[0]), float(sr[1])) * (2.2 if big else 1.0)
			var key := "%s|%d" % [path, rng.randi() % rock_mats.size()]
			var b := Basis.from_euler(Vector3(rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU)).scaled(Vector3(1.0, rng.randf_range(0.7, 1.0), rng.randf_range(0.8, 1.2)) * size)
			if not buckets.has(key):
				buckets[key] = []
			(buckets[key] as Array).append(Transform3D(b, pos))
	for key: String in buckets.keys():
		var parts := key.split("|")
		var src := _source(parts[0])
		var xfs: Array = buckets[key]
		var norm := _norm_xf(src)
		for part: Array in src["parts"]:
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = part[0]
			mm.instance_count = xfs.size()
			for i: int in xfs.size():
				mm.set_instance_transform(i, (xfs[i] as Transform3D) * norm * (part[1] as Transform3D))
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			mmi.material_override = rock_mats[int(parts[1])]
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mmi.visibility_range_end = 3200.0
			add_child(mmi)


## Wreck shells and girders tumbling slowly just outside the corridor.
func _drift_debris(rng: RandomNumberGenerator) -> void:
	var paths := _usable(DictUtil.get_arr(doc, "drift_debris"))
	if paths.is_empty():
		return
	for i: int in int(doc.get("drift_debris_count", 40)):
		var path: String = paths[rng.randi() % paths.size()]
		var n := _instance(path, atlas, rng.randf_range(3.0, 10.0), true)
		var side := -1.0 if rng.randf() < 0.5 else 1.0
		if rng.randf() < 0.7:
			n.position = Vector3(side * rng.randf_range(110.0, 240.0), rng.randf_range(-70.0, 70.0), -rng.randf_range(60.0, 1300.0))
		else:
			n.position = Vector3(rng.randf_range(-160.0, 160.0), side * rng.randf_range(62.0, 120.0), -rng.randf_range(60.0, 1300.0))
		n.rotation = Vector3(rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU)
		add_child(n)
		_movers.append({"node": n, "vel": Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.6, 0.6), rng.randf_range(-1, 1)) * 2.0,
			"spin": Vector3(rng.randf_range(-0.3, 0.3), rng.randf_range(-0.4, 0.4), 0), "loop": 0.0, "origin": n.position})


func _ships() -> void:
	for s: Variant in DictUtil.get_arr(doc, "ships"):
		var d: Dictionary = s
		var path := str(d.get("mesh", ""))
		if _source(path).is_empty():
			continue
		var n := _instance(path, atlas, float(d.get("size", 50.0)), true)
		var p: Array = DictUtil.get_arr(d, "pos")
		n.position = Vector3(float(p[0]), float(p[1]), float(p[2]))
		n.rotation_degrees.y = float(d.get("yaw", 0.0))
		var tl: Array = DictUtil.get_arr(d, "tilt")
		if tl.size() == 3:
			n.rotation_degrees = Vector3(float(tl[0]), float(tl[1]), float(tl[2]))
		add_child(n)
		var v: Array = DictUtil.get_arr(d, "vel")
		var vel := Vector3(float(v[0]), float(v[1]), float(v[2])) if v.size() == 3 else Vector3.ZERO
		if vel != Vector3.ZERO and float(d.get("spin", 0.0)) == 0.0:
			n.basis = Basis.looking_at(vel, Vector3.UP)
			n.rotate_object_local(Vector3.UP, deg_to_rad(float(d.get("yaw_offset", 180.0))))
			_engine_glow(n, float(d.get("size", 50.0)))
		_movers.append({"node": n, "vel": vel, "spin": Vector3(0, float(d.get("spin", 0.0)), 0), "loop": float(d.get("loop", 0.0)), "origin": n.position})


## A soft blue exhaust behind a moving ship (billboard quad, additive).
func _engine_glow(ship: Node3D, size: float) -> void:
	var q := QuadMesh.new()
	q.size = Vector2.ONE * size * 0.35
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.albedo_color = Color(0.45, 0.75, 1.0, 0.9)
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(0.5, 0.0)
	m.albedo_texture = gt
	q.material = m
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Ship models face -Z after look_at + 180 deg turn: the engines sit on local -Z... measured per model by the AABB.
	var box := AssetSlots.aabb_of(ship, Transform3D.IDENTITY)
	mi.position = Vector3(0, 0, box.position.z + box.size.z * 0.02)
	ship.add_child(mi)


## A ringed gas giant far off to the side: banded planet shader + ring quad
## (art/shaders/planet_ring.gdshader). Its palette contrasts the destination biome.
func _gas_giant(biome: String) -> void:
	var g: Dictionary = DictUtil.get_dict(doc, "gas_giant")
	if g.is_empty():
		return
	var pal: Dictionary = DictUtil.get_dict(DictUtil.get_dict(g, "palettes"), biome)
	var root := Node3D.new()
	root.name = "GasGiant"
	var p: Array = DictUtil.get_arr(g, "pos")
	root.position = Vector3(float(p[0]), float(p[1]), float(p[2]))
	var t: Array = DictUtil.get_arr(g, "tilt")
	if t.size() == 3:
		root.rotation_degrees = Vector3(float(t[0]), float(t[1]), float(t[2]))
	var radius := float(g.get("radius", 400.0))
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	sphere.radial_segments = 96
	sphere.rings = 48
	var m := ShaderMaterial.new()
	m.shader = PlanetLook.SHADER
	m.set_shader_parameter("base_color", Color(str(pal.get("base", "#c98a5a"))))
	m.set_shader_parameter("ocean_color", Color(str(pal.get("ocean", "#6a3b2a"))))
	m.set_shader_parameter("high_color", Color(str(pal.get("high", "#f2dcc0"))))
	m.set_shader_parameter("atmo_color", Color(str(pal.get("atmo", "#ffb27a"))))
	m.set_shader_parameter("sea_level", 0.46)
	m.set_shader_parameter("cloud_amount", 0.0)
	m.set_shader_parameter("banding", 1.0)
	m.set_shader_parameter("seed", 31.0)
	m.set_shader_parameter("cloud_speed", 0.0)
	var mi := MeshInstance3D.new()
	mi.mesh = sphere
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	var rq := PlaneMesh.new()
	rq.size = Vector2.ONE * radius * float(g.get("ring_scale", 4.6))
	var rm := ShaderMaterial.new()
	rm.shader = preload("res://art/shaders/planet_ring.gdshader")
	rm.set_shader_parameter("ring_color", Color(str(pal.get("ring", "#e8d2b4"))))
	rm.set_shader_parameter("band_color", Color(str(pal.get("ring_band", "#8a7262"))))
	rm.set_shader_parameter("inner", 0.5)
	var ring := MeshInstance3D.new()
	ring.mesh = rq
	ring.material_override = rm
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(ring)
	add_child(root)


# --- mesh helpers -----------------------------------------------------------

func _usable(paths: Array) -> Array:
	return paths.filter(func(p: Variant) -> bool: return not _source(str(p)).is_empty())


## A node with the model's meshes under one parent, scaled so its mean radius
## (or, with by_size, its largest extent) equals size.
func _instance(path: String, mat: Material, size: float, by_size: bool = false) -> Node3D:
	var src := _source(path)
	var root := Node3D.new()
	var box: AABB = src["aabb"]
	var holder := Node3D.new()
	var s := size / maxf(0.01, box.get_longest_axis_size() if by_size else (box.size.x + box.size.y + box.size.z) / 6.0)
	holder.transform = Transform3D(Basis().scaled(Vector3.ONE * s), -box.get_center() * s)
	root.add_child(holder)
	for part: Array in src["parts"]:
		var mi := MeshInstance3D.new()
		mi.mesh = part[0]
		mi.transform = part[1]
		if mat:
			mi.material_override = mat
		holder.add_child(mi)
	return root


## Transform that centres a model and scales its mean radius to 1 (MultiMesh use).
func _norm_xf(src: Dictionary) -> Transform3D:
	var box: AABB = src["aabb"]
	var s := 1.0 / maxf(0.01, (box.size.x + box.size.y + box.size.z) / 6.0)
	return Transform3D(Basis().scaled(Vector3.ONE * s), -box.get_center() * s)


static func _source(path: String) -> Dictionary:
	if _cache.has(path):
		return _cache[path]
	var out: Dictionary = {}
	if not path.is_empty() and ResourceLoader.exists(path):
		var ps := load(path) as PackedScene
		if ps:
			var inst := ps.instantiate()
			var parts: Array = []
			var box := AABB()
			var mis: Array = [inst] if inst is MeshInstance3D else []
			mis.append_array(inst.find_children("*", "MeshInstance3D", true, false))
			for n: Variant in mis:
				var mi := n as MeshInstance3D
				if mi == null or mi.mesh == null:
					continue
				var local := Transform3D.IDENTITY
				var cur: Node = mi
				while cur != null and cur != inst:
					if cur is Node3D:
						local = (cur as Node3D).transform * local
					cur = cur.get_parent()
				var b := local * mi.mesh.get_aabb()
				box = b if parts.is_empty() else box.merge(b)
				parts.append([mi.mesh, local])
			inst.free()
			if not parts.is_empty():
				out = {"parts": parts, "aabb": box}
	_cache[path] = out
	return out

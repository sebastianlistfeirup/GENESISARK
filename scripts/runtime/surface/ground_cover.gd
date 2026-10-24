class_name GroundCover
extends RefCounted
## Planet identity dressing (data/art/ground_cover.json, D-039): per planet (or
## biome fallback) trees with trunk collision, dense clustered ground cover drawn
## as one MultiMesh per piece (no collision), shore and on-water pieces for wet
## worlds, landmarks in an outer ring and an optional cliff ring. Nature Biomes
## FBX go through NatureKit with the planet's look (tints, glow, wind). Pieces
## whose purchased source is missing are skipped (fresh clone = bare terrain).
## Gameplay space is respected: nothing lands inside `avoid` circles.

const PATH := "res://data/art/ground_cover.json"

static var _meshes: Dictionary = {}  # prefab path -> [ArrayMesh, Transform3D local, AABB]


static func spec_for(key: String, fallback: String) -> Dictionary:
	var doc: Variant = DictUtil.load_json(PATH)
	if not doc is Dictionary:
		return {}
	var d: Dictionary = doc
	return DictUtil.get_dict(d, key) if d.has(key) else DictUtil.get_dict(d, fallback)


static func build(terrain: Node3D, key: String, seed_value: int, avoid: Array, size_m: float, fallback: String = "") -> Node3D:
	var root := Node3D.new()
	root.name = "GroundCover"
	var spec := spec_for(key, fallback if not fallback.is_empty() else str(terrain.get("biome_id")))
	if spec.is_empty():
		return root
	var look: Dictionary = DictUtil.get_dict(spec, "look")
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var q := Quality.value("scatter_scale", 1.0)
	var half := size_m * 0.47
	var water: float = float(terrain.get("water_level"))
	var wet := water > -50.0
	var body := StaticBody3D.new()
	body.name = "TreeTrunks"
	body.collision_layer = 1
	root.add_child(body)
	# Trees: individual instances (they cast big shadows and need trunks to collide).
	for item: Variant in DictUtil.get_arr(spec, "trees"):
		var it: Dictionary = item
		var srcs: Array = []
		for m: Variant in DictUtil.get_arr(it, "meshes"):
			var src := mesh_of(str(m), look)
			if not src.is_empty():
				srcs.append(src)
		if srcs.is_empty():
			continue
		var batches: Dictionary = {}
		var count := int(float(it.get("count", 40)) * q)
		var sc: Array = DictUtil.get_arr(it, "scale")
		var tries := 0
		var placed := 0
		while placed < count and tries < count * 8:
			tries += 1
			var p := Vector2(rng.randf_range(-half, half), rng.randf_range(-half, half))
			if _blocked(p, avoid, 2.0):
				continue
			var y: float = terrain.call("height_at", p.x, p.y)
			if wet and y < water + 0.4:
				continue
			var k := rng.randi() % srcs.size()
			var s := rng.randf_range(float(sc[0]), float(sc[1])) if sc.size() == 2 else 1.0
			var xf := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s), Vector3(p.x, y - 0.15, p.y)) * (srcs[k][1] as Transform3D)
			if not batches.has(k):
				batches[k] = []
			(batches[k] as Array).append(xf)
			var r := float(it.get("radius", 0.5)) * s
			var cs := CollisionShape3D.new()
			var cyl := CylinderShape3D.new()
			cyl.radius = r
			cyl.height = 4.0 * s
			cs.shape = cyl
			cs.position = Vector3(p.x, y + cyl.height * 0.5, p.y)
			body.add_child(cs)
			placed += 1
		for k: int in batches.keys():
			root.add_child(_multimesh(srcs[k][0], batches[k], true, 180.0))
	# Ground cover: clustered patches, MultiMesh per piece.
	for item: Variant in DictUtil.get_arr(spec, "cover"):
		var it: Dictionary = item
		var src := mesh_of(str(it.get("mesh", "")), look)
		if src.is_empty():
			continue
		var shore := bool(it.get("shore", false))
		var on_water := bool(it.get("on_water", false))
		if (shore or on_water) and not wet:
			continue
		var count := int(float(it.get("count", 100)) * q)
		var cluster := maxi(1, int(it.get("cluster", 4)))
		var sc: Array = DictUtil.get_arr(it, "scale")
		var smin := float(sc[0]) if sc.size() == 2 else 1.0
		var smax := float(sc[1]) if sc.size() == 2 else 1.0
		var xfs: Array = []
		var tries := 0
		while xfs.size() < count and tries < count * 8:
			tries += 1
			var centre := Vector2(rng.randf_range(-half, half), rng.randf_range(-half, half))
			for k: int in cluster:
				var p := centre + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.0, 2.5 + cluster * 0.6)
				if absf(p.x) > half or absf(p.y) > half or _blocked(p, avoid):
					continue
				var y: float = terrain.call("height_at", p.x, p.y)
				if wet:
					if on_water and (y > water - 0.15 or y < water - 3.0):
						continue
					if shore and absf(y - water) > 0.9:
						continue
					if not on_water and not shore and y < water + 0.3:
						continue
					if on_water:
						y = water + 0.02
				var s := rng.randf_range(smin, smax)
				var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s)
				xfs.append(Transform3D(b, Vector3(p.x, y - (0.0 if on_water else 0.05), p.y)) * (src[1] as Transform3D))
				if xfs.size() >= count:
					break
		if xfs.is_empty():
			continue
		var mmi := _multimesh(src[0], xfs, smax >= 0.5 and not str(it.get("mesh", "")).containsn("grass"), 120.0)
		if it.has("emissive"):
			var em := StandardMaterial3D.new()
			var ec := Color(str(it["emissive"]))
			em.albedo_color = ec.lightened(0.3)
			em.emission_enabled = true
			em.emission = ec
			em.emission_energy_multiplier = 2.5
			mmi.material_override = em
		root.add_child(mmi)
	# Landmarks: big silhouettes in an outer ring (no collision: beyond the playable edge).
	for item: Variant in DictUtil.get_arr(spec, "landmarks"):
		var it: Dictionary = item
		var srcs: Array = []
		for m: Variant in DictUtil.get_arr(it, "meshes"):
			var src := mesh_of(str(m), look)
			if not src.is_empty():
				srcs.append(src)
		if srcs.is_empty():
			continue
		var ring: Array = DictUtil.get_arr(it, "ring")
		var sc: Array = DictUtil.get_arr(it, "scale")
		var n := int(it.get("count", 10))
		for i: int in n:
			var a := TAU * (i + rng.randf_range(0.0, 0.7)) / n
			var r := rng.randf_range(float(ring[0]), float(ring[1])) if ring.size() == 2 else 80.0
			r *= size_m / 180.0  # rings are authored for the 180 m expedition map
			var p := Vector2(cos(a), sin(a)) * r
			var src: Array = srcs[rng.randi() % srcs.size()]
			var s := rng.randf_range(float(sc[0]), float(sc[1])) if sc.size() == 2 else 1.0
			var reach := maxf((src[2] as AABB).size.x, (src[2] as AABB).size.z) * s * 0.5
			if _blocked(p, avoid, reach + 6.0):
				continue  # never over a site, route or colony district
			var mi := MeshInstance3D.new()
			mi.mesh = src[0]
			# Anchor by the mesh's own base, on the LOWEST ground under its footprint, sunk a
			# little, so big pieces never hover whatever their pivot (Synty cliffs pivot mid-air).
			var box: AABB = src[2]
			var half_w := maxf(box.size.x, box.size.z) * s * 0.4
			var lo := INF
			for k: int in 9:
				var qq := p + (Vector2.from_angle(TAU * k / 8.0) * half_w if k < 8 else Vector2.ZERO)
				lo = minf(lo, float(terrain.call("height_at", clampf(qq.x, -size_m * 0.49, size_m * 0.49), clampf(qq.y, -size_m * 0.49, size_m * 0.49))))
			var y := lo - box.position.y * s - box.size.y * s * 0.06
			mi.transform = Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s), Vector3(p.x, y, p.y)) * (src[1] as Transform3D)
			mi.visibility_range_end = 600.0
			root.add_child(mi)
	_cliffs(root, terrain, DictUtil.get_arr(spec, "cliffs"), rng, size_m)
	return root


static func _multimesh(mesh: Mesh, xfs: Array, shadows: bool, vis_end: float) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xfs.size()
	for i: int in xfs.size():
		mm.set_instance_transform(i, xfs[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.visibility_range_end = vis_end
	return mmi


static func _blocked(p: Vector2, avoid: Array, extra: float = 0.0) -> bool:
	for a: Variant in avoid:
		var arr: Array = a
		if p.distance_to(arr[0]) < float(arr[1]) + extra:
			return true
	return false


## A broken wall of cliffs just inside the map edge, facing inwards.
static func _cliffs(root: Node3D, terrain: Node3D, paths: Array, rng: RandomNumberGenerator, size_m: float) -> void:
	var usable: Array = []
	for p: Variant in paths:
		if not mesh_of(str(p)).is_empty():
			usable.append(str(p))
	if usable.is_empty():
		return
	var r := size_m * 0.5 - 4.0
	var steps := int(TAU * r / 22.0)
	for i: int in steps:
		var a := TAU * i / steps + rng.randf_range(-0.04, 0.04)
		var pos := Vector2(cos(a), sin(a)) * (r + rng.randf_range(-3.0, 3.0))
		var src := mesh_of(usable[rng.randi() % usable.size()])
		var box: AABB = src[2]
		var s := rng.randf_range(22.0, 34.0) / maxf(box.size.y, 0.1)
		var mi := MeshInstance3D.new()
		mi.mesh = src[0]
		var y: float = terrain.call("height_at", clampf(pos.x, -size_m * 0.49, size_m * 0.49), clampf(pos.y, -size_m * 0.49, size_m * 0.49)) - 2.0
		mi.transform = Transform3D(Basis(Vector3.UP, -a + PI * 0.5 + rng.randf_range(-0.3, 0.3)).scaled(Vector3.ONE * s), Vector3(pos.x, y, pos.y)) * (src[1] as Transform3D)
		mi.visibility_range_end = 400.0
		root.add_child(mi)


## Mesh for a piece: Nature Biomes FBX via NatureKit (planet look), Godot prefabs directly.
static func mesh_of(path: String, look: Dictionary = {}) -> Array:
	if path.contains("/Synty/Nature/"):
		return NatureKit.mesh(path, look)
	return _mesh_of(path)


## First drawn mesh of a prefab, with its material overrides baked into a copy.
static func _mesh_of(path: String) -> Array:
	if _meshes.has(path):
		return _meshes[path]
	var out: Array = []
	if not path.is_empty() and ResourceLoader.exists(path) and load(path) is PackedScene:
		var inst: Node = (load(path) as PackedScene).instantiate()
		var mis: Array = [inst] if inst is MeshInstance3D else []
		mis.append_array(inst.find_children("*", "MeshInstance3D", true, false))
		for n: Variant in mis:
			var mi := n as MeshInstance3D
			if mi == null or mi.mesh == null or not mi.visible:
				continue
			var mesh := mi.mesh.duplicate() as Mesh
			if mesh is ArrayMesh:
				for s: int in mesh.get_surface_count():
					var mat := mi.get_surface_override_material(s)
					if mat:
						(mesh as ArrayMesh).surface_set_material(s, mat)
			var local := Transform3D.IDENTITY
			var cur: Node = mi
			while cur != null and cur != inst:
				if cur is Node3D:
					local = (cur as Node3D).transform * local
				cur = cur.get_parent()
			out = [mesh, local, local * mesh.get_aabb()]
			break
		inst.free()
	_meshes[path] = out
	return out

class_name GroundCover
extends RefCounted
## Dense, cheap ground dressing for a biome map (data/art/ground_cover.json):
## grass tufts, small plants and pebbles in clusters drawn as one MultiMesh per
## piece (no collision, no gameplay), plus a ring of cliffs that frames the map
## the way the Synty demo scenes do. Pieces whose source files are missing (a
## fresh clone without the purchased packs) are skipped. Presentation only.

const PATH := "res://data/art/ground_cover.json"

static var _meshes: Dictionary = {}  # prefab path -> [ArrayMesh, Transform3D local, AABB]


static func build(terrain: Node3D, biome: String, seed_value: int, avoid: Array, size_m: float) -> Node3D:
	var root := Node3D.new()
	root.name = "GroundCover"
	var doc: Variant = DictUtil.load_json(PATH)
	if not doc is Dictionary:
		return root
	var spec: Dictionary = DictUtil.get_dict(doc, biome)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var q := Quality.value("scatter_scale", 1.0)
	var half := size_m * 0.47
	for item: Variant in DictUtil.get_arr(spec, "cover"):
		var it: Dictionary = item
		var src := _mesh_of(str(it.get("mesh", "")))
		if src.is_empty():
			continue
		var count := int(float(it.get("count", 100)) * q)
		var cluster := maxi(1, int(it.get("cluster", 4)))
		var sc: Array = DictUtil.get_arr(it, "scale")
		var smin := float(sc[0]) if sc.size() == 2 else 1.0
		var smax := float(sc[1]) if sc.size() == 2 else 1.0
		var xfs: Array[Transform3D] = []
		var tries := 0
		while xfs.size() < count and tries < count * 6:
			tries += 1
			# Growth in patches: a centre, then a few pieces around it.
			var centre := Vector2(rng.randf_range(-half, half), rng.randf_range(-half, half))
			for k: int in cluster:
				var p := centre + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.0, 2.5 + cluster * 0.6)
				if absf(p.x) > half or absf(p.y) > half or _blocked(p, avoid):
					continue
				var s := rng.randf_range(smin, smax)
				var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s)
				var y: float = terrain.call("height_at", p.x, p.y) - 0.05
				xfs.append(Transform3D(b, Vector3(p.x, y, p.y)) * (src[1] as Transform3D))
				if xfs.size() >= count:
					break
		if xfs.is_empty():
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = src[0]
		mm.instance_count = xfs.size()
		for i: int in xfs.size():
			mm.set_instance_transform(i, xfs[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if smax < 0.5 or str(it.get("mesh", "")).contains("Grass") else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		mmi.visibility_range_end = 120.0
		root.add_child(mmi)
	_cliffs(root, terrain, DictUtil.get_arr(spec, "cliffs"), rng, size_m)
	return root


static func _blocked(p: Vector2, avoid: Array) -> bool:
	for a: Variant in avoid:
		var arr: Array = a
		if p.distance_to(arr[0]) < float(arr[1]):
			return true
	return false


## A broken wall of cliffs just inside the map edge, facing inwards.
static func _cliffs(root: Node3D, terrain: Node3D, paths: Array, rng: RandomNumberGenerator, size_m: float) -> void:
	var usable: Array = []
	for p: Variant in paths:
		if not _mesh_of(str(p)).is_empty():
			usable.append(str(p))
	if usable.is_empty():
		return
	var r := size_m * 0.5 - 4.0
	var steps := int(TAU * r / 22.0)
	for i: int in steps:
		var a := TAU * i / steps + rng.randf_range(-0.04, 0.04)
		var pos := Vector2(cos(a), sin(a)) * (r + rng.randf_range(-3.0, 3.0))
		var src := _mesh_of(usable[rng.randi() % usable.size()])
		var box: AABB = src[2]
		var s := rng.randf_range(22.0, 34.0) / maxf(box.size.y, 0.1)
		var mi := MeshInstance3D.new()
		mi.mesh = src[0]
		var y: float = terrain.call("height_at", clampf(pos.x, -size_m * 0.49, size_m * 0.49), clampf(pos.y, -size_m * 0.49, size_m * 0.49)) - 2.0
		mi.transform = Transform3D(Basis(Vector3.UP, -a + PI * 0.5 + rng.randf_range(-0.3, 0.3)).scaled(Vector3.ONE * s), Vector3(pos.x, y, pos.y)) * (src[1] as Transform3D)
		mi.visibility_range_end = 400.0
		root.add_child(mi)


## First drawn mesh of a prefab, with its material overrides baked into a copy.
static func _mesh_of(path: String) -> Array:
	if _meshes.has(path):
		return _meshes[path]
	var out: Array = []
	if not path.is_empty() and ResourceLoader.exists(path):
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

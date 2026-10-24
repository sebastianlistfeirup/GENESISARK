class_name MeshLod
extends RefCounted
## Render-cost rules applied automatically to purchased geometry (D-054), so the
## game runs on a mid-range GPU without hand-editing a single prefab:
##  * LODs for meshes that ship without them. The Synty Godot packs' extracted
##    meshes (building kits, props, alien plants) have no LOD levels, so a 21k
##    triangle research pod drew all of them at 150 m, four times over for the
##    shadow cascades. `lodded()` returns a copy with automatic LODs (what the
##    importer does for imported meshes; meshoptimizer, screen-space error, so
##    the switch is invisible at the engine's 1 px threshold). Copies are
##    cached in memory and, for meshes loaded from a file, on disk under
##    user://mesh_lods (derived local data, never in the repository).
##  * Spatial chunks for big MultiMeshes. The engine picks a MultiMesh's LOD,
##    frustum culling, shadow culling and visibility range from its whole AABB,
##    so one MultiMesh spread over the colony always drew every instance at
##    full detail. `split_multimeshes()` cuts heavy ones into grid cells.
##  * Small pieces (pebbles, cans, crates) are handed to ShadowLod: they cast
##    shadows only while the camera is near enough to see them.
##  * Shadow twins for heavy pieces. The importer's LOD error is dominated by
##    normal/UV changes, and on the packs' colour atlases the reduced levels do
##    recolour faces, so the visible mesh keeps the engine's strict 1 px rule.
##    A shadow only shows the silhouette: a shadow-only twin of the same mesh
##    picks its LOD by measured geometric error (`shadow_lod_bias`), while the
##    visible mesh stops casting. Same shadow within a couple of pixels, a
##    fraction of the triangles in every cascade.
## Presentation only; the shared pack resources are never modified.

const CACHE_DIR := "user://mesh_lods"
const CACHE_VERSION := 5
## Meshes below this many triangles gain nothing from LODs.
const MIN_TRIS := 200
const NORMAL_MERGE_ANGLE := 60.0
## A MultiMesh is cut into cells only when it draws at least this many triangles at LOD0.
const SPLIT_MIN_TRIS := 24000
## Shadow twins only for pieces with at least this many triangles at LOD0.
const TWIN_MIN_TRIS := 400
## Silhouette error allowed in shadows, in multiples of the viewport LOD threshold.
const SHADOW_ERROR_PX := 3.0
const _DIRS: Array[Vector3] = [Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN, Vector3.FORWARD, Vector3.BACK,
	Vector3(0.577, 0.577, 0.577), Vector3(-0.577, 0.577, 0.577), Vector3(0.577, -0.577, 0.577), Vector3(0.577, 0.577, -0.577),
	Vector3(-0.577, -0.577, 0.577), Vector3(-0.577, 0.577, -0.577), Vector3(0.577, -0.577, -0.577), Vector3(-0.577, -0.577, -0.577)]

## Small-piece shadow rule for VisualSlot assets (apply_tree): switched on by the
## colony and surface scenes only, so interiors such as the ship keep theirs.
static var small_shadow_rules := false
static var _done: Dictionary = {}  # source Mesh -> Mesh with LODs (or the source itself)
static var stats := {"generated": 0, "from_disk": 0, "skipped": 0, "ms": 0.0, "split": 0, "chunks": 0, "twins": 0}


## The mesh with automatic LODs if it has none and is worth it; else the mesh itself.
static func lodded(mesh: Mesh) -> Mesh:
	if mesh == null or not (mesh is ArrayMesh):
		return mesh
	if _done.has(mesh):
		return _done[mesh]
	var out: Mesh = mesh
	if needs_lods(mesh):
		var t0 := Time.get_ticks_usec()
		out = _from_disk(mesh)
		if out == null:
			out = _generate(mesh as ArrayMesh)
		stats["ms"] = float(stats["ms"]) + (Time.get_ticks_usec() - t0) / 1000.0
	else:
		stats["skipped"] = int(stats["skipped"]) + 1
	_done[mesh] = out
	_done[out] = out
	return out


static func needs_lods(mesh: Mesh) -> bool:
	if mesh.get_surface_count() == 0 or lod_count(mesh) > 0:
		return false
	var tris := 0
	for s: int in mesh.get_surface_count():
		if mesh.surface_get_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES:
			return false
		var fmt := (mesh as ArrayMesh).surface_get_format(s)
		if fmt & Mesh.ARRAY_FORMAT_BONES or (mesh as ArrayMesh).get_blend_shape_count() > 0:
			return false  # skinned / morphing (characters): left alone
		tris += _surface_tris(mesh as ArrayMesh, s)
	return tris >= MIN_TRIS


static func lod_count(mesh: Mesh) -> int:
	if mesh == null or mesh.get_surface_count() == 0:
		return 0
	var d: Dictionary = RenderingServer.mesh_get_surface(mesh.get_rid(), 0)
	return (d.get("lods", []) as Array).size()


static func tris_of(mesh: Mesh) -> int:
	var t := 0
	if mesh is ArrayMesh:
		for s: int in mesh.get_surface_count():
			t += _surface_tris(mesh as ArrayMesh, s)
	return t


static func _surface_tris(mesh: ArrayMesh, s: int) -> int:
	var n := mesh.surface_get_array_index_len(s)
	return (n if n > 0 else mesh.surface_get_array_len(s)) / 3


## Swap every non-skinned MeshInstance3D under `root` to its LOD copy. Surface
## override materials keep working (same surfaces in the same order).
static func apply_tree(root: Node) -> void:
	var list: Array = root.find_children("*", "MeshInstance3D", true, false)
	if root is MeshInstance3D:
		list.append(root)
	for n: Node in list:
		var mi := n as MeshInstance3D
		if mi.mesh == null or mi.skin != null:
			continue  # skinned meshes are refused by needs_lods() too
		mi.mesh = lodded(mi.mesh)
		var mb := mi.mesh.get_aabb()
		if small_shadow_rules and maxf(mb.size.x, maxf(mb.size.y, mb.size.z)) < ShadowLod.MAX_SIZE * 3.0:
			ShadowLod.register(mi)  # small pieces: shadow only while the camera is near


## Shadow-only twins for the heavy pieces under `root` (see the header): the
## piece stops casting, a child twin with the same mesh and materials casts with
## a geometric LOD bias. Freed, moved and hidden together with its piece.
static func add_shadow_twins(root: Node) -> void:
	var list: Array = root.find_children("*", "MeshInstance3D", true, false)
	for n: Node in list:
		var mi := n as MeshInstance3D
		if mi.has_meta("has_shadow_twin") or mi.has_meta("is_shadow_twin") or mi.skin != null:
			continue
		var bias := _twin_bias(mi.mesh, mi.cast_shadow)
		if bias <= 0.0:
			continue
		var tw := MeshInstance3D.new()
		tw.name = "ShadowTwin"
		tw.mesh = mi.mesh
		tw.set_meta("is_shadow_twin", true)
		tw.material_override = mi.material_override
		for s: int in mi.get_surface_override_material_count():
			tw.set_surface_override_material(s, mi.get_surface_override_material(s))
		tw.layers = mi.layers
		tw.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		tw.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		tw.lod_bias = bias
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.set_meta("has_shadow_twin", true)
		mi.add_child(tw)
		ShadowLod.register(tw)  # small heavy pieces: the twin also stops casting from afar
		stats["twins"] = int(stats["twins"]) + 1


## lod_bias for a shadow twin of `mesh`, 0 = no twin (light, casts no shadow, or no gain).
static func _twin_bias(mesh: Mesh, cast: int) -> float:
	if mesh == null or cast == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF or cast == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY:
		return 0.0
	if not mesh.has_meta("shadow_lod_bias") or mesh.get_surface_count() == 0:
		return 0.0
	var tris := 0
	for s: int in mesh.get_surface_count():
		tris += _surface_tris(mesh as ArrayMesh, s)
	var b := float(mesh.get_meta("shadow_lod_bias")) / SHADOW_ERROR_PX
	return b if tris >= TWIN_MIN_TRIS and b < 0.8 else 0.0


## Cut heavy MultiMeshInstance3D children of `parent` into `cell`-metre grid
## chunks (siblings that keep every setting), so each chunk gets its own LOD,
## culling and visibility range. `min_range` > 0 raises (never lowers) the
## visibility range of the chunks: the whole-colony batch was effectively never
## range-culled, and a camera that sees 250 m must not lose props now.
## Small meshes stop casting shadows.
static func split_multimeshes(parent: Node, cell: float, min_range: float = 0.0) -> void:
	for c: Node in parent.get_children():
		if c is MultiMeshInstance3D:
			_split(c as MultiMeshInstance3D, cell, min_range)


static func _split(mmi: MultiMeshInstance3D, cell: float, min_range: float) -> void:
	var mm := mmi.multimesh
	if mm == null or mm.mesh == null:
		return
	var piece := _piece_size(mm)
	var tris := 0
	for s: int in mm.mesh.get_surface_count():
		tris += _surface_tris(mm.mesh as ArrayMesh, s) if mm.mesh is ArrayMesh else 0
	if mm.mesh is ArrayMesh:
		var lm := lodded(mm.mesh)
		if lm != mm.mesh:
			mm.mesh = lm
	var range_end := mmi.visibility_range_end
	if min_range > 0.0 and range_end > 0.0:
		mmi.visibility_range_end = maxf(range_end, min_range)
	var count := mm.instance_count if mm.visible_instance_count < 0 else mm.visible_instance_count
	if count < 2 or tris * count < SPLIT_MIN_TRIS:
		_shadow_for(mmi, piece)
		return
	var cells: Dictionary = {}  # Vector2i -> Array of instance indices (an Array: packed arrays are copied on write)
	for i: int in count:
		var o := mm.get_instance_transform(i).origin
		var k := Vector2i(floori(o.x / cell), floori(o.z / cell))
		if not cells.has(k):
			cells[k] = []
		(cells[k] as Array).append(i)
	if cells.size() < 2:
		return
	var parent := mmi.get_parent()
	var at := mmi.get_index()
	var keys := cells.keys()
	keys.sort()
	for k: Vector2i in keys:
		var idx: Array = cells[k]
		var part := MultiMesh.new()
		part.transform_format = mm.transform_format
		part.use_colors = mm.use_colors
		part.use_custom_data = mm.use_custom_data
		part.mesh = mm.mesh
		part.instance_count = idx.size()
		for j: int in idx.size():
			part.set_instance_transform(j, mm.get_instance_transform(idx[j]))
			if mm.use_colors:
				part.set_instance_color(j, mm.get_instance_color(idx[j]))
			if mm.use_custom_data:
				part.set_instance_custom_data(j, mm.get_instance_custom_data(idx[j]))
		var chunk := MultiMeshInstance3D.new()
		chunk.name = "%s_%d_%d" % [mmi.name, k.x, k.y]
		chunk.multimesh = part
		_copy_settings(mmi, chunk)
		parent.add_child(chunk)
		at += 1
		parent.move_child(chunk, at)
		if _shadow_for(chunk, piece):
			at += 1
		stats["chunks"] = int(stats["chunks"]) + 1
	stats["split"] = int(stats["split"]) + 1
	parent.remove_child(mmi)
	mmi.queue_free()


## A heavy batch casts through a shadow-only twin right after it (geometric LOD,
## shared MultiMesh, so pruning instances prunes the shadow too); a light one is
## handed to ShadowLod. True if a twin was added.
static func _shadow_for(mmi: MultiMeshInstance3D, piece: float) -> bool:
	var bias := _twin_bias(mmi.multimesh.mesh, mmi.cast_shadow)
	if bias <= 0.0:
		ShadowLod.register(mmi, piece)
		return false
	var tw := MultiMeshInstance3D.new()
	tw.name = String(mmi.name) + "_shadow"
	tw.multimesh = mmi.multimesh
	_copy_settings(mmi, tw)
	tw.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	tw.lod_bias = bias
	tw.set_meta("is_shadow_twin", true)
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.set_meta("has_shadow_twin", true)
	var parent := mmi.get_parent()
	parent.add_child(tw)
	parent.move_child(tw, mmi.get_index() + 1)
	ShadowLod.register(tw, piece)
	stats["twins"] = int(stats["twins"]) + 1
	return true


static func _copy_settings(from: MultiMeshInstance3D, to: MultiMeshInstance3D) -> void:
	to.transform = from.transform
	to.visible = from.visible
	to.layers = from.layers
	to.material_override = from.material_override
	to.material_overlay = from.material_overlay
	to.cast_shadow = from.cast_shadow
	to.gi_mode = from.gi_mode
	to.lod_bias = from.lod_bias
	to.extra_cull_margin = from.extra_cull_margin
	to.ignore_occlusion_culling = from.ignore_occlusion_culling
	to.visibility_range_begin = from.visibility_range_begin
	to.visibility_range_begin_margin = from.visibility_range_begin_margin
	to.visibility_range_end = from.visibility_range_end
	to.visibility_range_end_margin = from.visibility_range_end_margin
	to.visibility_range_fade_mode = from.visibility_range_fade_mode
	for m: StringName in from.get_meta_list():
		to.set_meta(m, from.get_meta(m))


## Largest side (metres) of the biggest drawn instance (sampled).
static func _piece_size(mm: MultiMesh) -> float:
	var box := mm.mesh.get_aabb()
	var side := maxf(box.size.x, maxf(box.size.y, box.size.z))
	var biggest := 0.0
	var n := mm.instance_count if mm.visible_instance_count < 0 else mm.visible_instance_count
	for i: int in mini(n, 512):
		var b := mm.get_instance_transform(i).basis
		biggest = maxf(biggest, maxf(b.x.length(), maxf(b.y.length(), b.z.length())))
	return side * biggest


static func _generate(src: ArrayMesh) -> ArrayMesh:
	var im := ImporterMesh.new()
	for s: int in src.get_surface_count():
		im.add_surface(Mesh.PRIMITIVE_TRIANGLES, src.surface_get_arrays(s), [], {}, null, src.surface_get_name(s))
	im.generate_lods(NORMAL_MERGE_ANGLE, 0.0, [])
	var out := im.get_mesh()
	if out == null or out.get_surface_count() != src.get_surface_count() or lod_count(out) == 0:
		return src
	stats["generated"] = int(stats["generated"]) + 1
	var tris := 0
	for s: int in src.get_surface_count():
		tris += _surface_tris(src, s)
	if tris >= TWIN_MIN_TRIS:
		out.set_meta("shadow_lod_bias", geometric_bias(im, src.get_aabb().size.length()))
	var key := _cache_key(src)
	if not key.is_empty():
		DirAccess.make_dir_recursive_absolute(CACHE_DIR)
		ResourceSaver.save(out, key)  # without materials: those stay the pack's own, set below
	_finish(src, out)
	return out


static func _from_disk(src: Mesh) -> ArrayMesh:
	var key := _cache_key(src)
	if key.is_empty() or not FileAccess.file_exists(key):
		return null
	var out := ResourceLoader.load(key, "ArrayMesh", ResourceLoader.CACHE_MODE_IGNORE) as ArrayMesh
	if out == null or out.get_surface_count() != src.get_surface_count():
		return null
	stats["from_disk"] = int(stats["from_disk"]) + 1
	_finish(src, out)
	return out


static func _finish(src: Mesh, out: ArrayMesh) -> void:
	for s: int in src.get_surface_count():
		out.surface_set_material(s, src.surface_get_material(s))
	out.resource_name = src.resource_name if not src.resource_name.is_empty() else src.resource_path.get_file().get_basename()
	out.custom_aabb = (src as ArrayMesh).custom_aabb if src is ArrayMesh else AABB()
	for m: StringName in src.get_meta_list():
		out.set_meta(m, src.get_meta(m))
	out.set_meta("lod_source", src.resource_path)


## How much smaller the measured silhouette error of each LOD is than the
## importer's (normal-weighted) error, as a lod_bias: the largest ratio over all
## levels and surfaces, so no level switches before its geometric error allows.
## Error = 95th percentile distance between LOD0 face centres and the reduced
## surface (and back), probed along 14 directions; a miss counts as a quarter of
## the mesh diagonal, so doubtful levels stay conservative.
static func geometric_bias(im: ImporterMesh, diag: float) -> float:
	var bias := 0.02
	for s: int in im.get_surface_count():
		var arr := im.get_surface_arrays(s)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		if arr[Mesh.ARRAY_INDEX] == null:
			return 1.0
		var i0: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		var tm0 := _trimesh(v, i0)
		for l: int in im.get_surface_lod_count(s):
			var il := im.get_surface_lod_indices(s, l)
			var err := maxf(_surface_error(v, i0, _trimesh(v, il), diag), _surface_error(v, il, tm0, diag))
			var size := im.get_surface_lod_size(s, l)
			if size <= 0.0:
				return 1.0
			bias = maxf(bias, err / size)
	return minf(bias, 1.0)


## The same LOD index sets as `im`, keyed by measured silhouette error (metres)
## instead of the importer's error: the engine then switches a level when its
## geometric deviation is under the viewport threshold (1 px). Materials as in `im`.
static func with_geometric_lods(im: ImporterMesh, diag: float) -> ArrayMesh:
	var out := ArrayMesh.new()
	for s: int in im.get_surface_count():
		var arr := im.get_surface_arrays(s)
		var lods := {}
		if arr[Mesh.ARRAY_INDEX] != null:
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var i0: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
			var tm0 := _trimesh(v, i0)
			var prev := 0.0
			for l: int in im.get_surface_lod_count(s):
				var il := im.get_surface_lod_indices(s, l)
				var err := maxf(_surface_error(v, i0, _trimesh(v, il), diag), _surface_error(v, il, tm0, diag))
				err = maxf(err, prev * 1.05 + 0.0001)  # strictly increasing, as the engine expects
				lods[err] = il
				prev = err
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr, [], lods)
		out.surface_set_material(out.get_surface_count() - 1, im.get_surface_material(s))
	return out


static func _trimesh(v: PackedVector3Array, idx: PackedInt32Array) -> TriangleMesh:
	var faces := PackedVector3Array()
	faces.resize(idx.size())
	for k: int in idx.size():
		faces[k] = v[idx[k]]
	var tm := TriangleMesh.new()
	tm.create_from_faces(faces)
	return tm


static func _surface_error(v: PackedVector3Array, idx: PackedInt32Array, to: TriangleMesh, diag: float) -> float:
	var reach := diag * 0.25
	var ds := PackedFloat32Array()
	var n := idx.size() / 3
	var stride := maxi(1, n / 160)
	for k: int in range(0, n, stride):
		var p := (v[idx[k * 3]] + v[idx[k * 3 + 1]] + v[idx[k * 3 + 2]]) / 3.0
		var best := reach
		for dir: Vector3 in _DIRS:
			var h := to.intersect_segment(p - dir * 0.0005, p + dir * best)
			if not h.is_empty():
				best = minf(best, (h["position"] as Vector3).distance_to(p))
				if best < 0.001:
					break
		ds.append(best)
	if ds.is_empty():
		return reach
	ds.sort()
	return ds[mini(ds.size() - 1, int(ds.size() * 0.95))]


## user://mesh_lods/<hash>.res for meshes loaded from a pack file ("" otherwise).
static func _cache_key(src: Mesh) -> String:
	var p := src.resource_path
	if p.is_empty() or p.contains("::"):
		return ""
	var stamp := FileAccess.get_modified_time(p)
	var tris := 0
	for s: int in src.get_surface_count():
		tris += _surface_tris(src as ArrayMesh, s)
	return CACHE_DIR.path_join("%s.res" % ("%s|%d|%d|%d|%.1f" % [p, stamp, tris, CACHE_VERSION, NORMAL_MERGE_ANGLE]).md5_text())

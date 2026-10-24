# Review findings

**1. `ground_cover.gd` → `build()` — `sc[0]`/`sc[1]` crash when `scale` array is malformed**
```gdscript
var s := rng.randf_range(float(sc[0]), float(sc[1])) if sc.size() == 2 else 1.0
```
The guard is correct here, but the same pattern is used for `cover` (`smin`/`smax`) and `landmarks` (`sc[0]`/`sc[1]`) — those are also guarded. **However**, `_cliffs` uses `box.size.y` and `landmarks` uses `ring[0]`/`ring[1]` guarded. No crash here. Skip.

**1. `ground_cover.gd` → `build()` (trees loop) — `srcs[k][1]` cast when `mesh_of` returns a 3-element array is fine, but `_multimesh(srcs[k][0], ...)` assumes `srcs[k][0]` is a `Mesh`.** `mesh_of` returns `[]` or `[mesh, xf, aabb]` — safe. Skip.

**1. `ground_cover.gd` → `_blocked()` — crashes on malformed `avoid` entries**
```gdscript
var arr: Array = a
if p.distance_to(arr[0]) < float(arr[1]) + extra:
```
If any `avoid` element is not a 2-element array (e.g. a `Vector2` or a dict), `arr[0]`/`arr[1]` throws. `avoid` is caller-supplied and untyped. **Fix:** `if not (a is Array) or (a as Array).size() < 2: continue`.

**2. `ground_cover.gd` → `build()` (landmarks) — `ring[0]`/`ring[1]` crash when `ring` has 1 element**
```gdscript
var r := rng.randf_range(float(ring[0]), float(ring[1])) if ring.size() == 2 else 80.0
```
Guarded. Skip.

**2. `ground_cover.gd` → `build()` (cover) — `sc[0]`/`sc[1]` crash when `scale` has 1 element**
```gdscript
var smin := float(sc[0]) if sc.size() == 2 else 1.0
var smax := float(sc[1]) if sc.size() == 2 else 1.0
```
Guarded. Skip.

**2. `ground_cover.gd` → `build()` (trees) — `sc[0]`/`sc[1]` crash when `scale` has 1 element**
```gdscript
var s := rng.randf_range(float(sc[0]), float(sc[1])) if sc.size() == 2 else 1.0
```
Guarded. Skip.

**2. `ground_cover.gd` → `build()` (landmarks) — `sc[0]`/`sc[1]` crash when `scale` has 1 element**
```gdscript
var s := rng.randf_range(float(sc[0]), float(sc[1])) if sc.size() == 2 else 1.0
```
Guarded. Skip.

**2. `ground_cover.gd` → `build()` (trees) — `it.get("radius", 0.5)` used as `float` but `it` is `Dictionary`; fine. Skip.**

**2. `ground_cover.gd` → `build()` (cover) — `for k: int in cluster:` iterates `cluster` times, but `cluster` is `maxi(1, ...)` so ≥1. Fine. Skip.**

**2. `ground_cover.gd` → `build()` (landmarks) — `for i: int in n:` where `n = int(it.get("count", 10))`. If `count` is 0 or negative, loop doesn't run. Fine. Skip.**

**2. `ground_cover.gd` → `build()` (landmarks) — `srcs[rng.randi() % srcs.size()]` — `srcs` non-empty (checked). Fine. Skip.**

**2. `ground_cover.gd` → `build()` (landmarks) — `box.position.y * s` — `box` is `AABB` from `src[2]`, which is `local * mesh.get_aabb()`. Fine. Skip.**

**2. `ground_cover.gd` → `_cliffs()` — `box.size.y` could be 0 → division by zero**
```gdscript
var s := rng.randf_range(22.0, 34.0) / maxf(box.size.y, 0.1)
```
Guarded with `maxf(..., 0.1)`. Skip.

**2. `ground_cover.gd` → `_cliffs()` — `src[2]` cast to `AABB` when `mesh_of` returns `[]`?** `usable` only contains paths where `mesh_of(...)` is non-empty, and `src := mesh_of(...)` is re-fetched — but if `mesh_of` returns `[]` on the second call (cache miss? no, it's cached), `src[2]` crashes. Since `_meshes` caches, second call returns same. Safe in practice. Skip.

**2. `ground_cover.gd` → `_mesh_of()` — `(load(path) as PackedScene).instantiate()` crashes if `load` returns non-PackedScene**
```gdscript
if not path.is_empty() and ResourceLoader.exists(path):
    var inst: Node = (load(path) as PackedScene).instantiate()
```
`ResourceLoader.exists` returns true for any resource type. If `path` points to a `.tres`/`.res` that isn't a `PackedScene`, `as PackedScene` yields `null` and `.instantiate()` throws. **Fix:** `var ps := load(path) as PackedScene; if ps == null: _meshes[path] = []; return []`.

**3. `nature_kit.gd` → `mesh()` — same `as PackedScene` crash**
```gdscript
var inst: Node = (load(path) as PackedScene).instantiate()
```
Same defect. **Fix:** null-check the cast.

**4. `nature_kit.gd` → `mesh()` — `slots[s]` out-of-bounds when `_slots_for` returns fewer slots than surfaces**
```gdscript
var mat: Material = _material(pack, slots[s] if s < slots.size() else {}, look)
```
Guarded. Skip.

**4. `nature_kit.gd` → `_material()` — `tex["_Triplanar_Texture_Side"]` used as fallback for top when `_Triplanar_Texture_Top` missing**
```gdscript
rm.set_shader_parameter("top_tex", ... _tex(pack, str(tex.get("_Triplanar_Texture_Top", tex["_Triplanar_Texture_Side"]))))
```
`tex.get(key, default)` evaluates `default` eagerly — `tex["_Triplanar_Texture_Side"]` is safe here because the branch is only entered when `tex.has("_Triplanar_Texture_Side")`. Skip.

**4. `nature_kit.gd` → `_material()` — `tex["_Leaf_Texture"]` in the `else` branch of trunk fallback**
```gdscript
sm.set_shader_parameter("trunk_tex", _tex(pack, trunk if not trunk.is_empty() else str(tex["_Leaf_Texture"])))
```
Branch only entered when `tex.has("_Leaf_Texture")`. Safe. Skip.

**4. `nature_kit.gd` → `_transform_arrays()` — `a[Mesh.ARRAY_VERTEX]` may be `null` for some surface formats**
```gdscript
var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
for i: int in v.size():
```
If a surface lacks vertex data (unusual but possible for e.g. point clouds or malformed FBX), `v` is `null` and `.size()` throws. **Fix:** `if a[Mesh.ARRAY_VERTEX] == null: return`.

**4. `nature_kit.gd` → `_transform_arrays()` — `a[Mesh.ARRAY_NORMAL]` null check present, but `a[Mesh.ARRAY_TANGENT] = null` unconditionally.** Fine.

**4. `nature_kit.gd` → `_transform_arrays()` — normals not re-normalized after non-uniform scale.** `xf.basis * nn[i]` then `.normalized()` — correct. Skip.

**4. `nature_kit.gd` → `_transform_arrays()` — `xf.basis * nn[i]` uses basis without inverse-transpose; wrong for non-uniform scale.** FBX local transforms are typically uniform, but if a node has non-uniform scale, normals skew. **Fix:** use `xf.basis.inverse().transposed() * nn[i]` (or `xf.basis * nn[i]` only if uniform). This is a real math defect for non-uniform scaled nodes.

**5. `nature_kit.gd` → `_scan()` — `DirAccess.get_files_at(dir)` crashes if `dir` doesn't exist**
```gdscript
for f: String in DirAccess.get_files_at(dir):
```
If `pack/Textures` is missing (partial asset), `get_files_at` returns `PackedStringArray()` in Godot 4 (doesn't crash), but `get_directories_at` on a missing dir also returns empty. Actually in Godot 4 these return empty arrays on error. Skip.

**5. `nature_kit.gd` → `_list()` — `DirAccess.get_files_at(pack)` on missing pack returns empty; fine. Skip.**

**5. `nature_kit.gd` → `_all_packs()` — `DirAccess.get_directories_at("res://assets/Synty/Nature")` returns empty if dir missing; fine. Skip.**

**5. `nature_kit.gd` → `_tex()` — `load(p)` where `p` may be a `.import`/`.remap` path.** `_scan` stores `dir.path_join(name)` where `name` is the trimmed source name (e.g. `x.png`), so `p` is `.../x.png` — `ResourceLoader.exists` on a source `.png` in an exported build returns false (only `.import` exists). **Fix:** in `_scan`, store the actual file path (`dir.path_join(f)`) not the trimmed name, or check both. This is a real defect: textures silently fail to load in exported builds.

**6. `fauna_flock.gd` → `build()` — `terrain.call("height_at", ...)` when `terrain` is null**
```gdscript
var jit := maxf(0.2, (h - (float(terrain.call("height_at", centre.x, centre.z)) if terrain

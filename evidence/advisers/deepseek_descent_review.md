# Review: PlanetDescent / DescentHud / SeaLeviathan

**1. `planet_descent.gd:_finish()` — `_done` set before `finished.emit()`, but `_skip()` on ascent path emits `finished` without cleanup**
`_skip()` (ascent branch) sets `_done = true` and emits `finished` but never restores `_world_env.environment`, `_restore_fog()`, `_show_surface()`, `_stretch_cover(false)`, `_site_water.visible`, `_sky_far` positions, `lander_body.top_level = false`, `_body_rest`, `_cam.current`, or `_layers` visibility. The caller then changes scene, so the surface root's CanvasLayers stay hidden and the lander stays top-level (leaks into the next scene if the node survives). **Fix:** route ascent skip through `_finish()` (or a shared `_teardown()`), guarding the descent-only bits.

**2. `planet_descent.gd:_finish()` — `queue_free()` while `_cam.current = false` and `_layers` restored, but `_hud` (CanvasLayer, layer 20) is a child of `self` and is freed with it; if `finished` handlers read `_gauge`/`_lbl_*` they hit freed nodes**
More concretely: `finished.emit()` runs *before* `queue_free()`, so listeners are fine, but any deferred callback (e.g. the `get_tree().create_timer(0.7).timeout.connect(_finish)` from `_touchdown`, or the `4.0` dust timer) can fire after `queue_free()` and touch freed nodes. **Fix:** guard `_finish()` with `if not is_inside_tree(): return` at top, and disconnect/ignore timers on free (or use `create_tween().bind_node(self)`).

**3. `planet_descent.gd:_touchdown()` — dust timer + `_finish` timer are not cancelled on skip**
If the player presses skip during the 0.7 s window after touchdown, `_skip()` calls `_finish()` immediately; then the pending `create_timer(0.7).timeout.connect(_finish)` fires on a freed node → error. Same for the 4 s dust `queue_free` if the lander is freed. **Fix:** store the timer / use `SceneTreeTimer` with a validity check, or `if is_instance_valid(self) and not _done` inside `_finish` (already there) plus `if is_instance_valid(dust)` in the dust callback.

**4. `planet_descent.gd:_begin_landing()` — tween on `lander_body` not bound to node; skip during landing frees the tween target**
`_skip()` during `_landing` calls `_finish()` → `queue_free()` of `self`, but the tween created in `_begin_landing` targets `lander_body` (still alive) and its `tween_callback(_touchdown)` will fire on a freed `self`. **Fix:** `create_tween().bind_node(self)` so the tween dies with the descent node.

**5. `planet_descent.gd:_process()` — `_update_hud` calls `_cam.unproject_position` / `is_position_behind` every frame even when `_cam` may be freed or when `_done`**
`_process` early-returns on `_done`, but `_update_hud` runs `_gauge.queue_redraw()` every frame unconditionally — a full redraw of the ladder + chevron each frame. Cheap but wasteful; more importantly `_gauge.visible = not _landing` while `_update_hud` still runs during landing (drawing off-screen). **Fix:** skip `_update_hud` when `_landing` (or gate `queue_redraw` on value change).

**6. `planet_descent.gd:_update_fx()` — `_streaks.multimesh.set_instance_transform` loop of 140 per frame plus `_streak_pts` mutation is fine, but `_plasma.global_basis` uses `Basis.looking_at(...).scaled(...)` where `scaled` on a rotation basis with non-uniform scale produces a skewed basis**
`Basis.looking_at(fwd, up).scaled(Vector3(4.2, 3.4, 8.5) * scale_k)` — `Basis.scaled` multiplies rows, which for a non-uniform scale on a rotation gives a sheared matrix, not a rotated+scaled one. The plasma sphere will visibly shear at high `scale_k` (Ark). **Fix:** `Basis.looking_at(fwd, up) * Basis.from_scale(Vector3(4.2,3.4,8.5) * scale_k)`.

**7. `planet_descent.gd:_fly()` — `heading.slerp(tdir, ...)` on `Vector3` when `heading` and `tdir` are near-antiparallel is guarded by `dot > -0.95`, but `heading` may be `Vector3.ZERO`-ish**
`hv.normalized() if hv.length() > 1.0 else to.normalized()` — if `to` is also near-zero (lander directly over pad at start of assist), `to.normalized()` is `(0,0,0)` and `heading.slerp` on zero vector yields NaN basis → lander transform corrupts. **Fix:** fall back to `-lander_body.global_basis.z` when both are degenerate.

**8. `planet_descent.gd:_ground_y()` — divide-by-zero / wrong curve when `p` is exactly at `target`**
`d * d / (2.0 * R_PLANET)` is fine, but `_ground_y` returns `terrain.height_at` inside the map and the globe-curve formula outside; at the map boundary the two disagree (terrain height vs `target.y - 14 - d²/2R`), so `_alt` jumps discontinuously as the lander crosses `half`, causing a visible pop in HUD altitude and in `_set_sky` / `_fog_for_alt` thresholds. **Fix:** blend the two over a margin, or clamp `_alt` change per frame.

**9. `planet_descent.gd:_update_camera()` — `_cam.look_at(look, Vector3.UP)` when `look` is directly above/below camera**
During ascent with `_alt > 700`, `look = pos - back*60 + DOWN*40`; if `back` is near-vertical (steep climb), `look - cam_pos` can be near-parallel to `UP` → `look_at` with `UP` produces NaN basis. **Fix:** `var up := Vector3.UP if absf((look - _cam.global_position).normalized().dot(Vector3.UP)) < 0.99 else Vector3.FORWARD`.

**10. `planet_descent.gd:_set_sky()` — `AudioService.set_ambience_any(["amb_surface_" + str(planet.get("biome_id")), ...])` called every frame the sky flips, but also `_set_sky` is called from `start()` before `_hud`/`_gauge` exist? No — but `_set_sky` calls `_hide_surface()` which iterates `surface_root` children and hides `_site_water`'s parent terrain meshes; on `_show_surface` it restores `visible = true` for everything in `_hidden`, including nodes that were *already* invisible for other reasons (e.g. culled by gameplay). **Fix:** record prior `visible` state per node, restore that, not `true`.

**11. `sea_leviathan.gd:_place()` — `_body.basis` set every frame but `_spray.global_basis` set every frame too; `_spray.emitting` toggled every frame**
`_spray.emitting = surf` is assigned every frame — Godot's `GPUParticles3D.emitting` setter restarts the emission cycle when it changes, but assigning the same value is a no-op; however `_spray.global_position`/`global_basis` are set every frame even when `k == 0` and `visible == false`, wasting work. More importantly: when `_cycle` wraps and `_new_spot` teleports `_pos`, the spray's `local_coords = false` particles from the previous spot keep emitting at the old world position for up to `lifetime` (2.2 s) — a visible spray plume in the middle of nowhere. **Fix:** `_spray.emitting = false` and `_spray.restart()` (or `emitting = false` for one frame) on `_new_spot`.

**12. `sea_leviathan.gd:build()` — `_height`/`_length` computed from `box.size` *after* `inst.scale` is applied, but `AssetSlots.aabb_of(inst, Transform3D.IDENTITY)` is measured *before* `inst.scale` is set**
`var box := AssetSlots.aabb_of(inst, Transform3D.IDENTITY)` runs on the unscaled instance; then `inst.scale = Vector3.ONE * s`; then `l._height = box.size.y * s` — correct. But `inst.position = -Vector3(box.get_center().x, box.position.y, box.get_center().z) * s` uses `box.position.y` (min Y) not `box.get_center().y`, so the model is offset by `-box.position.y * s` rather than centered vertically — the serpent's pivot sits at its feet, and `_place()`'s `sink` math (which assumes pivot at model center) is off by half the height. **Fix:** use `box.get_center().y` for the Y offset, or document that `_height` is measured from the base.

---

**Cross-file note (counts as part of #1):** `descent_hud.gd:_draw()` calls `UiKit.body_font()` and `Loc.t()` every redraw; `_update_hud` calls `queue_redraw()` every frame → `Loc.t` (likely a dictionary lookup) × 3 + font fetch × 60/s. Minor, but if `Loc.t` does any allocation it's a per-frame GC trap. Cache the strings when `_phase`/`_landing`/`autopilot` change instead.

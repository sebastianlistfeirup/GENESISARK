# ShipWakeup / power_wave / ship scene — concrete bugs

**1. `ShipWakeup._finish()` never runs if the node is freed or the scene changes mid-sequence — captain/HUD/input stay disabled.**
`start()` sets `captain.visible = false`, `captain.input_enabled = false`, `hud.visible = false`. The only place these are restored is `_finish()`. If the player quits to menu, the ship scene is reloaded, or the node is freed (e.g. `queue_free` from elsewhere, scene change during the 9 s), the captain stays invisible with input disabled and the HUD hidden. There is no `_exit_tree` / `_notification(NOTIFICATION_PREDELETE)` cleanup. Minimal fix: add
```gdscript
func _exit_tree() -> void:
    if _done: return
    _done = true
    if is_instance_valid(captain):
        captain.visible = true
        captain.input_enabled = true
    if is_instance_valid(hud): hud.visible = true
```
(and guard `_finish` against double-run). Same applies to `waypoints.visible` — if `finished` never fires, waypoints stay hidden.

**2. `_open_now()` timer fires on a possibly-freed vapour node.**
`get_tree().create_timer(6.0).timeout.connect(vapour.queue_free)` — if the ship scene is torn down (or `ShipWakeup` freed) before 6 s, `vapour` is already freed and `queue_free` on a freed instance errors. Also the timer itself is not tied to the node's lifetime. Minimal fix: `vapour.tree_exiting`-safe pattern, e.g. connect with `CONNECT_ONE_SHOT` and check `is_instance_valid(vapour)` in a lambda, or parent the timer to `vapour` via `get_tree().create_timer(6.0, false)` + `if is_instance_valid(vapour): vapour.queue_free()`.

**3. Skip path leaves `_t` past `_dur` but `_finish` still waits a frame — and skip during reduced-motion is a no-op that can double-fire `_open_now`.**
`if Input.is_action_just_pressed("skip_line") or ... "pause": _t = maxf(_t, _dur - 0.6); _open_now()`. In reduced motion `_t` starts at 6.5 and `_dur` is 2.5, so `_t >= _dur` immediately and `_finish()` runs on the first `_process` — but the same frame also processes the skip branch, calling `_open_now()` (guarded, fine) and then `_finish()` — OK. The real bug: pressing `pause` here consumes the pause action for the wakeup but the pause menu is never opened, and `_process` keeps running because `_done` is only set in `_finish`. If `_finish` is delayed (e.g. `_t` clamped below `_dur` on a slow first frame), the pause press is swallowed. Minimal fix: on skip, call `_finish()` directly instead of nudging `_t`, and don't consume `pause` — use only `skip_line`/`ui_cancel` or forward the pause to the pause menu.

**4. `_cam.current = true` re-asserted every frame fights the captain's rig; on `_finish` the rig may not yet be `current` when `snap()` runs.**
`if not _cam.current: _cam.current = true` runs each frame until `_done`. In `_finish`, `captain.camera_rig.camera.current = true` then `snap()` — but `_process` for this node may run again before `_done` short-circuits? No: `_done = true` is set first, so `_process` returns early. However the ordering `camera.current = true` then `snap()` is fine only if `snap()` reads the *new* current camera; if `snap()` computes from the old transform it can pop. More concrete: if `captain.camera_rig` is null (captain freed / different rig), `_finish` throws and leaves input disabled. Minimal fix: `if is_instance_valid(captain) and captain.camera_rig: ...` guard, and set `_done = true` before touching captain so a throw can't re-enter.

**5. `power_wave` tweens target `OmniLight3D`/`Node3D` that may be freed; no `is_instance_valid` guard on the light/lamp tweens.**
The `power_nodes` loop guards `is_instance_valid(n)`, but the `lights` loop does not: `tw.tween_property(ol, "light_energy", ...)` and the `lamp.visible = true` callback will error if a lamp/light is freed mid-wave (scene change, ship rebuild). Also `create_tween()` is bound to the *builder* node; if the builder is freed the tween is killed silently and `done` never fires — callers waiting on `done` hang. Minimal fix: guard `if not is_instance_valid(ol) or not is_instance_valid(lamp): continue` at loop top, and in the `done` callback check `is_instance_valid(self)` before calling.

**6. `power_wave` `done` callback is dropped if the tween is killed (re-entrant `power_wave` call).**
`_flicker.clear(); set_process(false); var tw := create_tween()...` — a second `power_wave` call (e.g. power toggled twice quickly, or `_on_state` fires again) creates a new tween but the old one is never killed and its `done` may still fire, or the new one overwrites state mid-flight. Worse: the first call's `done` Callable is lost if the tween is auto-killed. Minimal fix: store `_wave_tween` and `if _wave_tween and _wave_tween.is_valid(): _wave_tween.kill()` at entry, and invoke `done` from a single terminal callback guarded by a generation counter.

**7. `_on_state` ambient tween is not killed on re-entry; overlapping power transitions corrupt ambient.**
`if powered and not _was_powered ...: var tw := create_tween(); tw.tween_property(we.environment, "ambient_light_energy", 0.0, 0.45) ...` — if `_on_state` fires again (another state change) before this 2.5 s tween finishes, a second tween runs concurrently on the same `ambient_light_energy`/`ambient_light_color`, producing flicker or a stuck value. Also if `we.environment` is freed (scene change) the tween errors. Minimal fix: keep a `_ambient_tween` member, `kill()` it at the top of the branch, and guard `is_instance_valid(we)`.

**8. `power_wave` delay math is frame-rate independent but `last` can be `0.0` when `lights` is empty, so `done` fires at `0.6 s` while `set_strip_glow` fires at `0.85 s` — `done` before the strip glow.**
`last` starts at `0.0`; if `lights` is empty (or all skipped), `tw.tween_callback(set_strip_glow...).set_delay(0.85 + (last - 0.85) * 0.4)` = `0.85 + (-0.85)*0.4 = 0.51`, and `done` at `last + 0.6 = 0.6`. So `done` fires *after* strip glow here — but if `last` is small (single close light, `delay ≈ 0.85`), `done` at `1.45` and strip glow at `0.85` — fine. The actual bug: `done` is scheduled at `last + 0.6` but the *last* light's settle tween ends at `delay + 0.09 + 0.45 = last + 0.54`, so `done` at `last + 0.6` is only 0.06 s after settle — acceptable, but if `last` is dominated by a `power_nodes` entry further out than any light, `done` fires before those nodes power on. Minimal fix: track `last` across *both* loops (`last = maxf(last, d)` in the `power_nodes` loop too).

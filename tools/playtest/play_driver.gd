extends Node
## DEV TOOL (D-066): plays the first half hour of GENESIS ARK like a player.
## Injects real input (keys, mouse clicks on controls found by their text,
## analog move/look like a stick), walks the captain to the objective targets,
## captures a JPEG at every beat and logs state, timings and friction.
## Never part of the player flow: boot adds it only with --playtest.
##   godot --path . -- --playtest=evidence/playtest_r1 [--pt_speed=1] [--pt_from=menu|orbit|colony]
##        [--pt_until=<stage>] [--pt_skip_wakeup=1] [--pt_probe=1] [--pt_dest=viridia]
## Saves go to user://saves_debug (SaveService), settings are never written.

const STAGES := ["menu", "wakeup", "power", "embryo", "starmap", "flight", "orbit", "descent", "surface",
	"ascent", "savecycle", "landing", "colony"]

var out_dir := "evidence/playtest_r1"
var speed := 1.0
var from := "menu"
var until := ""
var dest := "viridia"
var skip_wakeup := false
var probe := false
var _abs_dir := ""
var _t0 := 0
var _stage := ""
var _stage_t0 := 0
var _shot_n := 0
var timings: Array = []   # [{stage, seconds, ok}]
var findings: Array = []  # [{stage, kind, text}]
var log_lines: Array = []
var errors_seen := 0
var _steer := Vector2.ZERO  # last analog move written (for release)


static func requested() -> bool:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--playtest"):
			return true
	return false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a: String in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		var v := kv[1] if kv.size() == 2 else "1"
		match kv[0]:
			"playtest": out_dir = v if v != "1" else out_dir
			"pt_speed": speed = float(v)
			"pt_from": from = v
			"pt_until": until = v
			"pt_dest": dest = v
			"pt_skip_wakeup": skip_wakeup = v == "1"
			"pt_probe": probe = v == "1"
	_abs_dir = out_dir if out_dir.is_absolute_path() else ProjectSettings.globalize_path("res://" + out_dir)
	DirAccess.make_dir_recursive_absolute(_abs_dir + "/shots")
	Engine.time_scale = speed
	_t0 = Time.get_ticks_msec()
	_clear_debug_saves()
	_run.call_deferred()


func _clear_debug_saves() -> void:
	# Only the debug folder (SaveService points there under --playtest); never user://saves.
	var d := DirAccess.open("user://saves_debug")
	if d == null:
		return
	for f: String in d.get_files():
		d.remove(f)


# ------------------------------------------------------------------ logging

func now_s() -> float:
	return (Time.get_ticks_msec() - _t0) / 1000.0


func log_ev(what: String, data: Dictionary = {}) -> void:
	var e := {"t": snappedf(now_s(), 0.01), "stage": _stage, "ev": what}
	e.merge(data)
	log_lines.append(e)
	print("PLAYTEST ", JSON.stringify(e))


func finding(kind: String, text: String) -> void:
	findings.append({"stage": _stage, "t": snappedf(now_s(), 0.1), "kind": kind, "text": text})
	log_ev("FINDING", {"kind": kind, "text": text})


func begin(stage: String) -> void:
	_stage = stage
	_stage_t0 = Time.get_ticks_msec()
	log_ev("begin")


func end_stage(ok: bool, note: String = "") -> void:
	var s := (Time.get_ticks_msec() - _stage_t0) / 1000.0
	timings.append({"stage": _stage, "seconds": snappedf(s * speed, 0.1), "ok": ok, "note": note})
	log_ev("end", {"ok": ok, "seconds": snappedf(s, 0.1), "note": note})


func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img == null or img.is_empty():
		return
	_shot_n += 1
	img.resize(960, int(960.0 * img.get_height() / img.get_width()), Image.INTERPOLATE_BILINEAR)
	var fname := "%02d_%s.jpg" % [_shot_n, name]
	img.save_jpg(_abs_dir + "/shots/" + fname, 0.72)
	log_ev("shot", {"file": fname, "scene": AppFlow.current_key, "prompt": _prompt_text(), "objective": _objective_text(),
		"music": AudioService.music_slot(), "ambience": AudioService.ambience_slot()})


func _write_report() -> void:
	var rep := {"engine": Engine.get_version_info().get("string"), "speed": speed, "from": from,
		"settings": {"reduced_motion": SettingsService.get_value("reduced_motion"), "realtime_descent": SettingsService.get_value("realtime_descent"),
			"subtitles": SettingsService.get_value("subtitles"), "language": SettingsService.get_value("language")},
		"total_s": snappedf(now_s() * speed, 0.1), "timings": timings, "findings": findings,
		"timestamp": Time.get_datetime_string_from_system(true)}
	var f := FileAccess.open(_abs_dir + "/timings.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(rep, "  "))
	f.close()
	var lf := FileAccess.open(_abs_dir + "/log.jsonl", FileAccess.WRITE)
	for e: Dictionary in log_lines:
		lf.store_line(JSON.stringify(e))
	lf.close()


# ------------------------------------------------------------------ waiting

func secs(s: float) -> void:
	await get_tree().create_timer(s, true, false, false).timeout


func frames(n: int) -> void:
	for i: int in n:
		await get_tree().process_frame


## Polls cond every frame until true or timeout (seconds of game time). Returns success.
func wait_until(cond: Callable, timeout: float) -> bool:
	var end := Time.get_ticks_msec() + int(timeout * 1000.0 / speed)
	while Time.get_ticks_msec() < end:
		if cond.call():
			return true
		await get_tree().process_frame
	return bool(cond.call())


func scene() -> Node:
	return get_tree().current_scene


func wait_scene(key: String, timeout: float = 30.0) -> bool:
	var ok := await wait_until(func() -> bool:
		return AppFlow.current_key == key and not AppFlow._busy and scene() != null and scene().is_node_ready(), timeout)
	await frames(10)
	return ok


# ------------------------------------------------------------------ input

func key(code: Key, hold: float = 0.06) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.pressed = true
	Input.parse_input_event(e)
	await secs(hold)
	var r := InputEventKey.new()
	r.keycode = code
	r.physical_keycode = code
	r.pressed = false
	Input.parse_input_event(r)
	await frames(2)


func key_down(code: Key, down: bool) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.pressed = down
	Input.parse_input_event(e)


## Analog movement like a stick: x = right, y = back (Input.get_vector convention).
func steer(v: Vector2) -> void:
	_steer = v
	_axis("move_left", "move_right", v.x)
	_axis("move_forward", "move_back", v.y)


func _axis(neg: String, pos: String, v: float) -> void:
	if v > 0.05:
		Input.action_press(pos, clampf(v, 0.0, 1.0))
		Input.action_release(neg)
	elif v < -0.05:
		Input.action_press(neg, clampf(-v, 0.0, 1.0))
		Input.action_release(pos)
	else:
		Input.action_release(neg)
		Input.action_release(pos)


func look(x: float) -> void:
	_axis("look_left", "look_right", x)


func release_all() -> void:
	steer(Vector2.ZERO)
	look(0.0)
	Input.action_release("sprint")


## Window coordinates of a control's centre (stretch + canvas layer applied).
func screen_pos(c: Control, at: Vector2 = Vector2(0.5, 0.5)) -> Vector2:
	var vp := c.get_global_transform_with_canvas() * (c.size * at)
	return get_tree().root.get_final_transform() * vp


func mouse_move(p: Vector2) -> void:
	var m := InputEventMouseMotion.new()
	m.position = p
	m.global_position = p
	m.relative = Vector2(4, 0)
	Input.parse_input_event(m)


func click_at(p: Vector2, button: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	mouse_move(p)
	await frames(2)
	mouse_move(p)  # again just before the press: a stray OS cursor event must not win
	await frames(1)
	for down: bool in [true, false]:
		var b := InputEventMouseButton.new()
		b.position = p
		b.global_position = p
		b.button_index = button
		b.pressed = down
		b.button_mask = MOUSE_BUTTON_MASK_LEFT if down and button == MOUSE_BUTTON_LEFT else 0
		Input.parse_input_event(b)
		await frames(2)


## Clicks a control like a player: moves the mouse onto it and clicks. For a
## Button, verifies the press landed (a covered or off-screen button is a finding).
func click(c: Control, what: String = "") -> bool:
	if c == null or not is_instance_valid(c):
		finding("missing", "nothing to click for '%s'" % what)
		return false
	var vis := get_viewport().get_visible_rect()
	var p := screen_pos(c)
	var vp_p := get_tree().root.get_final_transform().affine_inverse() * p
	if not vis.has_point(vp_p):
		finding("offscreen", "'%s' is outside the screen at %s" % [what, vp_p])
	var got := [false]
	var cb := func() -> void: got[0] = true
	var btn := c as BaseButton
	if btn:
		if btn.disabled:
			finding("disabled", "'%s' is disabled" % what)
			return false
		btn.pressed.connect(cb, CONNECT_ONE_SHOT)
	await click_at(p)
	await frames(2)
	if btn:
		if not got[0]:
			if is_instance_valid(btn) and btn.pressed.is_connected(cb):
				btn.pressed.disconnect(cb)
			var hov := get_viewport().gui_get_hovered_control()
			finding("click_missed", "click on '%s' did not press it (hovered: %s)" % [what, hov.get_class() + ":" + str(hov.name) if hov else "none"])
			return false
	log_ev("click", {"what": what})
	return true


## Visible buttons whose own text or child label text matches q: an exact
## match beats a prefix, a prefix beats a substring; enabled beats disabled.
func find_button(q: String, root: Node = null) -> Control:
	var ql := q.to_lower()
	var best: Control = null
	var best_score := -1
	for n: Node in (root if root else get_tree().root).find_children("*", "BaseButton", true, false):
		var c := n as BaseButton
		if not c.is_visible_in_tree():
			continue
		var texts: Array = [(c as Button).text.to_lower().strip_edges() if c is Button else ""]
		for l: Node in c.find_children("*", "Label", true, false):
			texts.append((l as Label).text.to_lower().strip_edges())
		var score := -1
		for t: String in texts:
			if t.is_empty():
				continue
			if t == ql:
				score = maxi(score, 3)
			elif t.begins_with(ql):
				score = maxi(score, 2)
			elif t.contains(ql):
				score = maxi(score, 1)
		if score < 0:
			continue
		score = score * 2 + (0 if c.disabled else 1)
		if score > best_score:
			best_score = score
			best = c
	return best


func _child_label_has(c: Node, ql: String) -> bool:
	for l: Node in c.find_children("*", "Label", true, false):
		if (l as Label).text.to_lower().contains(ql):
			return true
	return false


func _prompt_text() -> String:
	var hud := _hud()
	if hud and hud.prompt and hud.prompt.is_visible_in_tree():
		return hud.prompt.text
	return ""


func _objective_text() -> String:
	var hud := _hud()
	if hud and hud.objective_title:
		return hud.objective_title.text
	return ""


func _hud() -> GameHud:
	var sc := scene()
	if sc == null:
		return null
	var h: Variant = sc.get("hud")
	return h as GameHud if h is GameHud else null


func _captain() -> Captain:
	var sc := scene()
	if sc == null:
		return null
	var c: Variant = sc.get("captain")
	return c as Captain if c is Captain else null


func _process(_d: float) -> void:
	# Keep the desktop's real cursor free (the game captures it for mouse look);
	# the driver looks around with the stick actions instead.
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


# ------------------------------------------------------------------ walking

## Walks the captain to a world point with stick input, turning the camera
## after the heading like a player. Returns true when within `arrive` metres.
func walk_to(target: Vector3, arrive: float = 1.0, timeout: float = 40.0, run: bool = true) -> bool:
	var cap := _captain()
	if cap == null:
		return false
	var end := Time.get_ticks_msec() + int(timeout * 1000.0 / speed)
	var last_p := cap.global_position
	var still := 0.0
	var dodge := 0.0
	var dodge_dir := 1.0
	if run:
		Input.action_press("sprint")
	while Time.get_ticks_msec() < end:
		await get_tree().physics_frame
		if not is_instance_valid(cap):
			return false
		var to := target - cap.global_position
		to.y = 0.0
		if to.length() < arrive:
			release_all()
			await secs(0.3)
			return true
		if Time.get_ticks_msec() > end - 50:
			log_ev("walk_timeout", {"pos": _v(cap.global_position), "target": _v(target)})
		if not cap.input_enabled:
			steer(Vector2.ZERO)
			continue
		var want_yaw := atan2(-to.x, -to.z)
		var cam_yaw := cap.camera_rig.yaw
		var err := angle_difference(cam_yaw, want_yaw)
		look(clampf(-err * 2.0, -1.0, 1.0) if absf(err) > 0.05 else 0.0)
		var local := Basis(Vector3.UP, cam_yaw).inverse() * to.normalized()
		var mv := Vector2(local.x, local.z)
		if to.length() < 3.0:
			mv *= clampf(to.length() / 3.0, 0.45, 1.0)
			Input.action_release("sprint")
		var dt := get_physics_process_delta_time()
		if dodge > 0.0:
			dodge -= dt
			mv = Vector2(mv.y, -mv.x) * dodge_dir * 0.9 + mv * 0.3
		steer(mv)
		var moved := cap.global_position.distance_to(last_p)
		last_p = cap.global_position
		still = still + dt if moved < 0.02 * speed else 0.0
		if still > 0.6 and dodge <= 0.0:
			dodge = 0.7
			dodge_dir = -dodge_dir if randf() < 0.5 else dodge_dir
			still = 0.0
			log_ev("stuck_dodge", {"pos": _v(cap.global_position)})
	release_all()
	return false


## Walks along an A* path over a physics-probed grid of the current scene
## (ship layout or surface terrain), smoothing corners by line of sight.
func walk_path(target: Vector3, arrive: float = 1.0, timeout: float = 60.0, run: bool = true) -> bool:
	var cap := _captain()
	if cap == null:
		return false
	var g := _grid()
	if g == null:
		return await walk_to(target, arrive, timeout, run)
	var a := _cell_of(g, cap.global_position)
	var b := _nearest_open(g, _cell_of(g, target))
	var ids := g.get_id_path(_nearest_open(g, a), b)
	if ids.is_empty():
		finding("nav", "no path from %s to %s" % [_v(cap.global_position), _v(target)])
		return await walk_to(target, arrive, timeout, run)
	var pts: Array = []
	for id: Vector2i in ids:
		pts.append(_cell_world(g, id))
	var end := Time.get_ticks_msec() + int(timeout * 1000.0 / speed)
	var i := 0
	while i < pts.size():
		# Farthest point still in straight sight (no solid cell on the way).
		var j := i
		while j + 1 < pts.size() and _clear(g, cap.global_position, pts[j + 1]):
			j += 1
		var left := (end - Time.get_ticks_msec()) * speed / 1000.0
		if left <= 0.0:
			break
		if not await walk_to(pts[j], 1.1, minf(left, 20.0), run):
			finding("stuck", "walk stalled near %s heading to %s" % [_v(cap.global_position), _v(pts[j])])
			return false
		i = j + 1
	return await walk_to(target, arrive, 15.0, false)


var _grid_cache: AStarGrid2D
var _grid_scene: Node
var _grid_origin := Vector3.ZERO
var _grid_heights: Callable


func _grid() -> AStarGrid2D:
	var sc := scene()
	if _grid_scene == sc and _grid_cache:
		return _grid_cache
	_grid_scene = sc
	_grid_cache = null
	var step := 0.75
	var rect := Rect2()
	var floor_y: Callable
	var exclude: Array[RID] = []
	var b: Variant = sc.get("builder")
	var terrain: Variant = sc.get("terrain")
	if b is ShipBuilder:
		var sb := b as ShipBuilder
		var w := 0
		for r: Variant in sb.rows:
			w = maxi(w, str(r).length())
		rect = Rect2(sb.origin.x, sb.origin.z, w * sb.cell, sb.rows.size() * sb.cell)
		floor_y = func(_x: float, _z: float) -> float: return sb.origin.y
	elif terrain is TerrainBuilder:
		var tb := terrain as TerrainBuilder
		step = 1.5
		var half := tb.size_m * 0.45
		rect = Rect2(-half, -half, half * 2.0, half * 2.0)
		floor_y = func(x: float, z: float) -> float: return tb.height_at(x, z)
		for body: Node in tb.find_children("*", "StaticBody3D", true, false):
			exclude.append((body as CollisionObject3D).get_rid())
	else:
		return null
	var g := AStarGrid2D.new()
	g.region = Rect2i(0, 0, int(rect.size.x / step), int(rect.size.y / step))
	g.cell_size = Vector2(step, step)
	g.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	g.update()
	_grid_origin = Vector3(rect.position.x, 0, rect.position.y)
	_grid_heights = floor_y
	var space := (sc as Node3D).get_world_3d().direct_space_state
	var q := PhysicsShapeQueryParameters3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.42
	cap.height = 1.1
	q.shape = cap
	q.collision_mask = 1 | 16
	q.exclude = exclude
	var solid := 0
	for x: int in g.region.size.x:
		for z: int in g.region.size.y:
			var wx := rect.position.x + (x + 0.5) * step
			var wz := rect.position.y + (z + 0.5) * step
			var y := float(floor_y.call(wx, wz))
			q.transform = Transform3D(Basis.IDENTITY, Vector3(wx, y + 1.25, wz))
			if not space.intersect_shape(q, 1).is_empty():
				g.set_point_solid(Vector2i(x, z), true)
				solid += 1
	log_ev("nav_grid", {"cells": g.region.size.x * g.region.size.y, "solid": solid, "step": step})
	_grid_cache = g
	return g


func _cell_of(g: AStarGrid2D, p: Vector3) -> Vector2i:
	var l := p - _grid_origin
	return Vector2i(clampi(int(l.x / g.cell_size.x), 0, g.region.size.x - 1), clampi(int(l.z / g.cell_size.y), 0, g.region.size.y - 1))


func _cell_world(g: AStarGrid2D, c: Vector2i) -> Vector3:
	var x := _grid_origin.x + (c.x + 0.5) * g.cell_size.x
	var z := _grid_origin.z + (c.y + 0.5) * g.cell_size.y
	return Vector3(x, float(_grid_heights.call(x, z)), z)


func _nearest_open(g: AStarGrid2D, c: Vector2i) -> Vector2i:
	if not g.is_point_solid(c):
		return c
	for r: int in range(1, 8):
		for dx: int in range(-r, r + 1):
			for dz: int in range(-r, r + 1):
				var n := c + Vector2i(dx, dz)
				if g.is_in_boundsv(n) and not g.is_point_solid(n):
					return n
	return c


func _clear(g: AStarGrid2D, a: Vector3, b: Vector3) -> bool:
	var d := Vector2(b.x - a.x, b.z - a.z)
	var n := int(d.length() / (g.cell_size.x * 0.5)) + 1
	for k: int in n + 1:
		var p := a.lerp(b, float(k) / n)
		var c := _cell_of(g, p)
		if g.is_point_solid(c):
			return false
	return true


func walk_ship(target: Vector3, arrive: float = 1.0, timeout: float = 60.0) -> bool:
	return await walk_path(target, arrive, timeout)


func _v(p: Vector3) -> String:
	return "(%.1f, %.1f, %.1f)" % [p.x, p.y, p.z]


## Faces an interactable and presses E once the prompt names it.
func interact(it: Interactable, what: String) -> bool:
	var cap := _captain()
	var ok := await wait_until(func() -> bool: return cap.current_target == it, 2.0)
	if not ok:
		# Nudge toward it like a player who sees no prompt yet.
		for i: int in 6:
			var to := it.global_position - cap.global_position
			var local := Basis(Vector3.UP, cap.camera_rig.yaw).inverse() * Vector3(to.x, 0, to.z).normalized()
			steer(Vector2(local.x, local.z) * 0.5)
			await secs(0.15)
			steer(Vector2.ZERO)
			if cap.current_target == it:
				ok = true
				break
	if not ok:
		finding("no_prompt", "no interact prompt for %s at distance %.1f m" % [what, cap.global_position.distance_to(it.global_position)])
		return false
	log_ev("prompt", {"text": _prompt_text()})
	await key(KEY_E)
	return true


# ------------------------------------------------------------------ stages

func _run() -> void:
	await frames(5)
	log_ev("start", {"from": from, "speed": speed, "settings": {"reduced_motion": SettingsService.get_value("reduced_motion"),
		"realtime_descent": SettingsService.get_value("realtime_descent")}})
	get_tree().node_added.connect(_watch_node)
	GameSession.command_failed.connect(func(r: CommandResult) -> void:
		log_ev("command_failed", {"code": r.code, "message": r.message}))
	GameSession.objectives_completed.connect(func(ids: Array) -> void: log_ev("objectives_completed", {"ids": ids}))
	AppFlow.scene_changed.connect(func(k: String) -> void: log_ev("scene", {"key": k}))
	var stages := STAGES.slice(STAGES.find(from) if from in STAGES else 0)
	if from == "orbit":
		DebugFixtures.prepare("orbit:" + dest)
		GameSession.state.mark_applied("story:intro_wakeup")  # a fixture, not a new campaign: no wake-up
		AppFlow.goto("ship", {"spawn": "orbit_terminal"})
	elif from == "colony":
		DebugFixtures.prepare("landed:" + dest)
		AppFlow.goto("colony", {"landing": true})
		stages = ["colony"]
	else:
		AppFlow.goto("menu")
	for s: String in stages:
		var ok: bool = await call("stage_" + s)
		release_all()
		if not ok:
			log_ev("abort", {"at": s})
			break
		if s == until:
			break
	_write_report()
	log_ev("done", {"findings": findings.size(), "total_s": snappedf(now_s(), 0.1)})
	await secs(0.5)
	get_tree().quit(0)


func _watch_node(n: Node) -> void:
	# Panels that open/close during cinematics and stray error dialogs show up here.
	if n is AcceptDialog:
		finding("dialog", "an AcceptDialog appeared: %s" % (n as AcceptDialog).dialog_text)


func stage_menu() -> bool:
	begin("menu")
	if not await wait_scene("menu", 40.0):
		finding("blocker", "main menu never appeared")
		end_stage(false)
		return false
	await secs(1.2)
	await shot("menu")
	var nb := find_button("New campaign")
	var ok := await click(nb, "New campaign")
	end_stage(ok)
	return ok


func stage_wakeup() -> bool:
	begin("wakeup")
	if not await wait_scene("ship", 30.0):
		finding("blocker", "ship scene did not load after New campaign")
		end_stage(false)
		return false
	var sc := scene()
	var w: Node = sc.get_node_or_null("Wakeup")
	if w == null:
		finding("story", "no wake-up cinematic on a new campaign (D-060)")
	var t_start := now_s()
	await secs(1.0)
	await shot("wakeup_dark")
	await secs(3.6)
	await shot("wakeup_hatch")
	if skip_wakeup and w != null:
		await key(KEY_ENTER)
	var wr: WeakRef = weakref(w)
	await wait_until(func() -> bool: return wr.get_ref() == null or (wr.get_ref() as Node).is_queued_for_deletion(), 40.0)
	var dur := now_s() - t_start
	await frames(5)
	var cap := _captain()
	log_ev("wakeup_done", {"seconds": snappedf(dur, 0.1), "input": cap.input_enabled, "cam_active": cap.camera_rig.active})
	if not cap.input_enabled:
		finding("control", "captain input disabled after the wake-up")
	await shot("wakeup_handover")
	end_stage(true, "cinematic %.1f s" % dur)
	return true


func stage_power() -> bool:
	begin("power")
	var sc := scene()
	var it: Interactable = sc.interactables["power_coupling"]
	var o := _objective_text()
	log_ev("objective", {"text": o})
	if not await walk_ship(it.global_position + Vector3(1.4, 0, 0), 0.6):
		end_stage(false)
		return false
	await shot("coupling_prompt")
	if not await interact(it, "power coupling"):
		end_stage(false)
		return false
	await secs(0.6)
	await shot("power_wave_early")
	await secs(1.8)
	await shot("power_wave")
	var powered: bool = GameSession.state.ark.systems.get("power") != "offline"
	if not powered:
		finding("blocker", "power did not come back after using the coupling")
	await secs(1.5)
	log_ev("objective", {"text": _objective_text()})
	end_stage(powered)
	return powered


func stage_embryo() -> bool:
	begin("embryo")
	var sc := scene()
	var it: Interactable = sc.interactables["embryo_bank"]
	if not await walk_ship(it.global_position + Vector3(0, 0, 2.3), 0.6, 90.0):
		end_stage(false)
		return false
	if not await interact(it, "embryo bank"):
		end_stage(false)
		return false
	await secs(1.0)
	await shot("embryo_panel")
	var cap := _captain()
	await key(KEY_ESCAPE)
	await secs(0.6)
	if (sc.get("embryo_panel") as CanvasLayer).visible:
		finding("control", "Esc did not close the embryo bank panel")
	var paused := get_tree().paused
	if paused:
		finding("control", "Esc on the embryo panel also opened the pause menu")
		await key(KEY_ESCAPE)
	if not cap.input_enabled:
		finding("control", "captain input not restored after closing the embryo panel")
	log_ev("objective", {"text": _objective_text()})
	end_stage(true)
	return true


func stage_starmap() -> bool:
	begin("starmap")
	var sc := scene()
	var it: Interactable = sc.interactables["starmap"]
	var b: ShipBuilder = sc.builder
	if not await walk_ship(b.cell_to_world(6.55, 2.4), 0.6, 90.0):
		end_stage(false)
		return false
	if not await interact(it, "star map"):
		end_stage(false)
		return false
	await secs(1.6)
	await shot("starmap")
	var sm: StarMapPanel = sc.starmap
	# Compare tab like a player: click its tab title.
	var tb := sm.tabs.get_tab_bar()
	var tab_rect := tb.get_tab_rect(1)
	await click_at(get_tree().root.get_final_transform() * (tb.get_global_transform_with_canvas() * tab_rect.get_center()))
	await secs(1.0)
	if sm.tabs.current_tab != 1:
		finding("click_missed", "clicking the Comparison tab did not switch tabs")
		sm.tabs.current_tab = 1
	await shot("compare")
	log_ev("objective", {"text": _objective_text()})
	await click_at(get_tree().root.get_final_transform() * (tb.get_global_transform_with_canvas() * tb.get_tab_rect(0).get_center()))
	await secs(0.6)
	# Pick the destination on the map.
	var mv: StarMapView = sm.map_view
	var p := get_tree().root.get_final_transform() * (mv.get_global_transform_with_canvas() * mv._pos(dest))
	await click_at(p)
	await secs(0.8)
	if mv.selected != dest:
		finding("click_missed", "clicking %s on the star map did not select it (selected '%s')" % [dest, mv.selected])
		mv.select(dest)
		await secs(0.5)
	await shot("starmap_" + dest)
	if probe:
		var pb := find_button("Send remote probe", sm)
		await click(pb, "Send remote probe")
		await secs(1.0)
		await shot("probe")
	log_ev("objective", {"text": _objective_text()})
	var tv := find_button("Travel here", sm)
	if tv == null:
		tv = find_button("Confirm risky voyage", sm)
	if not await click(tv, "Travel here"):
		end_stage(false)
		return false
	await secs(0.5)
	var conf := find_button("Confirm risky voyage", sm)
	if conf and sm.visible:
		log_ev("risky_confirm")
		await shot("risky_confirm")
		await click(conf, "Confirm risky voyage")
	end_stage(true)
	return true


func stage_flight() -> bool:
	begin("flight")
	if not await wait_scene("flight", 20.0):
		finding("blocker", "flight scene did not open after travel")
		end_stage(false)
		return false
	var fs := scene()
	await secs(1.0)
	await shot("flight_start")
	# Manual: throttle up and weave for a few seconds.
	steer(Vector2(0.0, -1.0))
	await secs(2.0)
	steer(Vector2(0.8, -1.0))
	await secs(1.2)
	steer(Vector2(-0.8, 0.0))
	await secs(1.2)
	release_all()
	var z0: float = -(fs.ship as Node3D).position.z
	log_ev("manual_progress", {"m": snappedf(z0, 1.0), "speed": fs.speed})
	if z0 < 30.0:
		finding("control", "manual flight barely moved (%d m in 4.4 s)" % int(z0))
	await key(KEY_V)
	await secs(1.0)
	if not fs.cockpit_view:
		finding("control", "V did not switch to the cockpit view")
	await shot("flight_cockpit")
	await key(KEY_V)
	await secs(0.5)
	await key(KEY_F)
	await secs(0.5)
	if not fs.autopilot:
		finding("control", "F did not engage the autopilot")
	await shot("flight_autopilot")
	var t := now_s()
	var fr: WeakRef = weakref(fs)
	var arrived := await wait_until(func() -> bool: return fr.get_ref() == null or bool((fr.get_ref() as Node).get("_done")), 120.0)
	await shot("flight_arrive")
	log_ev("flight", {"autopilot_s": snappedf(now_s() - t, 0.1), "hits": fs.hits if is_instance_valid(fs) else -1})
	end_stage(arrived)
	return arrived


func stage_orbit() -> bool:
	begin("orbit")
	if not await wait_scene("ship", 30.0):
		finding("blocker", "did not return to the ship after the approach")
		end_stage(false)
		return false
	await secs(1.5)
	await shot("orbit_ship")
	var sc := scene()
	log_ev("objective", {"text": _objective_text()})
	var it: Interactable = sc.interactables["orbit_terminal"]
	var cap := _captain()
	var d := cap.global_position.distance_to(it.global_position)
	log_ev("spawn_dist", {"m": snappedf(d, 0.1), "target": cap.current_target == it})
	if cap.current_target != it:
		await walk_ship(it.global_position + Vector3(0, 0, 1.6), 0.6)
	if not await interact(it, "orbit terminal"):
		end_stage(false)
		return false
	await secs(1.6)
	await shot("orbit_panel")
	var op: OrbitPanel = sc.orbit
	var scan := find_button("Orbital scan", op)
	if scan and not (scan as BaseButton).disabled:
		await click(scan, "Orbital scan")
		await secs(1.0)
	await shot("orbit_scanned")
	var chk := _find_check(op)
	if chk:
		await click(chk, "drone reserve switch")
		await secs(0.3)
		if not chk.button_pressed:
			finding("click_missed", "drone reserve switch did not toggle")
			chk.button_pressed = true
	var ex := find_button("Expedition", op)
	if not await click(ex, "Expedition"):
		end_stage(false)
		return false
	await secs(1.5)
	await shot("after_expedition_click")
	end_stage(true)
	return true


func _find_check(root: Node) -> CheckButton:
	for n: Node in root.find_children("*", "CheckButton", true, false):
		if (n as Control).is_visible_in_tree():
			return n
	return null


func stage_descent() -> bool:
	begin("descent")
	if not await wait_scene("surface", 30.0):
		finding("blocker", "surface scene did not load after Expedition")
		end_stage(false)
		return false
	var sc := scene()
	var d: PlanetDescent = sc.get_node_or_null("Descent")
	if d == null:
		finding("info", "no real-time descent (reduced motion or setting off)")
		end_stage(true, "no descent")
		return true
	var suit0: float = GameSession.state.expedition.suit_energy
	var t := now_s()
	await secs(1.5)
	await shot("descent_orbit")
	# Manual for a while: F, steer, then hand back to the autopilot.
	await key(KEY_F)
	steer(Vector2(0.5, -1.0))
	await secs(3.0)
	release_all()
	if d.autopilot:
		finding("control", "F did not switch the descent to manual")
	await shot("descent_manual")
	await key(KEY_F)
	await secs(4.0)
	await shot("descent_entry")
	# Pause mid-descent: the menu must show (the HUD is hidden during the flight) and hold the descent.
	var alt0 := float(d.get("_alt"))
	await key(KEY_ESCAPE)
	await secs(1.0)
	var hud := _hud()
	log_ev("pause_in_descent", {"paused": get_tree().paused, "menu_visible": hud.pause_menu.visible})
	if get_tree().paused != hud.pause_menu.visible:
		finding("control", "Esc during the descent: paused=%s but menu visible=%s" % [get_tree().paused, hud.pause_menu.visible])
	await shot("descent_paused")
	if absf(float(d.get("_alt")) - alt0) > 30.0 and get_tree().paused:
		finding("timer", "the descent kept flying while paused")
	if get_tree().paused:
		await key(KEY_ESCAPE)
		await secs(0.5)
	var dr: WeakRef = weakref(d)
	var done := await wait_until(func() -> bool: return dr.get_ref() == null or float((dr.get_ref() as Node).get("_alt")) < 900.0, 90.0)
	await shot("descent_low")
	done = await wait_until(func() -> bool: return dr.get_ref() == null, 90.0)
	var dur := now_s() - t
	await secs(0.8)
	await shot("touchdown")
	var suit1: float = GameSession.state.expedition.suit_energy
	if suit1 < suit0 - 0.5:
		finding("timer", "suit energy drained during the descent (%.1f -> %.1f)" % [suit0, suit1])
	log_ev("descent", {"seconds": snappedf(dur, 0.1), "autopilot_completed": done})
	if dur > 75.0:
		finding("pacing", "descent took %.0f s on autopilot" % dur)
	end_stage(done, "%.1f s" % dur)
	return done


func stage_surface() -> bool:
	begin("surface")
	var sc := scene()
	var cap := _captain()
	await wait_until(func() -> bool: return cap.input_enabled, 10.0)
	await secs(1.0)
	await shot("surface_start")
	log_ev("objective", {"text": _objective_text(), "status": (sc._status as Label).text})
	# Scanner
	await key(KEY_C)
	await secs(1.6)
	await shot("scanner")
	var markers: Dictionary = sc._markers
	var survey: Dictionary = sc.survey
	# Follow the safe route's chevrons to the main sample.
	var safe: Array = []
	for r: Dictionary in DictUtil.get_arr(survey, "routes"):
		if str(r.get("id")) == "safe":
			safe = DictUtil.get_arr(r, "waypoints")
	for w: Variant in safe:
		var wp := Vector2(float(w[0]), float(w[1]))
		if wp.length() < 3.0:
			continue
		var p := Vector3(wp.x, 0, wp.y)
		if not await walk_to(p, 3.0, 40.0):
			finding("stuck", "could not follow the safe route at %s" % _v(p))
			break
	if markers.has("main_sample"):
		var ms: Interactable = markers["main_sample"]
		await walk_to(ms.global_position, 1.4, 30.0, false)
		await _hold_sample(ms, "main sample")
	# Drone reserve on the way to the relay.
	var ex: ExpeditionState = GameSession.state.expedition
	if ex.drone_refill_available and not ex.drone_refill_used:
		var before := ex.suit_energy
		await key(KEY_G)
		await secs(0.4)
		if ex.drone_refill_used:
			if before > 85.0:
				finding("waste", "the drone reserve fired at once on a %d %% suit (no warning)" % int(before))
		else:
			log_ev("drone_warned", {"suit": snappedf(before, 0.1)})
			await shot("drone_warning")
			await key(KEY_G)
		await secs(1.0)
		await shot("droppod_incoming")
		await secs(2.5)
		await shot("droppod_landed")
		await wait_until(func() -> bool: return not (sc._pod and sc._pod.is_busy()), 25.0)
		await secs(0.5)
		await shot("droppod_done")
		log_ev("drone", {"before": snappedf(before, 0.1), "after": snappedf(GameSession.state.expedition.suit_energy, 0.1)})
		if not cap.input_enabled:
			finding("control", "captain input off after the drop pod")
	if markers.has("relay"):
		var rl: Interactable = markers["relay"]
		if await walk_to(rl.global_position, 1.6, 60.0):
			await shot("relay_prompt")
			await interact(rl, "relay")
			await secs(1.0)
			await shot("relay_placed")
	# Risk sample through the hazard zone (optional, tests the hazard drain + warnings).
	if markers.has("risk_sample"):
		var rs: Interactable = markers["risk_sample"]
		if await walk_to(rs.global_position, 1.4, 60.0):
			await shot("hazard_zone")
			await _hold_sample(rs, "risk sample")
	var ln: Interactable = markers["lander"]
	await walk_to(ln.global_position + (cap.global_position - ln.global_position).normalized() * 3.2, 1.0, 60.0)
	await shot("lander_prompt")
	log_ev("expedition", {"samples": GameSession.state.expedition.samples, "relay": GameSession.state.expedition.relay_placed,
		"suit": snappedf(GameSession.state.expedition.suit_energy, 0.1)})
	var ok := await interact(ln, "lander")
	end_stage(ok)
	return ok


func _hold_sample(it: Interactable, what: String) -> void:
	var cap := _captain()
	if not await wait_until(func() -> bool: return cap.current_target == it, 3.0):
		finding("no_prompt", "no prompt at %s (%.1f m)" % [what, cap.global_position.distance_to(it.global_position)])
		return
	log_ev("prompt", {"text": _prompt_text()})
	key_down(KEY_E, true)
	await secs(3.0)
	await shot("sampling_" + what.replace(" ", "_"))
	await wait_until(func() -> bool: return it.locked, 12.0)
	key_down(KEY_E, false)
	await secs(0.5)
	if not it.locked:
		finding("control", "holding E did not finish the %s" % what)
	await shot("sample_done_" + what.replace(" ", "_"))


func stage_ascent() -> bool:
	begin("ascent")
	var t := now_s()
	await secs(2.0)
	await shot("ascent")
	await secs(4.0)
	await shot("ascent_climb")
	await key(KEY_ENTER)  # skip the rest of the climb like an impatient player
	var ok := await wait_scene("ship", 60.0)
	log_ev("ascent", {"seconds": snappedf(now_s() - t, 0.1)})
	await secs(1.5)
	await shot("back_on_ship")
	log_ev("objective", {"text": _objective_text()})
	end_stage(ok)
	return ok


func stage_savecycle() -> bool:
	begin("savecycle")
	var loc := GameSession.state.campaign.location_id
	var day := GameSession.state.campaign.elapsed_days
	await key(KEY_ESCAPE)
	await secs(0.8)
	if not get_tree().paused:
		finding("control", "Esc did not open the pause menu in the ship")
	await shot("pause")
	await click(find_button("Save game"), "Save game")
	await secs(0.6)
	await shot("save_slots")
	var hud := _hud()
	var slot_card := _first_card(hud.pause_menu)
	await click(slot_card, "save slot 1")
	await secs(0.8)
	await shot("saved")
	var mm := find_button("Main menu")
	await click(mm, "Main menu")
	if not await wait_scene("menu", 20.0):
		finding("blocker", "Main menu did not open from pause")
		end_stage(false)
		return false
	await secs(1.2)
	await shot("menu_continue")
	var cont := find_button("Continue")
	if not await click(cont, "Continue"):
		end_stage(false)
		return false
	var ok := await wait_scene("ship", 20.0)
	await secs(1.2)
	await shot("continued")
	if GameSession.state.campaign.location_id != loc or GameSession.state.campaign.elapsed_days != day:
		finding("save", "continue restored a different place/day (%s/%d vs %s/%d)" % [GameSession.state.campaign.location_id, GameSession.state.campaign.elapsed_days, loc, day])
	var cap := _captain()
	if cap and not cap.input_enabled:
		finding("control", "captain input off after Continue")
	end_stage(ok)
	return ok


func _first_card(root: Node) -> Control:
	for n: Node in root.find_children("*", "HoloCard", true, false):
		if (n as Control).is_visible_in_tree():
			return n
	return null


func stage_landing() -> bool:
	begin("landing")
	var sc := scene()
	var it: Interactable = sc.interactables["orbit_terminal"]
	if not await walk_ship(it.global_position + Vector3(0, 0, 1.6), 0.6):
		end_stage(false)
		return false
	if not await interact(it, "orbit terminal"):
		end_stage(false)
		return false
	await secs(1.4)
	var op: OrbitPanel = sc.orbit
	var prep := find_button("Prepare landing", op)
	await click(prep, "Prepare landing")
	await secs(1.4)
	await shot("landing_preview")
	var commit := find_button("Confirm landing", op)
	if not await click(commit, "Confirm landing (final)"):
		end_stage(false)
		return false
	end_stage(true)
	return true


func stage_colony() -> bool:
	begin("colony")
	if not await wait_scene("colony", 40.0):
		finding("blocker", "colony scene did not load after the landing")
		end_stage(false)
		return false
	var sc := scene()
	var d: PlanetDescent = sc.get_node_or_null("Descent")
	var t := now_s()
	var day0 := GameSession.state.campaign.colony_day
	if d:
		await secs(2.0)
		await shot("ark_descent")
		await secs(6.0)
		await shot("ark_descent_entry")
		var adr: WeakRef = weakref(d)
		await wait_until(func() -> bool: return adr.get_ref() == null or float((adr.get_ref() as Node).get("_alt")) < 600.0, 120.0)
		await shot("ark_descent_low")
		await wait_until(func() -> bool: return adr.get_ref() == null, 120.0)
		log_ev("ark_descent", {"seconds": snappedf(now_s() - t, 0.1)})
		if GameSession.state.campaign.colony_day != day0:
			finding("timer", "colony days passed during the Ark descent (%d -> %d)" % [day0, GameSession.state.campaign.colony_day])
	await secs(1.5)
	await shot("colony_start")
	log_ev("colony_open", {"objective": _objective_text(), "hint": _hud().objective_hint.text, "speed": GameSession.colony_speed})
	# Build power, water, habitat from the bar.
	for def_id: String in ["solar_array", "water_plant", "habitat"]:
		await _build(def_id)
	await shot("colony_built")
	log_ev("objective", {"text": _objective_text()})
	# Pick a building and change your mind with Esc (the ghost tip promises it).
	for b: Node in (sc._build_bar as Node).get_children():
		if b.get_meta("def_id", "") == "battery":
			await click(b as Control, "build battery")
	await secs(0.3)
	var had_ghost := not str(sc.build_def).is_empty()
	await key(KEY_ESCAPE)
	await secs(0.3)
	log_ev("esc_cancel_build", {"had_ghost": had_ghost, "cancelled": str(sc.build_def).is_empty(), "paused": get_tree().paused})
	if had_ghost and (get_tree().paused or not str(sc.build_def).is_empty()):
		finding("control", "Esc with a build ghost: paused=%s, ghost still active=%s" % [get_tree().paused, not str(sc.build_def).is_empty()])
		if get_tree().paused:
			await key(KEY_ESCAPE)
	if get_tree().paused:
		await key(KEY_ESCAPE)
	# Time: 3x until the first supply goals are met, then the care center.
	await key(KEY_3)
	await secs(0.5)
	if GameSession.colony_speed != 3:
		finding("control", "key 3 did not set 3x speed")
	var t3 := now_s()
	await wait_until(func() -> bool: return GameSession.sim.objectives.is_done(GameSession.state, "obj_build_habitat"), 60.0)
	log_ev("first_builds_active", {"after_s": snappedf(now_s() - t3, 0.1), "day": GameSession.state.campaign.colony_day, "objective": _objective_text()})
	await shot("colony_running")
	# The care center costs more material than is left after the first three: wait for the drones.
	var tm := now_s()
	var cost := int(DictUtil.get_dict(GameSession.content.building("care_center"), "cost").get("alloy", 0))
	await wait_until(func() -> bool: return float(GameSession.state.colony.inventory.get("alloy", 0.0)) >= cost, 240.0)
	log_ev("material_wait", {"seconds": snappedf(now_s() - tm, 0.1), "day": GameSession.state.campaign.colony_day, "cost": cost})
	await _build("care_center")
	await wait_until(func() -> bool: return GameSession.state.colony.count_active("care_center") > 0, 90.0)
	# Start the first cohort from the care center's card (the objective hint's path).
	var cc_id := -1
	for b: Dictionary in GameSession.state.colony.buildings:
		if str(b["def_id"]) == "care_center":
			cc_id = int(b["id"])
	if cc_id >= 0:
		await _click_building(cc_id, "care center")
		await secs(0.6)
		await shot("care_center_card")
		var ib := find_button("Start incubation")
		var tw := now_s()
		while ib and (ib as BaseButton).disabled and now_s() - tw < 120.0:
			await secs(2.0)
			await _click_building(cc_id, "care center")
			ib = find_button("Start incubation")
		log_ev("incubation_ready", {"wait_s": snappedf(now_s() - tw, 0.1), "day": GameSession.state.campaign.colony_day,
			"blockers": GameSession.sim.population.incubation_blockers(GameSession.state, int(GameSession.content.bal("incubation.cohort_size", 10)))})
		if ib and not (ib as BaseButton).disabled:
			await click(ib, "Start incubation")
			await secs(0.6)
			await shot("incubation_started")
	# First event / decision at 3x.
	if GameSession.colony_speed != 3:
		await key(KEY_3)
	var t2 := now_s()
	await wait_until(func() -> bool: return (sc.event_dialog as CanvasLayer).visible or (sc.decision as CanvasLayer).visible, 420.0)
	log_ev("first_event", {"after_s": snappedf(now_s() - t2, 0.1), "day": GameSession.state.campaign.colony_day,
		"event": (sc.event_dialog as CanvasLayer).visible, "decision": (sc.decision as CanvasLayer).visible,
		"population": GameSession.state.population.alive_count()})
	for dlg: CanvasLayer in [sc.event_dialog, sc.decision]:
		if dlg.visible:
			await secs(1.2)
			await shot("event")
			await click(_first_option(dlg), "event option")
			await secs(1.0)
			if dlg.visible:
				finding("control", "the event stayed open after choosing an option")
			await shot("event_resolved")
	await key(KEY_SPACE)
	await secs(0.3)
	var ov := find_button("Colony overview")
	await click(ov, "Colony overview")
	await secs(1.4)
	await shot("overview")
	await key(KEY_ESCAPE)
	await secs(0.6)
	if (sc.overview as CanvasLayer).visible:
		finding("control", "Esc did not close the colony overview")
	if get_tree().paused:
		finding("control", "Esc on the overview also opened the pause menu")
		await key(KEY_ESCAPE)
	await key(KEY_B)
	await secs(1.5)
	await shot("captain_mode")
	await key(KEY_B)
	await secs(0.8)
	log_ev("colony_state", {"buildings": GameSession.state.colony.buildings.size(), "day": GameSession.state.campaign.colony_day,
		"objective": _objective_text(), "population": GameSession.state.population.alive_count()})
	end_stage(true)
	return true


func _first_option(root: Node) -> Control:
	var card := _first_card(root)
	if card:
		return card
	for n: Node in root.find_children("*", "BaseButton", true, false):
		var b := n as BaseButton
		if b.is_visible_in_tree() and not b.disabled:
			return b
	return null


## Moves the pointer onto a world spot and clicks it.
func click_world(p: Vector3) -> void:
	var cam := get_viewport().get_camera_3d()
	var vp := cam.unproject_position(p)
	var wp := get_tree().root.get_final_transform() * vp
	mouse_move(wp)
	await secs(0.35)
	await click_at(wp)


func _click_building(bid: int, what: String) -> void:
	var b := GameSession.state.colony.building_by_id(bid)
	var sc := scene()
	var p := Vector3(float(b["x"]), float(sc.terrain.height_at(float(b["x"]), float(b["z"]))) + 1.0, float(b["z"]))
	await click_world(p)
	await secs(0.3)
	log_ev("pick", {"what": what, "selected": sc.selected_id})


## Clicks the build button, finds a valid on-screen spot (near the landing zone,
## then the other districts) and clicks the ground there.
func _build(def_id: String) -> void:
	var sc := scene()
	var btn: Control = null
	for b: Node in (sc._build_bar as Node).get_children():
		if b.get_meta("def_id", "") == def_id:
			btn = b
	if not await click(btn, "build " + def_id):
		return
	await secs(0.4)
	var cam: Camera3D = sc.cam_rig.cam
	var gs: GameState = GameSession.state
	var centers: Array = []
	var districts: Dictionary = DictUtil.get_dict(sc.site, "districts")
	for k: String in ["landing", "living", "resource"] + districts.keys():
		var lc: Array = DictUtil.get_arr(districts.get(k, {}), "center")
		if lc.size() == 2:
			centers.append(Vector2(float(lc[0]), float(lc[1])))
	var spot := Vector2.INF
	var vis := get_viewport().get_visible_rect().grow(-150)
	for c: Vector2 in centers:
		for r: int in range(6, 48, 3):
			for i: int in 16:
				var p := (c + Vector2.from_angle(TAU * i / 16.0) * r).round()
				if GameSession.sim.colony.check_placement(gs, def_id, p.x, p.y, 0)["ok"]:
					var w := Vector3(p.x, float(sc.terrain.height_at(p.x, p.y)), p.y)
					if vis.has_point(cam.unproject_position(w)) and not cam.is_position_behind(w):
						spot = p
						break
			if spot != Vector2.INF:
				break
		if spot != Vector2.INF:
			break
	if spot == Vector2.INF:
		# Off screen: pan the camera like a player (WASD) toward the nearest valid spot.
		var best := Vector2.INF
		var rig: Node3D = sc.cam_rig
		var here := Vector2(rig.global_position.x, rig.global_position.z)
		var why: Array = []
		for c: Vector2 in centers:
			for r: int in range(6, 48, 3):
				for i: int in 16:
					var p := (c + Vector2.from_angle(TAU * i / 16.0) * r).round()
					var chk: Dictionary = GameSession.sim.colony.check_placement(gs, def_id, p.x, p.y, 0)
					if chk["ok"]:
						if best == Vector2.INF or p.distance_to(here) < best.distance_to(here):
							best = p
					elif why.size() < 3 and not str(chk["reasons"]) in why:
						why.append(str(chk["reasons"]))
		if best == Vector2.INF:
			finding("build", "no valid spot at all for %s: %s" % [def_id, why])
			await key(KEY_ESCAPE)
			return
		log_ev("pan_to", {"def": def_id, "spot": [best.x, best.y]})
		var tpan := now_s()
		while now_s() - tpan < 6.0:
			var w := Vector3(best.x, float(sc.terrain.height_at(best.x, best.y)), best.y)
			if vis.grow(-60).has_point(cam.unproject_position(w)) and not cam.is_position_behind(w):
				break
			var to := Vector3(best.x - rig.global_position.x, 0, best.y - rig.global_position.z)
			var local := Basis(Vector3.UP, rig.rotation.y).inverse() * to.normalized()
			steer(Vector2(local.x, local.z))
			await get_tree().process_frame
		steer(Vector2.ZERO)
		await secs(0.3)
		spot = best
	var wpos := Vector3(spot.x, float(sc.terrain.height_at(spot.x, spot.y)), spot.y)
	var vp := cam.unproject_position(wpos)
	mouse_move(get_tree().root.get_final_transform() * vp)
	await secs(0.5)
	await shot("ghost_" + def_id)
	var n0 := gs.colony.buildings.size()
	for i: int in 5:
		if sc.ghost_pos == spot:
			break
		mouse_move(get_tree().root.get_final_transform() * vp)
		await frames(2)
	await click_at(get_tree().root.get_final_transform() * vp)
	await secs(0.6)
	if GameSession.state.colony.buildings.size() == n0:
		finding("build", "clicking a valid spot did not place %s (ghost_ok=%s, ghost at %s, wanted %s)" % [def_id, sc.ghost_ok, sc.ghost_pos, spot])
		await key(KEY_ESCAPE)
		if get_tree().paused or not str(sc.build_def).is_empty():
			finding("control", "Esc did not cancel the build ghost (paused=%s)" % get_tree().paused)
			if get_tree().paused:
				await key(KEY_ESCAPE)
	else:
		log_ev("built", {"def": def_id, "at": [spot.x, spot.y]})

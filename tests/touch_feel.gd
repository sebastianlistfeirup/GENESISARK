extends Node
## Touch-feel test (run with the --touch user arg, see tools/check.sh). Drives the
## real TouchControls joystick with screen-touch events and measures the captain:
## jitter is ignored, a half throw walks slowly, a full throw runs, speed never
## jumps between frames, and letting go eases to a stop.
## Writes evidence/touch_feel.json.

var results: Array = []


func _ready() -> void:
	AppFlow.test_mode = true
	await get_tree().process_frame
	await _run()
	var fails := results.filter(func(r: Dictionary) -> bool: return not r["ok"])
	for r: Dictionary in results:
		print("TOUCH %s %s %s" % ["PASS" if r["ok"] else "FAIL", r["name"], r["detail"]])
	print("TOUCH TOTAL %d checks, %d failures" % [results.size(), fails.size()])
	var f := FileAccess.open("res://evidence/touch_feel.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"checks": results, "status": "PASS" if fails.is_empty() else "FAIL"}, "  "))
	f.close()
	get_tree().quit(0 if fails.is_empty() else 1)


func check(name: String, ok: bool, detail: String = "") -> void:
	results.append({"name": name, "ok": ok, "detail": detail})


func _touch(pos: Vector2, pressed: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = 0
	e.position = pos
	e.pressed = pressed
	TouchControls._input(e)


func _drag(pos: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = 0
	e.position = pos
	TouchControls._input(e)


## Holds the stick at `offset` for `n` physics frames; returns [mean speed of the last half, max per-frame speed change].
func _hold(origin: Vector2, offset: Vector2, n: int, captain: Captain) -> Array:
	_drag(origin + offset)
	var speeds: Array = []
	var max_jump := 0.0
	var last := Vector2(captain.velocity.x, captain.velocity.z).length()
	for i: int in n:
		await get_tree().physics_frame
		var s := Vector2(captain.velocity.x, captain.velocity.z).length()
		max_jump = maxf(max_jump, absf(s - last))
		last = s
		speeds.append(s)
	var tail := speeds.slice(n / 2)
	var mean := 0.0
	for s: float in tail:
		mean += s
	return [mean / maxf(tail.size(), 1), max_jump]


func _run() -> void:
	check("touch_enabled", TouchControls.enabled, "start med -- --touch")
	if not TouchControls.enabled:
		return
	DebugFixtures.prepare("power")
	var ship: Node = load("res://scenes/ship/ship.tscn").instantiate()
	add_child(ship)
	AppFlow.current_key = "ship"
	TouchControls._update_visibility()
	for i: int in 10:
		await get_tree().physics_frame
	var captain: Captain = ship.get("captain")
	var hud: Node = ship.get("hud")
	if hud and hud.has_method("close_all"):
		hud.call("close_all")
	captain.input_enabled = true
	# Middle of the ring corridor, facing along it.
	captain.teleport(Vector3(30.0, 0.1, 22.0), PI * 0.5)
	for i: int in 5:
		await get_tree().physics_frame
	var origin := Vector2(230, 590)
	var dt := 1.0 / Engine.physics_ticks_per_second
	_touch(origin, true)
	var jitter := await _hold(origin, Vector2(9, -8), 30, captain)
	check("jitter_ignored", float(jitter[0]) < 0.05, "%.3f m/s" % jitter[0])
	var half := await _hold(origin, Vector2(0, -75), 60, captain)
	var walk := captain.walk_speed
	check("half_throw_walks_slowly", float(half[0]) > 0.4 and float(half[0]) < walk * 0.7, "%.2f m/s (gang %.1f)" % [half[0], walk])
	var full := await _hold(origin, Vector2(0, -150), 90, captain)
	check("full_throw_runs", float(full[0]) > captain.run_speed * 0.9, "%.2f m/s (løb %.1f)" % [full[0], captain.run_speed])
	var limit := captain.deceleration * dt + 0.01
	check("speed_never_jumps", maxf(float(half[1]), float(full[1])) <= limit, "max %.3f m/s pr. frame (grænse %.3f)" % [maxf(float(half[1]), float(full[1])), limit])
	_touch(origin + Vector2(0, -150), false)
	var frames_to_stop := 0
	var stop_jump := 0.0
	var last := Vector2(captain.velocity.x, captain.velocity.z).length()
	while Vector2(captain.velocity.x, captain.velocity.z).length() > 0.05 and frames_to_stop < 240:
		await get_tree().physics_frame
		var s := Vector2(captain.velocity.x, captain.velocity.z).length()
		stop_jump = maxf(stop_jump, absf(s - last))
		last = s
		frames_to_stop += 1
	var t_stop := frames_to_stop * dt
	check("release_eases_to_stop", t_stop > 0.2 and t_stop < 0.9 and stop_jump <= limit, "%.2f s, max %.3f m/s pr. frame" % [t_stop, stop_jump])
	ship.queue_free()

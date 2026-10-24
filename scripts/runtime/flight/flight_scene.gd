extends Node3D
## Approach to the destination after a committed journey (bible p.6: short,
## bounded, assisted). The route's hazard (data/routes: none / field / debris /
## belt) fills the corridor with drifting asteroids; NAV warns about collision
## courses and reports impacts. The domain books the result exactly once
## (GameSession.cmd_resolve_approach): impacts cost hull, severe ones leak
## oxygen, evasive burns and the autopilot cost fuel. Autopilot = NAV flies:
## cautious, fewer impacts, more fuel.
## Controls: W/S speed · A/D sideways · Space/Ctrl up/down · Shift evasive burn · F autopilot.
## V (camera_view) switches between the chase camera and the cockpit (D-044).

const LENGTH := 1100.0      # metres from the start to orbit insertion
const SHIP_R := 6.0         # collision radius of the ark
const LANE := Vector2(90, 45)  # half-width / half-height of the approach corridor
const SEVERE_R := 7.0       # asteroids this big (or hits this fast) are severe
const SEVERE_SPEED := 45.0

var ship: Node3D
var cam: Camera3D
var speed := 26.0
var lateral := Vector2.ZERO  # sideways/vertical velocity (m/s)
var autopilot := false
var autopilot_used := false
var hits := 0
var severe := 0
var burn_s := 0.0
var hud: GameHud
var _info: Label
var _done := false
var _shake := 0.0
var _dest := ""
var _hazard: Dictionary = {"type": "none", "density": 0.0}
var _rocks: Array = []  # [{node, r, vel, hit, warned}]
var _thruster: AudioStreamPlayer
var _warn_t := 0.0
var _cleared := false
var _start_integrity := 100.0
var _start_oxygen := 100.0
var scenery: SpaceScenery  # non-colliding backdrop + hazard rock models (presentation only)
## Cockpit or chase camera; remembered for the session (presentation only).
static var cockpit_view := false
var cockpit: FlightCockpit
var _ark_visual: VisualSlot
var _thr: Node3D


func _ready() -> void:
	var gs: GameState = GameSession.state if GameSession.has_game() else null
	var pa: Dictionary = gs.campaign.pending_approach if gs else {}
	_dest = str(pa.get("destination", AppFlow.params.get("destination", gs.campaign.location_id if gs else "viridia")))
	_hazard = DictUtil.get_dict(pa, "hazard") if not pa.is_empty() else _route_hazard(gs)
	if gs:
		_start_integrity = gs.ark.integrity
		_start_oxygen = gs.ark.oxygen
	var backdrop := SpaceBackdrop.new()
	add_child(backdrop)
	backdrop.set_depth_haze(Color("2a1f4a"), 0.00045)
	# The system's sun ahead and to the left, like the key art: its fiery
	# nebula region and lens streak sit in the frame (sky shader LIGHT0).
	backdrop.set_sun(Vector3(-4.0, -138.0, 0.0), 1.7)
	# The sun is ahead, so the rocks the pilot sees face away from it: a lilac
	# fill from behind the camera and a brighter ambient keep them warm-lit stone
	# instead of black cut-outs (the key art lights its asteroids from the front).
	backdrop.fill.rotation_degrees = Vector3(-28.0, 22.0, 0.0)
	backdrop.fill.light_color = Color("d6a0ff")
	backdrop.fill.light_energy = 1.15
	backdrop.environment.ambient_light_energy = 1.0
	# The cockpit is lit by its own lamps only (FlightCockpit.LAYER).
	backdrop.sun.light_cull_mask &= ~FlightCockpit.LAYER
	backdrop.fill.light_cull_mask &= ~FlightCockpit.LAYER
	var pid := str(GameSession.content.locations.get(_dest, {}).get("planet_id", "viridia"))
	var p := GameSession.content.planet(pid)
	scenery = SpaceScenery.new().setup(str(p.get("biome_id", "green")), hash(pid))
	add_child(scenery)
	var planet := VisualSlot.make("space.planet_" + str(p.get("biome_id", "green")), str(p.get("palette", {}).get("nature", "")))
	planet.scale = Vector3.ONE * 3.0
	planet.position = Vector3(0, -120, -LENGTH - 300.0)
	add_child(planet)
	PlanetLook.apply(planet, str(p.get("biome_id", "green")), str(p.get("palette", {}).get("nature", "")), hash(pid), pid)
	ship = Node3D.new()
	_ark_visual = VisualSlot.make("space.ark_exterior")
	ship.add_child(_ark_visual)
	add_child(ship)
	_dress_ark()
	cam = Camera3D.new()
	cam.far = 5000
	cam.fov = 70
	add_child(cam)
	cam.global_position = Vector3(0, 9, 34)
	_build_cockpit()
	_spawn_hazard(hash(str(pa.get("txn", _dest))))
	hud = GameHud.new()
	add_child(hud)
	_info = UiKit.label("", 17)
	var panel := UiKit.panel()
	panel.add_child(_info)
	hud.top_right.add_child(panel)
	# The campaign objective still names the ship task until the Ark is in orbit;
	# in the cockpit the goal is the approach itself.
	hud.override_objective({"title": Loc.t("Reach orbit around %s") % str(GameSession.content.locations.get(_dest, {}).get("name", _dest)),
		"hint": Loc.t("Steer around the rocks, or let NAV fly. Impacts cost hull and oxygen.")})
	hud.dock_prompt_low()  # no subtitles here: the controls line sits under the Ark, never on it
	var k := SettingsService.primary_key
	if cockpit != null:
		hud.set_prompt(Loc.t("%s/%s speed · %s/%s sideways · %s/%s up/down · [%s] evasive burn · [%s] autopilot · [%s] view") % [k.call("move_forward"), k.call("move_back"),
			k.call("move_left"), k.call("move_right"), k.call("ascend"), k.call("descend"), k.call("sprint"), k.call("autopilot"), k.call("camera_view")])
	else:
		hud.set_prompt(Loc.t("%s/%s speed · %s/%s sideways · %s/%s up/down · [%s] evasive burn · [%s] autopilot") % [k.call("move_forward"), k.call("move_back"),
			k.call("move_left"), k.call("move_right"), k.call("ascend"), k.call("descend"), k.call("sprint"), k.call("autopilot")])
	AudioService.set_ambience("amb_space")
	_thruster = AudioStreamPlayer.new()
	_thruster.stream = AudioService.stream("sfx_thruster")
	_thruster.bus = "SFX"
	_thruster.volume_db = -14
	add_child(_thruster)
	_thruster.play()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if GameSession.has_game():
		hud.nav.say(GameSession.sim.nav.approach_start(_hazard, _belt_start()))


## The Ark exterior like the key art's capital ships (D-044): the carrier is
## turned so its engines face the chase camera (the model's bow is +Z; the
## flight flies -Z), lit window strips, glowing nozzles and trails. Without the
## pack (proxy model) the old thruster effect stays.
func _dress_ark() -> void:
	var spec: Dictionary = DictUtil.get_dict(scenery.doc, "ark_fx") if scenery else {}
	if _ark_visual.using_asset and not spec.is_empty():
		if bool(spec.get("flip", false)):
			_ark_visual.rotation_degrees.y = 180.0
		SpaceFx.dress_ark(_ark_visual, spec)
	else:
		_thr = VisualSlot.make("fx.thruster")
		_thr.position = Vector3(0, -1.5, 15)
		ship.add_child(_thr)


func _build_cockpit() -> void:
	var spec: Dictionary = DictUtil.get_dict(scenery.doc, "cockpit") if scenery else {}
	if spec.is_empty() or scenery.atlas == null:
		return
	var c := FlightCockpit.new()
	if not c.build(spec, scenery.atlas):
		c.free()
		return
	cockpit = c
	var m: Array = DictUtil.get_arr(spec, "mount")
	cockpit.position = Vector3(float(m[0]), float(m[1]), float(m[2])) if m.size() == 3 else Vector3(0, 0.8, -3)
	ship.add_child(cockpit)
	_set_view(cockpit_view)


func _set_view(inside: bool) -> void:
	cockpit_view = inside and cockpit != null
	if cockpit:
		cockpit.visible = cockpit_view
	_ark_visual.visible = not cockpit_view
	if _thr:
		_thr.visible = not cockpit_view
	cam.fov = 74.0 if cockpit_view else 70.0
	cam.near = 0.03 if cockpit_view else 0.05


func _update_camera(delta: float) -> void:
	if cockpit_view:
		# Bank with the Ark, but softer than the hull rolls (none with reduced motion).
		var calm := FxEffect.reduced_motion()
		var shake := 0.0
		if _shake > 0.0:
			shake = clampf(_shake / 0.6, 0.0, 1.0)
		var xf := cockpit.eye.global_transform * cockpit.sway(shake)
		var counter := ship.rotation.z * (1.0 if calm else 0.55)
		xf.basis = xf.basis * Basis(Vector3(0, 0, 1), -counter)
		cam.global_transform = xf
		if _shake > 0.0:
			_shake -= delta
		return
	var behind := Vector3(0, 9, 34)
	cam.global_position = cam.global_position.lerp(ship.global_position + behind, clampf(delta * 5.0, 0, 1))
	if _shake > 0.0:
		_shake -= delta
		cam.global_position += Vector3(randf_range(-0.5, 0.5), randf_range(-0.5, 0.5), 0)
	cam.look_at(ship.global_position + Vector3(0, 2, -40))


func _route_hazard(gs: GameState) -> Dictionary:
	# Debug/legacy entry without a pending approach: show the route's hazard, book nothing.
	if gs == null:
		return {"type": "field", "density": 0.3}
	for r: Dictionary in GameSession.content.routes:
		if (r.get("a") == _dest or r.get("b") == _dest) and (r.get("a") == "drift" or r.get("b") == "drift"):
			return DictUtil.get_dict(r, "hazard")
	return {"type": "none", "density": 0.0}


func _belt_start() -> float:
	return 420.0 if str(_hazard.get("type")) == "belt" else 150.0


## Deterministic per journey (seeded by the approach txn): reloading shows the same field.
func _spawn_hazard(seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var vis_rng := RandomNumberGenerator.new()  # art choices only, never gameplay
	vis_rng.seed = seed_value + 101
	var t := str(_hazard.get("type", "none"))
	var dens := float(_hazard.get("density", 0.0))
	var groups: Array = []  # [count, z_from, z_to, r_min, r_max, drift]
	match t:
		"field":
			groups.append([int(25 + dens * 70), 150.0, LENGTH - 80.0, 2.0, 7.0, 3.0])
		"debris":
			groups.append([int(60 + dens * 160), 150.0, LENGTH - 80.0, 0.7, 2.6, 5.0])
			groups.append([int(6 + dens * 10), 200.0, LENGTH - 120.0, 4.0, 6.5, 2.0])
		"belt":
			groups.append([int(10 + dens * 20), 150.0, 400.0, 2.0, 6.0, 2.0])
			groups.append([int(70 + dens * 160), 420.0, 720.0, 2.0, 8.0, 1.5])  # the belt itself
			groups.append([int(10 + dens * 20), 740.0, LENGTH - 80.0, 2.0, 6.0, 2.0])
	# Scenery outside the corridor so space never looks empty.
	groups.append([30, 0.0, LENGTH, 6.0, 18.0, 0.5, true])
	for g: Array in groups:
		var outside: bool = g.size() > 6
		for i: int in int(g[0]):
			var r := rng.randf_range(float(g[3]), float(g[4]))
			var pos := Vector3(rng.randf_range(-LANE.x, LANE.x), rng.randf_range(-LANE.y, LANE.y), -rng.randf_range(float(g[1]), float(g[2])))
			if outside:
				pos.x = signf(rng.randf() - 0.5) * rng.randf_range(LANE.x + 40.0, LANE.x + 260.0)
			# Look only (D-038): Synty asteroid models normalised to radius 1, or the
			# slot (proxy radius 2 m) without the packs. The rng draws stay identical
			# so positions, radii and drift never change with the art.
			var synty := scenery != null and scenery.has_rocks()
			var a: Node3D = scenery.hazard_visual(vis_rng, "rock" if outside else t, r) if synty else VisualSlot.make("space.asteroid")
			a.position = pos
			a.scale = Vector3(r, r * rng.randf_range(0.7, 1.0), r * rng.randf_range(0.8, 1.2)) / (1.0 if synty else 2.0)
			a.rotation = Vector3(rng.randf() * TAU, rng.randf() * TAU, 0)
			add_child(a)
			var vel := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.5, 0.5), 0) * float(g[5])
			_rocks.append({"node": a, "r": r, "vel": vel, "hit": false, "warned": false, "spin": rng.randf_range(-0.4, 0.4), "scenery": outside})


func _physics_process(delta: float) -> void:
	if _done or hud.any_modal_open():
		return
	if Input.is_action_just_pressed("camera_view") and cockpit != null:
		_set_view(not cockpit_view)
		if not cockpit_view:
			cam.global_position = ship.global_position + Vector3(0, 9, 34)
		AudioService.ui("ui_confirm")
	if Input.is_action_just_pressed("autopilot"):
		autopilot = not autopilot
		autopilot_used = autopilot_used or autopilot
		AudioService.ui("ui_confirm")
		if GameSession.has_game():
			var est: Dictionary = GameSession.sim.travel.approach_estimate(_hazard)
			hud.nav.say({"id": "autopilot_on" if autopilot else "autopilot_off", "severity": "info", "speaker": "NAV",
				"text": GameSession.sim.nav.line("autopilot_on" if autopilot else "autopilot_off", {"fuel": float(est["approach_fuel_autopilot"])})})
	var throttle := Input.get_axis("move_back", "move_forward")
	var steer := Vector2(Input.get_axis("move_left", "move_right"), Input.get_axis("descend", "ascend"))
	var burning := Input.is_action_pressed("sprint") and steer != Vector2.ZERO
	if autopilot:
		var plan := _autopilot_plan()
		steer = plan[0]
		throttle = plan[1]
		burning = false
	var target_speed := clampf(speed + throttle * 30.0 * delta, 12.0, 60.0)
	speed = target_speed if not autopilot else move_toward(speed, 24.0, 20.0 * delta)
	var accel := 34.0 if burning else 16.0
	lateral = lateral.move_toward(steer * (26.0 if burning else 14.0), accel * delta)
	if burning:
		burn_s += delta
	ship.position += Vector3(lateral.x, lateral.y, -speed) * delta
	ship.position.x = clampf(ship.position.x, -LANE.x - 20.0, LANE.x + 20.0)
	ship.position.y = clampf(ship.position.y, -LANE.y - 15.0, LANE.y + 15.0)
	ship.rotation.z = lerpf(ship.rotation.z, -lateral.x * 0.02, clampf(delta * 4.0, 0, 1))
	ship.rotation.x = lerpf(ship.rotation.x, lateral.y * 0.012, clampf(delta * 4.0, 0, 1))
	_update_rocks(delta)
	_warn_t -= delta
	if _warn_t <= 0.0:
		_warn_t = 0.4
		_collision_warnings()
	_update_camera(delta)
	_thruster.pitch_scale = 0.7 + speed / 100.0 + (0.2 if burning else 0.0)
	var progress := -ship.position.z
	if not _cleared and progress > _belt_start() + 330.0 and str(_hazard.get("type")) != "none":
		_cleared = true
		if GameSession.has_game():
			hud.nav.say({"id": "hazard_cleared", "severity": "info", "speaker": "NAV", "text": GameSession.sim.nav.line("hazard_cleared", {"hits": hits})})
	_info.text = Loc.t("Approach: %s\nOrbit in %d m · speed %d\nHull %d %% · Oxygen %d %% · impacts %d\nPilot: %s") % [
		GameSession.content.locations.get(_dest, {}).get("name", _dest), int(maxf(0.0, LENGTH - progress)), int(speed),
		int(_projected_integrity()), int(_projected_oxygen()), hits, Loc.t("AUTOPILOT (NAV)") if autopilot else Loc.t("manual")]
	if progress >= LENGTH:
		_arrive()


func _update_rocks(delta: float) -> void:
	var sp := ship.global_position
	for rk: Dictionary in _rocks:
		var n: Node3D = rk["node"]
		n.position += (rk["vel"] as Vector3) * delta
		n.rotation.y += float(rk["spin"]) * delta
		n.rotation.x += float(rk["spin"]) * 0.4 * delta  # slow tumble (look only)
		# Rocks already passed would sit between camera and ark: hide them.
		n.visible = rk["scenery"] or n.position.z < sp.z + float(rk["r"]) + 4.0
		if rk["hit"] or rk["scenery"]:
			continue
		var r := float(rk["r"])
		if n.position.distance_to(sp) < r + SHIP_R:
			rk["hit"] = true
			_impact(r)
			var away := (sp - n.position).normalized()
			lateral += Vector2(away.x, away.y) * 12.0
			speed *= 0.75


func _impact(r: float) -> void:
	var is_severe := r >= SEVERE_R or speed >= SEVERE_SPEED
	hits += 1
	if is_severe:
		severe += 1
	AudioService.play("alarm_warning" if not is_severe else "alarm_critical", "SFX", -6.0)
	AudioService.alarm_raised.emit(is_severe)
	if SettingsService.get_value("camera_shake", true) and not SettingsService.get_value("reduced_motion", false):
		_shake = 0.6 if is_severe else 0.35
	if GameSession.has_game():
		var item := GameSession.sim.nav.impact(GameSession.state, is_severe, ["A", "B", "C", "D", "E"][hits % 5])
		# The domain books impacts on arrival; show NAV the projected values now.
		item["text"] = GameSession.sim.nav.line(item["id"], {"integrity": _projected_integrity(), "oxygen": _projected_oxygen(), "section": ["A", "B", "C", "D", "E"][hits % 5]})
		hud.nav.say(item)


func _projected_integrity() -> float:
	var ap: Dictionary = GameSession.content.bal("approach", {})
	return maxf(0.0, _start_integrity - hits * float(ap.get("hit_integrity", 1.5)) - severe * (float(ap.get("severe_integrity", 3.0)) - float(ap.get("hit_integrity", 1.5))))


func _projected_oxygen() -> float:
	return maxf(0.0, _start_oxygen - severe * float(GameSession.content.bal("approach", {}).get("severe_oxygen", 2.5)))


## Rocks that will pass within reach in the next few seconds, nearest first: [{rk, t, miss}].
func _threats(horizon: float) -> Array:
	var out: Array = []
	var sp := ship.global_position
	var sv := Vector3(lateral.x, lateral.y, -speed)
	for rk: Dictionary in _rocks:
		if rk["hit"] or rk["scenery"]:
			continue
		var n: Node3D = rk["node"]
		var rel := n.position - sp
		var rv := (rk["vel"] as Vector3) - sv
		var t := -rel.dot(rv) / maxf(rv.length_squared(), 0.001)
		if t < 0.0 or t > horizon:
			continue
		var miss := (rel + rv * t).length()
		if miss < float(rk["r"]) + SHIP_R + 3.0:
			out.append({"rk": rk, "t": t, "miss": miss, "rel": rel})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["t"] < b["t"])
	return out


func _collision_warnings() -> void:
	if not GameSession.has_game() or autopilot:
		return
	for th: Dictionary in _threats(4.0):
		var rk: Dictionary = th["rk"]
		if rk["warned"]:
			continue
		rk["warned"] = true
		var rel: Vector3 = th["rel"]
		var side := "right" if rel.x <= 0.0 else "left"
		if absf(rel.y) > absf(rel.x) * 1.5:
			side = "down" if rel.y > 0.0 else "up"
		hud.nav.say(GameSession.sim.nav.collision_course(float(th["t"]), side))
		break


## NAV's flying: steer away from the nearest predicted collision, otherwise
## drift back to the corridor centre; slow and steady. Returns [steer, throttle].
func _autopilot_plan() -> Array:
	var steer := Vector2(-ship.position.x, -ship.position.y) * 0.02
	var threats := _threats(5.0)
	if not threats.is_empty():
		var th: Dictionary = threats[0]
		var rel: Vector3 = th["rel"]
		var away := Vector2(-rel.x, -rel.y)
		if away.length() < 0.5:
			away = Vector2(1.0 if ship.position.x <= 0.0 else -1.0, 0.0)
		steer = away.normalized()
	return [steer.limit_length(1.0), 0.0]


func _arrive() -> void:
	_done = true
	if GameSession.has_game() and not GameSession.state.campaign.pending_approach.is_empty():
		var r := GameSession.cmd_resolve_approach(hits, severe, burn_s, autopilot_used)
		if r.ok:
			hud.nav.say(GameSession.sim.nav.arrival(GameSession.state))
	hud.set_prompt(Loc.t("Orbit established."))
	await get_tree().create_timer(2.5).timeout
	AppFlow.goto("ship", {"spawn": "orbit_terminal"})


func debug_action(action: String) -> void:
	match action:
		"autopilot":
			autopilot = true
			autopilot_used = true
			for i: int in 200:
				_physics_process(1.0 / 60.0)
		"belt":
			ship.position.z = -_belt_start() + 40.0
			for i: int in 60:
				_physics_process(1.0 / 60.0)
		"cockpit", "cockpit_belt":  # evidence: the view from the bridge
			_set_view(true)
			if action == "cockpit_belt":
				ship.position.z = -_belt_start() + 40.0
			for i: int in 30:
				_physics_process(1.0 / 60.0)

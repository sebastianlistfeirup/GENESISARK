extends Node3D
## Captain's expedition (bible p.8, GA-06): a 6-10 minute area with a clear
## goal, two routes, an optional risk sample, suit energy as the clock, and a
## warned way home. Runtime reports position/time; ExpeditionService decides.

const FX_FOR_HAZARD := {"spores": "fx.spores", "storms": "fx.storm", "heat": "fx.dust", "dust": "fx.dust", "cold": "fx.snow", "long_night": "fx.snow"}

## F6 in the editor without a running campaign builds this fixture
## (e.g. "colony:nivalis", "grown:umbra", "expedition:ferrum").
@export var preview_setup := "expedition:viridia"

var terrain: TerrainBuilder
var captain: Captain
var hud: GameHud
var survey: Dictionary = {}
var planet: Dictionary = {}
## Hazard id -> ambience layer cue (docs/AUDIO_LEDGER.csv).
const HAZARD_SOUND := {"spores": "amb_hazard_spores", "storms": "amb_hazard_storm", "heat": "amb_hazard_dust",
	"dust": "amb_hazard_dust", "cold": "amb_hazard_cold", "long_night": "amb_hazard_cold"}
var hazard_areas: Array = []  # [{area: Area3D, mult: float, label: String}]
var _suit_bar: ProgressBar
var _suit_label: Label
var _status: Label
var _finishing := false
var _markers: Dictionary = {}
var waypoints: WaypointLayer
var _nav_said: Dictionary = {}  # what NAV has reported this expedition (UI memory, not saved)
var _objective_key := ""
var _nav_t := 0.0
var _descending := false  # PlanetDescent in progress: no suit drain, no HUD
var _poi_labels: Dictionary = {}  # key -> Label3D: far-off signage, handed to the waypoint layer up close


func _ready() -> void:
	if not GameSession.has_game():
		DebugFixtures.prepare(preview_setup)
	var gs: GameState = GameSession.state
	if gs.expedition == null:
		AppFlow.goto("ship")
		return
	var ex := gs.expedition
	planet = GameSession.content.planet(ex.planet_id)
	survey = GameSession.content.surveys.get(ex.planet_id, {})
	var site := GameSession.content.site(ex.site_id)
	for n: Node in TerrainBuilder.environment_for(planet, str(planet.get("biome_id"))):
		add_child(n)
	terrain = TerrainBuilder.new()
	terrain.name = "Terrain"
	terrain.setup(str(planet.get("biome_id")), site, DictUtil.get_dict(planet, "palette"), 180.0)
	var pts: Dictionary = DictUtil.get_dict(survey, "points")
	terrain.add_flat(Vector2.ZERO, 9.0)
	var avoid: Array = [[Vector2.ZERO, 14.0]]
	for k: String in pts.keys():
		var pos := _pt(pts[k])
		terrain.add_flat(pos, 4.0)
		avoid.append([pos, 7.0])
	for r: Dictionary in DictUtil.get_arr(survey, "routes"):
		for w: Variant in DictUtil.get_arr(r, "waypoints"):
			avoid.append([Vector2(float(w[0]), float(w[1])), 5.0])
	terrain.apply_planet_style(str(planet.get("id")))
	var must_reach: Array = [Vector2.ZERO]
	for i: int in 12:  # the landing pad and the lander beside it stay on land
		must_reach.append(Vector2.from_angle(TAU * i / 12.0) * 6.0)
		must_reach.append(Vector2.from_angle(TAU * i / 12.0) * 11.0)
	for k: String in pts.keys():
		must_reach.append(_pt(pts[k]))
	for r: Dictionary in DictUtil.get_arr(survey, "routes"):
		var prev := Vector2.ZERO
		for w: Variant in DictUtil.get_arr(r, "waypoints"):
			var wp := Vector2(float(w[0]), float(w[1]))
			for i: int in 9:
				must_reach.append(prev.lerp(wp, i / 8.0))
			prev = wp
	terrain.set_water_below(must_reach)
	add_child(terrain)
	terrain.build()
	terrain.scatter(hash(ex.site_id), 70 if GroundCover.spec_for(str(planet.get("id")), "").is_empty() else 0, avoid)
	add_child(GroundCover.build(terrain, str(planet.get("id")), hash(ex.site_id) + 7, avoid, 180.0, str(planet.get("biome_id"))))
	add_child(PlanetSky.build(str(planet.get("id")), str(planet.get("biome_id")), terrain))
	_place_lander()
	SceneDressing.attach(self, str(site.get("id", "")), terrain)
	_place_points(pts)
	_place_routes()
	_place_hazards()
	add_child(PoiDressing.build(terrain, survey, planet, hash(ex.site_id)))  # D-038: camp, POI, hazard and route set dressing (look only)
	captain = Captain.new()
	captain.footstep_slot = "sfx_footstep_soil"
	captain.wear_helmet = true
	add_child(captain)
	var motes := PlanetSky.motes(str(planet.get("id")), str(planet.get("biome_id")))
	if motes:
		captain.add_child(motes)
	captain.teleport(Vector3(4, terrain.height_at(4, 4) + 0.3, 4), PI * 0.25)
	if str(planet.get("id")) == "umbra":
		var lamp := SpotLight3D.new()
		lamp.position = Vector3(0, 1.7, -0.3)
		lamp.spot_range = 30
		lamp.light_energy = 3.0
		captain.visual_pivot.add_child(lamp)
	hud = GameHud.new()
	add_child(hud)
	_maybe_landing_intro(ex)
	waypoints = WaypointLayer.new()
	add_child(waypoints)
	waypoints.visible = not _descending
	for key: String in _markers.keys():
		var m: Interactable = _markers[key]
		waypoints.add_place(m, WaypointLayer.nice(m.title), 3.6 if key != "lander" else 4.2)
	captain.interact_target_changed.connect(func(t: Interactable) -> void: hud.set_prompt(t.prompt_text() + ("\n" + t.consequence if t and not t.consequence.is_empty() else "") if t else ""))
	captain.hold_progress.connect(hud.set_hold)
	_build_suit_hud()
	AudioService.set_ambience_any(["amb_surface_" + str(planet.get("biome_id")), "amb_colony_wind"])
	GameSession.trigger_story("expedition_start")
	# On the ground the voyage objective's hint ("choose a landing site ...") is
	# stale: the panel shows this site's goal instead (it used to be a toast).
	var o := GameSession.sim.objectives.current(GameSession.state)
	hud.override_objective({"title": str(o.get("title", "")), "hint": str(survey.get("goal", o.get("hint", "")))})
	_update_waypoint(ex)
	hud.nav.say(GameSession.sim.nav.surface_brief(ex, _nav_context(ex, [1.0, "", "", ""])))


func _pt(v: Variant) -> Vector2:
	var a: Array = v if v is Array else DictUtil.get_arr(v, "pos")
	return Vector2(float(a[0]), float(a[1])) if a.size() == 2 else Vector2.ZERO


func _ground(p: Vector2) -> Vector3:
	return Vector3(p.x, terrain.height_at(p.x, p.y), p.y)


func _place_lander() -> void:
	var lander := Interactable.new()
	lander.interact_id = "lander"
	lander.title = Loc.t("the lander")
	lander.verb = Loc.t("Return to")
	lander.consequence = Loc.t("Ends the expedition. Samples and relay become knowledge of the planet.")
	lander.radius = 3.5
	add_child(lander)
	lander.global_position = _ground(Vector2.ZERO)
	lander.add_child(VisualSlot.make("surface.lander"))
	var sb := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 2.0
	cyl.height = 3.5
	cs.shape = cyl
	cs.position.y = 1.75
	sb.add_child(cs)
	lander.add_child(sb)
	lander.used.connect(_on_use)
	_markers["lander"] = lander


func _place_points(pts: Dictionary) -> void:
	for key: String in ["main_sample", "risk_sample", "relay"]:
		if not pts.has(key):
			continue
		var d: Dictionary = pts[key]
		var it := Interactable.new()
		it.interact_id = key
		it.title = str(d.get("label", key))
		it.radius = 2.4
		if key == "relay":
			it.verb = Loc.t("Place relay at")
			it.consequence = Loc.t("The relay secures data and assesses the landing site.")
		else:
			it.verb = Loc.t("Take sample:")
			it.hold_time = float(GameSession.content.bal("suit.sample_time_s", 8.0))
			it.consequence = Loc.t("Hold [%s] for %d seconds.%s") % [SettingsService.binding_text("interact"), int(it.hold_time), Loc.t(" Optional risk sample.") if key == "risk_sample" else ""]
		add_child(it)
		it.global_position = _ground(_pt(d))
		var marker := VisualSlot.make("surface.sample_marker" if key != "relay" else "surface.relay_beacon")
		it.add_child(marker)
		var lbl := Label3D.new()
		lbl.text = str(d.get("label", key))
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lbl.font_size = 64
		lbl.pixel_size = 0.01
		lbl.position.y = 3.2
		lbl.modulate = UiKit.AMBER if key != "relay" else UiKit.PETROL.lightened(0.3)
		lbl.outline_size = 12
		lbl.outline_modulate = Color(0.02, 0.05, 0.06, 0.85)
		lbl.no_depth_test = true
		it.add_child(lbl)
		_poi_labels[key] = lbl
		it.used.connect(_on_use)
		_markers[key] = it


func _place_routes() -> void:
	for r: Dictionary in DictUtil.get_arr(survey, "routes"):
		var col := "#1f8a8a" if r.get("id") == "safe" else "#e8a33d"
		var prev := Vector2.ZERO
		var wps: Array = [[0, 0]] + DictUtil.get_arr(r, "waypoints")
		for w: Variant in wps:
			var p := Vector2(float(w[0]), float(w[1]))
			var seg := p - prev
			var steps := int(seg.length() / 4.0)
			for i: int in steps:
				var q := prev + seg * (float(i) / maxf(1.0, float(steps)))
				# A flat glowing chevron on the ground pointing along the route (shape + colour, a11y).
				var dot := MeshInstance3D.new()
				var pm := PrismMesh.new()
				pm.size = Vector3(0.55, 0.5, 0.05)
				dot.mesh = pm
				dot.material_override = AssetSlots.material(col, 2.2)
				dot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				dot.position = _ground(q) + Vector3(0, 0.06, 0)
				dot.rotation = Vector3(-PI * 0.5, atan2(-seg.x, -seg.y), 0)
				add_child(dot)
			prev = p
		var lbl := Label3D.new()
		# Safe vs. risky route: symbol as well as colour.
		lbl.text = UiKit.status_text("ok" if r.get("id") == "safe" else "warning", str(r.get("label", "")))
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lbl.font_size = 48
		lbl.pixel_size = 0.01
		lbl.modulate = Color(col)
		lbl.outline_size = 10
		lbl.outline_modulate = Color(0.02, 0.05, 0.06, 0.85)
		# Label at the route's first bend (waypoint 0 is the lander, shared by every route).
		var bends: Array = DictUtil.get_arr(r, "waypoints").filter(func(w: Variant) -> bool: return Vector2(float(w[0]), float(w[1])).length() > 3.0)
		var first: Array = bends[0] if not bends.is_empty() else [0, 0]
		lbl.position = _ground(Vector2(float(first[0]), float(first[1]))) + Vector3(0, 2.0, 0)
		# A choice made near the lander: the sign fades out with distance instead
		# of piling onto the place and objective labels across the map.
		lbl.visibility_range_end = 45.0
		lbl.visibility_range_end_margin = 8.0
		lbl.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		add_child(lbl)


func _place_hazards() -> void:
	var lines: Array = []  # beacons keep off the routes and the interactables
	for rt: Dictionary in DictUtil.get_arr(survey, "routes"):
		var line: Array = [Vector2.ZERO]
		for w: Variant in DictUtil.get_arr(rt, "waypoints"):
			line.append(Vector2(float(w[0]), float(w[1])))
		lines.append(line)
	var keep: Array = []
	for key: String in _markers.keys():
		var m: Node3D = _markers[key]
		keep.append([Vector2(m.global_position.x, m.global_position.z), 5.5 if key == "lander" else 3.2])
	for hz: Dictionary in DictUtil.get_arr(survey, "hazard_zones"):
		var hid := str(hz.get("hazard_id"))
		var hdef: Dictionary = GameSession.content.hazards.get(hid, {})
		var c := _pt(hz.get("center"))
		var r := DictUtil.get_float(hz, "radius", 10.0)
		var area := Area3D.new()
		area.collision_layer = 32
		area.collision_mask = 2
		var cs := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = r
		cyl.height = 30.0
		cs.shape = cyl
		area.add_child(cs)
		add_child(area)
		area.global_position = _ground(c)
		# D-043: glowing ground ring + hazard-tape band, edge haze, per-type haze and beacons.
		area.add_child(HazardZoneVisual.build(terrain, c, r, hid, str(hdef.get("color", "#d6c447")), lines, keep))
		var fx := VisualSlot.make(FX_FOR_HAZARD.get(hid, "fx.dust"))
		area.add_child(fx)
		var lbl := Label3D.new()
		lbl.text = "▲ " + str(hz.get("label", hdef.get("name", hid)))
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lbl.font_size = 56
		lbl.pixel_size = 0.01
		lbl.position.y = 6.5
		lbl.modulate = Color(str(hdef.get("color", "#d6c447")))
		lbl.outline_size = 10
		lbl.outline_modulate = Color(0.02, 0.05, 0.06, 0.85)
		area.add_child(lbl)
		hazard_areas.append({"area": area, "mult": DictUtil.get_float(DictUtil.get_dict(hdef, "expedition"), "suit_drain_multiplier", 2.0),
			"label": str(hz.get("label", hdef.get("name", hid))), "sound": str(HAZARD_SOUND.get(hid, "")), "id": hid + "@" + str(hazard_areas.size())})


func _build_suit_hud() -> void:
	var p := UiKit.panel(Vector2(340, 0))
	var v := UiKit.vbox(4)
	v.add_child(UiKit.title(Loc.t("Suit")))
	_suit_bar = UiKit.bar(100, 100, UiKit.PETROL, 18)
	v.add_child(_suit_bar)
	_suit_label = UiKit.label("", 16)
	v.add_child(_suit_label)
	_status = UiKit.label("", 15, UiKit.MUTED, true)
	v.add_child(_status)
	p.add_child(v)
	hud.top_right.add_child(p)


## Expedition order: main sample -> relay -> back to the lander (the risk
## sample is optional, so it is a place, never the objective).
func _update_waypoint(ex: ExpeditionState) -> void:
	if waypoints == null:
		return
	var key := "lander"
	var label := Loc.t("Return to the lander")
	if not "main_sample" in ex.samples and _markers.has("main_sample"):
		key = "main_sample"
		label = Loc.t("Take the main sample")
	elif not ex.relay_placed and _markers.has("relay"):
		key = "relay"
		label = Loc.t("Place the relay")
	_objective_key = key
	waypoints.set_objective(_markers.get(key), label, 3.6 if key != "lander" else 4.2)


## Big place signs read from afar; up close (and for the current objective) the
## waypoint layer names the spot, so the two never stack on top of each other.
func _process(_delta: float) -> void:
	if captain == null:
		return
	for key: String in _poi_labels:
		var lbl: Label3D = _poi_labels[key]
		var far := captain.global_position.distance_to(lbl.global_position) > WaypointLayer.PLACE_RANGE
		lbl.visible = far and key != _objective_key


func _hazard_mult() -> Array:
	for h: Dictionary in hazard_areas:
		if (h["area"] as Area3D).overlaps_body(captain):
			return [float(h["mult"]), str(h["label"]), str(h["sound"]), str(h["id"])]
	return [1.0, "", "", ""]


func _physics_process(delta: float) -> void:
	var gs: GameState = GameSession.state
	if gs == null or gs.expedition == null or _finishing:
		return
	var ex := gs.expedition
	_update_waypoint(ex)
	var hm := _hazard_mult()
	AudioService.set_layer(hm[2], -4.0)
	if not hud.any_modal_open() and not _descending:
		GameSession.sim.expedition.tick(gs, delta, hm[0])
	var reserve := float(GameSession.content.bal("suit.reserve_warning", 30.0))
	_suit_bar.value = ex.suit_energy
	var fill := UiKit.DANGER if ex.suit_energy <= reserve else (UiKit.WARN if hm[0] > 1.0 else UiKit.PETROL)
	(_suit_bar.get_theme_stylebox("fill") as StyleBoxFlat).bg_color = fill
	var drain := float(GameSession.content.bal("suit.drain_per_s", 0.12)) * float(hm[0])
	_suit_label.text = Loc.t("%s %d%%  (−%.2f/s · ~%d s left)") % [UiKit.status_icon("critical" if ex.suit_energy <= reserve else "ok"), int(ex.suit_energy), drain, int(ex.suit_energy / maxf(drain, 0.01))]
	var lines: Array = []
	if hm[0] > 1.0:
		lines.append(Loc.t("▲ In hazard zone: %s (×%.1f consumption)") % [hm[1], hm[0]])
	lines.append(Loc.t("Samples: %d/2 · Relay: %s") % [ex.samples.size(), Loc.t("placed") if ex.relay_placed else Loc.t("missing")])
	if ex.drone_refill_available and not ex.drone_refill_used:
		lines.append(Loc.t("[%s] Call drone reserve (+%d%%)") % [SettingsService.binding_text("drone_refill"), int(GameSession.content.bal("suit.drone_refill", 35.0))])
	var lander: Node3D = _markers.get("lander")
	if lander:
		lines.append(Loc.t("Lander: %d m") % int(captain.global_position.distance_to(lander.global_position)))
	_status.text = "\n".join(lines)
	_nav_t -= delta
	if _nav_t <= 0.0:
		_nav_t = 0.5
		for item: Dictionary in GameSession.sim.nav.surface_update(ex, _nav_context(ex, hm), _nav_said):
			hud.nav.say(item)
	for key: String in ["main_sample", "risk_sample"]:
		if _markers.has(key) and key in ex.samples:
			(_markers[key] as Interactable).locked = true
			(_markers[key] as Interactable).locked_reason = Loc.t("the sample is taken")
	if _markers.has("relay") and ex.relay_placed:
		(_markers["relay"] as Interactable).locked = true
		(_markers["relay"] as Interactable).locked_reason = Loc.t("the relay is here")
	if ex.status == ExpeditionState.STATUS_RECALLED:
		_finish(true)


func _nav_context(ex: ExpeditionState, hm: Array) -> Dictionary:
	var base := float(GameSession.content.bal("suit.drain_per_s", 0.12))
	var lander: Node3D = _markers.get("lander")
	var target: Node3D = _markers.get(_objective_key)
	return {"dist_lander": captain.global_position.distance_to(lander.global_position) if lander else 0.0,
		"walk_speed": captain.walk_speed, "drain": base * maxf(1.0, float(hm[0])), "base_drain": base,
		"hazard_id": str(hm[3]), "hazard_label": str(hm[1]), "mult": float(hm[0]),
		"next_key": _objective_key, "next_label": waypoints.objective_label if waypoints else "",
		"next_dist": captain.global_position.distance_to(target.global_position) if target else 0.0}


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("drone_refill"):
		var r := GameSession.cmd_drone_refill()
		if r.ok:
			hud.toast(Loc.t("The drone delivers an energy cell."), "ok")


func _on_use(it: Interactable) -> void:
	var gs: GameState = GameSession.state
	match it.interact_id:
		"main_sample", "risk_sample":
			var r := GameSession.cmd_take_sample(it.interact_id)
			if r.ok:
				hud.toast(str(r.data.get("text", Loc.t("Sample taken."))), "ok", 8.0)
		"relay":
			if GameSession.cmd_place_relay().ok:
				hud.toast(str(DictUtil.get_dict(survey, "findings").get("relay", Loc.t("The relay is transmitting."))), "ok")
		"lander":
			if gs.expedition.samples.is_empty() and not it.has_meta("confirmed"):
				it.set_meta("confirmed", true)
				hud.toast(Loc.t("You have no samples yet. Press again to return anyway."), "warning")
				return
			_finish(false)


func _finish(recalled: bool) -> void:
	if _finishing:
		return
	_finishing = true
	captain.set_active(false)
	if recalled:
		hud.toast(str(survey.get("evacuation", Loc.t("ARK is guiding you back."))), "critical", 6.0)
		await get_tree().create_timer(2.5).timeout
	GameSession.cmd_finish_expedition()
	await get_tree().create_timer(1.0).timeout
	AppFlow.goto("ship", {"spawn": "orbit_terminal"})


func debug_action(action: String) -> void:
	if action == "sunview":  # evidence: look toward the system's star from the camp
		var pr := Lighting.preset(planet)
		var dir := Basis.from_euler(Vector3(deg_to_rad(float(pr.get("sun_pitch", -45))), deg_to_rad(float(pr.get("sun_yaw", 30))), 0)).z.normalized()
		var cam := Camera3D.new()
		add_child(cam)
		var at := Vector3(0, terrain.height_at(0, 0) + 6.0, 0)
		cam.position = at - Vector3(dir.x, 0, dir.z).normalized() * 12.0
		cam.look_at(at + dir * 100.0 + Vector3(0, -30, 0))
		cam.fov = 70.0
		cam.far = 3000.0
		cam.current = true
		if hud:
			hud.visible = false
		return
	if action.begins_with("vista"):  # evidence: a high establishing shot over the site (vista / vista:<azimuth deg>)
		var az := deg_to_rad(float(action.get_slice(":", 1))) if action.contains(":") else 0.6
		var cam := Camera3D.new()
		add_child(cam)
		var at := Vector3(0, terrain.height_at(0, 0), 0)
		cam.position = at + Vector3(sin(az) * -20.0, 24.0, cos(az) * 20.0)
		cam.look_at(at + Vector3(sin(az) * 30.0, 4.0, -cos(az) * 30.0))
		cam.fov = 60.0
		cam.far = 3000.0
		cam.current = true
		if hud:
			hud.visible = false
		return
	if action.begins_with("sky"):  # evidence: look up at the sky bodies (sky / sky:<azimuth deg>)
		var az := deg_to_rad(float(action.get_slice(":", 1))) if action.contains(":") else 0.0
		captain.camera_rig.yaw = -az
		captain.camera_rig.pitch = 0.25
		captain.camera_rig.snap()
		return
	match action:
		"at_sample":
			var m: Node3D = _markers.get("main_sample")
			captain.teleport(m.global_position + Vector3(-4, 0.5, 5), -0.6)
		"hazard":  # evidence: look at the first hazard zone and its fx.* particles
			if not hazard_areas.is_empty():
				var c: Vector3 = (hazard_areas[0]["area"] as Area3D).global_position
				var at := Vector2(c.x, c.z + 16.0)
				captain.teleport(Vector3(at.x, terrain.height_at(at.x, at.y) + 0.5, at.y), 0.0)
				captain.camera_rig.pitch = -0.2
				captain.camera_rig.distance = 6.0
		"hazard_far", "hazard_edge":  # evidence: the whole zone from above the lander side / the edge at eye level beside a beacon
			if not hazard_areas.is_empty():
				var c: Vector3 = (hazard_areas[0]["area"] as Area3D).global_position
				var r := float(((hazard_areas[0]["area"] as Area3D).get_child(0) as CollisionShape3D).shape.get("radius"))
				var dir := Vector2(-c.x, -c.z).normalized()  # toward the open landing site
				var cam := Camera3D.new()
				add_child(cam)
				if action == "hazard_far":
					var p := Vector2(c.x, c.z) + dir * (r + 12.0)
					cam.position = Vector3(p.x, c.y + 15.0, p.y)
					cam.look_at(c + Vector3(0, 1.0, 0))
				else:
					var p := Vector2(c.x, c.z) + dir.rotated(0.35) * (r + 6.0)
					cam.position = Vector3(p.x, terrain.height_at(p.x, p.y) + 2.2, p.y)
					cam.look_at(c + Vector3(0, 1.2, 0))
				cam.fov = 62.0
				cam.current = true
				if hud:
					hud.visible = false
		"overview":
			captain.teleport(Vector3(0, terrain.height_at(0, 12) + 0.5, 12), 0.0)
			captain.camera_rig.pitch = -0.6
			captain.camera_rig.distance = 14.0


## The lander comes down on a fresh expedition: it drops from the sky on its
## thrusters, kicks up dust, and the captain steps out. Visual only (the domain
## already holds the landed state); skipped in tests, evidence captures (unless
## --action=intro), saved mid-expedition, and shortened with reduced motion.
func _maybe_landing_intro(ex: ExpeditionState) -> void:
	if AppFlow.test_mode or ex.elapsed_s > 0.5 or not ex.samples.is_empty():
		return
	var action := str(AppFlow.params.get("action", ""))
	if DebugCapture.requested() and action != "intro" and not action.begins_with("descent"):
		return
	var lander: Node3D = _markers.get("lander")
	if lander == null or lander.get_child_count() == 0:
		return
	var body: Node3D = null  # the lander's VisualSlot (child 0 is the interactable's own shape)
	for c: Node in lander.get_children():
		if c is VisualSlot:
			body = c
			break
	if body == null:
		return
	if PlanetDescent.wanted() and action != "intro":
		_start_descent(lander, body, float(action.get_slice(":", 1)) if action.contains(":") else PlanetDescent.START_ALT)
		return
	var dur := 0.6 if FxEffect.reduced_motion() else 3.4
	var height := 38.0
	body.position.y = height
	var thr := VisualSlot.make("fx.thruster")
	thr.rotation_degrees.x = -90.0  # plume points down at the ground
	body.add_child(thr)
	captain.visible = false
	captain.input_enabled = false
	captain.camera_rig.pitch = 0.12
	captain.camera_rig.yaw = captain.camera_rig.yaw + 0.5
	captain.camera_rig.snap()
	var t := create_tween()
	t.tween_property(body, "position:y", 0.0, dur).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	t.tween_callback(func() -> void:
		thr.queue_free()
		var dust := VisualSlot.make("fx.landing_dust")
		lander.add_child(dust)
		get_tree().create_timer(4.0).timeout.connect(dust.queue_free)
		AudioService.play("sfx_landing", "SFX", -6.0))
	t.tween_interval(0.0 if FxEffect.reduced_motion() else 0.6)
	t.tween_callback(func() -> void:
		captain.visible = true
		captain.input_enabled = true
		captain.camera_rig.pitch = CaptainCamera.REST_PITCH)


## Real-time descent from orbit (PlanetDescent, D-049): the captain waits in the
## lander, the suit clock and the HUD wait until touchdown.
func _start_descent(lander: Node3D, body: Node3D, start_alt: float) -> void:
	_descending = true
	captain.visible = false
	captain.input_enabled = false
	var d := PlanetDescent.new()
	d.name = "Descent"
	add_child(d)
	d.start(self, terrain, planet, lander.global_position, body, start_alt)
	d.finished.connect(func() -> void:
		_descending = false
		if waypoints:
			waypoints.visible = true
		captain.visible = true
		captain.input_enabled = true
		captain.camera_rig.camera.current = true
		captain.camera_rig.pitch = CaptainCamera.REST_PITCH
		captain.camera_rig.snap())

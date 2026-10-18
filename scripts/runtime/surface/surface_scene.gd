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
	add_child(terrain)
	terrain.build()
	terrain.scatter(hash(ex.site_id), 70, avoid)
	_place_lander()
	SceneDressing.attach(self, str(site.get("id", "")), terrain)
	_place_points(pts)
	_place_routes()
	_place_hazards()
	captain = Captain.new()
	captain.footstep_slot = "sfx_footstep_soil"
	add_child(captain)
	captain.teleport(Vector3(4, terrain.height_at(4, 4) + 0.3, 4), PI * 0.25)
	if str(planet.get("id")) == "umbra":
		var lamp := SpotLight3D.new()
		lamp.position = Vector3(0, 1.7, -0.3)
		lamp.spot_range = 30
		lamp.light_energy = 3.0
		captain.visual_pivot.add_child(lamp)
	hud = GameHud.new()
	add_child(hud)
	waypoints = WaypointLayer.new()
	add_child(waypoints)
	for key: String in _markers.keys():
		var m: Interactable = _markers[key]
		waypoints.add_place(m, WaypointLayer.nice(m.title), 3.6 if key != "lander" else 4.2)
	captain.interact_target_changed.connect(func(t: Interactable) -> void: hud.set_prompt(t.prompt_text() + ("\n" + t.consequence if t and not t.consequence.is_empty() else "") if t else ""))
	captain.hold_progress.connect(hud.set_hold)
	_build_suit_hud()
	AudioService.set_ambience_any(["amb_surface_" + str(planet.get("biome_id")), "amb_colony_wind"])
	GameSession.trigger_story("expedition_start")
	hud.toast(str(survey.get("goal", "")), "info", 9.0)
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
		lbl.no_depth_test = true
		it.add_child(lbl)
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
				var dot := MeshInstance3D.new()
				var sm := SphereMesh.new()
				sm.radius = 0.18
				sm.height = 0.36
				dot.mesh = sm
				dot.material_override = AssetSlots.material(col, 1.5)
				dot.position = _ground(q) + Vector3(0, 0.25, 0)
				add_child(dot)
			prev = p
		var lbl := Label3D.new()
		lbl.text = str(r.get("label", ""))
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
		add_child(lbl)


func _place_hazards() -> void:
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
		var vis := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = r
		cm.bottom_radius = r
		cm.height = 6.0
		vis.mesh = cm
		vis.position.y = 2.0
		vis.material_override = AssetSlots.material(str(hdef.get("color", "#d6c447")), 0.3, 0.18)
		area.add_child(vis)
		var fx := VisualSlot.make(FX_FOR_HAZARD.get(hid, "fx.dust"))
		area.add_child(fx)
		var lbl := Label3D.new()
		lbl.text = "▲ " + str(hz.get("label", hdef.get("name", hid)))
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lbl.font_size = 56
		lbl.pixel_size = 0.01
		lbl.position.y = 6.5
		lbl.modulate = Color(str(hdef.get("color", "#d6c447")))
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
	if not hud.any_modal_open():
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
	match action:
		"at_sample":
			var m: Node3D = _markers.get("main_sample")
			captain.teleport(m.global_position + Vector3(-4, 0.5, 5), -0.6)
		"overview":
			captain.teleport(Vector3(0, terrain.height_at(0, 12) + 0.5, 12), 0.0)
			captain.camera_rig.pitch = -0.6
			captain.camera_rig.distance = 14.0

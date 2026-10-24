extends Node3D
## The ark interior: bridge, embryo bank, workshop and cryo bay on one loop
## (bible p.6). Terminals issue domain commands; lights follow ship power.

var builder: ShipBuilder
var captain: Captain
var hud: GameHud
var starmap: StarMapPanel
var orbit: OrbitPanel
var embryo_panel: ArkPanels.EmbryoBankPanel
var workshop_panel: ArkPanels.WorkshopPanel
var interactables: Dictionary = {}
var _display: Label3D
var _ai: Node3D
var _ai_t := 0.0
var _zone := ""
var waypoints: WaypointLayer
var _window_planet: Node3D
var _voyage_label: Label


func _ready() -> void:
	if not GameSession.has_game():
		GameSession.new_campaign()
	var env := WorldEnvironment.new()
	var e := Environment.new()
	# Space outside the windows: the same painted nebula as the flight (ambient stays local).
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = preload("res://art/shaders/nebula_sky.gdshader")
	sky_mat.set_shader_parameter("seed", 7.0)
	sky_mat.set_shader_parameter("veil_strength", 1.6)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("5a3f6e")  # magenta-violet shade against teal screens: the Sci-Fi Space key art grade
	e.ambient_light_energy = 0.75
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.tonemap_white = 2.2
	e.glow_enabled = true
	e.glow_intensity = 1.1
	e.glow_bloom = 0.12
	e.adjustment_enabled = true
	e.adjustment_saturation = 1.2
	e.adjustment_contrast = 1.06
	e.glow_hdr_threshold = 0.9
	e.ssao_enabled = true
	e.ssao_radius = 1.6
	e.ssao_intensity = 2.0
	e.fog_enabled = true
	e.fog_light_color = Color("0b1219")
	e.fog_density = 0.01
	e.fog_sky_affect = 0.0  # the interior haze must not blank the nebula outside the windows
	env.environment = e
	add_child(env)
	# The builder and an empty "Dressing" node live in ship.tscn: tick
	# ShipBuilder.build_now in the editor to preview the layout, and place
	# extra Synty props under Dressing (see docs/SCENE_ASSEMBLY.md).
	builder = get_node_or_null("ShipBuilder")
	if builder == null:
		builder = ShipBuilder.new()
		builder.name = "ShipBuilder"
		add_child(builder)
	builder.build()
	_spawn_interactables()
	_spawn_display()
	_window_view()
	captain = Captain.new()
	captain.name = "Captain"
	add_child(captain)
	captain.teleport(builder.spawn + Vector3(0, 0.1, 0), builder.spawn_yaw)
	if AppFlow.params.has("spawn") and interactables.has(str(AppFlow.params["spawn"])):
		var it: Interactable = interactables[str(AppFlow.params["spawn"])]
		captain.teleport(it.global_position + Vector3(0, 0.1, 3.0), 0.0)
	hud = GameHud.new()
	add_child(hud)
	waypoints = WaypointLayer.new()
	add_child(waypoints)
	for id: String in interactables.keys():
		var wit: Interactable = interactables[id]
		waypoints.add_place(wit, WaypointLayer.nice(wit.title), 2.4 if id != "embryo_bank" else 3.8)
	captain.interact_target_changed.connect(func(t: Interactable) -> void: hud.set_prompt(t.prompt_text() + ("" if t.consequence.is_empty() or t.locked else "\n" + t.consequence) if t else ""))
	captain.hold_progress.connect(hud.set_hold)
	var vp := UiKit.panel(Vector2(300, 0))
	_voyage_label = UiKit.label("", 16)
	vp.add_child(_voyage_label)
	hud.top_right.add_child(vp)
	starmap = StarMapPanel.new()
	starmap.closed.connect(_panel_closed)
	starmap.travel_committed.connect(func(dest: String) -> void: AppFlow.goto("flight", {"destination": dest}))
	add_child(starmap)
	orbit = OrbitPanel.new()
	orbit.closed.connect(_panel_closed)
	orbit.expedition_requested.connect(func(_s: String) -> void: AppFlow.goto("surface"))
	orbit.landing_committed.connect(func(_s: String) -> void: AppFlow.goto("colony", {"landing": true}))
	add_child(orbit)
	embryo_panel = ArkPanels.EmbryoBankPanel.new()
	embryo_panel.closed.connect(_panel_closed)
	add_child(embryo_panel)
	workshop_panel = ArkPanels.WorkshopPanel.new()
	workshop_panel.closed.connect(_panel_closed)
	add_child(workshop_panel)
	GameSession.state_changed.connect(_on_state)
	_on_state("init")
	AudioService.set_ambience_any(["amb_ship_dark" if GameSession.state.ark.systems.get("power") == "offline" else "amb_ship_powered", "amb_ship_hum"])
	AudioService.set_music_any(["music_ark_alone"])
	GameSession.trigger_story("intro_wakeup")
	if GameSession.state.campaign.location_id != GameSession.content.start_location:
		GameSession.trigger_story("arrival_" + GameSession.state.campaign.location_id)


func _spawn_interactables() -> void:
	var defs := {
		"power_coupling": [Loc.t("the emergency power coupling"), Loc.t("Connect"), Loc.t("Restarts emergency power. The bridge, the embryo bank and the star map come online.")],
		"workbench": [Loc.t("the workbench"), Loc.t("Use"), Loc.t("Repair the hull with components. What you use here will be missing in the colony.")],
		"embryo_bank": [Loc.t("the embryo bank"), Loc.t("Examine"), Loc.t("View storage status and redundancy for the 50,000.")],
		"starmap": [Loc.t("the star map"), Loc.t("Open"), Loc.t("Compare candidate worlds, send probes and choose a route.")],
		"bridge_terminal": [Loc.t("the planet comparison"), Loc.t("Open"), Loc.t("Known and missing knowledge about all six worlds.")],
		"orbit_terminal": [Loc.t("the orbital terminal"), Loc.t("Open"), Loc.t("Scanning, site probes, expedition and landing.")],
	}
	for m: Dictionary in builder.interact_markers:
		var id := str(m["id"])
		var it := Interactable.new()
		it.name = "I_" + id
		it.interact_id = id
		var d: Array = defs.get(id, [id, Loc.t("Use"), ""])
		it.title = d[0]
		it.verb = d[1]
		it.consequence = d[2]
		it.radius = 2.2
		add_child(it)
		it.global_position = m["pos"]
		var v := VisualSlot.make(str(m["slot"]))
		v.rotation.y = float(m["yaw"])
		it.add_child(v)
		var sb := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(1.4, 1.6, 1.0) if id != "embryo_bank" else Vector3(3.2, 3.2, 3.2)
		if id == "starmap":
			bs.size = Vector3(2.8, 1.0, 2.8)
		cs.shape = bs
		cs.position.y = bs.size.y * 0.5
		sb.add_child(cs)
		it.add_child(sb)
		it.used.connect(_on_use)
		interactables[id] = it
		if id == "power_coupling":
			_coupling_beacon(it)


func _spawn_display() -> void:
	_display = Label3D.new()
	_display.text = "50.000"
	_display.font_size = 220
	_display.pixel_size = 0.01
	_display.modulate = Color("7fd6d0")
	_display.outline_size = 0
	_display.position = builder.embryo_display_pos + Vector3(0, 2.4, 0.2)
	add_child(_display)
	var sub := Label3D.new()
	sub.text = Loc.t("VIABLE EMBRYOS · CRYOPRESERVATION STABLE")
	sub.font_size = 48
	sub.pixel_size = 0.01
	sub.modulate = Color("8fa3ad")
	sub.position = _display.position + Vector3(0, -0.9, 0)
	add_child(sub)
	_ai = VisualSlot.make("char.ark_ai_hologram")
	_ai.position = builder.ai_pos
	add_child(_ai)
	if not _ai.using_asset and ResourceLoader.exists("res://assets/Synty/SciFiSpace/FBX/SM_Hud_Box_01.fbx"):
		# ARK as a hologram: a faceted core of light inside turning HUD rings (key-art look).
		for c: Node in _ai.get_children():
			c.queue_free()
		var core := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.28
		sm.height = 0.56
		sm.radial_segments = 6
		sm.rings = 3
		core.mesh = sm
		var cm := StandardMaterial3D.new()
		cm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		cm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		cm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		cm.albedo_color = Color(0.45, 1.0, 0.95, 0.9)
		core.material_override = cm
		core.position.y = 1.55
		_ai.add_child(core)
		var holo := Hologram.make(Color("#4ff6ff"), 1.5, 3)
		holo.position.y = 1.2
		_ai.add_child(holo)


func _window_view() -> void:
	# A candidate world outside the bridge windows once in orbit.
	_window_planet = Node3D.new()
	add_child(_window_planet)
	# The orbited world framed in the port bridge window (azimuth ~41 deg left of
	# the console, seen from the bridge centre): its curved limb crosses the
	# window strip. Before, it sat behind the wall between the windows.
	var eye := builder.cell_to_world(7.5, 3.6) + Vector3(0, 2.0, 0)
	var dir := Vector3(-sin(deg_to_rad(41.0)), 0, -cos(deg_to_rad(41.0)))
	_window_planet.position = eye + dir * 250.0 + Vector3(0, -80.0, 0)
	_window_planet.scale = Vector3.ONE * 1.6  # radius 96 m at 250 m: a big curved limb across the window


func _on_state(_kind: String) -> void:
	var gs: GameState = GameSession.state
	var powered: bool = gs.ark.systems.get("power") != "offline"
	builder.set_power(powered)
	_display.visible = powered
	for id: String in ["starmap", "bridge_terminal", "orbit_terminal", "embryo_bank"]:
		var it: Interactable = interactables.get(id)
		if it:
			it.locked = not powered
			it.locked_reason = Loc.t("no power — restore emergency power in the workshop")
	var orbit_it: Interactable = interactables.get("orbit_terminal")
	if orbit_it and powered:
		var pid := GameSession.sim.travel.current_planet_id(gs)
		orbit_it.locked = pid.is_empty()
		orbit_it.locked_reason = Loc.t("the Ark is not in orbit around a planet")
	var loc: Dictionary = GameSession.content.locations.get(gs.campaign.location_id, {})
	_voyage_label.text = Loc.t("%s\nFuel %d · Hull %d%% · Oxygen %d%% · Comp. %d\nEmbryos %s · Stasis %.1f yrs") % [
		str(loc.get("name", "")) + (Loc.t("  (orbit)") if loc.has("planet_id") else ""), int(gs.ark.fuel), int(gs.ark.integrity),
		int(gs.ark.oxygen), gs.ark.components, UiKit.thousands(gs.ark.embryo_viable), gs.campaign.captain_stasis_years]
	# NAV's standing alerts (fuel, oxygen, hull): said once per change, never spammed.
	for alert: Dictionary in GameSession.sim.nav.status(gs):
		hud.nav.say(alert)
	_update_waypoint()
	var pc: Interactable = interactables.get("power_coupling")
	if pc:
		pc.locked = powered
		pc.locked_reason = Loc.t("emergency power is running")
	UiKit.clear(_window_planet)
	var pid2 := GameSession.sim.travel.current_planet_id(gs)
	if not pid2.is_empty():
		var p := GameSession.content.planet(pid2)
		var v := VisualSlot.make("space.planet_" + str(p.get("biome_id")), str(p.get("palette", {}).get("nature", "")))
		_window_planet.add_child(v)
		PlanetLook.apply(v, str(p.get("biome_id")), str(p.get("palette", {}).get("nature", "")), hash(pid2))


func _on_use(it: Interactable) -> void:
	match it.interact_id:
		"power_coupling":
			GameSession.cmd_restore_power()
		"embryo_bank":
			GameSession.cmd_mark("embryo_bank_checked", "embryo_bank")
			_open(embryo_panel)
		"workbench":
			GameSession.cmd_mark("workshop_checked")
			_open(workshop_panel)
		"starmap":
			GameSession.cmd_mark("starmap_opened", "starmap_first")
			_open(starmap)
		"bridge_terminal":
			GameSession.cmd_mark("starmap_opened", "starmap_first")
			_open(starmap)
			starmap.tabs.current_tab = 1
		"orbit_terminal":
			GameSession.trigger_story("arrival_orbit")
			_open(orbit)


func _open(p: OverlayPanel) -> void:
	captain.set_active(false)
	hud.set_prompt("")
	p.open()


func _panel_closed() -> void:
	captain.set_active(true)


func _process(delta: float) -> void:
	_process_beacon(delta)
	_ai_t += delta
	_update_zone_audio()
	if _ai:
		_ai.position.y = builder.ai_pos.y + sin(_ai_t * 1.3) * 0.08
	if hud.any_modal_open() and captain.input_enabled:
		captain.set_active(false)
	elif not hud.any_modal_open() and not captain.input_enabled and not _any_panel():
		captain.set_active(true)


## Doorways hiss as the captain passes ('D' cells are where door modules go);
## the embryo bank adds its own quiet bed on top of the ship ambience.
func _update_zone_audio() -> void:
	if captain == null:
		return
	var z := builder.zone_at(captain.global_position)
	if z == _zone:
		return
	if z == "D":
		AudioService.play("sfx_door", "SFX", -8.0)
	_zone = z
	if z != "D":
		AudioService.set_layer("amb_embryo_bank" if z == "E" else "", -4.0)


## The objective marker points at the interactable named in objectives.json
## (targets.ship) for the current objective; nothing when it lives elsewhere.
func _update_waypoint() -> void:
	if waypoints == null:
		return
	var o := GameSession.sim.objectives.current(GameSession.state)
	var id := str(DictUtil.get_dict(o, "targets").get("ship", ""))
	var it: Interactable = interactables.get(id)
	waypoints.set_objective(it, str(o.get("title", "")) if it else "", 2.4 if id != "embryo_bank" else 3.8)


func _any_panel() -> bool:
	return starmap.visible or orbit.visible or embryo_panel.visible or workshop_panel.visible


## DEBUG/evidence hook used by DebugCapture (--action=...).
func debug_action(action: String) -> void:
	if action == "corridor":  # evidence: down the west leg of the ring corridor
		captain.teleport(builder._cell_center(1, 10), 0.0)
		return
	if action == "door_bridge":  # evidence: the corridor in front of the bridge door and its sign
		captain.teleport(builder._cell_center(9, 5), 0.75)
		captain.camera_rig.pitch = 0.0
		captain.camera_rig.snap()
		return
	if action == "coupling":  # evidence: the first goal in the dark workshop
		var it: Node3D = interactables.get("power_coupling")
		captain.teleport(it.global_position + Vector3(4.5, 0.1, 0.0), PI * 0.5)
		return
	if action == "window":  # evidence: the bridge windows from inside
		captain.teleport(builder.cell_to_world(7.5, 2.6), 0.0)
		captain.camera_rig.pitch = 0.05
		captain.camera_rig.snap()
		return
	if action.begins_with("room_"):  # evidence: stand at the south middle of a room, facing north (room_B, room_E, room_W, room_C)
		var want := action.trim_prefix("room_")
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		for r: int in builder.rows.size():
			for c: int in str(builder.rows[r]).length():
				if builder._zone(c, r) == want:
					lo = lo.min(Vector2(c, r))
					hi = hi.max(Vector2(c, r))
		if lo.x < INF:
			captain.teleport(builder.cell_to_world((lo.x + hi.x + 1.0) * 0.5 + 1.2, hi.y + 0.2), 0.0)
		return
	match action:
		"starmap":
			_open(starmap)
			starmap.map_view.selected = "ferrum"
			starmap._show_detail("ferrum")
		"compare":
			_open(starmap)
			starmap.tabs.current_tab = 1
		"orbit":
			_open(orbit)
		"embryo":
			_open(embryo_panel)
		"bridge":
			captain.teleport(interactables["starmap"].global_position + Vector3(2.5, 0.1, 5.0), 0.3)
		"embryo_room":
			captain.teleport(builder.embryo_display_pos + Vector3(-3.0, 0.1, 9.0), 0.0)
		"landing":
			_open(orbit)
			orbit._landing_site = str(GameSession.content.planet(GameSession.sim.travel.current_planet_id(GameSession.state))["site_templates"][0])
			orbit._landing_txn = "dbg"
			orbit.refresh()


func _exit_tree() -> void:
	ShipBuilder.set_strip_glow(true)  # the shared atlas is also used outside the ship


var _beacon: OmniLight3D
var _beacon_t := 0.0


## The first goal must read in the dark: a pulsing amber light and spark FX on
## the emergency coupling until power is restored (calm, no pulse with reduced motion).
func _coupling_beacon(it: Node3D) -> void:
	_beacon = OmniLight3D.new()
	_beacon.light_color = Color("ffb347")
	_beacon.light_energy = 2.0
	_beacon.omni_range = 4.5
	_beacon.position = Vector3(0, 1.4, 0)
	it.add_child(_beacon)
	var sparks := VisualSlot.make("fx.power_surge")
	sparks.position = Vector3(0, 1.1, 0)
	sparks.name = "CouplingSparks"
	it.add_child(sparks)


func _process_beacon(delta: float) -> void:
	if _beacon == null:
		return
	var off: bool = GameSession.state.ark.systems.get("power") == "offline"
	_beacon.visible = off
	var sp := _beacon.get_parent().get_node_or_null("CouplingSparks") as Node3D
	if sp:
		sp.visible = off
	if off and not FxEffect.reduced_motion():
		_beacon_t += delta
		_beacon.light_energy = 1.4 + 1.2 * (0.5 + 0.5 * sin(_beacon_t * 3.0))

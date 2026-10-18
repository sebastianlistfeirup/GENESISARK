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
var _window_planet: Node3D
var _voyage_label: Label


func _ready() -> void:
	if not GameSession.has_game():
		GameSession.new_campaign()
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("020407")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("26343c")
	e.ambient_light_energy = 0.35
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.glow_enabled = true
	e.glow_intensity = 0.6
	e.fog_enabled = true
	e.fog_light_color = Color("0b1219")
	e.fog_density = 0.01
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
		"power_coupling": [Loc.t("nødstrømskoblingen"), Loc.t("Tilslut"), Loc.t("Genstarter nødstrømmen. Broen, embryobanken og stjernekortet kommer online.")],
		"workbench": [Loc.t("værkstedsbænken"), Loc.t("Brug"), Loc.t("Reparér skroget med komponenter. Det, du bruger her, mangler i kolonien.")],
		"embryo_bank": ["embryobanken", Loc.t("Undersøg"), Loc.t("Se lagerstatus og redundans for de 50.000.")],
		"starmap": ["stjernekortet", Loc.t("Åbn"), Loc.t("Sammenlign kandidatverdener, send sonder og vælg rute.")],
		"bridge_terminal": ["planetsammenligningen", Loc.t("Åbn"), Loc.t("Kendt og manglende viden om alle seks verdener.")],
		"orbit_terminal": [Loc.t("kredsløbsterminalen"), Loc.t("Åbn"), Loc.t("Scanning, sitesonder, ekspedition og landing.")],
	}
	for m: Dictionary in builder.interact_markers:
		var id := str(m["id"])
		var it := Interactable.new()
		it.name = "I_" + id
		it.interact_id = id
		var d: Array = defs.get(id, [id, Loc.t("Brug"), ""])
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
	sub.text = Loc.t("LEVEDYGTIGE EMBRYONER · KRYOBEVARING STABIL")
	sub.font_size = 48
	sub.pixel_size = 0.01
	sub.modulate = Color("8fa3ad")
	sub.position = _display.position + Vector3(0, -0.9, 0)
	add_child(sub)
	_ai = VisualSlot.make("char.ark_ai_hologram")
	_ai.position = builder.ai_pos
	add_child(_ai)


func _window_view() -> void:
	# A candidate world outside the bridge windows once in orbit.
	_window_planet = Node3D.new()
	add_child(_window_planet)
	_window_planet.position = Vector3(0, -40, builder.origin.z - 220)


func _on_state(_kind: String) -> void:
	var gs: GameState = GameSession.state
	var powered: bool = gs.ark.systems.get("power") != "offline"
	builder.set_power(powered)
	_display.visible = powered
	for id: String in ["starmap", "bridge_terminal", "orbit_terminal", "embryo_bank"]:
		var it: Interactable = interactables.get(id)
		if it:
			it.locked = not powered
			it.locked_reason = Loc.t("ingen strøm — genopret nødstrømmen i værkstedet")
	var orbit_it: Interactable = interactables.get("orbit_terminal")
	if orbit_it and powered:
		var pid := GameSession.sim.travel.current_planet_id(gs)
		orbit_it.locked = pid.is_empty()
		orbit_it.locked_reason = Loc.t("arken er ikke i kredsløb om en planet")
	var loc: Dictionary = GameSession.content.locations.get(gs.campaign.location_id, {})
	_voyage_label.text = Loc.t("%s\nBrændstof %d · Skrog %d%% · Komp. %d\nEmbryoner %s · Stasis %.1f år") % [
		str(loc.get("name", "")) + (Loc.t("  (kredsløb)") if loc.has("planet_id") else ""), int(gs.ark.fuel), int(gs.ark.integrity),
		gs.ark.components, UiKit.thousands(gs.ark.embryo_viable), gs.campaign.captain_stasis_years]
	var pc: Interactable = interactables.get("power_coupling")
	if pc:
		pc.locked = powered
		pc.locked_reason = Loc.t("nødstrømmen kører")
	UiKit.clear(_window_planet)
	var pid2 := GameSession.sim.travel.current_planet_id(gs)
	if not pid2.is_empty():
		var p := GameSession.content.planet(pid2)
		var v := VisualSlot.make("space.planet_" + str(p.get("biome_id")), str(p.get("palette", {}).get("nature", "")))
		_window_planet.add_child(v)


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


func _any_panel() -> bool:
	return starmap.visible or orbit.visible or embryo_panel.visible or workshop_panel.visible


## DEBUG/evidence hook used by DebugCapture (--action=...).
func debug_action(action: String) -> void:
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

class_name OrbitPanel
extends OverlayPanel
## In orbit: orbital scan, site probes, expeditions and the landing decision
## with known risks, start stock, energy plan and the option to travel on.

signal expedition_requested(site_id: String)
signal landing_committed(site_id: String)

var _landing_site := ""
var _landing_txn := ""
var _drone := false


func _init() -> void:
	# Fixed width, height from the content: the landing preview is much shorter
	# than the site list and used to leave ~40 % of the panel blank.
	super(Vector2(1180, 0))


func refresh() -> void:
	UiKit.clear(body)
	_shrink_to_content()
	var content := GameSession.content
	var gs: GameState = GameSession.state
	var pid := GameSession.sim.travel.current_planet_id(gs)
	if pid.is_empty():
		header(Loc.t("Orbit"), Loc.t("The Ark is not in orbit around a planet. Use the star map to travel."))
		return
	var p := content.planet(pid)
	header(Loc.t("Orbiting %s") % p.get("name"), Loc.t("Components %d · Fuel %d · Hull %d%%") % [gs.ark.components, int(gs.ark.fuel), int(gs.ark.integrity)])
	if not _landing_site.is_empty():
		_landing_preview(pid, _landing_site)
		return
	var top := UiKit.hbox(16)
	var left := UiKit.vbox(8)
	left.custom_minimum_size = Vector2(520, 0)
	# The world below, live (D-046): the faceted planet with its moons, the Ark
	# parked on its orbit, satellites and traffic against the painted nebula.
	left.add_child(PlanetDiorama.framed(PlanetDiorama.make(pid, "orbit", Vector2i(520, 260)), str(p.get("name", ""))))
	left.add_child(UiKit.title(Loc.t("The planet")))
	left.add_child(StarMapPanel.knowledge_grid(pid))
	var k := gs.knowledge_of(pid)
	var scan := UiKit.button(Loc.t("Orbital scan (1 day)") if not k.level_reached.get("orbital_scan_done", false) else Loc.t("Orbital scan complete"), func() -> void:
		GameSession.cmd_orbital_scan(pid)
		refresh())
	scan.disabled = k.level_reached.get("orbital_scan_done", false)
	left.add_child(scan)
	top.add_child(left)
	var right := UiKit.vbox(10)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_child(UiKit.title(Loc.t("Landing sites")))
	var chk := CheckBox.new()
	chk.text = Loc.t("Plan drone reserve for the expedition (2 components, one refill)")
	chk.button_pressed = _drone
	chk.toggled.connect(func(on: bool) -> void: _drone = on)
	right.add_child(chk)
	for sid: Variant in DictUtil.get_arr(p, "site_templates"):
		right.add_child(_site_card(pid, str(sid)))
	top.add_child(right)
	body.add_child(top)


func _site_card(pid: String, sid: String) -> PanelContainer:
	var gs: GameState = GameSession.state
	var site := GameSession.content.site(sid)
	var k := gs.knowledge_of(pid)
	var card := UiKit.panel()
	var v := UiKit.vbox(4)
	var name_l := UiKit.label(str(site.get("name", sid)), 19, UiKit.AMBER)
	v.add_child(name_l)
	v.add_child(UiKit.label(str(site.get("description", "")), 14, UiKit.MUTED, true))
	var facts: Dictionary = k.site_facts.get(sid, {})
	var ft: Array = []
	for f: String in facts.keys():
		ft.append("%s: %s" % [Loc.t(str(FACT_LABELS.get(f, f))), _fact_text(f, facts[f].get("value"))])
	v.add_child(UiKit.label(Loc.t("Known: ") + (", ".join(ft) if not ft.is_empty() else Loc.t("nothing yet")), 14, UiKit.TEXT, true))
	if sid in k.expedition_sites:
		v.add_child(UiKit.label(Loc.t("● Explored by the captain"), 14, UiKit.OK))
	var row := UiKit.hbox(8)
	var probe := UiKit.button(Loc.t("Site probe (3)"), func() -> void:
		GameSession.cmd_probe(pid, sid)
		refresh(), Loc.t("Reveals water distance, heat source and exposure at this site."))
	probe.disabled = sid in k.probed_sites or gs.ark.components < 3
	row.add_child(probe)
	var ex := UiKit.button(Loc.t("Expedition"), func() -> void:
		var r := GameSession.cmd_start_expedition(sid, _drone)
		if r.ok:
			close()
			expedition_requested.emit(sid), Loc.t("The captain goes down in person: samples, relay and assessment of the landing site."))
	ex.disabled = sid in k.expedition_sites
	row.add_child(ex)
	row.add_child(UiKit.button(Loc.t("Prepare landing…"), func() -> void:
		_landing_site = sid
		_landing_txn = GameSession.txn("landing")
		refresh()))
	v.add_child(row)
	card.add_child(v)
	return card


func _landing_preview(pid: String, sid: String) -> void:
	var gs: GameState = GameSession.state
	var pv := GameSession.sim.landing.preview(gs, sid)
	var site := GameSession.content.site(sid)
	var v := UiKit.vbox(8)
	v.add_child(UiKit.heading(Loc.t("Landing: %s, %s") % [GameSession.content.planet(pid).get("name"), site.get("name")]))
	v.add_child(UiKit.label(Loc.t("Once the Ark lands, it becomes the colony's base. It cannot lift off again."), 17, UiKit.WARN, true))
	v.add_child(UiKit.rich(Loc.t("[color=#5fae6e]+[/color] %s\n[color=#e8a33d]−[/color] %s") % [pv.get("advantage", ""), pv.get("price", "")]))
	v.add_child(UiKit.title(Loc.t("Known risks")))
	for r: Variant in pv.get("known_risks", []):
		v.add_child(UiKit.label("▲ " + str(r), 15, UiKit.WARN, true))
	if (pv.get("known_risks", []) as Array).is_empty():
		v.add_child(UiKit.label(Loc.t("No mapped risks — that doesn't mean there are none."), 15, UiKit.MUTED, true))
	v.add_child(UiKit.title(Loc.t("Unknown")))
	for u: Variant in pv.get("unknowns", []):
		v.add_child(UiKit.label("✕ " + str(u), 15, UiKit.MUTED, true))
	var inv: Dictionary = pv.get("start_inventory", {})
	v.add_child(UiKit.title(Loc.t("Starting stock and energy")))
	v.add_child(UiKit.label(Loc.t("Building material %d · Components %d · Water %d person-days · Food %d person-days") % [int(inv.get("alloy", 0)), int(inv.get("components", 0)), int(inv.get("water", 0)), int(inv.get("food", 0))], 16))
	v.add_child(UiKit.label(str(pv.get("energy_plan", "")), 15, UiKit.TEXT, true))
	for reason: Variant in pv.get("reasons", []):
		v.add_child(UiKit.label("■ " + str(reason), 16, UiKit.DANGER, true))
	var row := UiKit.hbox(10)
	row.add_child(UiKit.button(Loc.t("Back — continue the voyage"), func() -> void:
		_landing_site = ""
		refresh()))
	var commit := UiKit.button(Loc.t("Confirm landing (final)"), func() -> void:
		var r := GameSession.cmd_commit_landing(sid, _landing_txn)
		if r.ok:
			close()
			landing_committed.emit(sid))
	commit.disabled = not pv["ok"]
	row.add_child(commit)
	v.add_child(row)
	body.add_child(v)


func close() -> void:
	_landing_site = ""
	super()


## A Control never shrinks on its own once it has grown: once the new page is
## laid out (wrapped labels know their width, so their height is right), drop
## to the content's height and re-centre.
func _shrink_to_content() -> void:
	if not is_inside_tree():
		return
	for i: int in 2:
		await get_tree().process_frame
	if not is_instance_valid(panel) or not visible:
		return
	panel.size = Vector2(panel.size.x, 0.0)  # clamped up to the combined minimum
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_KEEP_SIZE)
	fit()


const FACT_LABELS := {"water_distance_m": "water", "flatness": "flatness", "shelter": "shelter", "vent": "heat source",
	"exposure": "exposure", "landing_quality": "landing quality"}


static func _fact_text(f: String, v: Variant) -> String:
	if f == "water_distance_m":
		return "%d m" % int(v)
	if f == "vent":
		return Loc.t("yes") if v else Loc.t("no")
	if v is float or v is int:
		var x := float(v)
		return Loc.t("high") if x >= 0.7 else (Loc.t("medium") if x >= 0.4 else Loc.t("low"))
	return str(v)

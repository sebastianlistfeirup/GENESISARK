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
	super(Vector2(1180, 760))


func refresh() -> void:
	UiKit.clear(body)
	var content := GameSession.content
	var gs: GameState = GameSession.state
	var pid := GameSession.sim.travel.current_planet_id(gs)
	if pid.is_empty():
		header(Loc.t("Kredsløb"), Loc.t("Arken er ikke i kredsløb om en planet. Brug stjernekortet til at rejse."))
		return
	var p := content.planet(pid)
	header(Loc.t("Kredsløb om %s") % p.get("name"), Loc.t("Komponenter %d · Brændstof %d · Skrog %d%%") % [gs.ark.components, int(gs.ark.fuel), int(gs.ark.integrity)])
	if not _landing_site.is_empty():
		_landing_preview(pid, _landing_site)
		return
	var top := UiKit.hbox(16)
	var left := UiKit.vbox(8)
	left.custom_minimum_size = Vector2(520, 0)
	left.add_child(UiKit.title(Loc.t("Planeten")))
	left.add_child(StarMapPanel.knowledge_grid(pid))
	var k := gs.knowledge_of(pid)
	var scan := UiKit.button(Loc.t("Orbital scanning (1 dag)") if not k.level_reached.get("orbital_scan_done", false) else Loc.t("Orbital scanning udført"), func() -> void:
		GameSession.cmd_orbital_scan(pid)
		refresh())
	scan.disabled = k.level_reached.get("orbital_scan_done", false)
	left.add_child(scan)
	top.add_child(left)
	var right := UiKit.vbox(10)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_child(UiKit.title(Loc.t("Landingssites")))
	var chk := CheckBox.new()
	chk.text = Loc.t("Planlæg dronereserve til ekspeditionen (2 komponenter, én genopfyldning)")
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
	v.add_child(UiKit.label(Loc.t("Kendt: ") + (", ".join(ft) if not ft.is_empty() else Loc.t("intet endnu")), 14, UiKit.TEXT, true))
	if sid in k.expedition_sites:
		v.add_child(UiKit.label(Loc.t("● Udforsket af kaptajnen"), 14, UiKit.OK))
	var row := UiKit.hbox(8)
	var probe := UiKit.button(Loc.t("Sitesonde (3)"), func() -> void:
		GameSession.cmd_probe(pid, sid)
		refresh(), Loc.t("Afslører vandafstand, varmekilde og eksponering på dette site."))
	probe.disabled = sid in k.probed_sites or gs.ark.components < 3
	row.add_child(probe)
	var ex := UiKit.button(Loc.t("Ekspedition"), func() -> void:
		var r := GameSession.cmd_start_expedition(sid, _drone)
		if r.ok:
			close()
			expedition_requested.emit(sid), Loc.t("Kaptajnen går selv ned: prøver, relæ og vurdering af landingspladsen."))
	ex.disabled = sid in k.expedition_sites
	row.add_child(ex)
	row.add_child(UiKit.button(Loc.t("Forbered landing…"), func() -> void:
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
	v.add_child(UiKit.label(Loc.t("Når arken lander, bliver den koloniens base. Den kan ikke lette igen."), 17, UiKit.WARN, true))
	v.add_child(UiKit.rich(Loc.t("[color=#5fae6e]+[/color] %s\n[color=#e8a33d]−[/color] %s") % [pv.get("advantage", ""), pv.get("price", "")]))
	v.add_child(UiKit.title(Loc.t("Kendte risici")))
	for r: Variant in pv.get("known_risks", []):
		v.add_child(UiKit.label("▲ " + str(r), 15, UiKit.WARN, true))
	if (pv.get("known_risks", []) as Array).is_empty():
		v.add_child(UiKit.label(Loc.t("Ingen kortlagte risici — det betyder ikke, at der ingen er."), 15, UiKit.MUTED, true))
	v.add_child(UiKit.title(Loc.t("Ukendt")))
	for u: Variant in pv.get("unknowns", []):
		v.add_child(UiKit.label("✕ " + str(u), 15, UiKit.MUTED, true))
	var inv: Dictionary = pv.get("start_inventory", {})
	v.add_child(UiKit.title(Loc.t("Startlager og energi")))
	v.add_child(UiKit.label(Loc.t("Byggemateriale %d · Komponenter %d · Vand %d persondøgn · Mad %d persondøgn") % [int(inv.get("alloy", 0)), int(inv.get("components", 0)), int(inv.get("water", 0)), int(inv.get("food", 0))], 16))
	v.add_child(UiKit.label(str(pv.get("energy_plan", "")), 15, UiKit.TEXT, true))
	for reason: Variant in pv.get("reasons", []):
		v.add_child(UiKit.label("■ " + str(reason), 16, UiKit.DANGER, true))
	var row := UiKit.hbox(10)
	row.add_child(UiKit.button(Loc.t("Tilbage — fortsæt rejsen"), func() -> void:
		_landing_site = ""
		refresh()))
	var commit := UiKit.button(Loc.t("Bekræft landing (endelig)"), func() -> void:
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


const FACT_LABELS := {"water_distance_m": "vand", "flatness": "fladhed", "shelter": "læ", "vent": "varmekilde",
	"exposure": "eksponering", "landing_quality": "landingskvalitet"}


static func _fact_text(f: String, v: Variant) -> String:
	if f == "water_distance_m":
		return "%d m" % int(v)
	if f == "vent":
		return Loc.t("ja") if v else Loc.t("nej")
	if v is float or v is int:
		var x := float(v)
		return Loc.t("høj") if x >= 0.7 else (Loc.t("middel") if x >= 0.4 else Loc.t("lav"))
	return str(v)

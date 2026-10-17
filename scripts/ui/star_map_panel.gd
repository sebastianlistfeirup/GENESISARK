class_name StarMapPanel
extends OverlayPanel
## Bridge star map (bible p.6-8): compare candidates, send probes, choose a
## route with all costs and the minimum reserve shown BEFORE committing.
## Emits travel_committed so the scene can play the approach.

signal travel_committed(destination: String)

var tabs: TabContainer
var map_view: StarMapView
var detail: VBoxContainer
var compare_box: VBoxContainer
var _pending_txn := ""
var _confirming := false


func _init() -> void:
	super(Vector2(1240, 760))


func refresh() -> void:
	UiKit.clear(body)
	var gs: GameState = GameSession.state
	header("Stjernekort", "Brændstof %d · Skrog %d%% · Komponenter %d · Position: %s" % [
		int(gs.ark.fuel), int(gs.ark.integrity), gs.ark.components, GameSession.content.locations.get(gs.campaign.location_id, {}).get("name", "")])
	tabs = TabContainer.new()
	tabs.custom_minimum_size = Vector2(1200, 640)
	body.add_child(tabs)
	var map_tab := UiKit.hbox(14)
	map_tab.name = "Rejse"
	map_view = StarMapView.new()
	map_view.planet_selected.connect(func(loc: String) -> void:
		_confirming = false
		_show_detail(loc))
	map_tab.add_child(map_view)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(640, 600)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	detail = UiKit.vbox(8)
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(detail)
	map_tab.add_child(scroll)
	tabs.add_child(map_tab)
	var cmp_scroll := ScrollContainer.new()
	cmp_scroll.name = "Sammenligning"
	compare_box = UiKit.vbox(6)
	compare_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cmp_scroll.add_child(compare_box)
	tabs.add_child(cmp_scroll)
	_build_compare()
	if map_view.selected.is_empty():
		detail.add_child(UiKit.label("Vælg en verden på kortet.", 18, UiKit.MUTED))
		detail.add_child(UiKit.label("Kendte værdier og usikkerheder vises separat. En sonde koster 3 komponenter og indsnævrer arkivets skøn. At rejse koster brændstof og slider på skroget.", 16, UiKit.MUTED, true))
	else:
		_show_detail(map_view.selected)


func _show_detail(loc: String) -> void:
	UiKit.clear(detail)
	var content := GameSession.content
	var gs: GameState = GameSession.state
	var pid := str(content.locations.get(loc, {}).get("planet_id", ""))
	var p := content.planet(pid)
	detail.add_child(UiKit.heading(str(p.get("name", loc))))
	detail.add_child(UiKit.label(str(p.get("description", "")), 16, UiKit.MUTED, true))
	detail.add_child(UiKit.rich("[color=#5fae6e]+[/color] %s\n[color=#e8a33d]−[/color] %s" % [p.get("advantage", ""), p.get("price", "")]))
	detail.add_child(UiKit.title("Viden"))
	detail.add_child(knowledge_grid(pid))
	detail.add_child(UiKit.title("Rute"))
	var q := GameSession.sim.travel.quote(gs, loc)
	if q.has("fuel"):
		detail.add_child(UiKit.rich("Brændstof [b]%d[/b] (efter: %d) · Skrog −%d%% · %d dage i stasis\nReserve til nærmeste alternativ: %s" % [
			int(q["fuel"]), int(q["fuel_after"]), int(q["integrity"]), int(q["days"]),
			("[color=#5fae6e]● ok (%d krævet)[/color]" % int(q["reserve_needed"])) if q["reserve_ok"] else ("[color=#e8a33d]▲ for lav (%d krævet)[/color]" % int(q["reserve_needed"]))]))
	for reason: Variant in q.get("reasons", []):
		detail.add_child(UiKit.label("■ " + str(reason), 16, UiKit.DANGER, true))
	for reason: Variant in q.get("risk_reasons", []):
		detail.add_child(UiKit.label("▲ " + str(reason), 16, UiKit.WARN, true))
	var row := UiKit.hbox(10)
	var k := gs.knowledge_of(pid)
	var probe := UiKit.button("Send fjernsonde (3 komponenter)", func() -> void:
		if GameSession.cmd_probe(pid, "").ok:
			_show_detail(loc)
			_build_compare(),
		"Indsnævrer arkivets skøn om %s uden at rejse." % p.get("name"))
	probe.disabled = k.level_reached.has("orbital") or gs.ark.components < 3 or gs.campaign.phase != CampaignState.PHASE_VOYAGE
	row.add_child(probe)
	var travel := UiKit.button("Bekræft risikabel rejse" if _confirming else "Rejs hertil", func() -> void: _travel(loc, q))
	travel.disabled = not q["ok"]
	row.add_child(travel)
	detail.add_child(row)
	if _confirming:
		detail.add_child(UiKit.label("Tryk igen for at bekræfte. Rejsen kan ikke fortrydes.", 15, UiKit.WARN, true))


func _travel(loc: String, q: Dictionary) -> void:
	if _pending_txn.is_empty():
		_pending_txn = GameSession.txn("travel")
	if q["risky"] and not _confirming:
		_confirming = true
		_show_detail(loc)
		return
	var r := GameSession.cmd_travel(loc, q["risky"], _pending_txn)
	if r.ok:
		_pending_txn = ""
		_confirming = false
		close()
		travel_committed.emit(loc)
	elif r.code != "duplicate_txn":
		_pending_txn = ""


## Known / estimated / unknown, each with its source (bible p.7, p.13).
static func knowledge_grid(pid: String) -> GridContainer:
	var g := GridContainer.new()
	g.columns = 3
	g.add_theme_constant_override("h_separation", 14)
	var cmp := GameSession.sim.survey.comparison(GameSession.state, pid)
	var rows: Dictionary = cmp["rows"]
	for prop: String in SurveyService.PROPERTY_LABELS.keys():
		if not rows.has(prop):
			continue
		var r: Dictionary = rows[prop]
		var status := str(r["status"])
		var kind: String = {"known": "ok", "estimated": "warning", "unknown": "locked"}[status]
		var l1 := UiKit.label(SurveyService.PROPERTY_LABELS[prop], 15, UiKit.MUTED)
		l1.custom_minimum_size = Vector2(170, 0)
		g.add_child(l1)
		var l2 := UiKit.label("%s %s" % [UiKit.status_icon(kind), r["text"]], 16, UiKit.status_color(kind))
		l2.custom_minimum_size = Vector2(220, 0)
		g.add_child(l2)
		g.add_child(UiKit.label({"known": "kendt", "estimated": "skøn", "unknown": "ukendt"}[status] + ("" if str(r["source"]).is_empty() else " · " + str(r["source"])), 13, UiKit.MUTED))
	return g


func _build_compare() -> void:
	if compare_box == null:
		return
	UiKit.clear(compare_box)
	var content := GameSession.content
	compare_box.add_child(UiKit.label("Kendt viden og manglende viden vises i hver sin kolonne. Ingen verden er bedst i alt.", 16, UiKit.MUTED, true))
	var g := GridContainer.new()
	g.columns = 4
	g.add_theme_constant_override("h_separation", 18)
	g.add_theme_constant_override("v_separation", 10)
	for h: String in ["Verden", "Kendt", "Skøn", "Mangler"]:
		g.add_child(UiKit.title(h))
	for pid: String in content.planet_ids_sorted():
		var cmp := GameSession.sim.survey.comparison(GameSession.state, pid)
		var known: Array = []
		var est: Array = []
		var unk: Array = []
		for prop: String in (cmp["rows"] as Dictionary).keys():
			var r: Dictionary = cmp["rows"][prop]
			var lbl := "%s: %s" % [SurveyService.PROPERTY_LABELS.get(prop, prop), r["text"]]
			match str(r["status"]):
				"known": known.append(lbl)
				"estimated": est.append(lbl)
				_: unk.append(SurveyService.PROPERTY_LABELS.get(prop, prop))
		var p := content.planet(pid)
		var name_box := UiKit.vbox(2)
		name_box.add_child(UiKit.label(str(p.get("name")), 20, Color(str(p.get("palette", {}).get("nature", "#ffffff")))))
		name_box.add_child(UiKit.label(str(p.get("tagline", "")), 13, UiKit.MUTED, true))
		name_box.custom_minimum_size = Vector2(220, 0)
		g.add_child(name_box)
		for arr: Array in [known, est, unk]:
			var l := UiKit.label("\n".join(arr) if not arr.is_empty() else "—", 14, UiKit.TEXT, true)
			l.custom_minimum_size = Vector2(300, 0)
			g.add_child(l)
	compare_box.add_child(g)

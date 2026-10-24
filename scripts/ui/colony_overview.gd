class_name ColonyOverview
extends OverlayPanel
## Colony overview: supply chain, population & incubation, and the future:
## generation leaps (forecast -> approve), council and hand-over.
## Holo dashboards (D-059), every number read from the domain report:
##   Supply     - power flow (production vs consumption bars, the Ark's share,
##                balance, battery as a ring), power by priority with cut-offs,
##                water and food in/out with the reserve as a ring in days,
##                bottlenecks as cards, drones and stable days as chips.
##   Population - living / adults / children / in incubation as readouts, the
##                embryo ledger strip, an age pyramid of the cohorts, cohort
##                cards (health, education, gestation), the incubation action.
##   Future     - the population chart (now, the path to the year-40 goal,
##                the forecast once calculated), the leap with its forecast
##                card, council and trust/autonomy meters, the hand-over.

signal leap_committed
signal handover_committed

var _forecast: Dictionary = {}
var _target := 0
## Forecasts run on a copy of the state in a worker thread (RISKS R4), so the
## UI keeps drawing. Commands stay on the main thread.
var _thread: Thread
var _computing := false
var _tabs: TabContainer
var _focus: Control


func _init() -> void:
	super(Vector2(1180, 760))


func focus_target() -> Control:
	return _focus if is_instance_valid(_focus) else _close_btn


func refresh() -> void:
	var keep := _tabs.current_tab if is_instance_valid(_tabs) else 0
	UiKit.clear(body)
	var gs: GameState = GameSession.state
	var p := GameSession.content.planet(gs.colony.planet_id)
	header(Loc.t("The colony on %s") % p.get("name"), Loc.t("Year %.1f · day %d · %s") % [gs.campaign.colony_year(), gs.campaign.colony_day, GameSession.content.site(gs.colony.site_id).get("name", "")], "ui.icon_planet",
		[["ui.icon_population", Loc.t("%d people") % gs.population.alive_count(), UiKit.FOOD], ["ui.icon_embryo", UiKit.thousands(gs.ark.embryo_viable), UiKit.PETROL.lightened(0.35)]])
	_tabs = TabContainer.new()
	_tabs.custom_minimum_size = Vector2(1140, 640)
	body.add_child(_tabs)
	_tabs.add_child(_supply_tab())
	_tabs.add_child(_population_tab())
	_tabs.add_child(_future_tab())
	var icons := ["ui.icon_power", "ui.icon_population", "ui.icon_time"]
	for i: int in 3:
		_tabs.set_tab_title(i, "  " + _tabs.get_tab_title(i).to_upper())
		var tex := SyntySkin.icon(str(icons[i]), 40)
		if tex:
			_tabs.set_tab_icon(i, tex)
			_tabs.set_tab_icon_max_width(i, 20)
	_tabs.current_tab = keep
	if not _forecast.is_empty() or _computing:
		_tabs.current_tab = 2
	_tabs.tab_changed.connect(func(_t: int) -> void: AudioService.ui("ui_click"))
	_focus = _tabs.get_tab_bar()
	regrab_focus.call_deferred()


## Evidence / navigation: show a tab (0 supply, 1 population, 2 future).
func show_tab(t: int) -> void:
	if is_instance_valid(_tabs):
		_tabs.current_tab = clampi(t, 0, 2)


func _scroll(name: String) -> Array:
	var s := ScrollContainer.new()
	s.name = name
	s.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 4)
	m.add_theme_constant_override("margin_right", 12)
	m.add_theme_constant_override("margin_top", 6)
	m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := UiKit.vbox(12)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	m.add_child(v)
	s.add_child(m)
	return [s, v]


## A dashboard card with a section title; returns [card, inner vbox].
func _card(title: String, icon_slot: String, accent: Color = UiKit.PETROL) -> Array:
	var c := Holo.card(accent)
	var v := UiKit.vbox(8)
	if not title.is_empty():
		v.add_child(UiKit.section(title, icon_slot))
	c.add_child(v)
	return [c, v]


func _supply_tab() -> Control:
	var sv := _scroll(Loc.t("Supply"))
	var v: VBoxContainer = sv[1]
	var gs: GameState = GameSession.state
	var sim: Simulation = GameSession.sim
	var rep: Dictionary = gs.colony.last_report
	var pw: Dictionary = rep.get("power", {})
	var produced := float(pw.get("produced_kw", 0))
	var ark := float(pw.get("ark_kw", 0))
	var demand := float(pw.get("demand_kw", 0))
	var surplus := float(pw.get("surplus_kw", 0))
	var bat := int(pw.get("battery_kwh", 0))
	var cap := int(pw.get("battery_capacity", 0))
	var row := UiKit.hbox(12)
	# --- Power ---
	var pc := _card(Loc.t("Power"), "ui.icon_power", UiKit.OK if surplus >= 0.0 else UiKit.DANGER)
	var pv: VBoxContainer = pc[1]
	var ph := UiKit.hbox(18)
	var ring := ProgressRing.make(float(bat) / maxf(float(cap), 1.0), "", Loc.t("Battery kWh"), UiKit.PETROL.lightened(0.25), 128, float(bat))
	ph.add_child(ring)
	var flow := UiKit.vbox(8)
	flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var scale := maxf(maxf(produced, demand), 1.0) * 1.1
	flow.add_child(_flow_bar(Loc.t("Production"), produced, scale, UiKit.OK, Loc.t("Ark %.1f") % ark, ark))
	flow.add_child(_flow_bar(Loc.t("Consumption"), demand, scale, UiKit.PETROL.lightened(0.3)))
	var bal := UiKit.hbox(10)
	var kind := "ok" if surplus >= 0.0 else "critical"
	bal.add_child(UiKit.status_glyph(kind, 20))
	var bl := UiKit.label(Loc.t("Balance %+.1f kW") % surplus, 22, UiKit.OK if surplus >= 0.0 else UiKit.DANGER.lightened(0.2))
	bl.add_theme_font_override("font", UiKit.display_font())
	bal.add_child(bl)
	bal.add_child(UiKit.label(Loc.t("Battery %d / %d kWh") % [bat, cap], 15, UiKit.MUTED))
	if pw.get("storm", false):
		bal.add_child(Holo.chip(Loc.t("Storm"), UiKit.WARN, "ui.icon_wind", 12))
	if pw.get("night", false):
		bal.add_child(Holo.chip(Loc.t("Night"), UiKit.PETROL.lightened(0.3), "ui.icon_time", 12))
	flow.add_child(bal)
	ph.add_child(flow)
	pv.add_child(ph)
	# Power by priority (who gets power first), with cut-offs.
	var hz := sim.colony.hazard_factors(gs, gs.campaign.colony_day)
	var prio_rows := UiKit.vbox(4)
	var maxkw := 0.01
	var prio_data: Array = []
	for prio: String in GameSession.content.building_priorities:
		var names: Array = []
		var kw := 0.0
		var cut := 0
		for b: Dictionary in gs.colony.buildings:
			if b.get("state") != ColonyState.B_ACTIVE:
				continue
			var def := GameSession.content.building(str(b["def_id"]))
			var k := sim.colony.building_power_kw(gs, b, hz)
			if k < 0.0 and str(def.get("priority")) == prio:
				names.append(str(def.get("name")))
				kw -= k
				if not b.get("powered"):
					cut += 1
		maxkw = maxf(maxkw, kw)
		prio_data.append([prio, names, kw, cut])
	var rank := 1
	for d: Array in prio_data:
		prio_rows.add_child(_prio_row(rank, str(d[0]), d[1], float(d[2]), int(d[3]), maxkw))
		rank += 1
	pv.add_child(prio_rows)
	row.add_child(pc[0])
	# --- Water and food ---
	var wc := _card(Loc.t("Water and food"), "ui.icon_water", UiKit.WATER)
	var wv: VBoxContainer = wc[1]
	(wc[0] as Control).custom_minimum_size = Vector2(390, 0)
	(wc[0] as Control).size_flags_horizontal = Control.SIZE_FILL
	var need: Dictionary = rep.get("need", {})
	var prod: Dictionary = rep.get("produced", {})
	var rd := float(rep.get("reserve_days", 9999))
	var wh := UiKit.hbox(14)
	var rtxt := "∞" if rd >= 9999 else str(int(rd))
	var rcol := UiKit.WARN if rd < 30 else UiKit.FOOD
	wh.add_child(ProgressRing.make(1.0 if rd >= 9999 else clampf(rd / 90.0, 0.0, 1.0), rtxt, Loc.t("Reserve days"), rcol, 112))
	var io := UiKit.vbox(10)
	io.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	io.add_child(_io_row("ui.icon_water", Loc.t("Water"), float(prod.get("water", 0)), float(need.get("water", 0)), UiKit.WATER, int(gs.colony.inventory.get("water", 0))))
	io.add_child(_io_row("ui.icon_food", Loc.t("Food"), float(prod.get("food", 0)), float(need.get("food", 0)), UiKit.FOOD, int(gs.colony.inventory.get("food", 0))))
	wh.add_child(io)
	wv.add_child(wh)
	wv.add_child(UiKit.label(Loc.t("Water +%.0f / −%.0f per day · Food +%.0f / −%.0f per day · Reserve: %s days") % [float(prod.get("water", 0)), float(need.get("water", 0)), float(prod.get("food", 0)), float(need.get("food", 0)), rtxt], 13, UiKit.MUTED, true))
	row.add_child(wc[0])
	v.add_child(row)
	# --- Bottlenecks ---
	# --- Stores (what the colony holds right now) ---
	var sc := _card(Loc.t("Stores"), "ui.icon_building", UiKit.PETROL)
	var sh := UiKit.hbox(26)
	var inv: Dictionary = gs.colony.inventory
	sh.add_child(Holo.big_readout("ui.icon_alloy", Loc.t("Building material"), "", UiKit.PETROL.lightened(0.3), "", float(inv.get("alloy", 0))))
	sh.add_child(Holo.big_readout("ui.icon_components", Loc.t("Components"), "", UiKit.PETROL.lightened(0.3), "", float(inv.get("components", 0))))
	sh.add_child(Holo.big_readout("ui.icon_water", Loc.t("Water"), "", UiKit.WATER, "", float(inv.get("water", 0))))
	sh.add_child(Holo.big_readout("ui.icon_food", Loc.t("Food"), "", UiKit.FOOD, "", float(inv.get("food", 0))))
	sh.add_child(Holo.big_readout("ui.icon_fuel", Loc.t("Ark fuel"), "", UiKit.AMBER, "", float(gs.colony.ark_fuel)))
	(sc[1] as VBoxContainer).add_child(sh)
	v.add_child(sc[0])
	var bn: Array = rep.get("bottlenecks", [])
	var bc := _card(Loc.t("Bottlenecks"), "ui.icon_bottleneck", UiKit.WARN if not bn.is_empty() else UiKit.OK)
	var bv: VBoxContainer = bc[1]
	if bn.is_empty():
		bv.add_child(Holo.bullet("ui.icon_ok", Loc.t("● None. All completed buildings are running."), UiKit.OK, "●", 16))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	for x: Dictionary in bn:
		grid.add_child(_bottleneck(x))
	if not bn.is_empty():
		bv.add_child(grid)
	var foot := UiKit.hbox(8)
	foot.add_child(Holo.chip(Loc.t("Drones %.1f") % float(rep.get("drones", 0)), UiKit.PETROL.lightened(0.35), "prop.drone", 12))
	foot.add_child(Holo.chip(Loc.t("Stable days in a row: %d") % int(gs.colony.stats.get("days_stable", 0)), UiKit.OK, "ui.icon_ok", 12))
	bv.add_child(foot)
	v.add_child(bc[0])
	return sv[0]


## One flow bar: caption + value, a long bar on a shared kW scale; an optional
## highlighted share (the Ark's emergency power inside production).
func _flow_bar(caption: String, kw: float, scale: float, col: Color, share_text: String = "", share: float = 0.0) -> Control:
	var v := UiKit.vbox(3)
	var h := UiKit.hbox(8)
	var c := UiKit.label(caption.to_upper(), 12, UiKit.MUTED)
	c.add_theme_font_override("font", UiKit.display_variant(1))
	h.add_child(c)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(sp)
	if not share_text.is_empty() and share > 0.0:
		h.add_child(Holo.chip(share_text + " kW", UiKit.AMBER, "ui.icon_ship", 11))
	var val := UiKit.label("%.1f kW" % kw, 18, col.lightened(0.3))
	val.add_theme_font_override("font", UiKit.display_font())
	h.add_child(val)
	v.add_child(h)
	var bar := _Bar.new()
	bar.frac = kw / scale
	bar.share = share / scale
	bar.col = col
	bar.custom_minimum_size = Vector2(0, 16)
	v.add_child(bar)
	return v


class _Bar extends Control:
	var frac := 0.0
	var share := 0.0
	var col := UiKit.OK
	var _k := 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_k = 1.0 if UiKit.calm() else 0.0

	func _process(delta: float) -> void:
		if _k < 1.0:
			_k = minf(1.0, _k + delta * 1.8)
			queue_redraw()

	func _draw() -> void:
		var w := size.x
		var h := size.y
		draw_rect(Rect2(0, 0, w, h), Color(0.02, 0.05, 0.07, 1.0), true)
		var e := ease(_k, 0.3)
		var fw := w * clampf(frac, 0.0, 1.0) * e
		draw_rect(Rect2(0, 2, fw, h - 4), Color(col, 0.8), true)
		draw_rect(Rect2(0, 2, fw, 3), Color(col.lightened(0.4), 0.9), true)
		if share > 0.0:
			var sw := w * clampf(share, 0.0, 1.0) * e
			draw_rect(Rect2(fw - sw, 2, sw, h - 4), Color(UiKit.AMBER, 0.75), true)
			draw_line(Vector2(fw - sw, 0), Vector2(fw - sw, h), Color(0, 0, 0, 0.8), 2.0)
		for t: int in 11:
			draw_line(Vector2(w * t / 10.0, h - 4), Vector2(w * t / 10.0, h), Color(0, 0, 0, 0.6), 1.0)
		draw_rect(Rect2(0, 0, w, h), Color(UiKit.PETROL.lightened(0.2), 0.35), false, 1.0)


## A priority row: rank, status glyph, name, a bar of its share, kW, who draws it, cut-offs.
func _prio_row(rank: int, prio: String, names: Array, kw: float, cut: int, maxkw: float) -> Control:
	var h := UiKit.hbox(10)
	var rk := UiKit.label(str(rank), 16, UiKit.AMBER)
	rk.add_theme_font_override("font", UiKit.display_font())
	rk.custom_minimum_size = Vector2(16, 0)
	h.add_child(rk)
	h.add_child(UiKit.status_glyph("critical" if cut > 0 else "ok", 16))
	var nm := UiKit.label(Loc.t(str(ColonySimulation.PRIORITY_LABELS.get(prio, prio))), 15, UiKit.TEXT)
	nm.add_theme_font_override("font", UiKit.bold_font())
	nm.custom_minimum_size = Vector2(110, 0)
	h.add_child(nm)
	h.add_child(Holo.meter(kw / maxkw if maxkw > 0.0 else 0.0, 10, UiKit.DANGER if cut > 0 else UiKit.PETROL.lightened(0.2), 110))
	var k := UiKit.label("%.1f kW" % kw, 14, UiKit.TEXT)
	k.custom_minimum_size = Vector2(62, 0)
	h.add_child(k)
	var who := UiKit.label(", ".join(names) if not names.is_empty() else Loc.t("none"), 13, UiKit.MUTED)
	who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	who.clip_text = true
	who.tooltip_text = who.text
	who.mouse_filter = Control.MOUSE_FILTER_PASS
	h.add_child(who)
	if cut > 0:
		h.add_child(Holo.chip(Loc.t("%d cut off") % cut, UiKit.DANGER, "ui.icon_warning", 11))
	return h


## Water or food: glyph, in / out per day with the net as an arrow, stock.
func _io_row(icon_slot: String, caption: String, inflow: float, outflow: float, col: Color, stock: int) -> Control:
	var h := UiKit.hbox(10)
	h.add_child(IconBadge.make(icon_slot, 34, col, false, "◆"))
	var v := UiKit.vbox(0)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var t := UiKit.hbox(6)
	var c := UiKit.label(caption.to_upper(), 12, UiKit.MUTED)
	c.add_theme_font_override("font", UiKit.display_variant(1))
	t.add_child(c)
	var net := inflow - outflow
	var arrow := "ui.icon_arrow_up" if net >= 0.0 else "ui.icon_arrow_down"
	var ac := UiKit.OK if net >= 0.0 else UiKit.WARN
	var ai := UiKit.icon_rect(arrow, 14, ac)
	if ai:
		t.add_child(ai)
	t.add_child(UiKit.label(("▲ " if net >= 0.0 else "▼ ") + "%+.0f / %s" % [net, Loc.t("day")], 13, ac))
	v.add_child(t)
	var n := UiKit.label("+%.0f  −%.0f" % [inflow, outflow], 20, col.lightened(0.3))
	n.add_theme_font_override("font", UiKit.display_font())
	v.add_child(n)
	v.add_child(UiKit.label(Loc.t("Stock %d person-days") % stock, 12, UiKit.MUTED))
	h.add_child(v)
	return h


func _bottleneck(x: Dictionary) -> Control:
	var c := Holo.card(UiKit.WARN, 10)
	c.custom_minimum_size = Vector2(340, 0)
	var h := UiKit.hbox(10)
	var did := str(x["def_id"])
	h.add_child(IconBadge.make("build." + did, 38, UiKit.WARN, false, "▲"))
	var v := UiKit.vbox(2)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var nm := UiKit.label(str(GameSession.content.building(did).get("name")), 15, UiKit.TEXT, true)
	nm.add_theme_font_override("font", UiKit.bold_font())
	v.add_child(nm)
	v.add_child(UiKit.label("▲ " + str(x["text"]), 14, UiKit.WARN.lightened(0.2), true))
	h.add_child(v)
	c.add_child(h)
	return c


func _population_tab() -> Control:
	var sv := _scroll(Loc.t("Population"))
	var v: VBoxContainer = sv[1]
	var gs: GameState = GameSession.state
	var l := gs.ark.ledger()
	var alive := gs.population.alive_count()
	var adults := gs.population.adult_workforce()
	var kids := gs.population.count_stage("child")
	var goal := int(GameSession.content.bal("campaign_goal.population", 500))
	var top := UiKit.hbox(12)
	var rc := _card("", "", UiKit.FOOD)
	var rh := UiKit.hbox(22)
	rh.add_child(ProgressRing.make(float(alive) / maxf(goal, 1.0), "", Loc.t("Living"), UiKit.FOOD, 116, float(alive)))
	var rv := UiKit.vbox(10)
	rv.alignment = BoxContainer.ALIGNMENT_CENTER
	rv.add_child(Holo.big_readout("ui.icon_population", Loc.t("Adults"), "", UiKit.PETROL.lightened(0.2), Loc.t("Work, build and decide."), float(adults)))
	rv.add_child(Holo.big_readout("ui.icon_heart", Loc.t("Children"), "", UiKit.AMBER, Loc.t("Children do not work."), float(kids)))
	rh.add_child(rv)
	var rv2 := UiKit.vbox(10)
	rv2.alignment = BoxContainer.ALIGNMENT_CENTER
	rv2.add_child(Holo.big_readout("ui.icon_embryo", Loc.t("In incubation"), "", UiKit.AMBER.lightened(0.1), "", float(l["incubating"])))
	rv2.add_child(Holo.big_readout("ui.icon_trophy", Loc.t("Goal for year 40"), "", UiKit.MUTED.lightened(0.2), Loc.t("at least %d people") % goal, float(goal)))
	rh.add_child(rv2)
	(rc[1] as VBoxContainer).add_child(rh)
	(rc[1] as VBoxContainer).add_child(UiKit.label(Loc.t("Population (living): %d · Adults: %d · Children: %d") % [alive, adults, kids], 13, UiKit.MUTED))
	top.add_child(rc[0])
	var pyr := _card(Loc.t("Age pyramid"), "ui.icon_population", UiKit.PETROL)
	(pyr[0] as Control).custom_minimum_size = Vector2(420, 0)
	(pyr[0] as Control).size_flags_horizontal = Control.SIZE_FILL
	var ap := _Pyramid.new()
	ap.custom_minimum_size = Vector2(380, 196)
	ap.rows = _age_rows(gs)
	(pyr[1] as VBoxContainer).add_child(ap)
	top.add_child(pyr[0])
	v.add_child(top)
	var led := _card(Loc.t("Embryo ledger (always 50,000)"), "ui.icon_embryo", UiKit.AMBER)
	(led[1] as VBoxContainer).add_child(LedgerStrip.panel(l, gs.ark.embryo_sum(), true))
	(led[1] as VBoxContainer).add_child(UiKit.label(Loc.t("Viable %s · In incubation %s · Born %s · Lost %s") % [UiKit.thousands(l["viable"]), UiKit.thousands(l["incubating"]), UiKit.thousands(l["born"]), UiKit.thousands(l["lost"])], 13, UiKit.MUTED))
	v.add_child(led[0])
	var cc := _card(Loc.t("Cohorts"), "ui.icon_population", UiKit.PETROL)
	var cv: VBoxContainer = cc[1]
	if gs.population.cohorts.is_empty():
		cv.add_child(Holo.bullet("ui.icon_info", Loc.t("None yet. The first cohort requires a care center, +5 kW surplus and 30 days of water and food reserves."), UiKit.PETROL.lightened(0.3), "i", 15, UiKit.MUTED.lightened(0.1)))
	var cg := GridContainer.new()
	cg.columns = 2
	cg.add_theme_constant_override("h_separation", 10)
	cg.add_theme_constant_override("v_separation", 8)
	for c: Dictionary in gs.population.cohorts:
		cg.add_child(_cohort(c))
	cv.add_child(cg)
	v.add_child(cc[0])
	var ic := _card(Loc.t("Incubation"), "ui.icon_time", UiKit.AMBER)
	var iv: VBoxContainer = ic[1]
	var size := int(GameSession.content.bal("incubation.cohort_size", 10))
	var blockers := GameSession.sim.population.incubation_blockers(gs, size)
	var b := GlowButton.make(Loc.t("Start incubation of %d embryos") % size, "ui.icon_embryo", "go", func() -> void:
		GameSession.cmd_start_incubation(size)
		refresh())
	b.disabled = not blockers.is_empty()
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	b.custom_minimum_size = Vector2(440, 50)
	iv.add_child(b)
	for bl: Variant in blockers:
		iv.add_child(Holo.bullet("ui.icon_locked", str(bl), UiKit.MUTED, "✕", 14, UiKit.MUTED.lightened(0.1)))
	v.add_child(ic[0])
	return sv[0]


## Cohorts by age band (years), children and adults apart; incubating at the bottom.
func _age_rows(gs: GameState) -> Array:
	var bands := [[0, 3, "0–2"], [3, 6, "3–5"], [6, 10, "6–9"], [10, 15, "10–14"], [15, 20, "15–19"], [20, 30, "20–29"], [30, 999, "30+"]]
	var rows: Array = []
	for bd: Array in bands:
		rows.append({"label": str(bd[2]), "child": 0, "adult": 0})
	var inc := 0
	for c: Dictionary in gs.population.cohorts:
		var st := str(c.get("stage", ""))
		if st == "incubating":
			inc += int(c.get("size", 0))
			continue
		var yrs := float(c.get("age_days", 0)) / 365.0
		for i: int in bands.size():
			if yrs >= float(bands[i][0]) and yrs < float(bands[i][1]):
				rows[i]["child" if st == "child" else "adult"] = int(rows[i]["child" if st == "child" else "adult"]) + int(c.get("size", 0))
	rows.reverse()
	rows.append({"label": Loc.t("unborn"), "child": 0, "adult": 0, "inc": inc})
	return rows


class _Pyramid extends Control:
	var rows: Array = []
	var _k := 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_k = 1.0 if UiKit.calm() else 0.0

	func _process(delta: float) -> void:
		if _k < 1.0:
			_k = minf(1.0, _k + delta * 1.6)
			queue_redraw()

	func _draw() -> void:
		var font := UiKit.display_variant(1)
		var mx := 1
		for r: Dictionary in rows:
			mx = maxi(mx, int(r.get("child", 0)) + int(r.get("adult", 0)) + int(r.get("inc", 0)))
		var lw := 52.0
		var cw := (size.x - lw - 40.0)
		var cx := lw + cw * 0.5
		var rh := size.y / maxf(rows.size(), 1)
		var e := ease(_k, 0.3)
		draw_line(Vector2(cx, 0), Vector2(cx, size.y), Color(UiKit.PETROL, 0.35), 1.0)
		for i: int in rows.size():
			var r: Dictionary = rows[i]
			var y := i * rh
			var ch := int(r.get("child", 0))
			var ad := int(r.get("adult", 0))
			var inc := int(r.get("inc", 0))
			var tot := ch + ad + inc
			var half := cw * 0.5 * float(tot) / mx * e
			var lbl := str(r["label"])
			draw_string(font, Vector2(lw - 6 - font.get_string_size(lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x, y + rh * 0.5 + 4), lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UiKit.MUTED)
			draw_rect(Rect2(lw, y + 2, cw, rh - 4), Color(0.02, 0.05, 0.07, 0.6), true)
			if tot > 0:
				var col := UiKit.PETROL.lightened(0.25) if ad >= ch else UiKit.AMBER
				if inc > 0:
					col = UiKit.AMBER.darkened(0.25)
				var rect := Rect2(cx - half, y + 3, half * 2.0, rh - 6)
				draw_rect(rect, Color(col, 0.8 if inc == 0 else 0.45), true)
				if ch > 0 and ad > 0:  # children share as the brighter core
					var chw := half * 2.0 * float(ch) / tot
					draw_rect(Rect2(cx - chw * 0.5, y + 3, chw, rh - 6), Color(UiKit.AMBER, 0.85), true)
				draw_rect(Rect2(rect.position, Vector2(rect.size.x, 2)), Color(col.lightened(0.4), 0.9), true)
				var t := str(tot)
				draw_string(font, Vector2(cx + half + 6, y + rh * 0.5 + 4), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UiKit.TEXT)
		# Key (colour + word).
		for k: int in 2:
			var kc := UiKit.PETROL.lightened(0.25) if k == 0 else UiKit.AMBER
			var kt := Loc.t("adults") if k == 0 else Loc.t("children")
			var kw := font.get_string_size(kt, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
			draw_rect(Rect2(size.x - kw - 16, 2 + k * 14, 9, 9), kc, true)
			draw_string(font, Vector2(size.x - kw - 3, 11 + k * 14), kt, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, UiKit.MUTED)


## One cohort as a compact card: size and stage, age, health and education
## meters, or the gestation progress while incubating.
func _cohort(c: Dictionary) -> Control:
	var stage := str(c["stage"])
	var col := UiKit.AMBER if stage != "adult" else UiKit.PETROL.lightened(0.25)
	var card := Holo.card(col, 10)
	card.custom_minimum_size = Vector2(530, 0)
	var h := UiKit.hbox(10)
	var icon := "ui.icon_embryo" if stage == "incubating" else ("ui.icon_heart" if stage == "child" else "ui.icon_population")
	h.add_child(IconBadge.make(icon, 36, col, false, "◆"))
	var v := UiKit.vbox(3)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if stage == "incubating":
		var gd := int(GameSession.content.bal("incubation.gestation_days", 270))
		var txt := Loc.t("Cohort %d · %d embryos · incubation %d/%d days%s") % [c["id"], c["size"], int(c["gestation_days"]), gd, Loc.t(" · ▲ stalled") if int(c.get("stalled_days", 0)) > 0 else ""]
		v.add_child(UiKit.label(txt, 15, UiKit.TEXT, true))
		var bar := _Bar.new()
		bar.frac = float(c["gestation_days"]) / maxf(gd, 1.0)
		bar.col = UiKit.AMBER
		bar.custom_minimum_size = Vector2(0, 10)
		v.add_child(bar)
	else:
		var txt := Loc.t("Cohort %d · %d %s · %.1f yrs · health %d%% · education %d%%") % [c["id"], c["size"], Loc.t("children") if stage == "child" else Loc.t("adults"), float(c["age_days"]) / 365.0, int(float(c["health"]) * 100), int(float(c.get("education", 0)) * 100)]
		v.add_child(UiKit.label(txt, 15, UiKit.TEXT, true))
		var mh := UiKit.hbox(8)
		mh.add_child(UiKit.label(Loc.t("Health"), 12, UiKit.MUTED))
		mh.add_child(Holo.meter(float(c["health"]), 10, UiKit.OK if float(c["health"]) > 0.6 else UiKit.WARN, 110))
		mh.add_child(UiKit.label(Loc.t("Education"), 12, UiKit.MUTED))
		mh.add_child(Holo.meter(float(c.get("education", 0)), 10, UiKit.PETROL.lightened(0.3), 110))
		v.add_child(mh)
	h.add_child(v)
	card.add_child(h)
	return card


func _future_tab() -> Control:
	var sv := _scroll(Loc.t("Future"))
	var v: VBoxContainer = sv[1]
	var gs: GameState = GameSession.state
	var sim: Simulation = GameSession.sim
	var y := gs.campaign.colony_year()
	var goal := int(GameSession.content.bal("campaign_goal.population", 500))
	var top := UiKit.hbox(12)
	# --- Population chart ---
	var chc := _card(Loc.t("Population outlook"), "ui.icon_population", UiKit.FOOD)
	var chart := HoloChart.new()
	chart.custom_minimum_size = Vector2(560, 230)
	chart.x_range = Vector2(0, 40)
	var pop := float(gs.population.alive_count())
	var top_y := float(goal)
	if not _forecast.is_empty():
		top_y = maxf(top_y, float(_forecast["population_end"]))
	chart.y_max = ceilf(top_y * 1.15 / 50.0) * 50.0
	for xl: int in [0, 10, 20, 30, 40]:
		chart.x_labels.append([xl, Loc.t("Y%d") % xl])
	chart.bands.append([float(goal), chart.y_max, UiKit.AMBER, Loc.t("Goal: %d people") % goal])
	chart.add_marker(20.0, Loc.t("Handover possible"), UiKit.PETROL.lightened(0.35))
	chart.add_series([Vector2(y, pop), Vector2(40, goal)], UiKit.AMBER, Loc.t("Path to the goal"), true)
	if not _forecast.is_empty():
		var f := _forecast
		chart.add_series([Vector2(float(f["start_day"]) / 365.0, float(f["population_start"])), Vector2(float(f["end_year"]), float(f["population_end"]))], UiKit.FOOD, Loc.t("Forecast"), false, true)
		chart.add_point(Vector2(float(f["end_year"]), float(f["population_end"])), str(int(f["population_end"])), UiKit.FOOD)
	chart.add_point(Vector2(y, pop), Loc.t("Now: %d") % int(pop), Color.WHITE)
	(chc[1] as VBoxContainer).add_child(chart)
	top.add_child(chc[0])
	# --- Generation leap ---
	var lc := _card(Loc.t("Generation leap"), "ui.icon_time", UiKit.AMBER)
	(lc[0] as Control).custom_minimum_size = Vector2(500, 0)
	var lv: VBoxContainer = lc[1]
	lv.add_child(Holo.bullet("ui.icon_embryo", Loc.t("Plan: approx. %d births a year, cohorts of %d, construction as needed.") % [int(ChoiceRules.births_per_year(GameSession.content, gs, float(EraService.default_plan(20)["births_per_year"]))), int(EraService.default_plan(20)["cohort_size"])], UiKit.AMBER, "◆", 15))
	lv.add_child(UiKit.label(Loc.t("A leap is a forecast, not a fast-forward button. The simulator calculates supply, aging, work and planned events day by day, and stops before an unresolved crisis or a deficit. ARK and the colony's institutions carry daily life according to the plan: incubation when conditions allow, construction as needed."), 13, UiKit.MUTED, true))
	_target = 20 if y < 20.0 else 40
	var blockers := sim.era.leap_blockers(gs)
	var fb := GlowButton.make(Loc.t("Calculating forecast…") if _computing else Loc.t("Calculate forecast to year %d") % _target, "ui.icon_time", "primary", _start_forecast)
	fb.disabled = not blockers.is_empty() or y >= 40.0 or _computing
	lv.add_child(fb)
	if _computing:
		HoloAnim.pulse.call_deferred(fb, 0.3, 0.8)
	for bl: Variant in blockers:
		lv.add_child(Holo.bullet("ui.icon_locked", str(bl), UiKit.MUTED, "✕", 14, UiKit.MUTED.lightened(0.1)))
	top.add_child(lc[0])
	v.add_child(top)
	if not fb.disabled:
		_focus = fb
	# --- Forecast result ---
	if not _forecast.is_empty():
		var f := _forecast
		var builds := {}
		var incs := 0
		for a: Dictionary in f.get("actions", []):
			if a.get("action") == "build":
				builds[str(a["def_id"])] = int(builds.get(str(a["def_id"]), 0)) + 1
			else:
				incs += 1
		var bl: Array = []
		for k: String in builds.keys():
			bl.append("%d× %s" % [builds[k], GameSession.content.building(k).get("name")])
		var ok: bool = f["stop_reason"] == EraService.STOP_TARGET
		var fc := _card("", "", UiKit.OK if ok else UiKit.WARN)
		var fv: VBoxContainer = fc[1]
		var fh := UiKit.hbox(10)
		fh.add_child(IconBadge.make("ui.icon_time", 40, UiKit.AMBER, true, "◆"))
		var ft := UiKit.label(Loc.t("Forecast: year %.1f → year %.1f (%d days)") % [float(f["start_day"]) / 365.0, float(f["end_year"]), int(f["days"])], 20, UiKit.AMBER)
		ft.add_theme_font_override("font", UiKit.display_font())
		ft.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		fh.add_child(ft)
		fh.add_child(Holo.chip(Loc.t("Reaches the target") if ok else Loc.t("Stops early"), UiKit.OK if ok else UiKit.WARN, "ui.icon_ok" if ok else "ui.icon_warning", 12))
		fv.add_child(fh)
		fv.add_child(UiKit.label(UiKit.status_icon("ok" if ok else "warning") + " " + str(f["stop_text"]) + ("  " + str(f.get("stop_detail", "")) if not str(f.get("stop_detail", "")).is_empty() else ""), 16, UiKit.OK if ok else UiKit.WARN, true))
		var tiles := UiKit.hbox(22)
		tiles.add_child(Holo.big_readout("ui.icon_population", Loc.t("Population"), "%d → %d" % [int(f["population_start"]), int(f["population_end"])], UiKit.FOOD))
		tiles.add_child(Holo.big_readout("ui.icon_heart", Loc.t("Births"), "", UiKit.AMBER, "", float(f["births"])))
		tiles.add_child(Holo.big_readout("ui.icon_population", Loc.t("Adults"), "", UiKit.PETROL.lightened(0.25), "", float(f["adults"])))
		tiles.add_child(Holo.big_readout("ui.icon_reserve", Loc.t("Reserve"), ("∞" if float(f["reserve_days"]) >= 9999 else str(int(float(f["reserve_days"])))) + " " + Loc.t("days"), UiKit.WATER))
		tiles.add_child(Holo.big_readout("ui.icon_fuel", Loc.t("Ark fuel"), str(f["ark_fuel"]), UiKit.AMBER))
		fv.add_child(tiles)
		fv.add_child(UiKit.label(Loc.t("Population %d → %d · births %d · adults %d · reserve %s days · Ark fuel %s") % [int(f["population_start"]), int(f["population_end"]), int(f["births"]), int(f["adults"]),
			"∞" if float(f["reserve_days"]) >= 9999 else str(int(float(f["reserve_days"]))), str(f["ark_fuel"])], 13, UiKit.MUTED, true))
		fv.add_child(UiKit.label(Loc.t("The plan: %d incubations · construction: %s") % [incs, ", ".join(bl) if not bl.is_empty() else Loc.t("none")], 15, UiKit.TEXT, true))
		var ab := GlowButton.make(Loc.t("Approve the plan and leap"), "ui.icon_play", "go", func() -> void:
			var r := GameSession.cmd_era_leap(_target)
			_forecast = {}
			if r.ok:
				close()
				leap_committed.emit())
		ab.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		ab.custom_minimum_size = Vector2(420, 54)
		ab.set_filled()
		fv.add_child(ab)
		_focus = ab
		v.add_child(fc[0])
	# --- Council and handover ---
	var cc := _card(Loc.t("Council and handover"), "ui.icon_council", Color("c9a0ff"))
	var cv: VBoxContainer = cc[1]
	var ch := UiKit.hbox(18)
	ch.add_child(Holo.chip(Loc.t("Council: %s") % (Loc.t("convened") if gs.society.council_formed else Loc.t("not convened")), UiKit.OK if gs.society.council_formed else UiKit.MUTED, "ui.icon_council", 13))
	ch.add_child(_dial(Loc.t("Trust"), gs.society.trust, UiKit.OK, float(GameSession.content.bal("trust_effects.low", 35)), float(GameSession.content.bal("trust_effects.high", 65))))
	ch.add_child(_dial(Loc.t("Autonomy"), gs.society.autonomy, Color("c9a0ff")))
	cv.add_child(ch)
	cv.add_child(UiKit.label(Loc.t("Council: %s · Trust %d · Autonomy %d") % [Loc.t("convened") if gs.society.council_formed else Loc.t("not convened"), int(gs.society.trust), int(gs.society.autonomy)], 13, UiKit.MUTED))
	_choice_lines(cv, gs)
	var m := sim.endings.metrics(gs)
	var prof := sim.endings.profile_for(m)
	var ec := Holo.card(UiKit.AMBER, 10)
	var eh := UiKit.hbox(12)
	eh.add_child(IconBadge.make("ui.icon_trophy", 40, UiKit.AMBER, false, "★"))
	var ev := UiKit.vbox(2)
	ev.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var cap := UiKit.label(Loc.t("If you hand over now").to_upper(), 11, UiKit.MUTED)
	cap.add_theme_font_override("font", UiKit.display_variant(2))
	ev.add_child(cap)
	ev.add_child(UiKit.label(Loc.t("If you hand over now: %s — %s") % [GameSession.content.endings.get(prof, {}).get("title", prof), GameSession.content.endings.get(prof, {}).get("criteria_text", "")], 15, UiKit.TEXT, true))
	eh.add_child(ev)
	ec.add_child(eh)
	cv.add_child(ec)
	cv.add_child(UiKit.label(Loc.t("Goal for year 40: at least %d people, a working council, its own power without the Ark and at least %d days of reserves.") % [goal, int(GameSession.content.bal("campaign_goal.min_reserve_days", 60))], 14, UiKit.MUTED, true))
	var hb := GlowButton.make(Loc.t("Hand over the colony (ends the campaign)"), "ui.icon_flag", "danger", func() -> void:
		if GameSession.cmd_handover().ok:
			close()
			handover_committed.emit())
	hb.disabled = y < 20.0
	hb.tooltip_text = Loc.t("Possible from year 20. The ending reflects the colony's actual resilience.")
	hb.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	hb.custom_minimum_size = Vector2(520, 50)
	cv.add_child(hb)
	if hb.disabled:
		cv.add_child(Holo.bullet("ui.icon_locked", hb.tooltip_text, UiKit.MUTED, "✕", 13, UiKit.MUTED))
	v.add_child(cc[0])
	return sv[0]


## A 0-100 dial as a labelled bar with its zones (trust: low / high marks).
func _dial(caption: String, value: float, col: Color, low: float = NAN, high: float = NAN) -> Control:
	var v := UiKit.vbox(2)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var h := UiKit.hbox(8)
	var c := UiKit.label(caption.to_upper(), 12, UiKit.MUTED)
	c.add_theme_font_override("font", UiKit.display_variant(1))
	h.add_child(c)
	var n := UiKit.label(str(int(value)), 18, col.lightened(0.3))
	n.add_theme_font_override("font", UiKit.display_font())
	h.add_child(n)
	v.add_child(h)
	var rb := RangeBar.new()
	rb.setup(0.0, 100.0, "known", value, value)
	rb.col = col
	rb.live = false
	if not is_nan(low):
		rb.ideal = Vector2(low, high)
	rb.custom_minimum_size = Vector2(220, 18)
	v.add_child(rb)
	return v


## R9: why the colony behaves as it does now: the chosen course and the trust dial.
func _choice_lines(v: VBoxContainer, gs: GameState) -> void:
	var content: ContentDB = GameSession.content
	var why := ChoiceRules.trust_explanation(content, gs)
	if not why.is_empty():
		var band := ChoiceRules.trust_band(content, gs)
		v.add_child(Holo.bullet("ui.icon_arrow_down" if band == "low" else "ui.icon_arrow_up", ("▼ " if band == "low" else "▲ ") + why, UiKit.WARN if band == "low" else UiKit.OK, "▲", 15, UiKit.WARN if band == "low" else UiKit.OK))
	var prio := ChoiceRules.active_priority(gs)
	if prio.is_empty():
		return
	var d := ChoiceRules.describe(content, prio)
	var names := {"expansion": Loc.t("expansion"), "safety": Loc.t("safety"), "self_determination": Loc.t("self-determination")}
	v.add_child(Holo.bullet("crest." + prio, Loc.t("Course: %s. Gain: %s. Price: %s.") % [names.get(prio, prio), ", ".join(d["gain"]), ", ".join(d["price"])], UiKit.AMBER, "◆", 15))


func _start_forecast() -> void:
	if _computing:
		return
	_computing = true
	GameSession.set_colony_speed(0)
	_thread = Thread.new()
	var target := _target
	_thread.start(func() -> Dictionary: return GameSession.era_forecast(target))
	refresh()


func _process(_delta: float) -> void:
	if _computing and _thread and not _thread.is_alive():
		_forecast = _thread.wait_to_finish()
		_thread = null
		_computing = false
		refresh()


func close() -> void:
	if _computing:
		return  # Let the forecast finish; it only touches a copy.
	_forecast = {}
	super()

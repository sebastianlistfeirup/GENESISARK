class_name ColonyOverview
extends OverlayPanel
## Colony overview: supply chain, population & incubation, and the future:
## generation leaps (forecast -> approve), council and hand-over.

signal leap_committed
signal handover_committed

var _forecast: Dictionary = {}
var _target := 0
## Forecasts run on a copy of the state in a worker thread (RISKS R4), so the
## UI keeps drawing. Commands stay on the main thread.
var _thread: Thread
var _computing := false


func _init() -> void:
	super(Vector2(1180, 760))


func refresh() -> void:
	UiKit.clear(body)
	var gs: GameState = GameSession.state
	var p := GameSession.content.planet(gs.colony.planet_id)
	header(Loc.t("The colony on %s") % p.get("name"), Loc.t("Year %.1f · day %d · %s") % [gs.campaign.colony_year(), gs.campaign.colony_day, GameSession.content.site(gs.colony.site_id).get("name", "")])
	var tabs := TabContainer.new()
	tabs.custom_minimum_size = Vector2(1140, 640)
	body.add_child(tabs)
	tabs.add_child(_supply_tab())
	tabs.add_child(_population_tab())
	tabs.add_child(_future_tab())
	if not _forecast.is_empty():
		tabs.current_tab = 2


func _scroll(name: String) -> Array:
	var s := ScrollContainer.new()
	s.name = name
	s.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var v := UiKit.vbox(8)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.add_child(v)
	return [s, v]


func _supply_tab() -> Control:
	var sv := _scroll(Loc.t("Supply"))
	var v: VBoxContainer = sv[1]
	var gs: GameState = GameSession.state
	var sim: Simulation = GameSession.sim
	var rep: Dictionary = gs.colony.last_report
	var pw: Dictionary = rep.get("power", {})
	v.add_child(UiKit.title(Loc.t("Power")))
	v.add_child(UiKit.label(Loc.t("Production %.1f kW (Ark %.1f) · Consumption %.1f kW · Balance %+.1f kW · Battery %d / %d kWh%s%s") % [
		float(pw.get("produced_kw", 0)), float(pw.get("ark_kw", 0)), float(pw.get("demand_kw", 0)), float(pw.get("surplus_kw", 0)),
		int(pw.get("battery_kwh", 0)), int(pw.get("battery_capacity", 0)), Loc.t(" · STORM") if pw.get(Loc.t("storm"), false) else "", Loc.t(" · NIGHT") if pw.get("night", false) else ""], 16, UiKit.TEXT, true))
	var hz := sim.colony.hazard_factors(gs, gs.campaign.colony_day)
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
		v.add_child(UiKit.rich(Loc.t("%s [b]%s[/b]: %.1f kW — %s%s") % [UiKit.status_icon("critical" if cut > 0 else "ok"), Loc.t(str(ColonySimulation.PRIORITY_LABELS.get(prio, prio))), kw,
			", ".join(names) if not names.is_empty() else Loc.t("none"), (Loc.t("  [color=#d25b4c]%d cut off[/color]") % cut) if cut > 0 else ""]))
	v.add_child(UiKit.title(Loc.t("Water and food")))
	var need: Dictionary = rep.get("need", {})
	var prod: Dictionary = rep.get("produced", {})
	v.add_child(UiKit.label(Loc.t("Water +%.0f / −%.0f per day · Food +%.0f / −%.0f per day · Reserve: %s days") % [float(prod.get("water", 0)), float(need.get("water", 0)), float(prod.get("food", 0)), float(need.get("food", 0)),
		"∞" if float(rep.get("reserve_days", 9999)) >= 9999 else str(int(float(rep.get("reserve_days", 0))))], 16))
	v.add_child(UiKit.title(Loc.t("Bottlenecks")))
	var bn: Array = rep.get("bottlenecks", [])
	if bn.is_empty():
		v.add_child(UiKit.label(Loc.t("● None. All completed buildings are running."), 16, UiKit.OK))
	for x: Dictionary in bn:
		v.add_child(UiKit.label("▲ %s: %s" % [GameSession.content.building(str(x["def_id"])).get("name"), x["text"]], 15, UiKit.WARN, true))
	v.add_child(UiKit.label(Loc.t("Drones: %.1f · Stable days in a row: %d") % [float(rep.get("drones", 0)), int(gs.colony.stats.get("days_stable", 0))], 15, UiKit.MUTED))
	return sv[0]


func _population_tab() -> Control:
	var sv := _scroll(Loc.t("Population"))
	var v: VBoxContainer = sv[1]
	var gs: GameState = GameSession.state
	var l := gs.ark.ledger()
	v.add_child(UiKit.title(Loc.t("Embryo ledger (always 50,000)")))
	v.add_child(UiKit.label(Loc.t("Viable %s · In incubation %s · Born %s · Lost %s") % [UiKit.thousands(l["viable"]), UiKit.thousands(l["incubating"]), UiKit.thousands(l["born"]), UiKit.thousands(l["lost"])], 17))
	v.add_child(UiKit.label(Loc.t("Population (living): %d · Adults: %d · Children: %d") % [gs.population.alive_count(), gs.population.adult_workforce(), gs.population.count_stage("child")], 17))
	v.add_child(UiKit.title(Loc.t("Cohorts")))
	if gs.population.cohorts.is_empty():
		v.add_child(UiKit.label(Loc.t("None yet. The first cohort requires a care center, +5 kW surplus and 30 days of water and food reserves."), 15, UiKit.MUTED, true))
	for c: Dictionary in gs.population.cohorts:
		var stage := str(c["stage"])
		var txt := ""
		if stage == "incubating":
			txt = Loc.t("Cohort %d · %d embryos · incubation %d/%d days%s") % [c["id"], c["size"], int(c["gestation_days"]), int(GameSession.content.bal("incubation.gestation_days", 270)), Loc.t(" · ▲ stalled") if int(c.get("stalled_days", 0)) > 0 else ""]
		else:
			txt = Loc.t("Cohort %d · %d %s · %.1f yrs · health %d%% · education %d%%") % [c["id"], c["size"], Loc.t("children") if stage == "child" else Loc.t("adults"), float(c["age_days"]) / 365.0, int(float(c["health"]) * 100), int(float(c.get("education", 0)) * 100)]
		v.add_child(UiKit.label(txt, 15))
	v.add_child(UiKit.title(Loc.t("Incubation")))
	var size := int(GameSession.content.bal("incubation.cohort_size", 10))
	var blockers := GameSession.sim.population.incubation_blockers(gs, size)
	var b := UiKit.button(Loc.t("Start incubation of %d embryos") % size, func() -> void:
		GameSession.cmd_start_incubation(size)
		refresh())
	b.disabled = not blockers.is_empty()
	v.add_child(b)
	for bl: Variant in blockers:
		v.add_child(UiKit.label("✕ " + str(bl), 15, UiKit.MUTED, true))
	return sv[0]


func _future_tab() -> Control:
	var sv := _scroll(Loc.t("Future"))
	var v: VBoxContainer = sv[1]
	var gs: GameState = GameSession.state
	var sim: Simulation = GameSession.sim
	var y := gs.campaign.colony_year()
	v.add_child(UiKit.title(Loc.t("Generation leap")))
	v.add_child(UiKit.label(Loc.t("Plan: approx. %d births a year, cohorts of %d, construction as needed.") % [int(EraService.default_plan(20)["births_per_year"]), int(EraService.default_plan(20)["cohort_size"])], 15, UiKit.TEXT, true))
	v.add_child(UiKit.label(Loc.t("A leap is a forecast, not a fast-forward button. The simulator calculates supply, aging, work and planned events day by day, and stops before an unresolved crisis or a deficit. ARK and the colony's institutions carry daily life according to the plan: incubation when conditions allow, construction as needed."), 15, UiKit.MUTED, true))
	_target = 20 if y < 20.0 else 40
	var blockers := sim.era.leap_blockers(gs)
	var row := UiKit.hbox(10)
	var fb := UiKit.button(Loc.t("Calculating forecast…") if _computing else Loc.t("Calculate forecast to year %d") % _target, _start_forecast)
	fb.disabled = not blockers.is_empty() or y >= 40.0 or _computing
	row.add_child(fb)
	v.add_child(row)
	for bl: Variant in blockers:
		v.add_child(UiKit.label("✕ " + str(bl), 15, UiKit.MUTED, true))
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
		var fp := UiKit.panel()
		var fv := UiKit.vbox(4)
		fv.add_child(UiKit.label(Loc.t("Forecast: year %.1f → year %.1f (%d days)") % [float(f["start_day"]) / 365.0, float(f["end_year"]), int(f["days"])], 18, UiKit.AMBER))
		fv.add_child(UiKit.label(UiKit.status_icon("ok" if f["stop_reason"] == EraService.STOP_TARGET else "warning") + " " + str(f["stop_text"]) + ("  " + str(f.get("stop_detail", "")) if not str(f.get("stop_detail", "")).is_empty() else ""), 16, UiKit.OK if f["stop_reason"] == EraService.STOP_TARGET else UiKit.WARN, true))
		fv.add_child(UiKit.label(Loc.t("Population %d → %d · births %d · adults %d · reserve %s days · Ark fuel %s") % [int(f["population_start"]), int(f["population_end"]), int(f["births"]), int(f["adults"]),
			"∞" if float(f["reserve_days"]) >= 9999 else str(int(float(f["reserve_days"]))), str(f["ark_fuel"])], 16, UiKit.TEXT, true))
		fv.add_child(UiKit.label(Loc.t("The plan: %d incubations · construction: %s") % [incs, ", ".join(bl) if not bl.is_empty() else Loc.t("none")], 15, UiKit.MUTED, true))
		fv.add_child(UiKit.button(Loc.t("Approve the plan and leap"), func() -> void:
			var r := GameSession.cmd_era_leap(_target)
			_forecast = {}
			if r.ok:
				close()
				leap_committed.emit()))
		fp.add_child(fv)
		v.add_child(fp)
	v.add_child(UiKit.title(Loc.t("Council and handover")))
	v.add_child(UiKit.label(Loc.t("Council: %s · Trust %d · Autonomy %d") % ["samlet" if gs.society.council_formed else Loc.t("not convened"), int(gs.society.trust), int(gs.society.autonomy)], 16))
	var m := sim.endings.metrics(gs)
	var prof := sim.endings.profile_for(m)
	v.add_child(UiKit.label(Loc.t("If you hand over now: %s — %s") % [GameSession.content.endings.get(prof, {}).get("title", prof), GameSession.content.endings.get(prof, {}).get("criteria_text", "")], 15, UiKit.TEXT, true))
	v.add_child(UiKit.label(Loc.t("Goal for year 40: at least %d people, a working council, its own power without the Ark and at least %d days of reserves.") % [int(GameSession.content.bal("campaign_goal.population", 500)), int(GameSession.content.bal("campaign_goal.min_reserve_days", 60))], 14, UiKit.MUTED, true))
	var hb := UiKit.button(Loc.t("Hand over the colony (ends the campaign)"), func() -> void:
		if GameSession.cmd_handover().ok:
			close()
			handover_committed.emit())
	hb.disabled = y < 20.0
	hb.tooltip_text = Loc.t("Possible from year 20. The ending reflects the colony's actual resilience.")
	v.add_child(hb)
	return sv[0]


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

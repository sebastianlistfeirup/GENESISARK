class_name ColonyOverview
extends OverlayPanel
## Colony overview: supply chain, population & incubation, and the future:
## generation leaps (forecast -> approve), council and hand-over.

signal leap_committed
signal handover_committed

var _forecast: Dictionary = {}
var _target := 0


func _init() -> void:
	super(Vector2(1180, 760))


func refresh() -> void:
	UiKit.clear(body)
	var gs: GameState = GameSession.state
	var p := GameSession.content.planet(gs.colony.planet_id)
	header("Kolonien på %s" % p.get("name"), "År %.1f · dag %d · %s" % [gs.campaign.colony_year(), gs.campaign.colony_day, GameSession.content.site(gs.colony.site_id).get("name", "")])
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
	var sv := _scroll("Forsyning")
	var v: VBoxContainer = sv[1]
	var gs: GameState = GameSession.state
	var sim: Simulation = GameSession.sim
	var rep: Dictionary = gs.colony.last_report
	var pw: Dictionary = rep.get("power", {})
	v.add_child(UiKit.title("Strøm"))
	v.add_child(UiKit.label("Produktion %.1f kW (heraf ark %.1f) · Forbrug %.1f kW · Balance %+.1f kW · Batteri %d / %d kWh%s%s" % [
		float(pw.get("produced_kw", 0)), float(pw.get("ark_kw", 0)), float(pw.get("demand_kw", 0)), float(pw.get("surplus_kw", 0)),
		int(pw.get("battery_kwh", 0)), int(pw.get("battery_capacity", 0)), " · STORM" if pw.get("storm", false) else "", " · NAT" if pw.get("night", false) else ""], 16, UiKit.TEXT, true))
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
		v.add_child(UiKit.rich("%s [b]%s[/b]: %.1f kW — %s%s" % [UiKit.status_icon("critical" if cut > 0 else "ok"), ColonySimulation.PRIORITY_LABELS.get(prio, prio), kw,
			", ".join(names) if not names.is_empty() else "ingen", ("  [color=#d25b4c]%d afbrudt[/color]" % cut) if cut > 0 else ""]))
	v.add_child(UiKit.title("Vand og mad"))
	var need: Dictionary = rep.get("need", {})
	var prod: Dictionary = rep.get("produced", {})
	v.add_child(UiKit.label("Vand +%.0f / −%.0f pr. dag · Mad +%.0f / −%.0f pr. dag · Reserve: %s dage" % [float(prod.get("water", 0)), float(need.get("water", 0)), float(prod.get("food", 0)), float(need.get("food", 0)),
		"∞" if float(rep.get("reserve_days", 9999)) >= 9999 else str(int(float(rep.get("reserve_days", 0))))], 16))
	v.add_child(UiKit.title("Flaskehalse"))
	var bn: Array = rep.get("bottlenecks", [])
	if bn.is_empty():
		v.add_child(UiKit.label("● Ingen. Alle færdige bygninger kører.", 16, UiKit.OK))
	for x: Dictionary in bn:
		v.add_child(UiKit.label("▲ %s: %s" % [GameSession.content.building(str(x["def_id"])).get("name"), x["text"]], 15, UiKit.WARN, true))
	v.add_child(UiKit.label("Droner: %.1f · Stabile dage i træk: %d" % [float(rep.get("drones", 0)), int(gs.colony.stats.get("days_stable", 0))], 15, UiKit.MUTED))
	return sv[0]


func _population_tab() -> Control:
	var sv := _scroll("Befolkning")
	var v: VBoxContainer = sv[1]
	var gs: GameState = GameSession.state
	var l := gs.ark.ledger()
	v.add_child(UiKit.title("Embryoregnskab (altid 50.000)"))
	v.add_child(UiKit.label("Levedygtige %s · I inkubation %s · Født %s · Tabt %s" % [UiKit.thousands(l["viable"]), UiKit.thousands(l["incubating"]), UiKit.thousands(l["born"]), UiKit.thousands(l["lost"])], 17))
	v.add_child(UiKit.label("Befolkning (levende): %d · Voksne: %d · Børn: %d" % [gs.population.alive_count(), gs.population.adult_workforce(), gs.population.count_stage("child")], 17))
	v.add_child(UiKit.title("Kohorter"))
	if gs.population.cohorts.is_empty():
		v.add_child(UiKit.label("Ingen endnu. Den første kohorte kræver et omsorgscenter, +5 kW overskud og 30 dages vand- og madreserve.", 15, UiKit.MUTED, true))
	for c: Dictionary in gs.population.cohorts:
		var stage := str(c["stage"])
		var txt := ""
		if stage == "incubating":
			txt = "Kohorte %d · %d embryoner · inkubation %d/%d dage%s" % [c["id"], c["size"], int(c["gestation_days"]), int(GameSession.content.bal("incubation.gestation_days", 270)), " · ▲ står stille" if int(c.get("stalled_days", 0)) > 0 else ""]
		else:
			txt = "Kohorte %d · %d %s · %.1f år · helbred %d%% · uddannelse %d%%" % [c["id"], c["size"], "børn" if stage == "child" else "voksne", float(c["age_days"]) / 365.0, int(float(c["health"]) * 100), int(float(c.get("education", 0)) * 100)]
		v.add_child(UiKit.label(txt, 15))
	v.add_child(UiKit.title("Inkubation"))
	var size := int(GameSession.content.bal("incubation.cohort_size", 10))
	var blockers := GameSession.sim.population.incubation_blockers(gs, size)
	var b := UiKit.button("Start inkubation af %d embryoner" % size, func() -> void:
		GameSession.cmd_start_incubation(size)
		refresh())
	b.disabled = not blockers.is_empty()
	v.add_child(b)
	for bl: Variant in blockers:
		v.add_child(UiKit.label("✕ " + str(bl), 15, UiKit.MUTED, true))
	return sv[0]


func _future_tab() -> Control:
	var sv := _scroll("Fremtid")
	var v: VBoxContainer = sv[1]
	var gs: GameState = GameSession.state
	var sim: Simulation = GameSession.sim
	var y := gs.campaign.colony_year()
	v.add_child(UiKit.title("Generationsspring"))
	v.add_child(UiKit.label("Et spring er en prognose, ikke en spoleknap. Simulatoren regner forsyning, aldring, arbejde og planlagte hændelser dag for dag og stopper før en uafklaret krise eller et underskud. ARK og koloniens institutioner bærer hverdagen efter planen: inkubation når forholdene tillader det, og byggeri efter behov.", 15, UiKit.MUTED, true))
	_target = 20 if y < 20.0 else 40
	var blockers := sim.era.leap_blockers(gs)
	var row := UiKit.hbox(10)
	var fb := UiKit.button("Beregn prognose til år %d" % _target, func() -> void:
		_forecast = GameSession.era_forecast(_target)
		refresh())
	fb.disabled = not blockers.is_empty() or y >= 40.0
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
		fv.add_child(UiKit.label("Prognose: år %.1f → år %.1f (%d dage)" % [float(f["start_day"]) / 365.0, float(f["end_year"]), int(f["days"])], 18, UiKit.AMBER))
		fv.add_child(UiKit.label(str(f["stop_text"]) + ("  " + str(f.get("stop_detail", "")) if not str(f.get("stop_detail", "")).is_empty() else ""), 16, UiKit.OK if f["stop_reason"] == EraService.STOP_TARGET else UiKit.WARN, true))
		fv.add_child(UiKit.label("Befolkning %d → %d · fødsler %d · voksne %d · reserve %s dage · arkens brændstof %s" % [int(f["population_start"]), int(f["population_end"]), int(f["births"]), int(f["adults"]),
			"∞" if float(f["reserve_days"]) >= 9999 else str(int(float(f["reserve_days"]))), str(f["ark_fuel"])], 16, UiKit.TEXT, true))
		fv.add_child(UiKit.label("Planen: %d inkubationer · byggeri: %s" % [incs, ", ".join(bl) if not bl.is_empty() else "intet"], 15, UiKit.MUTED, true))
		fv.add_child(UiKit.button("Godkend planen og spring", func() -> void:
			var r := GameSession.cmd_era_leap(_target)
			_forecast = {}
			if r.ok:
				close()
				leap_committed.emit()))
		fp.add_child(fv)
		v.add_child(fp)
	v.add_child(UiKit.title("Råd og overdragelse"))
	v.add_child(UiKit.label("Rådet: %s · Tillid %d · Selvbestemmelse %d" % ["samlet" if gs.society.council_formed else "ikke samlet", int(gs.society.trust), int(gs.society.autonomy)], 16))
	var m := sim.endings.metrics(gs)
	var prof := sim.endings.profile_for(m)
	v.add_child(UiKit.label("Hvis du overdrager nu: %s — %s" % [GameSession.content.endings.get(prof, {}).get("title", prof), GameSession.content.endings.get(prof, {}).get("criteria_text", "")], 15, UiKit.TEXT, true))
	v.add_child(UiKit.label("Mål for år 40: mindst %d mennesker, et fungerende råd, egen strøm uden arken og mindst %d dages reserve." % [int(GameSession.content.bal("campaign_goal.population", 500)), int(GameSession.content.bal("campaign_goal.min_reserve_days", 60))], 14, UiKit.MUTED, true))
	var hb := UiKit.button("Overdrag kolonien (afslutter kampagnen)", func() -> void:
		if GameSession.cmd_handover().ok:
			close()
			handover_committed.emit())
	hb.disabled = y < 20.0
	hb.tooltip_text = "Mulig fra år 20. Afslutningen følger koloniens faktiske robusthed."
	v.add_child(hb)
	return sv[0]


func close() -> void:
	_forecast = {}
	super()

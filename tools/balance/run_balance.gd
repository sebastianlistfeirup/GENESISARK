extends SceneTree
## Balance harness (bible p.15, GA-28): every candidate world x three colony
## strategies, fixed seeds, from landing to the year-40 hand-over, through the
## same domain commands and era leaps the player uses. Writes
## evidence/balance/balance_report.json and prints a table.
## Usage: godot --headless --path . --script res://tools/balance/run_balance.gd

const STRATEGIES := {
	"balanced": ["solar_array", "water_plant", "habitat", "greenhouse", "solar_array", "battery", "mine", "workshop", "care_center", "clinic", "school_hall"],
	"power_first": ["solar_array", "geothermal_generator", "water_plant", "habitat", "battery", "battery", "mine", "greenhouse", "workshop", "care_center", "school_hall"],
	"lean": ["solar_array", "water_plant", "habitat", "mine", "care_center", "greenhouse", "school_hall"],
}

var content: ContentDB
var tc: TestCase


func _init() -> void:
	content = ContentDB.load_default()
	tc = TestCase.new()
	tc.content = content
	var rows: Array = []
	var t0 := Time.get_ticks_msec()
	var only_planet := ""
	var only_strat := ""
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--planet="):
			only_planet = a.substr(9)
		if a.begins_with("--strategy="):
			only_strat = a.substr(11)
	var idx := 0
	for pid: String in content.planet_ids_sorted():
		for strat: String in STRATEGIES.keys():
			idx += 1
			if (not only_planet.is_empty() and pid != only_planet) or (not only_strat.is_empty() and strat != only_strat):
				continue
			var t1 := Time.get_ticks_msec()
			var row := _run(pid, strat, 1000 + idx)
			row["ms"] = Time.get_ticks_msec() - t1
			rows.append(row)
	var by_planet := {}
	for r: Dictionary in rows:
		var pr: Dictionary = by_planet.get(r["planet"], {"wins": 0, "best_pop": 0})
		if r["profile"] != "fragile":
			pr["wins"] = int(pr["wins"]) + 1
		pr["best_pop"] = maxi(int(pr["best_pop"]), int(r["population"]))
		by_planet[r["planet"]] = pr
	var report := {"engine_version": Engine.get_version_info().get("string"), "content_version": content.content_version,
		"runs": rows, "by_planet": by_planet, "elapsed_ms": Time.get_ticks_msec() - t0, "timestamp": Time.get_datetime_string_from_system(true)}
	DirAccess.make_dir_recursive_absolute("res://evidence/balance")
	var f := FileAccess.open("res://evidence/balance/balance_report.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(report, "  "))
	f.close()
	print("%-8s %-12s %5s %4s %5s %5s %5s %6s %5s %7s %6s %5s %-12s %s" % ["planet", "strategy", "year", "open", "defic", "pop20", "pop", "adult", "crisis", "reserve", "ownkW", "dmd", "profile", "stops"])
	for r: Dictionary in rows:
		print("%-8s %-12s %5.1f %4d %5d %5d %5d %6d %5d %7s %6.1f %5.1f %-12s %s" % [r["planet"], r["strategy"], r["year"], r["opening_days"], r["deficit_days"], r["pop_y20"], r["population"], r["adults"], r["crises"],
			str(int(r["reserve_days"])), r["own_kw"], r["demand_kw"], r["profile"], ",".join(r["stops"])])
	print("by planet: ", JSON.stringify(by_planet))
	quit(0)


func _run(pid: String, strat: String, seed_value: int) -> Dictionary:
	var sim := Simulation.new_campaign(content, seed_value)
	tc.land_on(sim, pid, 0)
	var gs := sim.state
	var req := sim.colony.requires_module(gs)
	var queue: Array = (STRATEGIES[strat] as Array).duplicate()
	var stops: Array = []
	var pop20 := -1  # Population at the year-20 hand-off: shows how fast a strategy grows
	# Act II opening: the player builds by hand, day by day.
	for day: int in 400:
		if not queue.is_empty():
			var d: String = queue[0]
			var cost := sim.colony.build_cost(gs, d)
			var ok := true
			for k: String in cost.keys():
				if float(gs.colony.inventory.get(k, 0.0)) < float(cost[k]):
					ok = false
			if ok and tc.place_near(sim, d) > 0:
				queue.pop_front()
		if not req.is_empty():
			for b: Dictionary in gs.colony.buildings:
				if b["def_id"] == "habitat" and b["state"] == ColonyState.B_ACTIVE and not req in b["modules"]:
					sim.colony.add_module(gs, int(b["id"]), req)
		# A player reacts to what the UI shows: power and water first.
		if day % 10 == 5:
			var rep: Dictionary = gs.colony.last_report
			if float(rep.get("power", {}).get("surplus_kw", 0.0)) < 7.0:
				tc.place_near(sim, "geothermal_generator" if DictUtil.get_float(sim.colony.modifiers(gs), "geothermal") >= 0.5 else "solar_array")
		if gs.population.cohorts.is_empty() and sim.population.incubation_blockers(gs, 10).is_empty():
			sim.population.start_incubation(gs, 10, "bal:first")
		sim.days.tick_day(gs)
		_resolve_events(sim)
		if gs.ark.embryo_incubating > 0 and queue.is_empty():
			break
	var opening_days := gs.campaign.colony_day  # How long the hand-built opening took
	# Era leaps with the institutions, resolving whatever stops the leap.
	for i: int in 80:
		if gs.campaign.colony_year() >= 40.0:
			break
		_resolve_events(sim)
		var target := 20 if gs.campaign.colony_year() < 20.0 else 40
		var r := sim.era.commit(gs, EraService.default_plan(target), "bal:leap:%d" % i)
		if not r.ok:
			stops.append("blocked")
			sim.days.tick_day(gs)
			continue
		var reason := str(r.data["stop_reason"])
		if reason != EraService.STOP_TARGET:
			stops.append(reason.substr(0, 6))
			_react(sim, reason)
		if pop20 < 0 and gs.campaign.colony_year() >= 20.0:
			pop20 = gs.population.alive_count()
		if gs.campaign.colony_year() >= 20.0 and gs.society.decisions.is_empty():
			sim.society.choose_priority(gs, "year_20", ["safety", "expansion", "self_determination"][seed_value % 3])
		if not gs.society.council_formed and sim.society.council_blockers(gs).is_empty():
			sim.society.form_council(gs, "bal:council")
	var m := sim.endings.metrics(gs)
	return {"planet": pid, "strategy": strat, "year": snappedf(gs.campaign.colony_year(), 0.1), "population": int(m.get("population", 0)),
		"pop_y20": pop20, "opening_days": opening_days, "deficit_days": int(gs.colony.stats.get("deficit_days", 0)),
		"adults": int(m.get("adults", 0)), "crises": int(m.get("crises_resolved", 0)), "reserve_days": float(m.get("reserve_days", 0)),
		"own_kw": float(m.get("own_power_kw", 0)), "demand_kw": float(m.get("demand_kw", 0)), "council": m.get("council", false),
		"profile": sim.endings.profile_for(m), "stops": stops, "buildings": gs.colony.buildings.size(), "ledger": gs.ark.ledger(),
		"invariants_ok": gs.validation_errors(content).is_empty(), "blockers_end": sim.population.incubation_blockers(gs, 10),
		"slots": sim.population.incubation_slots(gs), "residents": sim.population.capacity(gs, "residents"), "births": gs.ark.embryo_born}


func _resolve_events(sim: Simulation) -> void:
	var gs := sim.state
	for a: Dictionary in gs.events.active.duplicate():
		if a.get("phase") != "active":
			continue
		var def: Dictionary = content.events.get(str(a["id"]), {})
		var chosen := str(def.get("fallback", ""))
		for o: Dictionary in DictUtil.get_arr(def, "options"):
			if o.get("id") != chosen and sim.events.option_blockers(gs, def, o).is_empty():
				chosen = str(o["id"])
				break
		sim.events.resolve(gs, str(a["id"]), chosen)


func _react(sim: Simulation, reason: String) -> void:
	var gs := sim.state
	match reason:
		EraService.STOP_SHORTAGE:
			tc.place_near(sim, "water_plant")
			tc.place_near(sim, "greenhouse")
		EraService.STOP_POWER:
			tc.place_near(sim, "geothermal_generator" if DictUtil.get_float(sim.colony.modifiers(gs), "geothermal") >= 0.5 else "solar_array")
			tc.place_near(sim, "battery")
	for d: int in 5:
		sim.days.tick_day(gs)

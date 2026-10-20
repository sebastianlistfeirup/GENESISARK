extends TestCase
## GA-21/25: deterministic era leaps and endings.


func _settled(pid: String) -> Simulation:
	var sim := new_sim(99)
	land_on(sim, pid)
	var inv: Dictionary = sim.state.colony.inventory
	inv["alloy"] = 800.0
	inv["components"] = 60.0
	inv["water"] = 600.0
	inv["food"] = 600.0
	for d: String in ["solar_array", "solar_array", "geothermal_generator", "water_plant", "greenhouse", "habitat", "care_center", "battery", "mine", "workshop"]:
		place_near(sim, d)
	var req := sim.colony.requires_module(sim.state)
	if not req.is_empty():
		for b: Dictionary in sim.state.colony.buildings:
			if b["def_id"] == "habitat":
				sim.colony.add_module(sim.state, int(b["id"]), req)
	run_days(sim, 40)
	sim.population.start_incubation(sim.state, 10, "first")
	run_days(sim, 5)
	return sim


func test_forecast_equals_commit() -> void:
	var sim := _settled("pelagos")
	var plan := EraService.default_plan(3)
	var fc := sim.era.forecast(sim.state, plan)
	var res := sim.era.commit(sim.state, plan, "leap1")
	if not ok(res, "commit"):
		return
	eq(res.data["end_day"], fc["end_day"], "samme stopdag")
	eq(res.data["end_checksum"], fc["end_checksum"], "prognose == resultat")
	fails(sim.era.commit(sim.state, plan, "leap1"), "duplicate_txn")


func test_same_fixture_same_result() -> void:
	var a := _settled("sere")
	var b := _settled("sere")
	a.era.commit(a.state, EraService.default_plan(2), "l")
	b.era.commit(b.state, EraService.default_plan(2), "l")
	eq(a.checksum(), b.checksum(), "deterministisk")


func test_leap_stops_before_critical_event() -> void:
	var sim := _settled("viridia")
	var crit := ""
	for id: String in content.events.keys():
		if content.events[id].get("critical", false):
			crit = id
			break
	sim.state.events.active.append({"id": crit, "day_started": sim.state.campaign.colony_day, "phase": "active"})
	var r := sim.era.commit(sim.state, EraService.default_plan(20), "l")
	fails(r, "leap_blocked", "uløst krise blokerer")


func test_ledger_holds_over_leap() -> void:
	var sim := _settled("nivalis")
	sim.era.commit(sim.state, EraService.default_plan(4), "l")
	eq(sim.state.ark.embryo_sum(), 50000, "sum efter spring")
	check(sim.state.validation_errors(content).is_empty(), str(sim.state.validation_errors(content)))


func test_ending_profiles_from_metrics() -> void:
	var sim := new_sim()
	var base := {"population": 520, "council": true, "power_independent": true, "reserve_days": 90.0}
	eq(sim.endings.profile_for(base), "independent", "selvstændig")
	var shielded := base.duplicate()
	shielded["power_independent"] = false
	eq(sim.endings.profile_for(shielded), "shielded", "skærmet")
	var fragile := base.duplicate()
	fragile["population"] = 120
	fragile["council"] = false
	eq(sim.endings.profile_for(fragile), "fragile", "skrøbelig")


func test_handover_once_and_epilogue() -> void:
	var sim := _settled("ferrum")
	ok(sim.endings.handover(sim.state, "h"), "overdrag")
	fails(sim.endings.handover(sim.state, "h2"), "already_ended")
	var ep := sim.endings.epilogue(sim.state)
	check(ep.size() >= 3, "epilog")
	check("Ferrum" in " ".join(ep), "nævner planeten")
	check(not "{" in " ".join(ep), "ingen ufyldte pladsholdere: " + " ".join(ep))


func test_commit_without_forecast_matches_forecast() -> void:
	var a := _settled("umbra")
	var b := _settled("umbra")
	var plan := EraService.default_plan(2)
	var fc := a.era.forecast(a.state, plan)
	var r := b.era.commit(b.state, plan, "fresh")
	if ok(r, "commit uden prognose"):
		check(not r.data.get("adopted_forecast", false), "simulerede selv")
		eq(r.data["end_checksum"], fc["end_checksum"], "uafhængig simulering == prognose")


func test_epilogue_names_the_choices_made() -> void:
	var sim := _settled("sere")
	ok(sim.society.choose_priority(sim.state, "year_20", "safety"), "year 20")
	ok(sim.society.choose_priority(sim.state, "year_40", "self_determination"), "year 40")
	sim.state.society.trust = 20.0
	ok(sim.endings.handover(sim.state, "h"), "handover")
	var ep := sim.endings.epilogue(sim.state)
	var text := " ".join(ep)
	check("chose safety" in text, "year-20 choice in the epilogue")
	check("stepped back for good" in text, "year-40 choice in the epilogue")
	check("Trust had worn thin" in text, "low trust is named")
	check(not "{" in text, "no unfilled placeholders")
	var planet_close: String = DictUtil.get_arr(content.endings[sim.state.campaign.ending_id], "epilogue").back()
	check(str(ep.back()).begins_with(EndingService.fill(planet_close, {}).left(12)), "the ending's own last line stays last")

func test_institutions_keep_construction_labor() -> void:
	# GA-28: mines + workshop could take every ark drone, freezing construction for
	# years. Nivalis has 2.4 effective drones; the settled colony staffs 2 of them.
	var sim := _settled("nivalis")
	check(_free_labor(sim) < 1.0, "udgangspunkt: under én fri arbejdsenhed")
	sim.era.commit(sim.state, EraService.default_plan(2), "l")
	check(sim.state.colony.count_active("drone_hub") >= 1, "institutionerne bygger en dronehub")
	check(_free_labor(sim) >= 1.0, "mindst én fri enhed til byggeri efter springet: %s" % _free_labor(sim))


func _free_labor(sim: Simulation) -> float:
	var free := sim.colony.drones(sim.state) + floorf(float(sim.state.population.adult_workforce()) / 4.0)
	for b: Dictionary in sim.state.colony.buildings:
		if b["state"] == ColonyState.B_ACTIVE or b["state"] == ColonyState.B_CONSTRUCTING:
			free -= float(content.building(str(b["def_id"])).get("workforce", 0.0))
	return free


func test_workshops_follow_the_maintenance_bill() -> void:
	# R10: a large colony on a high-wear world must not starve for components.
	var sim := _settled("sere")
	var bal_before := sim.era.component_balance(sim.state)
	# Fixture: a grown colony (~100 finished buildings), as after a 20-year leap.
	var proto: Dictionary = sim.state.colony.buildings.filter(func(b: Dictionary) -> bool: return b["def_id"] == "solar_array")[0]
	for i: int in 70:
		var b: Dictionary = proto.duplicate(true)
		b["id"] = 1000 + i
		b["state"] = ColonyState.B_ACTIVE
		sim.state.colony.buildings.append(b)
	check(sim.era.component_balance(sim.state) < bal_before, "more buildings, bigger maintenance bill")
	check(sim.era.component_balance(sim.state) < 0.1, "one workshop cannot service the colony: %.2f/day, %d buildings, %d workshops" % [sim.era.component_balance(sim.state), sim.state.colony.buildings.size(), sim.state.colony.count_active("workshop")])
	sim.state.colony.inventory["components"] = 20.0
	var needs: Array = sim.era._needs(sim.state, EraService.default_plan(20), sim.state.colony.last_report)
	check("workshop" in needs or "drone_hub" in needs, "planner asks for a workshop (or the labor to staff one): " + str(needs))

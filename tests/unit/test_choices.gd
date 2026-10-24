extends TestCase
## R9 / D-034: choices with consequence. Year-20/40 priorities are lasting
## modifier sets; trust thresholds have systemic effects; the shielded ending
## follows what the Ark's emergency power actually carries.


func _colony(pid: String = "pelagos") -> Simulation:
	var sim := new_sim(77)
	land_on(sim, pid)
	var inv: Dictionary = sim.state.colony.inventory
	inv["alloy"] = 900.0
	inv["components"] = 80.0
	inv["water"] = 800.0
	inv["food"] = 800.0
	for d: String in ["solar_array", "solar_array", "water_plant", "greenhouse", "habitat", "care_center", "battery"]:
		place_near(sim, d)
	run_days(sim, 40)
	return sim


func _decide(sim: Simulation, id: String, prio: String) -> void:
	ok(sim.society.choose_priority(sim.state, id, prio), "decide %s" % prio)


func _adults(sim: Simulation, n: int) -> void:
	sim.state.population.cohorts.append({"id": 900, "size": n, "age_days": 20 * 365, "health": 1.0, "care_need": 0.0,
		"education": 1.0, "role": "worker", "stage": "adult", "gestation_days": 0, "stalled_days": 0, "txn": "t"})


# ------------------------------------------------------------ layer 1

func test_latest_decision_is_the_course() -> void:
	var sim := _colony()
	eq(ChoiceRules.active_priority(sim.state), "", "no course before a decision")
	_decide(sim, "year_20", "expansion")
	eq(ChoiceRules.active_priority(sim.state), "expansion")
	_decide(sim, "year_40", "safety")
	eq(ChoiceRules.active_priority(sim.state), "safety", "year 40 replaces year 20")


func test_every_priority_has_gain_and_price() -> void:
	for p: String in ChoiceRules.PRIORITY_IDS:
		var d := ChoiceRules.describe(content, p)
		check(not (d["gain"] as Array).is_empty(), "%s has a gain" % p)
		check(not (d["price"] as Array).is_empty(), "%s has a price" % p)


func test_expansion_grows_districts_and_births_but_wears_and_shrinks_storage() -> void:
	var sim := _colony()
	var gs := sim.state
	gs.campaign.colony_day = 20 * 365
	var scale0 := sim.colony.district_scale(gs)
	var wear0 := float(sim.colony.hazard_factors(gs, 5)["wear"])
	_decide(sim, "year_20", "expansion")
	check(sim.colony.district_scale(gs) > scale0, "districts larger (%.2f > %.2f)" % [sim.colony.district_scale(gs), scale0])
	check(float(sim.colony.hazard_factors(gs, 5)["wear"]) > wear0 * 1.1, "wear up")
	gs.campaign.colony_day += 365 * 2
	check(is_equal_approx(ChoiceRules.planned_birth_offset(content, gs), 8.0), "+4 births/yr for 2 years: %.2f" % ChoiceRules.planned_birth_offset(content, gs))
	gs.colony.inventory["alloy"] = 1490.0
	sim.days.tick_day(gs)
	check(float(gs.colony.inventory["alloy"]) <= 1500.0 * 0.75 + 0.01, "alloy capped at 75%%: %.0f" % float(gs.colony.inventory["alloy"]))


func test_safety_slows_building_lowers_births_and_softens_crises() -> void:
	var a := _colony()
	var b := _colony()
	_decide(b, "year_20", "safety")
	var ida := place_near(a, "school_hall")
	var idb := place_near(b, "school_hall")
	a.days.tick_day(a.state)
	b.days.tick_day(b.state)
	var pa := float(a.state.colony.building_by_id(ida).get("progress", 0.0))
	var pb := float(b.state.colony.building_by_id(idb).get("progress", 0.0))
	check(pa > 0.0 and pb < pa, "safety builds slower (%.3f < %.3f)" % [pb, pa])
	b.state.campaign.colony_day += 365
	check(ChoiceRules.planned_birth_offset(content, b.state) < -2.9, "−3 births/yr")
	var crisis := {"kind": "crisis"}
	var opt := {"effects": {"deaths": 3, "trust": -5, "food": 40, "wear": 10}}
	var e := b.events.option_effects(b.state, crisis, opt)
	eq(int(e["deaths"]), 2, "3 deaths × 0.7 → 2")
	check(is_equal_approx(float(e["trust"]), -3.5), "trust loss softened")
	eq(float(e["food"]), 40.0, "benefits untouched")
	eq(a.events.option_effects(a.state, crisis, opt)["deaths"], 3, "no course: full effect")


func test_self_determination_council_labor_and_ark() -> void:
	var sim := _colony()
	var gs := sim.state
	_adults(sim, 30)
	var labor0 := ChoiceRules.adult_labor(content, gs)
	_decide(sim, "year_20", "self_determination")
	check(ChoiceRules.adult_labor(content, gs) > labor0, "adults work more (%.0f > %.0f)" % [ChoiceRules.adult_labor(content, gs), labor0])
	eq(ChoiceRules.council_min_adults(content, gs), 6, "council from 6 adults")
	check(ChoiceRules.ark_burn_factor(content, gs, 0.0) > 0.0, "the Ark is wound down even on standby")
	check(is_equal_approx(ChoiceRules.ark_burn_factor(content, gs, 1.0), 2.0), "full draw burns 2×")


func test_ark_emergency_power_idles_when_not_needed() -> void:
	var sim := _colony()
	var gs := sim.state
	for i: int in 4:
		place_near(sim, "solar_array")
	run_days(sim, 20)
	var pw: Dictionary = gs.colony.last_report["power"]
	if float(pw["produced_kw"]) - float(pw["ark_kw"]) >= float(pw["demand_kw"]) and not bool(pw["night"]):
		var f0 := gs.colony.ark_fuel
		sim.days.tick_day(gs)
		eq(float(gs.colony.last_report["power"]["ark_drawn_kw"]), 0.0, "own power covers demand: Ark idle")
		eq(gs.colony.ark_fuel, f0, "no fuel burnt on standby")
	eq(ChoiceRules.ark_burn_factor(content, gs, 0.0), 0.0, "baseline standby burn is zero")


# ------------------------------------------------------------ layer 2

func test_low_trust_slows_work_and_raises_reserve_requirement() -> void:
	var sim := _colony()
	var gs := sim.state
	_adults(sim, 40)
	gs.society.trust = 50.0
	eq(ChoiceRules.trust_band(content, gs), "neutral")
	var neutral := ChoiceRules.adult_labor(content, gs)
	eq(ChoiceRules.incubation_reserve_days(content, gs), 30)
	gs.society.trust = 30.0
	eq(ChoiceRules.trust_band(content, gs), "low")
	check(ChoiceRules.adult_labor(content, gs) < neutral, "low trust: less work")
	eq(ChoiceRules.incubation_reserve_days(content, gs), 45, "45 reserve days")
	check(not ChoiceRules.trust_explanation(content, gs).is_empty(), "the Future tab explains why")
	# The blocker text names the higher requirement.
	gs.colony.inventory["water"] = 10.0
	var bl := " ".join(sim.population.incubation_blockers(gs, 10))
	check(bl.contains("45 days"), "blocker says 45 days: " + bl)


func test_high_trust_works_harder_and_crises_cost_less() -> void:
	var sim := _colony()
	var gs := sim.state
	_adults(sim, 40)
	gs.society.trust = 50.0
	var neutral := ChoiceRules.adult_labor(content, gs)
	gs.society.trust = 80.0
	check(ChoiceRules.adult_labor(content, gs) > neutral, "high trust: more work")
	var opt := {"cost": {"components": 10, "alloy": 0}}
	eq(float(sim.events.option_cost(gs, {"kind": "crisis"}, opt)["components"]), 8.0, "crisis −20%")
	eq(float(sim.events.option_cost(gs, {"kind": "civic"}, opt)["components"]), 10.0, "civic events unchanged")


func test_bad_choices_and_shortage_can_drop_trust_below_threshold() -> void:
	var sim := _colony()
	var gs := sim.state
	gs.society.trust = 50.0
	for i: int in 3:
		sim.events._apply_effects(gs, {"trust": -4})
	for i: int in 100:
		sim.society.tick_day(gs, {"shortage": true})
	check(gs.society.trust < 35.0, "three bad choices + a shortage period: %.1f" % gs.society.trust)


# ------------------------------------------------------------ endings

func test_shielded_follows_what_the_ark_carries() -> void:
	var sim := new_sim()
	var base := {"population": 520, "council": true, "power_independent": false, "reserve_days": 90.0, "power_gap_share": 0.05, "ark_share": 0.0}
	eq(sim.endings.profile_for(base), "shielded", "small gap, robust stores")
	var gap := base.duplicate()
	gap["power_gap_share"] = 0.4
	gap["ark_share"] = 0.02
	eq(sim.endings.profile_for(gap), "fragile", "a large gap nothing carries is fragile")
	var carried := gap.duplicate()
	carried["ark_share"] = 0.2
	carried["reserve_days"] = 10.0
	eq(sim.endings.profile_for(carried), "shielded", "the Ark carries > 15% of demand")
	var ind := base.duplicate()
	ind["power_independent"] = true
	ind["power_gap_share"] = 0.0
	ind["trust"] = 5.0
	eq(sim.endings.profile_for(ind), "independent", "trust alone never decides the ending")
	var leaning := ind.duplicate()
	leaning["ark_days_share"] = 0.3
	eq(sim.endings.profile_for(leaning), "shielded", "Ark emergency power drawn on 30% of days: still shielded")


func test_ark_draw_share_tracks_days_and_survives_save() -> void:
	var sim := _colony()
	var gs := sim.state
	gs.colony.ark_draw_share = 0.0
	gs.colony.ark_fuel = 50.0
	gs.colony.battery_kwh = 0.0
	for b: Dictionary in gs.colony.buildings.duplicate():
		if b["def_id"] == "solar_array":
			sim.colony.demolish(gs, int(b["id"]))  # own generation gone: the Ark must carry
	run_days(sim, 30)
	check(gs.colony.ark_draw_share > 0.05, "share rises on draw days: %.3f" % gs.colony.ark_draw_share)
	var back := GameState.from_dict(JSON.parse_string(JSON.stringify(gs.to_dict())))
	check(is_equal_approx(back.colony.ark_draw_share, gs.colony.ark_draw_share), "saved and loaded")


func test_power_margin_follows_the_course() -> void:
	var a := _colony()
	var b := _colony()
	_decide(b, "year_20", "expansion")
	var ta := a.era.power_targets(a.state)
	var tb := b.era.power_targets(b.state)
	eq(ta, Vector2(8.0, 20.0), "default margins")
	check(tb.x < ta.x and tb.y < ta.y, "expansion keeps smaller margins: %s" % tb)
	_decide(a, "year_20", "safety")
	check(a.era.power_targets(a.state).x > ta.x, "safety keeps larger margins")

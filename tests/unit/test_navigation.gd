extends TestCase
## Oxygen, approach hazards and NAV (D-024): costs shown before the choice,
## the approach is booked exactly once, NAV's reports are complete and factual.


func test_quote_shows_oxygen_and_hazard() -> void:
	var sim := new_sim()
	ark_ready(sim)
	var q := sim.travel.quote(sim.state, "umbra")
	eq(q["hazard"]["type"], "belt", "drift->umbra krydser bæltet")
	check(float(q["oxygen"]) > 0.0 and is_equal_approx(float(q["oxygen_after"]), 100.0 - float(q["oxygen"])), "iltforbrug vises")
	check(float(q["approach_hits_manual"]) > float(q["approach_hits_autopilot"]), "autopilot giver færre nedslag")
	check(float(q["approach_fuel_autopilot"]) > 0.0, "autopilot koster brændstof")
	var q2 := sim.travel.quote(sim.state, "pelagos")
	eq(q2["hazard"]["type"], "none", "fri rute")
	eq(float(q2["approach_hits_manual"]), 0.0, "ingen nedslag på fri rute")


func test_travel_uses_oxygen_and_opens_approach() -> void:
	var sim := new_sim()
	ark_ready(sim)
	var q := sim.travel.quote(sim.state, "umbra")
	ok(sim.travel.request_travel(sim.state, "umbra", "trip-u", true), "rejse")
	check(is_equal_approx(sim.state.ark.oxygen, 100.0 - float(q["oxygen"])), "ilt trukket én gang")
	eq(sim.state.campaign.pending_approach.get("destination"), "umbra", "indflyvning venter")


func test_approach_booked_once_and_clamped() -> void:
	var sim := new_sim()
	ark_ready(sim)
	ok(sim.travel.request_travel(sim.state, "umbra", "trip-u", true), "rejse")
	var integ := sim.state.ark.integrity
	var oxy := sim.state.ark.oxygen
	var fuel := sim.state.ark.fuel
	var r := sim.travel.resolve_approach(sim.state, 999, 999, 9999.0, true)
	ok(r, "indflyvning bogført")
	var ap: Dictionary = content.bal("approach", {})
	var max_hits := int(ceil(float(ap["max_hits"]) * 0.85))
	eq(int(r.data["hits"]), max_hits, "nedslag begrænset af tætheden")
	check(sim.state.ark.integrity < integ and sim.state.ark.oxygen < oxy and sim.state.ark.fuel < fuel, "skrog, ilt og brændstof betalt")
	check(sim.state.campaign.pending_approach.is_empty(), "ingen ventende indflyvning")
	fails(sim.travel.resolve_approach(sim.state, 1, 0, 0.0, false), "no_approach", "kan ikke bogføres igen")
	check(sim.state.ark.invariant_errors().is_empty(), "invarianter")


func test_approach_survives_reload_without_double_booking() -> void:
	var sim := new_sim()
	ark_ready(sim)
	ok(sim.travel.request_travel(sim.state, "umbra", "trip-u", true), "rejse")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(sim.state.to_dict()))
	ok(sim.travel.resolve_approach(sim.state, 2, 0, 0.0, false), "bogført")
	var restored := Simulation.new(content, GameState.from_dict(saved))
	eq(restored.state.campaign.pending_approach.get("destination"), "umbra", "save midt i indflyvningen husker den")
	ok(restored.travel.resolve_approach(restored.state, 2, 0, 0.0, false), "kan flyves efter load")
	eq(restored.state.ark.integrity, sim.state.ark.integrity, "samme resultat")


func test_oxygen_blocks_travel_and_repairs() -> void:
	var sim := new_sim()
	ark_ready(sim)
	sim.state.ark.oxygen = 5.0
	var q := sim.travel.quote(sim.state, "umbra")
	check(not q["ok"], "for lidt ilt til 100 dage")
	ok(sim.ark.repair_life_support(sim.state, 5, "ox-1"), "reparér iltrensere")
	eq(sim.state.ark.oxygen, 25.0, "+4 % pr. komponent")
	fails(sim.ark.repair_life_support(sim.state, 5, "ox-1"), "duplicate_txn", "samme txn")
	sim.state.ark.oxygen = 100.0
	fails(sim.ark.repair_life_support(sim.state, 1, "ox-2"), "full_oxygen", "fuldt lager")


func test_old_save_without_oxygen_loads_full() -> void:
	var sim := new_sim()
	var d := sim.state.to_dict()
	(d["ark"] as Dictionary).erase("oxygen")
	(d["campaign"] as Dictionary).erase("pending_approach")
	var gs := GameState.from_dict(d)
	eq(gs.ark.oxygen, 100.0, "ilt fra før v0.2 = fuldt")
	check(gs.campaign.pending_approach.is_empty(), "ingen indflyvning")


func test_nav_route_brief_is_complete_and_factual() -> void:
	var sim := new_sim()
	ark_ready(sim)
	for loc: String in content.locations.keys():
		var q := sim.travel.quote(sim.state, loc)
		for item: Dictionary in sim.nav.route_brief(sim.state, q):
			check(not str(item["text"]).contains("{") and not str(item["text"]).is_empty(), "%s: %s udfyldt" % [loc, item["id"]])
			eq(item["speaker"], "NAV", "taler som NAV")
	var belt := sim.nav.route_brief(sim.state, sim.travel.quote(sim.state, "umbra"))
	eq(belt[0]["id"], "route_belt", "bæltet nævnes først")
	eq(belt[0]["severity"], "warning", "som advarsel")


func test_nav_status_alerts() -> void:
	var sim := new_sim()
	ark_ready(sim)
	check(sim.nav.status(sim.state).is_empty(), "alt nominelt")
	sim.state.ark.oxygen = 10.0
	sim.state.ark.fuel = 1.0
	var ids: Array = sim.nav.status(sim.state).map(func(i: Dictionary) -> String: return i["id"])
	check("status_oxygen_critical" in ids and "status_fuel_none" in ids, str(ids))
	for item: Dictionary in sim.nav.status(sim.state):
		check(not str(item["text"]).contains("{"), "udfyldt: " + str(item["id"]))


func test_nav_lines_cover_every_id_used() -> void:
	for id: String in ["route_clear", "route_field", "route_debris", "route_belt", "route_fuel", "route_reserve_breach", "route_oxygen",
			"route_oxygen_low", "status_fuel_low", "status_fuel_none", "status_oxygen_low", "status_oxygen_critical", "status_hull_low",
			"approach_clear", "approach_field", "approach_debris", "approach_belt", "collision_course", "impact", "impact_severe",
			"autopilot_on", "autopilot_off", "hazard_cleared", "arrival", "surface_brief", "surface_hazard_enter",
			"surface_hazard_exit", "surface_next", "surface_all_done", "surface_energy_half", "surface_return_margin", "surface_return_now"]:
		check(content.nav_lines.has(id), "NAV-linje findes: " + id)


func _surface_ctx(dist: float, hazard: String = "", key: String = "main_sample") -> Dictionary:
	return {"dist_lander": dist, "walk_speed": 4.2, "drain": 0.12 * (2.0 if hazard != "" else 1.0), "base_drain": 0.12,
		"hazard_id": hazard, "hazard_label": "Spore field", "mult": 2.0 if hazard != "" else 1.0,
		"next_key": key, "next_label": "Take the main sample", "next_dist": 40.0}


func test_nav_surface_callouts_fire_once_in_order() -> void:
	var ex := ExpeditionState.new()
	var nav := NavAdvisor.new(content)
	var said := {}
	var brief := nav.surface_brief(ex, _surface_ctx(0.0))
	check(str(brief["text"]).contains("13.9 minutes") or str(brief["text"]).contains("14 minutes"), "brief states endurance: " + str(brief["text"]))
	check(nav.surface_update(ex, _surface_ctx(10.0), said).is_empty(), "nothing to report at full suit")
	var enter := nav.surface_update(ex, _surface_ctx(30.0, "spores@0"), said)
	eq(enter.size(), 1, "hazard entry reported")
	eq(enter[0]["id"], "surface_hazard_enter", "entry line")
	check(nav.surface_update(ex, _surface_ctx(31.0, "spores@0"), said).is_empty(), "not repeated inside the zone")
	eq(nav.surface_update(ex, _surface_ctx(35.0), said)[0]["id"], "surface_hazard_exit", "exit reported")
	eq(nav.surface_update(ex, _surface_ctx(35.0, "", "relay"), said)[0]["id"], "surface_next", "objective progress")
	ex.suit_energy = 48.0
	eq(nav.surface_update(ex, _surface_ctx(35.0, "", "relay"), said)[0]["id"], "surface_energy_half", "half-way mark")
	check(nav.surface_update(ex, _surface_ctx(35.0, "", "relay"), said).is_empty(), "half-way said once")
	# 6 % suit = 50 s endurance; 150 m back = ~43 s walk: margin, then turn back.
	ex.suit_energy = 6.0
	var ids: Array = nav.surface_update(ex, _surface_ctx(150.0, "", "relay"), said).map(func(i: Dictionary) -> String: return i["id"])
	check("surface_return_now" in ids, "turn back now: " + str(ids))
	check(nav.surface_update(ex, _surface_ctx(150.0, "", "relay"), said).is_empty(), "critical said once")
	ex.suit_energy = 40.0  # drone refill re-arms the warning
	nav.surface_update(ex, _surface_ctx(20.0, "", "relay"), said)
	ex.suit_energy = 6.0
	ids = nav.surface_update(ex, _surface_ctx(150.0, "", "relay"), said).map(func(i: Dictionary) -> String: return i["id"])
	check("surface_return_now" in ids, "re-armed after refill")
	for item: Dictionary in nav.surface_update(ex, _surface_ctx(150.0, "", "lander"), said):
		check(not str(item["text"]).contains("{"), "filled: " + str(item["id"]))
		eq(item["id"], "surface_all_done", "all done when only the lander is left")

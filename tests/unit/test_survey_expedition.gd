extends TestCase
## GA-06: scouting narrows intervals and pays once; expeditions end safely.


func test_long_range_probe_narrows_once() -> void:
	var sim := new_sim()
	ark_ready(sim)
	var k := sim.state.knowledge_of("ferrum")
	eq(k.observations["water_access"]["min"], 0.0, "arkivinterval")
	ok(sim.survey.launch_probe(sim.state, "ferrum", "", "p1"), "fjernsonde")
	eq(sim.state.ark.components, 37, "3 komponenter")
	eq(k.observations["water_access"]["min"], 0.1, "snævrere interval")
	fails(sim.survey.launch_probe(sim.state, "ferrum", "", "p1"), "duplicate_txn")
	fails(sim.survey.launch_probe(sim.state, "ferrum", "", "p2"), "no_new_knowledge")
	eq(sim.state.ark.components, 37, "betaler én gang")


func test_site_probe_requires_orbit() -> void:
	var sim := new_sim()
	ark_ready(sim)
	fails(sim.survey.launch_probe(sim.state, "ferrum", "desert_a", "s1"), "not_in_orbit")
	sim.travel.request_travel(sim.state, "ferrum", "t")
	ok(sim.survey.launch_probe(sim.state, "ferrum", "desert_a", "s1"), "sitesonde")
	check(sim.state.knowledge_of("ferrum").site_facts.has("desert_a"), "site-fakta afsløret")


func test_truth_never_rerolled() -> void:
	var sim := new_sim()
	ark_ready(sim)
	sim.travel.request_travel(sim.state, "nivalis", "t", true)
	sim.survey.orbital_scan(sim.state, "nivalis")
	sim.survey.launch_probe(sim.state, "nivalis", "ice_a", "s")
	var obs: Dictionary = sim.state.knowledge_of("nivalis").observations["geothermal_factor"]
	check(float(obs["min"]) <= 0.8 and float(obs["max"]) >= 0.8, "interval indeholder sandheden")


func test_expedition_full_flow() -> void:
	var sim := new_sim()
	ark_ready(sim)
	sim.travel.request_travel(sim.state, "viridia", "t")
	ok(sim.expedition.start(sim.state, "green_a", false), "start")
	sim.expedition.tick(sim.state, 60.0)
	eq(sim.state.expedition.suit_energy, 100.0 - 0.12 * 60.0, "drain 0.12/s")
	ok(sim.expedition.take_sample(sim.state, "main_sample"), "prøve")
	fails(sim.expedition.take_sample(sim.state, "main_sample"), "already_sampled")
	ok(sim.expedition.place_relay(sim.state), "relæ")
	ok(sim.expedition.finish(sim.state, "ex1"), "hjem")
	fails(sim.expedition.finish(sim.state, "ex1"), "duplicate_txn")
	var k := sim.state.knowledge_of("viridia")
	check("green_a" in k.expedition_sites, "site udforsket")
	var main: Dictionary = content.surveys["viridia"]["points"]["main_sample"]
	for prop: Variant in main["reveals"]:
		eq(k.status_of(str(prop)), "known", "prøven afslører %s" % prop)


func test_suit_depletion_is_announced_recall() -> void:
	var sim := new_sim()
	ark_ready(sim)
	sim.travel.request_travel(sim.state, "viridia", "t")
	sim.expedition.start(sim.state, "green_a", false)
	var warned := [false]
	sim.expedition.reserve_warning.connect(func() -> void: warned[0] = true)
	sim.expedition.tick(sim.state, 600.0)
	check(warned[0], "reservevarsel ved 30")
	sim.expedition.tick(sim.state, 600.0)
	eq(sim.state.expedition.status, ExpeditionState.STATUS_RECALLED, "tilbagekaldt, ikke låst")
	ok(sim.expedition.finish(sim.state, "e"), "kan afsluttes")
	eq(sim.state.campaign.phase, CampaignState.PHASE_VOYAGE, "kampagnen fortsætter")


func test_drone_reserve_once() -> void:
	var sim := new_sim()
	ark_ready(sim)
	sim.travel.request_travel(sim.state, "viridia", "t")
	ok(sim.expedition.start(sim.state, "green_b", true), "med dronereserve")
	eq(sim.state.ark.components, 38, "reserve koster 2")
	sim.expedition.tick(sim.state, 500.0)
	ok(sim.expedition.use_drone_refill(sim.state), "refill")
	fails(sim.expedition.use_drone_refill(sim.state), "no_refill", "kun én gang")

extends TestCase
## GA-07/08/16: landing commitment, building, network, power priorities.


func test_landing_once_and_planet_parameters() -> void:
	var sim := new_sim()
	ark_ready(sim)
	sim.travel.request_travel(sim.state, "nivalis", "t", true)
	ok(sim.landing.commit_landing(sim.state, "ice_a", "L1"), "landing")
	eq(sim.state.campaign.phase, CampaignState.PHASE_SETTLED, "fase")
	eq(sim.state.colony.biome_id, "ice", "biome fra planeten")
	eq(sim.state.colony.buildings.size(), 1, "én ark")
	var alloy: float = sim.state.colony.inventory["alloy"]
	fails(sim.landing.commit_landing(sim.state, "ice_a", "L1"), "already_landed")
	fails(sim.landing.commit_landing(sim.state, "ice_b", "L2"), "already_landed")
	eq(sim.state.colony.buildings.size(), 1, "ingen ekstra ark")
	eq(sim.state.colony.inventory["alloy"], alloy, "ingen dobbelt ressource")


func test_landing_cancel_changes_nothing() -> void:
	var sim := new_sim()
	ark_ready(sim)
	sim.travel.request_travel(sim.state, "viridia", "t")
	var before := sim.checksum()
	sim.landing.preview(sim.state, "green_a")
	eq(sim.checksum(), before, "preview ændrer intet")


func test_phase1_buildings_power_water_habitat() -> void:
	var sim := new_sim()
	land_on(sim, "viridia")
	var solar := place_near(sim, "solar_array")
	var water := place_near(sim, "water_plant")
	var hab := place_near(sim, "habitat")
	check(solar > 0 and water > 0 and hab > 0, "tre bygninger placeret (%d %d %d)" % [solar, water, hab])
	eq(sim.state.colony.inventory["alloy"], 120.0 - 30 - 35 - 40, "omkostning reserveret ved ordre")
	run_days(sim, 15)
	eq(sim.state.colony.count_active("solar_array"), 1, "sol færdig")
	eq(sim.state.colony.count_active("water_plant"), 1, "vand færdig")
	eq(sim.state.colony.count_active("habitat"), 1, "habitat færdig")
	var rep: Dictionary = sim.state.colony.last_report
	check(float(rep["power"]["surplus_kw"]) > 0.0, "strømoverskud")
	check(float(rep["produced"]["water"]) > 0.0, "vand produceres")


func test_placement_rules() -> void:
	var sim := new_sim()
	land_on(sim, "viridia")
	var chk := sim.colony.check_placement(sim.state, "solar_array", 0, 0, 0)
	check(not chk["ok"], "overlapper arken")
	chk = sim.colony.check_placement(sim.state, "solar_array", 110, 110, 0)
	check(not chk["ok"], "uden for distrikt/net")
	chk = sim.colony.check_placement(sim.state, "mine", 0, 20, 0)
	check(not chk["ok"] and " ".join(chk["reasons"]).contains("ressource"), "mine kun i ressourceområde")


func test_no_double_spend_and_refund_bounds() -> void:
	var sim := new_sim()
	land_on(sim, "viridia")
	var id := place_near(sim, "solar_array")
	var after: float = sim.state.colony.inventory["alloy"]
	fails(sim.colony.place_building(sim.state, "solar_array", 999, 999, 0, "p:solar_array:2:0"), "duplicate_txn")
	ok(sim.colony.demolish(sim.state, id), "annuller før arbejde")
	eq(sim.state.colony.inventory["alloy"], after + 30.0, "fuld refusion af reservation")
	id = place_near(sim, "solar_array")
	run_days(sim, 10)
	var before: float = sim.state.colony.inventory["alloy"]
	ok(sim.colony.demolish(sim.state, id), "nedriv")
	check(float(sim.state.colony.inventory["alloy"]) - before <= 15.0 + 0.001, "aldrig mere end investeret")


func test_power_cut_stops_output_with_reason() -> void:
	var sim := new_sim()
	land_on(sim, "viridia")
	place_near(sim, "water_plant")
	run_days(sim, 6)
	# Remove ark power: the water plant should be shed and explained, not silently fail.
	sim.state.colony.ark_fuel = 0.0
	var rep := run_days(sim, 1)
	var reasons: Array = []
	for b: Dictionary in rep["bottlenecks"]:
		reasons.append(b["reason"])
	check("no_power" in reasons, "vandanlæg mister strøm med årsag: %s" % str(reasons))
	eq(rep["produced"]["water"], 0.0, "ingen vand uden strøm")


func test_priority_life_support_before_production() -> void:
	var sim := new_sim()
	land_on(sim, "viridia")
	sim.state.colony.inventory["alloy"] = 400.0
	var hab := place_near(sim, "habitat")
	var mine := place_near(sim, "mine")
	var wp := place_near(sim, "water_plant")
	run_days(sim, 30)
	# 8 kW ark only: habitat (3) + water (4) fit, mine (4) does not.
	var rep: Dictionary = sim.state.colony.last_report
	check(int(mine) in rep["power"]["shed"], "produktion afbrydes først")
	check(bool(sim.state.colony.building_by_id(hab)["powered"]), "livsstøtte har strøm")
	check(bool(sim.state.colony.building_by_id(wp)["powered"]), "vand har strøm")


func test_save_ids_stable_across_roundtrip() -> void:
	var sim := new_sim()
	land_on(sim, "sere")
	place_near(sim, "solar_array")
	place_near(sim, "water_plant")
	run_days(sim, 5)
	var copy := GameState.from_dict(JSON.parse_string(JSON.stringify(sim.state.to_dict())))
	var a := DictUtil.canonical_json(sim.state.to_dict())
	var b := DictUtil.canonical_json(copy.to_dict())
	eq(a, b, "identisk efter JSON-roundtrip")


func test_biomes_differ() -> void:
	var outputs := {}
	for pid: String in ["viridia", "ferrum", "umbra"]:
		var sim := new_sim()
		land_on(sim, pid)
		place_near(sim, "solar_array")
		place_near(sim, "water_plant")
		run_days(sim, 20)
		outputs[pid] = sim.state.colony.last_report["power"]["produced_kw"]
	check(outputs["viridia"] != outputs["umbra"], "sol giver forskelligt: %s" % str(outputs))

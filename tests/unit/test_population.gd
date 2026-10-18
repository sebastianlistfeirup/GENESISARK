extends TestCase
## GA-09: incubation, cohorts, embryo ledger invariant.


func _care_colony(pid: String = "pelagos") -> Simulation:
	var sim := new_sim()
	land_on(sim, pid)
	var inv: Dictionary = sim.state.colony.inventory
	inv["alloy"] = 600.0
	inv["components"] = 40.0
	inv["water"] = 800.0
	inv["food"] = 800.0
	for d: String in ["solar_array", "solar_array", "water_plant", "greenhouse", "habitat", "care_center", "battery"]:
		check(place_near(sim, d) > 0, "placér %s" % d)
	run_days(sim, 40)
	return sim


func test_blocked_without_supply() -> void:
	var sim := new_sim()
	land_on(sim, "pelagos")
	var r := sim.population.start_incubation(sim.state, 10, "inc1")
	fails(r, "incubation_blocked")
	check(r.reason.contains("care and incubation center"), "explains care center: " + r.reason)
	eq(sim.state.ark.embryo_viable, 50000, "intet trukket")


func test_incubation_birth_and_ledger() -> void:
	var sim := _care_colony()
	var r := sim.population.start_incubation(sim.state, 10, "inc1")
	if not ok(r, "start inkubation"):
		return
	fails(sim.population.start_incubation(sim.state, 10, "inc1"), "duplicate_txn")
	eq(sim.state.ark.embryo_incubating, 10, "inkuberer")
	eq(sim.state.ark.embryo_sum(), 50000, "sum")
	run_days(sim, 270)
	eq(sim.state.ark.embryo_born, 10, "født efter 270 dage")
	eq(sim.state.ark.embryo_incubating, 0, "")
	eq(sim.state.ark.embryo_sum(), 50000, "sum bevaret")
	eq(sim.state.population.alive_count(), 10, "befolkning")
	eq(sim.state.population.adult_workforce(), 0, "børn er ikke arbejdskraft")


func test_repeated_completion_no_extra_birth() -> void:
	var sim := _care_colony()
	sim.population.start_incubation(sim.state, 10, "inc1")
	run_days(sim, 271)
	run_days(sim, 5)
	eq(sim.state.ark.embryo_born, 10, "ingen ekstra fødsler")


func test_accelerated_fixture_to_adulthood() -> void:
	# DEBUG fixture: an isolated accelerated cohort (bible GA-09). Not a player path.
	var sim := _care_colony()
	sim.population.start_incubation(sim.state, 10, "inc1")
	run_days(sim, 270)
	var c: Dictionary = sim.state.population.cohorts[0]
	c["age_days"] = 18 * 365 - 1
	run_days(sim, 1)
	eq(sim.state.population.adult_workforce(), 10, "voksne efter 18 år")
	eq(sim.state.ark.embryo_sum(), 50000, "sum")


func test_power_failure_pauses_not_kills() -> void:
	var sim := _care_colony()
	sim.population.start_incubation(sim.state, 10, "inc1")
	run_days(sim, 10)
	for b: Dictionary in sim.state.colony.buildings:
		if b["def_id"] == "care_center":
			sim.colony.demolish(sim.state, int(b["id"]))
			break
	var rep := run_days(sim, 5)
	check(not (rep["population"]["alerts"] as Array).is_empty(), "varsel om stillestående inkubation")
	eq(sim.state.ark.embryo_lost, 0, "intet tavst tab")
	eq(sim.state.ark.embryo_sum(), 50000, "sum")

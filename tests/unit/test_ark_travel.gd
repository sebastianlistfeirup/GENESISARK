extends TestCase
## GA-03/04/05: ark state, embryo ledger, transactional travel.


func test_new_campaign_baseline() -> void:
	var gs := new_sim().state
	eq(gs.ark.fuel, 100.0, "fuel")
	eq(gs.ark.integrity, 100.0, "integrity")
	eq(gs.ark.components, 40, "components")
	eq(gs.ark.embryo_viable, 50000, "viable")
	eq(gs.ark.embryo_sum(), 50000, "sum")
	check(gs.ark.invariant_errors().is_empty(), "invarianter")


func test_negative_resources_rejected() -> void:
	var sim := new_sim()
	sim.state.ark.fuel = -1
	check(not sim.state.validation_errors(content).is_empty(), "negativ fuel afvises")
	sim.state.ark.fuel = 10
	sim.state.ark.embryo_viable = 49999
	check(" ".join(sim.state.validation_errors(content)).contains("embryo sum"), "embryo sum must be 50000")


func test_power_objective_once() -> void:
	var sim := new_sim()
	ok(sim.ark.restore_power(sim.state), "første gang")
	fails(sim.ark.restore_power(sim.state), "already_restored", "anden gang")
	sim.update_objectives()
	var n := sim.state.campaign.completed_objectives.size()
	sim.update_objectives()
	eq(sim.state.campaign.completed_objectives.size(), n, "ingen dobbelt belønning")


func test_travel_requires_power() -> void:
	var sim := new_sim()
	fails(sim.travel.request_travel(sim.state, "viridia", "t1"), "travel_blocked")


func test_travel_costs_and_idempotency() -> void:
	var sim := new_sim()
	ark_ready(sim)
	var q := sim.travel.quote(sim.state, "viridia")
	eq(q["fuel"], 12.0, "prototyperute 12")
	ok(sim.travel.request_travel(sim.state, "viridia", "trip-1"), "rejse")
	eq(sim.state.ark.fuel, 88.0, "fuel trukket én gang")
	eq(sim.state.campaign.location_id, "viridia", "location opdateret")
	fails(sim.travel.request_travel(sim.state, "viridia", "trip-1"), "duplicate_txn", "dobbeltklik")
	eq(sim.state.ark.fuel, 88.0, "ingen dobbelt fuel")


func test_reload_on_arrival_cannot_spend_twice() -> void:
	var sim := new_sim()
	ark_ready(sim)
	ok(sim.travel.request_travel(sim.state, "ferrum", "trip-x"), "rejse")
	var restored := Simulation.new(content, GameState.from_dict(JSON.parse_string(JSON.stringify(sim.state.to_dict()))))
	fails(restored.travel.request_travel(restored.state, "ferrum", "trip-x"), "", "samme txn efter load")
	eq(restored.state.ark.fuel, 84.0, "fuel")


func test_risky_route_needs_confirmation() -> void:
	var sim := new_sim()
	ark_ready(sim)
	var q := sim.travel.quote(sim.state, "umbra")
	check(q["risky"], "umbra-ruten slider hårdt")
	fails(sim.travel.request_travel(sim.state, "umbra", "r1"), "needs_confirmation")
	ok(sim.travel.request_travel(sim.state, "umbra", "r1", true), "bekræftet")


func test_insufficient_reserve_explained() -> void:
	var sim := new_sim()
	ark_ready(sim)
	sim.state.ark.fuel = 13.0
	var q := sim.travel.quote(sim.state, "viridia")
	check(q["ok"], "kan nå frem")
	check(not q["reserve_ok"], "men ikke videre")
	check(" ".join(q["risk_reasons"]).length() > 10, "forklaring gives før valg")


func test_two_journeys_differ() -> void:
	var a := new_sim()
	var b := new_sim()
	ark_ready(a)
	ark_ready(b)
	a.travel.request_travel(a.state, "viridia", "x")
	b.travel.request_travel(b.state, "sere", "x")
	check(a.state.ark.fuel != b.state.ark.fuel, "forskelligt forbrug")

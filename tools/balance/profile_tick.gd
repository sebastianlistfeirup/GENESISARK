extends SceneTree
## Micro-profile of one colony day on a grown colony (tooling only).

func _init() -> void:
	var content := ContentDB.load_default()
	var tc := TestCase.new()
	tc.content = content
	var sim := Simulation.new_campaign(content, 5)
	tc.land_on(sim, "pelagos")
	var gs := sim.state
	gs.colony.inventory["alloy"] = 5000.0
	gs.colony.inventory["components"] = 500.0
	gs.colony.inventory["water"] = 5000.0
	gs.colony.inventory["food"] = 5000.0
	for i: int in 12:
		for d: String in ["solar_array", "water_plant", "habitat", "greenhouse", "battery", "solar_array"]:
			tc.place_near(sim, d)
	tc.run_days(sim, 30)
	print("buildings ", gs.colony.buildings.size())
	var sections := {"tick": 0}
	var t := Time.get_ticks_usec()
	for i: int in 300:
		sim.days.tick_day(gs)
	print("tick_day avg us: ", (Time.get_ticks_usec() - t) / 300)
	t = Time.get_ticks_usec()
	for i: int in 300:
		sim.colony.allocate_power(gs, sim.colony.hazard_factors(gs, 1))
	print("allocate_power avg us: ", (Time.get_ticks_usec() - t) / 300)
	t = Time.get_ticks_usec()
	for i: int in 300:
		sim.population.tick_day(gs, gs.colony.last_report)
	print("population avg us: ", (Time.get_ticks_usec() - t) / 300)
	t = Time.get_ticks_usec()
	for i: int in 300:
		sim.events.tick_day(gs, {})
	print("events avg us: ", (Time.get_ticks_usec() - t) / 300)
	t = Time.get_ticks_usec()
	for i: int in 20:
		sim.era._institutions(gs, EraService.default_plan(20), [])
	print("institutions avg us: ", (Time.get_ticks_usec() - t) / 20)
	t = Time.get_ticks_usec()
	for i: int in 20:
		sim.colony.check_placement(gs, "habitat", 0, 30, 0)
	print("check_placement avg us: ", (Time.get_ticks_usec() - t) / 20)
	quit(0)

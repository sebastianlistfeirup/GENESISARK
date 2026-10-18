class_name DebugFixtures
extends RefCounted
## DEBUG / TEST ONLY: named campaign states built through the same domain
## commands the player uses. Used by screenshots and scene smoke tests.

static func prepare(setup: String) -> void:
	if setup == "none":
		return
	GameSession.new_campaign(4242)
	var sim: Simulation = GameSession.sim
	var gs := sim.state
	var parts := setup.split(":")
	var kind := parts[0]
	var pid := parts[1] if parts.size() > 1 else "viridia"
	if kind == "fresh":
		return
	sim.ark.restore_power(gs)
	sim.ark.mark_system(gs, "starmap_opened")
	sim.ark.mark_system(gs, "embryo_bank_checked")
	if kind == "power":
		sim.update_objectives()
		return
	sim.travel.request_travel(gs, pid, "dbg:travel", true)
	if kind == "approach":  # journey committed, approach flight not yet flown
		sim.update_objectives()
		return
	sim.travel.resolve_approach(gs, 0, 0, 0.0, true)
	sim.survey.orbital_scan(gs, pid)
	if kind == "orbit":
		sim.update_objectives()
		return
	var site := str(GameSession.content.planet(pid)["site_templates"][0])
	if kind == "expedition":
		sim.expedition.start(gs, site, true)
		sim.update_objectives()
		return
	sim.landing.commit_landing(gs, site, "dbg:land")
	if kind == "landed":
		sim.update_objectives()
		return
	# "colony": a working robot colony (phase 1 endpoint)
	for d: String in ["solar_array", "water_plant", "habitat"]:
		PlacementHelper.place_near(sim, d)
	PlacementHelper.run_days(sim, 14)
	if kind == "colony":
		sim.update_objectives()
		return
	# "grown": a later colony with care center and the first cohort (phase 2 preview)
	var inv: Dictionary = gs.colony.inventory
	inv["alloy"] = float(inv["alloy"]) + 500.0
	inv["components"] = float(inv["components"]) + 40.0
	inv["water"] = float(inv["water"]) + 400.0
	inv["food"] = float(inv["food"]) + 400.0
	for d: String in ["solar_array", "solar_array", "greenhouse", "care_center", "battery", "mine", "workshop", "habitat"]:
		PlacementHelper.place_near(sim, d)
	var req := sim.colony.requires_module(gs)
	if not req.is_empty():
		for b: Dictionary in gs.colony.buildings:
			if b["def_id"] == "habitat":
				sim.colony.add_module(gs, int(b["id"]), req)
	PlacementHelper.run_days(sim, 40)
	sim.population.start_incubation(gs, 10, "dbg:inc")
	PlacementHelper.run_days(sim, 10)
	if kind == "grown":
		sim.update_objectives()
		return
	if kind == "era":
		# Leap like a player would: resolve what stops the leap, then continue.
		var target := int(parts[2]) if parts.size() > 2 else 20
		for i: int in 30:
			if gs.campaign.colony_year() >= float(target):
				break
			for a: Dictionary in gs.events.active.duplicate():
				if a.get("phase") == "active":
					sim.events.resolve(gs, str(a["id"]), str(GameSession.content.events[str(a["id"])].get("fallback", "")))
			var r := sim.era.commit(gs, EraService.default_plan(target), "dbg:era:%d" % i)
			if not r.ok:
				PlacementHelper.run_days(sim, 5)
			elif str(r.data["stop_reason"]) in [EraService.STOP_SHORTAGE, EraService.STOP_POWER]:
				PlacementHelper.place_near(sim, "water_plant")
				PlacementHelper.place_near(sim, "solar_array")
			if gs.campaign.colony_year() >= 20.0 and gs.society.decisions.is_empty():
				sim.society.choose_priority(gs, "year_20", "self_determination")
			if not gs.society.council_formed:
				sim.society.form_council(gs, "dbg:council")
		sim.update_objectives()

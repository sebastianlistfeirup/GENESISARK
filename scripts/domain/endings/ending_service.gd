class_name EndingService
extends RefCounted
## Ending profiles follow actual robustness and council status (bible p.12, GA-25).
## No hidden moral score decides the ending.

var content: ContentDB
var colony_sim: ColonySimulation
var population: PopulationService


func _init(db: ContentDB, sim: ColonySimulation, pop: PopulationService) -> void:
	content = db
	colony_sim = sim
	population = pop


func metrics(gs: GameState) -> Dictionary:
	var c := gs.colony
	if c == null:
		return {}
	var hz := colony_sim.hazard_factors(gs, gs.campaign.colony_day)
	var own_kw := 0.0
	var demand_kw := 0.0
	for b: Dictionary in c.buildings:
		if b.get("state") != ColonyState.B_ACTIVE or not b.get("accessible"):
			continue
		var kw := colony_sim.building_power_kw(gs, b, hz)
		if b.get("def_id") == "ark_core":
			continue
		if kw >= 0.0:
			own_kw += kw
		else:
			demand_kw -= kw
	var rd := population.reserve_days(gs)
	return {
		"population": gs.population.alive_count(),
		"adults": gs.population.adult_workforce(),
		"council": gs.society.council_formed,
		"trust": snappedf(gs.society.trust, 0.1),
		"autonomy": snappedf(gs.society.autonomy, 0.1),
		"own_power_kw": snappedf(own_kw, 0.1),
		"demand_kw": snappedf(demand_kw, 0.1),
		"power_independent": own_kw >= demand_kw and demand_kw > 0.0,
		"reserve_days": rd,
		"crises_resolved": int(c.stats.get("crises_resolved", 0)),
		"years": snappedf(gs.campaign.colony_year(), 0.1),
		"ark_fuel": snappedf(c.ark_fuel, 0.1),
	}


func profile_for(m: Dictionary) -> String:
	var goal: Dictionary = content.bal("campaign_goal", {})
	var pop_goal := DictUtil.get_int(goal, "population", 500)
	var reserve_goal := DictUtil.get_float(goal, "min_reserve_days", 60.0)
	if m.is_empty():
		return "fragile"
	var robust := float(m["reserve_days"]) >= reserve_goal
	if int(m["population"]) >= pop_goal and bool(m["council"]) and bool(m["power_independent"]) and robust:
		return "independent"
	if int(m["population"]) >= pop_goal / 2 and bool(m["council"]) and (robust or bool(m["power_independent"])):
		return "shielded"
	return "fragile"


func handover(gs: GameState, txn: String) -> CommandResult:
	if gs.campaign.phase == CampaignState.PHASE_ENDED:
		return CommandResult.fail("already_ended", Loc.t("Overdragelsen er allerede sket."))
	if gs.colony == null:
		return CommandResult.fail("no_colony", Loc.t("Der er ingen koloni at overdrage."))
	if gs.is_applied(txn):
		return CommandResult.fail("duplicate_txn", Loc.t("Allerede behandlet."))
	var m := metrics(gs)
	var id := profile_for(m)
	gs.campaign.ending_id = id
	gs.campaign.final_state = m
	gs.campaign.phase = CampaignState.PHASE_ENDED
	gs.campaign.act = 3
	gs.mark_applied(txn)
	gs.log_journal(Loc.t("Kaptajnen overdrager kolonien. Profil: %s.") % content.endings.get(id, {}).get("title", id), "ending")
	return CommandResult.success({"ending_id": id, "metrics": m})


func epilogue(gs: GameState) -> Array:
	var def: Dictionary = content.endings.get(gs.campaign.ending_id, {})
	var m: Dictionary = gs.campaign.final_state
	var p := content.planet(gs.campaign.selected_planet_id)
	var site := content.site(gs.campaign.landing_site_id)
	var vars := {
		"planet": str(p.get("name", "")), "site": str(site.get("name", "")),
		"population": str(m.get("population", 0)), "years": str(int(float(m.get("years", 0.0)))),
		"crises": str(m.get("crises_resolved", 0)), "council": str(clampi(int(m.get("adults", 0)) / 25, 5, 15)) if m.get("council", false) else Loc.t("ingen"),
		"captain_years": str(int(gs.campaign.captain_stasis_years)),
		"settlement": gs.society.settlement_name if not gs.society.settlement_name.is_empty() else "kolonien",
	}
	var out: Array = []
	for para: Variant in DictUtil.get_arr(def, "epilogue"):
		out.append(fill(str(para), vars))
	return out


func summary(gs: GameState) -> String:
	var def: Dictionary = content.endings.get(gs.campaign.ending_id, {})
	return fill(str(def.get("summary", "")), {"settlement": gs.society.settlement_name if not gs.society.settlement_name.is_empty() else Loc.t("Kolonien"),
		"planet": str(content.planet(gs.campaign.selected_planet_id).get("name", ""))})


static func fill(text: String, vars: Dictionary) -> String:
	for k: String in vars.keys():
		text = text.replace("{%s}" % k, str(vars[k]))
	return text

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
	# What the Ark's emergency power carries: the part of demand the colony's own
	# generation does not cover, up to what the Ark can still deliver (R9, D-034).
	var ark_kw := colony_sim.ark_power_kw(gs)
	var gap_kw := maxf(0.0, demand_kw - own_kw)
	return {
		"population": gs.population.alive_count(),
		"adults": gs.population.adult_workforce(),
		"council": gs.society.council_formed,
		"trust": snappedf(gs.society.trust, 0.1),
		"autonomy": snappedf(gs.society.autonomy, 0.1),
		"own_power_kw": snappedf(own_kw, 0.1),
		"demand_kw": snappedf(demand_kw, 0.1),
		"power_independent": own_kw >= demand_kw and demand_kw > 0.0,
		"ark_kw": snappedf(ark_kw, 0.1),
		"power_gap_share": snappedf(gap_kw / demand_kw, 0.001) if demand_kw > 0.0 else 0.0,
		"ark_share": snappedf(minf(ark_kw, gap_kw) / demand_kw, 0.001) if demand_kw > 0.0 else 0.0,
		"ark_days_share": snappedf(c.ark_draw_share, 0.001),
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
	var share := float(content.bal("ark_power.shielded_share", 0.15))
	# The Ark still shields the colony (R9): its emergency power carries more than
	# `share` of demand now, or was needed on more than `share` of the last year's days.
	var ark_carries := float(m.get("ark_share", 0.0)) > share or float(m.get("ark_days_share", 0.0)) > share
	if int(m["population"]) >= pop_goal and bool(m["council"]) and bool(m["power_independent"]) and robust and not ark_carries:
		return "independent"
	# Shielded (sharpened, R9): the colony lives, but either the Ark still carries
	# it, or it is nearly self-sufficient with robust stores. A large own-power gap
	# that nothing carries is fragile. Trust never enters here; only its systemic
	# effects (work, reserves, crisis costs) do.
	var near_self := float(m.get("power_gap_share", 0.0)) <= share and (robust or bool(m["power_independent"]))
	if int(m["population"]) >= pop_goal / 2 and bool(m["council"]) and (ark_carries or near_self):
		return "shielded"
	return "fragile"


func handover(gs: GameState, txn: String) -> CommandResult:
	if gs.campaign.phase == CampaignState.PHASE_ENDED:
		return CommandResult.fail("already_ended", Loc.t("The handover has already taken place."))
	if gs.colony == null:
		return CommandResult.fail("no_colony", Loc.t("There is no colony to hand over."))
	if gs.is_applied(txn):
		return CommandResult.fail("duplicate_txn", Loc.t("Already processed."))
	var m := metrics(gs)
	var id := profile_for(m)
	gs.campaign.ending_id = id
	gs.campaign.final_state = m
	gs.campaign.phase = CampaignState.PHASE_ENDED
	gs.campaign.act = 3
	gs.mark_applied(txn)
	gs.log_journal(Loc.t("The captain hands over the colony. Profile: %s.") % content.endings.get(id, {}).get("title", id), "ending")
	return CommandResult.success({"ending_id": id, "metrics": m})


func epilogue(gs: GameState) -> Array:
	var def: Dictionary = content.endings.get(gs.campaign.ending_id, {})
	var m: Dictionary = gs.campaign.final_state
	var p := content.planet(gs.campaign.selected_planet_id)
	var site := content.site(gs.campaign.landing_site_id)
	var vars := {
		"planet": str(p.get("name", "")), "site": str(site.get("name", "")),
		"population": str(m.get("population", 0)), "years": _count(int(float(m.get("years", 0.0))), Loc.t("%d year"), Loc.t("%d years")),
		"crises": _count(int(m.get("crises_resolved", 0)), Loc.t("%d crisis"), Loc.t("%d crises")), "council": str(clampi(int(m.get("adults", 0)) / 25, 5, 15)) if m.get("council", false) else Loc.t("none"),
		"captain_years": _count(int(gs.campaign.captain_stasis_years), Loc.t("%d year"), Loc.t("%d years")),
		"settlement": gs.society.settlement_name if not gs.society.settlement_name.is_empty() else Loc.t("the colony"),
	}
	var out: Array = []
	for para: Variant in DictUtil.get_arr(def, "epilogue"):
		out.append(fill(str(para), vars))
	# The choices the player made, in the order they were made (bible: the epilogue names institutional choices).
	var lines: Dictionary = DictUtil.get_dict(content.legacy, "lines")
	var legacy: Array = []
	for d: Dictionary in gs.society.decisions:
		var key := "%s_%s" % [d.get("id"), d.get("choice")]
		if lines.has(key):
			legacy.append(fill(str(DictUtil.get_dict(lines, key).get("text", "")), vars))
	var trust := float(m.get("trust", gs.society.trust))
	if trust >= DictUtil.get_float(content.legacy, "trust_high", 65.0):
		legacy.append(fill(str(DictUtil.get_dict(lines, "trust_high").get("text", "")), vars))
	elif trust < DictUtil.get_float(content.legacy, "trust_low", 35.0):
		legacy.append(fill(str(DictUtil.get_dict(lines, "trust_low").get("text", "")), vars))
	if not legacy.is_empty() and out.size() > 1:
		out = out.slice(0, out.size() - 1) + legacy + [out[out.size() - 1]]  # the planet's closing line stays last
	else:
		out += legacy
	return out


func summary(gs: GameState) -> String:
	var def: Dictionary = content.endings.get(gs.campaign.ending_id, {})
	return fill(str(def.get("summary", "")), {"settlement": gs.society.settlement_name if not gs.society.settlement_name.is_empty() else Loc.t("The colony"),
		"planet": str(content.planet(gs.campaign.selected_planet_id).get("name", ""))})


## "1 crisis" / "3 crises": numbers in prose carry their noun.
static func _count(n: int, one: String, many: String) -> String:
	return (one if n == 1 else many) % n


static func fill(text: String, vars: Dictionary) -> String:
	for k: String in vars.keys():
		text = text.replace("{%s}" % k, str(vars[k]))
	return text

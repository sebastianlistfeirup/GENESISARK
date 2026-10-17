class_name PopulationService
extends RefCounted
## Embryo ledger transitions, cohorts, ageing, care and education (bible p.11, GA-09).
## Embryos leave "viable" once. Birth moves incubating -> born. Nobody becomes an
## adult by clicking; adults are 18 years of simulated life.

var content: ContentDB
var colony_sim: ColonySimulation


func _init(db: ContentDB, sim: ColonySimulation) -> void:
	content = db
	colony_sim = sim


func incubation_slots(gs: GameState) -> int:
	var slots := 0
	for b: Dictionary in gs.colony.buildings:
		if b.get("state") == ColonyState.B_ACTIVE and b.get("accessible") and b.get("powered"):
			slots += DictUtil.get_int(DictUtil.get_dict(content.building(str(b.get("def_id"))), "provides"), "incubation_slots")
	return slots


func capacity(gs: GameState, key: String) -> int:
	var n := 0
	for b: Dictionary in gs.colony.buildings:
		if b.get("state") == ColonyState.B_ACTIVE and b.get("accessible") and b.get("powered"):
			if b.get("def_id") == "habitat" and key == "residents" and not colony_sim.habitat_ok(gs, b):
				continue
			n += DictUtil.get_int(DictUtil.get_dict(content.building(str(b.get("def_id"))), "provides"), key)
	return n


func daily_need(gs: GameState, extra_people: int = 0) -> Dictionary:
	var people := gs.population.alive_count() + extra_people
	return {"water": people * float(content.bal("consumption.water_per_person_day", 1.0)),
		"food": people * float(content.bal("consumption.food_per_person_day", 1.0))}


func reserve_days(gs: GameState, extra_people: int = 0) -> float:
	var need := daily_need(gs, extra_people)
	if need["water"] <= 0.0:
		return 9999.0  # No residents yet: JSON-safe "unlimited"
	return minf(9999.0, minf(float(gs.colony.inventory["water"]) / need["water"], float(gs.colony.inventory["food"]) / need["food"]))


## All reasons incubation cannot start right now (shown to the player before the choice).
func incubation_blockers(gs: GameState, count: int) -> Array:
	var out: Array = []
	if gs.colony == null:
		return ["Der er ingen koloni."]
	var inc: Dictionary = content.bal("incubation", {})
	if gs.ark.embryo_viable < count:
		out.append("Ikke nok levedygtige embryoner.")
	if gs.colony.count_active("care_center") == 0:
		out.append("Kræver et færdigt omsorgs- og inkubationscenter.")
	elif incubation_slots(gs) - gs.ark.embryo_incubating < count:
		out.append("Ikke nok ledige inkubationspladser (%d ledige)." % maxi(0, incubation_slots(gs) - gs.ark.embryo_incubating))
	var surplus := float(gs.colony.last_report.get("power", {}).get("surplus_kw", 0.0))
	if surplus < float(inc.get("required_surplus_kw", 5)):
		out.append("Kræver mindst +%d kW strømoverskud (nu %+.1f kW)." % [int(inc.get("required_surplus_kw", 5)), surplus])
	var rd := reserve_days(gs, count + gs.ark.embryo_incubating)
	if rd < float(inc.get("required_reserve_days", 30)):
		out.append("Kræver vand- og madreserve til %d dage for de kommende børn (nu %.0f)." % [int(inc.get("required_reserve_days", 30)), rd])
	var req := colony_sim.requires_module(gs)
	if not req.is_empty():
		var any_ok := false
		for b: Dictionary in gs.colony.buildings:
			if b.get("def_id") == "habitat" and b.get("state") == ColonyState.B_ACTIVE and colony_sim.habitat_ok(gs, b):
				any_ok = true
		if not any_ok:
			out.append("Planeten kræver et habitat med %s." % ("filtermodul" if req == "filter" else "varmemodul"))
	if capacity(gs, "residents") < gs.population.alive_count() + gs.ark.embryo_incubating + count:
		out.append("Ikke nok boligpladser til de kommende børn.")
	return out


func start_incubation(gs: GameState, count: int, txn: String) -> CommandResult:
	if gs.is_applied(txn):
		return CommandResult.fail("duplicate_txn", "Inkubationen er allerede startet.")
	if count <= 0:
		return CommandResult.fail("invalid_count", "Antallet skal være positivt.")
	var blockers := incubation_blockers(gs, count)
	if not blockers.is_empty():
		return CommandResult.fail("incubation_blocked", " ".join(blockers), {"blockers": blockers})
	gs.ark.embryo_viable -= count
	gs.ark.embryo_incubating += count
	var c := {
		"id": gs.population.next_cohort_id, "size": count, "age_days": 0, "health": 1.0, "care_need": 1.0,
		"education": 0.0, "role": "", "stage": "incubating", "gestation_days": 0, "stalled_days": 0, "txn": txn,
		"start_day": gs.campaign.colony_day,
	}
	gs.population.next_cohort_id += 1
	gs.population.cohorts.append(c)
	gs.mark_applied(txn)
	gs.log_journal("Inkubation af kohorte %d startet: %d embryoner." % [c["id"], count], "population")
	return CommandResult.success({"cohort_id": c["id"]})


## One colony day for every cohort. Returns {births: [cohort ids], adults: [...], alerts: [...]}.
func tick_day(gs: GameState, report: Dictionary) -> Dictionary:
	var out := {"births": [], "adults": [], "alerts": []}
	var inc: Dictionary = content.bal("incubation", {})
	var gestation := int(inc.get("gestation_days", 270))
	var adult_days := int(inc.get("adult_age_years", 18)) * int(content.bal("time.days_per_year", 365))
	var care_ok := incubation_slots(gs) > 0
	var shortage := bool(report.get("shortage", false))
	var children := gs.population.count_stage("child")
	var care_cap := capacity(gs, "care_capacity")
	var edu_cap := capacity(gs, "education_capacity")
	var clinic := capacity(gs, "health_per_day") > 0 or gs.colony.count_active("clinic") > 0
	var hazard_health := _hazard_health_penalty(gs)
	for c: Dictionary in gs.population.cohorts:
		match str(c.get("stage")):
			"incubating":
				if care_ok and not shortage:
					c["gestation_days"] = int(c["gestation_days"]) + 1
					c["stalled_days"] = 0
				else:
					c["stalled_days"] = int(c.get("stalled_days", 0)) + 1
					out["alerts"].append("Inkubation af kohorte %d står stille: %s" % [c["id"], "ingen strøm til omsorgscentret" if not care_ok else "forsyningsmangel"])
				if int(c["gestation_days"]) >= gestation:
					c["stage"] = "child"
					c["age_days"] = 0
					gs.ark.embryo_incubating -= int(c["size"])
					gs.ark.embryo_born += int(c["size"])
					out["births"].append(int(c["id"]))
			"child", "adult":
				c["age_days"] = int(c["age_days"]) + 1
				var h := float(c.get("health", 1.0))
				if shortage:
					h -= 0.01
				h -= hazard_health
				if clinic:
					h += 0.004
				if c["stage"] == "child":
					var cared := care_cap >= children
					c["care_need"] = 1.0 if not cared else 0.6
					if not cared:
						h -= 0.002
					if edu_cap > 0:
						c["education"] = minf(1.0, float(c.get("education", 0.0)) + 1.0 / float(adult_days) * 1.4)
					if int(c["age_days"]) >= adult_days:
						c["stage"] = "adult"
						c["role"] = "worker"
						c["care_need"] = 0.0
						out["adults"].append(int(c["id"]))
				# No silent loss: health has a floor; deaths only come from resolved events.
				c["health"] = clampf(h, 0.15, 1.0)
	for cid: int in out["births"]:
		gs.log_journal("Kohorte %d er født. %d nye mennesker." % [cid, int(gs.population.cohort_by_id(cid).get("size", 0))], "birth")
	return out


func _hazard_health_penalty(gs: GameState) -> float:
	var req := colony_sim.requires_module(gs)
	if req.is_empty():
		return 0.0
	for b: Dictionary in gs.colony.buildings:
		if b.get("def_id") == "habitat" and b.get("state") == ColonyState.B_ACTIVE and not colony_sim.habitat_ok(gs, b):
			return 0.004
	return 0.0


## Applies an explicit, player-visible loss (only called from event resolutions).
func apply_deaths(gs: GameState, count: int) -> int:
	var remaining := count
	for c: Dictionary in gs.population.cohorts:
		if remaining <= 0:
			break
		if c.get("stage") == "incubating":
			continue
		var n := mini(remaining, int(c["size"]))
		c["size"] = int(c["size"]) - n
		remaining -= n
		gs.population.deaths += n
	gs.population.cohorts = gs.population.cohorts.filter(func(c: Dictionary) -> bool: return int(c["size"]) > 0)
	return count - remaining


## Explicit loss of incubating embryos (event outcome only). Keeps the ledger whole.
func apply_embryo_loss(gs: GameState, count: int) -> int:
	var remaining := count
	for c: Dictionary in gs.population.cohorts:
		if remaining <= 0:
			break
		if c.get("stage") != "incubating":
			continue
		var n := mini(remaining, int(c["size"]))
		c["size"] = int(c["size"]) - n
		gs.ark.embryo_incubating -= n
		gs.ark.embryo_lost += n
		remaining -= n
	gs.population.cohorts = gs.population.cohorts.filter(func(c: Dictionary) -> bool: return int(c["size"]) > 0)
	return count - remaining

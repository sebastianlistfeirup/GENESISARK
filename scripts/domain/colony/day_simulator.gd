class_name DaySimulator
extends RefCounted
## One strategic colony day, in a fixed order, used by both real-time play and
## era leaps so they can never disagree (bible p.11, p.22 determinism):
## network -> workforce -> construction -> power -> production -> consumption ->
## maintenance -> population -> society -> events -> stats.

var content: ContentDB
var colony_sim: ColonySimulation
var population: PopulationService
var events: EventService
var society: SocietyService


func _init(db: ContentDB, sim: ColonySimulation, pop: PopulationService, ev: EventService, soc: SocietyService) -> void:
	content = db
	colony_sim = sim
	population = pop
	events = ev
	society = soc


func tick_day(gs: GameState) -> Dictionary:
	var c := gs.colony
	if c == null:
		return {}
	gs.campaign.colony_day += 1
	var day := gs.campaign.colony_day
	var hz := colony_sim.hazard_factors(gs, day)
	var mods := colony_sim.modifiers(gs)
	var bottlenecks: Array = []
	if c.network_dirty:
		colony_sim.recompute_network(gs)

	# Workforce: drones (+ adults) staff production first, the rest builds.
	var workforce := colony_sim.drones(gs) + ChoiceRules.adult_labor(content, gs)
	for b: Dictionary in c.buildings:
		b["staffed"] = true
		if b["state"] != ColonyState.B_ACTIVE:
			continue
		var need := float(content.buildings[b["def_id"]].get("workforce", 0.0))
		if need > 0.0:
			if workforce >= need:
				workforce -= need
			else:
				b["staffed"] = false
	var build_capacity := workforce
	var build_speed := ChoiceRules.mult(content, gs, "build_speed")
	for b: Dictionary in c.buildings:
		if b.get("state") != ColonyState.B_CONSTRUCTING:
			continue
		if not b.get("accessible"):
			b["blocked_reason"] = "no_access"
			continue
		var work := float(content.building(str(b.def_id)).get("build_work", 1))
		var units := minf(build_capacity, 3.0)
		if units <= 0.0:
			b["blocked_reason"] = "no_workforce"
			continue
		build_capacity -= units
		b["progress"] = minf(1.0, float(b.progress) + units / work * build_speed)
		b["blocked_reason"] = "constructing"
		if float(b.progress) >= 1.0:
			b["state"] = ColonyState.B_ACTIVE
			b["blocked_reason"] = ""
			c.network_dirty = true
			gs.log_journal(Loc.t("%s is complete.") % content.building(str(b.def_id)).get("name"), "build")
	if c.network_dirty:
		colony_sim.recompute_network(gs)

	var power := colony_sim.allocate_power(gs, hz)

	# Production
	var produced := {"water": 0.0, "food": 0.0, "alloy": 0.0, "components": 0.0}
	var out_mult := {"water": DictUtil.get_float(mods, "water", 1.0), "food": DictUtil.get_float(mods, "food", 1.0), "alloy": DictUtil.get_float(mods, "mine", 1.0)}
	var req_mod := colony_sim.requires_module(gs)
	var empty := {}
	for b: Dictionary in c.buildings:
		if b["state"] != ColonyState.B_ACTIVE:
			continue
		var def: Dictionary = content.buildings[b["def_id"]]
		var reason := ""
		if not b["accessible"]:
			reason = "no_access"
		elif not b["powered"]:
			reason = "no_power"
		elif not b.get("staffed", true):
			reason = "no_workforce"
		elif b["def_id"] == "habitat" and not req_mod.is_empty() and not req_mod in b["modules"]:
			reason = "module_missing"
		var eff := float(b.get("efficiency", 1.0))
		if reason.is_empty():
			var output: Dictionary = def.get("output", empty)
			var input: Dictionary = def.get("input", empty)
			var has_input := true
			for k: String in input.keys():
				if float(c.inventory.get(k, 0.0)) < float(input[k]):
					has_input = false
			if not has_input:
				reason = "input_missing"
			else:
				for k: String in input.keys():
					c.inventory[k] = float(c.inventory[k]) - float(input[k])
				for k: String in output.keys():
					var amount := float(output[k]) * float(out_mult.get(k, 1.0)) * eff
					c.inventory[k] = float(c.inventory.get(k, 0.0)) + amount
					produced[k] = float(produced[k]) + amount
		if b.def_id != "ark_core" and b.get("state") == ColonyState.B_ACTIVE:
			b["blocked_reason"] = reason
			if not reason.is_empty():
				bottlenecks.append({"id": b.id, "def_id": b.def_id, "reason": reason, "text": Loc.t(str(ColonySimulation.REASONS.get(reason, reason)))})
	# Ark salvage and fuel burn
	var ark_def: Dictionary = DictUtil.get_dict(content.building("ark_core"), "provides")
	if c.salvage_left > 0.0:
		var s := minf(c.salvage_left, DictUtil.get_float(ark_def, "salvage_alloy_per_day", 2.0))
		c.salvage_left -= s
		c.inventory["alloy"] = float(c.inventory["alloy"]) + s
		produced["alloy"] = float(produced["alloy"]) + s
	# How often the colony still needs the Ark: ~1-year moving share of days with draw (R9).
	var drew := 1.0 if float(power.get("ark_drawn_kw", 0.0)) > 0.01 else 0.0
	c.ark_draw_share += (drew - c.ark_draw_share) / float(content.bal("time.days_per_year", 365))
	if c.ark_fuel > 0.0:
		# Emergency power burns fuel for what is drawn; standby costs little (R9).
		var ark_kw := float(power.get("ark_kw", 0.0))
		var drawn := float(power.get("ark_drawn_kw", 0.0)) / ark_kw if ark_kw > 0.0 else 0.0
		c.ark_fuel = maxf(0.0, c.ark_fuel - DictUtil.get_float(ark_def, "fuel_per_day", 0.1) * ChoiceRules.ark_burn_factor(content, gs, drawn))

	# Consumption: every living person, every day. Captain is supplied by the ark module.
	var need := population.daily_need(gs)
	var shortage := false
	for k: String in ["water", "food"]:
		var have := float(c.inventory[k])
		if have < float(need[k]):
			shortage = true
			c.inventory[k] = 0.0
		else:
			c.inventory[k] = have - float(need[k])

	# Storage limits: lagers are physical. Water/food keep up to a year of need.
	var st: Dictionary = content.bal("storage", {})
	if not st.is_empty():
		var smult := ChoiceRules.mult(content, gs, "storage")  # expansion −, safety + (R9)
		c.inventory["alloy"] = minf(float(c.inventory["alloy"]), DictUtil.get_float(st, "alloy", 1500.0) * smult)
		c.inventory["components"] = minf(float(c.inventory["components"]), DictUtil.get_float(st, "components", 300.0) * smult)
		for k: String in ["water", "food"]:
			var cap := maxf(DictUtil.get_float(st, "supply_min", 1500.0), float(need[k]) * DictUtil.get_float(st, "supply_days", 365.0)) * smult
			c.inventory[k] = minf(float(c.inventory[k]), cap)

	# Maintenance: robots service worn buildings with components; otherwise output halves.
	var maint: Dictionary = content.bal("maintenance", {})
	var wear_day := DictUtil.get_float(maint, "wear_per_day", 0.4) * float(hz["wear"])
	var threshold := DictUtil.get_float(maint, "service_threshold", 60.0)
	var cost := DictUtil.get_float(maint, "component_per_service", 1.0)
	for b: Dictionary in c.buildings:
		if b["state"] != ColonyState.B_ACTIVE or b["def_id"] == "ark_core":
			continue
		b["wear"] = float(b["wear"]) + wear_day
		if float(b["wear"]) >= threshold:
			if float(c.inventory["components"]) >= cost:
				c.inventory["components"] = float(c.inventory["components"]) - cost
				b["wear"] = 0.0
				b["efficiency"] = 1.0
			else:
				b["efficiency"] = DictUtil.get_float(maint, "degraded_output", 0.5)
				if b.get("blocked_reason", "") == "":
					b["blocked_reason"] = "maintenance"
					bottlenecks.append({"id": b.id, "def_id": b.def_id, "reason": "maintenance", "text": Loc.t(str(ColonySimulation.REASONS["maintenance"]))})

	var report := {
		"day": day, "power": power, "produced": produced, "need": need, "shortage": shortage,
		"bottlenecks": bottlenecks, "hazards": hz, "inventory": c.inventory.duplicate(),
		"drones": colony_sim.drones(gs), "free_build_capacity": build_capacity,
	}
	var pop := population.tick_day(gs, report)
	report["population"] = pop
	report["reserve_days"] = population.reserve_days(gs)
	report["alive"] = gs.population.alive_count()
	report["soc"] = society.tick_day(gs, report)
	report["events"] = events.tick_day(gs, report)

	# Stability stats (objective obj_stable_supply, ending robustness)
	if float(power["surplus_kw"]) >= 0.0 and not shortage and (power["shed"] as Array).is_empty():
		c.stats["days_stable"] = int(c.stats.get("days_stable", 0)) + 1
	else:
		c.stats["days_stable"] = 0
		c.stats["deficit_days"] = int(c.stats.get("deficit_days", 0)) + 1
	report["days_stable"] = c.stats["days_stable"]
	c.last_report = report
	return report

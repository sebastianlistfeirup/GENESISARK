class_name EraService
extends RefCounted
## Generation leaps (bible p.11, GA-21). A leap is a forecast, not a free
## rewind button: the simulator runs the same DaySimulator day by day on a copy,
## stops before an unresolved crisis or deficit, and shows when and why. The
## player approves a concrete plan; committing replays the identical plan on the
## real state (deterministic, so forecast == result).

const STOP_TARGET := "target_reached"
const STOP_CRISIS := "critical_event"
const STOP_SHORTAGE := "supply_shortage"
const STOP_POWER := "critical_power_cut"
const STOP_INCUBATION := "incubation_stalled"
const STOP_LIMIT := "day_limit"

const STOP_TEXT := {
	"target_reached": "The goal has been reached.",
	"critical_event": "Stopped before an unresolved critical event.",
	"supply_shortage": "Stopped: water or food is running out.",
	"critical_power_cut": "Stopped: life support or care is losing power.",
	"incubation_stalled": "Stopped: incubation has stalled.",
	"day_limit": "Stopped at the safety limit for a single leap.",
}

var content: ContentDB
var days: DaySimulator
var colony_sim: ColonySimulation
var population: PopulationService
var events: EventService
## Last forecast: committing the same plan from the same start adopts it
## instead of simulating the same days twice (deterministic, so identical).
var _last: Dictionary = {}
## Transient: def_id -> colony day until which a "no free spot" result is trusted.
var _no_space: Dictionary = {}


func _init(db: ContentDB, day_sim: DaySimulator) -> void:
	content = db
	days = day_sim
	colony_sim = day_sim.colony_sim
	population = day_sim.population
	events = day_sim.events


static func default_plan(target_year: int) -> Dictionary:
	return {"target_year": target_year, "cohort_size": 10, "auto_incubate": true, "auto_build": true, "births_per_year": 16}


func forecast(gs: GameState, plan: Dictionary) -> Dictionary:
	var start := DictUtil.sha256(DictUtil.canonical_json(gs.to_dict()))
	var copy := GameState.from_dict(gs.to_dict())
	var res := _simulate(copy, plan)
	res["end_checksum"] = world_checksum(copy)
	_last = {"start": start, "plan": JSON.stringify(plan), "state": copy.to_dict(), "result": res.duplicate(true)}
	return res


func commit(gs: GameState, plan: Dictionary, txn: String) -> CommandResult:
	if gs.is_applied(txn):
		return CommandResult.fail("duplicate_txn", Loc.t("The leap has already been made."))
	var blockers := leap_blockers(gs)
	if not blockers.is_empty():
		return CommandResult.fail("leap_blocked", " ".join(blockers), {"blockers": blockers})
	var res: Dictionary
	if not _last.is_empty() and _last["plan"] == JSON.stringify(plan) and _last["start"] == DictUtil.sha256(DictUtil.canonical_json(gs.to_dict())):
		gs.assign_from(GameState.from_dict(_last["state"]))
		res = (_last["result"] as Dictionary).duplicate(true)
		res["adopted_forecast"] = true
	else:
		res = _simulate(gs, plan)
	_last = {}
	gs.mark_applied(txn)
	gs.campaign.captain_stasis_years += float(res["days"]) / 365.0
	gs.log_journal(Loc.t("Time leap: %d years. %s") % [int(float(res["days"]) / 365.0), Loc.t(str(STOP_TEXT.get(res["stop_reason"], "")))], "era")
	res["end_checksum"] = world_checksum(gs)
	return CommandResult.success(res)


## Checksum of the simulated world (not bookkeeping such as journal or txn ids).
static func world_checksum(gs: GameState) -> String:
	var d := gs.to_dict()
	var w := {"ark": d["ark"], "colony": d["colony"], "population": d["population"], "society": d["society"],
		"events": d["events"], "colony_day": gs.campaign.colony_day}
	return DictUtil.sha256(DictUtil.canonical_json(w))


func leap_blockers(gs: GameState) -> Array:
	var out: Array = []
	if gs.colony == null:
		out.append(Loc.t("There is no colony."))
		return out
	var ev := events.blocking_event(gs)
	if not ev.is_empty():
		out.append(Loc.t("Resolve first: %s.") % ev.get("title", ev.get("id")))
	if gs.ark.embryo_born == 0 and gs.ark.embryo_incubating == 0:
		out.append(Loc.t("The first generation leap requires a stable period of care with the first cohort."))
	return out


func _simulate(gs: GameState, plan: Dictionary) -> Dictionary:
	_no_space = {}  # Transient cache must start empty so every run is reproducible
	var target_day := int(plan.get("target_year", 20)) * int(content.bal("time.days_per_year", 365))
	var start_day := gs.campaign.colony_day
	var start_pop := gs.population.alive_count()
	var start_born := gs.ark.embryo_born
	var actions: Array = []
	var shortage_streak := 0
	var stop := STOP_LIMIT
	var limit := start_day + 365 * 25
	var stop_detail := ""
	while gs.campaign.colony_day < limit:
		if gs.campaign.colony_day >= target_day:
			stop = STOP_TARGET
			break
		var ev := events.blocking_event(gs)
		if not ev.is_empty():
			stop = STOP_CRISIS
			stop_detail = str(ev.get("title", ev.get("id")))
			break
		if posmod(gs.campaign.colony_day, 15) == 0:
			_institutions(gs, plan, actions)
		var report := days.tick_day(gs)
		shortage_streak = shortage_streak + 1 if report.get("shortage", false) else 0
		if shortage_streak >= 3:
			stop = STOP_SHORTAGE
			break
		if _critical_shed(gs, report):
			stop = STOP_POWER
			break
		for c: Dictionary in gs.population.cohorts:
			if c.get("stage") == "incubating" and int(c.get("stalled_days", 0)) >= 10:
				stop = STOP_INCUBATION
		if stop == STOP_INCUBATION:
			break
	return {
		"stop_reason": stop, "stop_text": Loc.t(str(STOP_TEXT.get(stop, stop))), "stop_detail": stop_detail,
		"start_day": start_day, "end_day": gs.campaign.colony_day, "days": gs.campaign.colony_day - start_day,
		"end_year": snappedf(gs.campaign.colony_year(), 0.1),
		"population_start": start_pop, "population_end": gs.population.alive_count(),
		"births": gs.ark.embryo_born - start_born, "adults": gs.population.adult_workforce(),
		"reserve_days": population.reserve_days(gs), "actions": actions,
		"buildings": gs.colony.buildings.size(), "ark_fuel": snappedf(gs.colony.ark_fuel, 0.1),
	}


func _critical_shed(gs: GameState, report: Dictionary) -> bool:
	for bid: Variant in report.get("power", {}).get("shed", []):
		var b := gs.colony.building_by_id(int(bid))
		var prio := str(content.building(str(b.get("def_id"))).get("priority"))
		if prio == "life_support" or prio == "care":
			return true
	return false


## The AI and the colony's institutions carry daily life during a leap: they
## follow the approved plan with the same commands and rules as the player.
func _institutions(gs: GameState, plan: Dictionary, actions: Array) -> void:
	var c := gs.colony
	var report: Dictionary = c.last_report
	var surplus := float(report.get("power", {}).get("surplus_kw", 0.0))
	if bool(plan.get("auto_build", true)):
		# Up to two projects per review, most urgent first (life before growth).
		var built := 0
		for want: String in _needs(gs, plan, report):
			if built >= 2:
				break
			var placed := _auto_place(gs, want, actions)
			if placed > 0:
				built += 1
				var req := colony_sim.requires_module(gs)
				if want == "habitat" and not req.is_empty():
					colony_sim.add_module(gs, placed, req)
	# A new cohort at most every 30 days: care is a commitment, not a conveyor belt.
	if bool(plan.get("auto_incubate", true)) and posmod(gs.campaign.colony_day, 30) == 0:
		var size := int(plan.get("cohort_size", 10))
		# The approved plan sets a birth rate: total births follow it, never a runaway.
		var planned := 20.0 + float(plan.get("births_per_year", 16)) * gs.campaign.colony_year()
		var on_plan := float(gs.ark.embryo_born + gs.ark.embryo_incubating) < planned
		if on_plan and population.incubation_blockers(gs, size).is_empty():
			var r := population.start_incubation(gs, size, "era:inc:%d" % gs.campaign.colony_day)
			if r.ok:
				actions.append({"day": gs.campaign.colony_day, "action": "incubation", "size": size})


## Ordered list of what the institutions think the colony needs now.
func _needs(gs: GameState, plan: Dictionary, report: Dictionary) -> Array:
	var c := gs.colony
	var out: Array = []
	var surplus := float(report.get("power", {}).get("surplus_kw", 0.0))
	var pop_soon := gs.population.alive_count() + gs.ark.embryo_incubating + int(plan.get("cohort_size", 10))
	var need := population.daily_need(gs, gs.ark.embryo_incubating + int(plan.get("cohort_size", 10)))
	var prod: Dictionary = report.get("produced", {})
	var gen := "geothermal_generator" if DictUtil.get_float(colony_sim.modifiers(gs), "geothermal", 0.0) >= 0.5 and float(c.inventory["components"]) >= 4.0 else "solar_array"
	# Robot labor staffs mines and workshops before anything gets built. Below one
	# free unit construction stalls (GA-28), so more drones come first.
	var free_wf := free_workforce(gs)
	if free_wf < 1.0:
		out.append("drone_hub")
	if surplus < 8.0:
		out.append(gen)
	if float(prod.get("water", 0.0)) < float(need["water"]) * 1.15 + 4.0 + float(c.count_active("greenhouse")) * 4.0:
		out.append("water_plant")
	if float(prod.get("food", 0.0)) < float(need["food"]) * 1.15 + 2.0:
		out.append("greenhouse")
	if population.capacity(gs, "residents") < pop_soon + 20:
		out.append("habitat")
	if float(c.inventory["alloy"]) < 120.0 and c.count_active("mine") < 2 + int(gs.campaign.colony_year() / 6.0):
		_staffed_need(out, "mine", free_wf)
	if float(c.inventory["components"]) < 8.0 and c.count_active("workshop") < 1 + int(gs.campaign.colony_year() / 15.0):
		_staffed_need(out, "workshop", free_wf)
	if c.battery_kwh <= 0.0 and colony_sim.battery_capacity(gs) < 240.0:
		out.append("battery")
	if population.incubation_slots(gs) < 20 + gs.population.alive_count() / 12:
		out.append("care_center")
	if gs.population.count_stage("child") > 0 and c.count_active("school_hall") == 0:
		out.append("school_hall")
	if gs.population.alive_count() > 60 and c.count_active("clinic") == 0:
		out.append("clinic")
	if surplus < 20.0 and out.size() < 2:
		out.append(gen)
	return out


## Robot labor left once every staffed building (active or under construction)
## has its crew: what remains is construction capacity.
func free_workforce(gs: GameState) -> float:
	var free := colony_sim.drones(gs) + floorf(float(gs.population.adult_workforce()) / 4.0)
	for b: Dictionary in gs.colony.buildings:
		if b.get("state") == ColonyState.B_ACTIVE or b.get("state") == ColonyState.B_CONSTRUCTING:
			free -= float(content.building(str(b.get("def_id"))).get("workforce", 0.0))
	return free


## A staffed building is only worth it if one unit of labor is left to build
## with afterwards; otherwise the colony needs a drone hub first.
func _staffed_need(out: Array, def_id: String, free_wf: float) -> void:
	var need := float(content.building(def_id).get("workforce", 0.0))
	if free_wf >= need + 1.0:
		out.append(def_id)
	elif not "drone_hub" in out:
		out.append("drone_hub")


func _auto_place(gs: GameState, def_id: String, actions: Array) -> int:
	var cost := colony_sim.build_cost(gs, def_id)
	for k: String in cost.keys():
		if float(gs.colony.inventory.get(k, 0.0)) < float(cost[k]):
			return 0
	for b: Dictionary in gs.colony.buildings:
		if b.get("def_id") == def_id and b.get("state") == ColonyState.B_CONSTRUCTING:
			return 0  # One at a time per type
	if int(_no_space.get(def_id, -1)) >= gs.campaign.colony_day:
		return 0
	var site := content.site(gs.colony.site_id)
	var districts: Dictionary = DictUtil.get_dict(site, "districts")
	var wanted := str(content.building(def_id).get("district", "any"))
	# Keep the safe living zone for homes and care; utilities go outside it first.
	var order: Array = ["resource", "landing", "living"] if wanted == "any" else [wanted]
	for dk: String in order:
		var d: Dictionary = districts.get(dk, {})
		var center: Array = DictUtil.get_arr(d, "center")
		var radius := DictUtil.get_float(d, "radius") * colony_sim.district_scale(gs)
		# Golden-angle spiral: ~110 well-spread candidates instead of a dense grid.
		for i: int in 110:
			var rr := radius * sqrt(float(i) / 110.0)
			var ang := float(i) * 2.39996
			var x2 := snappedf(float(center[0]) + cos(ang) * rr, 1.0)
			var z2 := snappedf(float(center[1]) + sin(ang) * rr, 1.0)
			if colony_sim.check_placement(gs, def_id, x2, z2, 0)["ok"]:
				var r := colony_sim.place_building(gs, def_id, x2, z2, 0, "era:%s:%d:%d" % [def_id, gs.campaign.colony_day, gs.colony.next_building_id])
				if r.ok:
					actions.append({"day": gs.campaign.colony_day, "action": "build", "def_id": def_id})
					return int(r.data["building_id"])
	# Districts grow with time (district_scale); retry later rather than every review.
	_no_space[def_id] = gs.campaign.colony_day + 120
	return 0

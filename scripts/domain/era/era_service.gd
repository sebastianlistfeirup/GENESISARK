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
	"target_reached": "Målet er nået.",
	"critical_event": "Stoppede før en uafklaret kritisk hændelse.",
	"supply_shortage": "Stoppede: vand eller mad slipper op.",
	"critical_power_cut": "Stoppede: livsstøtte eller omsorg mister strøm.",
	"incubation_stalled": "Stoppede: inkubationen står stille.",
	"day_limit": "Stoppede ved sikkerhedsgrænsen for et spring.",
}

var content: ContentDB
var days: DaySimulator
var colony_sim: ColonySimulation
var population: PopulationService
var events: EventService


func _init(db: ContentDB, day_sim: DaySimulator) -> void:
	content = db
	days = day_sim
	colony_sim = day_sim.colony_sim
	population = day_sim.population
	events = day_sim.events


static func default_plan(target_year: int) -> Dictionary:
	return {"target_year": target_year, "cohort_size": 10, "auto_incubate": true, "auto_build": true}


func forecast(gs: GameState, plan: Dictionary) -> Dictionary:
	var copy := GameState.from_dict(gs.to_dict())
	var res := _simulate(copy, plan)
	res["end_checksum"] = world_checksum(copy)
	return res


func commit(gs: GameState, plan: Dictionary, txn: String) -> CommandResult:
	if gs.is_applied(txn):
		return CommandResult.fail("duplicate_txn", "Springet er allerede gennemført.")
	var blockers := leap_blockers(gs)
	if not blockers.is_empty():
		return CommandResult.fail("leap_blocked", " ".join(blockers), {"blockers": blockers})
	var res := _simulate(gs, plan)
	gs.mark_applied(txn)
	gs.campaign.captain_stasis_years += float(res["days"]) / 365.0
	gs.log_journal("Tidsspring: %d år. %s" % [int(float(res["days"]) / 365.0), STOP_TEXT.get(res["stop_reason"], "")], "era")
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
		out.append("Der er ingen koloni.")
		return out
	var ev := events.blocking_event(gs)
	if not ev.is_empty():
		out.append("Løs først: %s." % ev.get("title", ev.get("id")))
	if gs.ark.embryo_born == 0 and gs.ark.embryo_incubating == 0:
		out.append("Det første generationsspring kræver en stabil omsorgsperiode med den første kohorte.")
	return out


func _simulate(gs: GameState, plan: Dictionary) -> Dictionary:
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
		"stop_reason": stop, "stop_text": STOP_TEXT.get(stop, stop), "stop_detail": stop_detail,
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
		var pop_soon := gs.population.alive_count() + gs.ark.embryo_incubating + int(plan.get("cohort_size", 10))
		var need := population.daily_need(gs, gs.ark.embryo_incubating)
		var water_out := float(report.get("produced", {}).get("water", 0.0))
		var food_out := float(report.get("produced", {}).get("food", 0.0))
		if surplus < 6.0:
			var gen := "geothermal_generator" if DictUtil.get_float(colony_sim.modifiers(gs), "geothermal", 0.0) >= 0.5 else "solar_array"
			_auto_place(gs, gen, actions)
		elif water_out < float(need["water"]) * 1.2 + 4.0:
			_auto_place(gs, "water_plant", actions)
		elif food_out < float(need["food"]) * 1.2 + 2.0:
			_auto_place(gs, "greenhouse", actions)
		elif population.capacity(gs, "residents") < pop_soon + 10:
			var placed := _auto_place(gs, "habitat", actions)
			if placed > 0:
				var req := colony_sim.requires_module(gs)
				if not req.is_empty():
					colony_sim.add_module(gs, placed, req)
		elif c.battery_kwh <= 0.0 and colony_sim.battery_capacity(gs) < 120.0:
			_auto_place(gs, "battery", actions)
		elif float(c.inventory["components"]) < 6.0 and c.count_active("workshop") == 0:
			_auto_place(gs, "workshop", actions)
		elif c.count_active("mine") < 1 + int(gs.campaign.colony_year() / 10.0):
			_auto_place(gs, "mine", actions)
		elif population.incubation_slots(gs) < 20 + gs.population.alive_count() / 10:
			_auto_place(gs, "care_center", actions)
	if bool(plan.get("auto_incubate", true)):
		var size := int(plan.get("cohort_size", 10))
		if population.incubation_blockers(gs, size).is_empty():
			var r := population.start_incubation(gs, size, "era:inc:%d" % gs.campaign.colony_day)
			if r.ok:
				actions.append({"day": gs.campaign.colony_day, "action": "incubation", "size": size})


func _auto_place(gs: GameState, def_id: String, actions: Array) -> int:
	var cost := colony_sim.build_cost(gs, def_id)
	for k: String in cost.keys():
		if float(gs.colony.inventory.get(k, 0.0)) < float(cost[k]):
			return 0
	for b: Dictionary in gs.colony.buildings:
		if b.get("def_id") == def_id and b.get("state") == ColonyState.B_CONSTRUCTING:
			return 0  # One at a time per type
	var site := content.site(gs.colony.site_id)
	var districts: Dictionary = DictUtil.get_dict(site, "districts")
	var wanted := str(content.building(def_id).get("district", "any"))
	var order: Array = ["living", "landing", "resource"] if wanted == "any" else [wanted]
	for dk: String in order:
		var d: Dictionary = districts.get(dk, {})
		var center: Array = DictUtil.get_arr(d, "center")
		var radius := DictUtil.get_float(d, "radius") * colony_sim.district_scale(gs)
		var step := 4.0
		var ring := 0
		while float(ring) * step <= radius:
			var n := maxi(1, ring * 6)
			for i: int in n:
				var ang := TAU * float(i) / float(n)
				var x := float(center[0]) + cos(ang) * float(ring) * step
				var z := float(center[1]) + sin(ang) * float(ring) * step
				var x2 := snappedf(x, 1.0)
				var z2 := snappedf(z, 1.0)
				if colony_sim.check_placement(gs, def_id, x2, z2, 0)["ok"]:
					var r := colony_sim.place_building(gs, def_id, x2, z2, 0, "era:%s:%d:%d" % [def_id, gs.campaign.colony_day, gs.colony.next_building_id])
					if r.ok:
						actions.append({"day": gs.campaign.colony_day, "action": "build", "def_id": def_id})
						return int(r.data["building_id"])
			ring += 1
	return 0

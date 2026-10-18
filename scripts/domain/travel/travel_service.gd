class_name TravelService
extends RefCounted
## Star map travel. A journey is one transaction: cost is paid and location
## updated at a single commit point; a repeated txn (double click, reload on
## arrival) can never spend fuel twice (GA-05).

var content: ContentDB


func _init(db: ContentDB) -> void:
	content = db


## Everything the star map needs to show *before* the choice (bible p.8).
func quote(gs: GameState, destination: String) -> Dictionary:
	var from := gs.campaign.location_id
	var q := {"from": from, "to": destination, "ok": false, "reasons": [], "risky": false, "risk_reasons": []}
	if destination == from:
		q["reasons"].append(Loc.t("The Ark is already here."))
		return q
	var route: Dictionary = content.route_between(from, destination)
	if route.is_empty():
		q["reasons"].append(Loc.t("No known route."))
		return q
	var fuel := float(route.get("fuel", 0))
	var integ := float(route.get("integrity", 0))
	q["fuel"] = fuel
	q["integrity"] = integ
	q["days"] = int(route.get("days", 0))
	q["fuel_after"] = gs.ark.fuel - fuel
	q["integrity_after"] = gs.ark.integrity - integ
	q["risk_note"] = str(route.get("risk_note", ""))
	# Life support in stasis and the approach hazard (NAV's numbers, bible p.8: costs before the choice).
	var ox: Dictionary = content.bal("oxygen", {})
	q["oxygen"] = float(q["days"]) * DictUtil.get_float(ox, "stasis_per_day", 0.12)
	q["oxygen_after"] = gs.ark.oxygen - float(q["oxygen"])
	var hz: Dictionary = DictUtil.get_dict(route, "hazard")
	q["hazard"] = {"type": DictUtil.get_str(hz, "type", "none"), "density": DictUtil.get_float(hz, "density", 0.0)}
	q.merge(approach_estimate(q["hazard"]))
	if gs.campaign.phase == CampaignState.PHASE_SETTLED:
		q["reasons"].append(Loc.t("The Ark has landed. The voyage is over."))
	elif gs.campaign.phase == CampaignState.PHASE_ARK:
		q["reasons"].append(Loc.t("Emergency power must be restored first."))
	if gs.ark.fuel < fuel:
		q["reasons"].append(Loc.t("Not enough fuel (%.0f / %.0f).") % [gs.ark.fuel, fuel])
	if gs.ark.integrity - integ <= 0.0:
		q["reasons"].append(Loc.t("The hull will not survive the voyage."))
	if float(q["oxygen_after"]) <= 0.0:
		q["reasons"].append(Loc.t("The oxygen reserve will not last the journey (%.0f %% / %.0f %%).") % [gs.ark.oxygen, float(q["oxygen"])])
	# Minimum reserve: from the destination, can we still reach the nearest other candidate?
	var nearest := INF
	var nearest_id := ""
	for loc: String in content.locations.keys():
		if loc == destination or str(content.locations[loc].get("planet_id", "")).is_empty():
			continue
		var r2: Dictionary = content.route_between(destination, loc)
		if r2.is_empty():
			continue
		if float(r2.get("fuel", 0)) < nearest:
			nearest = float(r2.get("fuel", 0))
			nearest_id = loc
	q["reserve_needed"] = nearest if nearest < INF else 0.0
	q["reserve_target"] = nearest_id
	q["reserve_ok"] = float(q["fuel_after"]) >= float(q["reserve_needed"])
	if not q["reserve_ok"]:
		q["risky"] = true
		q["risk_reasons"].append(Loc.t("After this voyage, the Ark cannot continue to %s (requires %.0f fuel). Landing will be effectively final.") % [
			content.locations.get(nearest_id, {}).get("name", nearest_id), nearest])
	if integ >= float(content.bal("risky_route_integrity_threshold", 6)):
		q["risky"] = true
		q["risk_reasons"].append(Loc.t("The route is hard on the hull (-%.0f integrity).") % integ)
	if float(q["oxygen_after"]) > 0.0 and float(q["oxygen_after"]) < DictUtil.get_float(ox, "low", 30.0):
		q["risky"] = true
		q["risk_reasons"].append(Loc.t("The oxygen reserve is below %.0f %% on arrival. Repair the scrubbers in the workshop.") % DictUtil.get_float(ox, "low", 30.0))
	q["ok"] = (q["reasons"] as Array).is_empty()
	return q


## Expected cost of the approach flight for a hazard (shown before travel, used by NAV).
func approach_estimate(hazard: Dictionary) -> Dictionary:
	var ap: Dictionary = content.bal("approach", {})
	var dens := DictUtil.get_float(hazard, "density", 0.0)
	var hit := DictUtil.get_float(ap, "hit_integrity", 1.5)
	var manual := dens * DictUtil.get_float(ap, "expected_hits_manual", 6.0)
	var auto := dens * DictUtil.get_float(ap, "expected_hits_autopilot", 1.5)
	return {"approach_hits_manual": snappedf(manual, 0.1), "approach_hits_autopilot": snappedf(auto, 0.1),
		"approach_integrity_manual": snappedf(manual * hit, 0.1), "approach_integrity_autopilot": snappedf(auto * hit, 0.1),
		"approach_fuel_autopilot": snappedf(dens * DictUtil.get_float(ap, "autopilot_fuel_per_density", 2.0), 0.1)}


## Books the approach flight once: impacts cost hull, severe impacts leak oxygen,
## evasive burns and the autopilot cost fuel. Values are clamped to what the
## hazard allows; a repeated txn (reload on arrival) changes nothing.
func resolve_approach(gs: GameState, hits: int, severe: int, burn_s: float, autopilot_used: bool) -> CommandResult:
	var pa := gs.campaign.pending_approach
	if pa.is_empty():
		return CommandResult.fail("no_approach", Loc.t("No approach is pending."))
	var txn := str(pa.get("txn", ""))
	if gs.is_applied(txn):
		gs.campaign.pending_approach = {}
		return CommandResult.fail("duplicate_txn", Loc.t("The approach has already been completed."))
	var ap: Dictionary = content.bal("approach", {})
	var dens := DictUtil.get_float(DictUtil.get_dict(pa, "hazard"), "density", 0.0)
	var max_hits := int(ceil(DictUtil.get_float(ap, "max_hits", 12.0) * maxf(dens, 0.1)))
	hits = clampi(hits, 0, max_hits)
	severe = clampi(severe, 0, hits)
	var integ := hits * DictUtil.get_float(ap, "hit_integrity", 1.5) + severe * (DictUtil.get_float(ap, "severe_integrity", 3.0) - DictUtil.get_float(ap, "hit_integrity", 1.5))
	var oxy := severe * DictUtil.get_float(ap, "severe_oxygen", 2.5)
	var fuel := clampf(burn_s, 0.0, 120.0) * DictUtil.get_float(ap, "burn_fuel_per_s", 0.06)
	if autopilot_used:
		fuel += dens * DictUtil.get_float(ap, "autopilot_fuel_per_density", 2.0)
	gs.ark.integrity = maxf(0.0, gs.ark.integrity - integ)
	gs.ark.oxygen = maxf(0.0, gs.ark.oxygen - oxy)
	gs.ark.fuel = maxf(0.0, gs.ark.fuel - fuel)
	gs.mark_applied(txn)
	gs.campaign.pending_approach = {}
	gs.log_journal(Loc.t("Approach to %s: %d impacts, hull −%.1f %%, oxygen −%.1f %%, fuel −%.1f.") % [
		content.locations.get(gs.campaign.location_id, {}).get("name", gs.campaign.location_id), hits, integ, oxy, fuel], "travel")
	return CommandResult.success({"hits": hits, "severe": severe, "integrity": integ, "oxygen": oxy, "fuel": fuel})


func request_travel(gs: GameState, destination: String, txn: String, confirm_risky: bool = false) -> CommandResult:
	if txn.is_empty():
		return CommandResult.fail("missing_txn", Loc.t("The voyage is missing a transaction id."))
	if gs.is_applied(txn):
		return CommandResult.fail("duplicate_txn", Loc.t("The voyage has already been completed."), {"location": gs.campaign.location_id})
	var q := quote(gs, destination)
	if not q["ok"]:
		return CommandResult.fail("travel_blocked", "; ".join(q["reasons"]), q)
	if q["risky"] and not confirm_risky:
		return CommandResult.fail("needs_confirmation", Loc.t("Risky route requires confirmation: ") + " ".join(q["risk_reasons"]), q)
	# Single commit point.
	gs.ark.fuel = maxf(0.0, gs.ark.fuel - float(q["fuel"]))
	gs.ark.integrity = maxf(0.0, gs.ark.integrity - float(q["integrity"]))
	gs.ark.oxygen = maxf(0.0, gs.ark.oxygen - float(q["oxygen"]))
	gs.campaign.elapsed_days += int(q["days"])
	gs.campaign.captain_stasis_years += float(q["days"]) / 365.0
	gs.campaign.location_id = destination
	if not destination in gs.campaign.visited:
		gs.campaign.visited.append(destination)
	gs.mark_applied(txn)
	gs.campaign.pending_approach = {"txn": "approach:" + txn, "destination": destination, "hazard": q["hazard"]}
	gs.log_journal(Loc.t("Arrived at %s after %d days in stasis.") % [content.locations[destination].get("name", destination), int(q["days"])], "travel")
	return CommandResult.success({"location": destination, "quote": q})


func current_planet_id(gs: GameState) -> String:
	return str(content.locations.get(gs.campaign.location_id, {}).get("planet_id", ""))

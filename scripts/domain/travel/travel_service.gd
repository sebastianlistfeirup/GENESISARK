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
		q["reasons"].append("Arken er allerede her.")
		return q
	var route: Dictionary = content.route_between(from, destination)
	if route.is_empty():
		q["reasons"].append("Ingen kendt rute.")
		return q
	var fuel := float(route.get("fuel", 0))
	var integ := float(route.get("integrity", 0))
	q["fuel"] = fuel
	q["integrity"] = integ
	q["days"] = int(route.get("days", 0))
	q["fuel_after"] = gs.ark.fuel - fuel
	q["integrity_after"] = gs.ark.integrity - integ
	q["risk_note"] = str(route.get("risk_note", ""))
	if gs.campaign.phase == CampaignState.PHASE_SETTLED:
		q["reasons"].append("Arken er landet. Rejsen er slut.")
	elif gs.campaign.phase == CampaignState.PHASE_ARK:
		q["reasons"].append("Nødstrømmen skal genoprettes først.")
	if gs.ark.fuel < fuel:
		q["reasons"].append("Ikke nok brændstof (%.0f / %.0f)." % [gs.ark.fuel, fuel])
	if gs.ark.integrity - integ <= 0.0:
		q["reasons"].append("Skroget vil ikke holde til rejsen.")
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
		q["risk_reasons"].append("Efter rejsen kan arken ikke nå videre til %s (kræver %.0f brændstof). Landing bliver i praksis endelig." % [
			content.locations.get(nearest_id, {}).get("name", nearest_id), nearest])
	if integ >= float(content.bal("risky_route_integrity_threshold", 6)):
		q["risky"] = true
		q["risk_reasons"].append("Ruten slider hårdt på skroget (-%.0f integritet)." % integ)
	q["ok"] = (q["reasons"] as Array).is_empty()
	return q


func request_travel(gs: GameState, destination: String, txn: String, confirm_risky: bool = false) -> CommandResult:
	if txn.is_empty():
		return CommandResult.fail("missing_txn", "Rejsen mangler et transaktions-id.")
	if gs.is_applied(txn):
		return CommandResult.fail("duplicate_txn", "Rejsen er allerede gennemført.", {"location": gs.campaign.location_id})
	var q := quote(gs, destination)
	if not q["ok"]:
		return CommandResult.fail("travel_blocked", "; ".join(q["reasons"]), q)
	if q["risky"] and not confirm_risky:
		return CommandResult.fail("needs_confirmation", "Risikabel rute kræver bekræftelse: " + " ".join(q["risk_reasons"]), q)
	# Single commit point.
	gs.ark.fuel = maxf(0.0, gs.ark.fuel - float(q["fuel"]))
	gs.ark.integrity = maxf(0.0, gs.ark.integrity - float(q["integrity"]))
	gs.campaign.elapsed_days += int(q["days"])
	gs.campaign.captain_stasis_years += float(q["days"]) / 365.0
	gs.campaign.location_id = destination
	if not destination in gs.campaign.visited:
		gs.campaign.visited.append(destination)
	gs.mark_applied(txn)
	gs.log_journal("Ankommet til %s efter %d dage i stasis." % [content.locations[destination].get("name", destination), int(q["days"])], "travel")
	return CommandResult.success({"location": destination, "quote": q})


func current_planet_id(gs: GameState) -> String:
	return str(content.locations.get(gs.campaign.location_id, {}).get("planet_id", ""))

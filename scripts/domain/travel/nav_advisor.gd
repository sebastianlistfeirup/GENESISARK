class_name NavAdvisor
extends RefCounted
## NAV, the navigation computer: turns the travel numbers into short, dry
## reports (data/story/nav.json). Pure domain: no nodes, deterministic, tested.
## Severity: "info" | "warning" | "critical".

const SIDE_TEXT := {"left": "port", "right": "starboard", "up": "up", "down": "down"}

var content: ContentDB


func _init(db: ContentDB) -> void:
	content = db


## Fills a NAV line. Numbers are rounded the way NAV speaks: whole units, one decimal below 10.
func line(id: String, params: Dictionary = {}) -> String:
	var text := str(DictUtil.get_dict(content.nav_lines, id).get("text", id))
	for k: String in params.keys():
		text = text.replace("{%s}" % k, speak(params[k]))
	return text


static func speak(v: Variant) -> String:
	if v is float:
		var f: float = v
		return str(roundi(f)) if absf(f) >= 10.0 or is_equal_approx(f, roundf(f)) else str(snappedf(f, 0.1))
	return str(v)


func _item(id: String, severity: String, params: Dictionary) -> Dictionary:
	return {"id": id, "severity": severity, "speaker": "NAV", "text": line(id, params)}


## Briefing for a quoted route (star map, before the choice).
func route_brief(gs: GameState, q: Dictionary) -> Array:
	var out: Array = []
	if not q.has("fuel"):
		return out
	var dest := str(content.locations.get(q["to"], {}).get("name", q["to"]))
	var hz: Dictionary = q.get("hazard", {})
	var t := str(hz.get("type", "none"))
	var p := {"dest": dest, "days": int(q["days"]), "density": float(hz.get("density", 0.0)) * 100.0,
		"hits_manual": float(q.get("approach_hits_manual", 0.0)), "hits_auto": float(q.get("approach_hits_autopilot", 0.0)),
		"integ_manual": float(q.get("approach_integrity_manual", 0.0)), "integ_auto": float(q.get("approach_integrity_autopilot", 0.0)),
		"fuel_auto": float(q.get("approach_fuel_autopilot", 0.0)), "fuel_after": float(q["fuel_after"]),
		"reserve_needed": float(q.get("reserve_needed", 0.0)),
		"reserve_target": str(content.locations.get(q.get("reserve_target", ""), {}).get("name", q.get("reserve_target", ""))),
		"oxygen": float(q.get("oxygen", 0.0)), "oxygen_after": float(q.get("oxygen_after", gs.ark.oxygen)),
		"low": DictUtil.get_float(content.bal("oxygen", {}), "low", 30.0)}
	out.append(_item("route_" + (t if t in ["field", "debris", "belt"] else "clear"), "warning" if t == "belt" else "info", p))
	out.append(_item("route_fuel", "info", p))
	if not q.get("reserve_ok", true):
		out.append(_item("route_reserve_breach", "warning", p))
	out.append(_item("route_oxygen_low" if float(p["oxygen_after"]) < float(p["low"]) else "route_oxygen",
		"warning" if float(p["oxygen_after"]) < float(p["low"]) else "info", p))
	return out


## Standing alerts about the ark (fuel, oxygen, hull). Empty when all is nominal.
func status(gs: GameState) -> Array:
	var out: Array = []
	if gs.campaign.phase == CampaignState.PHASE_SETTLED or gs.campaign.phase == CampaignState.PHASE_ENDED:
		return out
	var ox: Dictionary = content.bal("oxygen", {})
	var rate := DictUtil.get_float(ox, "stasis_per_day", 0.12)
	if gs.ark.oxygen < DictUtil.get_float(ox, "critical", 15.0):
		out.append(_item("status_oxygen_critical", "critical", {"oxygen": gs.ark.oxygen, "days_left": int(gs.ark.oxygen / maxf(rate, 0.001))}))
	elif gs.ark.oxygen < DictUtil.get_float(ox, "low", 30.0):
		out.append(_item("status_oxygen_low", "warning", {"oxygen": gs.ark.oxygen}))
	var routes := 0
	var reachable := 0
	for loc: String in content.locations.keys():
		var r: Dictionary = content.route_between(gs.campaign.location_id, loc)
		if loc == gs.campaign.location_id or r.is_empty():
			continue
		routes += 1
		if float(r.get("fuel", 0)) <= gs.ark.fuel:
			reachable += 1
	if gs.campaign.phase == CampaignState.PHASE_VOYAGE and routes > 0:
		if reachable == 0:
			out.append(_item("status_fuel_none", "critical", {"fuel": gs.ark.fuel}))
		elif reachable < routes:
			out.append(_item("status_fuel_low", "warning", {"fuel": gs.ark.fuel, "reachable": reachable, "routes": routes}))
	if gs.ark.integrity < 40.0:
		out.append(_item("status_hull_low", "warning", {"integrity": gs.ark.integrity}))
	return out


## Line for the start of an approach flight.
func approach_start(hazard: Dictionary, distance_m: float) -> Dictionary:
	var t := str(hazard.get("type", "none"))
	return _item("approach_" + (t if t in ["field", "debris", "belt"] else "clear"), "warning" if t == "belt" else "info", {"distance": distance_m})


func collision_course(seconds: float, side: String) -> Dictionary:
	return _item("collision_course", "critical", {"seconds": maxf(1.0, roundf(seconds)), "side": Loc.t(str(SIDE_TEXT.get(side, side)))})


func impact(gs: GameState, severe: bool, section: String = "C") -> Dictionary:
	return _item("impact_severe" if severe else "impact", "critical" if severe else "warning",
		{"integrity": gs.ark.integrity, "oxygen": gs.ark.oxygen, "section": section})


func arrival(gs: GameState) -> Dictionary:
	return _item("arrival", "info", {"dest": str(content.locations.get(gs.campaign.location_id, {}).get("name", "")),
		"integrity": gs.ark.integrity, "fuel": gs.ark.fuel, "oxygen": gs.ark.oxygen})


## Planet surface: opening brief for an expedition. ctx: see surface_update().
func surface_brief(ex: ExpeditionState, ctx: Dictionary) -> Dictionary:
	var drain := DictUtil.get_float(ctx, "base_drain", 0.12)
	return _item("surface_brief", "info", {"energy": ex.suit_energy, "minutes": ex.suit_energy / maxf(drain, 0.001) / 60.0,
		"objective": str(ctx.get("next_label", "")), "dist": DictUtil.get_float(ctx, "next_dist", 0.0)})


## Seconds NAV budgets for walking back to the lander (walk speed, 20% terrain margin).
static func return_seconds(dist_m: float, walk_speed: float) -> float:
	return dist_m / maxf(walk_speed, 0.5) * 1.2


## Planet surface: lines due this frame. Deterministic given (ex, ctx, said);
## `said` is the caller's memory of what NAV has already reported (mutated here,
## never saved). ctx: {dist_lander, walk_speed, drain (current, per s),
## base_drain, hazard_id, hazard_label, mult, next_key, next_label, next_dist}.
func surface_update(ex: ExpeditionState, ctx: Dictionary, said: Dictionary) -> Array:
	var out: Array = []
	if ex.status != ExpeditionState.STATUS_ACTIVE:
		return out
	var drain := maxf(DictUtil.get_float(ctx, "drain", 0.12), 0.001)
	var endurance := ex.suit_energy / drain
	var dist := DictUtil.get_float(ctx, "dist_lander", 0.0)
	var ret := return_seconds(dist, DictUtil.get_float(ctx, "walk_speed", 4.2))
	var p := {"energy": ex.suit_energy, "seconds": endurance, "return_s": ret, "dist": dist,
		"hazard": str(ctx.get("hazard_label", "")), "mult": DictUtil.get_float(ctx, "mult", 1.0),
		"objective": str(ctx.get("next_label", "")), "next_dist": DictUtil.get_float(ctx, "next_dist", 0.0)}
	# Hazard zones: report entry once per zone visit, and the exit.
	var hz := str(ctx.get("hazard_id", ""))
	var was := str(said.get("hazard", ""))
	if hz != was:
		said["hazard"] = hz
		if hz != "":
			out.append(_item("surface_hazard_enter", "warning", p))
		elif was != "":
			out.append(_item("surface_hazard_exit", "info", p))
	# Progress: a finished objective moves the objective on.
	var key := str(ctx.get("next_key", ""))
	if said.has("objective") and str(said["objective"]) != key:
		out.append(_item("surface_all_done" if key == "lander" else "surface_next", "info", p))
	said["objective"] = key
	# Energy: half-way mark, then the return window.
	if ex.suit_energy <= 50.0 and not said.get("half", false):
		said["half"] = true
		out.append(_item("surface_energy_half", "info", p))
	if endurance > ret * 3.0 + 30.0:
		said.erase("margin")  # drone refill / walked closer: re-arm
		said.erase("now")
	if key != "lander" and endurance < ret * 2.0 + 20.0 and not said.get("margin", false):
		said["margin"] = true
		out.append(_item("surface_return_margin", "warning", p))
	if endurance < ret * 1.25 + 10.0 and not said.get("now", false):
		said["now"] = true
		said["margin"] = true
		out.append(_item("surface_return_now", "critical", p))
	return out

class_name EventService
extends RefCounted
## Data-driven crises and citizen events (bible p.12, GA-23). Each event
## triggers at most once; each resolution applies at most once. Unresolved
## critical events stop time leaps.

var content: ContentDB
var population: PopulationService


func _init(db: ContentDB, pop: PopulationService) -> void:
	content = db
	population = pop


func eligible(gs: GameState, def: Dictionary) -> bool:
	var id := str(def.get("id"))
	if gs.events.resolved.has(id) or gs.events.is_active(id):
		return false
	var biome := str(def.get("biome", ""))
	if not biome.is_empty() and biome != gs.colony.biome_id:
		return false
	var needs_hazard: Array = DictUtil.get_arr(def, "hazards")
	if not needs_hazard.is_empty():
		var has := false
		for h: Variant in DictUtil.get_arr(content.planet(gs.colony.planet_id), "hazard_ids"):
			if h in needs_hazard:
				has = true
		if not has:
			return false
	var pids: Array = DictUtil.get_arr(def, "planet_ids")
	if not pids.is_empty() and not gs.colony.planet_id in pids:
		return false
	var t: Dictionary = DictUtil.get_dict(def, "trigger")
	if gs.campaign.colony_day < DictUtil.get_int(t, "min_day", 0):
		return false
	if gs.population.alive_count() < DictUtil.get_int(t, "min_population", 0):
		return false
	for bid: Variant in DictUtil.get_arr(t, "requires_buildings"):
		if gs.colony.count_active(str(bid)) == 0:
			return false
	return true


func tick_day(gs: GameState, _report: Dictionary) -> Dictionary:
	var out := {"started": [], "warned": []}
	var ids: Array = content.events.keys()
	ids.sort()
	var rng := gs.rng.stream("events")
	for id: String in ids:
		var def: Dictionary = content.events[id]
		if not eligible(gs, def):
			continue
		var chance := DictUtil.get_float(DictUtil.get_dict(def, "trigger"), "chance_per_day", 0.0)
		# Always draw so the stream advances identically whatever the outcome.
		var roll := rng.randf()
		if not id in gs.events.warnings:
			# Warning precedes the event: a crisis is never sprung without notice.
			if roll < chance * 2.0:
				gs.events.warnings.append(id)
				gs.events.active.append({"id": id, "day_started": gs.campaign.colony_day + DictUtil.get_int(def, "warning_days", 3), "phase": "warning"})
				gs.log_journal(Loc.t("Warning: %s") % def.get("warning", def.get("title")), "warning")
				out["warned"].append(id)
	# Promote warnings to active events when their day arrives.
	for a: Dictionary in gs.events.active:
		if a.get("phase") == "warning" and gs.campaign.colony_day >= int(a.get("day_started", 0)):
			a["phase"] = "active"
			out["started"].append(a.get("id"))
	return out


func active_events(gs: GameState) -> Array:
	var out: Array = []
	for a: Dictionary in gs.events.active:
		if a.get("phase") == "active":
			out.append(content.events.get(str(a.get("id")), {}))
	return out


func blocking_event(gs: GameState) -> Dictionary:
	for a: Dictionary in gs.events.active:
		if a.get("phase") != "active":
			continue
		var def: Dictionary = content.events.get(str(a.get("id")), {})
		if bool(def.get("critical", false)):
			return def
	return {}


## What an option actually costs now: crises cost less when trust is high (R9).
func option_cost(gs: GameState, def: Dictionary, option: Dictionary) -> Dictionary:
	var m := ChoiceRules.crisis_cost_mult(content, gs) if str(def.get("kind")) == "crisis" else 1.0
	var out := {}
	var cost: Dictionary = DictUtil.get_dict(option, "cost")
	for k: String in cost.keys():
		out[k] = ceilf(float(cost[k]) * m) if float(cost[k]) > 0.0 else float(cost[k])
	return out


## The option's effects after the colony's course: under "safety" the harmful
## side of a crisis is smaller (R9). Benefits are never scaled.
func option_effects(gs: GameState, def: Dictionary, option: Dictionary) -> Dictionary:
	var e: Dictionary = DictUtil.get_dict(option, "effects").duplicate()
	if str(def.get("kind")) != "crisis":
		return e
	var m := ChoiceRules.crisis_effect_mult(content, gs)
	if is_equal_approx(m, 1.0):
		return e
	for k: String in ["food", "water", "alloy", "components", "trust", "health", "power_kw_days"]:
		if e.has(k) and float(e[k]) < 0.0:
			e[k] = float(e[k]) * m
	if e.has("wear") and float(e["wear"]) > 0.0:
		e["wear"] = float(e["wear"]) * m
	for k: String in ["deaths", "embryo_lost"]:
		if e.has(k) and int(e[k]) > 0:
			e[k] = roundi(float(e[k]) * m)
	return e


func option_blockers(gs: GameState, def: Dictionary, option: Dictionary) -> Array:
	var out: Array = []
	var cost: Dictionary = option_cost(gs, def, option)
	for k: String in cost.keys():
		if float(cost[k]) > 0.0 and float(gs.colony.inventory.get(k, 0.0)) < float(cost[k]):
			out.append(Loc.t("Missing %s.") % ColonySimulation._res_label(k))
	var req: Dictionary = DictUtil.get_dict(option, "requires")
	var rb := DictUtil.get_str(req, "building")
	if not rb.is_empty() and gs.colony.count_active(rb) == 0:
		out.append(Loc.t("Requires %s.") % content.building(rb).get("name", rb))
	var rm := DictUtil.get_str(req, "module")
	if not rm.is_empty():
		var found := false
		for b: Dictionary in gs.colony.buildings:
			if rm in b.get("modules", []):
				found = true
		if not found:
			out.append(Loc.t("Requires %s.") % ("filtermodul" if rm == "filter" else "varmemodul"))
	return out


func resolve(gs: GameState, event_id: String, option_id: String) -> CommandResult:
	if gs.events.resolved.has(event_id):
		return CommandResult.fail("already_resolved", Loc.t("The event has already been resolved."))
	var active_entry: Dictionary = {}
	for a: Dictionary in gs.events.active:
		if a.get("id") == event_id and a.get("phase") == "active":
			active_entry = a
	if active_entry.is_empty():
		return CommandResult.fail("not_active", Loc.t("The event is not active."))
	var def: Dictionary = content.events.get(event_id, {})
	var option: Dictionary = {}
	for o: Dictionary in DictUtil.get_arr(def, "options"):
		if o.get("id") == option_id:
			option = o
	if option.is_empty():
		return CommandResult.fail("unknown_option", Loc.t("Unknown choice."))
	var blockers := option_blockers(gs, def, option)
	if not blockers.is_empty():
		return CommandResult.fail("option_blocked", " ".join(blockers), {"blockers": blockers})
	var cost: Dictionary = option_cost(gs, def, option)
	for k: String in cost.keys():
		gs.colony.inventory[k] = maxf(0.0, float(gs.colony.inventory.get(k, 0.0)) - float(cost[k]))
	_apply_effects(gs, option_effects(gs, def, option))
	gs.events.active.erase(active_entry)
	gs.events.resolved[event_id] = {"option": option_id, "day": gs.campaign.colony_day}
	if str(def.get("kind")) == "crisis":
		gs.colony.stats["crises_resolved"] = int(gs.colony.stats.get("crises_resolved", 0)) + 1
	gs.mark_applied("event:%s" % event_id)
	gs.log_journal("%s — %s" % [def.get("title", event_id), option.get("result", option.get("label", ""))], "event")
	return CommandResult.success({"result": option.get("result", "")})


func _apply_effects(gs: GameState, e: Dictionary) -> void:
	var c := gs.colony
	for k: String in ["food", "water", "alloy", "components"]:
		if e.has(k):
			c.inventory[k] = maxf(0.0, float(c.inventory.get(k, 0.0)) + float(e[k]))
	if e.has("trust"):
		gs.society.trust = clampf(gs.society.trust + float(e["trust"]), 0.0, 100.0)
	if e.has("autonomy"):
		gs.society.autonomy = clampf(gs.society.autonomy + float(e["autonomy"]), 0.0, 100.0)
	if e.has("health"):
		for co: Dictionary in gs.population.cohorts:
			if co.get("stage") != "incubating":
				co["health"] = clampf(float(co.get("health", 1.0)) + float(e["health"]), 0.15, 1.0)
	if e.has("wear"):
		for b: Dictionary in c.buildings:
			if b.get("state") == ColonyState.B_ACTIVE and b.get("def_id") != "ark_core":
				b["wear"] = float(b.get("wear", 0.0)) + float(e["wear"])
	if e.has("settlement_name"):
		gs.society.settlement_name = str(e["settlement_name"])
	var prio := DictUtil.get_str(e, "priority")
	if gs.society.priorities.has(prio):
		gs.society.priorities[prio] = int(gs.society.priorities[prio]) + 1
	if e.has("power_kw_days"):
		# Negative = extra drain on the stored reserve (kW sustained for N days).
		c.battery_kwh = maxf(0.0, c.battery_kwh + float(e["power_kw_days"]) * 24.0)
	if e.has("deaths"):
		population.apply_deaths(gs, int(e["deaths"]))
	if e.has("embryo_lost"):
		population.apply_embryo_loss(gs, int(e["embryo_lost"]))


## Validation for event data (bible GA-23: no event demands a lost one-off resource).
func validate_events() -> PackedStringArray:
	var out: PackedStringArray = []
	for id: String in content.events.keys():
		var def: Dictionary = content.events[id]
		var fb := str(def.get("fallback", ""))
		var found := false
		for o: Dictionary in DictUtil.get_arr(def, "options"):
			if o.get("id") == fb:
				found = true
				for k: Variant in DictUtil.get_dict(o, "cost").values():
					if float(k) > 0.0:
						out.append(Loc.t("event %s: fallback '%s' has a cost") % [id, fb])
				var req: Dictionary = DictUtil.get_dict(o, "requires")
				if not DictUtil.get_str(req, "building").is_empty() or not DictUtil.get_str(req, "module").is_empty():
					out.append(Loc.t("event %s: fallback '%s' has requirements") % [id, fb])
		if not found:
			out.append(Loc.t("event %s: missing valid fallback") % id)
		for bid: Variant in DictUtil.get_arr(DictUtil.get_dict(def, "trigger"), "requires_buildings"):
			if not content.buildings.has(str(bid)):
				out.append(Loc.t("event %s: unknown building %s") % [id, bid])
	return out

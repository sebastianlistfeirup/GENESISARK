class_name ChoiceRules
extends RefCounted
## R9 (D-034): choices with consequence. Pure functions over ContentDB + GameState
## that every service reads, so real-time play and era leaps can never disagree.
##  * Layer 1: the latest year-20/40 priority is a lasting modifier set
##    (balance.priorities). Each priority has a gain and a price.
##  * Layer 2: trust is a dial (balance.trust_effects): below "low" adults work
##    less and incubation demands more reserve days; above "high" adults work
##    more and crises cost less. Trust never decides an ending on its own.

const BAND_LOW := "low"
const BAND_NEUTRAL := "neutral"
const BAND_HIGH := "high"
const PRIORITY_IDS := ["expansion", "safety", "self_determination"]


## The colony's current course: the latest year-20/40 decision ("" before any).
static func active_priority(gs: GameState) -> String:
	var out := ""
	for d: Dictionary in gs.society.decisions:
		var ch := str(d.get("choice", ""))
		if ch in PRIORITY_IDS:
			out = ch
	return out


static func _prio_value(content: ContentDB, priority: String, key: String, fallback: float) -> float:
	if priority.is_empty():
		return fallback
	return DictUtil.get_float(DictUtil.get_dict(content.bal("priorities", {}), priority), key, fallback)


## A multiplier from the active priority (1.0 when absent).
static func mult(content: ContentDB, gs: GameState, key: String) -> float:
	return _prio_value(content, active_priority(gs), key, 1.0)


static func trust_band(content: ContentDB, gs: GameState) -> String:
	var te: Dictionary = content.bal("trust_effects", {})
	if gs.society.trust < DictUtil.get_float(te, "low", 35.0):
		return BAND_LOW
	if gs.society.trust > DictUtil.get_float(te, "high", 65.0):
		return BAND_HIGH
	return BAND_NEUTRAL


## Adult work effort from trust (1.0 in the neutral band).
static func work_effort(content: ContentDB, gs: GameState) -> float:
	var te: Dictionary = content.bal("trust_effects", {})
	match trust_band(content, gs):
		BAND_LOW:
			return DictUtil.get_float(te, "low_effort", 0.75)
		BAND_HIGH:
			return DictUtil.get_float(te, "high_effort", 1.1)
	return 1.0


## Robot-equivalent labor units the adults provide (children never work).
static func adult_labor(content: ContentDB, gs: GameState) -> float:
	var share := _prio_value(content, active_priority(gs), "adult_work_share", float(content.bal("workforce.adult_work_share", 0.25)))
	return floorf(float(gs.population.adult_workforce()) * share * work_effort(content, gs))


## Reserve days incubation demands for the coming children.
static func incubation_reserve_days(content: ContentDB, gs: GameState) -> int:
	var base := int(content.bal("incubation.required_reserve_days", 30))
	if trust_band(content, gs) == BAND_LOW:
		return maxi(base, int(content.bal("trust_effects.low_reserve_days", 45)))
	return base


## Multiplier on crisis option costs (high trust: people pull together).
static func crisis_cost_mult(content: ContentDB, gs: GameState) -> float:
	if trust_band(content, gs) == BAND_HIGH:
		return float(content.bal("trust_effects.high_crisis_cost", 0.8))
	return 1.0


## Multiplier on the harmful side of crisis outcomes (safety priority).
static func crisis_effect_mult(content: ContentDB, gs: GameState) -> float:
	return mult(content, gs, "crisis_effects")


static func council_min_adults(content: ContentDB, gs: GameState) -> int:
	return int(_prio_value(content, active_priority(gs), "council_min_adults", float(content.bal("council.min_adults", 10))))


## Extra planned births from the priorities chosen so far: each decision's
## births_per_year delta applies from its day until the next decision.
static func planned_birth_offset(content: ContentDB, gs: GameState) -> float:
	var dpy := float(content.bal("time.days_per_year", 365))
	var out := 0.0
	var decs: Array = gs.society.decisions.filter(func(d: Dictionary) -> bool: return str(d.get("choice", "")) in PRIORITY_IDS)
	for i: int in decs.size():
		var d: Dictionary = decs[i]
		var start := int(d.get("day", 0))
		var stop := int(decs[i + 1].get("day", 0)) if i + 1 < decs.size() else gs.campaign.colony_day
		out += _prio_value(content, str(d["choice"]), "births_per_year", 0.0) * maxf(0.0, float(stop - start)) / dpy
	return out


## Births per year the institutions plan with under the current course.
static func births_per_year(content: ContentDB, gs: GameState, base: float) -> float:
	return maxf(0.0, base + _prio_value(content, active_priority(gs), "births_per_year", 0.0))


## Fraction of the Ark core's daily fuel burn for a day on which `drawn_frac`
## of its output was actually needed (0..1). Standby burns little or nothing.
static func ark_burn_factor(content: ContentDB, gs: GameState, drawn_frac: float) -> float:
	var p := active_priority(gs)
	var standby := _prio_value(content, p, "ark_standby_burn", float(content.bal("ark_power.standby_burn", 0.0)))
	var frac := clampf(drawn_frac, 0.0, 1.0)
	return (frac + (1.0 - frac) * standby) * _prio_value(content, p, "ark_fuel_burn", 1.0)


## Player-facing gain/price lines for a priority, built from the same data the rules read.
static func describe(content: ContentDB, priority: String) -> Dictionary:
	var gain: Array = []
	var price: Array = []
	var p: Dictionary = DictUtil.get_dict(content.bal("priorities", {}), priority)
	for k: String in p.keys():
		if k.begins_with("_"):
			continue
		var v := float(p[k])
		match k:
			"district_growth":
				(gain if v > 1.0 else price).append(Loc.t("Districts grow %+d%% faster") % roundi((v - 1.0) * 100.0))
			"births_per_year":
				(gain if v > 0.0 else price).append(Loc.t("Birth plan %+d per year") % roundi(v))
			"wear":
				(price if v > 1.0 else gain).append(Loc.t("Wear %+d%%") % roundi((v - 1.0) * 100.0))
			"storage":
				(gain if v > 1.0 else price).append(Loc.t("Storage limits %+d%%") % roundi((v - 1.0) * 100.0))
			"crisis_effects":
				(gain if v < 1.0 else price).append(Loc.t("Crisis damage %+d%%") % roundi((v - 1.0) * 100.0))
			"power_margin":
				if v > 1.0:
					gain.append(Loc.t("Institutions keep a %d%% larger power margin") % roundi((v - 1.0) * 100.0))
				else:
					price.append(Loc.t("Institutions keep a %d%% smaller power margin and lean on the Ark's emergency power") % roundi((1.0 - v) * 100.0))
			"build_speed":
				(gain if v > 1.0 else price).append(Loc.t("Construction %+d%% speed") % roundi((v - 1.0) * 100.0))
			"council_min_adults":
				gain.append(Loc.t("A council can form with %d adults") % roundi(v))
			"adult_work_share":
				gain.append(Loc.t("Adults work 1 in %d instead of 1 in %d") % [roundi(1.0 / maxf(v, 0.01)), roundi(1.0 / maxf(float(content.bal("workforce.adult_work_share", 0.25)), 0.01))])
			"ark_fuel_burn":
				price.append(Loc.t("The Ark's emergency power is wound down %d times faster") % roundi(v))
	return {"gain": gain, "price": price}


## Why trust matters right now (Future tab, HUD tooltip). Empty in the neutral band.
static func trust_explanation(content: ContentDB, gs: GameState) -> String:
	var te: Dictionary = content.bal("trust_effects", {})
	match trust_band(content, gs):
		BAND_LOW:
			return Loc.t("People work more slowly: they don't trust the plan. Adult work %d%%, incubation needs %d days of reserves.") % [roundi(DictUtil.get_float(te, "low_effort", 0.75) * 100.0), incubation_reserve_days(content, gs)]
		BAND_HIGH:
			return Loc.t("People trust the plan: adult work %d%%, crises cost %d%% less.") % [roundi(DictUtil.get_float(te, "high_effort", 1.1) * 100.0), roundi((1.0 - DictUtil.get_float(te, "high_crisis_cost", 0.8)) * 100.0)]
	return ""

class_name SurveyService
extends RefCounted
## Three scouting tiers (bible p.8): orbital scan (in orbit, free), probe
## (3 components; long-range from anywhere, or a site probe in orbit), and the
## captain's expedition (ExpeditionService). Scouting only narrows knowledge.

var content: ContentDB


func _init(db: ContentDB) -> void:
	content = db


func orbital_scan(gs: GameState, planet_id: String) -> CommandResult:
	if not content.planets.has(planet_id):
		return CommandResult.fail("unknown_planet", "Ukendt planet '%s'." % planet_id)
	var here := str(content.locations.get(gs.campaign.location_id, {}).get("planet_id", ""))
	if here != planet_id:
		return CommandResult.fail("not_in_orbit", "Orbital scanning kræver, at arken er i kredsløb om %s." % content.planet(planet_id).get("name"))
	var k := gs.knowledge_of(planet_id)
	if k.level_reached.get("orbital_scan_done", false):
		return CommandResult.fail("already_scanned", "Planeten er allerede scannet fra kredsløb.")
	var changed := k.apply_level(content.planet(planet_id), "orbital", "Orbital scanning")
	k.level_reached["orbital_scan_done"] = true
	# Coarse terrain for every candidate site: enough to choose where to probe.
	for sid: Variant in DictUtil.get_arr(content.planet(planet_id), "site_templates"):
		var facts: Dictionary = DictUtil.get_dict(content.site(str(sid)), "facts")
		if k.reveal_site_fact(str(sid), "flatness", facts.get("flatness"), "Orbital scanning"):
			changed.append("site:%s:flatness" % sid)
	gs.campaign.elapsed_days += 1
	gs.log_journal("Orbital scanning af %s: %d egenskaber præciseret." % [content.planet(planet_id).get("name"), changed.size()], "survey")
	return CommandResult.success({"changed": changed})


## site_id empty = long-range probe (reveals orbital-level data from afar).
## site_id set = site probe; requires orbit; reveals probe-level data + site facts.
func launch_probe(gs: GameState, planet_id: String, site_id: String, txn: String) -> CommandResult:
	if gs.is_applied(txn):
		return CommandResult.fail("duplicate_txn", "Sonden er allerede sendt.")
	if gs.campaign.phase != CampaignState.PHASE_VOYAGE:
		return CommandResult.fail("wrong_phase", "Sonder kan kun sendes under rejsen.")
	var p := content.planet(planet_id)
	if p.is_empty():
		return CommandResult.fail("unknown_planet", "Ukendt planet '%s'." % planet_id)
	var k := gs.knowledge_of(planet_id)
	var cost := int(content.bal("probe_component_cost", 3))
	var here := str(content.locations.get(gs.campaign.location_id, {}).get("planet_id", ""))
	if site_id.is_empty():
		if k.level_reached.has("orbital"):
			return CommandResult.fail("no_new_knowledge", "En fjernsonde vil ikke lære os mere om %s. Rejs dertil for en sitesonde." % p.get("name"))
	else:
		if not site_id in DictUtil.get_arr(p, "site_templates"):
			return CommandResult.fail("unknown_site", "Sitet '%s' findes ikke på %s." % [site_id, p.get("name")])
		if here != planet_id:
			return CommandResult.fail("not_in_orbit", "En sitesonde kræver, at arken er i kredsløb.")
		if site_id in k.probed_sites:
			return CommandResult.fail("already_probed", "Der står allerede en sonde på dette site.")
	if gs.ark.components < cost:
		return CommandResult.fail("insufficient_components", "Sonden kræver %d komponenter (har %d)." % [cost, gs.ark.components])
	gs.ark.components -= cost
	var changed: Array = []
	if site_id.is_empty():
		changed = k.apply_level(p, "orbital", "Fjernsonde")
	else:
		changed = k.apply_level(p, "probe", "Sonde: " + str(content.site(site_id).get("name", site_id)))
		k.probed_sites.append(site_id)
		var facts: Dictionary = DictUtil.get_dict(content.site(site_id), "facts")
		for f: String in ["water_distance_m", "vent"]:
			if k.reveal_site_fact(site_id, f, facts.get(f), "Sonde"):
				changed.append("site:%s" % f)
		# One site-specific risk signal.
		k.reveal_site_fact(site_id, "exposure", facts.get("exposure"), "Sonde")
	gs.mark_applied(txn)
	gs.log_journal("Sonde til %s%s: %d nye oplysninger." % [p.get("name"), "" if site_id.is_empty() else " (" + str(content.site(site_id).get("name")) + ")", changed.size()], "survey")
	return CommandResult.success({"changed": changed, "components": gs.ark.components})


## Compact comparison row for the planet comparison UI (known vs. missing, bible p.13).
func comparison(gs: GameState, planet_id: String) -> Dictionary:
	var p := content.planet(planet_id)
	var k := gs.knowledge_of(planet_id)
	var rows := {}
	for prop: String in DictUtil.get_dict(p, "properties").keys():
		var obs: Dictionary = k.observations.get(prop, {"status": "unknown"})
		var pdef: Dictionary = p["properties"][prop]
		rows[prop] = {"status": obs.get("status"), "text": format_observation(pdef, obs), "source": obs.get("source", ""), "confidence": obs.get("confidence", 0.0)}
	var known := 0
	for prop: String in rows.keys():
		if rows[prop]["status"] == "known":
			known += 1
	return {"planet_id": planet_id, "rows": rows, "known_count": known, "total": rows.size()}


static func format_observation(pdef: Dictionary, obs: Dictionary) -> String:
	var unit := str(pdef.get("unit", ""))
	match str(obs.get("status")):
		"known":
			var v: Variant = obs.get("value")
			if v is float or v is int:
				return "%s %s" % [_fmt(float(v)), unit]
			return ATMOSPHERE_LABELS.get(str(v), str(v))
		"estimated":
			if obs.has("candidates"):
				var labels: Array = []
				for c: Variant in obs.get("candidates"):
					labels.append(ATMOSPHERE_LABELS.get(str(c), str(c)))
				return " / ".join(labels) + " ?"
			return "%s – %s %s" % [_fmt(float(obs.get("min"))), _fmt(float(obs.get("max"))), unit]
		_:
			return "ukendt"


static func _fmt(v: float) -> String:
	if absf(v - roundf(v)) < 0.001:
		return str(int(roundf(v)))
	return "%.2f" % v


const ATMOSPHERE_LABELS := {
	"breathable": "åndbar",
	"breathable_spores": "åndbar m. sporer",
	"breathable_humid": "åndbar, fugtig",
	"thin_dry": "tynd og tør",
	"thin_dusty": "tynd og støvet",
	"thin_cold": "tynd og kold",
	"inert_thin": "tynd, inaktiv",
}

const PROPERTY_LABELS := {
	"gravity_multiplier": "Tyngde",
	"mean_temperature_c": "Middeltemperatur",
	"atmosphere_class": "Atmosfære",
	"water_access": "Vandadgang",
	"mineral_yield": "Mineraludbytte",
	"solar_factor": "Solenergi",
	"geothermal_factor": "Geotermi",
	"biological_risk": "Biologisk risiko",
}

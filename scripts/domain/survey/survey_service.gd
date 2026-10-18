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
		return CommandResult.fail("unknown_planet", Loc.t("Unknown planet '%s'.") % planet_id)
	var here := str(content.locations.get(gs.campaign.location_id, {}).get("planet_id", ""))
	if here != planet_id:
		return CommandResult.fail("not_in_orbit", Loc.t("Orbital scanning requires the Ark to be in orbit around %s.") % content.planet(planet_id).get("name"))
	var k := gs.knowledge_of(planet_id)
	if k.level_reached.get("orbital_scan_done", false):
		return CommandResult.fail("already_scanned", Loc.t("The planet has already been scanned from orbit."))
	var changed := k.apply_level(content.planet(planet_id), "orbital", Loc.t("Orbital scan"))
	k.level_reached["orbital_scan_done"] = true
	# Coarse terrain for every candidate site: enough to choose where to probe.
	for sid: Variant in DictUtil.get_arr(content.planet(planet_id), "site_templates"):
		var facts: Dictionary = DictUtil.get_dict(content.site(str(sid)), "facts")
		if k.reveal_site_fact(str(sid), "flatness", facts.get("flatness"), Loc.t("Orbital scan")):
			changed.append("site:%s:flatness" % sid)
	gs.campaign.elapsed_days += 1
	gs.log_journal(Loc.t("Orbital scan of %s: %d properties refined.") % [content.planet(planet_id).get("name"), changed.size()], "survey")
	return CommandResult.success({"changed": changed})


## site_id empty = long-range probe (reveals orbital-level data from afar).
## site_id set = site probe; requires orbit; reveals probe-level data + site facts.
func launch_probe(gs: GameState, planet_id: String, site_id: String, txn: String) -> CommandResult:
	if gs.is_applied(txn):
		return CommandResult.fail("duplicate_txn", Loc.t("The probe has already been sent."))
	if gs.campaign.phase != CampaignState.PHASE_VOYAGE:
		return CommandResult.fail("wrong_phase", Loc.t("Probes can only be sent during the voyage."))
	var p := content.planet(planet_id)
	if p.is_empty():
		return CommandResult.fail("unknown_planet", Loc.t("Unknown planet '%s'.") % planet_id)
	var k := gs.knowledge_of(planet_id)
	var cost := int(content.bal("probe_component_cost", 3))
	var here := str(content.locations.get(gs.campaign.location_id, {}).get("planet_id", ""))
	if site_id.is_empty():
		if k.level_reached.has("orbital"):
			return CommandResult.fail("no_new_knowledge", Loc.t("A remote probe won't teach us more about %s. Travel there for a site probe.") % p.get("name"))
	else:
		if not site_id in DictUtil.get_arr(p, "site_templates"):
			return CommandResult.fail("unknown_site", Loc.t("The site '%s' does not exist on %s.") % [site_id, p.get("name")])
		if here != planet_id:
			return CommandResult.fail("not_in_orbit", Loc.t("A site probe requires the Ark to be in orbit."))
		if site_id in k.probed_sites:
			return CommandResult.fail("already_probed", Loc.t("There is already a probe at this site."))
	if gs.ark.components < cost:
		return CommandResult.fail("insufficient_components", Loc.t("The probe requires %d components (have %d).") % [cost, gs.ark.components])
	gs.ark.components -= cost
	var changed: Array = []
	if site_id.is_empty():
		changed = k.apply_level(p, "orbital", Loc.t("Remote probe"))
	else:
		changed = k.apply_level(p, "probe", Loc.t("Probe: ") + str(content.site(site_id).get("name", site_id)))
		k.probed_sites.append(site_id)
		var facts: Dictionary = DictUtil.get_dict(content.site(site_id), "facts")
		for f: String in ["water_distance_m", "vent"]:
			if k.reveal_site_fact(site_id, f, facts.get(f), Loc.t("Probe")):
				changed.append("site:%s" % f)
		# One site-specific risk signal.
		k.reveal_site_fact(site_id, "exposure", facts.get("exposure"), Loc.t("Probe"))
	gs.mark_applied(txn)
	gs.log_journal(Loc.t("Probe to %s%s: %d new findings.") % [p.get("name"), "" if site_id.is_empty() else " (" + str(content.site(site_id).get("name")) + ")", changed.size()], "survey")
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
			return Loc.t(str(ATMOSPHERE_LABELS.get(str(v), str(v))))
		"estimated":
			if obs.has("candidates"):
				var labels: Array = []
				for c: Variant in obs.get("candidates"):
					labels.append(Loc.t(str(ATMOSPHERE_LABELS.get(str(c), str(c)))))
				return " / ".join(labels) + " ?"
			return "%s – %s %s" % [_fmt(float(obs.get("min"))), _fmt(float(obs.get("max"))), unit]
		_:
			return Loc.t("unknown")


static func _fmt(v: float) -> String:
	if absf(v - roundf(v)) < 0.001:
		return str(int(roundf(v)))
	return "%.2f" % v


const ATMOSPHERE_LABELS := {
	"breathable": "breathable",
	"breathable_spores": "breathable w. spores",
	"breathable_humid": "breathable, humid",
	"thin_dry": "thin and dry",
	"thin_dusty": "thin and dusty",
	"thin_cold": "thin and cold",
	"inert_thin": "thin, inert",
}

const PROPERTY_LABELS := {
	"gravity_multiplier": "Gravity",
	"mean_temperature_c": "Mean temperature",
	"atmosphere_class": "Atmosphere",
	"water_access": "Water access",
	"mineral_yield": "Mineral yield",
	"solar_factor": "Solar energy",
	"geothermal_factor": "Geothermal",
	"biological_risk": "Biological risk",
}

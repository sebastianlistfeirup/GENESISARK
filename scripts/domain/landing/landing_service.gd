class_name LandingService
extends RefCounted
## The commitment point (bible p.8, GA-07): phase VOYAGE -> SETTLED exactly once.
## The ark becomes habitat and power support; its leftovers become colony stock.

var content: ContentDB


func _init(db: ContentDB) -> void:
	content = db


func preview(gs: GameState, site_id: String) -> Dictionary:
	var pid := str(content.locations.get(gs.campaign.location_id, {}).get("planet_id", ""))
	var p := content.planet(pid)
	var site := content.site(site_id)
	var k: PlanetKnowledge = gs.knowledge_of(pid) if not pid.is_empty() else null
	var out := {"ok": false, "reasons": [], "planet_id": pid, "site_id": site_id}
	if gs.campaign.phase != CampaignState.PHASE_VOYAGE:
		out["reasons"].append("Landing er kun mulig under rejsen.")
	if p.is_empty():
		out["reasons"].append("Arken er ikke i kredsløb om en planet.")
		return out
	if site.is_empty() or not site_id in DictUtil.get_arr(p, "site_templates"):
		out["reasons"].append("Ukendt landingssite.")
		return out
	var known_risks: Array = []
	var unknown: Array = []
	for hid: Variant in DictUtil.get_arr(p, "hazard_ids"):
		var h: Dictionary = content.hazards.get(str(hid), {})
		if k.status_of("biological_risk") != "unknown" or k.level_reached.has("orbital"):
			known_risks.append(str(h.get("name", hid)) + ": " + str(h.get("description", "")))
		else:
			unknown.append("Lokale farer er ikke kortlagt.")
	for prop: String in ["water_access", "solar_factor", "geothermal_factor", "mineral_yield"]:
		if k.status_of(prop) == "unknown":
			unknown.append("%s er ukendt." % SurveyService.PROPERTY_LABELS.get(prop, prop))
	var start: Dictionary = content.bal("colony_start", {})
	out["known_risks"] = known_risks
	out["unknowns"] = unknown
	out["site_facts"] = k.site_facts.get(site_id, {})
	out["start_inventory"] = {
		"alloy": DictUtil.get_float(start, "alloy"), "components": float(gs.ark.components),
		"water": DictUtil.get_float(start, "water"), "food": DictUtil.get_float(start, "food"),
	}
	out["energy_plan"] = "Arkens nødstrøm giver %d kW, så længe brændstoffet rækker (%.0f enheder ≈ %d dage)." % [
		int(content.bal("ark_core.power_kw", 8)), gs.ark.fuel, int(gs.ark.fuel / maxf(0.01, float(content.building("ark_core").get("provides", {}).get("fuel_per_day", 0.1))))]
	out["can_continue_journey"] = gs.ark.fuel > 0.0
	out["advantage"] = p.get("advantage", "")
	out["price"] = p.get("price", "")
	out["ok"] = (out["reasons"] as Array).is_empty()
	return out


func commit_landing(gs: GameState, site_id: String, txn: String) -> CommandResult:
	if gs.is_applied(txn) or not gs.campaign.landing_txn.is_empty():
		return CommandResult.fail("already_landed", "Landingen er allerede gennemført og kan ikke gentages.")
	var pv := preview(gs, site_id)
	if not pv["ok"]:
		return CommandResult.fail("landing_blocked", "; ".join(pv["reasons"]), pv)
	var pid := str(pv["planet_id"])
	var p := content.planet(pid)
	var site := content.site(site_id)
	var c := ColonyState.new()
	c.planet_id = pid
	c.biome_id = str(p.get("biome_id"))
	c.site_id = site_id
	var inv: Dictionary = pv["start_inventory"]
	c.inventory = {"alloy": float(inv["alloy"]), "components": float(inv["components"]),
		"water": float(inv["water"]), "food": float(inv["food"])}
	c.ark_fuel = gs.ark.fuel
	c.salvage_left = float(content.building("ark_core").get("provides", {}).get("salvage_pool", 300))
	var landing_center: Array = DictUtil.get_arr(DictUtil.get_dict(DictUtil.get_dict(site, "districts"), "landing"), "center")
	c.buildings.append({
		"id": c.next_building_id, "def_id": "ark_core", "x": float(landing_center[0]), "z": float(landing_center[1]), "rot": 0,
		"state": ColonyState.B_ACTIVE, "progress": 1.0, "modules": [], "wear": 0.0,
		"powered": true, "accessible": true, "efficiency": 1.0, "blocked_reason": "",
	})
	c.next_building_id += 1
	gs.colony = c
	gs.ark.components = 0  # Transferred to colony stock
	gs.expedition = null
	gs.campaign.phase = CampaignState.PHASE_SETTLED
	gs.campaign.act = 2
	gs.campaign.selected_planet_id = pid
	gs.campaign.landing_site_id = site_id
	gs.campaign.landing_txn = txn
	gs.mark_applied(txn)
	gs.log_journal("Arken er landet på %s, %s. Herfra er der ingen vej tilbage." % [p.get("name"), site.get("name")], "landing")
	return CommandResult.success({"planet_id": pid, "site_id": site_id})

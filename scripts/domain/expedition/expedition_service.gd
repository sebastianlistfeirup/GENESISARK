class_name ExpeditionService
extends RefCounted
## Captain's surface expedition (bible p.8, GA-06). Runtime reports positions and
## time; this service owns suit energy, samples and the knowledge they produce.

signal reserve_warning
signal suit_depleted

var content: ContentDB


func _init(db: ContentDB) -> void:
	content = db


func survey_for(planet_id: String) -> Dictionary:
	return content.surveys.get(planet_id, {})


func start(gs: GameState, site_id: String, plan_drone_reserve: bool) -> CommandResult:
	if gs.campaign.phase != CampaignState.PHASE_VOYAGE:
		return CommandResult.fail("wrong_phase", "Ekspeditioner kræver, at arken er i kredsløb før landing.")
	if gs.expedition != null and gs.expedition.status == ExpeditionState.STATUS_ACTIVE:
		return CommandResult.fail("already_active", "En ekspedition er allerede i gang.")
	var pid := str(content.locations.get(gs.campaign.location_id, {}).get("planet_id", ""))
	if pid.is_empty():
		return CommandResult.fail("not_in_orbit", "Arken er ikke i kredsløb om en planet.")
	if not site_id in DictUtil.get_arr(content.planet(pid), "site_templates"):
		return CommandResult.fail("unknown_site", "Sitet findes ikke på denne planet.")
	if pid in _done_planets(gs) and site_id in gs.knowledge_of(pid).expedition_sites:
		return CommandResult.fail("already_explored", "Dette site er allerede udforsket.")
	var reserve_cost := 2 if plan_drone_reserve else 0
	if gs.ark.components < reserve_cost:
		return CommandResult.fail("insufficient_components", "Dronereserven kræver %d komponenter." % reserve_cost)
	gs.ark.components -= reserve_cost
	var ex := ExpeditionState.new()
	ex.planet_id = pid
	ex.site_id = site_id
	ex.survey_id = str(survey_for(pid).get("id", ""))
	ex.suit_energy = float(content.bal("suit.max_energy", 100.0))
	ex.drone_refill_available = plan_drone_reserve
	gs.expedition = ex
	return CommandResult.success({"site_id": site_id, "planet_id": pid})


func _done_planets(gs: GameState) -> Array:
	var out: Array = []
	for pid: String in gs.knowledge.keys():
		if not gs.knowledge_of(pid).expedition_sites.is_empty():
			out.append(pid)
	return out


## Advances suit drain. hazard_multiplier comes from the runtime (inside hazard zone).
func tick(gs: GameState, dt: float, hazard_multiplier: float = 1.0) -> void:
	var ex := gs.expedition
	if ex == null or ex.status != ExpeditionState.STATUS_ACTIVE:
		return
	ex.elapsed_s += dt
	ex.suit_energy = maxf(0.0, ex.suit_energy - float(content.bal("suit.drain_per_s", 0.12)) * maxf(1.0, hazard_multiplier) * dt)
	if not ex.warned_reserve and ex.suit_energy <= float(content.bal("suit.reserve_warning", 30.0)):
		ex.warned_reserve = true
		reserve_warning.emit()
	if ex.suit_energy <= 0.0:
		_recall(gs)


func use_drone_refill(gs: GameState) -> CommandResult:
	var ex := gs.expedition
	if ex == null or ex.status != ExpeditionState.STATUS_ACTIVE:
		return CommandResult.fail("no_expedition", "Ingen aktiv ekspedition.")
	if not ex.drone_refill_available or ex.drone_refill_used:
		return CommandResult.fail("no_refill", "Ingen planlagt dronereserve tilbage.")
	ex.drone_refill_used = true
	ex.suit_energy = minf(float(content.bal("suit.max_energy", 100.0)), ex.suit_energy + float(content.bal("suit.drone_refill", 35.0)))
	ex.warned_reserve = ex.suit_energy <= float(content.bal("suit.reserve_warning", 30.0))
	return CommandResult.success({"suit_energy": ex.suit_energy})


## point_id: "main_sample" | "risk_sample". Runtime has already checked the 8 s sampling.
func take_sample(gs: GameState, point_id: String) -> CommandResult:
	var ex := gs.expedition
	if ex == null or ex.status != ExpeditionState.STATUS_ACTIVE:
		return CommandResult.fail("no_expedition", "Ingen aktiv ekspedition.")
	var sv := survey_for(ex.planet_id)
	var point: Dictionary = DictUtil.get_dict(DictUtil.get_dict(sv, "points"), point_id)
	if point.is_empty() or not point_id.ends_with("sample"):
		return CommandResult.fail("unknown_point", "Ukendt prøvepunkt '%s'." % point_id)
	if point_id in ex.samples:
		return CommandResult.fail("already_sampled", "Prøven er allerede taget.")
	ex.samples.append(point_id)
	if point_id == "risk_sample":
		ex.risk_sample_taken = true
	for prop: Variant in DictUtil.get_arr(point, "reveals"):
		ex.extracted.append("prop:%s" % prop)
	for fact: Variant in DictUtil.get_arr(point, "site_facts"):
		ex.extracted.append("fact:%s" % fact)
	return CommandResult.success({"point": point_id, "text": point.get("text", "")})


func place_relay(gs: GameState) -> CommandResult:
	var ex := gs.expedition
	if ex == null or ex.status != ExpeditionState.STATUS_ACTIVE:
		return CommandResult.fail("no_expedition", "Ingen aktiv ekspedition.")
	if ex.relay_placed:
		return CommandResult.fail("already_placed", "Relæet står der allerede.")
	ex.relay_placed = true
	ex.extracted.append("fact:landing_quality")
	return CommandResult.success({})


## Captain is back at the lander: results become knowledge (once).
func finish(gs: GameState, txn: String) -> CommandResult:
	var ex := gs.expedition
	if ex == null:
		return CommandResult.fail("no_expedition", "Ingen ekspedition.")
	if gs.is_applied(txn):
		return CommandResult.fail("duplicate_txn", "Ekspeditionen er allerede afsluttet.")
	if ex.status == ExpeditionState.STATUS_ACTIVE:
		ex.status = ExpeditionState.STATUS_RETURNED
	var applied := _apply_results(gs, ex)
	gs.mark_applied(txn)
	gs.campaign.elapsed_days += 1
	return CommandResult.success({"status": ex.status, "applied": applied, "samples": ex.samples.size()})


func _recall(gs: GameState) -> void:
	var ex := gs.expedition
	ex.status = ExpeditionState.STATUS_RECALLED
	# Unsecured risk-sample data is lost in the forced return; main results are kept.
	if ex.risk_sample_taken and not ex.relay_placed:
		var kept: Array = []
		var risk_point: Dictionary = DictUtil.get_dict(DictUtil.get_dict(survey_for(ex.planet_id), "points"), "risk_sample")
		var lost: Array = []
		for prop: Variant in DictUtil.get_arr(risk_point, "reveals"):
			lost.append("prop:%s" % prop)
		for e: Variant in ex.extracted:
			if not e in lost:
				kept.append(e)
		ex.extracted = kept
	gs.log_journal("Dragtens energi slap op. ARK trak kaptajnen tilbage til landeren.", "warning")
	suit_depleted.emit()


func _apply_results(gs: GameState, ex: ExpeditionState) -> Array:
	var k := gs.knowledge_of(ex.planet_id)
	var p := content.planet(ex.planet_id)
	var props: Dictionary = DictUtil.get_dict(p, "properties")
	var changed: Array = []
	var site_name := str(content.site(ex.site_id).get("name", ex.site_id))
	for e: Variant in ex.extracted:
		var s := str(e)
		if s.begins_with("prop:"):
			var prop := s.substr(5)
			if props.has(prop) and k.status_of(prop) != "known":
				k.observations[prop] = {"status": "known", "value": props[prop].get("truth"), "confidence": 1.0, "source": "Ekspedition: " + site_name}
				changed.append(prop)
		elif s.begins_with("fact:"):
			var fact := s.substr(5)
			var facts: Dictionary = DictUtil.get_dict(content.site(ex.site_id), "facts")
			if k.reveal_site_fact(ex.site_id, fact, facts.get(fact), "Ekspedition"):
				changed.append("site:" + fact)
	if ex.status == ExpeditionState.STATUS_RETURNED and ex.samples.size() > 0:
		changed.append_array(k.apply_level(p, "expedition", "Ekspedition: " + site_name))
	if not ex.site_id in k.expedition_sites:
		k.expedition_sites.append(ex.site_id)
	gs.log_journal("Ekspedition på %s afsluttet: %d nye oplysninger." % [site_name, changed.size()], "survey")
	return changed

class_name GameState
extends RefCounted
## The single CampaignState aggregate that binds voyage, expedition and colony
## together (bible p.14). Pure data + serialisation; no Node references.

const SCHEMA_VERSION := 2

var game_id: String = ""
var seed_value: int = 0
var rng: DetRng
var campaign: CampaignState
var ark: ArkState
var knowledge: Dictionary = {}       # planet_id -> PlanetKnowledge
var expedition: ExpeditionState = null
var colony: ColonyState = null
var population: PopulationState
var society: SocietyState
var events: EventState


static func create_new(content: ContentDB, new_seed: int, id: String = "") -> GameState:
	var gs := GameState.new()
	gs.seed_value = new_seed
	gs.game_id = id if not id.is_empty() else "ga-%d" % new_seed
	gs.rng = DetRng.new(new_seed)
	gs.campaign = CampaignState.new()
	gs.campaign.location_id = content.start_location
	gs.campaign.visited = [content.start_location]
	gs.ark = ArkState.new()
	var start: Dictionary = content.bal("ark_start", {})
	gs.ark.fuel = DictUtil.get_float(start, "fuel", 100.0)
	gs.ark.integrity = DictUtil.get_float(start, "integrity", 100.0)
	gs.ark.components = DictUtil.get_int(start, "components", 40)
	gs.ark.oxygen = DictUtil.get_float(start, "oxygen", 100.0)
	for pid: String in content.planet_ids_sorted():
		gs.knowledge[pid] = PlanetKnowledge.create(content.planet(pid))
	gs.population = PopulationState.new()
	gs.society = SocietyState.new()
	gs.events = EventState.new()
	return gs


func knowledge_of(planet_id: String) -> PlanetKnowledge:
	return knowledge.get(planet_id)


func is_applied(txn: String) -> bool:
	return txn in campaign.event_ids


func mark_applied(txn: String) -> void:
	if not txn.is_empty() and not txn in campaign.event_ids:
		campaign.event_ids.append(txn)


func log_journal(text: String, kind: String = "info") -> void:
	campaign.journal.append({"day": campaign.elapsed_days + campaign.colony_day, "text": text, "kind": kind})
	if campaign.journal.size() > 200:
		campaign.journal = campaign.journal.slice(campaign.journal.size() - 200)


func to_dict() -> Dictionary:
	var k := {}
	for pid: String in knowledge.keys():
		k[pid] = (knowledge[pid] as PlanetKnowledge).to_dict()
	return {
		"schema_version": SCHEMA_VERSION,
		"game_id": game_id,
		"seed": str(seed_value),
		"rng": rng.to_dict(),
		"campaign": campaign.to_dict(),
		"ark": ark.to_dict(),
		"knowledge": k,
		"expedition": expedition.to_dict() if expedition else null,
		"colony": colony.to_dict() if colony else null,
		"population": population.to_dict(),
		"society": society.to_dict(),
		"events": events.to_dict(),
	}


static func from_dict(d: Dictionary) -> GameState:
	var gs := GameState.new()
	gs.game_id = DictUtil.get_str(d, "game_id")
	gs.seed_value = int(str(d.get("seed", "0")))
	gs.rng = DetRng.from_dict(DictUtil.get_dict(d, "rng"))
	gs.campaign = CampaignState.from_dict(DictUtil.get_dict(d, "campaign"))
	gs.ark = ArkState.from_dict(DictUtil.get_dict(d, "ark"))
	var k: Dictionary = DictUtil.get_dict(d, "knowledge")
	for pid: String in k.keys():
		gs.knowledge[pid] = PlanetKnowledge.from_dict(k[pid])
	var ex: Variant = d.get("expedition")
	gs.expedition = ExpeditionState.from_dict(ex) if ex is Dictionary else null
	var col: Variant = d.get("colony")
	gs.colony = ColonyState.from_dict(col) if col is Dictionary else null
	gs.population = PopulationState.from_dict(DictUtil.get_dict(d, "population"))
	gs.society = SocietyState.from_dict(DictUtil.get_dict(d, "society"))
	gs.events = EventState.from_dict(DictUtil.get_dict(d, "events"))
	return gs


## Replaces this state's contents with another's (used when an approved era
## forecast is adopted as the result: identical by determinism).
func assign_from(o: GameState) -> void:
	game_id = o.game_id
	seed_value = o.seed_value
	rng = o.rng
	campaign = o.campaign
	ark = o.ark
	knowledge = o.knowledge
	expedition = o.expedition
	colony = o.colony
	population = o.population
	society = o.society
	events = o.events


## Validates types, ID references and value ranges before a state is activated (bible p.22).
func validation_errors(content: ContentDB) -> PackedStringArray:
	var out: PackedStringArray = []
	out.append_array(ark.invariant_errors())
	if not content.locations.has(campaign.location_id):
		out.append(Loc.t("ukendt location_id '%s'") % campaign.location_id)
	if not campaign.selected_planet_id.is_empty() and not content.planets.has(campaign.selected_planet_id):
		out.append(Loc.t("ukendt planet '%s'") % campaign.selected_planet_id)
	if not campaign.phase in [CampaignState.PHASE_ARK, CampaignState.PHASE_VOYAGE, CampaignState.PHASE_SETTLED, CampaignState.PHASE_ENDED]:
		out.append(Loc.t("ukendt fase '%s'") % campaign.phase)
	for pid: String in knowledge.keys():
		if not content.planets.has(pid):
			out.append(Loc.t("viden om ukendt planet '%s'") % pid)
	if campaign.phase == CampaignState.PHASE_SETTLED and colony == null:
		out.append(Loc.t("fase SETTLED uden koloni"))
	if colony:
		out.append_array(colony.invariant_errors())
		if not content.sites.has(colony.site_id):
			out.append(Loc.t("koloni på ukendt site '%s'") % colony.site_id)
		for b: Dictionary in colony.buildings:
			if not content.buildings.has(str(b.get("def_id"))):
				out.append(Loc.t("ukendt bygning '%s'") % b.get("def_id"))
	# Born is historical; population is alive. Born must cover everyone who ever lived.
	if population.alive_count() + population.deaths > ark.embryo_born:
		out.append(Loc.t("befolkning (%d) + døde overstiger fødte (%d)") % [population.alive_count(), ark.embryo_born])
	if population.count_stage("incubating") != ark.embryo_incubating:
		out.append(Loc.t("inkuberende kohorter (%d) != ledger incubating (%d)") % [population.count_stage("incubating"), ark.embryo_incubating])
	return out

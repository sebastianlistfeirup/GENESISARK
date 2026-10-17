class_name Simulation
extends RefCounted
## Wires every domain service around one GameState. Pure logic: usable from
## headless tests, the era forecaster and the GameSession autoload alike.

var content: ContentDB
var state: GameState
var objectives: ObjectiveService
var ark: ArkService
var travel: TravelService
var survey: SurveyService
var expedition: ExpeditionService
var landing: LandingService
var colony: ColonySimulation
var population: PopulationService
var events: EventService
var society: SocietyService
var days: DaySimulator
var era: EraService
var endings: EndingService


func _init(db: ContentDB, gs: GameState = null) -> void:
	content = db
	state = gs
	objectives = ObjectiveService.new(db)
	ark = ArkService.new(db)
	travel = TravelService.new(db)
	survey = SurveyService.new(db)
	expedition = ExpeditionService.new(db)
	landing = LandingService.new(db)
	colony = ColonySimulation.new(db)
	population = PopulationService.new(db, colony)
	events = EventService.new(db, population)
	society = SocietyService.new(db)
	days = DaySimulator.new(db, colony, population, events, society)
	era = EraService.new(db, days)
	endings = EndingService.new(db, colony, population)


static func new_campaign(db: ContentDB, seed_value: int) -> Simulation:
	return Simulation.new(db, GameState.create_new(db, seed_value))


## Checksum of the canonical state: equal checksums mean identical simulations.
func checksum() -> String:
	return DictUtil.sha256(DictUtil.canonical_json(state.to_dict()))


## Automatic objective bookkeeping after any state change. Returns newly completed ids.
func update_objectives() -> Array:
	var gs := state
	var done: Array = []
	var checks := {
		"obj_restore_power": gs.ark.systems.get("power") != "offline",
		"obj_check_embryo_bank": bool(gs.ark.systems.get("embryo_bank_checked", false)),
		"obj_wake": bool(gs.ark.systems.get("workshop_checked", false)) or gs.ark.systems.get("power") != "offline",
		"obj_open_starmap": bool(gs.ark.systems.get("starmap_opened", false)),
		"obj_choose_probe": _any_probe(),
		"obj_travel": gs.campaign.visited.size() > 1,
		"obj_orbital_scan": _any_level("orbital_scan_done"),
		"obj_expedition": _any_expedition(),
		"obj_commit_landing": gs.campaign.phase == CampaignState.PHASE_SETTLED or gs.campaign.phase == CampaignState.PHASE_ENDED,
	}
	if gs.colony:
		checks["obj_build_power"] = gs.colony.count_active("solar_array") + gs.colony.count_active("geothermal_generator") > 0
		checks["obj_build_water"] = gs.colony.count_active("water_plant") > 0
		checks["obj_build_habitat"] = gs.colony.count_active("habitat") > 0
		checks["obj_stable_supply"] = int(gs.colony.stats.get("days_stable", 0)) >= 7 and gs.colony.count_active("water_plant") > 0
		checks["obj_care_center"] = gs.colony.count_active("care_center") > 0
		checks["obj_first_cohort"] = gs.population.cohorts.size() > 0
		checks["obj_first_birth"] = gs.ark.embryo_born > 0
		checks["obj_school"] = gs.colony.count_active("school_hall") > 0
		checks["obj_council"] = gs.society.council_formed
		checks["obj_year_20"] = gs.campaign.colony_year() >= 20.0
		checks["obj_year_40_500"] = gs.campaign.colony_year() >= 40.0 and gs.population.alive_count() >= 500
	for id: String in checks.keys():
		if checks[id] and not id in gs.campaign.completed_objectives and content.objectives.has(id):
			objectives.complete(gs, id)
			done.append(id)
	return done


func _any_probe() -> bool:
	for pid: String in state.knowledge.keys():
		var k: PlanetKnowledge = state.knowledge[pid]
		if k.level_reached.has("orbital") or not k.probed_sites.is_empty():
			return true
	return false


func _any_level(flag: String) -> bool:
	for pid: String in state.knowledge.keys():
		if (state.knowledge[pid] as PlanetKnowledge).level_reached.get(flag, false):
			return true
	return false


func _any_expedition() -> bool:
	for pid: String in state.knowledge.keys():
		if not (state.knowledge[pid] as PlanetKnowledge).expedition_sites.is_empty():
			return true
	return false

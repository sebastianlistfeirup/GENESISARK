class_name CampaignState
extends RefCounted
## Top-level campaign progress. Owner: CampaignService (bible p.14).

const PHASE_ARK := "ARK"            # On board, before power is restored
const PHASE_VOYAGE := "VOYAGE"      # Ark can travel and scout
const PHASE_SETTLED := "SETTLED"    # Landing committed; colony exists
const PHASE_ENDED := "ENDED"        # Hand-over / epilogue reached

var phase: String = PHASE_ARK
var act: int = 1
var elapsed_days: int = 0           # Ship-time days since awakening
var colony_day: int = 0             # Colony days since landing
var captain_stasis_years: float = 0.0
var location_id: String = "drift"
var selected_planet_id: String = ""
var landing_site_id: String = ""
var landing_txn: String = ""
var completed_objectives: Array = []  # objective ids, each rewarded once
var event_ids: Array = []             # applied event/transaction ids (idempotency)
var journal: Array = []               # [{day, text, kind}]
var visited: Array = []               # location ids
var ending_id: String = ""
var final_state: Dictionary = {}


func colony_year() -> float:
	return float(colony_day) / 365.0


func to_dict() -> Dictionary:
	return {
		"phase": phase, "act": act, "elapsed_days": elapsed_days, "colony_day": colony_day,
		"captain_stasis_years": captain_stasis_years, "location_id": location_id,
		"selected_planet_id": selected_planet_id, "landing_site_id": landing_site_id,
		"landing_txn": landing_txn, "completed_objectives": completed_objectives.duplicate(),
		"event_ids": event_ids.duplicate(), "journal": journal.duplicate(true),
		"visited": visited.duplicate(), "ending_id": ending_id, "final_state": final_state.duplicate(true),
	}


static func from_dict(d: Dictionary) -> CampaignState:
	var s := CampaignState.new()
	s.phase = DictUtil.get_str(d, "phase", PHASE_ARK)
	s.act = DictUtil.get_int(d, "act", 1)
	s.elapsed_days = DictUtil.get_int(d, "elapsed_days")
	s.colony_day = DictUtil.get_int(d, "colony_day")
	s.captain_stasis_years = DictUtil.get_float(d, "captain_stasis_years")
	s.location_id = DictUtil.get_str(d, "location_id", "drift")
	s.selected_planet_id = DictUtil.get_str(d, "selected_planet_id")
	s.landing_site_id = DictUtil.get_str(d, "landing_site_id")
	s.landing_txn = DictUtil.get_str(d, "landing_txn")
	s.completed_objectives = DictUtil.get_arr(d, "completed_objectives").duplicate()
	s.event_ids = DictUtil.get_arr(d, "event_ids").duplicate()
	s.journal = DictUtil.get_arr(d, "journal").duplicate(true)
	s.visited = DictUtil.get_arr(d, "visited").duplicate()
	s.ending_id = DictUtil.get_str(d, "ending_id")
	s.final_state = DictUtil.get_dict(d, "final_state").duplicate(true)
	return s

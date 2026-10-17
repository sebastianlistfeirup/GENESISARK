class_name ExpeditionState
extends RefCounted
## A captain's surface expedition on one site. Real-time; owner: ExpeditionService.

const STATUS_ACTIVE := "active"
const STATUS_RETURNED := "returned"     # Back at the lander with results
const STATUS_RECALLED := "recalled"     # Suit depleted: forced, announced return (no campaign lock)

var planet_id: String = ""
var site_id: String = ""
var survey_id: String = ""
var status: String = STATUS_ACTIVE
var suit_energy: float = 100.0
var drone_refill_available: bool = false
var drone_refill_used: bool = false
var samples: Array = []           # sample point ids taken
var extracted: Array = []         # facts extracted from samples
var relay_placed: bool = false
var risk_sample_taken: bool = false
var warned_reserve: bool = false
var elapsed_s: float = 0.0


func to_dict() -> Dictionary:
	return {
		"planet_id": planet_id, "site_id": site_id, "survey_id": survey_id, "status": status,
		"suit_energy": suit_energy, "drone_refill_available": drone_refill_available,
		"drone_refill_used": drone_refill_used, "samples": samples.duplicate(),
		"extracted": extracted.duplicate(), "relay_placed": relay_placed,
		"risk_sample_taken": risk_sample_taken, "warned_reserve": warned_reserve, "elapsed_s": elapsed_s,
	}


static func from_dict(d: Dictionary) -> ExpeditionState:
	var s := ExpeditionState.new()
	s.planet_id = DictUtil.get_str(d, "planet_id")
	s.site_id = DictUtil.get_str(d, "site_id")
	s.survey_id = DictUtil.get_str(d, "survey_id")
	s.status = DictUtil.get_str(d, "status", STATUS_ACTIVE)
	s.suit_energy = DictUtil.get_float(d, "suit_energy", 100.0)
	s.drone_refill_available = bool(d.get("drone_refill_available", false))
	s.drone_refill_used = bool(d.get("drone_refill_used", false))
	s.samples = DictUtil.get_arr(d, "samples").duplicate()
	s.extracted = DictUtil.get_arr(d, "extracted").duplicate()
	s.relay_placed = bool(d.get("relay_placed", false))
	s.risk_sample_taken = bool(d.get("risk_sample_taken", false))
	s.warned_reserve = bool(d.get("warned_reserve", false))
	s.elapsed_s = DictUtil.get_float(d, "elapsed_s")
	return s

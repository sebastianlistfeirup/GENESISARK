class_name SocietyState
extends RefCounted
## Trust, council and the three named young perspectives (bible p.12, GA-24).

var trust: float = 50.0            # 0..100
var council_formed: bool = false
var council_day: int = -1
var autonomy: float = 0.0           # 0..100: how much the society decides itself
var priorities: Dictionary = {"expansion": 0, "safety": 0, "self_determination": 0}
var decisions: Array = []           # [{id, choice, day}]
var voices: Dictionary = {}         # name -> {perspective, standing}


func to_dict() -> Dictionary:
	return {
		"trust": trust, "council_formed": council_formed, "council_day": council_day,
		"autonomy": autonomy, "priorities": priorities.duplicate(), "decisions": decisions.duplicate(true),
		"voices": voices.duplicate(true),
	}


static func from_dict(d: Dictionary) -> SocietyState:
	var s := SocietyState.new()
	s.trust = DictUtil.get_float(d, "trust", 50.0)
	s.council_formed = bool(d.get("council_formed", false))
	s.council_day = DictUtil.get_int(d, "council_day", -1)
	s.autonomy = DictUtil.get_float(d, "autonomy")
	var p: Dictionary = DictUtil.get_dict(d, "priorities")
	for k: String in s.priorities.keys():
		s.priorities[k] = DictUtil.get_int(p, k)
	s.decisions = DictUtil.get_arr(d, "decisions").duplicate(true)
	s.voices = DictUtil.get_dict(d, "voices").duplicate(true)
	return s

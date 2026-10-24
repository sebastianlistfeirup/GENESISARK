class_name EventState
extends RefCounted
## Crisis and citizen events. An event fires once; a resolution is applied once
## (event_id + option is the transaction key).

var active: Array = []        # [{id, day_started, warned}]
var resolved: Dictionary = {} # event_id -> {option, day}
var warnings: Array = []      # event ids that have shown their warning
var aftermath: Array = []     # [{event_id, option, due_day}] delayed consequences (R9 layer 3)


func is_active(event_id: String) -> bool:
	for a: Dictionary in active:
		if a.get("id") == event_id:
			return true
	return false


func has_unresolved_critical(events_db: Dictionary) -> bool:
	for a: Dictionary in active:
		var def: Dictionary = events_db.get(str(a.get("id")), {})
		if bool(def.get("critical", false)):
			return true
	return false


func to_dict() -> Dictionary:
	return {"active": active.duplicate(true), "resolved": resolved.duplicate(true), "warnings": warnings.duplicate(), "aftermath": aftermath.duplicate(true)}


static func from_dict(d: Dictionary) -> EventState:
	var s := EventState.new()
	s.active = DictUtil.get_arr(d, "active").duplicate(true)
	s.resolved = DictUtil.get_dict(d, "resolved").duplicate(true)
	s.warnings = DictUtil.get_arr(d, "warnings").duplicate()
	s.aftermath = DictUtil.get_arr(d, "aftermath").duplicate(true)
	for a: Dictionary in s.aftermath:
		a["due_day"] = int(a.get("due_day", 0))
	return s

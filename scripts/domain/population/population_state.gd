class_name PopulationState
extends RefCounted
## Cohorts are the authoritative population data (bible p.11). Visible citizens
## only illustrate them. Cohort dict: {id, size, age_days, health, care_need,
## education, role, stage, gestation_days, txn}
## stage: "incubating" | "child" | "adult"; role: "" | "worker" | "council" | ...

var cohorts: Array = []
var next_cohort_id: int = 1
var deaths: int = 0


func alive_count() -> int:
	var n := 0
	for c: Dictionary in cohorts:
		if c.get("stage") != "incubating":
			n += int(c.get("size", 0))
	return n


func count_stage(stage: String) -> int:
	var n := 0
	for c: Dictionary in cohorts:
		if c.get("stage") == stage:
			n += int(c.get("size", 0))
	return n


func adult_workforce() -> int:
	var n := 0
	for c: Dictionary in cohorts:
		if c.get("stage") == "adult":
			n += int(c.get("size", 0))
	return n


func cohort_by_id(cid: int) -> Dictionary:
	for c: Dictionary in cohorts:
		if int(c.get("id")) == cid:
			return c
	return {}


func to_dict() -> Dictionary:
	return {"cohorts": cohorts.duplicate(true), "next_cohort_id": next_cohort_id, "deaths": deaths}


static func from_dict(d: Dictionary) -> PopulationState:
	var s := PopulationState.new()
	s.cohorts = DictUtil.get_arr(d, "cohorts").duplicate(true)
	for c: Dictionary in s.cohorts:
		c["id"] = int(c.get("id", 0))
		c["size"] = int(c.get("size", 0))
		c["age_days"] = int(c.get("age_days", 0))
		c["gestation_days"] = int(c.get("gestation_days", 0))
	s.next_cohort_id = DictUtil.get_int(d, "next_cohort_id", 1)
	s.deaths = DictUtil.get_int(d, "deaths")
	return s

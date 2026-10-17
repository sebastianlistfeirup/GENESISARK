class_name PlanetKnowledge
extends RefCounted
## What the player actually knows about a planet. Each property records status
## (known/estimated/unknown), interval or candidates, confidence and source.
## Scouting only narrows knowledge; it never re-rolls truth (bible p.7).

var planet_id: String = ""
var level_reached: Dictionary = {}   # level -> true ("archive", "orbital", ...)
var observations: Dictionary = {}    # prop -> {status, min, max, value, candidates, confidence, source}
var probed_sites: Array = []         # site ids with a probe placed
var expedition_sites: Array = []     # site ids visited in person
var site_facts: Dictionary = {}      # site_id -> {fact: {status, value, source}}


static func create(planet_def: Dictionary) -> PlanetKnowledge:
	var k := PlanetKnowledge.new()
	k.planet_id = str(planet_def.get("id"))
	k.apply_level(planet_def, "archive", "Arkens arkiv")
	return k


## Applies one knowledge level from the definition. Returns the props that changed.
func apply_level(planet_def: Dictionary, level: String, source: String) -> Array:
	var changed: Array = []
	level_reached[level] = true
	var props: Dictionary = DictUtil.get_dict(planet_def, "properties")
	for prop: String in props.keys():
		var p: Dictionary = props[prop]
		var levels: Dictionary = DictUtil.get_dict(p, "levels")
		if not levels.has(level):
			if not observations.has(prop):
				observations[prop] = {"status": "unknown", "confidence": 0.0, "source": ""}
			continue
		var lv: Dictionary = levels[level]
		var status := str(lv.get("status"))
		var prev: Dictionary = observations.get(prop, {"status": "unknown"})
		if prev.get("status") == "known":
			continue  # Never regress
		var obs := {"status": status, "source": source}
		match status:
			"known":
				obs["value"] = p.get("truth")
				obs["confidence"] = 1.0
			"estimated":
				if str(p.get("type")) == "number":
					obs["min"] = lv.get("min")
					obs["max"] = lv.get("max")
					var width := float(lv.get("max")) - float(lv.get("min"))
					obs["confidence"] = clampf(1.0 - width / maxf(absf(float(lv.get("max"))), 1.0), 0.1, 0.9)
				else:
					obs["candidates"] = DictUtil.get_arr(lv, "candidates").duplicate()
					obs["confidence"] = 1.0 / maxf(1.0, float(DictUtil.get_arr(lv, "candidates").size()))
			_:
				obs["confidence"] = 0.0
		if prev.get("status") == "unknown" and status == "unknown":
			continue
		if JSON.stringify(prev) != JSON.stringify(obs):
			observations[prop] = obs
			changed.append(prop)
	return changed


func reveal_site_fact(site_id: String, fact: String, value: Variant, source: String) -> bool:
	var facts: Dictionary = site_facts.get(site_id, {})
	if facts.has(fact) and facts[fact].get("status") == "known":
		return false
	facts[fact] = {"status": "known", "value": value, "source": source}
	site_facts[site_id] = facts
	return true


func status_of(prop: String) -> String:
	return str(observations.get(prop, {}).get("status", "unknown"))


func to_dict() -> Dictionary:
	return {
		"planet_id": planet_id, "level_reached": level_reached.duplicate(),
		"observations": observations.duplicate(true), "probed_sites": probed_sites.duplicate(),
		"expedition_sites": expedition_sites.duplicate(), "site_facts": site_facts.duplicate(true),
	}


static func from_dict(d: Dictionary) -> PlanetKnowledge:
	var k := PlanetKnowledge.new()
	k.planet_id = DictUtil.get_str(d, "planet_id")
	k.level_reached = DictUtil.get_dict(d, "level_reached").duplicate()
	k.observations = DictUtil.get_dict(d, "observations").duplicate(true)
	k.probed_sites = DictUtil.get_arr(d, "probed_sites").duplicate()
	k.expedition_sites = DictUtil.get_arr(d, "expedition_sites").duplicate()
	k.site_facts = DictUtil.get_dict(d, "site_facts").duplicate(true)
	return k

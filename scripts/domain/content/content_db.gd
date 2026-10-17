class_name ContentDB
extends RefCounted
## Loads and validates every data definition (planets, sites, hazards, routes,
## buildings, surveys, events, endings, objectives, story). Validation errors
## carry the exact reason (bible GA-04: "Ugyldig planet afvises med præcis årsag").

const ROOT := "res://data"

var balance: Dictionary = {}
var planets: Dictionary = {}       # id -> Dictionary
var biome_maps: Dictionary = {}    # biome_id -> {map, sites}
var sites: Dictionary = {}         # site_id -> Dictionary (with biome_id)
var hazards: Dictionary = {}
var locations: Dictionary = {}
var routes: Array = []
var start_location: String = ""
var buildings: Dictionary = {}
var building_priorities: Array = []
var surveys: Dictionary = {}       # planet_id -> survey problem
var events: Dictionary = {}
var endings: Dictionary = {}
var objectives: Dictionary = {}
var story: Dictionary = {}         # scene_id -> scene
var journal_entries: Array = []    # [{id, trigger, text}]
var characters: Dictionary = {}    # id -> {name, perspective, bio}
var errors: PackedStringArray = []
var content_version: String = "0"

const NUMBER_PROPS := ["gravity_multiplier", "mean_temperature_c", "water_access", "mineral_yield",
	"solar_factor", "geothermal_factor", "biological_risk"]
const CATEGORY_PROPS := ["atmosphere_class"]
const LEVEL_ORDER := ["archive", "orbital", "probe", "expedition"]
const BIOMES := ["green", "desert", "ice"]


static func load_default() -> ContentDB:
	var db := ContentDB.new()
	db.load_all(ROOT)
	return db


func load_all(root: String) -> bool:
	errors.clear()
	balance = _load_dict(root + "/balance/baseline.json")
	content_version = str(balance.get("content_version", "0"))
	for file: String in _list_json(root + "/planets"):
		var p: Dictionary = _load_dict(root + "/planets/" + file)
		if p.is_empty():
			continue
		planets[str(p.get("id", file))] = p
	for biome: String in BIOMES:
		var m: Dictionary = _load_dict(root + "/sites/%s.json" % biome)
		if m.is_empty():
			errors.append("sites/%s.json mangler" % biome)
			continue
		biome_maps[biome] = m
		for s: Dictionary in DictUtil.get_arr(m, "sites"):
			var site: Dictionary = s.duplicate(true)
			site["biome_id"] = biome
			sites[str(site.get("id"))] = site
	for h: Dictionary in DictUtil.get_arr(_load_dict(root + "/hazards/hazards.json"), "hazards"):
		hazards[str(h.get("id"))] = h
	var r: Dictionary = _load_dict(root + "/routes/routes.json")
	locations = DictUtil.get_dict(r, "locations")
	routes = DictUtil.get_arr(r, "routes")
	start_location = DictUtil.get_str(r, "start_location", "drift")
	var b: Dictionary = _load_dict(root + "/buildings/buildings.json")
	building_priorities = DictUtil.get_arr(b, "priorities")
	for bd: Dictionary in DictUtil.get_arr(b, "buildings"):
		buildings[str(bd.get("id"))] = bd
	for file: String in _list_json(root + "/surveys"):
		var sv: Dictionary = _load_dict(root + "/surveys/" + file)
		if not sv.is_empty():
			surveys[str(sv.get("planet_id"))] = sv
	_load_keyed(root + "/events", "events", events)
	_load_keyed(root + "/endings", "endings", endings)
	_load_keyed(root + "/objectives", "objectives", objectives)
	_load_keyed(root + "/story", "scenes", story)
	var jv: Variant = DictUtil.load_json(root + "/story/journal.json")
	if jv is Dictionary:
		journal_entries = DictUtil.get_arr(jv, "entries")
	var sv2: Variant = DictUtil.load_json(root + "/story/scenes.json")
	if sv2 is Dictionary:
		for ch: Dictionary in DictUtil.get_arr(sv2, "characters"):
			characters[str(ch.get("id"))] = ch
	validate()
	return errors.is_empty()


func _load_keyed(dir: String, list_key: String, target: Dictionary) -> void:
	for file: String in _list_json(dir):
		var d: Dictionary = _load_dict(dir + "/" + file)
		for item: Dictionary in DictUtil.get_arr(d, list_key):
			var id := str(item.get("id", ""))
			if id.is_empty():
				errors.append("%s/%s: element uden id" % [dir.get_file(), file])
				continue
			if target.has(id):
				errors.append("%s: dubleret id '%s'" % [dir.get_file(), id])
			target[id] = item


func _load_dict(path: String) -> Dictionary:
	var v: Variant = DictUtil.load_json(path)
	if v == null:
		if not path.ends_with("/"):
			errors.append("Kunne ikke læse %s" % path)
		return {}
	if not v is Dictionary:
		errors.append("%s: forventede et objekt" % path)
		return {}
	return v


func _list_json(dir_path: String) -> PackedStringArray:
	var out: PackedStringArray = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	for f: String in dir.get_files():
		# Exported builds list remapped files; JSON stays as-is because it is not imported.
		if f.ends_with(".json"):
			out.append(f)
	out.sort()
	return out


# ---------------------------------------------------------------- validation

func validate() -> PackedStringArray:
	for id: String in planets.keys():
		for e: String in validate_planet(planets[id]):
			errors.append(e)
	_validate_routes()
	_validate_buildings()
	_validate_sites()
	if int(balance.get("embryos_total", 0)) != 50000:
		errors.append("balance: embryos_total skal være 50000")
	return errors


## Returns a list of precise reasons why a planet definition is invalid.
func validate_planet(p: Dictionary) -> PackedStringArray:
	var out: PackedStringArray = []
	var id := str(p.get("id", ""))
	if id.is_empty() or not id.is_valid_identifier():
		out.append("planet '%s': ugyldigt id" % id)
		return out
	var biome := str(p.get("biome_id", ""))
	if not biome in BIOMES:
		out.append("planet %s: ukendt biome_id '%s'" % [id, biome])
	var props: Dictionary = DictUtil.get_dict(p, "properties")
	for prop: String in NUMBER_PROPS + CATEGORY_PROPS:
		if not props.has(prop):
			out.append("planet %s: mangler egenskab %s" % [id, prop])
			continue
		for e: String in _check_property(id, prop, props[prop]):
			out.append(e)
	for h: Variant in DictUtil.get_arr(p, "hazard_ids"):
		if not hazards.is_empty() and not hazards.has(str(h)):
			out.append("planet %s: ukendt hazard '%s'" % [id, h])
	var st: Array = DictUtil.get_arr(p, "site_templates")
	if st.size() != 3:
		out.append("planet %s: skal have præcis 3 site_templates (har %d)" % [id, st.size()])
	for s: Variant in st:
		if not sites.is_empty() and not sites.has(str(s)):
			out.append("planet %s: ukendt site '%s'" % [id, s])
		elif sites.has(str(s)) and str(sites[str(s)].get("biome_id")) != biome:
			out.append("planet %s: site %s tilhører ikke biome %s" % [id, s, biome])
	var mods: Dictionary = DictUtil.get_dict(p, "colony_modifiers")
	for k: String in ["solar", "water", "food", "mine", "geothermal", "build_cost", "drone_efficiency"]:
		var v := DictUtil.get_float(mods, k, -1.0)
		if v < 0.0 or v > 3.0:
			out.append("planet %s: colony_modifiers.%s=%s uden for [0,3]" % [id, k, v])
	return out


func _check_property(pid: String, prop: String, d: Variant) -> PackedStringArray:
	var out: PackedStringArray = []
	if not d is Dictionary:
		out.append("planet %s.%s: forventede objekt" % [pid, prop])
		return out
	var levels: Dictionary = DictUtil.get_dict(d, "levels")
	if not levels.has("archive"):
		out.append("planet %s.%s: mangler archive-niveau" % [pid, prop])
	var is_num := str(d.get("type")) == "number"
	var truth: Variant = d.get("truth")
	if is_num and not (truth is float or truth is int):
		out.append("planet %s.%s: truth skal være et tal" % [pid, prop])
		return out
	if is_num and prop == "gravity_multiplier" and (float(truth) < 0.3 or float(truth) > 2.0):
		out.append("planet %s.gravity_multiplier: %s uden for [0.3, 2.0]" % [pid, truth])
	if is_num and prop in ["water_access", "biological_risk"] and (float(truth) < 0.0 or float(truth) > 1.0):
		out.append("planet %s.%s: %s uden for [0, 1]" % [pid, prop, truth])
	# Knowledge may only narrow: every level must contain the truth and sit inside the previous interval.
	var prev_min := -INF
	var prev_max := INF
	var prev_candidates: Array = []
	var seen_known := false
	for level: String in LEVEL_ORDER:
		if not levels.has(level):
			continue
		var lv: Dictionary = levels[level]
		var status := str(lv.get("status", ""))
		if not status in ["known", "estimated", "unknown"]:
			out.append("planet %s.%s.%s: ugyldig status '%s'" % [pid, prop, level, status])
			continue
		if seen_known and status != "known":
			out.append("planet %s.%s.%s: viden må ikke gå tilbage efter 'known'" % [pid, prop, level])
		if status == "known":
			seen_known = true
		elif status == "estimated":
			if is_num:
				var lo := DictUtil.get_float(lv, "min", NAN)
				var hi := DictUtil.get_float(lv, "max", NAN)
				if is_nan(lo) or is_nan(hi) or lo > hi:
					out.append("planet %s.%s.%s: ugyldigt interval" % [pid, prop, level])
				elif float(truth) < lo - 0.0001 or float(truth) > hi + 0.0001:
					out.append("planet %s.%s.%s: interval [%s, %s] indeholder ikke sandheden %s" % [pid, prop, level, lo, hi, truth])
				elif lo < prev_min - 0.0001 or hi > prev_max + 0.0001:
					out.append("planet %s.%s.%s: interval udvider tidligere viden" % [pid, prop, level])
				else:
					prev_min = lo
					prev_max = hi
			else:
				var cands: Array = DictUtil.get_arr(lv, "candidates")
				if not truth in cands:
					out.append("planet %s.%s.%s: kandidater indeholder ikke sandheden" % [pid, prop, level])
				if not prev_candidates.is_empty():
					for c: Variant in cands:
						if not c in prev_candidates:
							out.append("planet %s.%s.%s: kandidat '%s' var udelukket" % [pid, prop, level, c])
				prev_candidates = cands
	return out


func _validate_routes() -> void:
	if not locations.has(start_location):
		errors.append("routes: start_location '%s' findes ikke" % start_location)
	var seen := {}
	for r: Dictionary in routes:
		var a := str(r.get("a"))
		var b := str(r.get("b"))
		if not locations.has(a) or not locations.has(b):
			errors.append("routes: ukendt lokation i %s-%s" % [a, b])
		var key := [a, b]
		key.sort()
		if seen.has(str(key)):
			errors.append("routes: dubleret rute %s" % str(key))
		seen[str(key)] = true
		if int(r.get("fuel", -1)) <= 0:
			errors.append("routes: %s-%s skal have positiv fuel" % [a, b])
	for loc: String in locations.keys():
		var pid := str(locations[loc].get("planet_id", ""))
		if not pid.is_empty() and not planets.has(pid):
			errors.append("routes: lokation %s peger på ukendt planet %s" % [loc, pid])


func _validate_buildings() -> void:
	var buildable := 0
	for id: String in buildings.keys():
		var b: Dictionary = buildings[id]
		var fp: Array = DictUtil.get_arr(b, "footprint")
		if fp.size() != 2 or float(fp[0]) <= 0 or float(fp[1]) <= 0:
			errors.append("building %s: ugyldigt footprint" % id)
		if not str(b.get("priority", "")) in building_priorities:
			errors.append("building %s: ukendt prioritet" % id)
		if b.get("buildable", true):
			buildable += 1
			if DictUtil.get_int(b, "build_work") <= 0:
				errors.append("building %s: build_work skal være > 0" % id)
			for k: String in DictUtil.get_dict(b, "cost").keys():
				if not k in ["alloy", "components"]:
					errors.append("building %s: ukendt cost '%s'" % [id, k])
	if buildable != 12:
		errors.append("buildings: version 1 skal have præcis 12 byggeklasser (har %d)" % buildable)


func _validate_sites() -> void:
	for biome: String in biome_maps.keys():
		var n := DictUtil.get_arr(biome_maps[biome], "sites").size()
		if n != 3:
			errors.append("sites/%s: skal have 3 landingssites (har %d)" % [biome, n])
	for sid: String in sites.keys():
		var s: Dictionary = sites[sid]
		var d: Dictionary = DictUtil.get_dict(s, "districts")
		for k: String in ["landing", "resource", "living"]:
			if not d.has(k):
				errors.append("site %s: mangler distrikt %s" % [sid, k])


# ---------------------------------------------------------------- queries

func planet(id: String) -> Dictionary:
	return planets.get(id, {})


func planet_ids_sorted() -> Array:
	var ids: Array = planets.keys()
	ids.sort_custom(func(a: String, b: String) -> bool:
		return int(planets[a].get("order", 0)) < int(planets[b].get("order", 0)))
	return ids


func scenes_for_trigger(trigger: String) -> Array:
	var out: Array = []
	for id: String in story.keys():
		if str(story[id].get("trigger", "")) == trigger:
			out.append(story[id])
	return out


func journal_for_trigger(trigger: String) -> Array:
	var out: Array = []
	for e: Dictionary in journal_entries:
		if str(e.get("trigger", "")) == trigger:
			out.append(e)
	return out


func building(id: String) -> Dictionary:
	return buildings.get(id, {})


func buildable_ids() -> Array:
	var out: Array = []
	for id: String in buildings.keys():
		if buildings[id].get("buildable", true):
			out.append(id)
	return out


func route_between(a: String, b: String) -> Dictionary:
	for r: Dictionary in routes:
		if (r.get("a") == a and r.get("b") == b) or (r.get("a") == b and r.get("b") == a):
			return r
	return {}


func site(id: String) -> Dictionary:
	return sites.get(id, {})


func bal(path: String, fallback: Variant = null) -> Variant:
	var cur: Variant = balance
	for part: String in path.split("."):
		if cur is Dictionary and (cur as Dictionary).has(part):
			cur = cur[part]
		else:
			return fallback
	return cur

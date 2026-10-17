class_name TestCase
extends RefCounted
## Minimal assertion base for headless domain tests (no addons, no network).

var failures: Array = []
var _current: String = ""
var content: ContentDB


func set_current(n: String) -> void:
	_current = n


func check(cond: bool, msg: String) -> bool:
	if not cond:
		failures.append("%s: %s" % [_current, msg])
	return cond


func eq(a: Variant, b: Variant, msg: String = "") -> bool:
	var same: bool = (a == b)
	if (a is float or a is int) and (b is float or b is int):
		same = is_equal_approx(float(a), float(b))
	if not same:
		failures.append("%s: %s (fik %s, forventede %s)" % [_current, msg, str(a), str(b)])
	return same


func ok(r: CommandResult, msg: String = "") -> bool:
	if r == null or not r.ok:
		failures.append("%s: %s -> %s" % [_current, msg, str(r)])
		return false
	return true


func fails(r: CommandResult, code: String, msg: String = "") -> bool:
	if r == null or r.ok or (not code.is_empty() and r.code != code):
		failures.append("%s: forventede fejl '%s' %s -> %s" % [_current, code, msg, str(r)])
		return false
	return true


## Shared helpers --------------------------------------------------------------

func new_sim(seed_value: int = 1234) -> Simulation:
	return Simulation.new_campaign(content, seed_value)


## Plays the ark prologue: power restored and starmap open.
func ark_ready(sim: Simulation) -> void:
	sim.ark.restore_power(sim.state)
	sim.ark.mark_system(sim.state, "starmap_opened")


## Travel to a planet and land at its first site with no scouting (test shortcut).
func land_on(sim: Simulation, planet_id: String, site_index: int = 0) -> void:
	ark_ready(sim)
	sim.travel.request_travel(sim.state, planet_id, "t:" + planet_id, true)
	var site := str(content.planet(planet_id)["site_templates"][site_index])
	sim.landing.commit_landing(sim.state, site, "land:" + planet_id)


## Places a building at the first valid spot near a district center.
func place_near(sim: Simulation, def_id: String, district: String = "") -> int:
	var gs := sim.state
	var site := content.site(gs.colony.site_id)
	var d: String = district if not district.is_empty() else str(content.building(def_id).get("district", "any"))
	if d == "any":
		d = "landing"
	var center: Array = site["districts"][d]["center"]
	for ring: int in range(0, 12):
		for i: int in range(maxi(1, ring * 8)):
			var ang := TAU * float(i) / float(maxi(1, ring * 8))
			var x := snappedf(float(center[0]) + cos(ang) * ring * 3.0, 1.0)
			var z := snappedf(float(center[1]) + sin(ang) * ring * 3.0, 1.0)
			if sim.colony.check_placement(gs, def_id, x, z, 0)["ok"]:
				var r := sim.colony.place_building(gs, def_id, x, z, 0, "p:%s:%d:%d" % [def_id, gs.colony.next_building_id, gs.campaign.colony_day])
				if r.ok:
					return int(r.data["building_id"])
	return -1


func run_days(sim: Simulation, n: int) -> Dictionary:
	var rep := {}
	for i: int in n:
		rep = sim.days.tick_day(sim.state)
	return rep

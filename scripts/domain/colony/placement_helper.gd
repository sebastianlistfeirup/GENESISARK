class_name PlacementHelper
extends RefCounted
## Finds the first valid spot near a district centre and places a building
## through the normal command. Used by fixtures, tests and balance tooling.

static func place_near(sim: Simulation, def_id: String, district: String = "") -> int:
	var gs := sim.state
	var site := sim.content.site(gs.colony.site_id)
	var d: String = district if not district.is_empty() else str(sim.content.building(def_id).get("district", "any"))
	if d == "any":
		d = "landing"
	var center: Array = site["districts"][d]["center"]
	for ring: int in range(0, 14):
		var n := maxi(1, ring * 8)
		for i: int in range(n):
			var ang := TAU * float(i) / float(n)
			var x := snappedf(float(center[0]) + cos(ang) * ring * 3.0, 1.0)
			var z := snappedf(float(center[1]) + sin(ang) * ring * 3.0, 1.0)
			if sim.colony.check_placement(gs, def_id, x, z, 0)["ok"]:
				var r := sim.colony.place_building(gs, def_id, x, z, 0, "p:%s:%d:%d" % [def_id, gs.colony.next_building_id, gs.campaign.colony_day])
				if r.ok:
					return int(r.data["building_id"])
	return -1


static func run_days(sim: Simulation, n: int) -> Dictionary:
	var rep := {}
	for i: int in n:
		rep = sim.days.tick_day(sim.state)
	return rep

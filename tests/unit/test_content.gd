extends TestCase
## GA-04 / GA-15: validated data, precise rejection reasons.


func test_default_content_is_valid() -> void:
	check(content.errors.is_empty(), "indholdsfejl: %s" % str(content.errors))
	eq(content.planets.size(), 6, "seks kandidatverdener")
	eq(content.buildable_ids().size(), 12, "tolv byggeklasser")
	eq(content.sites.size(), 9, "tre sites pr. biome")
	eq(content.surveys.size(), 6, "seks scoutingproblemer")
	eq(content.endings.size(), 3, "tre afslutningsprofiler")
	check(content.events.size() >= 9, "mindst ni kriser/borgerbegivenheder")


func test_invalid_planet_rejected_with_reason() -> void:
	var p: Dictionary = content.planet("viridia").duplicate(true)
	p["properties"]["gravity_multiplier"]["truth"] = 3.5
	var errs := content.validate_planet(p)
	check(not errs.is_empty(), "skal afvises")
	check(" ".join(errs).contains("gravity_multiplier"), "årsag nævner egenskaben: %s" % str(errs))


func test_interval_must_contain_truth() -> void:
	var p: Dictionary = content.planet("ferrum").duplicate(true)
	p["properties"]["water_access"]["levels"]["orbital"] = {"status": "estimated", "min": 0.5, "max": 0.9}
	var errs := content.validate_planet(p)
	check(" ".join(errs).contains("does not contain the truth"), "fanger interval uden sandhed: %s" % str(errs))


func test_knowledge_cannot_widen() -> void:
	var p: Dictionary = content.planet("ferrum").duplicate(true)
	p["properties"]["water_access"]["levels"]["probe"] = {"status": "estimated", "min": 0.0, "max": 0.5}
	var errs := content.validate_planet(p)
	check(" ".join(errs).contains("widens"), "fanger udvidet interval: %s" % str(errs))


func test_no_planet_universally_best() -> void:
	var keys := ["solar", "water", "food", "mine", "geothermal"]
	for pid: String in content.planets.keys():
		var mine: Dictionary = content.planet(pid)["colony_modifiers"]
		var best_all := true
		for k: String in keys:
			for other: String in content.planets.keys():
				if other != pid and float(content.planet(other)["colony_modifiers"][k]) > float(mine[k]):
					best_all = false
		check(not best_all, "%s er bedst i alle felter" % pid)


func test_events_have_free_fallback() -> void:
	var sim := new_sim()
	var errs := sim.events.validate_events()
	check(errs.is_empty(), str(errs))

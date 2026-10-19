extends SceneTree
## Campaign bot (GA-30 groundwork): plays the WHOLE game headless on every
## world, through the same domain commands the player's UI sends: ark prologue,
## probe, travel, approach, orbital scan, expedition, landing, building, events,
## era leaps, year-20/40 decisions, council, hand-over and epilogue.
## After every step it checks the bible's invariants, and at every phase
## boundary it saves -> JSON -> loads and demands an identical checksum.
## Event choices follow a policy per run, so together the runs exercise as many
## of the choices as possible; the report lists what was never reached.
##
##   godot --headless --path . --script res://tools/campaign/campaign_bot.gd [-- --planet=sere --policy=rotate --quick]
## --quick: one policy per planet (middle). Writes evidence/campaign_bot.json; exit 1 on any failure.

## Event/decision policy per run: always the first, middle or last open choice.
## "neglect" plays badly on purpose (few buildings, no reaction, no council) to
## prove that the other endings are reachable through play, not only in tests.
const POLICIES := ["first", "middle", "last", "neglect"]
const BUILD := ["solar_array", "water_plant", "habitat", "greenhouse", "solar_array", "battery", "mine",
	"workshop", "care_center", "clinic", "school_hall"]

var content: ContentDB
var failures: Array = []
var _run_id := ""


func _init() -> void:
	content = ContentDB.load_default()
	var only_planet := ""
	var only_policy := ""
	var quick := false
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--planet="):
			only_planet = a.substr(9)
		elif a.begins_with("--policy="):
			only_policy = a.substr(9)
		elif a == "--quick":
			quick = true
	var t0 := Time.get_ticks_msec()
	var runs: Array = []
	var seen_events := {}
	var chosen := {}
	var endings := {}
	var idx := 0
	for pid: String in content.planet_ids_sorted():
		if not only_planet.is_empty() and pid != only_planet:
			continue
		for pol: String in POLICIES:
			if (not only_policy.is_empty() and pol != only_policy) or (quick and only_policy.is_empty() and pol != "middle"):
				continue
			idx += 1
			var t1 := Time.get_ticks_msec()
			var r := _play(pid, pol, 5000 + idx)
			r["ms"] = Time.get_ticks_msec() - t1
			runs.append(r)
			for e: String in r["events"].keys():
				seen_events[e] = true
				chosen["%s/%s" % [e, r["events"][e]]] = true
			endings[r["ending"]] = int(endings.get(r["ending"], 0)) + 1
			print("%-8s %-6s year %4.1f  pop %4d  ending %-12s events %d  saves %d  %5d ms  %s" % [pid, pol, r["year"], r["population"],
				r["ending"], r["events"].size(), r["roundtrips"], r["ms"], "OK" if r["failures"] == 0 else "FAIL x%d" % r["failures"]])
	# Determinism: the same seed and policy must give the same final checksum.
	if only_planet.is_empty() or runs.size() > 0:
		var p0: String = runs[0]["planet"] if not runs.is_empty() else "viridia"
		var again := _play(p0, str(runs[0]["policy"]) if not runs.is_empty() else "middle", 5001, "determinism")
		failures = failures.filter(func(f: Dictionary) -> bool: return f["run"] != "determinism")
		_run_id = "determinism"
		_expect(again["checksum"] == runs[0]["checksum"], "determinism", "same seed/policy -> same final checksum")
	# Coverage of event choices across all runs.
	var never: Array = []
	var total_options := 0
	for id: String in content.events.keys():
		for o: Dictionary in DictUtil.get_arr(content.events[id], "options"):
			total_options += 1
			if not chosen.has("%s/%s" % [id, o.get("id")]):
				never.append("%s/%s" % [id, o.get("id")])
	var report := {"engine_version": Engine.get_version_info().get("string"), "content_version": content.content_version,
		"timestamp": Time.get_datetime_string_from_system(true), "elapsed_ms": Time.get_ticks_msec() - t0,
		"runs": runs, "failures": failures, "endings": endings,
		"events_seen": seen_events.keys(), "events_total": content.events.size(),
		"options_chosen": chosen.size(), "options_total": total_options, "options_never_chosen": never}
	var f := FileAccess.open("res://evidence/campaign_bot.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(report, "  "))
	f.close()
	print("endings: %s" % JSON.stringify(endings))
	print("events seen %d/%d, choices taken %d/%d" % [seen_events.size(), content.events.size(), chosen.size(), total_options])
	for fl: Dictionary in failures:
		print("FAIL [%s] %s: %s" % [fl["run"], fl["step"], fl["detail"]])
	print("CAMPAIGN %d runs, %d failures, %d ms" % [runs.size(), failures.size(), Time.get_ticks_msec() - t0])
	quit(0 if failures.is_empty() else 1)


func _expect(cond: bool, step: String, detail: String) -> bool:
	if not cond:
		failures.append({"run": _run_id, "step": step, "detail": detail})
	return cond


## Invariants that must hold after every command (bible p.14).
func _check(sim: Simulation, step: String) -> void:
	var gs := sim.state
	var errs := gs.validation_errors(content)
	_expect(errs.is_empty(), step, "invariants: " + ", ".join(errs))
	_expect(gs.ark.embryo_sum() == 50000, step, "embryo sum %d" % gs.ark.embryo_sum())
	for k: String in ["fuel", "integrity", "oxygen"]:
		_expect(float(gs.ark.get(k)) >= 0.0, step, "ark.%s < 0" % k)
	if gs.colony:
		for k: String in gs.colony.inventory.keys():
			_expect(float(gs.colony.inventory[k]) >= 0.0, step, "inventory %s = %s" % [k, gs.colony.inventory[k]])


## Save -> JSON text -> load must reproduce the state exactly.
func _roundtrip(sim: Simulation, step: String) -> bool:
	var env := SaveCodec.encode(sim.state, content.content_version, "bot")
	var parsed: Variant = JSON.parse_string(JSON.stringify(env))
	var dec := SaveCodec.decode(parsed, content)
	if not _expect(bool(dec["ok"]), step, "load failed: " + str(dec["error"])):
		return false
	var loaded: GameState = dec["state"]
	return _expect(SaveCodec.checksum(loaded.to_dict()) == SaveCodec.checksum(sim.state.to_dict()), step, "save/load checksum differs")


func _ok(r: CommandResult, step: String) -> bool:
	return _expect(r.ok, step, "%s: %s" % [r.code, r.reason] if not r.ok else "")


func _play(pid: String, policy: String, seed_value: int, label: String = "") -> Dictionary:
	_run_id = label if not label.is_empty() else "%s/%s" % [pid, policy]
	var sim := Simulation.new_campaign(content, seed_value)
	var gs := sim.state
	var trips := 0
	_check(sim, "new")
	# Act I: the ark.
	_ok(sim.ark.restore_power(gs), "restore_power")
	sim.ark.mark_system(gs, "embryo_bank_checked")
	sim.ark.mark_system(gs, "starmap_opened")
	sim.update_objectives()
	_check(sim, "prologue")
	trips += int(_roundtrip(sim, "save:prologue"))
	var site := str(content.planet(pid)["site_templates"][0])
	var probe := sim.survey.launch_probe(gs, pid, site, "bot:probe")
	_check(sim, "probe")
	var q := sim.travel.quote(gs, pid)
	_expect(not sim.nav.route_brief(gs, q).is_empty(), "nav_brief", "NAV has nothing to say about the route")
	_ok(sim.travel.request_travel(gs, pid, "bot:travel", true), "travel")
	_expect(not sim.travel.request_travel(gs, pid, "bot:travel", true).ok, "travel_once", "same travel txn applied twice")
	_check(sim, "travel")
	trips += int(_roundtrip(sim, "save:approach_pending"))
	_ok(sim.travel.resolve_approach(gs, int(round(float(q.get("approach_hits_autopilot", 0.0)))), 0, 4.0, true), "approach")
	_expect(not sim.travel.resolve_approach(gs, 3, 1, 0.0, false).ok, "approach_once", "approach booked twice")
	_ok(sim.survey.orbital_scan(gs, pid), "orbital_scan")
	_check(sim, "orbit")
	# Expedition: main sample, relay, back.
	if _ok(sim.expedition.start(gs, site, true), "expedition_start"):
		sim.expedition.tick(gs, 90.0, 1.0)
		_ok(sim.expedition.take_sample(gs, "main_sample"), "sample")
		_ok(sim.expedition.place_relay(gs), "relay")
		sim.expedition.tick(gs, 60.0, 2.0)
		_check(sim, "expedition")
		trips += int(_roundtrip(sim, "save:expedition"))
		_ok(sim.expedition.finish(gs, "bot:exp"), "expedition_finish")
	sim.update_objectives()
	# Act II: landing and the robot colony.
	_ok(sim.landing.commit_landing(gs, site, "bot:land"), "landing")
	_expect(not sim.landing.commit_landing(gs, site, "bot:land2").ok, "landing_once", "landed twice")
	_check(sim, "landed")
	trips += int(_roundtrip(sim, "save:landed"))
	var neglect := policy == "neglect"
	var queue: Array = ["solar_array", "water_plant", "habitat", "greenhouse", "solar_array", "care_center"] if neglect else BUILD.duplicate()
	var req := sim.colony.requires_module(gs)
	var events := {}
	var stops := {}
	for day: int in 420:
		if not queue.is_empty() and PlacementHelper.place_near(sim, str(queue[0])) > 0:
			queue.pop_front()
		if not req.is_empty():
			for b: Dictionary in gs.colony.buildings:
				if b["def_id"] == "habitat" and b["state"] == ColonyState.B_ACTIVE and not req in b["modules"]:
					sim.colony.add_module(gs, int(b["id"]), req)
		if day % 10 == 5 and float(gs.colony.last_report.get("power", {}).get("surplus_kw", 0.0)) < 7.0:
			PlacementHelper.place_near(sim, "geothermal_generator" if DictUtil.get_float(sim.colony.modifiers(gs), "geothermal") >= 0.5 else "solar_array")
		if gs.population.cohorts.is_empty() and sim.population.incubation_blockers(gs, 10).is_empty():
			_ok(sim.population.start_incubation(gs, 10, "bot:first"), "incubation")
		sim.days.tick_day(gs)
		_events(sim, policy, events)
		if day % 30 == 0:
			_check(sim, "colony_day_%d" % day)
		if gs.ark.embryo_incubating > 0 and queue.is_empty():
			break
	sim.update_objectives()
	trips += int(_roundtrip(sim, "save:colony"))
	# Act III: generations. A neglectful player who keeps hitting shortages gives up and hands over early.
	var shortage_run := 0
	for i: int in 80:
		if gs.campaign.colony_year() >= 40.0 or (neglect and shortage_run >= 3):
			break
		_events(sim, policy, events)
		var target := 20 if gs.campaign.colony_year() < 20.0 else 40
		var r := sim.era.commit(gs, EraService.default_plan(target), "bot:leap:%d" % i)
		_check(sim, "leap_%d" % i)
		if not r.ok:
			stops[r.code] = int(stops.get(r.code, 0)) + 1
			sim.days.tick_day(gs)
			continue
		var why := str(r.data["stop_reason"])
		if why != EraService.STOP_TARGET:
			stops[why] = int(stops.get(why, 0)) + 1
		shortage_run = shortage_run + 1 if why == EraService.STOP_SHORTAGE else 0
		match "" if neglect else str(r.data["stop_reason"]):
			EraService.STOP_SHORTAGE:
				PlacementHelper.place_near(sim, "water_plant")
				PlacementHelper.place_near(sim, "greenhouse")
			EraService.STOP_POWER:
				PlacementHelper.place_near(sim, "geothermal_generator" if DictUtil.get_float(sim.colony.modifiers(gs), "geothermal") >= 0.5 else "solar_array")
				PlacementHelper.place_near(sim, "battery")
		for id: String in ["year_20", "year_40"]:
			if gs.campaign.colony_year() >= (20.0 if id == "year_20" else 40.0) and not gs.society.decisions.any(func(d: Dictionary) -> bool: return d.get("id") == id):
				var prios: Array = gs.society.priorities.keys()
				prios.sort()
				_ok(sim.society.choose_priority(gs, id, str(prios[_pick(prios.size(), policy)])), "decision_" + id)
		if not neglect and not gs.society.council_formed and sim.society.council_blockers(gs).is_empty():
			_ok(sim.society.form_council(gs, "bot:council"), "council")
		if i % 4 == 0:
			trips += int(_roundtrip(sim, "save:leap_%d" % i))
	_events(sim, policy, events)
	if neglect:
		_expect(gs.ark.embryo_born > 0, "neglect_progress", "a careless player never got the first children born")
	else:
		_expect(gs.campaign.colony_year() >= 40.0, "year_40", "stuck at year %.1f" % gs.campaign.colony_year())
	# Hand-over and epilogue.
	var m := sim.endings.metrics(gs)
	var h := sim.endings.handover(gs, "bot:handover")
	_ok(h, "handover")
	_expect(not sim.endings.handover(gs, "bot:handover2").ok, "handover_once", "handed over twice")
	var ending := str(gs.campaign.ending_id)
	_expect(content.endings.has(ending), "ending", "unknown ending '%s'" % ending)
	if neglect:
		_expect(ending != "independent", "neglect_ending", "careless play still earned the best ending")
	var ep := " ".join(sim.endings.epilogue(gs))
	_expect(ep.length() > 80 and not "{" in ep, "epilogue", "epilogue empty or has placeholders: " + ep.left(120))
	_check(sim, "ended")
	trips += int(_roundtrip(sim, "save:ended"))
	return {"planet": pid, "policy": policy, "seed": seed_value, "probe": probe.ok, "year": snappedf(gs.campaign.colony_year(), 0.1),
		"population": int(m.get("population", 0)), "ending": ending, "events": events, "roundtrips": trips, "stops": stops,
		"decisions": gs.society.decisions.map(func(d: Dictionary) -> String: return "%s:%s" % [d["id"], d["choice"]]),
		"council": gs.society.council_formed, "ledger": gs.ark.ledger(), "checksum": sim.checksum(),
		"failures": failures.filter(func(f: Dictionary) -> bool: return f["run"] == _run_id).size()}


func _pick(n: int, policy: String) -> int:
	match policy:
		"last":
			return n - 1
		"middle":
			return n / 2
	return 0


## Resolve every active event the way a player would: a choice that is allowed now.
func _events(sim: Simulation, policy: String, seen: Dictionary) -> void:
	var gs := sim.state
	for a: Dictionary in gs.events.active.duplicate():
		if a.get("phase") != "active":
			continue
		var id := str(a["id"])
		var def: Dictionary = content.events.get(id, {})
		var open: Array = DictUtil.get_arr(def, "options").filter(func(o: Dictionary) -> bool: return sim.events.option_blockers(gs, def, o).is_empty())
		var choice := str(def.get("fallback", "")) if open.is_empty() else str((open[_pick(open.size(), policy)] as Dictionary)["id"])
		if _ok(sim.events.resolve(gs, id, choice), "event_" + id):
			seen[id] = choice
		_check(sim, "event_" + id)

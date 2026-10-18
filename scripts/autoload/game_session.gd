extends Node
## Owns the active domain (bible p.21). UI and 3D adapters send commands here;
## they never mutate state directly. Typed signals instead of a global event bus.

signal state_changed(kind: String)
signal command_failed(result: CommandResult)
signal objectives_completed(ids: Array)
signal story_requested(scene: Dictionary)
signal colony_ticked(report: Dictionary)
signal event_started(event_def: Dictionary)
signal notice(text: String, kind: String)

var content: ContentDB
var sim: Simulation
var state: GameState:
	get:
		return sim.state if sim else null
var colony_speed: int = 0
var colony_clock_active := false
var _accum := 0.0
var _txn_counter := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	content = ContentDB.load_default()
	if not content.errors.is_empty():
		for e: String in content.errors:
			push_error("Indholdsfejl: " + e)


## Reloads content for the active language and rebinds the running campaign to
## it. The domain state holds only ids and numbers, so nothing else changes.
func reload_content() -> void:
	content = ContentDB.load_default()
	if has_game():
		var gs := sim.state
		sim = Simulation.new(content, gs)
		_wire()
		state_changed.emit("language")


func has_game() -> bool:
	return sim != null and sim.state != null


func new_campaign(seed_value: int = -1) -> void:
	if seed_value < 0:
		seed_value = int(Time.get_unix_time_from_system()) % 1000000
	sim = Simulation.new_campaign(content, seed_value)
	colony_speed = 0
	_wire()
	state_changed.emit("new")


## Restore order: model first, then actors (scene), then UI (bible p.22).
func adopt_state(gs: GameState) -> void:
	sim = Simulation.new(content, gs)
	colony_speed = 0
	_wire()
	state_changed.emit("loaded")


func _wire() -> void:
	sim.expedition.reserve_warning.connect(func() -> void:
		AudioService.alarm(false)
		trigger_story("expedition_suit_low")
		notice.emit(Loc.t("Dragtens energi er under reserve. Vend tilbage til landeren."), "warning"))
	sim.expedition.suit_depleted.connect(func() -> void:
		AudioService.alarm(true)
		notice.emit(Loc.t("Dragten er tom. ARK fører dig tilbage til landeren."), "critical"))


func txn(prefix: String) -> String:
	# UI transactions only need uniqueness; dialogs create one id up front and
	# reuse it, so a double click or repeated confirm can never apply twice.
	_txn_counter += 1
	return "%s:%d:%d:%d:%d" % [prefix, state.campaign.elapsed_days, state.campaign.colony_day, state.campaign.event_ids.size(), Time.get_ticks_usec() + _txn_counter]


## Wraps every command: report failures, refresh objectives, emit changes.
func _after(r: CommandResult, kind: String) -> CommandResult:
	if r.ok:
		var done := sim.update_objectives()
		if not done.is_empty():
			objectives_completed.emit(done)
			AudioService.ui("ui_confirm")
		state_changed.emit(kind)
	else:
		command_failed.emit(r)
	return r


# ---------------------------------------------------------------- story

func trigger_story(trigger: String) -> void:
	if not has_game():
		return
	var key := "story:" + trigger
	if state.is_applied(key):
		return
	state.mark_applied(key)
	for e: Dictionary in content.journal_for_trigger(trigger):
		state.log_journal(str(e.get("text", "")), "story")
	for sc: Dictionary in content.scenes_for_trigger(trigger):
		story_requested.emit(sc)


# ---------------------------------------------------------------- ark & voyage

func cmd_restore_power() -> CommandResult:
	var r := _after(sim.ark.restore_power(state), "ark")
	if r.ok:
		AudioService.play("sfx_power_on")
		trigger_story("power_restored")
	return r


func cmd_mark(key: String, story_trigger: String = "") -> CommandResult:
	var r := sim.ark.mark_system(state, key)
	if r.ok:
		_after(r, "ark")
	if not story_trigger.is_empty():
		trigger_story(story_trigger)
	return r


func cmd_repair(components: int) -> CommandResult:
	return _after(sim.ark.repair(state, components, txn("repair")), "ark")


func cmd_travel(dest: String, confirm_risky: bool, travel_txn: String = "") -> CommandResult:
	var t := travel_txn if not travel_txn.is_empty() else txn("travel")
	var r := _after(sim.travel.request_travel(state, dest, t, confirm_risky), "travel")
	if r.ok:
		autosave()
	return r


func cmd_probe(planet_id: String, site_id: String) -> CommandResult:
	var r := _after(sim.survey.launch_probe(state, planet_id, site_id, txn("probe")), "survey")
	if r.ok:
		AudioService.play("sfx_probe_launch")
		trigger_story("probe_result")
	return r


func cmd_orbital_scan(planet_id: String) -> CommandResult:
	var r := _after(sim.survey.orbital_scan(state, planet_id), "survey")
	if r.ok:
		AudioService.play("sfx_scan")
		trigger_story("orbital_scan")
	return r


func cmd_start_expedition(site_id: String, drone_reserve: bool) -> CommandResult:
	var r := _after(sim.expedition.start(state, site_id, drone_reserve), "expedition")
	if r.ok:
		autosave()
	return r


func cmd_take_sample(point_id: String) -> CommandResult:
	var r := _after(sim.expedition.take_sample(state, point_id), "expedition")
	if r.ok:
		AudioService.play("sfx_sample")
	return r


func cmd_place_relay() -> CommandResult:
	return _after(sim.expedition.place_relay(state), "expedition")


func cmd_drone_refill() -> CommandResult:
	return _after(sim.expedition.use_drone_refill(state), "expedition")


func cmd_finish_expedition() -> CommandResult:
	var r := _after(sim.expedition.finish(state, txn("expedition")), "expedition")
	if r.ok:
		trigger_story("expedition_complete")
		autosave()
	return r


func cmd_commit_landing(site_id: String, landing_txn: String = "") -> CommandResult:
	# Pre-landing checkpoint before the irreversible step (bible p.8).
	SaveService.save_state("pre_landing", state, content)
	var r := _after(sim.landing.commit_landing(state, site_id, landing_txn if not landing_txn.is_empty() else txn("landing")), "landing")
	if r.ok:
		trigger_story("landing_commit")
		autosave()
	return r


# ---------------------------------------------------------------- colony

func cmd_place_building(def_id: String, pos: Vector2, rot: int) -> CommandResult:
	var r := _after(sim.colony.place_building(state, def_id, pos.x, pos.y, rot, txn("build")), "colony")
	if r.ok:
		AudioService.play("sfx_build_place")
	return r


func cmd_demolish(building_id: int) -> CommandResult:
	return _after(sim.colony.demolish(state, building_id), "colony")


func cmd_add_module(building_id: int, module_id: String) -> CommandResult:
	return _after(sim.colony.add_module(state, building_id, module_id), "colony")


func cmd_start_incubation(count: int) -> CommandResult:
	var r := _after(sim.population.start_incubation(state, count, txn("incubation")), "population")
	if r.ok:
		trigger_story("incubation_start")
		autosave()
	return r


func cmd_resolve_event(event_id: String, option_id: String) -> CommandResult:
	var r := _after(sim.events.resolve(state, event_id, option_id), "event")
	if r.ok:
		if str(content.events.get(event_id, {}).get("kind")) == "crisis":
			trigger_story("crisis_survived")
		autosave()
	return r


func cmd_form_council() -> CommandResult:
	var r := _after(sim.society.form_council(state, txn("council")), "society")
	if r.ok:
		trigger_story("council_formed")
	return r


func cmd_choose_priority(decision_id: String, priority: String) -> CommandResult:
	return _after(sim.society.choose_priority(state, decision_id, priority), "society")


func era_forecast(target_year: int) -> Dictionary:
	return sim.era.forecast(state, EraService.default_plan(target_year))


func cmd_era_leap(target_year: int) -> CommandResult:
	SaveService.save_state("auto", state, content)
	var r := _after(sim.era.commit(state, EraService.default_plan(target_year), txn("era")), "era")
	if r.ok:
		trigger_story("captain_stasis")
		var y := state.campaign.colony_year()
		if y >= 20.0:
			trigger_story("year_20")
		if y >= 40.0:
			trigger_story("year_40")
		_check_new_events()
		autosave()
	return r


func cmd_handover() -> CommandResult:
	var r := _after(sim.endings.handover(state, txn("handover")), "ending")
	if r.ok:
		autosave()
	return r


func set_colony_speed(speed: int) -> void:
	colony_speed = speed
	if state and state.colony:
		state.colony.speed = speed
	state_changed.emit("speed")


## Advances exactly one colony day (also used by tests/debug tools).
func advance_colony_day() -> Dictionary:
	if not has_game() or state.colony == null or state.campaign.phase != CampaignState.PHASE_SETTLED:
		return {}
	var born_before := state.ark.embryo_born
	var rep := sim.days.tick_day(state)
	var done := sim.update_objectives()
	if not done.is_empty():
		objectives_completed.emit(done)
	if state.ark.embryo_born > 0 and born_before == 0:
		trigger_story("first_birth")
		AudioService.play("stinger_birth", "Music")
	if "obj_build_habitat" in done:
		trigger_story("first_light")
	if "obj_stable_supply" in done:
		trigger_story("stable_supply")
	for b: Dictionary in rep.get("bottlenecks", []):
		if b.get("reason") == "no_power":
			AudioService.alarm(false)
			break
	colony_ticked.emit(rep)
	_check_new_events()
	if posmod(state.campaign.colony_day, 30) == 0:
		autosave()
	return rep


func _check_new_events() -> void:
	for a: Dictionary in state.events.active:
		if a.get("phase") == "active" and not a.get("shown", false):
			a["shown"] = true
			var def: Dictionary = content.events.get(str(a.get("id")), {})
			set_colony_speed(0)  # Decisions are made in paused time
			AudioService.alarm(bool(def.get("critical", false)))
			event_started.emit(def)


func _process(delta: float) -> void:
	if not colony_clock_active or colony_speed <= 0 or not has_game() or state.colony == null:
		_accum = 0.0
		return
	_accum += delta * float(colony_speed)
	var spd := float(content.bal("time.colony_seconds_per_day_1x", 2.0))
	var guard := 0
	while _accum >= spd and guard < 4:
		_accum -= spd
		guard += 1
		advance_colony_day()


# ---------------------------------------------------------------- persistence

func autosave() -> void:
	if has_game():
		var r := SaveService.save_state("auto", state, content)
		if not r["ok"]:
			notice.emit(Loc.t("Autogem fejlede: ") + str(r["error"]), "critical")


func save_to(slot: String) -> Dictionary:
	return SaveService.save_state(slot, state, content)


func load_from(slot: String, prefer_backup: bool = false) -> Dictionary:
	var r := SaveService.load_state(slot, content, prefer_backup)
	if r["ok"]:
		adopt_state(r["state"])
	return r

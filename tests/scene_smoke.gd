extends Node
## Scene tests (test layer 2, bible p.26). Run as a scene so autoloads exist:
##   godot --headless --path . res://scenes/tests/scene_smoke.tscn
## Loads every gameplay scene from a fixture, drives the captain with real
## input actions (GA-02: 10 runs of one route without leaving the hull or
## losing the figure), checks interaction, travel, expedition, building and
## save/load through the live GameSession. Writes evidence/scene_smoke.json.

var results: Array = []
var failures: Array = []


func _ready() -> void:
	AppFlow.test_mode = true
	get_tree().create_timer(240.0).timeout.connect(func() -> void:
		print("SMOKE FAIL watchdog timeout; completed checks: %d" % results.size())
		for r: Dictionary in results:
			print("SMOKE %s %s %s" % ["PASS" if r["ok"] else "FAIL", r["name"], r.get("detail", "")])
		get_tree().quit(2))
	await _run()
	var report := {"engine_version": Engine.get_version_info().get("string"), "checks": results, "failures": failures,
		"status": "PASS" if failures.is_empty() else "FAIL", "timestamp": Time.get_datetime_string_from_system(true)}
	var f := FileAccess.open("res://evidence/scene_smoke.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(report, "  "))
	f.close()
	for r: Dictionary in results:
		print("SMOKE %s %s %s" % ["PASS" if r["ok"] else "FAIL", r["name"], r.get("detail", "")])
	print("SMOKE TOTAL %d checks, %d failures" % [results.size(), failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)


func check(name: String, ok: bool, detail: String = "") -> void:
	results.append({"name": name, "ok": ok, "detail": detail})
	if not ok:
		failures.append(name + " " + detail)


func frames(n: int) -> void:
	for i: int in n:
		await get_tree().physics_frame


func load_scene(path: String) -> Node:
	var ps: PackedScene = load(path)
	var inst := ps.instantiate()
	add_child(inst)
	await frames(10)
	return inst


func unload(n: Node) -> void:
	n.queue_free()
	await frames(3)


func _run() -> void:
	# Main menu
	var menu := await load_scene("res://scenes/menu/main_menu.tscn")
	check("menu_loads", is_instance_valid(menu))
	# Controller in menus: a pad button with nothing focused focuses the first button.
	var fo := get_viewport().gui_get_focus_owner()
	if fo:
		fo.release_focus()
	var jb := InputEventJoypadButton.new()
	jb.button_index = JOY_BUTTON_DPAD_DOWN
	jb.pressed = true
	Input.parse_input_event(jb)
	await frames(2)
	check("pad_focuses_menu", get_viewport().gui_get_focus_owner() is Button and SettingsService.using_pad, str(get_viewport().gui_get_focus_owner()))
	var jr := InputEventJoypadButton.new()
	jr.button_index = JOY_BUTTON_DPAD_DOWN
	Input.parse_input_event(jr)
	var mk := InputEventKey.new()
	mk.physical_keycode = KEY_SHIFT
	mk.pressed = true
	Input.parse_input_event(mk)
	mk.pressed = false
	Input.parse_input_event(mk)
	await frames(1)
	await unload(menu)

	# Settings survive a restart (GA-33): written to disk and read back by a fresh loader.
	var old_lang: Variant = SettingsService.get_value("language")
	var old_scale: Variant = SettingsService.get_value("ui_scale")
	SettingsService.values["ui_scale"] = 1.15
	SettingsService.values["language"] = "en"
	SettingsService.save_settings()
	var cfg := ConfigFile.new()
	var loaded := cfg.load(SettingsService.PATH) == OK
	check("settings_persist", loaded and is_equal_approx(float(cfg.get_value("settings", "ui_scale", 0.0)), 1.15) and cfg.get_value("settings", "language", "") == "en")
	SettingsService.values["ui_scale"] = old_scale
	SettingsService.values["language"] = old_lang
	SettingsService.save_settings()
	SettingsService.apply()

	# Controller: every pad binding is in the input map (keyboard remaps never remove it).
	var pad_missing: Array = []
	for action: String in SettingsService.PAD.keys():
		var has_pad := false
		if InputMap.has_action(action):
			for e: InputEvent in InputMap.action_get_events(action):
				has_pad = has_pad or e is InputEventJoypadButton or e is InputEventJoypadMotion
		if not has_pad:
			pad_missing.append(action)
	check("pad_bindings_complete", pad_missing.is_empty(), str(pad_missing))

	# Audio: every cue with a placeholder loads, loops follow the ledger rule, footsteps have takes.
	var bad_audio: Array = []
	for f: String in DirAccess.get_files_at("res://assets/audio/placeholder"):
		if f.ends_with(".wav"):
			var cue := f.get_basename()
			var st := AudioService.stream(cue)
			if st == null or (st is AudioStreamWAV and ((st as AudioStreamWAV).loop_mode != AudioStreamWAV.LOOP_DISABLED) != AudioService.loops(cue)):
				bad_audio.append(cue)
	check("audio_cues_load", bad_audio.is_empty() and AudioService.variants("sfx_footstep").size() >= 4 and AudioService.variants("sfx_footstep_soil").size() >= 4, str(bad_audio))
	AudioService.set_layer("amb_embryo_bank")
	check("audio_layer_set", AudioService.layer_slot() == "amb_embryo_bank")
	AudioService.set_layer("")

	# RigLab (GA-14 prep): every character slot audits clean and the lab scene runs all states.
	var rig_bad: Array = []
	for sid: String in RigLab.SLOTS:
		var au := RigLab.audit(sid)
		if not au["ok"]:
			rig_bad.append("%s: %s" % [sid, au["issues"]])
	check("riglab_audit_all_slots", rig_bad.is_empty(), str(rig_bad))
	var lab: RigLab = await load_scene("res://scenes/tests/RigLab.tscn")
	lab.moving = true
	var lab_moved := 0.0
	for st: String in RigLab.STATES:
		lab._set_state(st)
		var p0: Vector3 = lab._pivot.position
		await frames(5)
		if st == "run":
			lab_moved = p0.distance_to(lab._pivot.position)
	lab._cycle(1)
	await frames(3)
	check("riglab_runs", lab_moved > 0.05 and lab.slot_index == 1, "moved=%.2f" % lab_moved)
	await unload(lab)

	# FX library (art/fx/): every fx.* slot is a real particle scene, not the proxy, and runs.
	var fx_bad: Array = []
	var fx_root := Node3D.new()
	add_child(fx_root)
	for sid: String in FxLab.SLOTS:
		var fx := VisualSlot.make(sid)
		fx_root.add_child(fx)
		var asset := fx.get_node_or_null("Asset")
		var parts := asset.find_children("*", "GPUParticles3D", true, false) if asset else []
		var animated := asset is FxEffect
		for n: Node in (asset.find_children("*", "", true, false) if asset else []):
			animated = animated or n is FxScanRing or n is AnimationPlayer
		if not fx.using_asset or asset == null or (parts.is_empty() and not animated):
			fx_bad.append(sid)
			continue
		for gp: GPUParticles3D in parts:
			if gp.process_material == null or gp.draw_pass_1 == null or gp.amount > 300:
				fx_bad.append("%s/%s" % [sid, gp.name])
	await frames(90)  # long enough for every BURSTS effect to fire at least once
	for fx: Node in fx_root.get_children():
		var a := fx.get_node_or_null("Asset")
		if not is_instance_valid(a) or (a is FxEffect and (a as FxEffect).mode == FxEffect.Mode.BURSTS and (a as FxEffect)._timer > (a as FxEffect).burst_interval.y):
			fx_bad.append(str(fx.name) + " stalled")
	var rm_before: Variant = SettingsService.values.get("reduced_motion", false)
	SettingsService.values["reduced_motion"] = true
	var calm_fx := VisualSlot.make("fx.spores")
	fx_root.add_child(calm_fx)
	var calm_ok := (calm_fx.get_node("Asset") as FxEffect).calm and is_equal_approx((calm_fx.get_node("Asset/Motes") as GPUParticles3D).amount_ratio, 0.5 * Quality.value("fx_amount", 1.0))
	SettingsService.values["reduced_motion"] = rm_before
	check("fx_library_particles", fx_bad.is_empty() and calm_ok, "%s calm=%s" % [fx_bad, calm_ok])
	fx_root.queue_free()
	await frames(2)

	# Touch joystick: dead zone swallows jitter, small throws stay slow, curve is monotonic, full throw = 1.
	var sh_ok := TouchControls.shape(Vector2(0.1, 0.0)) == Vector2.ZERO and TouchControls.shape(Vector2(0.0, -1.0)).is_equal_approx(Vector2(0, -1))
	var prev := 0.0
	for i: int in range(17, 101):
		var m := TouchControls.shape(Vector2(i / 100.0, 0.0)).length()
		sh_ok = sh_ok and m >= prev
		prev = m
	sh_ok = sh_ok and TouchControls.shape(Vector2(0.4, 0.0)).length() < 0.3
	check("touch_stick_curve", sh_ok)

	# Synty variants: a slot with several wrappers picks one per placement, stable for the same spot.
	AssetSlots.slots()
	AssetSlots._built["surface.rock_small"] = ["res://tests/fixtures/variant_a.tscn", "res://tests/fixtures/variant_b.tscn"]
	AssetSlots._scenes.clear()
	var seen := {}
	var stable := true
	for i: int in 24:
		var at := Vector3(i * 3.7, 0, i * -2.3)
		var picks: Array = []
		for k: int in 2:
			var vs := VisualSlot.make("surface.rock_small")
			vs.position = at
			add_child(vs)
			var asset := vs.get_node_or_null("Asset")
			picks.append(str(asset.get_meta("variant")) if asset else "proxy")
			vs.free()
		stable = stable and picks[0] == picks[1]
		seen[picks[0]] = true
	AssetSlots.reload()
	check("synty_variants_spread_and_stable", stable and seen.has("a") and seen.has("b") and not seen.has("proxy"), str(seen.keys()))

	# Animation library (tools/synty retarget pipeline): states play as ga/<state>, missing states fall back to idle.
	var lib := AnimationLibrary.new()
	for st: String in ["idle", "walk"]:
		var an := Animation.new()
		an.length = 1.0
		lib.add_animation(st, an)
	var ca := CharacterAnimator.new()
	ca.player = AnimationPlayer.new()
	add_child(ca.player)
	ca.player.add_animation_library(CharacterAnimator.LIB_NAME, lib)
	ca.prefix = CharacterAnimator.LIB_NAME + "/"
	ca.cfg = {"idle": {}, "walk": {"speed_ref": 1.5}, "blend_s": 0.1}
	ca.update("walk", 3.0)
	var walk_ok := ca.current == "ga/walk" and is_equal_approx(ca.player.speed_scale, 1.8)
	ca.update("sample", 0.0)
	check("anim_library_states", walk_ok and ca.current == "ga/idle", "%s %.2f" % [ca.current, ca.player.speed_scale])
	ca.player.queue_free()

	# Language switch mid-campaign: content reloads translated, the domain state is untouched.
	DebugFixtures.prepare("fresh")
	var lang_before := SaveCodec.checksum(GameSession.state.to_dict())
	Loc.set_language("da")
	GameSession.reload_content()
	var da_name := str(GameSession.content.building("water_plant").get("name"))
	var lang_after := SaveCodec.checksum(GameSession.state.to_dict())
	Loc.set_language(Loc.SOURCE)
	GameSession.reload_content()
	check("language_switch_keeps_state", lang_before == lang_after and da_name == "Vandanlæg" and str(GameSession.content.building("water_plant").get("name")) == "Water plant", da_name)

	# Ship: dark start, captain route x10, power coupling, starmap
	DebugFixtures.prepare("fresh")
	var ship := await load_scene("res://scenes/ship/ship.tscn")
	var captain: Captain = ship.get("captain")
	check("ship_captain_spawned", captain != null and captain.is_on_floor() or captain.global_position.y > -0.5, str(captain.global_position))
	var wl: WaypointLayer = ship.get("waypoints")
	check("waypoint_points_to_objective", wl != null and wl.objective == ship.get("interactables")["power_coupling"] and wl.places.size() >= 6,
		"%s, %d places" % [wl.objective_label if wl else "-", wl.places.size() if wl else 0])
	var start := captain.global_position
	var bounds: ShipBuilder = ship.get("builder")
	var escaped := 0
	var lost := 0
	for run: int in 10:
		captain.teleport(start, 0.0)
		await frames(2)
		for leg: Array in [["move_forward", 50], ["move_left", 70], ["move_back", 30], ["move_right", 40], ["move_forward", 90]]:
			Input.action_press(leg[0])
			if run % 2 == 1:
				Input.action_press("sprint")
			await frames(int(leg[1]))
			Input.action_release(leg[0])
			Input.action_release("sprint")
			if bounds.zone_at(captain.global_position) == "#":
				escaped += 1
			if captain.global_position.y < -1.0 or not captain.visible:
				lost += 1
	check("ga02_route_10_runs_no_wall_pass", escaped == 0, "escapes=%d" % escaped)
	check("ga02_route_10_runs_figure_kept", lost == 0, "lost=%d" % lost)
	# Camera stays out of walls: put the captain against a wall facing away.
	# Cryo bay south hull is at z=30: stand 1 m from it, camera looking from behind.
	captain.teleport(Vector3(start.x, start.y, 29.0), 0.0)
	await frames(8)
	var arm: SpringArm3D = captain.camera_rig.arm
	check("ga02_camera_never_passes_hull", arm.get_hit_length() < arm.spring_length - 0.5 and captain.camera_rig.camera.global_position.z < 30.0,
		"hit=%.2f cam_z=%.2f" % [arm.get_hit_length(), captain.camera_rig.camera.global_position.z])
	# Controller right stick turns the camera.
	var yaw0: float = captain.camera_rig.yaw
	Input.action_press("look_right", 1.0)
	await frames(15)
	Input.action_release("look_right")
	check("pad_look_turns_camera", absf(captain.camera_rig.yaw - yaw0) > 0.2, "dyaw=%.2f" % (captain.camera_rig.yaw - yaw0))
	var coupling: Interactable = ship.get("interactables")["power_coupling"]
	captain.teleport(coupling.global_position + Vector3(1.6, 0.1, 0), PI * 0.5)
	await frames(8)
	check("prompt_targets_coupling", captain.current_target == coupling, str(captain.current_target))
	Input.action_press("interact")
	var ev := InputEventAction.new()
	ev.action = "interact"
	ev.pressed = true
	Input.parse_input_event(ev)
	await frames(4)
	Input.action_release("interact")
	check("ga03_power_restored_by_interaction", GameSession.state.ark.systems["power"] != "offline")
	await frames(2)
	var cur_obj := GameSession.sim.objectives.current(GameSession.state)
	var want_it: Variant = ship.get("interactables").get(str(DictUtil.get_dict(cur_obj, "targets").get("ship", "")))
	check("waypoint_follows_next_objective", wl.objective != ship.get("interactables")["power_coupling"] and wl.objective == want_it, "%s → %s" % [cur_obj.get("id"), wl.objective_label])
	coupling.use()
	await frames(2)
	check("ga03_objective_not_rewarded_twice", GameSession.state.campaign.completed_objectives.count("obj_restore_power") == 1)
	var sm: StarMapPanel = ship.get("starmap")
	ship.call("_open", sm)
	await frames(3)
	check("starmap_opens", sm.visible)
	sm.close()
	await unload(ship)

	# Travel via command, flight scene autopilot
	var r := GameSession.cmd_travel("viridia", false, "smoke:trip")
	check("ga05_travel_command", r.ok, r.reason)
	var r2 := GameSession.cmd_travel("viridia", false, "smoke:trip")
	check("ga05_double_click_rejected", not r2.ok and GameSession.state.ark.fuel == 88.0, "fuel=%s" % GameSession.state.ark.fuel)
	AppFlow.params = {"destination": "viridia"}
	check("approach_pending_after_travel", GameSession.state.campaign.pending_approach.get("destination") == "viridia")
	var flight := await load_scene("res://scenes/flight/flight.tscn")
	var rocks: Array = flight.get("_rocks")
	var hazard_rocks := rocks.filter(func(rk: Dictionary) -> bool: return not rk["scenery"])
	check("approach_hazard_spawned", str(flight.get("_hazard")["type"]) == "field" and hazard_rocks.size() > 20, "%d sten" % hazard_rocks.size())
	flight.set("autopilot", true)
	flight.set("autopilot_used", true)
	var fship: Node3D = flight.get("ship")
	await frames(90)
	check("flight_autopilot_progresses", fship.position.z < -20.0, "z=%.1f" % fship.position.z)
	flight.set("autopilot", false)
	var target_rock: Node3D = hazard_rocks[0]["node"]
	fship.position = target_rock.position
	await frames(3)
	check("approach_collision_registered", int(flight.get("hits")) >= 1 and (flight.get("hud") as GameHud).nav.busy(), "hits=%d" % flight.get("hits"))
	var integ_before := GameSession.state.ark.integrity
	var fuel_before := GameSession.state.ark.fuel
	fship.position = Vector3(0, 0, -1099.5)
	for rk: Dictionary in rocks:
		(rk["node"] as Node3D).position.x += 500.0  # clear the last metres
	await frames(20)
	check("approach_booked_once", GameSession.state.campaign.pending_approach.is_empty() and GameSession.state.ark.integrity < integ_before
		and GameSession.state.ark.fuel < fuel_before and not GameSession.cmd_resolve_approach(1, 0, 0.0, false).ok,
		"skrog %.1f -> %.1f, brændstof %.1f -> %.1f" % [integ_before, GameSession.state.ark.integrity, fuel_before, GameSession.state.ark.fuel])
	await unload(flight)

	# Expedition scene
	var rs := GameSession.cmd_start_expedition("green_a", true)
	check("ga06_expedition_start", rs.ok, rs.reason)
	var surf := await load_scene("res://scenes/surface/surface.tscn")
	var cap2: Captain = surf.get("captain")
	await frames(30)
	check("surface_captain_on_terrain", cap2.global_position.y > -5.0 and cap2.global_position.y < 40.0, str(cap2.global_position))
	var e0 := GameSession.state.expedition.suit_energy
	await frames(60)
	check("ga06_suit_drains_in_scene", GameSession.state.expedition.suit_energy < e0)
	var markers: Dictionary = surf.get("_markers")
	var swl: WaypointLayer = surf.get("waypoints")
	check("waypoint_surface_main_sample", swl.objective == markers["main_sample"], swl.objective_label)
	var sample: Interactable = markers["main_sample"]
	sample.use()
	await frames(2)
	check("ga06_sample_recorded", "main_sample" in GameSession.state.expedition.samples)
	check("waypoint_surface_then_relay", swl.objective == markers.get("relay", markers["lander"]), swl.objective_label)
	(markers["lander"] as Interactable).use()
	await frames(150)
	check("ga06_expedition_finished", GameSession.state.knowledge_of("viridia").expedition_sites.has("green_a"))
	if is_instance_valid(surf):
		await unload(surf)
	await frames(60)
	for c: Node in get_tree().root.get_children():
		if c != self and not c.name in ["SettingsService", "AudioService", "SaveService", "GameSession", "AppFlow"]:
			c.queue_free()
	await frames(5)

	# Landing + colony
	var rl := GameSession.cmd_commit_landing("green_a", "smoke:land")
	check("ga07_landing", rl.ok, rl.reason)
	var rl2 := GameSession.cmd_commit_landing("green_b", "smoke:land2")
	check("ga07_landing_once", not rl2.ok)
	var col := await load_scene("res://scenes/colony/colony.tscn")
	var site := GameSession.content.site("green_a")
	var placed := 0
	var tc := TestCase.new()
	tc.content = GameSession.content
	for d: String in ["solar_array", "water_plant", "habitat"]:
		if tc.place_near(GameSession.sim, d) > 0:
			placed += 1
	check("ga08_three_buildings_placed", placed == 3, "placed=%d" % placed)
	for i: int in 16:
		GameSession.advance_colony_day()
	await frames(5)
	# GA-02: switching camera modes gives no double input and no teleport.
	var cap3: Captain = col.get("captain")
	var p0 := cap3.global_position
	col.call("_toggle_mode")
	await frames(5)
	var on_captain: bool = col.get("mode") == "captain" and cap3.input_enabled and not (col.get("cam_rig") as ColonyCamera).active
	col.call("_toggle_mode")
	await frames(5)
	var back: bool = col.get("mode") == "overhead" and not cap3.input_enabled and (col.get("cam_rig") as ColonyCamera).active
	check("ga02_camera_mode_switch_clean", on_captain and back and cap3.global_position.distance_to(p0) < 0.5, "moved=%.2f" % cap3.global_position.distance_to(p0))
	var views: Dictionary = col.get("views")
	check("ga08_building_views_synced", views.size() == GameSession.state.colony.buildings.size(), "%d vs %d" % [views.size(), GameSession.state.colony.buildings.size()])
	check("ga08_habitat_active", GameSession.state.colony.count_active("habitat") == 1)
	# Walkable collision follows the model (ShapeCollider), not the whole footprint.
	var shape_ok := true
	var shape_detail := ""
	var multi_box := false
	var solid := true
	for bid: Variant in views.keys():
		var bv: BuildingView = views[bid]
		var boxes: Array[AABB] = bv.collision_boxes()
		if boxes.is_empty():
			shape_ok = false
			shape_detail += "%s: none; " % bv.def_id
			continue
		var fp := ColonySimulation.footprint_size(GameSession.content.building(bv.def_id), 0)
		for bb: AABB in boxes:
			if absf(bb.position.x) > fp.x * 0.5 + 1.5 or absf(bb.end.x) > fp.x * 0.5 + 1.5 or absf(bb.position.z) > fp.y * 0.5 + 1.5 or absf(bb.end.z) > fp.y * 0.5 + 1.5:
				shape_ok = false
				shape_detail += "%s: box outside footprint; " % bv.def_id
		if bv.def_id == "water_plant" and boxes.size() > 1:
			multi_box = true
		var probe := PhysicsPointQueryParameters3D.new()
		probe.position = bv.to_global(boxes[0].get_center())
		probe.collision_mask = 1
		if col.get_world_3d().direct_space_state.intersect_point(probe).is_empty():
			solid = false
	check("building_collision_follows_shape", shape_ok and multi_box and solid,
		"%s multi_box=%s solid=%s" % [shape_detail, multi_box, solid])
	# Save -> load roundtrip through the live session
	var before := GameSession.sim.checksum()
	var sv := GameSession.save_to("manual_3")
	check("ga10_save", sv["ok"], str(sv.get("error", "")))
	var ld := GameSession.load_from("manual_3")
	check("ga10_load_identical", ld["ok"] and GameSession.sim.checksum() == before)
	await unload(col)

	# Ending screen from a grown colony
	DebugFixtures.prepare("grown:pelagos")
	var rh := GameSession.cmd_handover()
	check("ga25_handover", rh.ok, rh.reason)
	var end := await load_scene("res://scenes/story/ending.tscn")
	check("ending_loads", is_instance_valid(end))
	await unload(end)

	await _check_a11y_fit()


## GA-29: at UI scale 1.5 the logical screen is 1280x720 (the bible's smallest
## tested size, at the largest scale). The colony HUD and its overlays must fit
## inside it, the top bar must not cover the objective panel, and an alarm must
## show a visual signal. Scale is set in memory only, never saved.
func _check_a11y_fit() -> void:
	var root := get_tree().root
	var old_scale := root.content_scale_factor
	var old_size := root.content_scale_size
	var old_aspect := root.content_scale_aspect
	# KEEP pins the logical screen to 1920x1080 / 1.5 = 1280x720 whatever the headless window is.
	root.content_scale_size = Vector2i(1920, 1080)
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	root.content_scale_factor = 1.5
	DebugFixtures.prepare("grown:pelagos")
	var col: Node = await load_scene("res://scenes/colony/colony.tscn")
	await frames(10)
	var vis := get_viewport().get_visible_rect()
	var hud: GameHud = col.get("hud")
	var outside: Array = []
	for c: Control in _visible_controls(hud.root):
		var r := c.get_global_rect()
		if r.size.x > 1.0 and r.size.y > 1.0 and not vis.grow(1.0).encloses(r):
			outside.append("%s %s" % [c.get_class() if c.name.begins_with("@") else str(c.name), r])
	check("a11y_hud_fits_1280x720_scale_1_5", outside.is_empty() and vis.size.is_equal_approx(Vector2(1280, 720)), "vis=%s %s" % [vis.size, outside.slice(0, 5)])
	# The build bar wraps to at most two rows instead of running off the screen.
	check("a11y_build_bar_wraps", hud.bottom.size.y <= 130.0, "bottom=%s" % hud.bottom.get_global_rect())
	var top: Control = col.get("_top")
	check("a11y_top_bar_clear_of_objectives", not top.get_global_rect().intersects(hud.objective_rect()), "%s vs %s" % [top.get_global_rect(), hud.objective_rect()])
	var overlays: Array = [col.get("overview"), col.get("event_dialog"), col.get("decision")]
	(overlays[0] as ColonyOverview).open()
	for id: String in GameSession.content.events.keys():
		(overlays[1] as EventDialog).show_event(GameSession.content.events[id])
		break
	(overlays[2] as DecisionDialog).ask("year_20")
	await frames(4)
	var clipped: Array = []
	for o: OverlayPanel in overlays:
		var r := Rect2(o.transform * o.panel.position, o.panel.size * o.scale)
		if not vis.grow(1.0).encloses(r):
			clipped.append("%s %s" % [o.get_class(), r])
		o.close()
	check("a11y_overlays_fit_1280x720_scale_1_5", clipped.is_empty(), str(clipped))
	AudioService.alarm_raised.emit(true)
	await frames(2)
	check("a11y_alarm_has_visual_signal", hud.alarm_visible())
	await unload(col)
	root.content_scale_factor = old_scale
	root.content_scale_size = old_size
	root.content_scale_aspect = old_aspect


func _visible_controls(n: Node) -> Array:
	var out: Array = []
	for c: Node in n.get_children():
		if c is Control and (c as Control).is_visible_in_tree():
			out.append(c)
			out.append_array(_visible_controls(c))
	return out

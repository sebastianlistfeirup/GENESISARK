extends Node3D
## The colony (bible p.9-10): three districts on hand-built terrain, the ark as
## base, ghost placement with footprint/network/cost validation, priority-based
## power, visible bottlenecks, real-time days (pause/1x/3x), incubation, era
## leaps, events and hand-over. B toggles captain <-> overhead.

## F6 in the editor without a running campaign builds this fixture
## (e.g. "colony:nivalis", "grown:umbra", "expedition:ferrum").
@export var preview_setup := "colony:viridia"

var terrain: TerrainBuilder
var cam_rig: ColonyCamera
var captain: Captain
var hud: GameHud
var overview: ColonyOverview
var event_dialog: EventDialog
var decision: DecisionDialog
var views: Dictionary = {}  # building id -> BuildingView
var mode := "overhead"      # "overhead" | "captain"
var build_def := ""
var build_rot := 0
var ghost: Node3D
var ghost_ok := false
var ghost_pos := Vector2.ZERO
var selected_id := -1
var _net: MeshInstance3D
var _res_box: HBoxContainer
var _speed_label: Label
var _info_holder: VBoxContainer
var _build_bar: HBoxContainer
var _ghost_tip: Label
var _people: Node3D
var _people_nodes: Array[Node3D] = []
var _t := 0.0
var planet: Dictionary = {}
var site: Dictionary = {}


func _ready() -> void:
	if not GameSession.has_game():
		DebugFixtures.prepare(preview_setup)
	var gs: GameState = GameSession.state
	if gs.colony == null:
		AppFlow.goto("ship")
		return
	planet = GameSession.content.planet(gs.colony.planet_id)
	site = GameSession.content.site(gs.colony.site_id)
	for n: Node in TerrainBuilder.environment_for(planet, gs.colony.biome_id):
		add_child(n)
	terrain = TerrainBuilder.new()
	terrain.setup(gs.colony.biome_id, site, DictUtil.get_dict(planet, "palette"), 220.0)
	var districts: Dictionary = DictUtil.get_dict(site, "districts")
	var avoid: Array = []
	for dk: String in districts.keys():
		var c: Array = DictUtil.get_arr(districts[dk], "center")
		var r := DictUtil.get_float(districts[dk], "radius") * 2.0
		terrain.add_flat(Vector2(float(c[0]), float(c[1])), r)
		avoid.append([Vector2(float(c[0]), float(c[1])), r + 6.0])
	add_child(terrain)
	terrain.build()
	terrain.scatter(hash(gs.colony.site_id) + 1, 60, avoid)
	_draw_districts()
	SceneDressing.attach(self, str(site.get("id", "")), terrain)
	_net = MeshInstance3D.new()
	add_child(_net)
	_people = Node3D.new()
	add_child(_people)
	cam_rig = ColonyCamera.new()
	add_child(cam_rig)
	var lc: Array = DictUtil.get_arr(districts.get("landing", {}), "center")
	cam_rig.position = Vector3(float(lc[0]), 0, float(lc[1]) + 8)
	cam_rig.make_current()
	captain = Captain.new()
	captain.footstep_slot = "sfx_footstep_soil"
	add_child(captain)
	captain.teleport(Vector3(float(lc[0]) + 10, terrain.height_at(float(lc[0]) + 10, float(lc[1]) + 9) + 0.5, float(lc[1]) + 9))
	captain.set_active(false)
	captain.visible = false
	cam_rig.make_current()
	hud = GameHud.new()
	add_child(hud)
	_build_ui()
	overview = ColonyOverview.new()
	overview.leap_committed.connect(_after_leap)
	overview.handover_committed.connect(func() -> void: AppFlow.goto("ending"))
	add_child(overview)
	event_dialog = EventDialog.new()
	add_child(event_dialog)
	decision = DecisionDialog.new()
	add_child(decision)
	GameSession.colony_ticked.connect(func(_r: Dictionary) -> void: _sync())
	GameSession.state_changed.connect(func(_k: String) -> void: _sync())
	GameSession.event_started.connect(event_dialog.show_event)
	GameSession.colony_clock_active = true
	AudioService.set_ambience_any(["amb_colony_" + gs.colony.biome_id, "amb_colony_wind"])
	if gs.population.alive_count() > 0:
		AudioService.set_music_any(["music_colony_act3" if gs.campaign.colony_year() >= 20.0 else "music_colony_act2", "music_hope"])
	else:
		AudioService.set_music("")
	if gs.colony.last_report.is_empty():
		GameSession.sim.colony.recompute_network(gs)
		GameSession.sim.colony.allocate_power(gs, GameSession.sim.colony.hazard_factors(gs, gs.campaign.colony_day))
	_sync()
	if AppFlow.params.get("landing", false):
		hud.toast(Loc.t("Arken er landet. Byg strøm, vand og et habitat. Tryk på en bygning nederst."), "info", 10.0)
	_check_pending_event()


func _draw_districts() -> void:
	var labels := {"landing": Loc.t("Landingszone"), "resource": Loc.t("Ressourceområde"), "living": Loc.t("Boligzone")}
	var cols := {"landing": "#1f8a8a", "resource": "#c08850", "living": "#7cc46a"}
	var scale := GameSession.sim.colony.district_scale(GameSession.state)
	for dk: String in DictUtil.get_dict(site, "districts").keys():
		var d: Dictionary = site["districts"][dk]
		var c: Array = DictUtil.get_arr(d, "center")
		var r := DictUtil.get_float(d, "radius") * scale
		var ring := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = r - 0.35
		tm.outer_radius = r
		tm.rings = 64
		ring.mesh = tm
		ring.scale = Vector3(1, 0.05, 1)
		ring.material_override = AssetSlots.material(cols[dk], 0.8, 0.8)
		ring.position = Vector3(float(c[0]), terrain.height_at(float(c[0]), float(c[1])) + 0.15, float(c[1]))
		add_child(ring)
		var lbl := Label3D.new()
		lbl.text = labels[dk]
		lbl.font_size = 96
		lbl.pixel_size = 0.02
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lbl.modulate = Color(cols[dk])
		lbl.position = ring.position + Vector3(0, 1.0, -r)
		add_child(lbl)
	for bz: Dictionary in DictUtil.get_arr(site, "blocked"):
		var bc: Array = DictUtil.get_arr(bz, "center")
		var m := VisualSlot.make("surface.rock_large", "#5f5d58")
		m.position = Vector3(float(bc[0]), terrain.height_at(float(bc[0]), float(bc[1])) - 0.5, float(bc[1]))
		m.scale = Vector3(1.0, 0.6, 1.0) * DictUtil.get_float(bz, "radius") / 2.5
		add_child(m)


func _build_ui() -> void:
	var top := UiKit.vbox(6)
	top.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	top.grow_horizontal = Control.GROW_DIRECTION_BOTH
	top.position.y = 16
	hud.root.add_child(top)
	_res_box = UiKit.hbox(6)
	top.add_child(_res_box)
	var sp := UiKit.hbox(6)
	sp.alignment = BoxContainer.ALIGNMENT_CENTER
	var sl := UiKit.panel()
	_speed_label = UiKit.label("", 17)
	sl.add_child(_speed_label)
	sp.add_child(sl)
	for s: Array in [[0, "❚❚"], [1, "▶ 1x"], [3, "▶▶ 3x"]]:
		sp.add_child(UiKit.button(s[1], func() -> void: GameSession.set_colony_speed(int(s[0])), Loc.t("Pause / 1x / 3x (Mellemrum, 1, 3)")))
	sp.add_child(UiKit.button(Loc.t("Koloni-overblik"), func() -> void: _open_overview(), Loc.t("Forsyning, befolkning, generationsspring og råd")))
	sp.add_child(UiKit.button(Loc.t("Kaptajn [B]"), _toggle_mode, Loc.t("Gå rundt i kolonien som kaptajnen")))
	top.add_child(sp)
	_info_holder = UiKit.vbox(6)
	hud.top_right.add_child(_info_holder)
	_build_bar = UiKit.hbox(6)
	hud.bottom.add_child(_build_bar)
	for def_id: String in ["solar_array", "geothermal_generator", "battery", "water_plant", "greenhouse", "habitat", "mine", "workshop", "drone_hub", "care_center", "clinic", "school_hall"]:
		var def := GameSession.content.building(def_id)
		var b := UiKit.button(str(def.get("name")).replace(Loc.t(" og inkubationscenter"), ""), func() -> void: _start_build(def_id))
		b.tooltip_text = ColonyUi.building_tooltip(GameSession.sim, def_id)
		b.custom_minimum_size = Vector2(0, 46)
		b.add_theme_font_size_override("font_size", 14)
		b.set_meta("def_id", def_id)
		_build_bar.add_child(b)
	_ghost_tip = UiKit.label("", 15, UiKit.TEXT, true)
	_ghost_tip.custom_minimum_size = Vector2(720, 0)
	var gp := UiKit.panel()
	gp.add_child(_ghost_tip)
	gp.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	gp.position.y -= 150
	gp.grow_horizontal = Control.GROW_DIRECTION_BOTH
	gp.grow_vertical = Control.GROW_DIRECTION_BEGIN
	gp.visible = false
	gp.name = "GhostTip"
	hud.root.add_child(gp)


func _sync() -> void:
	var gs: GameState = GameSession.state
	if gs == null or gs.colony == null:
		return
	UiKit.clear(_res_box)
	_res_box.add_child(ColonyUi.resource_bar(gs))
	AudioService.set_layer("amb_colony_people" if gs.population.alive_count() > 0 else "", -10.0)
	_speed_label.text = Loc.t("År %d · dag %d   %s") % [int(gs.campaign.colony_year()), gs.campaign.colony_day % 365, [Loc.t("Pause"), "1x", "", "3x"][clampi(GameSession.colony_speed, 0, 3)]]
	var seen := {}
	for b: Dictionary in gs.colony.buildings:
		var bid := int(b["id"])
		seen[bid] = true
		if not views.has(bid):
			var v := BuildingView.new()
			add_child(v)
			v.setup(b, terrain.height_at(float(b["x"]), float(b["z"])))
			views[bid] = v
		else:
			(views[bid] as BuildingView).refresh(b)
	for bid: int in views.keys():
		if not seen.has(bid):
			(views[bid] as Node).queue_free()
			views.erase(bid)
	for b: Button in _build_bar.get_children():
		var def_id := str(b.get_meta("def_id"))
		var cost := GameSession.sim.colony.build_cost(gs, def_id)
		var afford := true
		for k: String in cost.keys():
			if float(gs.colony.inventory.get(k, 0.0)) < float(cost[k]):
				afford = false
		b.modulate = Color.WHITE if afford else Color(1, 1, 1, 0.55)
		b.text = Loc.t("%s\n%d mat.%s") % [str(GameSession.content.building(def_id).get("name")).replace(Loc.t(" og inkubationscenter"), "").replace(Loc.t("Geotermisk generator"), Loc.t("Geotermi")), int(cost.get("alloy", 0)), (Loc.t(" · %d komp.") % int(cost["components"])) if cost.has("components") else ""]
	_draw_network()
	_refresh_info()
	_sync_people()


func _draw_network() -> void:
	var gs: GameState = GameSession.state
	var im := ImmediateMesh.new()
	var bs: Array = gs.colony.buildings
	var any := false
	for i: int in bs.size():
		var a: Dictionary = bs[i]
		if not a.get("accessible") or a.get("state") != ColonyState.B_ACTIVE:
			continue
		for j: int in range(i + 1, bs.size()):
			var b: Dictionary = bs[j]
			if not b.get("accessible"):
				continue
			var r := maxf(GameSession.sim.colony.link_range(str(a["def_id"])), GameSession.sim.colony.link_range(str(b["def_id"])))
			var pa := Vector2(float(a["x"]), float(a["z"]))
			var pb := Vector2(float(b["x"]), float(b["z"]))
			if pa.distance_to(pb) <= r:
				if not any:
					im.surface_begin(Mesh.PRIMITIVE_LINES)
					any = true
				im.surface_set_color(Color("1f8a8a"))
				im.surface_add_vertex(Vector3(pa.x, terrain.height_at(pa.x, pa.y) + 0.4, pa.y))
				im.surface_add_vertex(Vector3(pb.x, terrain.height_at(pb.x, pb.y) + 0.4, pb.y))
	if any:
		im.surface_end()
	_net.mesh = im
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	_net.material_override = m


func _refresh_info() -> void:
	UiKit.clear(_info_holder)
	if selected_id >= 0 and GameSession.state.colony.building_by_id(selected_id).is_empty():
		selected_id = -1
	if selected_id >= 0:
		_info_holder.add_child(ColonyUi.info_panel(GameSession.sim, selected_id, {
			"module": func(bid: int, m: String) -> void: GameSession.cmd_add_module(bid, m),
			"demolish": func(bid: int) -> void:
				GameSession.cmd_demolish(bid)
				selected_id = -1
				_sync(),
			"incubate": func() -> void: GameSession.cmd_start_incubation(int(GameSession.content.bal("incubation.cohort_size", 10))),
			"council": func() -> void: GameSession.cmd_form_council(),
		}))
	var bn: Array = GameSession.state.colony.last_report.get("bottlenecks", [])
	if not bn.is_empty():
		var p := UiKit.panel(Vector2(380, 0))
		var v := UiKit.vbox(2)
		v.add_child(UiKit.title(Loc.t("Flaskehalse")))
		for x: Dictionary in bn.slice(0, 5):
			v.add_child(UiKit.label("▲ %s: %s" % [GameSession.content.building(str(x["def_id"])).get("name"), str(x["text"])], 14, UiKit.WARN, true))
		p.add_child(v)
		_info_holder.add_child(p)


## Up to ~40 visible citizens illustrate the cohorts (bible p.11); they never
## change population data. Robots show up at construction sites.
func _sync_people() -> void:
	var gs: GameState = GameSession.state
	var want_people := mini(40, gs.population.alive_count())
	var robots := 0
	for b: Dictionary in gs.colony.buildings:
		if b["state"] == ColonyState.B_CONSTRUCTING:
			robots += 1
	var want := want_people + mini(robots * 2, 12)
	while _people_nodes.size() < want:
		var is_robot := _people_nodes.size() >= want_people
		var slot := "char.robot_worker" if is_robot else ("char.citizen_child" if gs.population.count_stage("adult") == 0 or _people_nodes.size() % 3 == 0 else "char.citizen_adult")
		var n := VisualSlot.make(slot)
		n.set_meta("robot", is_robot)
		n.set_meta("seed", _people_nodes.size())
		_people.add_child(n)
		_people_nodes.append(n)
	while _people_nodes.size() > want:
		var n: Node3D = _people_nodes.pop_back()
		n.queue_free()


func _process(delta: float) -> void:
	_t += delta
	var gs: GameState = GameSession.state
	if gs == null or gs.colony == null:
		return
	var living: Dictionary = DictUtil.get_dict(DictUtil.get_dict(site, "districts"), "living")
	var lc: Array = DictUtil.get_arr(living, "center")
	var targets: Array = []
	for b: Dictionary in gs.colony.buildings:
		if b["state"] == ColonyState.B_CONSTRUCTING:
			targets.append(Vector2(float(b["x"]), float(b["z"])))
	for n: Node3D in _people_nodes:
		var s := float(int(n.get_meta("seed")))
		var center := Vector2(float(lc[0]), float(lc[1])) if lc.size() == 2 else Vector2.ZERO
		var rad := 14.0
		if n.get_meta("robot") and not targets.is_empty():
			center = targets[int(s) % targets.size()]
			rad = 5.0
		var ang := _t * (0.05 + fmod(s * 0.37, 0.1)) + s * 1.7
		var p := center + Vector2(cos(ang), sin(ang * 0.8)) * rad * (0.4 + fmod(s * 0.13, 0.6))
		n.position = Vector3(p.x, terrain.height_at(p.x, p.y), p.y)
		n.rotation.y = -ang
	if not build_def.is_empty():
		_update_ghost()


func _unhandled_input(event: InputEvent) -> void:
	if hud.any_modal_open() or _overlay_open():
		return
	if event.is_action_pressed("colony_mode"):
		_toggle_mode()
		get_viewport().set_input_as_handled()
		return
	if mode != "overhead":
		return
	if event.is_action_pressed("speed_pause"):
		GameSession.set_colony_speed(0 if GameSession.colony_speed > 0 else 1)
	elif event.is_action_pressed("speed_1"):
		GameSession.set_colony_speed(1)
	elif event.is_action_pressed("speed_3"):
		GameSession.set_colony_speed(3)
	elif event.is_action_pressed("build_confirm") and not build_def.is_empty():
		_confirm_build()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("rotate_building") and not build_def.is_empty():
		build_rot = (build_rot + 1) % 4
	elif event.is_action_pressed("cancel") and not build_def.is_empty():
		_cancel_build()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		if not build_def.is_empty():
			# On touch a tap moves the ghost; the "Byg" button confirms.
			if not TouchControls.enabled:
				_confirm_build()
		else:
			_pick((event as InputEventMouseButton).position)
		get_viewport().set_input_as_handled()


func _overlay_open() -> bool:
	return overview.visible or event_dialog.visible or decision.visible


func _toggle_mode() -> void:
	if mode == "overhead":
		mode = "captain"
		_cancel_build()
		cam_rig.active = false
		captain.visible = true
		captain.set_active(true)
		captain.camera_rig.make_current()
		_build_bar.visible = false
	else:
		mode = "overhead"
		captain.set_active(false)
		captain.visible = false
		cam_rig.active = true
		cam_rig.position = Vector3(captain.global_position.x, 0, captain.global_position.z)
		cam_rig.make_current()
		_build_bar.visible = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _mouse_ground(screen: Vector2) -> Variant:
	var cam := cam_rig.cam
	var from := cam.project_ray_origin(screen)
	var dir := cam.project_ray_normal(screen)
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * 1500.0, 16)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return null
	return hit["position"]


func _pick(screen: Vector2) -> void:
	var cam := cam_rig.cam
	var from := cam.project_ray_origin(screen)
	var q := PhysicsRayQueryParameters3D.create(from, from + cam.project_ray_normal(screen) * 1500.0, 8)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty() and (hit["collider"] as Node).has_meta("building_id"):
		selected_id = int((hit["collider"] as Node).get_meta("building_id"))
		AudioService.ui("ui_click")
	else:
		selected_id = -1
	_refresh_info()


func _start_build(def_id: String) -> void:
	_cancel_build()
	build_def = def_id
	selected_id = -1
	ghost = Node3D.new()
	var v := VisualSlot.make(str(GameSession.content.building(def_id).get("visual_slot", "building." + def_id)), "#5fae6e")
	ghost.add_child(v)
	add_child(ghost)
	hud.root.get_node("GhostTip").visible = true
	_refresh_info()


func _cancel_build() -> void:
	build_def = ""
	if ghost:
		ghost.queue_free()
		ghost = null
	if hud and hud.root.has_node("GhostTip"):
		hud.root.get_node("GhostTip").visible = false


func _update_ghost() -> void:
	# Controller: the build cursor is the screen centre; move the camera to aim.
	var screen := get_viewport().get_visible_rect().size * 0.5 if SettingsService.using_pad else get_viewport().get_mouse_position()
	var gp: Variant = _mouse_ground(screen)
	if gp == null:
		return
	var p: Vector3 = gp
	ghost_pos = Vector2(roundf(p.x), roundf(p.z))
	var chk := GameSession.sim.colony.check_placement(GameSession.state, build_def, ghost_pos.x, ghost_pos.y, build_rot)
	ghost_ok = chk["ok"]
	ghost.position = Vector3(ghost_pos.x, terrain.height_at(ghost_pos.x, ghost_pos.y) + 0.05, ghost_pos.y)
	ghost.rotation.y = build_rot * PI * 0.5
	var vs: VisualSlot = ghost.get_child(0)
	var want := "#5fae6e" if ghost_ok else "#d25b4c"
	if vs.tint != want:
		vs.tint = want
		vs.rebuild()
	var def := GameSession.content.building(build_def)
	var cost: Dictionary = chk["cost"]
	_ghost_tip.text = Loc.t("%s — %s\n%s\n[Venstre klik] byg · [%s] drej · [Højre klik/Esc] fortryd") % [def.get("name"),
		Loc.t("● kan bygges") if ghost_ok else Loc.t("✕ kan ikke bygges"), " ".join(chk["reasons"]) if not ghost_ok else Loc.t("Pris: %d mat.%s · %+d kW") % [int(cost.get("alloy", 0)), (Loc.t(" + %d komp.") % int(cost["components"])) if cost.has("components") else "", int(def.get("power_kw", 0))],
		SettingsService.binding_text("rotate_building")]
	_ghost_tip.add_theme_color_override("font_color", UiKit.TEXT if ghost_ok else UiKit.WARN)


func _confirm_build() -> void:
	if not ghost_ok:
		AudioService.ui("ui_error")
		return
	var r := GameSession.cmd_place_building(build_def, ghost_pos, build_rot)
	if r.ok and not Input.is_key_pressed(KEY_SHIFT):
		_cancel_build()


func _open_overview() -> void:
	GameSession.set_colony_speed(0)
	overview.open()


func _after_leap() -> void:
	_sync()
	var y := int(GameSession.state.campaign.colony_year())
	for id: String in ["year_20", "year_40"]:
		var target := 20 if id == "year_20" else 40
		var done := false
		for d: Dictionary in GameSession.state.society.decisions:
			if d.get("id") == id:
				done = true
		if y >= target and not done:
			decision.ask(id)
			break
	_check_pending_event()


func _check_pending_event() -> void:
	var gs: GameState = GameSession.state
	for a: Dictionary in gs.events.active:
		if a.get("phase") == "active":
			event_dialog.show_event(GameSession.content.events.get(str(a.get("id")), {}))
			return


func debug_action(action: String) -> void:
	match action:
		"ghost":
			_start_build("habitat")
			var gs: GameState = GameSession.state
			var lc: Array = site["districts"]["living"]["center"]
			ghost_pos = Vector2(float(lc[0]), float(lc[1]))
			ghost.position = Vector3(ghost_pos.x, terrain.height_at(ghost_pos.x, ghost_pos.y), ghost_pos.y)
		"select_ark":
			selected_id = 1
			_refresh_info()
		"overview":
			overview.open()
		"future":
			overview.open()
			overview._start_forecast()
		"zoomout":
			cam_rig.zoom = 110.0
		"event":
			for id: String in GameSession.content.events.keys():
				if GameSession.content.events[id].get("critical", false):
					event_dialog.show_event(GameSession.content.events[id])
					break
		"decision":
			decision.ask("year_20")

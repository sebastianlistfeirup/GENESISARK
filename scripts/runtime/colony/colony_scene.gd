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
var _build_bar: HFlowContainer  # wraps to two rows when the screen is narrow (UI scale)
var _top: VBoxContainer
var _ghost_tip: Label
var _life: ColonyLife
var _cover: Node3D
var _roads: Node3D
var _paths: ColonyPaths
var _district_marks: Array[Node3D] = []
const DISTRICT_MARKS_UNTIL := 24  # buildings; a bigger colony shows its districts only while placing
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
	# The world's architecture (Synty demo-scene families): explorer pods, corporation, scavenger.
	AssetSlots.style = str(GroundCover.spec_for(gs.colony.planet_id, "").get("colony_style", ""))
	if AssetSlots.style == "explorer":
		AssetSlots.style = ""
	ResourcePrefetch.request(_prefetch_paths(gs))  # D-054: pack scenes load on worker threads meanwhile
	MeshLod.small_shadow_rules = true
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
	terrain.apply_planet_style(gs.colony.planet_id)
	var reach: Array = []
	for a: Array in avoid:
		reach.append(a[0])
		for i: int in 8:
			reach.append(a[0] + Vector2.from_angle(TAU * i / 8.0) * float(a[1]))
	terrain.set_water_below(reach, false)
	add_child(terrain)
	terrain.build()
	terrain.scatter(hash(gs.colony.site_id) + 1, 60 if GroundCover.spec_for(gs.colony.planet_id, "").is_empty() else 0, avoid)
	add_child(PlanetSky.build(gs.colony.planet_id, gs.colony.biome_id, terrain))
	_draw_districts()
	SceneDressing.attach(self, str(site.get("id", "")), terrain)
	_net = MeshInstance3D.new()
	add_child(_net)
	_life = ColonyLife.new()
	_life.terrain = terrain
	var lv: Array = DictUtil.get_arr(districts.get("living", {}), "center")
	_life.living_center = Vector2(float(lv[0]), float(lv[1])) if lv.size() == 2 else Vector2.ZERO
	add_child(_life)
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
	if AppFlow.params.get("landing", false) or str(AppFlow.params.get("action", "")).begins_with("descent"):
		_maybe_ark_descent()
	_check_pending_event()
	ResourcePrefetch.release()


## Pack scenes this colony builds from: its buildings' wrappers, the street
## dressing, corridor modules, the planet's ground cover and the colonists.
func _prefetch_paths(gs: GameState) -> Array:
	AssetSlots.slots()
	var out: Array = []
	for b: Dictionary in gs.colony.buildings:
		var def := GameSession.content.building(str(b["def_id"]))
		out.append_array(AssetSlots.scene_paths(str(def.get("visual_slot", "building." + str(b["def_id"])))))
	for slot: String in ["char.citizen_adult", "char.citizen_child", "char.robot_worker"]:
		out.append_array(AssetSlots.scene_paths(slot))
	ResourcePrefetch.paths_in(BuildingDressing.doc(), BuildingDressing.resolve, out)
	out.append_array(ColonyCorridors.MODULES)
	ResourcePrefetch.paths_in(GroundCover.spec_for(gs.colony.planet_id, gs.colony.biome_id), Callable(), out)
	return out


func _draw_districts() -> void:
	var labels := {"landing": Loc.t("Landing zone"), "resource": Loc.t("Resource area"), "living": Loc.t("Living zone")}
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
		_district_marks.append(ring)
		var lbl := Label3D.new()
		lbl.text = labels[dk]
		lbl.font_size = 96
		lbl.pixel_size = 0.02
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lbl.modulate = Color(cols[dk])
		# Above trees and roofs, drawn on top with an outline so nothing hides it.
		lbl.position = ring.position + Vector3(0, 4.0, -r)
		lbl.pixel_size = 0.014
		lbl.no_depth_test = true
		lbl.outline_size = 18
		lbl.outline_modulate = Color(0, 0, 0, 0.55)
		lbl.render_priority = 2
		add_child(lbl)
		_district_marks.append(lbl)
	for bz: Dictionary in DictUtil.get_arr(site, "blocked"):
		var bc: Array = DictUtil.get_arr(bz, "center")
		var spec := GroundCover.spec_for(gs_planet_id(), "")
		var rock := GroundCover.mesh_of(str(spec.get("blocked_rock", "")), DictUtil.get_dict(spec, "look"))
		if not rock.is_empty():
			# The world's own rock formation marks ground that cannot be built on: a
			# low cluster of outcrops across the zone (one big piece scaled to the zone's
			# width filled the default colony camera), each at most ~0.55 x radius high.
			var rb: AABB = rock[2]
			var r := DictUtil.get_float(bz, "radius")
			var rng := RandomNumberGenerator.new()
			rng.seed = absi(hash(bc))
			var pieces := [[Vector2.ZERO, 1.0]]
			for k: int in 4:
				pieces.append([Vector2.from_angle(TAU * k / 4.0 + rng.randf_range(-0.5, 0.5)) * r * rng.randf_range(0.45, 0.7), rng.randf_range(0.45, 0.7)])
			for pc: Array in pieces:
				var w := r * 1.0 * float(pc[1])
				var sc := w / maxf(maxf(rb.size.x, rb.size.z), 0.1)
				var sy := minf(sc, r * 0.55 * float(pc[1]) / maxf(rb.size.y, 0.1))
				var pos := Vector2(float(bc[0]), float(bc[1])) + (pc[0] as Vector2)
				var mi := MeshInstance3D.new()
				mi.mesh = rock[0]
				mi.transform = Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(sc, sy, sc)), Vector3(pos.x, terrain.height_at(pos.x, pos.y) - rb.position.y * sy - 0.4, pos.y)) * (rock[1] as Transform3D)
				add_child(mi)
			continue
		var m := VisualSlot.make("surface.rock_large", "#5f5d58")
		m.position = Vector3(float(bc[0]), terrain.height_at(float(bc[0]), float(bc[1])) - 0.5, float(bc[1]))
		m.scale = Vector3(1.0, 0.6, 1.0) * DictUtil.get_float(bz, "radius") / 2.5
		add_child(m)


func _build_ui() -> void:
	var top := UiKit.vbox(6)
	_top = top
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
		sp.add_child(UiKit.button(s[1], func() -> void: GameSession.set_colony_speed(int(s[0])), Loc.t("Pause / 1x / 3x (%s, %s, %s)") % [SettingsService.primary_key("speed_pause"), SettingsService.primary_key("speed_1"), SettingsService.primary_key("speed_3")]))
	sp.add_child(UiKit.button(Loc.t("Colony overview"), func() -> void: _open_overview(), Loc.t("Supply, population, generation leap and council")))
	sp.add_child(UiKit.button(Loc.t("Captain [%s]") % SettingsService.primary_key("colony_mode"), _toggle_mode, Loc.t("Walk the colony as the captain")))
	top.add_child(sp)
	_info_holder = UiKit.vbox(6)
	hud.top_right.add_child(_info_holder)
	_build_bar = HFlowContainer.new()
	_build_bar.alignment = FlowContainer.ALIGNMENT_CENTER
	_build_bar.add_theme_constant_override("h_separation", 6)
	_build_bar.add_theme_constant_override("v_separation", 6)
	hud.bottom.add_child(_build_bar)
	for def_id: String in ["solar_array", "geothermal_generator", "battery", "water_plant", "greenhouse", "habitat", "mine", "workshop", "drone_hub", "care_center", "clinic", "school_hall"]:
		var def := GameSession.content.building(def_id)
		var b := UiKit.button(str(def.get("name")).replace(Loc.t(" and incubation center"), ""), func() -> void: _start_build(def_id))
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
	_speed_label.text = Loc.t("Year %d · day %d   %s") % [int(gs.campaign.colony_year()), gs.campaign.colony_day % 365, [Loc.t("Pause"), "1x", "", "3x"][clampi(GameSession.colony_speed, 0, 3)]]
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
		b.text = Loc.t("%s\n%d mat.%s") % [str(GameSession.content.building(def_id).get("name")).replace(Loc.t(" and incubation center"), "").replace(Loc.t("Geothermal generator"), Loc.t("Geothermal")), int(cost.get("alloy", 0)), (Loc.t(" · %d comp.") % int(cost["components"])) if cost.has("components") else ""]
	_draw_network()
	_draw_corridors()
	_relayout()
	_refresh_info()
	_sync_people()


var _corridors: Node3D
var _corridor_key := ""


## Walkway tubes along a spanning tree of the active links (visual only).
func _draw_corridors() -> void:
	var gs: GameState = GameSession.state
	var key := ""
	for b: Dictionary in gs.colony.buildings:
		if b.get("accessible") and b.get("state") == ColonyState.B_ACTIVE:
			key += "%d," % int(b["id"])
	if key == _corridor_key:
		_process_network_visibility()
		return
	_corridor_key = key
	if _corridors:
		_corridors.queue_free()
	_corridors = ColonyCorridors.build(gs, terrain)
	MeshLod.add_shadow_twins(_corridors)  # D-054
	add_child(_corridors)
	if AssetSlots.style == "corp":
		if _perimeter:
			_perimeter.queue_free()
		_perimeter = ColonyPerimeter.build(gs, site, terrain)
		add_child(_perimeter)
	_process_network_visibility()


var _perimeter: Node3D
var _dressing: ColonyDressing
var _layout_key := ""


## Set dressing, roads and the walking grid follow the building set; rebuilt only
## when a building is added, removed, or finishes construction (visual only).
func _relayout() -> void:
	var gs: GameState = GameSession.state
	var key := _corridor_key + "|"
	for b: Dictionary in gs.colony.buildings:
		key += "%d:%s," % [int(b["id"]), str(b["state"]) == ColonyState.B_CONSTRUCTING]
	if key == _layout_key:
		return
	_layout_key = key
	var clear := ColonyClearance.new()
	for b: Dictionary in gs.colony.buildings:
		var def := GameSession.content.building(str(b["def_id"]))
		clear.add_rect(ColonySimulation.rect_for(def, float(b["x"]), float(b["z"]), int(b.get("rot", 0))), int(b["id"]))
	var segs: Array = _corridors.get_meta("segments") if _corridors and _corridors.has_meta("segments") else []
	for sg: Array in segs:
		clear.add_segment(sg[0], sg[1], ColonyCorridors.WIDTH * 0.5 + 0.2)
	var road_cfg: Dictionary = DictUtil.get_dict(BuildingDressing.doc(), "roads")
	var road_w := DictUtil.get_float(road_cfg, "width", 3.2)
	_paths = ColonyPaths.new()
	_paths.build(gs, site, segs, 220.0)
	for rd: PackedVector2Array in _paths.roads:
		clear.add_polyline(rd, road_w * 0.5 + 0.3)
	_draw_roads(road_cfg, clear)
	if _cover == null:
		_lay_ground_cover(clear)
	_prune_cover(clear)
	if _dressing == null:
		_dressing = ColonyDressing.new()
		_dressing.name = "Dressing"
		_dressing.weather_world = str(planet.get("id", ""))
		add_child(_dressing)
	var lights: Dictionary = DictUtil.get_dict(BuildingDressing.doc(), "lights")
	_open_crossings()
	var dl: Array = []
	var dscale := GameSession.sim.colony.district_scale(gs)
	for dk: String in DictUtil.get_dict(site, "districts").keys():
		var dc: Array = DictUtil.get_arr(site["districts"][dk], "center")
		if dc.size() == 2:
			dl.append([dk, Vector2(float(dc[0]), float(dc[1])), DictUtil.get_float(site["districts"][dk], "radius") * dscale])
	var rocks: Array = []  # the site's blocked rock formations (drawn ~1.1 x radius wide) and colliding plants
	for bz: Dictionary in DictUtil.get_arr(site, "blocked"):
		var bc: Array = DictUtil.get_arr(bz, "center")
		if bc.size() == 2:
			rocks.append([Vector2(float(bc[0]), float(bc[1])), DictUtil.get_float(bz, "radius") * 1.25 + 0.5])
	if _cover:  # tree trunks and landmarks that collide: no market or parked rover grows through them
		for n: Node in _cover.find_children("*", "CollisionShape3D", true, false):
			var cs := n as CollisionShape3D
			if cs.disabled or not cs.is_inside_tree():
				continue
			var r := 1.5
			if cs.shape is CylinderShape3D:
				r = (cs.shape as CylinderShape3D).radius
			elif cs.shape is BoxShape3D:
				r = maxf((cs.shape as BoxShape3D).size.x, (cs.shape as BoxShape3D).size.z) * 0.5
			elif cs.shape is SphereShape3D:
				r = (cs.shape as SphereShape3D).radius
			rocks.append([Vector2(cs.global_position.x, cs.global_position.z), r + 0.8])
	_dressing.rebuild(views, terrain, clear, float(lights.get(str(planet.get("id", "")), lights.get("_default", 0.45))), dl,
		DictUtil.get_dict(DictUtil.get_dict(BuildingDressing.doc(), "night"), str(planet.get("id", ""))), _paths.roads, rocks)
	_prune_cover(_dressing.street_area)  # no tree through a market stall or a parked rover
	_paths.block_discs(_dressing.kept)  # walkers step around the crates and lamps
	_life.relayout(gs, _paths)
	_life.set_crowd(gs, _dressing.crowd)


## Where a road has to run through a corridor tube, the one tube module there is
## left out and both cut ends get an end cap (an airlock gate), so vehicles and
## walkers never pass through its walls.
func _open_crossings() -> void:
	if _corridors == null or _paths == null:
		return
	for c: Node in _corridors.get_children():
		if c.has_meta("gate_cap"):
			c.queue_free()
		elif c is MeshInstance3D:
			(c as MeshInstance3D).visible = true
	var cap: Dictionary = BuildingDressing.parts(str(DictUtil.get_dict(BuildingDressing.doc(), "roads").get("gate_cap", "")))
	for h: Vector2 in _paths.crossings():
		var best: MeshInstance3D = null
		var bd := INF
		for c: Node in _corridors.get_children():
			if c is MeshInstance3D and not c.has_meta("gate_cap") and not c.has_meta("joint"):
				var w: Vector3 = (c as MeshInstance3D).transform * (c as MeshInstance3D).get_aabb().get_center()
				if Vector2(w.x, w.z).distance_to(h) < bd:
					bd = Vector2(w.x, w.z).distance_to(h)
					best = c
		if best == null or bd > 4.0 or not best.visible:
			continue
		best.visible = false
		if cap.is_empty():
			continue
		var box := best.get_aabb()
		var cb: AABB = cap["aabb"]
		for zend: float in [box.position.z + cb.size.z * 0.5, box.end.z - cb.size.z * 0.5]:
			var at: Vector3 = best.transform * Vector3(box.get_center().x, box.position.y, zend)
			var turn := 0.0 if zend < box.get_center().z else PI  # the cap faces the road
			var xf := Transform3D(best.transform.basis * Basis(Vector3.UP, turn), at) * Transform3D(Basis.IDENTITY, -Vector3(cb.get_center().x, cb.position.y, cb.get_center().z))
			for part: Array in cap["parts"]:
				var mi := MeshInstance3D.new()
				mi.mesh = part[0]
				mi.transform = xf * (part[1] as Transform3D)
				mi.set_meta("gate_cap", true)
				_corridors.add_child(mi)


## Dirt roads between the districts, a darker tone of the planet's ground.
func _draw_roads(cfg: Dictionary, under: ColonyClearance) -> void:
	if _roads:
		_roads.queue_free()
	_roads = Node3D.new()
	_roads.name = "Roads"
	add_child(_roads)
	# The terrain's own ground tone (same rule as TerrainBuilder.build), trodden darker.
	var base := Color(str(terrain.palette.get("nature", DictUtil.get_str(terrain.map_def, "base_color", "#556b4a"))))
	var ground := base.darkened(0.25) if terrain.biome_id == "green" else (base.darkened(0.12) if terrain.biome_id == "ice" else base)
	ground = Color.from_hsv(ground.h, clampf(ground.s * 1.25, 0.0, 1.0), ground.v)
	var tstyle: Dictionary = terrain.style
	if tstyle.has("ground"):
		ground = Color(str(tstyle["ground"]))
	var col := Color.from_hsv(ground.h, clampf(ground.s * 1.05, 0.0, 1.0), ground.v * DictUtil.get_float(cfg, "darken", 0.62))
	var per: Dictionary = DictUtil.get_dict(cfg, "colors")  # a dirt tone per world reads better than a shade
	if per.has(str(planet.get("id", ""))):
		col = Color(str(per[str(planet.get("id", ""))]))
	# Night worlds: a lighter, faintly glowing track and lit edge studs; day
	# worlds get plain reflective studs (data: roads.night / roads.markers).
	var pid := str(planet.get("id", ""))
	var night: Dictionary = DictUtil.get_dict(DictUtil.get_dict(cfg, "night"), pid)
	if night.has("color"):
		col = Color(str(night["color"]))
	var marks: Dictionary = DictUtil.get_dict(cfg, "markers")
	var mk: Dictionary = DictUtil.get_dict(marks, pid) if marks.has(pid) else DictUtil.get_dict(marks, "_default")
	var w := DictUtil.get_float(cfg, "width", 3.2)
	var grow := BuildingDressing.platform_margin() - 0.2
	for rd: PackedVector2Array in _paths.roads:
		_roads.add_child(ColonyPaths.road_mesh(rd, terrain, col, w, DictUtil.get_float(cfg, "shoulder", 1.4), under, grow, DictUtil.get_float(night, "glow", 0.0)))
		if not mk.is_empty():
			_roads.add_child(ColonyPaths.road_markers(rd, terrain, w, DictUtil.get_float(mk, "every", 5.0), Color(str(mk.get("color", "#ffb04a"))),
				DictUtil.get_float(mk, "energy", 0.0), under, grow + 0.3))


## Ground cover is laid with the first layout (district cores, buildings, roads
## and tubes stay clear; plants grow right up to them) and then kept stable.
func _lay_ground_cover(clear: ColonyClearance) -> void:
	var avoid: Array = []
	var dscale := GameSession.sim.colony.district_scale(GameSession.state)
	for dk: String in DictUtil.get_dict(site, "districts").keys():
		var dc: Array = DictUtil.get_arr(site["districts"][dk], "center")
		avoid.append([Vector2(float(dc[0]), float(dc[1])), DictUtil.get_float(site["districts"][dk], "radius") * dscale * 0.6])
	for bz: Dictionary in DictUtil.get_arr(site, "blocked"):
		var bc: Array = DictUtil.get_arr(bz, "center")
		avoid.append([Vector2(float(bc[0]), float(bc[1])), DictUtil.get_float(bz, "radius") + 1.0])
	var segs: Array = _corridors.get_meta("segments") if _corridors and _corridors.has_meta("segments") else []
	for sg: Array in segs:
		var a: Vector2 = sg[0]
		var b: Vector2 = sg[1]
		for k: int in int(a.distance_to(b) / 2.0) + 1:
			avoid.append([a.lerp(b, k * 2.0 / maxf(a.distance_to(b), 0.01)), 2.2])
	var road_w := DictUtil.get_float(DictUtil.get_dict(BuildingDressing.doc(), "roads"), "width", 3.0)
	for rd: PackedVector2Array in _paths.roads:
		for i: int in range(0, rd.size(), 2):
			avoid.append([rd[i], road_w * 0.5 + 1.8])
	for rr: Array in clear.rects():
		var r: Rect2 = rr[0]
		avoid.append([r.get_center(), r.size.length() * 0.5 + 2.0])
	var gs: GameState = GameSession.state
	_cover = GroundCover.build(terrain, gs.colony.planet_id, hash(gs.colony.site_id) + 3, avoid, 220.0, gs.colony.biome_id)
	# D-054: chunks get their own LOD and culling; the overhead camera sees ~250 m, so nothing is range-culled sooner than before.
	MeshLod.split_multimeshes(_cover, 40.0, 300.0)
	add_child(_cover)
	# D-053: a lighter set of the world's wildlife out past the districts' full
	# grown extent (buildings, roads and tubes come later; animals keep clear).
	var wild_avoid := avoid.duplicate()
	wild_avoid.append_array(GroundWildlife.obstacles(_cover))
	for dk: String in DictUtil.get_dict(site, "districts").keys():
		var dc: Array = DictUtil.get_arr(site["districts"][dk], "center")
		wild_avoid.append([Vector2(float(dc[0]), float(dc[1])), DictUtil.get_float(site["districts"][dk], "radius") * 2.0 + 10.0])
	var wild_spec := GroundCover.spec_for(gs.colony.planet_id, gs.colony.biome_id)
	add_child(GroundWildlife.build(terrain, DictUtil.get_arr(wild_spec, "wildlife"), hash(gs.colony.site_id) + 13, wild_avoid, 220.0, null, 0.5))


## Ground cover is laid once (stable, deterministic); each new layout hides the
## pieces a building, road or corridor now stands on (tree trunks stop colliding
## there too) and any landmark silhouette the grown colony has reached.
func _prune_cover(clear: ColonyClearance) -> void:
	if _cover == null:
		return
	for c: Node in _cover.get_children():
		if c is MultiMeshInstance3D:
			var mm := (c as MultiMeshInstance3D).multimesh
			# Big alien plants spread metres from their stem: test their canopy, not
			# only the stem (they grew through roofs in the grown districts).
			var mb := mm.mesh.get_aabb() if mm.mesh else AABB()
			var half := maxf(mb.size.x, mb.size.z) * 0.35
			for i: int in mm.instance_count:
				var xf := mm.get_instance_transform(i)
				var sx := xf.basis.get_scale().x
				if sx > 0.0001 and clear.blocked(Vector2(xf.origin.x, xf.origin.z), maxf(0.5, half * sx), -1, half * sx > 1.5):
					mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ONE * 0.00001), xf.origin))
		elif c is MeshInstance3D and (c as MeshInstance3D).visible:
			var mi := c as MeshInstance3D
			var box: AABB = mi.transform * mi.get_aabb()
			if clear.blocked(Vector2(box.get_center().x, box.get_center().z), maxf(box.size.x, box.size.z) * 0.4, -1, true):
				mi.visible = false
		elif c is StaticBody3D:
			for cs: Node in c.get_children():
				if cs is CollisionShape3D and not (cs as CollisionShape3D).disabled:
					var at := (cs as Node3D).position
					if clear.blocked(Vector2(at.x, at.z), 0.5):
						(cs as CollisionShape3D).disabled = true


## District rings and names explain the map early on; once the colony has grown
## into a town they would cut through it, so they only show while placing.
func _process_district_marks() -> void:
	var show := not build_def.is_empty() or GameSession.state == null or GameSession.state.colony == null \
		or GameSession.state.colony.buildings.size() < DISTRICT_MARKS_UNTIL
	for n: Node3D in _district_marks:
		if is_instance_valid(n) and n.visible != show:
			n.visible = show


func _process_network_visibility() -> void:
	_process_district_marks()
	# The raw link lines are a build-mode aid; outside it the corridors carry the read.
	if _net:
		_net.visible = not build_def.is_empty() or _corridors == null or _corridors.get_child_count() == 0


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
		v.add_child(UiKit.title(Loc.t("Bottlenecks")))
		for x: Dictionary in bn.slice(0, 5):
			v.add_child(UiKit.label("▲ %s: %s" % [GameSession.content.building(str(x["def_id"])).get("name"), str(x["text"])], 14, UiKit.WARN, true))
		p.add_child(v)
		_info_holder.add_child(p)


## Up to ~40 visible citizens illustrate the cohorts (bible p.11); they never
## change population data. Robots show up at construction sites. ColonyLife
## walks them along the colony's paths.
func _sync_people() -> void:
	_life.sync_people(GameSession.state)


var _follow: Node3D  # evidence only ("people" debug action)


func _process(delta: float) -> void:
	_process_network_visibility()
	if is_instance_valid(_follow):
		cam_rig.position = _follow.position
	_t += delta
	_layout_hud()
	var gs: GameState = GameSession.state
	if gs == null or gs.colony == null:
		return
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


## Narrow screens (1280x720, UI scale 1.5): the build bar wraps instead of
## running off both edges, and the objective/info columns and the subtitles
## make room for the top and bottom bars instead of overlapping them.
func _layout_hud() -> void:
	if hud == null or _build_bar == null:
		return
	var vis := get_viewport().get_visible_rect().size
	var natural := 0.0
	for b: Control in _build_bar.get_children():
		natural += b.get_combined_minimum_size().x + 6.0
	var w := minf(natural, vis.x - 48.0)
	if not is_equal_approx(_build_bar.custom_minimum_size.x, w):
		_build_bar.custom_minimum_size.x = w
	var top_rect := _top.get_global_rect()
	var side_w := maxf(hud.objective_rect().size.x, 380.0) + 24.0 + 12.0
	var top_inset := top_rect.end.y + 8.0 - 20.0 if top_rect.position.x < side_w else 0.0
	var bottom_h := hud.bottom.size.y if _build_bar.visible else 0.0
	hud.set_insets(top_inset, maxf(0.0, bottom_h - 60.0))


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
	_ghost_tip.text = Loc.t("%s — %s\n%s\n[Left click] build · [%s] rotate · [Right click/Esc] cancel") % [def.get("name"),
		Loc.t("● can be built") if ghost_ok else Loc.t("✕ cannot be built"), " ".join(chk["reasons"]) if not ghost_ok else Loc.t("Cost: %d mat.%s · %+d kW") % [int(cost.get("alloy", 0)), (Loc.t(" + %d comp.") % int(cost["components"])) if cost.has("components") else "", int(def.get("power_kw", 0))],
		SettingsService.binding_text("rotate_building")]
	_ghost_tip.add_theme_color_override("font_color", UiKit.TEXT if ghost_ok else UiKit.WARN)


func _confirm_build() -> void:
	if not ghost_ok:
		AudioService.ui("ui_error")
		return
	var r := GameSession.cmd_place_building(build_def, ghost_pos, build_rot)
	if r.ok and not Input.is_action_pressed("build_repeat"):
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


## Evidence only: plans n door-to-door routes the way ColonyLife does and
## measures, every 10 cm, the distance to the nearest footprint and tube wall.
func _walk_audit(n: int) -> Dictionary:
	var gs: GameState = GameSession.state
	var doors: Array = []
	for b: Dictionary in gs.colony.buildings:
		if b["state"] == ColonyState.B_ACTIVE:
			var d := _paths.door(b, _life.living_center)
			if _paths.walkable(d):
				doors.append(d)
	var rects: Array = []
	for b: Dictionary in gs.colony.buildings:
		rects.append(ColonySimulation.rect_for(GameSession.content.building(str(b["def_id"])), float(b["x"]), float(b["z"]), int(b.get("rot", 0))))
	var segs: Array = _corridors.get_meta("segments") if _corridors and _corridors.has_meta("segments") else []
	var gates: Array = _paths.crossings()  # tube modules left out where a road passes
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var out := {"routes": 0, "samples": 0, "in_footprint": 0, "under_0_3m": 0, "in_tube": 0, "min_clear": INF}
	for i: int in n:
		if doors.size() < 2:
			break
		var r := _paths.route(doors[rng.randi() % doors.size()], doors[rng.randi() % doors.size()])
		if r.size() < 2:
			continue
		out["routes"] += 1
		for k: int in range(1, r.size()):
			var steps := maxi(1, int(r[k - 1].distance_to(r[k]) / 0.1))
			for s: int in steps:
				var p := r[k - 1].lerp(r[k], float(s) / steps)
				out["samples"] += 1
				var best := INF
				for rc: Rect2 in rects:
					var c := Vector2(clampf(p.x, rc.position.x, rc.end.x), clampf(p.y, rc.position.y, rc.end.y))
					best = minf(best, c.distance_to(p))
				out["min_clear"] = minf(out["min_clear"], best)
				if best <= 0.0:
					out["in_footprint"] += 1
				elif best < 0.3:
					out["under_0_3m"] += 1
				var at_gate := false
				for h: Vector2 in gates:
					if h.distance_to(p) < 3.2:
						at_gate = true
				for sg: Array in ([] if at_gate else segs):
					if Geometry2D.get_closest_point_to_segment(p, sg[0], sg[1]).distance_to(p) < ColonyCorridors.WIDTH * 0.5:
						out["in_tube"] += 1
						break
	return out


func debug_action(action: String) -> void:
	if action.begins_with("district:"):  # evidence: "district:<landing|resource|living>:<zoom>[:<yaw deg>]"
		var parts := action.split(":")
		var dc: Array = DictUtil.get_arr(DictUtil.get_dict(DictUtil.get_dict(site, "districts"), parts[1]), "center")
		if dc.size() == 2:
			cam_rig.position = Vector3(float(dc[0]), terrain.height_at(float(dc[0]), float(dc[1])), float(dc[1]))
		cam_rig.zoom = float(parts[2]) if parts.size() > 2 else 40.0
		if parts.size() > 3:
			cam_rig.target_yaw = deg_to_rad(float(parts[3]))
			cam_rig.rotation.y = cam_rig.target_yaw
		if decision.visible:
			decision.hide()
		if event_dialog.visible:
			event_dialog.hide()
		get_viewport().warp_mouse(Vector2(get_viewport().get_visible_rect().size.x * 0.5, 160))  # no stray tooltip in the shot
		return
	if action.begins_with("wildlife"):  # evidence: "wildlife[:<n>[:<zoom>]]" the colony camera on the n-th animal (D-053)
		var parts := action.split(":")
		var wild := get_node_or_null("GroundWildlife") as GroundWildlife
		if wild and wild.count() > 0:
			var at := wild.animal_position(int(parts[1]) if parts.size() > 1 else 0)
			cam_rig.position = at
			cam_rig.target_yaw = atan2(at.x, at.z)  # look out from the colony
			cam_rig.rotation.y = cam_rig.target_yaw
		cam_rig.zoom = float(parts[2]) if parts.size() > 2 else 22.0
		if decision.visible:
			decision.hide()
		if event_dialog.visible:
			event_dialog.hide()
		get_viewport().warp_mouse(Vector2(get_viewport().get_visible_rect().size.x * 0.5, 160))
		return
	if action.begins_with("market"):  # evidence: "market[:<n>[:<zoom>[:<yaw deg>]]]" close-up on the n-th market crowd spot
		var parts := action.split(":")
		var spots: Array = _dressing.crowd if _dressing else []
		print("STREET_STATS ", _dressing.stats if _dressing else {})
		if not spots.is_empty():
			var p: Vector2 = (spots[mini(int(parts[1]) if parts.size() > 1 else 0, spots.size() - 1)] as Array)[0]
			cam_rig.position = Vector3(p.x, terrain.height_at(p.x, p.y), p.y)
		cam_rig.zoom = float(parts[2]) if parts.size() > 2 else 14.0
		if parts.size() > 3:
			cam_rig.target_yaw = deg_to_rad(float(parts[3]))
			cam_rig.rotation.y = cam_rig.target_yaw
		if decision.visible:
			decision.hide()
		if event_dialog.visible:
			event_dialog.hide()
		get_viewport().warp_mouse(Vector2(get_viewport().get_visible_rect().size.x * 0.5, 160))
		return
	match action:
		"people":  # evidence: close-up on a walking colonist (the camera follows them)
			_follow = _life.walker()
			cam_rig.zoom = 9.0
			if decision.visible:
				decision.hide()
			if event_dialog.visible:
				event_dialog.hide()
			get_viewport().warp_mouse(Vector2(get_viewport().get_visible_rect().size.x * 0.5, 160))
		"tri_audit":  # evidence: triangles per dressing batch (instances x mesh), biggest first
			var rows: Array = []
			for c: Node in _dressing.get_children():
				if c is MultiMeshInstance3D:
					var mm := (c as MultiMeshInstance3D).multimesh
					var tris := 0
					for s: int in mm.mesh.get_surface_count():
						var arr := mm.mesh.surface_get_arrays(s)
						var idx: Variant = arr[Mesh.ARRAY_INDEX]
						tris += (idx as PackedInt32Array).size() / 3 if idx != null else (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
					rows.append([tris * mm.instance_count, mm.instance_count, tris, str(mm.mesh.get_meta("short", "?"))])
			rows.sort_custom(func(a: Array, b: Array) -> bool: return int(a[0]) > int(b[0]))
			var total := 0
			for r: Array in rows:
				total += int(r[0])
			print("TRI_AUDIT total=", total)
			for r: Array in rows.slice(0, 25):
				print("TRI_AUDIT ", r)
		"walk_audit":  # evidence: how close walker routes come to footprints and corridor tubes
			print("WALK_AUDIT ", _walk_audit(400))
		"ghost":
			_start_build("habitat")
			var gs: GameState = GameSession.state
			var lc: Array = site["districts"]["living"]["center"]
			ghost_pos = Vector2(float(lc[0]), float(lc[1]))
			ghost.position = Vector3(ghost_pos.x, terrain.height_at(ghost_pos.x, ghost_pos.y), ghost_pos.y)
		"construct":  # evidence: a construction site close up (fx.construction_sparks)
			var lc: Array = site["districts"]["living"]["center"]
			for i: int in 24:
				var p := Vector2(float(lc[0]), float(lc[1])) + Vector2.from_angle(i * 0.9) * (4.0 + i * 1.5)
				if GameSession.cmd_place_building("habitat", p, 0).ok:
					_sync()
					cam_rig.position = Vector3(p.x, terrain.height_at(p.x, p.y), p.y)
					cam_rig.zoom = 24.0
					break
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
			if decision.visible:
				decision.hide()
			if event_dialog.visible:
				event_dialog.hide()
			get_viewport().warp_mouse(Vector2(get_viewport().get_visible_rect().size.x * 0.5, 160))  # no stray tooltip in the shot
		"living":  # evidence: the living district close up (citizens, habitats)
			var lc: Array = site["districts"]["living"]["center"]
			cam_rig.position = Vector3(float(lc[0]), terrain.height_at(float(lc[0]), float(lc[1])), float(lc[1]))
			cam_rig.zoom = 30.0
			if decision.visible:
				decision.hide()
			if event_dialog.visible:
				event_dialog.hide()
			cam_rig.zoom = 18.0
		"event":
			for id: String in GameSession.content.events.keys():
				if GameSession.content.events[id].get("critical", false):
					event_dialog.show_event(GameSession.content.events[id])
					break
		"decision":
			decision.ask("year_20")


func _exit_tree() -> void:
	AssetSlots.style = ""
	MeshLod.small_shadow_rules = false


func gs_planet_id() -> String:
	return GameSession.state.colony.planet_id if GameSession.state and GameSession.state.colony else ""


## The Ark comes down from orbit onto the landing zone in real time
## (PlanetDescent, D-049); the colony clock and its UI wait until touchdown.
func _maybe_ark_descent() -> void:
	var ark: Node3D = null
	for v: Variant in views.values():
		var bv := v as BuildingView
		if bv and bv.def_id == "ark_core":
			ark = bv.get("_visual") as Node3D  # the model flies; its pad and label wait on the ground
			break
	var action := str(AppFlow.params.get("action", ""))
	if ark == null or not PlanetDescent.wanted() or AppFlow.test_mode or ((DebugCapture.requested() or PerfProbe.requested()) and not action.begins_with("descent")):
		hud.toast(Loc.t("The Ark has landed. Build power, water and a habitat. Tap a building below."), "info", 10.0)
		return
	GameSession.colony_clock_active = false
	var d := PlanetDescent.new()
	d.name = "Descent"
	d.nose_yaw = -PI * 0.5  # the landed Ark model is long in X
	add_child(d)
	d.start(self, terrain, planet, ark.global_position, ark, float(action.get_slice(":", 1)) if action.contains(":") else PlanetDescent.START_ALT)
	d.finished.connect(func() -> void:
		GameSession.colony_clock_active = true
		cam_rig.make_current()
		hud.toast(Loc.t("The Ark has landed. Build power, water and a habitat. Tap a building below."), "info", 10.0))

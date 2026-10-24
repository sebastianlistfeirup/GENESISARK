extends Control
## Epilogue (bible p.12, GA-25): the profile follows actual robustness and the
## council; text references planet, crises, people and institutions.
## Cinematic layout (D-059): over the world they made home, a chapter kicker
## (EPILOGUE · planet · year), the ending's title large in the display face,
## the summary, stat medallions (people, years, crises resolved, reserve days;
## laurel crest, the number counting up, the word under it), the epilogue in
## readable columns (two on wide screens), the facts line and the actions.
## The chapter fades in block by block (all at once with reduced motion).

func _ready() -> void:
	theme = UiKit.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	AudioService.set_ambience("")
	var bg := ColorRect.new()
	bg.color = UiKit.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	if not GameSession.has_game() or GameSession.state.colony == null:
		DebugFixtures.prepare("era:pelagos:40")  # developer path: opened without a campaign
	if GameSession.state.campaign.ending_id.is_empty():
		GameSession.cmd_handover()  # e.g. --scene=ending --setup=era:<planet>:40 shows that planet's ending
	var gs: GameState = GameSession.state
	_backdrop(gs)
	var def: Dictionary = GameSession.content.endings.get(gs.campaign.ending_id, {})
	AudioService.set_music_any(["music_ending_" + gs.campaign.ending_id, "music_hope"])
	# Text scrolls, the buttons stay on screen: nothing is cut off at 1280x720
	# with a large UI scale (bible p.26).
	var vis := get_viewport().get_visible_rect().size
	var frame := MarginContainer.new()
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.add_theme_constant_override("margin_left", 140 if vis.x >= 1500.0 else 72)
	# The text column keeps clear of the planet on the right at every size and
	# UI scale (at 1280x720 @1.5 it used to run across the bright limb).
	frame.add_theme_constant_override("margin_right", int(maxf(60.0, vis.x * 0.3)))
	frame.add_theme_constant_override("margin_top", 70)
	frame.add_theme_constant_override("margin_bottom", 36)
	add_child(frame)
	var outer := UiKit.vbox(14)
	frame.add_child(outer)
	var m: Dictionary = gs.campaign.final_state
	var p := GameSession.content.planet(gs.colony.planet_id if gs.colony else gs.campaign.selected_planet_id)
	# Chapter kicker + title + summary.
	var kick := UiKit.hbox(10)
	kick.add_child(IconBadge.make("ui.icon_trophy", 34, UiKit.AMBER, true, "★"))
	var kt := UiKit.label("%s  ·  %s  ·  %s" % [Loc.t("EPILOGUE"), str(p.get("name", "")).to_upper(), (Loc.t("Year %d") % int(float(m.get("years", gs.campaign.colony_year())))).to_upper()], 15, UiKit.AMBER)
	kt.add_theme_font_override("font", UiKit.display_variant(4))
	kick.add_child(kt)
	var rule := UiKit.trim(Color(UiKit.AMBER, 0.6))
	rule.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rule.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	kick.add_child(rule)
	outer.add_child(kick)
	var head := UiKit.label(str(def.get("title", gs.campaign.ending_id)).to_upper(), 50 if vis.x >= 1500.0 else 38, Color.WHITE, true)
	head.add_theme_font_override("font", Holo.name_font())
	head.add_theme_color_override("font_shadow_color", Color(UiKit.AMBER, 0.35))
	head.add_theme_constant_override("shadow_outline_size", 18)
	head.add_theme_constant_override("shadow_offset_x", 0)
	head.add_theme_constant_override("shadow_offset_y", 0)
	outer.add_child(head)
	outer.add_child(UiKit.label(GameSession.sim.endings.summary(gs), 20, UiKit.AMBER.lightened(0.15), true))
	# Stat medallions.
	var medals := HFlowContainer.new()
	medals.add_theme_constant_override("h_separation", 22)
	medals.add_theme_constant_override("v_separation", 8)
	var rd := float(m.get("reserve_days", 0))
	medals.add_child(_medal("ui.icon_population", int(m.get("population", 0)), Loc.t("People"), UiKit.FOOD))
	medals.add_child(_medal("ui.icon_time", int(float(m.get("years", 0.0))), Loc.t("Years"), UiKit.AMBER))
	medals.add_child(_medal("ui.icon_critical", int(m.get("crises_resolved", 0)), Loc.t("Crises resolved"), UiKit.DANGER.lightened(0.2)))
	medals.add_child(_medal("ui.icon_reserve", -1 if rd >= 9999 else int(rd), Loc.t("Reserve days"), UiKit.WATER))
	var council := bool(m.get("council", false))
	var side := UiKit.vbox(6)
	side.alignment = BoxContainer.ALIGNMENT_CENTER
	side.add_child(Holo.chip(Loc.t("council") if council else Loc.t("no council"), UiKit.OK if council else UiKit.MUTED, "ui.icon_council", 13))
	side.add_child(Holo.chip(Loc.t("own power %.0f / %.0f kW") % [float(m.get("own_power_kw", 0)), float(m.get("demand_kw", 0))], UiKit.PETROL.lightened(0.35), "ui.icon_power", 13))
	side.add_child(Holo.chip(Loc.t("captain in stasis %d yrs") % int(gs.campaign.captain_stasis_years), UiKit.PETROL.lightened(0.35), "ui.icon_ship", 13))
	medals.add_child(side)
	outer.add_child(medals)
	# The epilogue in readable columns (two on wide screens), scrolling.
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# A faint glass sheet behind the text keeps it readable where it meets the bright limb.
	var sheet := PanelContainer.new()
	# It fades out downwards, so a short epilogue leaves no empty box.
	var sg := Gradient.new()
	sg.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	sg.colors = PackedColorArray([Color(0.0, 0.01, 0.03, 0.55), Color(0.0, 0.01, 0.03, 0.45), Color(0.0, 0.01, 0.03, 0.0)])
	var sgt := GradientTexture2D.new()
	sgt.gradient = sg
	sgt.fill_from = Vector2(0, 0)
	sgt.fill_to = Vector2(0, 1)
	sgt.width = 4
	sgt.height = 64
	var ssb := StyleBoxTexture.new()
	ssb.texture = sgt
	ssb.content_margin_left = 16
	ssb.content_margin_right = 18
	ssb.content_margin_top = 12
	ssb.content_margin_bottom = 12
	sheet.add_theme_stylebox_override("panel", ssb)
	sheet.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sheet.add_child(scroll)
	outer.add_child(sheet)
	var paras: Array = GameSession.sim.endings.epilogue(gs)
	var cols_n := 2 if vis.x >= 1500.0 and paras.size() > 1 else 1
	var cols := UiKit.hbox(34)
	cols.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(cols)
	var per := ceili(float(paras.size()) / cols_n)
	for ci: int in cols_n:
		var col := UiKit.vbox(14)
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		for para: String in paras.slice(ci * per, (ci + 1) * per):
			var l := UiKit.label(para, 18, UiKit.TEXT, true)
			l.add_theme_constant_override("line_spacing", 4)
			col.add_child(l)
		cols.add_child(col)
	var facts := UiKit.label(Loc.t("%d people · %s · own power %.0f / %.0f kW · reserve %s days · %d crises resolved · the captain in stasis for %d years") % [
		int(m.get("population", 0)), Loc.t("council") if m.get("council", false) else Loc.t("no council"), float(m.get("own_power_kw", 0)), float(m.get("demand_kw", 0)),
		"∞" if float(m.get("reserve_days", 0)) >= 9999 else str(int(float(m.get("reserve_days", 0)))), int(m.get("crises_resolved", 0)), int(gs.campaign.captain_stasis_years)], 13, UiKit.MUTED, true)
	outer.add_child(facts)
	var row := UiKit.hbox(12)
	var mm := GlowButton.make(Loc.t("Main menu"), "ui.icon_menu", "primary", func() -> void: AppFlow.goto("menu"))
	mm.custom_minimum_size = Vector2(280, 50)
	mm.set_filled()
	row.add_child(mm)
	var pre := UiKit.button(Loc.t("Continue from the last save before the handover"), func() -> void:
		var r := GameSession.load_from("auto", true)
		if r["ok"]:
			AppFlow.continue_game())
	pre.tooltip_text = Loc.t("Loading the backup from before the ending.")
	UiKit.with_icon(pre, "ui.icon_load", 18)
	pre.custom_minimum_size = Vector2(0, 50)
	row.add_child(pre)
	outer.add_child(row)
	mm.grab_focus.call_deferred()
	HoloAnim.stagger(outer, 0.12, 0.3, 0.6)


## A stat medallion: laurel crest behind a ring, the number counting up in
## the display face, its word under it. value -1 shows ∞.
func _medal(icon_slot: String, value: int, caption: String, col: Color) -> Control:
	var v := UiKit.vbox(2)
	var box := Control.new()
	box.custom_minimum_size = Vector2(112, 104)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var wreath := UiKit.icon_rect("crest.wreath", 104, Color(col.lightened(0.2), 0.55))
	if wreath:
		wreath.set_anchors_preset(Control.PRESET_FULL_RECT)
		box.add_child(wreath)
	var ring := HoloRing.new()
	ring.set_anchors_preset(Control.PRESET_FULL_RECT)
	ring.add_layer("Ring_Small_06", 0.74, 0.15, Color(col, 0.6), 10)
	box.add_child(ring)
	var n: Label
	if value < 0:
		n = Holo.value_label("∞", 30, Color.WHITE)
	else:
		n = CountUpLabel.make(value, 30 if value < 1000 else 24, Color.WHITE)
		(n as CountUpLabel).seconds = 1.6
	n.add_theme_font_override("font", UiKit.display_font())
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	n.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	n.set_anchors_preset(Control.PRESET_FULL_RECT)
	n.add_theme_color_override("font_shadow_color", Color(col, 0.6))
	n.add_theme_constant_override("shadow_outline_size", 8)
	box.add_child(n)
	var ic := UiKit.icon_rect(icon_slot, 16, col.lightened(0.3))
	if ic:
		ic.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
		ic.offset_top = 14
		ic.grow_horizontal = Control.GROW_DIRECTION_BOTH
		box.add_child(ic)
	v.add_child(box)
	var c := UiKit.label(caption.to_upper(), 12, col.lightened(0.35))
	c.add_theme_font_override("font", UiKit.display_variant(2))
	c.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(c)
	return v


var _world: Node3D
var _cam: Camera3D
var _t := 0.0


## The world they made home, seen from orbit: the colony's lights on the night
## side, the Ark drifting past, the painted nebula. Text stays legible on a
## navy gradient from the left. Static with reduced motion.
func _backdrop(gs: GameState) -> void:
	var svc := SubViewportContainer.new()
	svc.stretch = true
	svc.set_anchors_preset(Control.PRESET_FULL_RECT)
	svc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(svc)
	var sv := SubViewport.new()
	sv.own_world_3d = true
	sv.msaa_3d = Viewport.MSAA_4X
	svc.add_child(sv)
	_world = Node3D.new()
	sv.add_child(_world)
	var back := SpaceBackdrop.new()
	back.seed_value = 23
	_world.add_child(back)
	var pid := gs.colony.planet_id if gs.colony else "viridia"
	var p := GameSession.content.planet(pid)
	var biome := str(p.get("biome_id", "green"))
	var tint := str(DictUtil.get_dict(p, "palette").get("nature", ""))
	var planet := VisualSlot.make("space.planet_" + biome, tint)
	planet.position = Vector3(95, -10, -175)
	planet.scale = Vector3.ONE * 1.0
	_world.add_child(planet)
	PlanetLook.apply(planet, biome, tint, hash(pid), pid)
	planet.rebuilt.connect(func() -> void: _lights_on(planet), CONNECT_ONE_SHOT)
	_lights_on(planet)
	var ark := VisualSlot.make("space.ark_exterior")
	ark.position = Vector3(44, 10, -62)
	ark.rotation_degrees = Vector3(4, -70, -6)
	ark.name = "Ark"
	_world.add_child(ark)
	_cam = Camera3D.new()
	_cam.position = Vector3(0, 2, 0)
	_cam.fov = 50
	_world.add_child(_cam)
	_cam.look_at(Vector3(22, 0, -100))
	_cam.current = true
	var shade := TextureRect.new()
	var g := Gradient.new()
	g.set_color(0, Color(UiKit.BG, 0.94))
	g.set_color(1, Color(UiKit.BG, 0.0))
	g.add_point(0.5, Color(UiKit.BG, 0.84))
	g.add_point(0.7, Color(UiKit.BG, 0.5))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_to = Vector2(1, 0)
	shade.texture = gt
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)


func _lights_on(planet: VisualSlot) -> void:
	# The world fills the right half here: a moon would sit behind the text column.
	for moon: Node in planet.find_children("Moon*", "", true, false):
		(moon as Node3D).visible = false
	for mi: Node in planet.find_children("*", "MeshInstance3D", true, false):
		if not mi.has_meta("planet_body"):
			continue  # moons, halo and ring keep their look
		var m := (mi as MeshInstance3D).material_override as ShaderMaterial
		if m:
			m.set_shader_parameter("city_lights", 1.0)
			m.set_shader_parameter("sun_dir", Vector3(-0.58, 0.42, 0.69))  # towards the backdrop key light
			m.set_shader_parameter("settlement", Vector3(0.95, 0.1, 0.3))  # on the night limb, facing the camera


func _process(delta: float) -> void:
	if _world == null or FxEffect.reduced_motion():
		return
	_t += delta
	var ark := _world.get_node_or_null("Ark") as Node3D
	if ark:
		ark.position.x = 44.0 - _t * 0.25
	if _cam:
		_cam.rotation.y += delta * 0.002

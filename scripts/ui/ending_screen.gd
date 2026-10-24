extends Control
## Epilogue (bible p.12, GA-25): the profile follows actual robustness and the
## council; text references planet, crises, people and institutions.

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
	frame.add_theme_constant_override("margin_left", 160)
	# The text column keeps clear of the planet on the right at every size and
	# UI scale (at 1280x720 @1.5 it used to run across the bright limb).
	frame.add_theme_constant_override("margin_right", int(maxf(60.0, vis.x * 0.3)))
	frame.add_theme_constant_override("margin_top", 90)
	frame.add_theme_constant_override("margin_bottom", 40)
	add_child(frame)
	var outer := UiKit.vbox(16)
	frame.add_child(outer)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(scroll)
	var col := UiKit.vbox(16)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(col)
	col.add_child(UiKit.label(Loc.t("EPILOGUE"), 18, UiKit.PETROL.lightened(0.3)))
	col.add_child(UiKit.label(str(def.get("title", gs.campaign.ending_id)), 54, UiKit.TEXT))
	col.add_child(UiKit.label(GameSession.sim.endings.summary(gs), 20, UiKit.AMBER, true))
	for para: String in GameSession.sim.endings.epilogue(gs):
		col.add_child(UiKit.label(para, 19, UiKit.TEXT, true))
	var m: Dictionary = gs.campaign.final_state
	col.add_child(UiKit.label(Loc.t("%d people · %s · own power %.0f / %.0f kW · reserve %s days · %d crises resolved · the captain in stasis for %d years") % [
		int(m.get("population", 0)), Loc.t("council") if m.get("council", false) else Loc.t("no council"), float(m.get("own_power_kw", 0)), float(m.get("demand_kw", 0)),
		"∞" if float(m.get("reserve_days", 0)) >= 9999 else str(int(float(m.get("reserve_days", 0)))), int(m.get("crises_resolved", 0)), int(gs.campaign.captain_stasis_years)], 15, UiKit.MUTED, true))
	var row := UiKit.hbox(12)
	row.add_child(UiKit.button(Loc.t("Main menu"), func() -> void: AppFlow.goto("menu")))
	var pre := UiKit.button(Loc.t("Continue from the last save before the handover"), func() -> void:
		var r := GameSession.load_from("auto", true)
		if r["ok"]:
			AppFlow.continue_game())
	pre.tooltip_text = Loc.t("Loading the backup from before the ending.")
	row.add_child(pre)
	outer.add_child(row)


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
	PlanetLook.apply(planet, biome, tint, hash(pid))
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
	for mi: Node in planet.find_children("*", "MeshInstance3D", true, false):
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

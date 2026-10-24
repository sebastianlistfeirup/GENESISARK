extends Node3D
## Main menu over a slow cinematic shot: the ark drifting past a candidate world
## against the star field and a faint nebula. With "reduced motion" the camera,
## ark and UI stay still and nothing fades (D-035).

const ARK_BASE := Vector3(19.0, 5.0, -40.0)
const CAM_BASE := Vector3(-10.0, 4.0, 50.0)
const CAM_TARGET := Vector3(2.0, -2.0, -20.0)

var _ark: Node3D
var _planet: Node3D
var _cam: Camera3D
var _settings: SettingsPanel
var _credits: CreditsPanel
var _col: VBoxContainer
var _body: VBoxContainer
var _ui: Control
var _t := 0.0
var _focus_sound_armed := false
var _rings: Array[TextureRect] = []  # slow-turning HUD rings behind the title (still with reduced motion)
var _save_card: Control
var _footer: HBoxContainer


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	AudioService.set_ambience("amb_space")
	AudioService.set_music("music_hope")
	_build_world()
	_build_ui()
	_settings = SettingsPanel.new()
	_settings.closed.connect(_on_panel_closed)
	add_child(_settings)
	_credits = CreditsPanel.new()
	_credits.closed.connect(_on_panel_closed)
	add_child(_credits)
	_build()
	_apply_pose(0.0)
	if not UiKit.calm():
		UiKit.fade_in(_ui, 1.2)


func _build_world() -> void:
	var backdrop := SpaceBackdrop.new()
	add_child(backdrop)
	# Grade the shared backdrop for a cinematic key: low ambient, strong rim sun.
	# The painted nebula of the flight shows here too (D-046; the menu used to
	# hide it behind its own dark sphere, and turned the violet fill into a
	# second sun).
	var e := backdrop.environment
	e.ambient_light_energy = 0.45
	e.glow_intensity = 1.0
	e.glow_bloom = 0.16
	e.adjustment_enabled = true
	e.adjustment_contrast = 1.08
	e.adjustment_saturation = 1.1
	backdrop.set_sun(Vector3(-18, -118, 0), 1.9)
	backdrop.sky_material.set_shader_parameter("veil_strength", 0.85)
	_planet = Node3D.new()
	_planet.position = Vector3(112, -96, -215)
	var planet_slot := VisualSlot.make("space.planet_green", "#4f8a3a")
	_planet.add_child(planet_slot)
	PlanetLook.apply(planet_slot, "green", "#4f8a3a", 11, "viridia")
	add_child(_planet)
	_ark = Node3D.new()
	var ark_slot := VisualSlot.make("space.ark_exterior")
	_ark.add_child(ark_slot)
	add_child(_ark)
	# Lit window strips and glowing nozzles, as in the approach flight (D-044).
	if ark_slot.using_asset:
		var sc: Variant = DictUtil.load_json(SpaceScenery.PATH)
		SpaceFx.dress_ark(ark_slot, DictUtil.get_dict(sc, "ark_fx") if sc is Dictionary else {})
	_cam = Camera3D.new()
	_cam.fov = 46
	add_child(_cam)


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_ui = Control.new()
	_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.theme = UiKit.theme()
	layer.add_child(_ui)
	# Readability: a navy wash from the left edge and a soft floor, so the
	# column stays legible over any art the ark slot brings.
	_ui.add_child(_wash(Vector2(0, 0.5), Vector2(1, 0.5), 0.86, Control.PRESET_LEFT_WIDE, Vector2(820, 0)))
	_ui.add_child(_wash(Vector2(0.5, 1), Vector2(0.5, 0), 0.7, Control.PRESET_BOTTOM_WIDE, Vector2(0, 220)))
	_ui.add_child(_wash(Vector2(0.5, 0), Vector2(0.5, 1), 0.5, Control.PRESET_TOP_WIDE, Vector2(0, 120)))
	_add_rings()
	# One column, centred vertically: title, menu and tagline never overlap at any UI scale.
	_col = UiKit.vbox(0)
	_col.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	_col.offset_left = 110
	_col.alignment = BoxContainer.ALIGNMENT_CENTER
	_ui.add_child(_col)
	# Logo: the display face, wide tracking, a petrol glow under a dark drop.
	var title := UiKit.label("GENESIS ARK", 88, UiKit.TEXT)
	title.add_theme_font_override("font", UiKit.display_variant(10))
	title.add_theme_color_override("font_shadow_color", Color(UiKit.PETROL, 0.35))
	title.add_theme_constant_override("shadow_offset_x", 0)
	title.add_theme_constant_override("shadow_offset_y", 0)
	title.add_theme_constant_override("shadow_outline_size", 22)
	title.add_theme_color_override("font_outline_color", Color(0, 0.02, 0.05, 0.6))
	title.add_theme_constant_override("outline_size", 4)
	_col.add_child(title)
	var rule := UiKit.hbox(8)
	rule.add_child(_rule(UiKit.AMBER, 72))
	rule.add_child(_rule(UiKit.PETROL, 180))
	var tr := UiKit.trim(Color(UiKit.PETROL.lightened(0.3), 0.7))
	tr.custom_minimum_size = Vector2(300, 9)
	tr.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rule.add_child(tr)
	_col.add_child(rule)
	_col.add_child(_gap(16))
	_col.add_child(UiKit.label(Loc.t("You are the last human who can give humanity a future."), 22, UiKit.MUTED.lightened(0.15)))
	_col.add_child(_gap(36))
	_body = UiKit.vbox(8)
	_body.custom_minimum_size = Vector2(380, 0)
	_body.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_col.add_child(_body)
	_col.add_child(_gap(30))
	_col.add_child(UiKit.label(Loc.t("50,000 embryos. Six possible worlds. One choice you must live with."), 16, UiKit.AMBER))
	var ver := UiKit.label(Loc.t("v%s · Godot %s") % [ProjectSettings.get_setting("application/config/version"), Engine.get_version_info().get("string")], 13, UiKit.MUTED)
	ver.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	ver.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	ver.grow_vertical = Control.GROW_DIRECTION_BEGIN
	ver.offset_right = -28
	ver.offset_bottom = -20
	_ui.add_child(ver)
	_footer = UiKit.hbox(8)
	_footer.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_footer.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_footer.offset_left = 110
	_footer.offset_bottom = -22
	_footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_footer)
	_build_footer()
	SettingsService.changed.connect(_build_footer)


## Key hints at the bottom (Mass Effect style): key caps on keyboard, the real
## face buttons on a controller. Read-only: the keys work anyway.
func _build_footer() -> void:
	if not is_instance_valid(_footer):
		return
	UiKit.clear(_footer)
	for hint: Array in [["ui_accept", "btn:0", "Enter", Loc.t("Select")], ["ui_cancel", "btn:1", "Esc", Loc.t("Back")]]:
		var glyph := SyntySkin.pad_glyph(str(hint[1])) if SettingsService.using_pad else null
		if glyph:
			var r := TextureRect.new()
			r.texture = glyph
			r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			r.custom_minimum_size = Vector2(24, 24)
			_footer.add_child(r)
		else:
			_footer.add_child(UiKit.keycap(str(hint[2]), 14))
		_footer.add_child(UiKit.label(str(hint[3]), 15, UiKit.MUTED.lightened(0.1)))
		var sp := Control.new()
		sp.custom_minimum_size = Vector2(14, 0)
		_footer.add_child(sp)


## Thin Synty HUD rings around the logo, turning slowly in opposite directions
## (No Man's Sky style); still with reduced motion. Absent without the packs.
func _add_rings() -> void:
	for spec: Array in [["Ring_Large_03", 820.0, 0.11], ["Ring_Medium_07", 580.0, 0.16], ["Ring_Small_06", 380.0, 0.12]]:
		var tex := SyntySkin.texture(SyntySkin.GENERAL + str(spec[0]) + ".png", 1024)
		if tex == null:
			return
		var r := TextureRect.new()
		r.texture = tex
		r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		var d: float = spec[1]
		r.modulate = Color(UiKit.PETROL.lightened(0.35), spec[2])
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_ui.add_child(r)
		# Centred on the logo's left half (logical 1920x1080 space).
		var c := Vector2(420, 330)
		r.set_anchors_preset(Control.PRESET_TOP_LEFT)
		r.offset_left = c.x - d * 0.5
		r.offset_top = c.y - d * 0.5
		r.offset_right = c.x + d * 0.5
		r.offset_bottom = c.y + d * 0.5
		r.pivot_offset = Vector2(d, d) * 0.5
		_rings.append(r)


## The newest save as a holo card bottom right (D-059: the SaveSlots card):
## where Continue will take you; clicking it continues.
func _refresh_save_card() -> void:
	if is_instance_valid(_save_card):
		_save_card.queue_free()
	_save_card = null
	if not SaveService.has_any():
		return
	var slot := SaveService.latest_slot()
	var card := SaveSlots.card(slot, SaveService.summary(slot), "load", func(_s: String) -> void: _continue())
	card.custom_minimum_size = Vector2(520, 0)
	card.focus_mode = Control.FOCUS_NONE  # the Continue entry owns keyboard / pad focus
	var box := UiKit.vbox(6)
	box.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	box.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	box.offset_right = -28
	box.offset_bottom = -52
	# The caption sits on a dark pill: over the planet's bright limb it used to wash out.
	var pill := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(UiKit.BG, 0.82)
	sb.border_color = Color(UiKit.AMBER, 0.35)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(12)
	sb.content_margin_left = 12
	sb.content_margin_right = 16
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	pill.add_theme_stylebox_override("panel", sb)
	pill.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.add_child(UiKit.section(Loc.t("Continue"), "ui.icon_load"))
	box.add_child(pill)
	box.add_child(card)
	_save_card = box
	_ui.add_child(box)


func _wash(from: Vector2, to: Vector2, alpha: float, preset: Control.LayoutPreset, size: Vector2) -> TextureRect:
	var g := Gradient.new()
	g.set_color(0, Color(UiKit.BG, alpha))
	g.set_color(1, Color(UiKit.BG, 0.0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = from
	gt.fill_to = to
	gt.width = 64
	gt.height = 64
	var r := TextureRect.new()
	r.texture = gt
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.set_anchors_and_offsets_preset(preset)
	if size.x > 0.0:
		r.offset_right = r.offset_left + size.x
	if size.y > 0.0:
		if preset == Control.PRESET_BOTTOM_WIDE:
			r.offset_top = -size.y
		else:
			r.offset_bottom = size.y
	return r


func _rule(c: Color, w: float) -> ColorRect:
	var r := ColorRect.new()
	r.color = c
	r.custom_minimum_size = Vector2(w, 3)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


func _gap(h: float) -> Control:
	var sp := Control.new()
	sp.custom_minimum_size = Vector2(0, h)
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return sp


func _menu_button(text: String, cb: Callable, icon_slot: String = "") -> Button:
	var b := UiKit.button(text.to_upper(), cb)
	if not icon_slot.is_empty():
		UiKit.with_icon(b, icon_slot, 22)
	UiKit.style_menu_button(b, not UiKit.calm())
	b.focus_entered.connect(func() -> void:
		if _focus_sound_armed and SettingsService.using_pad:
			AudioService.ui("ui_hover"))
	return b


func _build() -> void:
	_focus_sound_armed = false
	UiKit.clear(_body)
	var first: Button
	if SaveService.has_any():
		first = _menu_button(Loc.t("Continue"), _continue, "ui.icon_play")
		_body.add_child(first)
	var nb := _menu_button(Loc.t("New campaign"), _new, "ui.icon_new")
	_body.add_child(nb)
	if first == null:
		first = nb
	if SaveService.has_any():
		_body.add_child(_menu_button(Loc.t("Load"), _load_list, "ui.icon_load"))
	_body.add_child(_menu_button(Loc.t("Settings"), func() -> void: _open_panel(_settings), "ui.icon_settings"))
	_body.add_child(_menu_button(Loc.t("Credits"), func() -> void: _open_panel(_credits), "ui.icon_credits"))
	if OS.get_name() != "Web":
		_body.add_child(_menu_button(Loc.t("Quit"), func() -> void: get_tree().quit(), "ui.icon_quit"))
	_stagger()
	_refresh_save_card()
	first.grab_focus.call_deferred()
	set_deferred("_focus_sound_armed", true)


## Entries fade in one after another (skipped with reduced motion).
func _stagger() -> void:
	if UiKit.calm():
		return
	var i := 0
	for c: Node in _body.get_children():
		var ci := c as CanvasItem
		ci.modulate.a = 0.0
		var tw := ci.create_tween()
		tw.tween_interval(0.05 * i)
		tw.tween_property(ci, "modulate:a", 1.0, 0.22).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		i += 1


func _open_panel(p: CanvasLayer) -> void:
	_col.visible = false
	for r: TextureRect in _rings:
		r.visible = false
	if is_instance_valid(_save_card):
		_save_card.visible = false
	p.call("open")


func _on_panel_closed() -> void:
	_show_column()
	_build()


func _show_column() -> void:
	_col.visible = true
	for r: TextureRect in _rings:
		r.visible = true
	if not UiKit.calm():
		UiKit.fade_in(_col, 0.25)


func _new() -> void:
	GameSession.new_campaign()
	AppFlow.goto("ship")


func _continue() -> void:
	var slot := SaveService.latest_slot()
	_try_load(slot, false)


## The saves as holo cards in an overlay (D-059): world render, place, day,
## people, embryos and date per slot; Esc / Back returns to the menu.
func _load_list() -> void:
	if _saves == null:
		_saves = OverlayPanel.new(Vector2(820, 0))
		_saves.closed.connect(_on_panel_closed)
		add_child(_saves)
	UiKit.clear(_saves.body)
	_saves.header(Loc.t("Load game"), Loc.t("Autosave, manual slots and the save from before the landing."), "ui.icon_load")
	var cards := SaveSlots.list("load", SaveService.SLOTS, func(slot: String) -> void:
		_saves.visible = false
		_show_column()
		_try_load(slot, false))
	_saves.body.add_child(cards)
	_open_panel(_saves)
	var first: Control = cards.get_child(0) as Control if cards.get_child_count() > 0 else _saves.focus_target()
	if first:
		first.grab_focus.call_deferred()


var _saves: OverlayPanel


func _try_load(slot: String, backup: bool) -> void:
	var r := GameSession.load_from(slot, backup)
	if r["ok"]:
		AppFlow.continue_game()
		return
	UiKit.clear(_body)
	_body.add_child(UiKit.label(Loc.t("Could not load: ") + str(r["error"]), 17, UiKit.WARN, true))
	if r["backup_available"] and not backup:
		_body.add_child(_menu_button(Loc.t("Load latest valid backup"), func() -> void: _try_load(slot, true), "ui.icon_load"))
	var back := _menu_button(Loc.t("Back"), _build, "ui.icon_back")
	_body.add_child(back)
	back.grab_focus.call_deferred()


func _process(delta: float) -> void:
	if UiKit.calm():
		return
	_t += delta
	_apply_pose(_t)
	for i: int in _rings.size():
		_rings[i].rotation = _t * (0.012 if i % 2 == 0 else -0.02) * (1.0 + i * 0.4)


## One pose per time value: slow camera drift (a lazy figure-eight around the
## base framing) and the ark gliding past the planet. t = 0 is the still frame
## used when reduced motion is on.
func _apply_pose(t: float) -> void:
	_ark.position = ARK_BASE + Vector3(sin(t * 0.021) * 7.0, sin(t * 0.37) * 0.35, cos(t * 0.017) * 3.0)
	_ark.rotation_degrees = Vector3(7.0 + sin(t * 0.23) * 0.6, 32.0 + sin(t * 0.021) * 6.0, -5.0 + sin(t * 0.19) * 0.8)
	_planet.rotation.y = t * 0.004
	_cam.position = CAM_BASE + Vector3(sin(t * 0.05) * 2.4, sin(t * 0.083) * 0.9, cos(t * 0.041) * 1.6)
	_cam.look_at(CAM_TARGET + Vector3(sin(t * 0.03) * 0.8, 0.0, 0.0))


## Evidence captures only (DebugCapture --action=credits|settings|still).
func debug_action(action: String) -> void:
	match action:
		"credits": _open_panel(_credits)
		"settings": _open_panel(_settings)
		"settings_display", "settings_access", "settings_controls":
			_open_panel(_settings)
			_settings.show_tab({"settings_display": 1, "settings_access": 2, "settings_controls": 3}[action])
		"load": _load_list()
		"new":  # the real New campaign path, with the wake-up a capture normally skips
			GameSession.new_campaign()
			AppFlow.goto("ship", {"action": "wakeup"})
		"continue": _continue()
		"focus2":
			if _body.get_child_count() > 1:
				(_body.get_child(1) as Control).grab_focus()
		"drift":
			_t = 60.0
			_apply_pose(_t)

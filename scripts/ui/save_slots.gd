class_name SaveSlots
extends RefCounted
## Save slots as holo cards (D-059), shared by the main menu and the pause menu:
##   [world]  SLOT 1 · COLONY                       2026-10-24 18:34
##            VIRIDIA
##            [day] Colony day 64 · year 0.2   [pop] 12   [dna] 49,990
## The world is the save's planet as a still 3D render (the Ark's glyph on the
## voyage); empty slots are dashed "new save" cards in save mode. Saving over
## a used slot asks first: the card turns red, a second press overwrites.
## Read-only: the summary comes from SaveService (no state is touched).
##   SaveSlots.list("save", SaveService.SLOTS_MANUAL, func(slot) -> void: ...)

const MANUAL := ["manual_1", "manual_2", "manual_3"]


## A column of cards for `slots`. mode "load": only used slots; mode "save":
## every slot, empty ones dashed. `on_pick(slot)` fires on the (confirmed) press.
static func list(mode: String, slots: Array, on_pick: Callable) -> VBoxContainer:
	var v := UiKit.vbox(10)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for slot: String in slots:
		var sm := SaveService.summary(slot)
		if sm.is_empty():
			if mode == "load":
				continue
			v.add_child(empty_card(slot, on_pick))
		else:
			v.add_child(card(slot, sm, mode, on_pick))
	return v


static func slot_name(slot: String) -> String:
	return Loc.t(str(SaveService.SLOT_LABELS.get(slot, slot)))


## Where the save stands: the world's name (or the voyage point) and its planet id.
static func place(sm: Dictionary) -> Array:
	var content: ContentDB = GameSession.content
	var loc := str(sm.get("location", ""))
	var pid := str(sm.get("planet", ""))
	var phase := str(sm.get("phase", ""))
	if phase in ["SETTLED", "ENDED"] and not pid.is_empty():
		return [str(content.planet(pid).get("name", pid)), pid]
	var ld: Dictionary = content.locations.get(loc, {})
	var lp := str(ld.get("planet_id", ""))
	return [str(ld.get("name", loc if not loc.is_empty() else Loc.t("Voyage"))), lp]


static func card(slot: String, sm: Dictionary, mode: String, on_pick: Callable) -> HoloCard:
	var phase := str(sm.get("phase", ""))
	var colony := phase in ["SETTLED", "ENDED"]
	var accent := UiKit.FOOD if colony else UiKit.PETROL.lightened(0.25)
	var c := HoloCard.make(accent, Callable(), "", Vector4(16, 12, 18, 12))
	c.custom_minimum_size = Vector2(560, 0)
	var h := UiKit.hbox(16)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pl := place(sm)
	h.add_child(_world(str(pl[1]), accent))
	var info := UiKit.vbox(2)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var top := UiKit.hbox(6)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(Holo.chip(slot_name(slot), UiKit.AMBER, "ui.icon_save" if slot.begins_with("manual") else ("ui.icon_time" if slot == "auto" else "ui.icon_lander"), 11))
	top.add_child(Holo.chip(Loc.t("Colony") if colony else Loc.t("Voyage"), accent, "ui.icon_home" if colony else "ui.icon_ship", 11))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(sp)
	var date := UiKit.label(str(sm.get("saved_at", "")).replace("T", "  ").substr(0, 17), 14, UiKit.MUTED)
	date.add_theme_font_override("font", UiKit.display_variant(1))
	top.add_child(date)
	info.add_child(top)
	var title := UiKit.label(str(pl[0]).to_upper(), 22, Color.WHITE)
	title.add_theme_font_override("font", Holo.name_font())
	title.clip_text = true
	info.add_child(title)
	var stats := UiKit.hbox(18)
	stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if colony:
		var day := int(sm.get("colony_day", 0))
		stats.add_child(_stat("ui.icon_time", Loc.t("Colony day %d") % day + " · " + Loc.t("year %.1f") % (day / 365.0)))
		stats.add_child(_stat("ui.icon_population", Loc.t("%d people") % int(sm.get("population", 0))))
	else:
		stats.add_child(_stat("ui.icon_time", Loc.t("Day %d of the voyage") % int(sm.get("elapsed_days", 0))))
	if int(sm.get("embryos", -1)) >= 0:
		stats.add_child(_stat("ui.icon_embryo", Loc.t("%s embryos") % UiKit.thousands(int(sm.get("embryos", 0)))))
	info.add_child(stats)
	h.add_child(info)
	var act := IconBadge.make("ui.icon_save" if mode == "save" else "ui.icon_play", 34, accent, false, "▶")
	h.add_child(act)
	c.content.add_child(h)
	c.tooltip_text = (Loc.t("Save over %s") if mode == "save" else Loc.t("Load %s")) % slot_name(slot)
	if mode == "save":
		# Overwriting asks first: the first press arms the card, the second saves.
		var warn := UiKit.label(Loc.t("Press again to overwrite this save."), 14, UiKit.DANGER.lightened(0.35))
		warn.visible = false
		info.add_child(warn)
		c.pressed.connect(func() -> void:
			if c.armed:
				on_pick.call(slot)
				return
			c.arm(true)
			warn.visible = true
			act.set_icon("ui.icon_warning", UiKit.DANGER))
		var disarm := func() -> void:
			if c.armed:
				c.arm(false)
				warn.visible = false
				act.set_icon("ui.icon_save", accent)
		c.focus_exited.connect(disarm)
		c.mouse_exited.connect(func() -> void:
			if not c.has_focus():
				disarm.call())
	else:
		c.pressed.connect(func() -> void: on_pick.call(slot))
	return c


## An empty slot in save mode: a dashed card with a plus.
static func empty_card(slot: String, on_pick: Callable) -> HoloCard:
	var c := HoloCard.make(UiKit.PETROL.lightened(0.3), func() -> void: on_pick.call(slot), Loc.t("Save to %s") % slot_name(slot), Vector4(16, 12, 18, 12))
	c.dashed = true
	c._styles()
	c.custom_minimum_size = Vector2(560, 0)
	var h := UiKit.hbox(16)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var plus := IconBadge.make("ui.icon_plus", 58, UiKit.PETROL.lightened(0.3), false, "+")
	plus.custom_minimum_size = Vector2(84, 64)
	h.add_child(plus)
	var v := UiKit.vbox(2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(Holo.chip(slot_name(slot), UiKit.AMBER, "ui.icon_save", 11))
	var t := UiKit.label(Loc.t("New save").to_upper(), 20, UiKit.TEXT)
	t.add_theme_font_override("font", Holo.name_font())
	v.add_child(t)
	v.add_child(UiKit.label(Loc.t("Empty slot. Save the current game here."), 14, UiKit.MUTED))
	h.add_child(v)
	c.content.add_child(h)
	return c


static func _stat(icon_slot: String, text: String) -> HBoxContainer:
	var h := UiKit.hbox(6)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ic := UiKit.icon_rect(icon_slot, 16, UiKit.PETROL.lightened(0.45))
	if ic:
		h.add_child(ic)
	h.add_child(UiKit.label(text, 15, UiKit.TEXT.darkened(0.08)))
	return h


## The save's world: a still render of the planet inside a thin turning ring,
## or the Ark's glyph on the voyage.
static func _world(pid: String, accent: Color) -> Control:
	var box := Control.new()
	box.custom_minimum_size = Vector2(84, 84)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ring := HoloRing.new()
	ring.set_anchors_preset(Control.PRESET_FULL_RECT)
	ring.add_layer("Ring_Small_06", 1.0, 0.12, Color(accent.lightened(0.3), 0.35), 8)
	box.add_child(ring)
	# A paused tree (pause menu) does not finish a 3D render: show the planet glyph in its colour then.
	var paused := (Engine.get_main_loop() as SceneTree).paused
	if pid.is_empty() or paused:
		var col := accent if pid.is_empty() else Color(str(DictUtil.get_dict(GameSession.content.planet(pid), "palette").get("nature", "#7cc46a")))
		var b := IconBadge.make("ui.icon_ship" if pid.is_empty() else "ui.icon_planet", 54, col, false, "▲" if pid.is_empty() else "●")
		b.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		b.grow_horizontal = Control.GROW_DIRECTION_BOTH
		b.grow_vertical = Control.GROW_DIRECTION_BOTH
		box.add_child(b)
	else:
		var d := PlanetDiorama.make(pid, "icon", Vector2i(70, 70))
		d.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		d.grow_horizontal = Control.GROW_DIRECTION_BOTH
		d.grow_vertical = Control.GROW_DIRECTION_BOTH
		box.add_child(d)
	return box

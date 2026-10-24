class_name DecisionDialog
extends OverlayPanel
## Generational chapter decision (bible p.12: at year 20 the first generation
## challenges your priorities — expansion, safety or self-determination).
## Dramatic cards (D-059): a HoloBanner, then the three voices side by side,
## each a large card: a speaker medallion (their course's crest in turning
## rings, initials without the packs), name and course chip, their line as a
## big quote, the bio, the gains as green ▲ bullets and the price as amber ▼
## bullets, and a "Support …" strip. The card is the button: mouse, keys and
## pad pick it (left/right moves between the voices); Esc never dismisses.

const COURSE_COL := {"expansion": Color("e8a33d"), "safety": Color("4fa3d9"), "self_determination": Color("c9a0ff")}

var decision_id := ""
var _first: Control


func _init() -> void:
	super(Vector2(1180, 640))


func ask(id: String) -> void:
	decision_id = id
	open()


func focus_target() -> Control:
	return _first


func refresh() -> void:
	UiKit.clear(body)
	_first = null
	var gs: GameState = GameSession.state
	body.add_child(HoloBanner.make("ui.icon_council", Loc.t("Generation decision"), Loc.t("Year %d: the first generation speaks") % int(gs.campaign.colony_year()),
		Loc.t("Those born here have their own answers to what the colony should be. Your choice sets the colony's lasting course until the next decision: each has a gain and a price. No answer is the right one."), UiKit.AMBER, false,
		[["ui.icon_population", Loc.t("%d people") % gs.population.alive_count(), UiKit.FOOD]]))
	var lines := {"expansion": Loc.t("We have to move on. The valleys to the north could feed thousands."), "safety": Loc.t("We can't afford to lose anything. Reserves before everything else."),
		"self_determination": Loc.t("We want to decide for ourselves. Give the council the keys.")}
	var names := {"expansion": Loc.t("expansion"), "safety": Loc.t("safety"), "self_determination": Loc.t("self-determination")}
	var row := UiKit.hbox(12)
	for ch: Dictionary in GameSession.content.characters.values():
		var persp := str(ch.get("perspective", ""))
		if persp.is_empty():
			continue
		var col: Color = COURSE_COL.get(persp, UiKit.AMBER)
		var who := str(ch.get("name"))
		var card := HoloCard.make(col, func() -> void:
			if GameSession.cmd_choose_priority(decision_id, persp).ok:
				close(), "", Vector4(18, 14, 16, 14))
		card.custom_minimum_size = Vector2(360, 0)
		var v := card.content
		v.add_theme_constant_override("separation", 8)
		var head := UiKit.hbox(12)
		head.mouse_filter = Control.MOUSE_FILTER_IGNORE
		head.add_child(_medallion(persp, who, col))
		var hv := UiKit.vbox(4)
		hv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hv.alignment = BoxContainer.ALIGNMENT_CENTER
		hv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var nm := UiKit.heading(who, 21)
		nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hv.add_child(nm)
		hv.add_child(Holo.chip(str(names[persp]), col, "crest." + persp, 12))
		head.add_child(hv)
		v.add_child(head)
		var q := UiKit.label("“%s”" % lines.get(persp, ""), 18, col.lightened(0.55), true)
		q.add_theme_font_override("font", UiKit.bold_font())
		v.add_child(q)
		v.add_child(UiKit.label(str(ch.get("bio", "")), 13, UiKit.MUTED, true))
		v.add_child(UiKit.trim(Color(col, 0.5)))
		var d := ChoiceRules.describe(GameSession.content, persp)
		var gl := UiKit.label(Loc.t("Gain").to_upper(), 11, UiKit.OK)
		gl.add_theme_font_override("font", UiKit.display_variant(2))
		v.add_child(gl)
		for g: Variant in d["gain"]:
			v.add_child(_point("▲", str(g), UiKit.OK))
		var pl := UiKit.label(Loc.t("Price").to_upper(), 11, UiKit.WARN)
		pl.add_theme_font_override("font", UiKit.display_variant(2))
		v.add_child(pl)
		for p: Variant in d["price"]:
			v.add_child(_point("▼", str(p), UiKit.WARN))
		# Visible text of the same facts (screen readers, tests): ● gain / ▲ price lines.
		card.tooltip_text = "● " + Loc.t("Gain: %s") % ", ".join(d["gain"]) + "\n▲ " + Loc.t("Price: %s") % ", ".join(d["price"])
		var sp := Control.new()
		sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
		sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(sp)
		v.add_child(_support_strip(Loc.t("Support %s (%s)") % [who.split(" ")[0], names[persp]], col))
		row.add_child(card)
		if _first == null:
			_first = card
	body.add_child(row)


## The speaker: their course's crest in a hex badge inside turning rings; the
## initials stand in without the packs.
func _medallion(persp: String, who: String, col: Color) -> Control:
	var box := Control.new()
	box.custom_minimum_size = Vector2(76, 76)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ring := HoloRing.new()
	ring.set_anchors_preset(Control.PRESET_FULL_RECT)
	ring.add_layer("Ring_Small_06", 1.0, 0.2, Color(col.lightened(0.3), 0.5), 8)
	box.add_child(ring)
	var parts := who.split(" ", false)
	var initials := ""
	for p: String in parts.slice(0, 2):
		initials += p.substr(0, 1)
	var b := IconBadge.make("crest." + persp, 54, col, false, initials)
	b.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	b.grow_horizontal = Control.GROW_DIRECTION_BOTH
	b.grow_vertical = Control.GROW_DIRECTION_BOTH
	box.add_child(b)
	if SyntySkin.icon("crest." + persp) == null:
		return box  # the badge already shows the initials
	var tag := UiKit.label(initials, 11, Color.WHITE)
	tag.add_theme_font_override("font", UiKit.display_variant(1))
	tag.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	tag.grow_horizontal = Control.GROW_DIRECTION_BOTH
	tag.offset_top = -4
	box.add_child(tag)
	return box


func _point(sym: String, text: String, col: Color) -> Control:
	var h := UiKit.hbox(8)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var s := UiKit.label(sym, 12, col)
	s.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	h.add_child(s)
	var l := UiKit.label(text, 14, UiKit.TEXT.darkened(0.05), true)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(l)
	return h


## The call to action at the foot of a voice card (part of the card button).
func _support_strip(text: String, col: Color) -> Control:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(col.darkened(0.6), 0.9)
	sb.border_color = Color(col, 0.9)
	sb.set_border_width_all(1)
	sb.border_width_bottom = 2
	sb.corner_radius_top_right = 10
	sb.corner_radius_bottom_left = 10
	sb.set_content_margin_all(8)
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := UiKit.label(text.to_upper(), 15, col.lightened(0.6), true)
	l.add_theme_font_override("font", UiKit.display_variant(2))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	p.add_child(l)
	return p


func _unhandled_input(event: InputEvent) -> void:
	pass

class_name JournalPanel
extends CanvasLayer
## Tab: objectives, log and the embryo ledger at a glance.
## Holo log (D-059): the embryo ledger as one gauge strip over all 50,000
## (viable / in incubation / born / lost, each with its count), objectives as
## cards with a status badge and word (done / current / next; the current one
## with its description and hint), and the logbook as a timeline: a rail with
## a marker per day and one glyph per kind of entry. Read only.

const KINDS := {
	"objective": ["ui.icon_objective", "5fae6e"], "survey": ["ui.icon_probe", "4fc3d9"], "travel": ["ui.icon_ship", "4fc3d9"],
	"landing": ["ui.icon_lander", "e8a33d"], "build": ["ui.icon_building", "8fd0c8"], "birth": ["ui.icon_heart", "7cc46a"],
	"population": ["ui.icon_population", "7cc46a"], "event": ["ui.icon_event", "e8a33d"], "warning": ["ui.icon_warning", "d25b4c"],
	"society": ["ui.icon_council", "c9a0ff"], "era": ["ui.icon_time", "e8a33d"], "ark": ["ui.icon_ship", "8fd0c8"],
	"ending": ["ui.icon_trophy", "e8a33d"],
}

var _panel: PanelContainer
var _body: VBoxContainer
var _frame: HoloFrame


func _ready() -> void:
	layer = 30
	process_mode = Node.PROCESS_MODE_ALWAYS
	_panel = UiKit.panel(Vector2(1120, 0))
	_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_body = UiKit.vbox(10)
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_panel.add_child(_body)
	_frame = HoloFrame.attach(_panel)
	add_child(_panel)
	visible = false
	get_viewport().size_changed.connect(_fit)
	SettingsService.changed.connect(_fit)


func toggle() -> void:
	visible = not visible
	if visible:
		refresh()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_fit()
		HoloAnim.boot_in(_panel)
		_frame.boot()
		HoloAnim.stagger(_body, 0.05, 0.1)
	AudioService.ui("ui_click")


func _fit() -> void:
	if visible:
		UiKit.fit_layer(self, _panel)
		UiKit.fit_layer.call_deferred(self, _panel)


func refresh() -> void:
	UiKit.clear(_body)
	if not GameSession.has_game():
		return
	var gs: GameState = GameSession.state
	var day := gs.campaign.elapsed_days + gs.campaign.colony_day
	var hb := UiKit.header_block(Loc.t("Journal"), Loc.t("Day %d · objectives, the logbook and the embryo ledger.") % day, "ui.icon_journal")
	var row := hb.get_child(0) as HBoxContainer
	var hint := UiKit.hbox(6)
	hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hint.add_child(UiKit.keycap(SettingsService.binding_text("journal").split(" / ")[0], 14))
	hint.add_child(UiKit.label(Loc.t("Close"), 15, UiKit.MUTED))
	row.add_child(hint)
	_body.add_child(hb)
	_body.add_child(LedgerStrip.panel(gs.ark.ledger(), gs.ark.embryo_sum()))
	var cols := UiKit.hbox(18)
	cols.custom_minimum_size = Vector2(0, 470)
	var left := UiKit.vbox(8)
	left.custom_minimum_size = Vector2(430, 0)
	left.add_child(UiKit.section(Loc.t("Objectives"), "ui.icon_objective"))
	var ids: Array = GameSession.content.objectives.keys()
	ids.sort_custom(func(a: String, b: String) -> bool: return int(GameSession.content.objectives[a].get("order", 0)) < int(GameSession.content.objectives[b].get("order", 0)))
	var done_cards: Array = []
	var open_cards: Array = []
	var shown := 0
	for id: String in ids:
		var o: Dictionary = GameSession.content.objectives[id]
		var done := id in gs.campaign.completed_objectives
		var cur := not done and shown == 0
		if not done:
			shown += 1
		if shown > 3:
			continue
		(done_cards if done else open_cards).append(_objective(o, "done" if done else ("current" if cur else "next")))
	# Open objectives first (what to do now), then the completed ones, dimmed.
	var ol := UiKit.vbox(6)
	for c: Control in open_cards + done_cards:
		ol.add_child(c)
	var os := ScrollContainer.new()
	os.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	os.size_flags_vertical = Control.SIZE_EXPAND_FILL
	ol.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	os.add_child(ol)
	left.add_child(os)
	left.add_child(Holo.chip(Loc.t("%d of %d done") % [gs.campaign.completed_objectives.size(), ids.size()], UiKit.OK, "ui.icon_ok", 12))
	cols.add_child(left)
	var right := UiKit.vbox(8)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_child(UiKit.section(Loc.t("Logbook"), "ui.icon_journal"))
	var ts := ScrollContainer.new()
	ts.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	ts.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var tl := _timeline(gs)
	tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ts.add_child(tl)
	right.add_child(ts)
	cols.add_child(right)
	_body.add_child(cols)


func _objective(o: Dictionary, st: String) -> Control:
	var col: Color = {"done": UiKit.OK, "current": UiKit.AMBER, "next": UiKit.MUTED}[st]
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(col.darkened(0.82), 0.85) if st == "current" else Color(0.02, 0.05, 0.07, 0.6)
	sb.border_color = Color(col, 0.9 if st != "next" else 0.4)
	sb.border_width_left = 3
	sb.corner_radius_top_right = 10
	sb.corner_radius_bottom_left = 10
	sb.content_margin_left = 12
	sb.content_margin_right = 10
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	p.add_theme_stylebox_override("panel", sb)
	var h := UiKit.hbox(10)
	var icon: String = {"done": "ui.icon_ok", "current": "ui.icon_target", "next": "ui.icon_locked"}[st]
	var b := IconBadge.make(icon, 30 if st != "current" else 38, col, st == "current", {"done": "✔", "current": "▶", "next": "○"}[st])
	b.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	h.add_child(b)
	var v := UiKit.vbox(2)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var word: String = {"done": Loc.t("Done"), "current": Loc.t("Current"), "next": Loc.t("Next")}[st]
	v.add_child(Holo.chip(word, col, "", 10))
	var t := UiKit.label(str(o.get("title", o.get("id", ""))), 17 if st == "current" else 15, UiKit.TEXT if st != "done" else UiKit.MUTED.lightened(0.15), true)
	t.add_theme_font_override("font", UiKit.bold_font())
	v.add_child(t)
	if st == "current":
		if not str(o.get("description", "")).is_empty():
			v.add_child(UiKit.label(str(o["description"]), 14, UiKit.TEXT.darkened(0.12), true))
		if not str(o.get("hint", "")).is_empty():
			v.add_child(Holo.bullet("ui.icon_info", str(o["hint"]), UiKit.PETROL.lightened(0.3), "i", 13, UiKit.MUTED.lightened(0.15)))
	h.add_child(v)
	p.add_child(h)
	return p


## The logbook as a timeline, newest first: a rail with a day marker where the
## day changes and a glyph per entry kind.
func _timeline(gs: GameState) -> VBoxContainer:
	var v := UiKit.vbox(0)
	var entries: Array = gs.campaign.journal.duplicate()
	entries.reverse()
	var last_day := -1
	for e: Dictionary in entries.slice(0, 40):
		var d := int(e.get("day", 0))
		var first := d != last_day
		last_day = d
		var row := UiKit.hbox(0)
		var dl := UiKit.vbox(-4)
		dl.custom_minimum_size = Vector2(62, 0)
		if first:
			var dc := UiKit.label(Loc.t("DAY"), 10, UiKit.MUTED)
			dc.add_theme_font_override("font", UiKit.display_variant(2))
			dc.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			dl.add_child(dc)
			var dn := UiKit.label(str(d), 20, UiKit.AMBER.lightened(0.15))
			dn.add_theme_font_override("font", UiKit.display_font())
			dn.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			dl.add_child(dn)
		row.add_child(dl)
		var kind: Array = KINDS.get(str(e.get("kind", "")), ["ui.icon_info", "8fa3ad"])
		var rail := _Rail.new()
		rail.marker = first
		rail.col = Color(str(kind[1]))
		rail.custom_minimum_size = Vector2(30, 0)
		row.add_child(rail)
		var ent := UiKit.hbox(8)
		ent.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var m := MarginContainer.new()
		m.add_theme_constant_override("margin_top", 6 if first else 2)
		m.add_theme_constant_override("margin_bottom", 6)
		m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var ic := UiKit.icon_rect(str(kind[0]), 16, Color(str(kind[1])))
		if ic:
			ic.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
			ent.add_child(ic)
		var tx := UiKit.label(str(e.get("text", "")), 15, UiKit.TEXT if first else UiKit.TEXT.darkened(0.1), true)
		tx.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ent.add_child(tx)
		m.add_child(ent)
		row.add_child(m)
		v.add_child(row)
	if entries.is_empty():
		v.add_child(UiKit.label(Loc.t("Nothing logged yet."), 15, UiKit.MUTED))
	return v


## The timeline rail: a vertical line through the row, a ringed marker on a new day, a dot otherwise.
class _Rail extends Control:
	var marker := false
	var col := UiKit.PETROL

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size_flags_vertical = Control.SIZE_FILL

	func _draw() -> void:
		var x := size.x * 0.5
		draw_line(Vector2(x, 0), Vector2(x, size.y), Color(UiKit.PETROL.lightened(0.2), 0.35), 2.0)
		var y := 16.0 if marker else 12.0
		if marker:
			draw_circle(Vector2(x, y), 7.0, Color(0.02, 0.05, 0.07, 1.0), true)
			draw_arc(Vector2(x, y), 7.0, 0, TAU, 20, UiKit.AMBER, 2.0, true)
			draw_circle(Vector2(x, y), 3.0, UiKit.AMBER.lightened(0.3), true)
		else:
			draw_circle(Vector2(x, y), 3.5, Color(col, 0.9), true)

class_name EventDialog
extends OverlayPanel
## Crisis / citizen event: situation, options with price, requirements and the
## consequence shown before choosing. Always at least one free option.
## Dramatic card (D-059): a HoloBanner (crisis red with hazard stripes, or
## amber for colony life), the situation in a readable column, and each
## option as a large card: letter badge, label, its consequence, the price as
## amber chips (or a green FREE chip), the effects after the colony's course
## as gain (green ▲) / price (amber ▼) chips, and what blocks it. Keyboard /
## pad: the cards take focus (first open option first); Esc never dismisses.

var event_def: Dictionary = {}
var _first: Control

## effect key -> [caption, glyph, good when positive (or null = neutral), scale, suffix]
const EFFECTS := {
	"trust": ["Trust", "ui.icon_council", true, 1.0, ""], "health": ["Health", "ui.icon_health", true, 100.0, "%"],
	"food": ["Food", "ui.icon_food", true, 1.0, ""], "water": ["Water", "ui.icon_water", true, 1.0, ""],
	"alloy": ["Material", "ui.icon_alloy", true, 1.0, ""], "components": ["Components", "ui.icon_components", true, 1.0, ""],
	"wear": ["Wear", "ui.icon_repair", false, 1.0, ""], "autonomy": ["Autonomy", "ui.icon_council", null, 1.0, ""],
	"power_kw_days": ["Stored power", "ui.icon_power", true, 24.0, " kWh"], "solar_penalty_days": ["Weaker sun", "ui.icon_power", false, 1.0, " d"],
	"deaths": ["Deaths", "ui.icon_skull", false, 1.0, ""], "embryo_lost": ["Embryos lost", "ui.icon_embryo", false, 1.0, ""],
}


func _init() -> void:
	super(Vector2(940, 620))


func show_event(def: Dictionary) -> void:
	event_def = def
	open()


func focus_target() -> Control:
	return _first


func refresh() -> void:
	UiKit.clear(body)
	_first = null
	if event_def.is_empty():
		return
	var crit := bool(event_def.get("critical", false))
	var crisis := str(event_def.get("kind", "")) == "crisis"
	var col := UiKit.DANGER.lightened(0.1) if crit else UiKit.AMBER
	var gs: GameState = GameSession.state
	var kind := Loc.t("Critical") if crit else (Loc.t("Crisis") if crisis else Loc.t("Colony life"))
	# Symbol + colour, never colour alone: ■ critical, ◆ other events.
	var title := ("■ " if crit else "◆ ") + str(event_def.get("title", ""))
	var sub := Loc.t("Time stands still until you have chosen. Time leaps stop at unresolved crises.") if crit else ""
	body.add_child(HoloBanner.make("ui.icon_critical" if crit else "ui.icon_event", kind, title, sub, col, crit,
		[["ui.icon_time", Loc.t("Day %d") % gs.campaign.colony_day]]))
	var text := UiKit.label(str(event_def.get("text", "")), 18, UiKit.TEXT, true)
	var tm := MarginContainer.new()
	tm.add_theme_constant_override("margin_left", 8)
	tm.add_theme_constant_override("margin_right", 40)
	tm.add_theme_constant_override("margin_top", 4)
	tm.add_theme_constant_override("margin_bottom", 4)
	tm.add_child(text)
	body.add_child(tm)
	var cards := UiKit.vbox(10)
	var letters := "ABCDEF"
	var i := 0
	for o: Dictionary in DictUtil.get_arr(event_def, "options"):
		var blockers := GameSession.sim.events.option_blockers(gs, event_def, o)
		var cost: Dictionary = GameSession.sim.events.option_cost(gs, event_def, o)
		var eff: Dictionary = GameSession.sim.events.option_effects(gs, event_def, o)
		var free := true
		for k: String in cost.keys():
			if float(cost[k]) > 0.0:
				free = false
		var card := HoloCard.make(UiKit.OK if free else UiKit.AMBER, func() -> void:
			var r := GameSession.cmd_resolve_event(str(event_def.get("id")), str(o.get("id")))
			if r.ok:
				event_def = {}
				close())
		card.disabled = not blockers.is_empty()
		var h := UiKit.hbox(14)
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var lb := IconBadge.make("", 42, UiKit.OK if free else UiKit.AMBER, false, letters[i % letters.length()])
		lb.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		h.add_child(lb)
		var v := UiKit.vbox(4)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var nm := UiKit.label(str(o.get("label", "")), 19, Color.WHITE if blockers.is_empty() else UiKit.MUTED, true)
		nm.add_theme_font_override("font", UiKit.display_variant(1))
		v.add_child(nm)
		v.add_child(UiKit.label(str(o.get("description", "")), 15, UiKit.MUTED.lightened(0.15), true))
		var chips := HFlowContainer.new()
		chips.add_theme_constant_override("h_separation", 6)
		chips.add_theme_constant_override("v_separation", 4)
		chips.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if free:
			chips.add_child(Holo.chip(Loc.t("Free"), UiKit.OK, "ui.icon_ok", 12))
		for k: String in cost.keys():
			if float(cost[k]) > 0.0:
				chips.add_child(Holo.chip("−%d %s" % [int(cost[k]), ColonySimulation._res_label(k)], UiKit.AMBER, "ui.icon_" + k, 12))
		for k: String in EFFECTS.keys():
			if not eff.has(k):
				continue
			var x := float(eff[k])
			if absf(x) < 0.001:
				continue
			var spec: Array = EFFECTS[k]
			var n := x * float(spec[3])
			var good: Variant = spec[2]
			var c := UiKit.PETROL.lightened(0.35)
			var sym := "◆"
			if good != null:
				var is_gain := (n > 0.0) == bool(good)
				c = UiKit.OK if is_gain else UiKit.AMBER
				sym = "▲" if is_gain else "▼"
			var num := ("%+d" % int(roundf(n))) if k not in ["deaths", "embryo_lost", "solar_penalty_days"] else str(int(roundf(n)))
			chips.add_child(Holo.chip("%s %s %s%s" % [sym, _caption(k), num, str(spec[4])], c, str(spec[1]), 12))
		var prio := str(eff.get("priority", ""))
		if not prio.is_empty():
			chips.add_child(Holo.chip(Loc.t("Course: %s") % {"expansion": Loc.t("expansion"), "safety": Loc.t("safety"), "self_determination": Loc.t("self-determination")}.get(prio, prio), Color("c9a0ff"), "crest." + prio, 12))
		v.add_child(chips)
		for bl: Variant in blockers:
			v.add_child(UiKit.label("✕ " + str(bl), 14, UiKit.WARN, true))
		h.add_child(v)
		card.content.add_child(h)
		card.tooltip_text = str(o.get("label", ""))
		cards.add_child(card)
		if _first == null and blockers.is_empty():
			_first = card
		i += 1
	body.add_child(cards)
	# Keyboard / pad: focus lands on the first open option (not only with a pad:
	# Enter must not answer by accident, so it is the default free/first choice).
	if _first and SettingsService.using_pad:
		_first.grab_focus.call_deferred()


## Effect captions as literal Loc.t calls (so tools/loc_extract.py finds them).
static func _caption(k: String) -> String:
	return {"trust": Loc.t("Trust"), "health": Loc.t("Health"), "food": Loc.t("Food"), "water": Loc.t("Water"), "alloy": Loc.t("Material"),
		"components": Loc.t("Components"), "wear": Loc.t("Wear"), "autonomy": Loc.t("Autonomy"), "power_kw_days": Loc.t("Stored power"),
		"solar_penalty_days": Loc.t("Weaker sun"), "deaths": Loc.t("Deaths"), "embryo_lost": Loc.t("Embryos lost")}.get(k, k)


func _unhandled_input(event: InputEvent) -> void:
	pass  # An event must be answered; Esc does not dismiss it.

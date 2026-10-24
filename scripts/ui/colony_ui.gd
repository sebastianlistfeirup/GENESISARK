class_name ColonyUi
extends RefCounted
## Builders for the colony HUD: resource bar, speed, build bar, info panel.
## Every number shown is read from the domain report; UI only sends commands.

## One readout of the resource dock: glyph + value, tooltip explains it.
static func res_chip(icon_slot: String, text: String, tip: String, color: Color = UiKit.TEXT, glyph: String = "") -> Control:
	var h := UiKit.hbox(6)
	h.tooltip_text = tip
	h.mouse_filter = Control.MOUSE_FILTER_PASS
	var tint := Color(str(AssetSlots.slot(icon_slot).get("proxy", [{}])[0].get("color", "#ffffff")))
	# Synty glyph tinted with the slot colour when the UI packs are installed;
	# otherwise the original colour square. The text always carries the value.
	var tex := SyntySkin.icon(glyph if not glyph.is_empty() else icon_slot)
	if tex:
		var ic := TextureRect.new()
		ic.texture = tex
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ic.custom_minimum_size = Vector2(18, 18)
		ic.modulate = tint.lightened(0.2)
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(ic)
	else:
		var dot := ColorRect.new()
		dot.custom_minimum_size = Vector2(10, 10)
		dot.color = tint
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(dot)
	var l := UiKit.label(text, 16, color)
	l.add_theme_font_override("font", UiKit.bold_font())
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(l)
	return h


## Trust as a dial (R9): symbol + number, never colour alone. ▼ low, ▲ high, ◆ neutral.
static func trust_chip(gs: GameState) -> Control:
	var band := ChoiceRules.trust_band(GameSession.content, gs)
	var sym := {"low": "▼", "high": "▲"}.get(band, "◆") as String
	var why := ChoiceRules.trust_explanation(GameSession.content, gs)
	var tip := Loc.t("Trust in the plan (0-100). Below %d people work more slowly and incubation needs larger reserves; above %d they work harder and crises cost less.") % [int(GameSession.content.bal("trust_effects.low", 35)), int(GameSession.content.bal("trust_effects.high", 65))]
	if not why.is_empty():
		tip += "
" + why
	return res_chip("ui.icon_population", Loc.t("%s Trust %d") % [sym, int(gs.society.trust)], tip, UiKit.WARN if band == "low" else (UiKit.OK if band == "high" else UiKit.TEXT))


## The colony's resource readouts on one dock plate, separated by hairlines
## (one HUD element instead of ten loose chips).
static func resource_bar(gs: GameState) -> HBoxContainer:
	var outer := UiKit.hbox(0)
	var dock := PanelContainer.new()
	dock.theme_type_variation = &"PanelDock"
	dock.mouse_filter = Control.MOUSE_FILTER_PASS
	outer.add_child(dock)
	var h := UiKit.hbox(4)
	dock.add_child(h)
	var c := gs.colony
	var rep: Dictionary = c.last_report
	var pw: Dictionary = rep.get("power", {})
	var surplus := float(pw.get("surplus_kw", 0.0))
	var rd := float(rep.get("reserve_days", 9999.0))
	var rd_text := "∞" if rd >= 9999.0 else str(int(rd))
	h.add_child(res_chip("ui.icon_power", UiKit.status_text("ok" if surplus >= 0 else "critical", Loc.t("%+.1f kW · %d kWh") % [surplus, int(c.battery_kwh)]), Loc.t("Power balance (production − consumption) and battery. Priority: life support, care, water/food, production."), UiKit.OK if surplus >= 0 else UiKit.DANGER))
	h.add_child(res_chip("ui.icon_alloy", "%d" % int(c.inventory["alloy"]), Loc.t("Building material")))
	h.add_child(res_chip("ui.icon_components", "%d" % int(c.inventory["components"]), Loc.t("Components (spare parts, maintenance, modules)")))
	h.add_child(res_chip("ui.icon_water", "%d" % int(c.inventory["water"]), Loc.t("Water in person-days (+%.0f/day)") % float(rep.get("produced", {}).get("water", 0.0))))
	h.add_child(res_chip("ui.icon_food", "%d" % int(c.inventory["food"]), Loc.t("Food in person-days (+%.0f/day)") % float(rep.get("produced", {}).get("food", 0.0))))
	h.add_child(res_chip("ui.icon_water", (UiKit.status_text("warning", Loc.t("Reserve %s d") % rd_text) if rd < 30 else Loc.t("Reserve %s d") % rd_text), Loc.t("Days that water and food will last for the current population."), UiKit.WARN if rd < 30 else UiKit.TEXT, "ui.icon_reserve"))
	h.add_child(res_chip("ui.icon_population", "%d" % gs.population.alive_count(), Loc.t("Living population (cohorts)")))
	h.add_child(trust_chip(gs))
	h.add_child(res_chip("ui.icon_embryo", UiKit.thousands(gs.ark.embryo_viable), Loc.t("Viable embryos (%d in incubation, %d born)") % [gs.ark.embryo_incubating, gs.ark.embryo_born]))
	h.add_child(res_chip("ui.icon_fuel", Loc.t("Ark %d") % int(c.ark_fuel), Loc.t("The Ark's fuel for emergency power (%d kW). If it runs out, the colony loses the Ark's power.") % int(pw.get("ark_kw", 0))))
	for i: int in range(h.get_child_count() - 1, 0, -1):
		var sep := VSeparator.new()
		sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(sep)
		h.move_child(sep, i)
	return outer


static func building_tooltip(sim: Simulation, def_id: String) -> String:
	var def := sim.content.building(def_id)
	var gs := sim.state
	var cost := sim.colony.build_cost(gs, def_id)
	var parts: Array = []
	for k: String in cost.keys():
		parts.append("%d %s" % [int(cost[k]), ColonySimulation._res_label(k)])
	var kw := float(def.get("power_kw", 0))
	var lines: Array = [str(def.get("name")), str(def.get("description", "")), Loc.t("Cost: ") + ", ".join(parts),
		Loc.t("Power: %+d kW%s") % [int(kw), Loc.t(" (depends on the planet)") if def.has("power_source") else ""],
		Loc.t("Construction work: %d drone-days") % int(def.get("build_work", 0))]
	var out: Dictionary = DictUtil.get_dict(def, "output")
	for k: String in out.keys():
		lines.append(Loc.t("Produces: %s %s/day") % [str(out[k]), ColonySimulation._res_label(k)])
	var d := str(def.get("district", "any"))
	if d != "any":
		lines.append(Loc.t("Placement: ") + (Loc.t("the living zone") if d == "living" else Loc.t("the resource area")))
	lines.append(Loc.t("Priority: ") + Loc.t(str(ColonySimulation.PRIORITY_LABELS.get(str(def.get("priority")), ""))))
	return "\n".join(lines)


static func info_panel(sim: Simulation, bid: int, actions: Dictionary) -> PanelContainer:
	var gs := sim.state
	var b := gs.colony.building_by_id(bid)
	var p := UiKit.panel(Vector2(380, 0))
	if b.is_empty():
		return p
	var def := sim.content.building(str(b["def_id"]))
	var v := UiKit.vbox(6)
	var head := UiKit.hbox(10)
	var bic := UiKit.badge("build." + str(b["def_id"]) if str(b["def_id"]) != "ark_core" else "ui.icon_ship", 38)
	if bic.custom_minimum_size.x > 0.0:
		head.add_child(bic)
	var nm := UiKit.heading(str(def.get("name")), 22)
	nm.add_theme_color_override("font_color", UiKit.AMBER)
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	head.add_child(nm)
	v.add_child(head)
	v.add_child(UiKit.label(str(def.get("description", "")), 14, UiKit.MUTED, true))
	var state := str(b["state"])
	if state == ColonyState.B_CONSTRUCTING:
		v.add_child(UiKit.label(Loc.t("Under construction: %d%%") % int(float(b["progress"]) * 100), 16, UiKit.AMBER))
		v.add_child(UiKit.bar(float(b["progress"]), 1.0, UiKit.AMBER))
	var hz := sim.colony.hazard_factors(gs, gs.campaign.colony_day)
	var kw := sim.colony.building_power_kw(gs, b, hz)
	v.add_child(UiKit.label(Loc.t("Power: %+.1f kW · %s · %s") % [kw, Loc.t("connected") if b.get("accessible") else Loc.t("NOT connected"), Loc.t("power") if b.get("powered") else Loc.t("no power")], 15))
	if b["def_id"] != "ark_core":
		v.add_child(UiKit.label(Loc.t("Wear: %d%% · Efficiency: %d%%") % [int(float(b.get("wear", 0.0)) / 60.0 * 100.0), int(float(b.get("efficiency", 1.0)) * 100.0)], 14, UiKit.MUTED))
	var reason := str(b.get("blocked_reason", ""))
	if not reason.is_empty() and reason != "constructing":
		v.add_child(UiKit.label("▲ " + Loc.t(str(ColonySimulation.REASONS.get(reason, reason))), 15, UiKit.WARN, true))
		v.add_child(UiKit.label(_fix_hint(reason), 14, UiKit.MUTED, true))
	if b["def_id"] == "ark_core":
		v.add_child(UiKit.label(Loc.t("Emergency power %d kW · Fuel %d · Salvage material left %d") % [int(sim.colony.ark_power_kw(gs)), int(gs.colony.ark_fuel), int(gs.colony.salvage_left)], 14, UiKit.TEXT, true))
	var mods: Dictionary = DictUtil.get_dict(def, "modules")
	for m: String in mods.keys():
		if m in b.get("modules", []):
			v.add_child(UiKit.label(Loc.t("● %s installed") % mods[m].get("name"), 14, UiKit.OK))
		elif state == ColonyState.B_ACTIVE:
			var c: Dictionary = mods[m].get("cost", {})
			var btn := UiKit.button(Loc.t("Add %s (%d mat., %d comp., %+d kW)") % [mods[m].get("name"), int(c.get("alloy", 0)), int(c.get("components", 0)), int(mods[m].get("power_kw", 0))],
				func() -> void: actions["module"].call(bid, m), str(mods[m].get("description", "")))
			if sim.colony.requires_module(gs) == m:
				btn.text = "★ " + btn.text
				btn.tooltip_text += Loc.t("\nThis planet requires the module before the habitat is safe.")
			v.add_child(btn)
	if b["def_id"] == "care_center" and state == ColonyState.B_ACTIVE:
		var size := int(sim.content.bal("incubation.cohort_size", 10))
		var blockers := sim.population.incubation_blockers(gs, size)
		var ib := UiKit.button(Loc.t("Start incubation (%d embryos)") % size, func() -> void: actions["incubate"].call())
		ib.disabled = not blockers.is_empty()
		v.add_child(ib)
		for bl: Variant in blockers:
			v.add_child(UiKit.label("✕ " + str(bl), 14, UiKit.MUTED, true))
	if b["def_id"] == "school_hall" and state == ColonyState.B_ACTIVE and not gs.society.council_formed:
		var cb := sim.society.council_blockers(gs)
		var btn := UiKit.button(Loc.t("Convene the colony's first council"), func() -> void: actions["council"].call())
		btn.disabled = not cb.is_empty()
		v.add_child(btn)
		for bl: Variant in cb:
			v.add_child(UiKit.label("✕ " + str(bl), 14, UiKit.MUTED, true))
	if b["def_id"] != "ark_core":
		var inv: Dictionary = DictUtil.get_dict(b, "invested")
		var frac := 1.0 if state == ColonyState.B_CONSTRUCTING and float(b["progress"]) <= 0.0 else float(sim.content.bal("demolish_refund", 0.5))
		var refund := int(float(inv.get("alloy", 0)) * frac)
		v.add_child(UiKit.button((Loc.t("Cancel (+%d mat.)") if frac >= 1.0 else Loc.t("Demolish (+%d mat. back)")) % refund, func() -> void: actions["demolish"].call(bid)))
	p.add_child(v)
	return p


static func _fix_hint(reason: String) -> String:
	match reason:
		"no_power": return Loc.t("Next step: build more power (solar/geothermal) or a battery. Life support and care get power first.")
		"no_access": return Loc.t("Next step: place a building or drone hub that connects it to the network.")
		"no_workforce": return Loc.t("Next step: build a drone hub — or wait for adult cohorts. Mines and workshops each keep one robot busy: if nothing gets built at all, demolish one to free a robot for construction.")
		"maintenance": return Loc.t("Next step: obtain components (workshop) so the robots can do servicing.")
		"input_missing": return Loc.t("Next step: secure raw materials (building material or water).")
		"module_missing": return Loc.t("Next step: install the module the planet requires.")
	return ""

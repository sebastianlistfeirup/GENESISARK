class_name ColonyUi
extends RefCounted
## Builders for the colony HUD: resource bar, speed, build bar, info panel.
## Every number shown is read from the domain report; UI only sends commands.

## One readout of the resource dock: glyph on a small tinted plate, the value,
## and an optional trend arrow (▲ / ▼, coloured: good green, bad amber;
## the arrow is a symbol, so colour is never the only cue). Tooltip explains it.
static func res_chip(icon_slot: String, text: String, tip: String, color: Color = UiKit.TEXT, glyph: String = "", trend: int = 0, trend_good: bool = true) -> Control:
	var h := UiKit.hbox(5)
	h.tooltip_text = tip
	h.mouse_filter = Control.MOUSE_FILTER_PASS
	var tint := Color(str(AssetSlots.slot(icon_slot).get("proxy", [{}])[0].get("color", "#ffffff")))
	# Synty glyph tinted with the slot colour when the UI packs are installed;
	# otherwise the original colour square. The text always carries the value.
	var plate := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(tint.darkened(0.65), 0.85)
	sb.border_color = Color(tint, 0.45)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(5)
	sb.set_content_margin_all(2)
	plate.add_theme_stylebox_override("panel", sb)
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var tex := SyntySkin.icon(glyph if not glyph.is_empty() else icon_slot)
	if tex:
		var ic := TextureRect.new()
		ic.texture = tex
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ic.custom_minimum_size = Vector2(16, 16)
		ic.modulate = tint.lightened(0.3)
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		plate.add_child(ic)
	else:
		var dot := ColorRect.new()
		dot.custom_minimum_size = Vector2(10, 10)
		dot.color = tint
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		plate.add_child(dot)
	h.add_child(plate)
	var l := UiKit.label(text, 16, color)
	l.add_theme_font_override("font", UiKit.bold_font())
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(l)
	if trend != 0:
		var good := (trend > 0) == trend_good
		var ar := UiKit.label("▲" if trend > 0 else "▼", 11, UiKit.OK if good else UiKit.WARN)
		ar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(ar)
	return h


## Trust as a dial (R9): symbol + number, never colour alone. ▼ low, ▲ high, ◆ neutral.
static func trust_chip(gs: GameState) -> Control:
	var band := ChoiceRules.trust_band(GameSession.content, gs)
	var sym := {"low": "▼", "high": "▲"}.get(band, "◆") as String
	var why := ChoiceRules.trust_explanation(GameSession.content, gs)
	var tip := Loc.t("Trust in the plan (0-100). Below %d people work more slowly and incubation needs larger reserves; above %d they work harder and crises cost less.") % [int(GameSession.content.bal("trust_effects.low", 35)), int(GameSession.content.bal("trust_effects.high", 65))]
	if not why.is_empty():
		tip += "\n" + why
	return res_chip("ui.icon_population", Loc.t("%s Trust %d") % [sym, int(gs.society.trust)], tip, UiKit.WARN if band == "low" else (UiKit.OK if band == "high" else UiKit.TEXT), "ui.icon_council")


static func _sgn(x: float) -> int:
	return 0 if absf(x) < 0.05 else (1 if x > 0.0 else -1)


## The colony's resource readouts on one dock plate, separated by hairlines
## (one HUD element instead of ten loose chips). Trend arrows come straight
## from the day report: power balance, water and food net per day, income of
## material and components, colonists on the way (incubation).
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
	var prod: Dictionary = rep.get("produced", {})
	var need: Dictionary = rep.get("need", {})
	var surplus := float(pw.get("surplus_kw", 0.0))
	var rd := float(rep.get("reserve_days", 9999.0))
	var rd_text := "∞" if rd >= 9999.0 else str(int(rd))
	var wnet := float(prod.get("water", 0.0)) - float(need.get("water", 0.0))
	var fnet := float(prod.get("food", 0.0)) - float(need.get("food", 0.0))
	h.add_child(res_chip("ui.icon_power", UiKit.status_text("ok" if surplus >= 0 else "critical", Loc.t("%+.1f kW · %d kWh") % [surplus, int(c.battery_kwh)]), Loc.t("Power balance (production − consumption) and battery. Priority: life support, care, water/food, production."), UiKit.OK if surplus >= 0 else UiKit.DANGER, "", _sgn(surplus)))
	h.add_child(res_chip("ui.icon_alloy", "%d" % int(c.inventory["alloy"]), Loc.t("Building material") + "\n" + Loc.t("Income: +%.0f per day") % float(prod.get("alloy", 0.0)), UiKit.TEXT, "", _sgn(float(prod.get("alloy", 0.0)))))
	h.add_child(res_chip("ui.icon_components", "%d" % int(c.inventory["components"]), Loc.t("Components (spare parts, maintenance, modules)") + "\n" + Loc.t("Income: +%.0f per day") % float(prod.get("components", 0.0)), UiKit.TEXT, "", _sgn(float(prod.get("components", 0.0)))))
	h.add_child(res_chip("ui.icon_water", "%d" % int(c.inventory["water"]), Loc.t("Water in person-days (+%.0f/day)") % float(prod.get("water", 0.0)) + "\n" + Loc.t("Net: %+.0f per day") % wnet, UiKit.TEXT, "", _sgn(wnet)))
	h.add_child(res_chip("ui.icon_food", "%d" % int(c.inventory["food"]), Loc.t("Food in person-days (+%.0f/day)") % float(prod.get("food", 0.0)) + "\n" + Loc.t("Net: %+.0f per day") % fnet, UiKit.TEXT, "", _sgn(fnet)))
	h.add_child(res_chip("ui.icon_water", (UiKit.status_text("warning", Loc.t("Reserve %s d") % rd_text) if rd < 30 else Loc.t("Reserve %s d") % rd_text), Loc.t("Days that water and food will last for the current population."), UiKit.WARN if rd < 30 else UiKit.TEXT, "ui.icon_reserve"))
	h.add_child(res_chip("ui.icon_population", "%d" % gs.population.alive_count(), Loc.t("Living population (cohorts)") + ("\n" + Loc.t("%d in incubation") % gs.ark.embryo_incubating if gs.ark.embryo_incubating > 0 else ""), UiKit.TEXT, "", 1 if gs.ark.embryo_incubating > 0 else 0))
	h.add_child(trust_chip(gs))
	h.add_child(res_chip("ui.icon_embryo", UiKit.thousands(gs.ark.embryo_viable), Loc.t("Viable embryos (%d in incubation, %d born)") % [gs.ark.embryo_incubating, gs.ark.embryo_born]))
	h.add_child(res_chip("ui.icon_fuel", Loc.t("Ark %d") % int(c.ark_fuel), Loc.t("The Ark's fuel for emergency power (%d kW). If it runs out, the colony loses the Ark's power.") % int(pw.get("ark_kw", 0))))
	for i: int in range(h.get_child_count() - 1, 0, -1):
		var sep := VSeparator.new()
		sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(sep)
		h.move_child(sep, i)
	return outer


## A build-bar button, icon first (D-059): the building's glyph on the left,
## its short name and the cost as small glyph + number chips under it. The
## full description stays in the tooltip. Updated each sync by update_build_button.
static func build_button(def_id: String, cb: Callable) -> Button:
	var b := UiKit.button("", cb)
	b.set_meta("def_id", def_id)
	b.set_meta("holo_build", true)
	b.custom_minimum_size = Vector2(118, 50)
	var h := UiKit.hbox(7)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.set_anchors_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 8
	h.offset_right = -6
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	var ic := UiKit.icon_rect("build." + def_id, 26, UiKit.PETROL.lightened(0.5))
	if ic:
		h.add_child(ic)
	var v := UiKit.vbox(0)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var nm := UiKit.label("", 13, UiKit.TEXT)
	nm.name = "Name"
	nm.add_theme_font_override("font", UiKit.bold_font())
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(nm)
	var cost := UiKit.hbox(6)
	cost.name = "Cost"
	cost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(cost)
	h.add_child(v)
	b.add_child(h)
	b.set_meta("box", h)
	return b


## Name, cost chips and affordability of a build button (read from the domain).
## The button sizes itself to its name + cost (Button ignores child sizes).
static func update_build_button(b: Button, sim: Simulation, gs: GameState) -> void:
	var def_id := str(b.get_meta("def_id"))
	var cost := sim.colony.build_cost(gs, def_id)
	var afford := true
	for k: String in cost.keys():
		if float(gs.colony.inventory.get(k, 0.0)) < float(cost[k]):
			afford = false
	var h: HBoxContainer = b.get_meta("box")
	var nm := h.find_child("Name", true, false) as Label
	var row := h.find_child("Cost", true, false) as HBoxContainer
	var short := str(sim.content.building(def_id).get("name")).replace(Loc.t(" and incubation center"), "").replace(Loc.t("Geothermal generator"), Loc.t("Geothermal"))
	var key := "%s|%s|%s" % [short, str(cost), afford]
	if str(b.get_meta("key", "")) == key:
		return
	b.set_meta("key", key)
	nm.text = short
	UiKit.clear(row)
	for k: String in ["alloy", "components"]:
		if not cost.has(k) or float(cost[k]) <= 0.0:
			continue
		var have := float(gs.colony.inventory.get(k, 0.0)) >= float(cost[k])
		var ch := UiKit.hbox(2)
		ch.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var ci := UiKit.icon_rect("ui.icon_" + k, 12, UiKit.MUTED.lightened(0.2) if have else UiKit.WARN)
		if ci:
			ch.add_child(ci)
		var cl := UiKit.label(("%d" % int(cost[k])) + ("" if ci else (" " + (Loc.t("mat.") if k == "alloy" else Loc.t("comp.")))), 12, UiKit.MUTED.lightened(0.25) if have else UiKit.WARN)
		cl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ch.add_child(cl)
		row.add_child(ch)
	b.modulate = Color.WHITE if afford else Color(1, 1, 1, 0.55)
	var need := h.get_combined_minimum_size().x + 16.0
	b.custom_minimum_size.x = maxf(96.0, need)


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


## The selected building as a holo card (D-059): its glyph in a hex badge
## (turning while it runs), name, a status chip (word + glyph + colour), the
## power readout with connection / supply chips, wear and efficiency meters,
## the robot crew it needs, the blocker with its next step, and the actions
## as icon buttons (demolish in red). Every value is read from the domain.
static func info_panel(sim: Simulation, bid: int, actions: Dictionary) -> PanelContainer:
	var gs := sim.state
	var b := gs.colony.building_by_id(bid)
	var p := UiKit.panel(Vector2(400, 0))
	if b.is_empty():
		return p
	var def := sim.content.building(str(b["def_id"]))
	var state := str(b["state"])
	var reason := str(b.get("blocked_reason", ""))
	var blocked := not reason.is_empty() and reason != "constructing"
	var st_kind := "warning" if state == ColonyState.B_CONSTRUCTING else ("critical" if blocked else "ok")
	var st_col := UiKit.status_color(st_kind)
	var st_word := Loc.t("Under construction") if state == ColonyState.B_CONSTRUCTING else (Loc.t("Blocked") if blocked else Loc.t("Running"))
	var v := UiKit.vbox(8)
	var head := UiKit.hbox(12)
	var is_ark := str(b["def_id"]) == "ark_core"
	head.add_child(IconBadge.make("build." + str(b["def_id"]) if not is_ark else "ui.icon_ship", 52, st_col if blocked else UiKit.AMBER, state == ColonyState.B_ACTIVE and not blocked, "◆"))
	var hv := UiKit.vbox(2)
	hv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hv.alignment = BoxContainer.ALIGNMENT_CENTER
	var nm := UiKit.heading(str(def.get("name")), 21)
	nm.add_theme_color_override("font_color", UiKit.AMBER.lightened(0.1))
	nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hv.add_child(nm)
	var chips := UiKit.hbox(6)
	chips.add_child(Holo.chip(st_word, st_col, "ui.icon_" + st_kind, 11))
	chips.add_child(Holo.chip(Loc.t(str(ColonySimulation.PRIORITY_LABELS.get(str(def.get("priority")), ""))), UiKit.PETROL.lightened(0.35), "", 11))
	hv.add_child(chips)
	head.add_child(hv)
	v.add_child(head)
	v.add_child(UiKit.label(str(def.get("description", "")), 14, UiKit.MUTED, true))
	if state == ColonyState.B_CONSTRUCTING:
		var ch := UiKit.hbox(8)
		var cl := UiKit.label(Loc.t("Under construction: %d%%") % int(float(b["progress"]) * 100), 16, UiKit.AMBER)
		cl.add_theme_font_override("font", UiKit.display_font())
		ch.add_child(cl)
		v.add_child(ch)
		v.add_child(UiKit.bar(float(b["progress"]), 1.0, UiKit.AMBER, 10))
	# Power: the number big, connection and supply as chips (glyph + word).
	var hz := sim.colony.hazard_factors(gs, gs.campaign.colony_day)
	var kw := sim.colony.building_power_kw(gs, b, hz)
	var pr := UiKit.hbox(10)
	pr.add_child(IconBadge.make("ui.icon_power", 34, UiKit.OK if kw >= 0.0 else UiKit.PETROL.lightened(0.3), false, "⚡"))
	var pv := UiKit.vbox(-2)
	var pc := UiKit.label(Loc.t("Power").to_upper(), 11, UiKit.MUTED)
	pc.add_theme_font_override("font", UiKit.display_variant(1))
	pv.add_child(pc)
	var pk := UiKit.label("%+.1f kW" % kw, 22, UiKit.OK.lightened(0.2) if kw >= 0.0 else UiKit.TEXT)
	pk.add_theme_font_override("font", UiKit.display_font())
	pv.add_child(pk)
	pr.add_child(pv)
	var pchips := VBoxContainer.new()
	pchips.add_theme_constant_override("separation", 3)
	pchips.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pchips.alignment = BoxContainer.ALIGNMENT_CENTER
	var acc := bool(b.get("accessible"))
	var has_pow := bool(b.get("powered"))
	pchips.add_child(Holo.chip(Loc.t("connected") if acc else Loc.t("NOT connected"), UiKit.OK if acc else UiKit.DANGER, "ui.icon_ok" if acc else "ui.icon_critical", 11))
	pchips.add_child(Holo.chip(Loc.t("power") if has_pow else Loc.t("no power"), UiKit.OK if has_pow else UiKit.DANGER, "ui.icon_power", 11))
	pr.add_child(pchips)
	v.add_child(pr)
	pr.tooltip_text = Loc.t("Power: %+.1f kW · %s · %s") % [kw, Loc.t("connected") if acc else Loc.t("NOT connected"), Loc.t("power") if has_pow else Loc.t("no power")]
	if not is_ark:
		var wear := float(b.get("wear", 0.0)) / 60.0
		var eff := float(b.get("efficiency", 1.0))
		var mg := GridContainer.new()
		mg.columns = 3
		mg.add_theme_constant_override("h_separation", 10)
		mg.add_theme_constant_override("v_separation", 4)
		for m: Array in [[Loc.t("Wear"), wear, UiKit.WARN if wear > 0.6 else UiKit.PETROL.lightened(0.3)], [Loc.t("Efficiency"), eff, UiKit.OK if eff > 0.7 else UiKit.WARN]]:
			var ml := UiKit.label(str(m[0]).to_upper(), 11, UiKit.MUTED)
			ml.add_theme_font_override("font", UiKit.display_variant(1))
			ml.custom_minimum_size = Vector2(96, 0)
			mg.add_child(ml)
			mg.add_child(Holo.meter(float(m[1]), 10, m[2], 170))
			mg.add_child(UiKit.label("%d%%" % int(float(m[1]) * 100.0), 14, UiKit.TEXT))
		v.add_child(mg)
		var crew := float(def.get("workforce", 0.0))
		if crew > 0.0:
			var staffed := reason != "no_workforce"
			v.add_child(Holo.bullet("ui.icon_building", Loc.t("Crew: %d robot(s)") % int(crew) + " · " + (Loc.t("staffed") if staffed else Loc.t("waiting for a robot")), UiKit.OK if staffed else UiKit.WARN, "◆", 14))
	if blocked:
		var bc := Holo.card(UiKit.WARN, 8)
		var bv := UiKit.vbox(2)
		bv.add_child(UiKit.label("▲ " + Loc.t(str(ColonySimulation.REASONS.get(reason, reason))), 15, UiKit.WARN, true))
		bv.add_child(UiKit.label(_fix_hint(reason), 13, UiKit.MUTED.lightened(0.1), true))
		bc.add_child(bv)
		v.add_child(bc)
	if is_ark:
		var ar := UiKit.hbox(16)
		ar.add_child(Holo.readout("ui.icon_power", Loc.t("Emergency power"), Holo.value_label("%d kW" % int(sim.colony.ark_power_kw(gs)), 18), UiKit.OK))
		ar.add_child(Holo.readout("ui.icon_fuel", Loc.t("Fuel"), Holo.value_label(str(int(gs.colony.ark_fuel)), 18), UiKit.AMBER))
		ar.add_child(Holo.readout("ui.icon_alloy", Loc.t("Salvage"), Holo.value_label(str(int(gs.colony.salvage_left)), 18), UiKit.PETROL.lightened(0.3)))
		v.add_child(ar)
		v.add_child(UiKit.label(Loc.t("Emergency power %d kW · Fuel %d · Salvage material left %d") % [int(sim.colony.ark_power_kw(gs)), int(gs.colony.ark_fuel), int(gs.colony.salvage_left)], 12, UiKit.MUTED, true))
	var acts := UiKit.vbox(6)
	var mods: Dictionary = DictUtil.get_dict(def, "modules")
	for m: String in mods.keys():
		if m in b.get("modules", []):
			acts.add_child(Holo.bullet("ui.icon_ok", Loc.t("● %s installed") % mods[m].get("name"), UiKit.OK, "●", 14, UiKit.OK))
		elif state == ColonyState.B_ACTIVE:
			var c: Dictionary = mods[m].get("cost", {})
			var btn := UiKit.button(Loc.t("Add %s (%d mat., %d comp., %+d kW)") % [mods[m].get("name"), int(c.get("alloy", 0)), int(c.get("components", 0)), int(mods[m].get("power_kw", 0))],
				func() -> void: actions["module"].call(bid, m), str(mods[m].get("description", "")))
			UiKit.with_icon(btn, "ui.icon_plus", 18)
			btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
			btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			if sim.colony.requires_module(gs) == m:
				btn.text = "★ " + btn.text
				btn.tooltip_text += Loc.t("\nThis planet requires the module before the habitat is safe.")
				btn.add_theme_color_override("font_color", UiKit.AMBER.lightened(0.3))
			acts.add_child(btn)
	if b["def_id"] == "care_center" and state == ColonyState.B_ACTIVE:
		var size := int(sim.content.bal("incubation.cohort_size", 10))
		var blockers := sim.population.incubation_blockers(gs, size)
		var ib := UiKit.button(Loc.t("Start incubation (%d embryos)") % size, func() -> void: actions["incubate"].call())
		UiKit.with_icon(ib, "ui.icon_embryo", 18)
		ib.alignment = HORIZONTAL_ALIGNMENT_LEFT
		ib.disabled = not blockers.is_empty()
		acts.add_child(ib)
		for bl: Variant in blockers:
			acts.add_child(UiKit.label("✕ " + str(bl), 13, UiKit.MUTED, true))
	if b["def_id"] == "school_hall" and state == ColonyState.B_ACTIVE and not gs.society.council_formed:
		var cb := sim.society.council_blockers(gs)
		var btn := UiKit.button(Loc.t("Convene the colony's first council"), func() -> void: actions["council"].call())
		UiKit.with_icon(btn, "ui.icon_council", 18)
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.disabled = not cb.is_empty()
		acts.add_child(btn)
		for bl: Variant in cb:
			acts.add_child(UiKit.label("✕ " + str(bl), 13, UiKit.MUTED, true))
	if not is_ark:
		var inv: Dictionary = DictUtil.get_dict(b, "invested")
		var frac := 1.0 if state == ColonyState.B_CONSTRUCTING and float(b["progress"]) <= 0.0 else float(sim.content.bal("demolish_refund", 0.5))
		var refund := int(float(inv.get("alloy", 0)) * frac)
		var db := UiKit.button((Loc.t("Cancel (+%d mat.)") if frac >= 1.0 else Loc.t("Demolish (+%d mat. back)")) % refund, func() -> void: actions["demolish"].call(bid))
		UiKit.with_icon(db, "ui.icon_delete", 16)
		db.alignment = HORIZONTAL_ALIGNMENT_LEFT
		db.add_theme_color_override("font_color", UiKit.DANGER.lightened(0.35))
		db.add_theme_color_override("icon_normal_color", UiKit.DANGER.lightened(0.2))
		acts.add_child(db)
	if acts.get_child_count() > 0:
		v.add_child(UiKit.trim())
		v.add_child(acts)
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

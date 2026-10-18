class_name ColonyUi
extends RefCounted
## Builders for the colony HUD: resource bar, speed, build bar, info panel.
## Every number shown is read from the domain report; UI only sends commands.

static func res_chip(icon_slot: String, text: String, tip: String, color: Color = UiKit.TEXT) -> PanelContainer:
	var p := UiKit.panel()
	p.tooltip_text = tip
	p.mouse_filter = Control.MOUSE_FILTER_PASS
	var h := UiKit.hbox(6)
	var dot := ColorRect.new()
	dot.custom_minimum_size = Vector2(10, 10)
	dot.color = Color(str(AssetSlots.slot(icon_slot).get("proxy", [{}])[0].get("color", "#ffffff")))
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(dot)
	h.add_child(UiKit.label(text, 16, color))
	p.add_child(h)
	return p


static func resource_bar(gs: GameState) -> HBoxContainer:
	var h := UiKit.hbox(6)
	var c := gs.colony
	var rep: Dictionary = c.last_report
	var pw: Dictionary = rep.get("power", {})
	var surplus := float(pw.get("surplus_kw", 0.0))
	var rd := float(rep.get("reserve_days", 9999.0))
	var rd_text := "∞" if rd >= 9999.0 else str(int(rd))
	h.add_child(res_chip("ui.icon_power", Loc.t("%+.1f kW · %d kWh") % [surplus, int(c.battery_kwh)], Loc.t("Strømbalance (produktion − forbrug) og batteri. Prioritet: livsstøtte, omsorg, vand/mad, produktion."), UiKit.OK if surplus >= 0 else UiKit.DANGER))
	h.add_child(res_chip("ui.icon_alloy", "%d" % int(c.inventory["alloy"]), Loc.t("Byggemateriale")))
	h.add_child(res_chip("ui.icon_components", "%d" % int(c.inventory["components"]), Loc.t("Komponenter (reservedele, vedligehold, moduler)")))
	h.add_child(res_chip("ui.icon_water", "%d" % int(c.inventory["water"]), Loc.t("Vand i persondøgn (+%.0f/dag)") % float(rep.get("produced", {}).get("water", 0.0))))
	h.add_child(res_chip("ui.icon_food", "%d" % int(c.inventory["food"]), Loc.t("Mad i persondøgn (+%.0f/dag)") % float(rep.get("produced", {}).get("food", 0.0))))
	h.add_child(res_chip("ui.icon_water", Loc.t("Reserve %s d") % rd_text, Loc.t("Dage, vand og mad rækker til den nuværende befolkning."), UiKit.WARN if rd < 30 else UiKit.TEXT))
	h.add_child(res_chip("ui.icon_population", "%d" % gs.population.alive_count(), Loc.t("Levende befolkning (kohorter)")))
	h.add_child(res_chip("ui.icon_embryo", UiKit.thousands(gs.ark.embryo_viable), Loc.t("Levedygtige embryoner (%d i inkubation, %d født)") % [gs.ark.embryo_incubating, gs.ark.embryo_born]))
	h.add_child(res_chip("ui.icon_fuel", Loc.t("Ark %d") % int(c.ark_fuel), Loc.t("Arkens brændstof til nødstrøm (%d kW). Slipper det op, mister kolonien arkens strøm.") % int(pw.get("ark_kw", 0))))
	return h


static func building_tooltip(sim: Simulation, def_id: String) -> String:
	var def := sim.content.building(def_id)
	var gs := sim.state
	var cost := sim.colony.build_cost(gs, def_id)
	var parts: Array = []
	for k: String in cost.keys():
		parts.append("%d %s" % [int(cost[k]), ColonySimulation._res_label(k)])
	var kw := float(def.get("power_kw", 0))
	var lines: Array = [str(def.get("name")), str(def.get("description", "")), Loc.t("Pris: ") + ", ".join(parts),
		Loc.t("Strøm: %+d kW%s") % [int(kw), Loc.t(" (afhænger af planeten)") if def.has("power_source") else ""],
		Loc.t("Byggearbejde: %d dronedage") % int(def.get("build_work", 0))]
	var out: Dictionary = DictUtil.get_dict(def, "output")
	for k: String in out.keys():
		lines.append(Loc.t("Producerer: %s %s/dag") % [str(out[k]), ColonySimulation._res_label(k)])
	var d := str(def.get("district", "any"))
	if d != "any":
		lines.append(Loc.t("Placering: ") + (Loc.t("boligzonen") if d == "living" else Loc.t("ressourceområdet")))
	lines.append(Loc.t("Prioritet: ") + Loc.t(str(ColonySimulation.PRIORITY_LABELS.get(str(def.get("priority")), ""))))
	return "\n".join(lines)


static func info_panel(sim: Simulation, bid: int, actions: Dictionary) -> PanelContainer:
	var gs := sim.state
	var b := gs.colony.building_by_id(bid)
	var p := UiKit.panel(Vector2(380, 0))
	if b.is_empty():
		return p
	var def := sim.content.building(str(b["def_id"]))
	var v := UiKit.vbox(6)
	v.add_child(UiKit.label(str(def.get("name")), 22, UiKit.AMBER))
	v.add_child(UiKit.label(str(def.get("description", "")), 14, UiKit.MUTED, true))
	var state := str(b["state"])
	if state == ColonyState.B_CONSTRUCTING:
		v.add_child(UiKit.label(Loc.t("Under opførelse: %d%%") % int(float(b["progress"]) * 100), 16, UiKit.AMBER))
		v.add_child(UiKit.bar(float(b["progress"]), 1.0, UiKit.AMBER))
	var hz := sim.colony.hazard_factors(gs, gs.campaign.colony_day)
	var kw := sim.colony.building_power_kw(gs, b, hz)
	v.add_child(UiKit.label(Loc.t("Strøm: %+.1f kW · %s · %s") % [kw, Loc.t("forbundet") if b.get("accessible") else Loc.t("IKKE forbundet"), Loc.t("strøm") if b.get("powered") else Loc.t("ingen strøm")], 15))
	if b["def_id"] != "ark_core":
		v.add_child(UiKit.label(Loc.t("Slid: %d%% · Effektivitet: %d%%") % [int(float(b.get("wear", 0.0)) / 60.0 * 100.0), int(float(b.get("efficiency", 1.0)) * 100.0)], 14, UiKit.MUTED))
	var reason := str(b.get("blocked_reason", ""))
	if not reason.is_empty() and reason != "constructing":
		v.add_child(UiKit.label("▲ " + Loc.t(str(ColonySimulation.REASONS.get(reason, reason))), 15, UiKit.WARN, true))
		v.add_child(UiKit.label(_fix_hint(reason), 14, UiKit.MUTED, true))
	if b["def_id"] == "ark_core":
		v.add_child(UiKit.label(Loc.t("Nødstrøm %d kW · Brændstof %d · Genbrugsmateriale tilbage %d") % [int(sim.colony.ark_power_kw(gs)), int(gs.colony.ark_fuel), int(gs.colony.salvage_left)], 14, UiKit.TEXT, true))
	var mods: Dictionary = DictUtil.get_dict(def, "modules")
	for m: String in mods.keys():
		if m in b.get("modules", []):
			v.add_child(UiKit.label(Loc.t("● %s installeret") % mods[m].get("name"), 14, UiKit.OK))
		elif state == ColonyState.B_ACTIVE:
			var c: Dictionary = mods[m].get("cost", {})
			var btn := UiKit.button(Loc.t("Tilføj %s (%d mat., %d komp., %+d kW)") % [mods[m].get("name"), int(c.get("alloy", 0)), int(c.get("components", 0)), int(mods[m].get("power_kw", 0))],
				func() -> void: actions["module"].call(bid, m), str(mods[m].get("description", "")))
			if sim.colony.requires_module(gs) == m:
				btn.text = "★ " + btn.text
				btn.tooltip_text += Loc.t("\nDenne planet kræver modulet, før habitatet er sikkert.")
			v.add_child(btn)
	if b["def_id"] == "care_center" and state == ColonyState.B_ACTIVE:
		var size := int(sim.content.bal("incubation.cohort_size", 10))
		var blockers := sim.population.incubation_blockers(gs, size)
		var ib := UiKit.button(Loc.t("Start inkubation (%d embryoner)") % size, func() -> void: actions["incubate"].call())
		ib.disabled = not blockers.is_empty()
		v.add_child(ib)
		for bl: Variant in blockers:
			v.add_child(UiKit.label("✕ " + str(bl), 14, UiKit.MUTED, true))
	if b["def_id"] == "school_hall" and state == ColonyState.B_ACTIVE and not gs.society.council_formed:
		var cb := sim.society.council_blockers(gs)
		var btn := UiKit.button(Loc.t("Saml koloniens første råd"), func() -> void: actions["council"].call())
		btn.disabled = not cb.is_empty()
		v.add_child(btn)
		for bl: Variant in cb:
			v.add_child(UiKit.label("✕ " + str(bl), 14, UiKit.MUTED, true))
	if b["def_id"] != "ark_core":
		var inv: Dictionary = DictUtil.get_dict(b, "invested")
		var frac := 1.0 if state == ColonyState.B_CONSTRUCTING and float(b["progress"]) <= 0.0 else float(sim.content.bal("demolish_refund", 0.5))
		var refund := int(float(inv.get("alloy", 0)) * frac)
		v.add_child(UiKit.button((Loc.t("Annullér (+%d mat.)") if frac >= 1.0 else Loc.t("Nedriv (+%d mat. tilbage)")) % refund, func() -> void: actions["demolish"].call(bid)))
	p.add_child(v)
	return p


static func _fix_hint(reason: String) -> String:
	match reason:
		"no_power": return Loc.t("Næste skridt: byg mere strøm (sol/geotermi) eller et batteri. Livsstøtte og omsorg får strøm først.")
		"no_access": return Loc.t("Næste skridt: placér en bygning eller dronehub, der forbinder den til nettet.")
		"no_workforce": return Loc.t("Næste skridt: byg en dronehub — eller vent på voksne kohorter.")
		"maintenance": return Loc.t("Næste skridt: skaf komponenter (værksted) så robotterne kan servicere.")
		"input_missing": return Loc.t("Næste skridt: sørg for råvarer (byggemateriale eller vand).")
		"module_missing": return Loc.t("Næste skridt: installér modulet, planeten kræver.")
	return ""

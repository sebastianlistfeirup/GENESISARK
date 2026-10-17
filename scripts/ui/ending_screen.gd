extends Control
## Epilogue (bible p.12, GA-25): the profile follows actual robustness and the
## council; text references planet, crises, people and institutions.

func _ready() -> void:
	theme = UiKit.theme()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	AudioService.set_ambience("")
	AudioService.set_music("music_hope")
	var bg := ColorRect.new()
	bg.color = UiKit.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	if not GameSession.has_game() or GameSession.state.campaign.ending_id.is_empty():
		DebugFixtures.prepare("grown:pelagos")
		GameSession.cmd_handover()
	var gs: GameState = GameSession.state
	var def: Dictionary = GameSession.content.endings.get(gs.campaign.ending_id, {})
	var col := UiKit.vbox(16)
	col.position = Vector2(160, 90)
	col.custom_minimum_size = Vector2(1100, 0)
	add_child(col)
	col.add_child(UiKit.label("EPILOG", 18, UiKit.PETROL.lightened(0.3)))
	col.add_child(UiKit.label(str(def.get("title", gs.campaign.ending_id)), 54, UiKit.TEXT))
	col.add_child(UiKit.label(str(def.get("summary", "")), 20, UiKit.AMBER, true))
	for para: String in GameSession.sim.endings.epilogue(gs):
		col.add_child(UiKit.label(para, 19, UiKit.TEXT, true))
	var m: Dictionary = gs.campaign.final_state
	col.add_child(UiKit.label("%d mennesker · %s · egen strøm %.0f / %.0f kW · reserve %s dage · %d kriser løst · kaptajnen i stasis i %d år" % [
		int(m.get("population", 0)), "råd" if m.get("council", false) else "intet råd", float(m.get("own_power_kw", 0)), float(m.get("demand_kw", 0)),
		"∞" if float(m.get("reserve_days", 0)) >= 9999 else str(int(float(m.get("reserve_days", 0)))), int(m.get("crises_resolved", 0)), int(gs.campaign.captain_stasis_years)], 15, UiKit.MUTED, true))
	var row := UiKit.hbox(12)
	row.add_child(UiKit.button("Hovedmenu", func() -> void: AppFlow.goto("menu")))
	var pre := UiKit.button("Fortsæt fra seneste save før overdragelsen", func() -> void:
		var r := GameSession.load_from("auto", true)
		if r["ok"]:
			AppFlow.continue_game())
	pre.tooltip_text = "Indlæser backuppen fra før slutningen."
	row.add_child(pre)
	col.add_child(row)

extends Node
## Scene flow: boot -> menu -> ship / flight / surface / colony -> ending.
## Fades between scenes; routes a loaded campaign to the scene its phase needs.

signal scene_changed(scene_key: String)

const SCENES := {
	"menu": "res://scenes/menu/main_menu.tscn",
	"ship": "res://scenes/ship/ship.tscn",
	"flight": "res://scenes/flight/flight.tscn",
	"surface": "res://scenes/surface/surface.tscn",
	"colony": "res://scenes/colony/colony.tscn",
	"ending": "res://scenes/story/ending.tscn",
	"riglab": "res://scenes/tests/RigLab.tscn",  # developer tool (GA-14)
	"fxlab": "res://scenes/tests/FxLab.tscn",  # developer tool: fx.* particle library
}

var current_key := ""
## Scene tests set this so gameplay code can request transitions without the
## test harness scene being replaced; the request is recorded instead.
var test_mode := false
var last_requested := ""
var params: Dictionary = {}
var _fade: ColorRect
var _card: VBoxContainer
var _card_title: Label
var _card_sub: Label
var _layer: CanvasLayer
var _busy := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_layer = CanvasLayer.new()
	_layer.layer = 100
	add_child(_layer)
	_fade = ColorRect.new()
	_fade.color = Color(0.02, 0.04, 0.06, 1.0)
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.modulate.a = 0.0
	_layer.add_child(_fade)
	# Location card shown while the screen is dark (a chapter break between scenes).
	_card = VBoxContainer.new()
	_card.set_anchors_preset(Control.PRESET_FULL_RECT)
	_card.alignment = BoxContainer.ALIGNMENT_CENTER
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.modulate.a = 0.0
	_layer.add_child(_card)
	_card_title = Label.new()
	_card_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_card_title.add_theme_font_size_override("font_size", 46)
	_card_title.add_theme_color_override("font_color", Color("e6f2f2"))
	_card.add_child(_card_title)
	var rule := ColorRect.new()
	rule.custom_minimum_size = Vector2(220, 2)
	rule.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	rule.color = Color("e8a33d")
	_card.add_child(rule)
	_card_sub = Label.new()
	_card_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_card_sub.add_theme_font_size_override("font_size", 18)
	_card_sub.add_theme_color_override("font_color", Color("8fd6d6"))
	_card.add_child(_card_sub)


func goto(key: String, p: Dictionary = {}) -> void:
	if _busy or not SCENES.has(key):
		return
	if test_mode:
		last_requested = key
		params = p
		return
	_busy = true
	params = p
	get_tree().paused = false
	var fast := bool(SettingsService.get_value("reduced_motion", false))
	var card := _card_text(key, p)
	_card_title.text = card[0]
	_card_sub.text = card[1]
	if not _card_title.has_theme_font_override("font"):
		var f: Font = load("res://art/fonts/zendots/ZenDots-Regular.ttf") if ResourceLoader.exists("res://art/fonts/zendots/ZenDots-Regular.ttf") else null
		if f:
			_card_title.add_theme_font_override("font", f)
	var t := create_tween()
	t.tween_property(_fade, "modulate:a", 1.0, 0.05 if fast else 0.35)
	if not card[0].is_empty() and not fast:
		t.tween_callback(AudioService.ui_soft.bind("ui_card_whoosh", -9.0, 1000))  # the location card sweeps in (D-064)
		t.tween_property(_card, "modulate:a", 1.0, 0.25)
		t.tween_interval(0.35)
	await t.finished
	GameSession.colony_clock_active = false
	AudioService.set_layer("")
	get_tree().change_scene_to_file(SCENES[key])
	current_key = key
	await get_tree().process_frame
	await get_tree().process_frame
	var t2 := create_tween()
	t2.tween_property(_card, "modulate:a", 0.0, 0.05 if fast else 0.3)
	t2.tween_property(_fade, "modulate:a", 0.0, 0.05 if fast else 0.45)
	_busy = false
	scene_changed.emit(key)


## Rebuilds the current scene in place (used after a language change).
func reload_current() -> void:
	goto(current_key if not current_key.is_empty() else "menu", params)


## Where a campaign in its current phase belongs.
func scene_for_state() -> String:
	if not GameSession.has_game():
		return "menu"
	var gs: GameState = GameSession.state
	match gs.campaign.phase:
		CampaignState.PHASE_SETTLED:
			return "colony"
		CampaignState.PHASE_ENDED:
			return "ending"
		_:
			if gs.expedition != null and gs.expedition.status == ExpeditionState.STATUS_ACTIVE:
				return "surface"
			if not gs.campaign.pending_approach.is_empty():
				return "flight"  # saved mid-approach: fly it (or let NAV fly it)
			return "ship"


func continue_game() -> void:
	goto(scene_for_state())


## [title, subtitle] for the location card of a transition ("" = no card).
func _card_text(key: String, p: Dictionary) -> Array:
	if not GameSession.has_game() or key in ["menu", "riglab", "fxlab"]:
		return ["", ""]
	var gs: GameState = GameSession.state
	var pname := ""
	match key:
		"ship":
			return [Loc.t("THE ARK"), Loc.t("Day %d of the voyage") % gs.campaign.elapsed_days]
		"flight":
			var dest := str(p.get("destination", ""))
			pname = str(GameSession.content.planet(dest).get("name", dest)) if not dest.is_empty() else ""
			return [pname.to_upper(), Loc.t("Approach")]
		"surface":
			if gs.expedition:
				pname = str(GameSession.content.planet(gs.expedition.planet_id).get("name", ""))
			return [pname.to_upper(), Loc.t("Expedition")]
		"colony":
			if gs.colony:
				pname = str(GameSession.content.planet(gs.colony.planet_id).get("name", ""))
			return [pname.to_upper(), Loc.t("Colony · year %d") % int(gs.campaign.colony_year())]
		"ending":
			return [Loc.t("EPILOGUE"), ""]
	return ["", ""]

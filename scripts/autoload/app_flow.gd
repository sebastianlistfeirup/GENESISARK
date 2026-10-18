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
	var t := create_tween()
	t.tween_property(_fade, "modulate:a", 1.0, 0.05 if fast else 0.35)
	await t.finished
	GameSession.colony_clock_active = false
	AudioService.set_layer("")
	get_tree().change_scene_to_file(SCENES[key])
	current_key = key
	await get_tree().process_frame
	await get_tree().process_frame
	var t2 := create_tween()
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

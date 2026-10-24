class_name StoryPlayer
extends CanvasLayer
## Plays short hand-written scenes as subtitles with speaker names (bible p.13:
## subtitles work without voice; size is adjustable). Non-blocking by default.

var blocking := false
var _queue: Array = []
var _box: PanelContainer
var _speaker: Label
var _text: Label
var _timer := 0.0
var _lines: Array = []
var _index := 0
var _scene_id := ""
## Lines still unsaid when the scene changed (the expedition's "hatch closes" on the
## climb to orbit, the landing order as the colony loads): the next scene's player
## picks them up instead of the subtitles vanishing mid-scene.
static var _carry: Array = []
static var _carry_state := 0
static var _carry_ms := 0


func _ready() -> void:
	layer = 20
	# Pausable: a line (and its voice) holds while the pause menu is open instead of
	# running out unseen behind it; the box steps aside meanwhile.
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_box = UiKit.panel()
	_box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_box.position.y -= 110
	_box.custom_minimum_size = Vector2(900, 0)
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var v := UiKit.vbox(2)
	_speaker = UiKit.label("", 16, UiKit.AMBER)
	_speaker.add_theme_font_override("font", UiKit.display_variant(2))
	_text = UiKit.label("", 22, UiKit.TEXT, true)
	_text.custom_minimum_size = Vector2(860, 0)
	v.add_child(_speaker)
	v.add_child(_text)
	_box.add_child(v)
	_box.visible = false
	add_child(_box)
	_resume_carry()  # before the new scene's own triggers: the interrupted lines come first


func _notification(what: int) -> void:
	if _box and (what == NOTIFICATION_PAUSED or what == NOTIFICATION_UNPAUSED):
		_box.modulate.a = 0.0 if what == NOTIFICATION_PAUSED else 1.0


func _exit_tree() -> void:
	if not is_playing() or AppFlow.test_mode or not GameSession.has_game():
		return
	var rest: Array = [{"id": _scene_id, "lines": _lines, "start": _index}]
	rest.append_array(_queue)
	_carry = rest
	_carry_state = GameSession.state.get_instance_id()
	_carry_ms = Time.get_ticks_msec()


## Same campaign, a moment ago: carry on where the last scene's player stopped
## (the interrupted line starts over, with its voice).
func _resume_carry() -> void:
	if _carry.is_empty():
		return
	var rest := _carry
	_carry = []
	if not GameSession.has_game() or GameSession.state.get_instance_id() != _carry_state or Time.get_ticks_msec() - _carry_ms > 15000:
		return
	for sc: Dictionary in rest:
		play_scene(sc)


## Moves the subtitle box up by `px` (more when a scene's bottom bar grows).
func shift_up(px: float) -> void:
	_box.position.y -= px


func play_scene(scene: Dictionary) -> void:
	_queue.append(scene)
	if _lines.is_empty():
		_next_scene()


func _next_scene() -> void:
	if _queue.is_empty():
		_lines = []
		_box.visible = false
		return
	var sc: Dictionary = _queue.pop_front()
	_scene_id = str(sc.get("id", ""))
	_lines = DictUtil.get_arr(sc, "lines")
	_index = int(sc.get("start", 0))
	_show_line()


func _show_line() -> void:
	if _index >= _lines.size():
		_next_scene()
		return
	var line: Dictionary = _lines[_index]
	var sp := str(line.get("speaker", ""))
	var name := sp
	if sp == "CAPTAIN":
		name = Loc.t("The captain")
	elif sp == "NARRATOR":
		name = ""
	elif GameSession.content and GameSession.content.characters.has(sp):
		name = str(GameSession.content.characters[sp].get("name", sp))
	_speaker.text = name.to_upper()
	_speaker.visible = not name.is_empty()
	_text.text = str(line.get("text", ""))
	var size := int(SettingsService.get_value("subtitle_size", 22))
	_text.add_theme_font_size_override("font_size", size)
	_speaker.add_theme_font_size_override("font_size", maxi(14, size - 6))  # the speaker scales with the subtitle
	_box.visible = bool(SettingsService.get_value("subtitles", true)) or sp != "NARRATOR"
	_timer = clampf(2.0 + _text.text.length() * 0.055, 3.0, 9.0)
	# Line id = "<scene id>_<two-digit index>", matching docs/VO_SCRIPT.csv.
	var vo := AudioService.play_voice("%s_%02d" % [_scene_id, _index + 1])
	if vo > 0.0:
		_timer = maxf(_timer, vo + 0.4)


func _process(delta: float) -> void:
	if _lines.is_empty():
		return
	_timer -= delta
	if _timer <= 0.0:
		_index += 1
		_show_line()


func skip_line() -> void:
	if not _lines.is_empty():
		AudioService.stop_voice()
		_index += 1
		_show_line()


func is_playing() -> bool:
	return not _lines.is_empty()


func _unhandled_input(event: InputEvent) -> void:
	if is_playing() and event.is_action_pressed("skip_line"):
		skip_line()
		get_viewport().set_input_as_handled()

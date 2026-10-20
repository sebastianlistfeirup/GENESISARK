class_name NavComms
extends PanelContainer
## NAV's channel: short, dry status lines from the navigation computer
## (NavAdvisor items: {id, severity, speaker, text}). Typed out like a terminal,
## queued, never spammed: the same line id is not repeated within REPEAT_S, and a
## critical line interrupts whatever is showing. Voice: assets/audio/vo/nav_<id>.ogg
## if it exists, otherwise a short computer tick. Text is the subtitle (always on).

const CHARS_PER_S := 70.0
const HOLD_S := 3.2
const REPEAT_S := 8.0

var _label: RichTextLabel
var _queue: Array = []
var _current: Dictionary = {}
var _shown := 0.0
var _hold := 0.0
var _last_said: Dictionary = {}  # id -> time
var _t := 0.0


func _ready() -> void:
	custom_minimum_size = Vector2(460, 0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.02, 0.05, 0.06, 0.82)
	sb.border_color = UiKit.PETROL
	sb.border_width_left = 3
	sb.set_content_margin_all(12)
	add_theme_stylebox_override("panel", sb)
	_label = RichTextLabel.new()
	_label.bbcode_enabled = true
	_label.fit_content = true
	_label.scroll_active = false
	_label.custom_minimum_size = Vector2(440, 0)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_apply_size()
	SettingsService.changed.connect(_apply_size)
	add_child(_label)
	visible = false


## NAV is a subtitle channel: it follows the subtitle size setting (default 22 -> 17).
func _apply_size() -> void:
	var s := maxi(14, int(SettingsService.get_value("subtitle_size", 22)) - 5)
	_label.add_theme_font_size_override("normal_font_size", s)
	_label.add_theme_font_size_override("bold_font_size", s)


## Queue a NAV line. Critical lines go first and cut the current line short.
func say(item: Dictionary) -> void:
	var id := str(item.get("id", ""))
	if _last_said.has(id) and _t - float(_last_said[id]) < REPEAT_S and id != "impact" and id != "impact_severe":
		return
	_last_said[id] = _t
	if str(item.get("severity", "")) == "critical":
		_queue.push_front(item)
		if not _current.is_empty() and str(_current.get("severity", "")) != "critical":
			_hold = 0.0
			_shown = 1e9
	else:
		_queue.append(item)


func busy() -> bool:
	return not _current.is_empty() or not _queue.is_empty()


func _process(delta: float) -> void:
	_t += delta
	if _current.is_empty():
		if _queue.is_empty():
			visible = false
			return
		_current = _queue.pop_front()
		_shown = 0.0
		_hold = HOLD_S + str(_current.get("text", "")).length() / 40.0
		visible = true
		if AudioService.play_voice("nav_" + str(_current.get("id", ""))) <= 0.0:
			AudioService.ui("ui_hover")
	var text := str(_current.get("text", ""))
	if _shown < text.length():
		var fast := bool(SettingsService.get_value("reduced_motion", false))
		_shown = text.length() if fast else _shown + CHARS_PER_S * delta
	else:
		_hold -= delta
		if _hold <= 0.0:
			_current = {}
			return
	var col: String = {"critical": "#d25b4c", "warning": "#e8a33d"}.get(str(_current.get("severity", "")), "#7fd6d0")
	var sev := str(_current.get("severity", ""))
	var icon := (UiKit.status_icon(sev) + " ") if sev in ["critical", "warning"] else ""
	_label.text = "[color=%s][b]%sNAV[/b][/color]  %s" % [col, icon, text.substr(0, int(_shown))]

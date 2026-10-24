class_name CountUpLabel
extends Label
## A number that counts up to its value when it enters the screen (D-055):
## ease-out over `seconds`, formatted by `formatter` (default: thousands
## grouping via Loc). With reduced motion it shows the final value at once.
## The final text is set immediately for accessibility/tests (`text` is the
## real value after the count); `prefix`/`suffix` frame the number ("%", " fuel").
##   var n := CountUpLabel.make(50000, 96); n.add_theme_font_override("font", Holo.name_font())

var value := 0.0
var from_value := 0.0
var seconds := 0.9
var decimals := 0
var prefix := ""
var suffix := ""
var formatter := Callable()
var _shown := 0.0


static func make(v: float, fs: int = 24, col: Color = UiKit.TEXT, suffix_text: String = "") -> CountUpLabel:
	var l := CountUpLabel.new()
	l.value = v
	l.suffix = suffix_text
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", col)
	l.add_theme_font_override("font", UiKit.display_font())
	l.text = l._fmt(v)
	return l


func _ready() -> void:
	# Reserve the final width, so the layout does not jitter while counting.
	var f := get_theme_font("font")
	if f:
		var w := f.get_string_size(_fmt(value), HORIZONTAL_ALIGNMENT_LEFT, -1, get_theme_font_size("font_size")).x
		custom_minimum_size.x = maxf(custom_minimum_size.x, ceilf(w) + 2.0)
	if HoloAnim.calm() or is_equal_approx(from_value, value):
		_set_shown(value)
		return
	_set_shown(from_value)
	var tw := create_tween()
	tw.tween_interval(0.15)
	tw.tween_method(_set_shown, from_value, value, seconds).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)


## Animates from the shown number to a new value.
func count_to(v: float) -> void:
	var start := _shown
	value = v
	if HoloAnim.calm() or not is_inside_tree():
		_set_shown(v)
		return
	create_tween().tween_method(_set_shown, start, v, seconds * 0.6).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _set_shown(v: float) -> void:
	_shown = v
	text = _fmt(v)


func _fmt(v: float) -> String:
	if formatter.is_valid():
		return prefix + str(formatter.call(v)) + suffix
	if decimals > 0:
		return prefix + (("%." + str(decimals) + "f") % v) + suffix
	return prefix + UiKit.thousands(int(roundf(v))) + suffix

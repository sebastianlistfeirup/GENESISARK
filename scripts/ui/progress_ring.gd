class_name ProgressRing
extends Control
## Circular gauge (D-055): a dark segmented track, the filled arc with a soft
## glow and a bright head, tick marks outside and, inside, a count-up value
## over a caption. The arc fills when shown (static with reduced motion).
## The value text always states the number, so colour is never the only cue.
##   var g := ProgressRing.make(0.97, "97%", Loc.t("Hull"), UiKit.OK, 120)

var frac := 0.0
var col := UiKit.PETROL
var _shown := 0.0
var _t := 0.0
var value_label: Label
var caption_label: Label


## `value` is the text in the middle (a CountUpLabel when `count` is given).
static func make(fraction: float, value_text: String, caption: String, colour: Color, px: int = 120, count: float = NAN, suffix: String = "") -> ProgressRing:
	var g := ProgressRing.new()
	g.frac = clampf(fraction, 0.0, 1.0)
	g.col = colour
	g.custom_minimum_size = Vector2(px, px + 22)
	g.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# The value sits inside the ring, the caption under it.
	var v := VBoxContainer.new()
	v.anchor_right = 1.0
	v.offset_bottom = px
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fs := int(px * 0.19)
	if not is_nan(count):
		g.value_label = CountUpLabel.make(count, fs, Color.WHITE, suffix)
	else:
		g.value_label = Holo.value_label(value_text, fs, Color.WHITE)
	g.value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(g.value_label)
	g.add_child(v)
	g.caption_label = UiKit.label(caption.to_upper(), 12, colour.lightened(0.35))
	g.caption_label.add_theme_font_override("font", UiKit.display_variant(2))
	g.caption_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	g.caption_label.anchor_right = 1.0
	g.caption_label.offset_top = px + 2
	g.caption_label.offset_bottom = px + 20
	g.add_child(g.caption_label)
	return g


func _ready() -> void:
	if HoloAnim.calm():
		_shown = frac
	else:
		var tw := create_tween()
		tw.tween_interval(0.15)
		tw.tween_property(self, "_shown", frac, 1.0).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	set_process(not HoloAnim.calm())


func _process(delta: float) -> void:
	if is_visible_in_tree():
		_t += delta
		queue_redraw()


func _draw() -> void:
	var side := minf(size.x, size.y - 22.0)
	var c := Vector2(size.x * 0.5, side * 0.5)
	var r := side * 0.5 - 8.0
	var w := maxf(5.0, r * 0.13)
	var start := -PI * 0.5
	# Ticks outside the track.
	for i: int in 40:
		var a := TAU * i / 40.0
		var lit := _shown > 0.001 and float(i) / 40.0 < _shown
		var l := 4.0 if i % 5 != 0 else 7.0
		draw_line(c + Vector2.from_angle(a + start) * (r + 4.0), c + Vector2.from_angle(a + start) * (r + 4.0 + l), Color(col if lit else UiKit.PETROL_D.lightened(0.2), 0.8 if lit else 0.5), 1.5)
	# Track: segmented dark ring.
	for i: int in 24:
		var a0 := start + TAU * i / 24.0 + 0.02
		draw_arc(c, r - w * 0.5, a0, a0 + TAU / 24.0 - 0.04, 6, Color(0.02, 0.05, 0.07, 0.95), w, true)
	if _shown > 0.001:
		var end := start + TAU * _shown
		draw_arc(c, r - w * 0.5, start, end, 64, Color(col, 0.22), w * 2.2, true)  # glow
		draw_arc(c, r - w * 0.5, start, end, 64, col, w, true)
		draw_arc(c, r - w * 0.5, start, end, 64, Color(col.lightened(0.5), 0.8), maxf(1.0, w * 0.25), true)
		var head := c + Vector2.from_angle(end) * (r - w * 0.5)
		var p := 0.5 + 0.5 * sin(_t * 3.0)
		draw_circle(head, w * (0.9 + 0.3 * p), Color(col.lightened(0.6), 0.9))
	# Inner hairline that turns slowly.
	draw_arc(c, r - w - 6.0, _t * 0.4, _t * 0.4 + PI * 1.4, 48, Color(col, 0.35), 1.0, true)

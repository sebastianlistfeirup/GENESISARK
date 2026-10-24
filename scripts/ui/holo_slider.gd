class_name HoloSlider
extends HSlider
## A big readable slider for the settings (D-059): a thick dark track, the
## filled part glowing petrol with a soft halo, tick marks under the track
## (major ticks at both ends and the middle) and the theme's amber knob.
## Arrow keys / d-pad step it like any HSlider; focus draws the amber outline.
## The value is always also shown as text next to it (HoloForm.slider_row).
##   var s := HoloSlider.make(0.0, 1.0, 0.05, 0.8)

var col := UiKit.PETROL.lightened(0.15)


static func make(lo: float, hi: float, step_v: float, v: float, w: float = 300.0) -> HoloSlider:
	var s := HoloSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step_v
	s.value = v
	s.custom_minimum_size = Vector2(w, 34)
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.focus_mode = Control.FOCUS_ALL
	s._styles()
	s.value_changed.connect(func(_v: float) -> void: s.queue_redraw())
	return s


func _styles() -> void:
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0.02, 0.05, 0.07, 0.95)
	track.border_color = Color(UiKit.PETROL.lerp(UiKit.MUTED, 0.4), 0.45)
	track.set_border_width_all(1)
	track.set_corner_radius_all(5)
	track.content_margin_top = 5
	track.content_margin_bottom = 5
	var fill := StyleBoxFlat.new()
	fill.bg_color = col
	fill.set_corner_radius_all(5)
	fill.content_margin_top = 5
	fill.content_margin_bottom = 5
	fill.shadow_color = Color(col, 0.45)
	fill.shadow_size = 6
	var hi := fill.duplicate() as StyleBoxFlat
	hi.bg_color = col.lightened(0.25)
	hi.shadow_size = 9
	add_theme_stylebox_override("slider", track)
	add_theme_stylebox_override("grabber_area", fill)
	add_theme_stylebox_override("grabber_area_highlight", hi)
	var foc := StyleBoxFlat.new()
	foc.draw_center = false
	foc.border_color = UiKit.AMBER
	foc.set_border_width_all(2)
	foc.set_corner_radius_all(8)
	foc.set_expand_margin_all(4)
	add_theme_stylebox_override("focus", foc)


func _draw() -> void:
	# Ticks under the track: 11 marks, the ends and the middle taller.
	var y := size.y * 0.5 + 9.0
	var x0 := 6.0
	var x1 := size.x - 6.0
	var frac := (value - min_value) / maxf(max_value - min_value, 0.0001)
	for i: int in 11:
		var t := i / 10.0
		var x := lerpf(x0, x1, t)
		var major := i == 0 or i == 5 or i == 10
		var on := t <= frac + 0.001
		draw_line(Vector2(x, y), Vector2(x, y + (5.0 if major else 3.0)), Color(col.lightened(0.3) if on else UiKit.MUTED, 0.75 if on else 0.35), 1.0)

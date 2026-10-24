class_name HoloBanner
extends PanelContainer
## The dramatic header strip of a dialog (D-059): a dark plate washed in the
## dialog's colour from the left, slow scan lines, a huge faint glyph on the
## right as the "illustration", hazard stripes along the left edge when it is
## critical, and in front a big badge in turning rings, a kind chip, the title
## in the display face and a sub line. Static with reduced motion.
##   var b := HoloBanner.make("ui.icon_critical", Loc.t("Crisis"), title, sub, UiKit.DANGER, true)

var col := UiKit.AMBER
var glyph: Texture2D
var hazard := false
var _t := 0.0


static func make(icon_slot: String, kind: String, title: String, sub: String, colour: Color, critical: bool = false, chips: Array = []) -> HoloBanner:
	var b := HoloBanner.new()
	b.col = colour
	b.hazard = critical
	b.glyph = SyntySkin.icon(icon_slot, 256)
	b.custom_minimum_size = Vector2(0, 118)
	b.clip_contents = true
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.015, 0.03, 0.045, 0.95)
	sb.border_color = Color(colour, 0.55)
	sb.border_width_bottom = 2
	sb.corner_radius_top_right = 14
	sb.corner_radius_bottom_left = 4
	sb.content_margin_left = 22 if not critical else 34
	sb.content_margin_right = 18
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	b.add_theme_stylebox_override("panel", sb)
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var h := UiKit.hbox(18)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var badge := Control.new()
	badge.custom_minimum_size = Vector2(88, 88)
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var ring := HoloRing.new()
	ring.set_anchors_preset(Control.PRESET_FULL_RECT)
	ring.add_layer("Ring_Small_06", 1.0, 0.25, Color(colour.lightened(0.3), 0.55), 8)
	ring.add_layer("Ring_Medium_05", 0.82, -0.4, Color(colour, 0.35), 5)
	badge.add_child(ring)
	var ib := IconBadge.make(icon_slot, 58, colour, false, "!" if critical else "◆")
	ib.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	ib.grow_horizontal = Control.GROW_DIRECTION_BOTH
	ib.grow_vertical = Control.GROW_DIRECTION_BOTH
	badge.add_child(ib)
	h.add_child(badge)
	var v := UiKit.vbox(2)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cr := UiKit.hbox(6)
	cr.add_child(Holo.chip(kind, colour, "", 12))
	for c: Array in chips:
		cr.add_child(Holo.chip(str(c[1]), c[2] if c.size() > 2 else UiKit.PETROL.lightened(0.35), str(c[0]), 12))
	v.add_child(cr)
	var t := UiKit.label(title.to_upper(), 30, Color.WHITE, true)
	t.add_theme_font_override("font", Holo.name_font())
	t.add_theme_color_override("font_shadow_color", Color(colour, 0.45))
	t.add_theme_constant_override("shadow_outline_size", 10)
	t.add_theme_constant_override("shadow_offset_x", 0)
	t.add_theme_constant_override("shadow_offset_y", 0)
	v.add_child(t)
	if not sub.is_empty():
		v.add_child(UiKit.label(sub, 15, colour.lightened(0.45), true))
	h.add_child(v)
	b.add_child(h)
	return b


func _ready() -> void:
	set_process(not UiKit.calm())


func _process(delta: float) -> void:
	if is_visible_in_tree():
		_t += delta
		queue_redraw()


func _draw() -> void:
	var s := size
	# Colour wash from the left, fading out.
	var steps := 24
	for i: int in steps:
		var x0 := s.x * i / steps
		var a := 0.32 * pow(1.0 - float(i) / steps, 1.6)
		draw_rect(Rect2(x0, 0, s.x / steps + 1.0, s.y), Color(col.darkened(0.3), a), true)
	# The illustration: a huge faint glyph on the right, slowly breathing.
	if glyph:
		var gh := s.y * 1.5
		var br := 0.10 + 0.03 * sin(_t * 1.3)
		draw_texture_rect(glyph, Rect2(s.x - gh * 0.95, (s.y - gh) * 0.5, gh, gh), false, Color(col.lightened(0.2), br))
	# Scan lines drifting down.
	var off := fmod(_t * 18.0, 6.0)
	var y := off
	while y < s.y:
		draw_line(Vector2(0, y), Vector2(s.x, y), Color(1, 1, 1, 0.025), 1.0)
		y += 6.0
	if hazard:  # amber/black hazard stripes along the left edge
		var w := 14.0
		draw_rect(Rect2(0, 0, w, s.y), Color(0.05, 0.05, 0.05, 0.9), true)
		var k := -s.y
		while k < s.y:
			var pts := PackedVector2Array([Vector2(0, k), Vector2(w, k - w), Vector2(w, k - w + 9), Vector2(0, k + 9)])
			draw_colored_polygon(pts, Color(col, 0.85))
			k += 18.0
	draw_line(Vector2(0, s.y - 1), Vector2(s.x * (0.6 + 0.4 * (0.5 + 0.5 * sin(_t * 0.9))), s.y - 1), Color(col.lightened(0.4), 0.8), 2.0)

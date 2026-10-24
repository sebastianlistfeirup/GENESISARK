class_name IconBadge
extends Control
## Hexagon badge with a glyph (D-055): a dark hex plate, a tinted hex outline,
## the Synty glyph in the middle and, if `spin`, a thin dashed ring turning
## slowly around it (panel headers, stat tiles, readouts). Without the packs
## the hexagon is drawn in code and the glyph becomes `fallback` text.
##   IconBadge.make("stat.gravity", 34, UiKit.AMBER, true)

var icon_slot := ""
var tint := UiKit.AMBER
var spin := false
var fallback := "◆"
var locked := false  # dims the glyph and draws diagonal hatching (unknown values)
var _icon: Texture2D
var _ring: Texture2D
var _hex: Texture2D
var _hex_bg: Texture2D
var _a := 0.0


static func make(slot: String, px: int = 40, col: Color = UiKit.AMBER, spinning: bool = false, fallback_text: String = "◆") -> IconBadge:
	var b := IconBadge.new()
	b.icon_slot = slot
	b.tint = col
	b.spin = spinning
	b.fallback = fallback_text
	b.custom_minimum_size = Vector2(px, px)
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return b


func _ready() -> void:
	var px := int(maxf(custom_minimum_size.x, 16.0))
	_icon = SyntySkin.icon(icon_slot, maxi(32, px * 2))
	_hex = Holo.tex(Holo.SFM + "Frame_Hexagon_01.png", px * 2)
	_hex_bg = Holo.tex(Holo.SFM + "Frame_Hexagon_01_Background.png", px * 2)
	if spin:
		_ring = Holo.tex(Holo.GEN + "Ring_Small_06.png", px * 3)
	_a = randf() * TAU
	set_process(spin and not HoloAnim.calm())


func set_icon(slot: String, col: Color) -> void:
	icon_slot = slot
	tint = col
	_icon = SyntySkin.icon(slot, maxi(32, int(custom_minimum_size.x) * 2))
	queue_redraw()


func _process(delta: float) -> void:
	if is_visible_in_tree():
		_a += delta * 0.6
		queue_redraw()


func _draw() -> void:
	var s := size
	var c := s * 0.5
	var r := minf(s.x, s.y) * 0.5
	if _ring:
		var rr := r * 1.42
		draw_set_transform(c, _a, Vector2.ONE)
		draw_texture_rect(_ring, Rect2(-Vector2.ONE * rr, Vector2.ONE * rr * 2.0), false, Color(tint, 0.55))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	elif spin:
		for i: int in 3:
			var a0 := _a + TAU * i / 3.0
			draw_arc(c, r * 1.25, a0, a0 + 1.2, 12, Color(tint, 0.5), 1.5, true)
	if _hex and _hex_bg:
		var rect := Rect2(c - Vector2.ONE * r, Vector2.ONE * r * 2.0)
		draw_texture_rect(_hex_bg, rect, false, Color(UiKit.PANEL.darkened(0.45), 0.95))
		draw_texture_rect(_hex, rect, false, Color(tint.lerp(Color.WHITE, 0.35), 0.9 if not locked else 0.45))
	else:
		var pts := PackedVector2Array()
		for i: int in 6:
			pts.append(c + Vector2.from_angle(TAU * i / 6.0 + PI / 6.0) * r * 0.96)
		draw_colored_polygon(pts, Color(UiKit.PANEL.darkened(0.45), 0.95))
		pts.append(pts[0])
		draw_polyline(pts, Color(tint, 0.9 if not locked else 0.45), 1.5, true)
	if locked:
		for i: int in 5:
			var x := -r + i * r * 0.5
			draw_line(c + Vector2(x - r * 0.3, r * 0.5), c + Vector2(x + r * 0.3, -r * 0.5), Color(UiKit.MUTED, 0.18), 2.0)
	var col := tint.lightened(0.25) if not locked else Color(UiKit.MUTED, 0.8)
	if _icon:
		var ir := r * 0.98
		draw_texture_rect(_icon, Rect2(c - Vector2.ONE * ir * 0.5, Vector2.ONE * ir), false, col)
	else:
		var font := get_theme_default_font()
		var fs := int(r * 0.9)
		var w := font.get_string_size(fallback, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		draw_string(font, c + Vector2(-w.x * 0.5, fs * 0.35), fallback, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)

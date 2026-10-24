class_name DescentHud
extends Control
## Flight instruments for PlanetDescent: an altitude ladder from orbit to the
## ground (log scale, bands for space / entry / cloud deck / descent) with the
## lander's marker, and a chevron at the screen edge pointing to the landing site
## whenever it is off-screen. Drawn, no textures; shape + colour + text (a11y).

var alt := 0.0
var max_alt := 5200.0
var switch_alt := 1250.0
var site_px := Vector2.ZERO
var site_on_screen := true
var site_text := ""

const BAND_SPACE := Color("8a6cff")
const BAND_ENTRY := Color("ff8a3d")
const BAND_CLOUD := Color("e6f2f2")
const BAND_AIR := Color("1f8a8a")


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _y_for(a: float, top: float, bottom: float) -> float:
	var k := log(1.0 + maxf(a, 0.0)) / log(1.0 + max_alt)
	return lerpf(bottom, top, clampf(k, 0.0, 1.0))


func _draw() -> void:
	var vs := size
	var font := UiKit.body_font()
	# Altitude ladder on the right edge.
	var x := vs.x - 64.0
	var top := vs.y * 0.2
	var bottom := vs.y * 0.78
	var bands := [[max_alt, 1900.0, BAND_SPACE], [1900.0, switch_alt + 200.0, BAND_ENTRY], [switch_alt + 200.0, switch_alt - 200.0, BAND_CLOUD], [switch_alt - 200.0, 0.0, BAND_AIR]]
	for b: Array in bands:
		var y0 := _y_for(float(b[0]), top, bottom)
		var y1 := _y_for(float(b[1]), top, bottom)
		draw_rect(Rect2(x, y0, 6.0, y1 - y0), Color(b[2] as Color, 0.75))
	draw_rect(Rect2(x - 2.0, top - 2.0, 10.0, bottom - top + 4.0), Color(0.02, 0.05, 0.06, 0.6), false, 2.0)
	for mark: Array in [[max_alt, Loc.t("ORBIT")], [switch_alt, Loc.t("CLOUDS")], [0.0, Loc.t("GROUND")]]:
		var y := _y_for(float(mark[0]), top, bottom)
		draw_line(Vector2(x - 8.0, y), Vector2(x, y), Color(1, 1, 1, 0.7), 2.0)
		draw_string(font, Vector2(x - 12.0 - font.get_string_size(str(mark[1]), HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x, y + 5.0), str(mark[1]), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.9, 0.95, 0.97, 0.85))
	var ya := _y_for(alt, top, bottom)
	var tri := PackedVector2Array([Vector2(x + 10.0, ya), Vector2(x + 24.0, ya - 8.0), Vector2(x + 24.0, ya + 8.0)])
	draw_colored_polygon(tri, UiKit.AMBER)
	# Landing site pointer when it is out of view.
	if not site_on_screen:
		var c := vs * 0.5
		var d := (site_px - c)
		if d.length() < 1.0:
			d = Vector2.DOWN
		var dir := d.normalized()
		var r := minf(vs.x, vs.y) * 0.42
		var p := c + dir * r
		var ang := dir.angle()
		var pts := PackedVector2Array([Vector2(18, 0), Vector2(-10, -12), Vector2(-4, 0), Vector2(-10, 12)])
		var out := PackedVector2Array()
		for q: Vector2 in pts:
			out.append(p + q.rotated(ang))
		draw_colored_polygon(out, UiKit.AMBER)
		draw_polyline(out + PackedVector2Array([out[0]]), Color(0.02, 0.05, 0.06, 0.9), 2.0)
		if not site_text.is_empty():
			var ts := font.get_string_size(site_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14)
			draw_string(font, p - dir * 34.0 - Vector2(ts.x * 0.5, -5.0), site_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UiKit.AMBER)

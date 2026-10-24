class_name LedgerStrip
extends Control
## The embryo ledger as one gauge strip over all 50,000 (D-059): viable,
## in incubation, born and lost share the width by count; a non-zero part
## always keeps a sliver so it never disappears; ticks every tenth. The strip
## grows in from the left when shown (drawn final with reduced motion).
## `LedgerStrip.panel(ledger)` adds the counters above it (colour swatch +
## caption + count each), so the numbers are always there as text.
##   body.add_child(LedgerStrip.panel(gs.ark.ledger(), gs.ark.embryo_sum()))

var parts: Array = []  # [[count, Color], ...]
var _k := 0.0


static func colors() -> Array:
	return [["viable", Loc.t("Viable"), UiKit.PETROL.lightened(0.3)], ["incubating", Loc.t("In incubation"), UiKit.AMBER],
		["born", Loc.t("Born"), UiKit.FOOD], ["lost", Loc.t("Lost"), UiKit.DANGER]]


static func make(ledger: Dictionary, h: float = 22.0) -> LedgerStrip:
	var s := LedgerStrip.new()
	for c: Array in colors():
		s.parts.append([float(ledger.get(c[0], 0)), c[2]])
	s.custom_minimum_size = Vector2(0, h)
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return s


## Glass card: badge + total, the four counters, the strip under them.
static func panel(ledger: Dictionary, total: int, compact: bool = false) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.02, 0.05, 0.07, 0.7)
	sb.border_color = Color(UiKit.PETROL.lerp(UiKit.MUTED, 0.5), 0.2)
	sb.set_border_width_all(1)
	sb.corner_radius_top_right = 12
	sb.corner_radius_bottom_left = 12
	sb.set_content_margin_all(12)
	p.add_theme_stylebox_override("panel", sb)
	var v := UiKit.vbox(8)
	var top := HFlowContainer.new()
	top.add_theme_constant_override("h_separation", 18)
	top.add_theme_constant_override("v_separation", 6)
	var head := UiKit.hbox(10)
	head.add_child(IconBadge.make("ui.icon_embryo", 34, UiKit.AMBER, true, "◆"))
	var cap := UiKit.vbox(-2)
	var c1 := UiKit.label(Loc.t("Embryo ledger").to_upper(), 12, UiKit.MUTED)
	c1.add_theme_font_override("font", UiKit.display_variant(2))
	cap.add_child(c1)
	var tl := CountUpLabel.make(total, 22 if compact else 26, Color.WHITE)
	tl.add_theme_font_override("font", Holo.name_font())
	cap.add_child(tl)
	head.add_child(cap)
	head.custom_minimum_size = Vector2(0 if compact else 260, 0)
	top.add_child(head)
	for c: Array in colors():
		var r := UiKit.hbox(8)
		var sw := ColorRect.new()
		sw.color = c[2]
		sw.custom_minimum_size = Vector2(4, 36)
		r.add_child(sw)
		var cv := UiKit.vbox(-2)
		var cl := UiKit.label(str(c[1]).to_upper(), 11, UiKit.MUTED)
		cl.add_theme_font_override("font", UiKit.display_variant(1))
		cv.add_child(cl)
		var n := CountUpLabel.make(int(ledger.get(c[0], 0)), 20, (c[2] as Color).lightened(0.25))
		n.add_theme_font_override("font", UiKit.display_font())
		cv.add_child(n)
		r.add_child(cv)
		top.add_child(r)
	v.add_child(top)
	v.add_child(make(ledger))
	p.add_child(v)
	return p


func _ready() -> void:
	_k = 1.0 if UiKit.calm() else 0.0


func _process(delta: float) -> void:
	if _k < 1.0:
		_k = minf(1.0, _k + delta * 1.6)
		queue_redraw()


func _draw() -> void:
	var total := 0.0
	for p: Array in parts:
		total += float(p[0])
	var w := size.x
	var h := size.y
	draw_rect(Rect2(0, 0, w, h), Color(0.02, 0.05, 0.07, 1.0), true)
	if total > 0.0:
		var widths: Array = []
		var slivers := 0.0
		for p: Array in parts:
			var pw := float(p[0]) / total * w
			if float(p[0]) > 0.0 and pw < 6.0:
				slivers += 6.0 - pw
				pw = 6.0
			widths.append(pw)
		var big := 0
		for i: int in widths.size():
			if float(widths[i]) > float(widths[big]):
				big = i
		widths[big] = maxf(0.0, float(widths[big]) - slivers)
		var x := 0.0
		var ek := ease(_k, 0.3)
		for i: int in parts.size():
			var pw: float = widths[i]
			if pw <= 0.0:
				continue
			var c: Color = parts[i][1]
			var r := Rect2(x * ek, 2, pw * ek, h - 4)
			draw_rect(r, Color(c, 0.85), true)
			draw_rect(Rect2(r.position, Vector2(r.size.x, 3)), Color(c.lightened(0.4), 0.9), true)
			if i > 0:
				draw_line(Vector2(r.position.x, 0), Vector2(r.position.x, h), Color(0, 0, 0, 0.8), 2.0)
			x += pw
	for t: int in 11:
		var tx := w * t / 10.0
		draw_line(Vector2(tx, h - 6), Vector2(tx, h), Color(0, 0, 0, 0.6), 1.0)
	draw_rect(Rect2(0, 0, w, h), Color(UiKit.PETROL.lightened(0.2), 0.4), false, 1.0)

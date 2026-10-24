class_name HoloRing
extends Control
## Layered holographic rings turning at their own speeds (D-055): radar around
## the Ark, the halo over a world, the vial ring of the embryo bank. Each layer
## is a Synty ring sprite (General/Ring_*), tinted, scaled to a fraction of the
## control and rotated about the centre; without the packs each layer is drawn
## as dashed arcs. Purely decorative (mouse ignored); still with reduced motion.
##   var r := HoloRing.new(); r.add_layer("Ring_Medium_05", 1.0, 0.15, Color(0.5, 1, 1, 0.5))

var layers: Array = []  # [{tex: Texture2D, frac: float, speed: float, col: Color, angle: float, dashes: int}]
var pulse := 0.0  # 0..1: breathing brightness amount
var _t := 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Adds a ring: `sprite` is a General ring name ("Ring_Small_06"), `frac` its
## diameter as a fraction of the control's short side, `speed` in rad/s.
func add_layer(sprite: String, frac: float, speed: float, col: Color, dashes: int = 6) -> HoloRing:
	var px := int(clampf(maxf(custom_minimum_size.x, 128.0) * frac * 1.4, 64.0, 1024.0))
	var t := Holo.tex(Holo.GEN + sprite + ".png", px) if not sprite.is_empty() else null
	layers.append({"tex": t, "frac": frac, "speed": speed, "col": col, "angle": randf() * TAU, "dashes": dashes})
	return self


func _ready() -> void:
	set_process(not HoloAnim.calm())


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_t += delta
	for l: Dictionary in layers:
		l["angle"] = float(l["angle"]) + float(l["speed"]) * delta
	queue_redraw()


func _draw() -> void:
	var c := size * 0.5
	var s := minf(size.x, size.y)
	var k := 1.0 + pulse * 0.25 * sin(_t * 2.2)
	for l: Dictionary in layers:
		var d := s * float(l["frac"])
		var col: Color = l["col"]
		col.a *= k
		var tex: Texture2D = l["tex"]
		if tex:
			draw_set_transform(c, float(l["angle"]), Vector2.ONE)
			draw_texture_rect(tex, Rect2(-Vector2.ONE * d * 0.5, Vector2.ONE * d), false, col)
		else:
			var n: int = maxi(1, int(l["dashes"]))
			draw_set_transform(c, float(l["angle"]), Vector2.ONE)
			for i: int in n:
				var a0 := TAU * i / n
				draw_arc(Vector2.ZERO, d * 0.5, a0, a0 + TAU / n * 0.6, 16, col, 1.5, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

class_name Holo
extends RefCounted
## Holo-console UI kit (D-055): the shared vocabulary of the ship terminals and,
## next, every other menu. Small static factories on top of UiKit; each piece
## works without the purchased Synty INTERFACE packs (fresh clone /
## GA_NO_SYNTY_UI=1): sprites fall back to code-drawn shapes or text symbols.
##
## Building blocks (one file each, all in scripts/ui/):
##   HoloFrame    - panel overlay: animated corner brackets, scanlines, edge glow, boot reveal
##   HoloAnim     - boot_in / stagger / hover_lift / power_off / pulse
##   HoloRing     - layered rotating ring sprites (radar, halo, vial ring)
##   IconBadge    - hexagon badge with a glyph and an optional spinning ring
##   StatTile     - icon + caption + value + RangeBar + source chip (known / estimate / unknown)
##   RangeBar     - scale with a min-max band, uncertainty shading, value marker, locked state
##   ProgressRing - circular gauge with animated fill and a count-up value
##   CountUpLabel - number label that counts up to its value when shown
##   GlowButton   - primary call to action: glowing pulse, light sweep, cost chip
## Factories here: chip(), tag(), bullet(), readout(), meter(), tex(), name_font().

## Synty sprite paths (relative to SyntySkin.ROOT). Local only, never committed.
const GEN := "SciFiMenus/SourceFiles/Sprites/General/SPR_SciFiMenus_"
const SFM := "SciFiMenus/SourceFiles/Sprites/SciFiMenus/SPR_SciFiMenus_"
const HUDP := "SoldierHUD/Source_Sprites/Sprites/HUD/SPR_HUD_SciFi_"
const FXP := "SciFiMenus/SourceFiles/Sprites/FX/SPR_SciFiMenus_FX_"
const RES := "SoldierHUD/Source_Sprites/Sprites/Icons_Resources/ICON_SM_Prop_"

## Display face for world names and hero numbers (Zen Dots, SIL OFL, art/fonts/zendots).
const FONT_NAME := "res://art/fonts/zendots/ZenDots-Regular.ttf"
static var _name_font: Font


## A Synty sprite (path relative to SyntySkin.ROOT) as a texture with its
## longest side `px`, cached; null without the packs.
static func tex(rel: String, px: int, tint: Color = Color.WHITE) -> Texture2D:
	return SyntySkin.texture(SyntySkin.ROOT + rel, px, tint)


## Zen Dots with Quantico/Exo 2 as glyph fallback (Danish letters, symbols).
static func name_font() -> Font:
	if _name_font == null:
		if ResourceLoader.exists(FONT_NAME):
			var f := load(FONT_NAME) as FontFile
			var fb: Array[Font] = [UiKit.display_font()]
			f.fallbacks = fb
			_name_font = f
		else:
			_name_font = UiKit.display_font()
	return _name_font


static var _chip_boxes: Dictionary = {}


## Rounded pill: optional glyph + short text, tinted outline and faint fill.
## Used for sources ("ESTIMATE · ARCHIVE"), costs and status words.
static func chip(text: String, col: Color = UiKit.PETROL.lightened(0.35), icon_slot: String = "", fs: int = 12) -> PanelContainer:
	var p := PanelContainer.new()
	var key := col.to_html()
	if not _chip_boxes.has(key):
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(col.darkened(0.7), 0.55)
		sb.border_color = Color(col, 0.7)
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(9)
		sb.content_margin_left = 7
		sb.content_margin_right = 8
		sb.content_margin_top = 1
		sb.content_margin_bottom = 1
		_chip_boxes[key] = sb
	p.add_theme_stylebox_override("panel", _chip_boxes[key])
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	p.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var h := UiKit.hbox(4)
	if not icon_slot.is_empty():
		var ic := UiKit.icon_rect(icon_slot, fs + 1, col.lightened(0.2))
		if ic:
			h.add_child(ic)
	var l := UiKit.label(text.to_upper(), fs, col.lightened(0.3))
	l.add_theme_font_override("font", UiKit.display_variant(1))
	h.add_child(l)
	p.add_child(h)
	return p


## Chamfered tag for the type strip under a world's name (biome, hazard,
## "visited"): glyph + upper-case word on a tinted plate.
static func tag(text: String, icon_slot: String, col: Color) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(col.darkened(0.55), 0.75)
	sb.border_color = Color(col.lightened(0.1), 0.9)
	sb.border_width_left = 3
	sb.border_width_bottom = 1
	sb.corner_radius_top_right = 8
	sb.corner_radius_bottom_left = 8
	sb.content_margin_left = 8
	sb.content_margin_right = 10
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var h := UiKit.hbox(6)
	var ic := UiKit.icon_rect(icon_slot, 16, col.lightened(0.45))
	if ic:
		h.add_child(ic)
	var l := UiKit.label(text.to_upper(), 13, col.lightened(0.55))
	l.add_theme_font_override("font", UiKit.display_variant(2))
	h.add_child(l)
	p.add_child(h)
	return p


## Icon bullet: a glyph in a small tinted hexagon, then wrapped text (pros,
## cons, risks, unknowns). `fallback` is the text symbol without the packs.
static func bullet(icon_slot: String, text: String, col: Color, fallback: String = "•", fs: int = 15, text_col: Color = UiKit.TEXT) -> HBoxContainer:
	var h := UiKit.hbox(10)
	var b := IconBadge.make(icon_slot, 26, col, false, fallback)
	b.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	h.add_child(b)
	var l := UiKit.label(text, fs, text_col, true)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.custom_minimum_size = Vector2(120, 0)
	h.add_child(l)
	return h


## A compact readout: glyph, upper-case caption over a big value (any Control,
## e.g. a CountUpLabel). For route costs, start stock, counters.
static func readout(icon_slot: String, caption: String, value: Control, col: Color = UiKit.PETROL.lightened(0.4)) -> HBoxContainer:
	var h := UiKit.hbox(8)
	h.add_child(IconBadge.make(icon_slot, 34, col, false, "◆"))
	var v := UiKit.vbox(-2)
	var c := UiKit.label(caption.to_upper(), 11, UiKit.MUTED)
	c.add_theme_font_override("font", UiKit.display_variant(1))
	v.add_child(c)
	v.add_child(value)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_child(v)
	return h


## A big number in the display face (static text); for animated numbers use CountUpLabel.
static func value_label(text: String, fs: int = 22, col: Color = UiKit.TEXT) -> Label:
	var l := UiKit.label(text, fs, col)
	l.add_theme_font_override("font", UiKit.display_font())
	return l


## Section header for terminal columns: glyph + title + a thin rule and a
## blinking pip on the right (the rule is the theme's SectionTitle).
static func section(text: String, icon_slot: String = "") -> Control:
	return UiKit.section(text, icon_slot)


## Secondary "ghost" button (D-059): no fill, a faint outline, lit petrol on
## hover/focus, so it never competes with the primary GlowButton beside it.
static func ghost(b: Button) -> Button:
	var base := StyleBoxFlat.new()
	base.bg_color = Color(0, 0, 0, 0.0)
	base.border_color = Color(UiKit.MUTED, 0.45)
	base.set_border_width_all(1)
	base.set_corner_radius_all(8)
	base.content_margin_left = 14
	base.content_margin_right = 14
	base.content_margin_top = 7
	base.content_margin_bottom = 7
	var hov := base.duplicate() as StyleBoxFlat
	hov.bg_color = Color(UiKit.PETROL, 0.18)
	hov.border_color = Color(UiKit.PETROL.lightened(0.35), 0.8)
	var dis := base.duplicate() as StyleBoxFlat
	dis.border_color = Color(UiKit.MUTED, 0.18)
	b.add_theme_stylebox_override("normal", base)
	b.add_theme_stylebox_override("hover", hov)
	b.add_theme_stylebox_override("pressed", hov)
	b.add_theme_stylebox_override("hover_pressed", hov)
	b.add_theme_stylebox_override("disabled", dis)
	b.add_theme_color_override("font_color", UiKit.TEXT.darkened(0.1))
	return b


## Dashboard card (D-059): dark glass, no full outline, a coloured accent bar
## on the left and the cut corners of the kit. Calm by design: bright colour
## stays for live values and the selected/primary things inside.
static func card(accent: Color = UiKit.PETROL, pad: int = 12) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.02, 0.05, 0.07, 0.72)
	sb.border_color = Color(accent.lightened(0.1), 0.85)
	sb.border_width_left = 3
	sb.corner_radius_top_right = 12
	sb.corner_radius_bottom_left = 12
	sb.set_content_margin_all(pad)
	sb.content_margin_left = pad + 3
	p.add_theme_stylebox_override("panel", sb)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return p


## A big readout tile: caption, a large value (CountUpLabel when `count` is a
## number), an optional muted sub line; glyph badge on the left.
static func big_readout(icon_slot: String, caption: String, value_text: String, col: Color, sub: String = "", count: float = NAN, suffix: String = "") -> HBoxContainer:
	var h := UiKit.hbox(10)
	h.add_child(IconBadge.make(icon_slot, 40, col, false, "◆"))
	var v := UiKit.vbox(-2)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	var c := UiKit.label(caption.to_upper(), 11, UiKit.MUTED)
	c.add_theme_font_override("font", UiKit.display_variant(1))
	v.add_child(c)
	var val: Label
	if is_nan(count):
		val = UiKit.label(value_text, 26, col.lightened(0.3))
	else:
		var cu := CountUpLabel.make(count, 26, col.lightened(0.3), suffix)
		val = cu
	val.add_theme_font_override("font", UiKit.display_font())
	v.add_child(val)
	if not sub.is_empty():
		v.add_child(UiKit.label(sub, 13, UiKit.MUTED))
	h.add_child(v)
	return h


## Segmented meter (e.g. flatness 0.8 -> 4 of 5 lit), code-drawn, `w` px wide.
## Always shown next to a text value (colour/length are never the only cue).
static func meter(frac: float, segments: int = 5, col: Color = UiKit.PETROL, w: float = 40.0) -> Control:
	var m := _Meter.new()
	m.frac = clampf(frac, 0.0, 1.0)
	m.segments = segments
	m.col = col
	m.custom_minimum_size = Vector2(w, 10)
	m.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return m


class _Meter extends Control:
	var frac := 0.0
	var segments := 5
	var col := UiKit.PETROL

	func _draw() -> void:
		var gap := 2.0
		var sw := (size.x - gap * (segments - 1)) / segments
		var lit := int(roundf(frac * segments))
		for i: int in segments:
			var r := Rect2(i * (sw + gap), 1.0, sw, size.y - 2.0)
			draw_rect(r, Color(col, 0.95) if i < lit else Color(0.05, 0.1, 0.12, 0.9), true)
			if i >= lit:
				draw_rect(r, Color(col, 0.35), false, 1.0)

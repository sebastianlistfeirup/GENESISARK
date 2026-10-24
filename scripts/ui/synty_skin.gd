class_name SyntySkin
extends RefCounted
## Optional Synty INTERFACE skin for the shared theme (D-035, D-048). The purchased
## sprite packs live under res://assets/Synty/UI/ (gitignored, never committed).
## When they are present, panels and buttons become 9-slice StyleBoxTextures
## built from the packs' frame + background sprites (background tinted with the
## game palette, frame composited on top, scaled down once at theme build), and
## icons/markers/keycaps come from the sprite map in data/art/ui_skin.json.
## When they are missing (fresh public clone, CI) every call returns null and
## UiKit keeps its StyleBoxFlat look, so nothing depends on the packs.

const ROOT := "res://assets/Synty/UI/"
const MENUS := ROOT + "SciFiMenus/SourceFiles/Sprites/"
const GENERAL := MENUS + "General/SPR_SciFiMenus_"
const HUD := ROOT + "SoldierHUD/Source_Sprites/Sprites/HUD/SPR_HUD_SciFi_"
const SKIN_PATH := "res://data/art/ui_skin.json"

const PAD_DIR := ROOT + "SciFiMenus/SourceFiles/Core/Icons_Input/Xbox/ICON_Input_Xbox_"
## SettingsService pad tokens -> Xbox glyph files (colour face buttons).
const PAD_GLYPHS := {
	"btn:0": "ButtonColor_A_Clean", "btn:1": "ButtonColor_B_Clean", "btn:2": "ButtonColor_X_Clean",
	"btn:3": "ButtonColor_Y_Clean", "btn:4": "Button_Share_Clean", "btn:6": "Button_Menu_Clean",
	"btn:9": "Button_LB_Clean", "btn:10": "Button_RB_Clean",
}

static var _icons: Dictionary = {}
static var _map: Dictionary = {}
static var _disabled := false  # tests can force the fallback look


static func available() -> bool:
	# GA_NO_SYNTY_UI=1 previews/tests the fresh-clone fallback with the packs installed.
	return not _disabled and OS.get_environment("GA_NO_SYNTY_UI") != "1" and ResourceLoader.exists(MENUS + "SciFiMenus/SPR_SciFiMenus_Button_Frame_03.png")


## Forces the flat fallback (or re-enables the packs). Theme must be rebuilt.
static func set_disabled(on: bool) -> void:
	_disabled = on
	_icons.clear()


## Slot -> sprite path from data/art/ui_skin.json ("" if unknown).
static func path_of(slot: String) -> String:
	if _map.is_empty():
		var d: Variant = DictUtil.load_json(SKIN_PATH)
		_map = DictUtil.get_dict(d, "icons") if d is Dictionary else {}
		if _map.is_empty():
			_map = {"_": ""}  # loaded, nothing in it: do not retry every call
	var rel := str(_map.get(slot, ""))
	return ROOT + rel if not rel.is_empty() else ""


static func _image(path: String) -> Image:
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	var tex := load(path) as Texture2D
	if tex == null:
		return null
	var img := tex.get_image()
	if img == null or img.is_empty():
		return null
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	return img


## Multiplies every pixel by `tint` (white sprites take the tint colour).
static func _tinted(img: Image, tint: Color) -> Image:
	var out := img.duplicate() as Image
	for y: int in out.get_height():
		for x: int in out.get_width():
			out.set_pixel(x, y, out.get_pixel(x, y) * tint)
	return out


static func _apply(sb: StyleBoxTexture, scale: float, slice: Vector4, content: Vector4, expand: Vector4) -> void:
	sb.texture_margin_left = slice.x * scale
	sb.texture_margin_top = slice.y * scale
	sb.texture_margin_right = slice.z * scale
	sb.texture_margin_bottom = slice.w * scale
	sb.expand_margin_left = expand.x * scale
	sb.expand_margin_top = expand.y * scale
	sb.expand_margin_right = expand.z * scale
	sb.expand_margin_bottom = expand.w * scale
	sb.content_margin_left = content.x
	sb.content_margin_top = content.y
	sb.content_margin_right = content.z
	sb.content_margin_bottom = content.w


## A 9-slice box from a Synty frame sprite and its "_Background" sprite.
## `slice` and `expand` are in SOURCE pixels (l, t, r, b); `content` is in
## screen pixels and is set explicitly so layouts (and the 1280x720 @1.5 fit
## checks) do not depend on the art. `frame_only` skips the background (focus rings).
static func box(frame: String, bg_tint: Color, frame_tint: Color, scale: float, slice: Vector4, content: Vector4, expand: Vector4 = Vector4.ZERO, frame_only: bool = false) -> StyleBoxTexture:
	if not available():
		return null
	var fr := _image(MENUS + "SciFiMenus/" + frame + ".png")
	if fr == null:
		return null
	var size := Vector2i(maxi(8, roundi(fr.get_width() * scale)), maxi(8, roundi(fr.get_height() * scale)))
	fr.resize(size.x, size.y, Image.INTERPOLATE_LANCZOS)
	var comp := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	var bg: Image = null if frame_only else _image(MENUS + "SciFiMenus/" + frame + "_Background.png")
	if bg != null:
		bg.resize(size.x, size.y, Image.INTERPOLATE_LANCZOS)
		comp.blend_rect(_tinted(bg, bg_tint), Rect2i(Vector2i.ZERO, size), Vector2i.ZERO)
	comp.blend_rect(_tinted(fr, frame_tint), Rect2i(Vector2i.ZERO, size), Vector2i.ZERO)
	var sb := StyleBoxTexture.new()
	sb.texture = ImageTexture.create_from_image(comp)
	_apply(sb, scale, slice, content, expand)
	return sb


## A 9-slice box stacked from white mask sprites, each tinted: [[path, Color], ...].
## Every layer is resized to the first layer's size * scale (the Soldier HUD
## masks share one 256 px grid, so fill, glass and outline line up).
static func stack(layers: Array, scale: float, slice: Vector4, content: Vector4, expand: Vector4 = Vector4.ZERO) -> StyleBoxTexture:
	if not available() or layers.is_empty():
		return null
	var first := _image(str(layers[0][0]))
	if first == null:
		return null
	var size := Vector2i(maxi(8, roundi(first.get_width() * scale)), maxi(8, roundi(first.get_height() * scale)))
	var comp := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	for i: int in layers.size():
		var l: Array = layers[i]
		if str(l[0]) == "rect":  # ["rect", Color, Rect2 in 0..1 of the texture]: a solid accent (bar, tab)
			var r: Rect2 = l[2]
			var ri := Rect2i(roundi(r.position.x * size.x), roundi(r.position.y * size.y), maxi(1, roundi(r.size.x * size.x)), maxi(1, roundi(r.size.y * size.y)))
			var solid := Image.create(ri.size.x, ri.size.y, false, Image.FORMAT_RGBA8)
			solid.fill(l[1])
			comp.blend_rect(solid, Rect2i(Vector2i.ZERO, ri.size), ri.position)
			continue
		var img := first if i == 0 else _image(str(l[0]))
		if img == null:
			continue
		img = img.duplicate() as Image
		img.resize(size.x, size.y, Image.INTERPOLATE_LANCZOS)
		if l.size() > 2 and str(l[2]) == "flip_y":
			img.flip_y()
		comp.blend_rect(_tinted(img, l[1]), Rect2i(Vector2i.ZERO, size), Vector2i.ZERO)
	var sb := StyleBoxTexture.new()
	sb.texture = ImageTexture.create_from_image(comp)
	_apply(sb, scale, slice, content, expand)
	return sb


## Any sprite as a texture whose longest side is `px`, cached; optional tint baked in.
static func texture(path: String, px: int, tint: Color = Color.WHITE) -> Texture2D:
	if not available() or path.is_empty():
		return null
	var key := "%s@%d/%s" % [path, px, tint.to_html()]
	if _icons.has(key):
		return _icons[key]
	var img := _image(path)
	var tex: Texture2D = null
	if img != null:
		var s := float(px) / float(maxi(img.get_width(), img.get_height()))
		img.resize(maxi(1, roundi(img.get_width() * s)), maxi(1, roundi(img.get_height() * s)), Image.INTERPOLATE_LANCZOS)
		if tint != Color.WHITE:
			img = _tinted(img, tint)
		tex = ImageTexture.create_from_image(img)
	_icons[key] = tex
	return tex


## White glyph icon for a ui_skin.json slot, downscaled once; null without the packs.
static func icon(slot: String, px: int = 48) -> Texture2D:
	return texture(path_of(slot), px)


## Controller glyph for a SettingsService pad token ("btn:1" = B); null if
## the packs are missing or the token has no glyph.
static func pad_glyph(token: String) -> Texture2D:
	if not PAD_GLYPHS.has(token):
		return null
	return texture(PAD_DIR + str(PAD_GLYPHS[token]) + ".png", 40)

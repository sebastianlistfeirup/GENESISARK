class_name SyntySkin
extends RefCounted
## Optional Synty INTERFACE skin for the shared theme (D-035). The purchased
## sprite packs live under res://assets/Synty/UI/ (gitignored, never committed).
## When they are present, panels and buttons become 9-slice StyleBoxTextures
## built from the packs' frame + background sprites (background tinted with the
## game palette, frame composited on top, scaled down once at theme build).
## When they are missing (fresh public clone, CI) every call returns null and
## UiKit keeps its StyleBoxFlat look, so nothing depends on the packs.

const MENUS := "res://assets/Synty/UI/SciFiMenus/SourceFiles/Sprites/"
const HUD := "res://assets/Synty/UI/SoldierHUD/Source_Sprites/Sprites/"

## Glyph icons (white, tinted at use) for the colony resource chips.
const ICONS := {
	"ui.icon_power": MENUS + "Icons_Menu/ICON_SciFiMenus_Menu_LightningBolt_01_Clean.png",
	"ui.icon_alloy": HUD + "Icons_Status/ICON_SciFi_Status_Armor.png",
	"ui.icon_components": MENUS + "Icons_Menu/ICON_SciFiMenus_Menu_Settings_01_Clean.png",
	"ui.icon_water": HUD + "Icons_Status/ICON_SciFi_Status_Bleeding.png",
	"ui.icon_food": HUD + "Icons_Status/ICON_SciFi_Status_Hunger.png",
	"ui.icon_reserve": HUD + "Icons_Status/ICON_SciFi_Status_Thirst.png",
	"ui.icon_population": MENUS + "Icons_Menu/ICON_SciFiMenus_Menu_Multiplayer_01_Clean.png",
	"ui.icon_embryo": MENUS + "Icons_Menu/ICON_SciFiMenus_Menu_DNA_01_Clean.png",
	"ui.icon_fuel": HUD + "Icons_Status/ICON_SciFi_Status_Oxygen02.png",
}

const PAD_DIR := "res://assets/Synty/UI/SciFiMenus/SourceFiles/Core/Icons_Input/Xbox/ICON_Input_Xbox_"
## SettingsService pad tokens -> Xbox glyph files (colour face buttons).
const PAD_GLYPHS := {
	"btn:0": "ButtonColor_A_Clean", "btn:1": "ButtonColor_B_Clean", "btn:2": "ButtonColor_X_Clean",
	"btn:3": "ButtonColor_Y_Clean", "btn:4": "Button_Share_Clean", "btn:6": "Button_Menu_Clean",
	"btn:9": "Button_LB_Clean", "btn:10": "Button_RB_Clean",
}

static var _icons: Dictionary = {}
static var _disabled := false  # tests can force the fallback look


static func available() -> bool:
	# GA_NO_SYNTY_UI=1 previews/tests the fresh-clone fallback with the packs installed.
	return not _disabled and OS.get_environment("GA_NO_SYNTY_UI") != "1" and ResourceLoader.exists(MENUS + "SciFiMenus/SPR_SciFiMenus_Button_Frame_03.png")


## Forces the flat fallback (or re-enables the packs). Theme must be rebuilt.
static func set_disabled(on: bool) -> void:
	_disabled = on
	_icons.clear()


static func _image(path: String) -> Image:
	if not ResourceLoader.exists(path):
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


## A 9-slice box from a Synty frame sprite and its "_Background" sprite.
## `slice` and `expand` are in SOURCE pixels (l, t, r, b); `content` is in
## screen pixels and is set explicitly so layouts (and the 1280x720 @1.5 fit
## checks) do not depend on the art.
static func box(frame: String, bg_tint: Color, frame_tint: Color, scale: float, slice: Vector4, content: Vector4, expand: Vector4 = Vector4.ZERO) -> StyleBoxTexture:
	if not available():
		return null
	var fr := _image(MENUS + "SciFiMenus/" + frame + ".png")
	if fr == null:
		return null
	var size := Vector2i(maxi(8, roundi(fr.get_width() * scale)), maxi(8, roundi(fr.get_height() * scale)))
	fr.resize(size.x, size.y, Image.INTERPOLATE_LANCZOS)
	var comp := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	var bg := _image(MENUS + "SciFiMenus/" + frame + "_Background.png")
	if bg != null:
		bg.resize(size.x, size.y, Image.INTERPOLATE_LANCZOS)
		comp.blend_rect(_tinted(bg, bg_tint), Rect2i(Vector2i.ZERO, size), Vector2i.ZERO)
	comp.blend_rect(_tinted(fr, frame_tint), Rect2i(Vector2i.ZERO, size), Vector2i.ZERO)
	var sb := StyleBoxTexture.new()
	sb.texture = ImageTexture.create_from_image(comp)
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
	return sb


## White glyph icon for a resource chip, downscaled once; null without the packs.
static func icon(slot: String) -> Texture2D:
	if not available() or not ICONS.has(slot):
		return null
	if _icons.has(slot):
		return _icons[slot]
	var img := _image(str(ICONS[slot]))
	var tex: Texture2D = null
	if img != null:
		img.resize(48, 48, Image.INTERPOLATE_LANCZOS)
		tex = ImageTexture.create_from_image(img)
	_icons[slot] = tex
	return tex


## Controller glyph for a SettingsService pad token ("btn:1" = B); null if
## the packs are missing or the token has no glyph.
static func pad_glyph(token: String) -> Texture2D:
	if not available() or not PAD_GLYPHS.has(token):
		return null
	var key := "pad:" + token
	if _icons.has(key):
		return _icons[key]
	var img := _image(PAD_DIR + str(PAD_GLYPHS[token]) + ".png")
	var tex: Texture2D = null
	if img != null:
		img.resize(40, 40, Image.INTERPOLATE_LANCZOS)
		tex = ImageTexture.create_from_image(img)
	_icons[key] = tex
	return tex

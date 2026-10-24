class_name HoloScreen
extends MeshInstance3D
## A floating holographic screen over a console or in front of a window (Sci-Fi
## Space key art): a procedural panel (art/shaders/holo_screen.gdshader) in the
## room's colour once power is back, a dim red blinking warning on emergency
## power (the derelict look). Presentation only: no collision, no light.

const SHADER := preload("res://art/shaders/holo_screen.gdshader")

var color_on := Color("3ff2ff")
var _mat: ShaderMaterial


static func make(size: Vector2, color: Color, seed_value: int = 0) -> HoloScreen:
	var s := HoloScreen.new()
	var q := QuadMesh.new()
	q.size = size
	s.mesh = q
	s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	s._mat = ShaderMaterial.new()
	s._mat.shader = SHADER
	s._mat.set_shader_parameter("aspect", Vector2(size.x / maxf(size.y, 0.01), 1.0))
	s._mat.set_shader_parameter("seed", float(seed_value % 97))
	s._mat.set_shader_parameter("motion", 0.0 if FxEffect.reduced_motion() else 1.0)
	s.material_override = s._mat
	s.color_on = color
	s.set_powered(true)
	return s


func set_powered(on: bool) -> void:
	_mat.set_shader_parameter("error", 0.0 if on else 1.0)
	_mat.set_shader_parameter("color", color_on if on else Color("ff3b2f"))
	_mat.set_shader_parameter("energy", 1.6 if on else 0.9)

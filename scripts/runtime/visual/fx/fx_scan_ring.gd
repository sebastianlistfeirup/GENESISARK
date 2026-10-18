class_name FxScanRing
extends MeshInstance3D
## Expanding ground ring for fx.scan_pulse: grows from the centre to `radius`
## metres over `period` seconds while fading out, then starts again.
## Presentation only. Reduced motion: slower and fainter.

@export var radius := 6.0
@export var period := 2.8
## 0..1: where in the cycle this ring starts (two rings at 0 and 0.5 overlap nicely).
@export var phase := 0.0
@export var peak_alpha := 0.9

var _t := 0.0
var _mat: StandardMaterial3D
var _color := Color.WHITE


func _ready() -> void:
	if FxEffect.reduced_motion():
		period *= 1.6
		peak_alpha *= 0.6
	_t = phase * period
	var m := material_override as StandardMaterial3D
	if m:
		_mat = m.duplicate() as StandardMaterial3D
		material_override = _mat
		_color = _mat.albedo_color
	_apply()


func _process(delta: float) -> void:
	_t = fmod(_t + delta, period)
	_apply()


func _apply() -> void:
	var k := _t / period
	var grow := 1.0 - pow(1.0 - k, 2.2)  # fast out, slow settle
	var s := maxf(0.02, grow * radius)
	scale = Vector3(s, 1.0, s)
	if _mat:
		var fade := minf(k * 8.0, 1.0) * pow(1.0 - k, 1.4)
		_mat.albedo_color = Color(_color.r, _color.g, _color.b, peak_alpha * fade)

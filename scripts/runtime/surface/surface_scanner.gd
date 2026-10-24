class_name SurfaceScanner
extends Node3D
## The suit scanner (D-062): [C] / pad Y sends a pulse rippling out across the
## terrain from the captain. As the wavefront passes each point of interest (samples,
## relay, lander, hazard zones) a tag pops up over it with its name and distance,
## holds, and fades. Information only; a short cooldown. Reduced motion: the tags
## appear at once without the pop.

const RANGE := 95.0
const SPEED := 60.0        # metres per second of the wavefront
const COOLDOWN := 5.0
const HOLD := 7.0

## A tag popped up over `node` for `seconds`: the scene hides its own sign and
## waypoint name there meanwhile, so the two never stack.
signal tagged(node: Node3D, seconds: float)

var captain: Node3D
var targets: Array = []    # [{node: Node3D, name: String, color: Color}]
var _cool := 0.0
var _wave: MeshInstance3D
var _mat: ShaderMaterial
var _r := -1.0
var _origin := Vector3.ZERO
var _pending: Array = []   # targets not reached yet this pulse
var _last_blip := 0.0      # _r at the last returning blip (spacing)


func _ready() -> void:
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.0
	cyl.bottom_radius = 1.0
	cyl.height = 1.0
	cyl.cap_top = false
	cyl.cap_bottom = false
	cyl.radial_segments = 96
	cyl.rings = 1
	_mat = ShaderMaterial.new()
	_mat.shader = preload("res://art/shaders/scan_wave.gdshader")
	_wave = MeshInstance3D.new()
	_wave.mesh = cyl
	_wave.material_override = _mat
	_wave.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_wave.visible = false
	add_child(_wave)


func can_scan() -> bool:
	return _cool <= 0.0


func pulse() -> bool:
	if not can_scan() or captain == null:
		return false
	_cool = COOLDOWN
	_origin = captain.global_position
	_r = 0.5
	_pending = targets.duplicate()
	_wave.visible = true
	_last_blip = -100.0
	AudioService.play_any(["sfx_scan_ping", "sfx_scan"], "SFX", -4.0)
	return true


func _process(delta: float) -> void:
	_cool = maxf(0.0, _cool - delta)
	if _r < 0.0:
		return
	_r += SPEED * delta
	var k := _r / RANGE
	_wave.global_position = _origin + Vector3(0, 3.5, 0)
	_wave.scale = Vector3(_r, 9.0, _r)
	_mat.set_shader_parameter("fade", 1.0 - smoothstep(0.55, 1.0, k))
	for t: Dictionary in _pending.duplicate():
		var n: Node3D = t["node"]
		if not is_instance_valid(n):
			_pending.erase(t)
			continue
		var d := Vector2(n.global_position.x - _origin.x, n.global_position.z - _origin.z).length()
		if d <= _r:
			_pending.erase(t)
			_tag(t, d)
	if _r >= RANGE:
		_r = -1.0
		_wave.visible = false
		_pending.clear()


func _tag(t: Dictionary, dist: float) -> void:
	var n: Node3D = t["node"]
	var lbl := Label3D.new()
	var nm := str(t["name"])
	lbl.text = ("%s · %d m" if nm.begins_with("▲") else "◆ %s · %d m") % [nm, int(round(dist))]  # hazards keep their own ▲
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.no_depth_test = true
	lbl.render_priority = 10  # drawn after glowing props (the relay beacon's orb cut through the text)
	lbl.fixed_size = true
	lbl.pixel_size = 0.0011
	lbl.font_size = 30
	lbl.outline_size = 10
	lbl.outline_modulate = Color(0.02, 0.05, 0.06, 0.85)
	lbl.modulate = t.get("color", Color("59e6ff"))
	add_child(lbl)
	lbl.global_position = n.global_position + Vector3(0, float(t.get("height", 4.5)), 0)
	var tw := create_tween()
	if FxEffect.reduced_motion():
		tw.tween_interval(HOLD)
	else:
		# Pop: overshoot then settle (follow-through), hold, fade.
		lbl.scale = Vector3.ONE * 0.2
		tw.tween_property(lbl, "scale", Vector3.ONE * 1.18, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(lbl, "scale", Vector3.ONE, 0.14)
		tw.tween_interval(HOLD)
	tw.tween_property(lbl, "modulate:a", 0.0, 0.6)
	tw.tween_callback(lbl.queue_free)
	tagged.emit(n, HOLD + 0.85)
	# Returning blip (D-064): fainter and lower the farther the tag; never two on one frame-step.
	if _r - _last_blip > 3.0:
		_last_blip = _r
		var k := clampf(dist / RANGE, 0.0, 1.0)
		AudioService.play("sfx_scan_blip", "SFX", -8.0 - 8.0 * k, 1.18 - 0.3 * k)

class_name FxEffect
extends Node3D
## Root script of every particle scene in art/fx/ (the fx.* VisualSlots).
## Presentation only: never reads or writes domain state.
## - LOOP: the GPUParticles3D children emit continuously (hazard zones, thruster).
## - BURSTS: one_shot children are restarted at random intervals, optionally at a
##   random offset, with a short "Flash" OmniLight3D (welding sparks, power surge).
## - ONCE: one_shot children fire once when the effect enters the tree (landing).
## Reduced motion (settings) is read once in _ready: fewer particles, slower and
## no light flicker. Works without autoloads (headless tests, editor preview).

enum Mode { LOOP, BURSTS, ONCE }

@export var mode: Mode = Mode.LOOP
## Seconds between bursts (min, max).
@export var burst_interval := Vector2(0.6, 2.4)
## Random local offset per burst (+/- per axis), e.g. a welder moving over a frame.
@export var burst_jitter := Vector3.ZERO
## Reduced motion: share of particles kept and time scale.
@export var calm_amount := 0.5
@export var calm_speed := 0.6

var calm := false
var _rng := RandomNumberGenerator.new()
var _timer := 0.0
var _bursts: Array[GPUParticles3D] = []
var _base: Dictionary = {}
var _light: OmniLight3D
var _light_energy := 0.0
var _light_base := Vector3.ZERO
var _flash := 0.0


## True when the player asked for reduced motion. Safe outside the game.
static func reduced_motion() -> bool:
	var ml := Engine.get_main_loop()
	if not ml is SceneTree:
		return false
	var s := (ml as SceneTree).root.get_node_or_null(^"SettingsService")
	if not is_instance_valid(s) or not s.has_method("get_value"):
		return false
	return bool(s.call("get_value", "reduced_motion", false))


func _ready() -> void:
	calm = reduced_motion()
	_rng.seed = hash(get_instance_id())
	var lean := Quality.value("fx_amount", 1.0)
	for n: Node in find_children("*", "GPUParticles3D", true, false):
		var gp := n as GPUParticles3D
		gp.amount_ratio = (calm_amount if calm else 1.0) * lean
		if calm:
			gp.speed_scale *= calm_speed
		if gp.one_shot:
			gp.emitting = false
			_bursts.append(gp)
			_base[gp] = gp.position
	_light = find_child("Flash", true, false) as OmniLight3D
	if _light:
		_light_energy = _light.light_energy * (0.5 if calm else 1.0)
		_light_base = _light.position
		_light.light_energy = 0.0
	match mode:
		Mode.BURSTS:
			_timer = _rng.randf_range(0.0, burst_interval.y)
		Mode.ONCE:
			_burst.call_deferred()
	set_process(mode != Mode.LOOP or _light != null)


func _process(delta: float) -> void:
	if mode == Mode.BURSTS:
		_timer -= delta
		if _timer <= 0.0:
			_burst()
			_timer = _rng.randf_range(burst_interval.x, burst_interval.y) / (calm_speed if calm else 1.0)
	if _light:
		_flash = maxf(0.0, _flash - delta * (3.0 if calm else 7.0))
		var flicker := 1.0 if calm else _rng.randf_range(0.55, 1.0)
		_light.light_energy = _light_energy * _flash * flicker


## Fire every one_shot emitter now (also callable by gameplay presentation code).
func burst() -> void:
	_burst()


func _burst() -> void:
	var off := Vector3(_rng.randf_range(-burst_jitter.x, burst_jitter.x), _rng.randf_range(-burst_jitter.y, burst_jitter.y),
		_rng.randf_range(-burst_jitter.z, burst_jitter.z))
	for gp: GPUParticles3D in _bursts:
		gp.position = (_base[gp] as Vector3) + off
		gp.restart()
	if _light:
		_light.position = _light_base + off
		_flash = 1.0

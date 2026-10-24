class_name RigLab
extends Node3D
## DEVELOPER TOOL (GA-14 prep, bible p.24-25). Inspect any char.* VisualSlot
## against fixed references before it goes into the game:
##   - 1 m floor grid, 1 m cube, 1.8 m height pole, terminal at 1.05 m, sample point
##   - every state in data/art/animation_map.json (idle/walk/run/interact/sample/build)
##   - in place or on a 6 m circle at a chosen speed, so foot sliding shows against the grid
##   - audit(): scale, feet on y=0, AnimationPlayer, missing clips -> also used by the smoke test
## Open: F6 on scenes/tests/RigLab.tscn, or
##   godot --path . -- --capture=evidence/shots/riglab.png --scene=riglab --action=audit
## Dev-only text, not localized (like DebugCapture).

const SLOTS := ["char.captain", "char.citizen_adult", "char.citizen_child", "char.robot_worker", "char.robot_drone",
	"char.ark_ai_hologram"]
const STATES := ["idle", "walk", "run", "interact", "sample", "build"]
## Plausible standing height (m) per slot: catches cm/m import mistakes (x100) and wrong rigs.
const HEIGHT := {"char.captain": [1.6, 2.0], "char.citizen_adult": [1.5, 1.95], "char.citizen_child": [0.9, 1.45],
	"char.robot_worker": [1.0, 2.2], "char.robot_drone": [0.2, 1.2], "char.ark_ai_hologram": [0.8, 2.4]}
const TERMINAL_HEIGHT := 1.05
const CIRCLE_R := 3.0

var slot_index := 0
var state := "idle"
var speed := 1.5
var moving := false

var _pivot: Node3D
var _slot: VisualSlot
var _anim: CharacterAnimator
var _angle := 0.0
var _cam: Camera3D
var _yaw := 2.3  # 3/4 front: the character faces -Z
var _pitch := -0.25
var _dist := 5.5
var _report: Label
var _title: Label
var _state_box: HBoxContainer
var _drag := false


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_build_world()
	_build_ui()
	_load_slot()


# ---------------------------------------------------------------- audit (headless-safe)

## Measures a slot without needing a scene tree. Returns issues in plain words.
static func audit(slot_id: String) -> Dictionary:
	var vs := VisualSlot.make(slot_id)
	vs.rebuild()
	var box := _aabb(vs, Transform3D.IDENTITY)
	var player := CharacterAnimator._find_player(vs)
	var map: Variant = DictUtil.load_json("res://data/art/animation_map.json")
	var cfg: Dictionary = DictUtil.get_dict(map if map is Dictionary else {}, slot_id)
	var built := AnimationLibraryBuilder.load_mappings()
	var lib_path := str(built.get(slot_id, ""))
	var lib: AnimationLibrary = load(lib_path) if not lib_path.is_empty() and ResourceLoader.exists(lib_path) else null
	if lib != null and vs.using_asset:
		# Built library (tools/synty): clips are named after the states; idle/walk/run are required.
		player = CharacterAnimator.attach(vs, lib)
	var clips: Array = Array(player.get_animation_list()) if player else []
	var missing: Array = []
	for st: String in STATES:
		if lib != null:
			if st in ["idle", "walk", "run"] and not lib.has_animation(st):
				missing.append(st)
		elif cfg.has(st):
			var clip := str(DictUtil.get_dict(cfg, st).get("clip", ""))
			if player and not player.has_animation(clip):
				missing.append("%s→%s" % [st, clip])
	var issues: Array = []
	var h := box.size.y
	var lim: Array = HEIGHT.get(slot_id, [0.1, 10.0])
	if h < float(lim[0]) or h > float(lim[1]):
		issues.append("højde %.2f m uden for %.2f–%.2f (skala/enheder? sæt 'scale' i asset_slots.json)" % [h, lim[0], lim[1]])
	if absf(box.position.y) > 0.05 and slot_id != "char.robot_drone":
		issues.append("fødder står %.2f m fra y=0 (sæt 'offset' i asset_slots.json)" % box.position.y)
	if vs.using_asset and player == null and not slot_id.begins_with("char.robot"):  # robots/drones are rigid props
		issues.append("importeret model uden AnimationPlayer")
	if not missing.is_empty():
		issues.append("mangler clips: " + ", ".join(missing))
	var out := {"slot": slot_id, "asset": vs.using_asset, "height_m": snappedf(h, 0.01), "feet_y": snappedf(box.position.y, 0.01),
		"footprint_m": [snappedf(box.size.x, 0.01), snappedf(box.size.z, 0.01)], "animation_player": player != null,
		"clips": clips, "mapped_states": cfg.keys().filter(func(k: Variant) -> bool: return str(k) in STATES),
		"missing_clips": missing, "issues": issues, "ok": issues.is_empty()}
	vs.free()
	return out


static func _aabb(n: Node, xf: Transform3D) -> AABB:
	return AssetSlots.aabb_of(n, xf * (n as Node3D).transform if n is Node3D else xf)


# ---------------------------------------------------------------- world

func _build_world() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("#141b21")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("#8aa0ad")
	e.ambient_light_energy = 0.6
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 35, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var floor := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(16, 16)
	floor.mesh = pm
	floor.material_override = AssetSlots.material("#26323a")
	add_child(floor)
	for i: int in range(-8, 9):  # 1 m grid, every 5th line brighter
		var c := "#5c7480" if i % 5 == 0 else "#36454e"
		_box(Vector3(16, 0.004, 0.015), Vector3(0, 0.002, i), c)
		_box(Vector3(0.015, 0.004, 16), Vector3(i, 0.002, 0), c)
	_box(Vector3.ONE, Vector3(-2.5, 0.5, -1.5), "#3f6e78", "1 m")
	_box(Vector3(0.05, 1.8, 0.05), Vector3(1.2, 0.9, 0), "#e8a33d")
	for k: int in range(1, 4):
		var y := k * 0.5
		_box(Vector3(0.2, 0.01, 0.01), Vector3(1.3, y, 0), "#e8a33d")
		_label("%.1f m" % y, Vector3(1.55, y, 0), 28)
	_label("1.8 m", Vector3(1.55, 1.8, 0), 28)
	# Interaction references: terminal panel at hand height, sample point on the ground ahead (-Z = forward).
	_box(Vector3(0.6, 0.04, 0.4), Vector3(0, TERMINAL_HEIGHT, -0.75), "#7fd6d0", "terminal %.2f m" % TERMINAL_HEIGHT)
	_box(Vector3(0.12, TERMINAL_HEIGHT, 0.12), Vector3(0, TERMINAL_HEIGHT * 0.5, -0.85), "#2d3b44")
	_box(Vector3(0.25, 0.02, 0.25), Vector3(0, 0.01, -0.55), "#d25b4c", "prøvepunkt")
	_label("−Z = fremad", Vector3(-1.2, 0.05, -1.6), 32)
	_pivot = Node3D.new()
	add_child(_pivot)
	_cam = Camera3D.new()
	_cam.fov = 45
	add_child(_cam)
	_place_cam()


func _box(size: Vector3, pos: Vector3, hex: String, text: String = "") -> void:
	var m := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	m.mesh = bm
	m.position = pos
	m.material_override = AssetSlots.material(hex)
	add_child(m)
	if not text.is_empty():
		_label(text, pos + Vector3(0, size.y * 0.5 + 0.12, 0), 26)


func _label(text: String, pos: Vector3, size: int) -> void:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = 0.0032
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.position = pos
	add_child(l)


# ---------------------------------------------------------------- UI

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var p := UiKit.panel(Vector2(430, 0))
	p.position = Vector2(20, 20)
	p.theme = UiKit.theme()
	layer.add_child(p)
	var v := UiKit.vbox(8)
	p.add_child(v)
	v.add_child(UiKit.label("RIGLAB · GA-14", 14, UiKit.PETROL.lightened(0.3)))
	var row := UiKit.hbox(6)
	row.add_child(UiKit.button("◀", func() -> void: _cycle(-1)))
	_title = UiKit.label("", 20)
	_title.custom_minimum_size = Vector2(280, 0)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(_title)
	row.add_child(UiKit.button("▶", func() -> void: _cycle(1)))
	v.add_child(row)
	_state_box = UiKit.hbox(4)
	v.add_child(_state_box)
	for st: String in STATES:
		_state_box.add_child(UiKit.button(st, func() -> void: _set_state(st)))
	var mv := CheckButton.new()
	mv.text = "Bevæg i cirkel (fodglid mod gitteret)"
	mv.toggled.connect(func(on: bool) -> void: moving = on)
	v.add_child(mv)
	var sp := UiKit.hbox(8)
	var spl := UiKit.label("Fart %.1f m/s" % speed, 15)
	spl.custom_minimum_size = Vector2(130, 0)
	sp.add_child(spl)
	var s := HSlider.new()
	s.min_value = 0.0
	s.max_value = 6.0
	s.step = 0.1
	s.value = speed
	s.custom_minimum_size = Vector2(250, 24)
	s.value_changed.connect(func(x: float) -> void:
		speed = x
		spl.text = "Fart %.1f m/s" % x)
	sp.add_child(s)
	v.add_child(sp)
	var views := UiKit.hbox(4)
	for vw: Array in [["Side", 1.5708, -0.1], ["Front", 3.1416, -0.1], ["3/4", 2.3, -0.25], ["Top", 0.0, -1.45]]:
		views.add_child(UiKit.button(str(vw[0]), func() -> void:
			_yaw = float(vw[1])
			_pitch = float(vw[2])
			_place_cam()))
	v.add_child(views)
	_report = UiKit.label("", 14, UiKit.MUTED, true)
	_report.custom_minimum_size = Vector2(410, 0)
	v.add_child(_report)
	v.add_child(UiKit.label("Træk = drej · hjul = zoom · Esc = menu", 12, UiKit.MUTED))


func _cycle(d: int) -> void:
	slot_index = posmod(slot_index + d, SLOTS.size())
	_load_slot()


func _set_state(st: String) -> void:
	state = st
	if st == "walk" or st == "run":
		var ref := DictUtil.get_float(DictUtil.get_dict(_anim.cfg, st), "speed_ref", 1.5 if st == "walk" else 4.5) if _anim else 1.5
		speed = ref
	_refresh_report()


func _load_slot() -> void:
	if _slot:
		_slot.queue_free()
	var id: String = SLOTS[slot_index]
	_slot = VisualSlot.make(id)
	_pivot.add_child(_slot)
	_anim = CharacterAnimator.for_slot(_slot)
	_title.text = id
	_angle = 0.0
	_pivot.position = Vector3.ZERO
	_pivot.rotation = Vector3.ZERO
	_refresh_report()


func _refresh_report() -> void:
	var a := audit(SLOTS[slot_index])
	var lines: Array = [
		"%s · højde %.2f m · fødder y=%.2f · fodaftryk %.2f×%.2f m" % ["ASSET" if a["asset"] else "PROXY", a["height_m"], a["feet_y"],
			a["footprint_m"][0], a["footprint_m"][1]],
		"AnimationPlayer: %s · clips: %s" % ["ja" if a["animation_player"] else "nej", ", ".join(a["clips"]) if not a["clips"].is_empty() else "—"],
		"Kortlagte tilstande: %s · aktiv: %s @ %.1f m/s" % [", ".join(a["mapped_states"]), state, speed],
	]
	if a["issues"].is_empty():
		lines.append("● Ingen fund")
	for i: String in a["issues"]:
		lines.append("▲ " + i)
	if not a["animation_player"]:
		lines.append("Proxy: map en scene i data/art/asset_slots.json for at teste clips.")
	_report.text = "\n".join(lines)


# ---------------------------------------------------------------- loop

func _process(delta: float) -> void:
	var cur := speed if state in ["walk", "run"] else 0.0
	if moving and cur > 0.0:
		_angle += cur / CIRCLE_R * delta
		_pivot.position = Vector3(cos(_angle), 0, sin(_angle)) * CIRCLE_R
		_pivot.rotation.y = -_angle  # tangent of the circle, facing -Z locally
	elif not moving:
		_pivot.position = Vector3.ZERO
	if _anim:
		_anim.update(state, cur)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_drag = mb.pressed
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_dist = maxf(1.5, _dist - 0.4)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_dist = minf(14.0, _dist + 0.4)
		_place_cam()
	elif event is InputEventMouseMotion and _drag:
		_yaw -= (event as InputEventMouseMotion).relative.x * 0.008
		_pitch = clampf(_pitch - (event as InputEventMouseMotion).relative.y * 0.008, -1.5, 0.3)
		_place_cam()
	elif event.is_action_pressed("pause"):
		AppFlow.goto("menu")


func _place_cam() -> void:
	if _cam == null:
		return
	var focus := Vector3(0, 0.9, 0)
	_cam.position = focus + Basis.from_euler(Vector3(_pitch, _yaw, 0)) * Vector3(0, 0, _dist)
	_cam.look_at(focus)


## Evidence captures (DebugCapture --action=audit|side|<slot index>).
func debug_action(action: String) -> void:
	match action:
		"side":
			_yaw = 1.5708
			_pitch = -0.1
			_place_cam()
		"walk":
			moving = true
			_set_state("walk")
		_:
			if action.is_valid_int():
				slot_index = int(action)
				_load_slot()

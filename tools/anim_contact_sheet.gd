extends SceneTree
## Animation contact sheets (D-040; bible p.25: "visual approval needs images").
## Poses a slot's real retargeted model at fixed clip times, renders each pose
## with a real GPU against a 1 m floor grid (plus a 1.05 m console block and a
## ground sample marker for actions) and tiles them into one PNG.
##   godot --path . --script res://tools/anim_contact_sheet.gd -- --sheet=locomotion --out=C:/abs/sheet.png
## Sheets: locomotion (captain gaits, side view), stops (captain stop/turn clips),
## actions (captain idle/interact/sample/build/idle_alt, 3/4 view),
## colonists (adult + child walk and idle variations). Dev tool; text not localized.

const CELL := Vector2i(420, 520)
const SHEETS := {
	"locomotion": {"slot": "char.captain", "view": "side", "cols": 6, "rows": [
		["walk_slow", [0.0, 0.17, 0.33, 0.5, 0.67, 0.83]], ["walk_mid", [0.0, 0.17, 0.33, 0.5, 0.67, 0.83]],
		["walk", [0.0, 0.17, 0.33, 0.5, 0.67, 0.83]], ["run", [0.0, 0.17, 0.33, 0.5, 0.67, 0.83]]]},
	"stops": {"slot": "char.captain", "view": "side", "cols": 6, "rows": [
		["stop_walk_l", [0.0, 0.2, 0.4, 0.6, 0.8, 1.0]], ["stop_walk_slow_r", [0.0, 0.2, 0.4, 0.6, 0.8, 1.0]],
		["turn_l", [0.0, 0.2, 0.4, 0.6, 0.8, 1.0]]]},
	"actions": {"slot": "char.captain", "view": "three_quarter", "cols": 5, "rows": [
		["idle", [0.0, 0.5]], ["interact", [0.25, 0.45, 0.65]], ["sample", [0.0, 0.33, 0.66]], ["build", [0.2, 0.6]],
		["idle_alt_look_l", [0.5]], ["idle_alt_watch", [0.5]], ["idle_alt_look_r", [0.5]], ["idle_alt_shift", [0.5]]]},
	"colonists": {"slot": "char.citizen_adult", "view": "three_quarter", "cols": 6, "rows": [
		["walk", [0.0, 0.25, 0.5, 0.75]], ["idle_alt_stretch", [0.45]], ["idle_alt_yawn", [0.5]],
		["idle_alt_think", [0.5]], ["idle_alt_watch", [0.5]], ["sample", [0.3]], ["build", [0.4]], ["idle", [0.2]],
		["@char.citizen_child", []], ["walk", [0.0, 0.25, 0.5, 0.75]], ["idle_alt_stretch", [0.45]], ["idle_alt_look_l", [0.5]]]},
}

var _sheet := "locomotion"
var _out := ""
var _jobs: Array = []  # [{slot, clip, phase}]
var _i := -1
var _wait := 0
var _img: Image
var _cols := 6
var _model: Node3D
var _slot := ""
var _ap: AnimationPlayer
var _label: Label3D
var _cam: Camera3D
var _props: Node3D
var _world: Node3D


func _initialize() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--sheet="):
			_sheet = a.substr(8)
		elif a.begins_with("--out="):
			_out = a.substr(6)
	if _out.is_empty():
		_out = "res://evidence/animation_pass/sheet_%s.png" % _sheet
	var spec: Dictionary = SHEETS[_sheet]
	_cols = int(spec["cols"])
	var slot := str(spec["slot"])
	for row: Array in spec["rows"]:
		var name := str(row[0])
		if name.begins_with("@"):
			slot = name.substr(1)
			continue
		for ph: float in row[1]:
			_jobs.append({"slot": slot, "clip": name, "phase": ph})
	_build_world(str(spec["view"]))
	var rows := int(ceil(_jobs.size() / float(_cols)))
	_img = Image.create(CELL.x * _cols, CELL.y * rows, false, Image.FORMAT_RGBA8)
	_img.fill(Color("#0d1216"))


func _build_world(view: String) -> void:
	_world = Node3D.new()
	root.add_child(_world)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("#1a2228")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("#9fb3bf")
	e.ambient_light_energy = 0.7
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	_world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, 30, 0)
	sun.shadow_enabled = true
	sun.light_energy = 1.2
	_world.add_child(sun)
	var fl := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(12, 12)
	fl.mesh = pm
	fl.material_override = _mat(Color("#2b3740"))
	_world.add_child(fl)
	for i: int in range(-6, 7):  # 1 m grid (0.25 m ticks along x so a planted foot reads)
		for along: int in 2:
			var ln := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(12, 0.004, 0.012) if along == 0 else Vector3(0.012, 0.004, 12)
			ln.mesh = bm
			ln.position = Vector3(0, 0.002, i) if along == 0 else Vector3(i, 0.002, 0)
			ln.material_override = _mat(Color("#6f8a97") if i == 0 else Color("#40525c"))
			_world.add_child(ln)
	for k: int in range(-24, 25):
		var t := MeshInstance3D.new()
		var tb := BoxMesh.new()
		tb.size = Vector3(0.008, 0.005, 0.12)
		t.mesh = tb
		t.position = Vector3(k * 0.25, 0.003, 0.0)
		t.material_override = _mat(Color("#8aa5b2"))
		_world.add_child(t)
	_props = Node3D.new()
	_world.add_child(_props)
	var console := MeshInstance3D.new()  # interact reference: top surface at 1.05 m, 0.55 m in front
	var cb := BoxMesh.new()
	cb.size = Vector3(0.7, 1.05, 0.35)
	console.mesh = cb
	console.position = Vector3(0, 0.525, -0.72)
	console.material_override = _mat(Color(0.35, 0.55, 0.65, 0.55), true)
	console.name = "Console"
	_props.add_child(console)
	var sample := MeshInstance3D.new()
	var cy := CylinderMesh.new()
	cy.top_radius = 0.09
	cy.bottom_radius = 0.12
	cy.height = 0.12
	sample.mesh = cy
	sample.position = Vector3(0, 0.06, -0.45)
	sample.material_override = _mat(Color("#d9a441"))
	sample.name = "Sample"
	_props.add_child(sample)
	_label = Label3D.new()
	_label.pixel_size = 0.0022
	_label.font_size = 50
	_label.outline_size = 12
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.position = Vector3(0, 2.15, 0)
	_world.add_child(_label)
	_cam = Camera3D.new()
	_cam.fov = 34
	_world.add_child(_cam)
	var focus := Vector3(0, 0.95, 0)
	if view == "side":
		_cam.look_at_from_position(Vector3(4.6, 1.05, 0.0), focus)  # character faces -Z: we look at its right side
	else:
		_cam.look_at_from_position(Vector3(2.6, 1.7, -3.2), focus)

	_cam.current = true


func _mat(c: Color, transparent: bool = false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.85
	if transparent:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m


func _use_slot(slot: String) -> void:
	if slot == _slot:
		return
	if _model:
		_model.queue_free()
	_slot = slot
	_model = (load("res://art/prefabs/%s.tscn" % slot) as PackedScene).instantiate()
	_world.add_child(_model)
	var libs := AnimationLibraryBuilder.load_mappings()
	_ap = CharacterAnimator.attach(_model, load(str(libs[slot])))


func _process(_d: float) -> bool:
	if not _cam.is_current():
		_cam.make_current()
	if _wait > 0:
		_wait -= 1
		return false
	if _i >= 0:
		# The window keeps its project size: crop the centre to the cell's aspect, then scale.
		var shot := root.get_texture().get_image()
		var h := shot.get_height()
		var w := int(h * float(CELL.x) / float(CELL.y))
		var cell := shot.get_region(Rect2i((shot.get_width() - w) / 2, 0, w, h))
		cell.resize(CELL.x, CELL.y, Image.INTERPOLATE_LANCZOS)
		cell.convert(Image.FORMAT_RGBA8)
		_img.blit_rect(cell, Rect2i(Vector2i.ZERO, CELL), Vector2i((_i % _cols) * CELL.x, (_i / _cols) * CELL.y))
	_i += 1
	if _i >= _jobs.size():
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out).get_base_dir())
		_img.save_png(_out)
		print("SHEET %s %d poses -> %s" % [_sheet, _jobs.size(), _out])
		quit(0)
		return true
	var j: Dictionary = _jobs[_i]
	_use_slot(str(j["slot"]))
	var clip := CharacterAnimator.LIB_NAME + "/" + str(j["clip"])
	if _ap and _ap.has_animation(clip):
		_ap.play(clip, 0.0)
		_ap.seek(float(j["phase"]) * _ap.current_animation_length, true)
		_ap.pause()
	var clip_name := str(j["clip"])
	(_props.get_node("Console") as Node3D).visible = clip_name in ["interact", "build", "idle"]
	(_props.get_node("Sample") as Node3D).visible = clip_name == "sample"
	_label.text = "%s %s  %d%%" % [str(j["slot"]).trim_prefix("char."), clip_name, int(float(j["phase"]) * 100.0)]
	_wait = 3
	return false

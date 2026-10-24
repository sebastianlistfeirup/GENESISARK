class_name BuildingView
extends Node3D
## Presentation of one colony building: its VisualSlot, a construction frame
## while building, module add-ons and a status marker with icon + text (never
## colour alone). Owns a pick collider on layer "buildings" (overhead clicks)
## and a walkable ShapeCollider body on "world" that follows the model's shape
## (scaffold footprint while under construction).

var building_id := 0
var def_id := ""
var _visual: VisualSlot
var _frame: Node3D
var _status: Label3D
var _modules: Node3D
var _size := Vector2(4, 4)
var _height := 3.0
var _last_state := ""
var _fx: Node3D
var _body: StaticBody3D
var _constructing := false
var _body_for := ""  # "frame" | "shape": what the walkable body currently follows
## Building-local set dressing (BuildingDressing.plan); ColonyDressing draws it.
var dressing: Array = []


func setup(b: Dictionary, terrain_height: float) -> void:
	building_id = int(b["id"])
	def_id = str(b["def_id"])
	var def := GameSession.content.building(def_id)
	_size = ColonySimulation.footprint_size(def, 0)
	position = Vector3(float(b["x"]), terrain_height, float(b["z"]))
	rotation.y = float(int(b.get("rot", 0))) * PI * 0.5
	_visual = VisualSlot.make(str(def.get("visual_slot", "building." + def_id)))
	_visual.rebuilt.connect(func() -> void:
		_body_for = ""
		if is_inside_tree():
			_fit_body(_constructing))
	add_child(_visual)
	_frame = Node3D.new()
	add_child(_frame)
	_modules = Node3D.new()
	add_child(_modules)
	dressing = BuildingDressing.plan(def_id, _size, building_id)
	var style := BuildingDressing.pad_style(def_id)
	if style != "none":
		# "pad": the plain slab (fresh clone). "skirt": a dark base under the Synty
		# platform tiles that hides the gap where the ground falls away.
		var pad := MeshInstance3D.new()
		var bm := BoxMesh.new()
		var grow := 1.0 if style == "pad" else BuildingDressing.platform_margin() * 2.0 - 0.1
		bm.size = Vector3(_size.x + grow, 0.3 if style == "pad" else 1.6, _size.y + grow)
		pad.mesh = bm
		pad.position.y = -0.1 if style == "pad" else -0.88
		pad.material_override = AssetSlots.material("#3b4a54" if style == "pad" else str(DictUtil.get_dict(BuildingDressing.doc(), "platform").get("skirt", "#2a3036")))
		add_child(pad)
	var sb := StaticBody3D.new()
	sb.collision_layer = 8
	sb.collision_mask = 0
	sb.set_meta("building_id", building_id)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	_height = 4.0 if def_id != "ark_core" else 9.0
	bs.size = Vector3(_size.x, _height, _size.y)
	cs.shape = bs
	cs.position.y = _height * 0.5
	sb.add_child(cs)
	add_child(sb)
	_status = Label3D.new()
	_status.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_status.no_depth_test = true
	_status.font_size = 72
	_status.pixel_size = 0.012
	_status.outline_size = 12
	_status.position.y = _height + 2.5
	add_child(_status)
	refresh(b)


## Walkable collision: the scaffold footprint while building, then the model's shape.
func _fit_body(constructing: bool) -> void:
	var want := "frame" if constructing else "shape"
	if want == _body_for:
		return
	_body_for = want
	if _body:
		remove_child(_body)
		_body.queue_free()
	var boxes: Array[AABB] = [AABB(Vector3(-_size.x * 0.5, 0, -_size.y * 0.5), Vector3(_size.x, 4.0, _size.y))]
	if not constructing:
		boxes = ShapeCollider.boxes_for(_visual, _visual.slot_id, _size, _height)
	_body = ShapeCollider.body(boxes)
	_body.set_meta("building_id", building_id)
	add_child(_body)
	var top := 0.0
	for bb: AABB in boxes:
		top = maxf(top, bb.end.y)
	if top > 0.5 and _status:
		_status.position.y = top + 2.0


## Walkable collision boxes (building space), for tests and debug views.
func collision_boxes() -> Array[AABB]:
	var out: Array[AABB] = []
	if _body:
		for cs: Node in _body.get_children():
			var bs := (cs as CollisionShape3D).shape as BoxShape3D
			out.append(AABB((cs as Node3D).position - bs.size * 0.5, bs.size))
	return out


func constructing() -> bool:
	return _constructing


func refresh(b: Dictionary) -> void:
	var state := str(b.get("state"))
	var constructing := state == ColonyState.B_CONSTRUCTING
	_constructing = constructing
	if _visual.is_inside_tree():
		_fit_body(constructing)
	else:
		_fit_body.call_deferred(constructing)
	_visual.visible = not constructing or float(b.get("progress", 0.0)) > 0.66
	_visual.scale = Vector3.ONE if not constructing else Vector3(1, maxf(0.15, float(b.get("progress", 0.0))), 1)
	if constructing != (_frame.get_child_count() > 0):
		UiKit.clear(_frame)
		if constructing:
			for corner: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
				var post := VisualSlot.make("building.construction_frame", "", Vector3(0.3, 4.0, 0.3))
				post.position = Vector3(corner.x * _size.x * 0.5, 0, corner.y * _size.y * 0.5)
				_frame.add_child(post)
			_fx = VisualSlot.make("fx.construction_sparks")
			_frame.add_child(_fx)
			AudioService.play_at("sfx_build_loop", _frame, -12.0, 45.0)  # freed with the frame
	UiKit.clear(_modules)
	var i := 0
	for m: Variant in b.get("modules", []):
		var mv := VisualSlot.make("building.module_" + str(m))
		mv.position = Vector3(_size.x * 0.5 + 1.0, 0, -_size.y * 0.3 + i * 2.0)
		_modules.add_child(mv)
		i += 1
	var reason := str(b.get("blocked_reason", ""))
	if constructing:
		_status.text = "⚙ %d%%" % int(float(b.get("progress", 0.0)) * 100.0)
		_status.modulate = UiKit.AMBER
		if reason == "no_access" or reason == "no_workforce":
			_status.text += "\n▲ " + (Loc.t("no access") if reason == "no_access" else Loc.t("waiting for drones"))
	elif not reason.is_empty():
		_status.text = "▲ " + {"no_power": Loc.t("no power"), "no_access": Loc.t("no access"), "no_workforce": Loc.t("no labor"),
			"maintenance": Loc.t("maintenance"), "input_missing": Loc.t("missing raw materials"), "module_missing": Loc.t("missing module")}.get(reason, reason)
		_status.modulate = UiKit.DANGER if reason in ["no_power", "no_access", "module_missing"] else UiKit.WARN
	else:
		_status.text = ""
	if state != _last_state and state == ColonyState.B_ACTIVE and _last_state == ColonyState.B_CONSTRUCTING:
		AudioService.play("sfx_build_done", "SFX", -6.0)
	_last_state = state


func set_selected(on: bool) -> void:
	_visual.tint = ""
	if on:
		_status.text = ("◆ " + str(GameSession.content.building(def_id).get("name"))) if _status.text.is_empty() else _status.text

class_name ShipDresser
extends RefCounted
## Furnishes the ark's rooms along their walls (data/art/ship_dressing.json):
## standing props with box collision in a strip against the wall, mounted panels
## and pipes higher up. Doorways, door cells and the ground around every marker
## (interactables, cryo pods, spawn) stay clear, so routes and prompts are
## untouched. Deterministic per cell. Pieces whose purchased source is missing
## are skipped. Presentation only.

const PATH := "res://data/art/ship_dressing.json"
const DIRS := [[0, -1], [0, 1], [-1, 0], [1, 0]]

static var _scenes: Dictionary = {}


static func dress(b: ShipBuilder) -> Node3D:
	var root := Node3D.new()
	root.name = "Dressing"
	var doc: Variant = DictUtil.load_json(PATH)
	if not doc is Dictionary:
		return root
	var mat_path := str(doc.get("material", ""))
	var mat: Material = load(mat_path) if ResourceLoader.exists(mat_path) else null
	var keep := DictUtil.get_float(doc, "keep_clear", 2.6)
	var inset := DictUtil.get_float(doc, "inset", 0.75)
	var zones: Dictionary = DictUtil.get_dict(doc, "zones")
	var clear: Array[Vector3] = [b.spawn]
	for m: Dictionary in b.interact_markers:
		clear.append(m["pos"])
	for m: Variant in b.markers:
		var cpos: Array = DictUtil.get_arr(m, "cell")
		if cpos.size() == 2:
			clear.append(b.cell_to_world(float(cpos[0]), float(cpos[1])))
	var body := StaticBody3D.new()
	body.name = "DressingCollision"
	body.collision_layer = 1
	root.add_child(body)
	for r: int in b.rows.size():
		for c: int in str(b.rows[r]).length():
			var z := b._zone(c, r)
			if not zones.has(z):
				continue
			var spec: Dictionary = zones[z]
			var center := b._cell_center(c, r)
			for i: int in DIRS.size():
				var d: Array = DIRS[i]
				var nz := b._zone(c + int(d[0]), r + int(d[1]))
				if nz != "#":
					continue  # only real walls; never in front of a doorway
				var h := absi(hash(Vector3i(c, r, i)))
				if float(h % 1000) / 1000.0 > DictUtil.get_float(spec, "chance", 0.5):
					continue
				var outward := Vector3(float(d[0]), 0, float(d[1]))
				var along := Vector3(-outward.z, 0, outward.x)
				var slide := (float((h / 1000) % 100) / 100.0 - 0.5) * b.cell * 0.5
				var wall_pt := center + outward * (b.cell * 0.5)
				var floor_pt := wall_pt - outward * inset + along * slide
				var yaw := atan2(-outward.x, -outward.z)  # Synty fronts face +Z: turn them into the room
				if _near(floor_pt, clear, keep):
					continue
				var floors: Array = DictUtil.get_arr(spec, "floor")
				if not floors.is_empty():
					var inst := _place(root, str(floors[h % floors.size()]), floor_pt, yaw, mat)
					if inst:
						_collide(body, inst)
				var walls: Array = DictUtil.get_arr(spec, "wall")
				if not walls.is_empty() and (h / 7) % 2 == 0:
					var w: Array = walls[(h / 13) % walls.size()]
					_place(root, str(w[0]), wall_pt - outward * 0.45 - along * slide * 0.6 + Vector3(0, float(w[1]), 0), yaw, mat)
	# Set pieces at fixed cells (bridge crew stations, cryo wall pods, sleepers in tubes).
	for sp: Variant in DictUtil.get_arr(doc, "set_pieces"):
		var d: Dictionary = sp
		var cell: Array = DictUtil.get_arr(d, "cell")
		if cell.size() != 2:
			continue
		var pos := b.cell_to_world(float(cell[0]), float(cell[1])) + Vector3(0, DictUtil.get_float(d, "y"), 0)
		var pm: Material = mat
		if d.has("material"):
			pm = load(str(d["material"])) if ResourceLoader.exists(str(d["material"])) else mat
		var inst := _place(root, str(d.get("mesh", "")), pos, deg_to_rad(DictUtil.get_float(d, "yaw")), pm)
		if inst == null:
			continue
		inst.scale = Vector3.ONE * DictUtil.get_float(d, "scale", 1.0)
		if bool(d.get("center", true)):
			# Kit pieces carry their assembly offset: stand them centred on the cell, base on the floor.
			var box := AssetSlots.aabb_of(inst, Transform3D(Basis(Vector3.UP, inst.rotation.y).scaled(inst.scale), Vector3.ZERO))
			inst.position -= Vector3(box.get_center().x, box.position.y, box.get_center().z)
		if bool(d.get("collide", false)):
			_collide(body, inst)
	# Holograms over the consoles of the bridge and the embryo bank.
	var holo: Dictionary = DictUtil.get_dict(doc, "holograms")
	for m: Dictionary in b.interact_markers:
		var z := b.zone_at(m["pos"])
		if not holo.has(z):
			continue
		var h := Hologram.make(Color(str(holo[z])), 0.9, absi(hash(str(m["id"]))))
		h.position = (m["pos"] as Vector3) + Vector3(0, 2.15, 0)
		root.add_child(h)
	return root


static func _near(p: Vector3, pts: Array[Vector3], dist: float) -> bool:
	for q: Vector3 in pts:
		if Vector2(p.x - q.x, p.z - q.z).length() < dist:
			return true
	return false


static func _place(root: Node3D, name: String, pos: Vector3, yaw: float, mat: Material) -> Node3D:
	var path := "res://assets/Synty/SciFiSpace/FBX/%s.fbx" % name
	if not _scenes.has(path):
		_scenes[path] = load(path) if ResourceLoader.exists(path) else null
	var ps: PackedScene = _scenes[path]
	if ps == null:
		return null
	var inst: Node3D = ps.instantiate()
	inst.position = pos
	inst.rotation.y = yaw
	if mat:
		for mi: Node in inst.find_children("*", "MeshInstance3D", true, false):
			(mi as MeshInstance3D).material_override = mat
	root.add_child(inst)
	return inst


static func _collide(body: StaticBody3D, inst: Node3D) -> void:
	var box := AssetSlots.aabb_of(inst, Transform3D.IDENTITY)
	if box.size.length() < 0.2:
		return
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(maxf(box.size.x, 0.2), maxf(box.size.y, 0.2), maxf(box.size.z, 0.2))
	cs.shape = shape
	cs.transform = Transform3D(Basis(Vector3.UP, inst.rotation.y), inst.position + Basis(Vector3.UP, inst.rotation.y) * box.get_center())
	body.add_child(cs)

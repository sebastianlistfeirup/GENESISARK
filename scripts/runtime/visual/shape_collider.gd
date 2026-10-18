class_name ShapeCollider
extends RefCounted
## Walkable collision that follows a visual's real shape (proxy or imported
## Synty wrapper), so the captain bumps into walls and tanks, not into an
## invisible footprint box. Vendor scenes stay untouched: we read their mesh
## bounds and build our own StaticBody3D (bible p.23: collision is ours).
##
## Per-slot override in data/art/asset_slots.json, key "collision":
##   "boxes" (default)  one box per mesh part, small/flat parts dropped, merged to <= MAX_BOXES
##   "footprint"        one box: building footprint x height
##   "none"             no walkable collision (pick box only)
##   [{"size": [x,y,z], "pos": [x,y,z]}, ...]  hand-placed boxes (slot space)

const MAX_BOXES := 12
const MIN_HEIGHT := 0.25  # floor plates, decals, cables: walk over them
const MIN_WIDTH := 0.2    # antennas, rails: not worth a collider


## Boxes in `root`'s local space for every visible mesh below it.
static func mesh_boxes(root: Node3D, max_boxes: int = MAX_BOXES) -> Array[AABB]:
	var out: Array[AABB] = []
	_collect(root, Transform3D.IDENTITY, out, true)
	out = _drop_contained(out)
	while out.size() > max_boxes:
		_merge_cheapest(out)
	return out


static func _collect(n: Node, xf: Transform3D, out: Array[AABB], is_root: bool) -> void:
	if n is Node3D and not (n as Node3D).visible:
		return
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		var bb: AABB = xf * (n as MeshInstance3D).get_aabb()
		if bb.size.y >= MIN_HEIGHT and maxf(bb.size.x, bb.size.z) >= MIN_WIDTH:
			out.append(bb)
	for c: Node in n.get_children():
		var cxf := xf * (c as Node3D).transform if c is Node3D else xf
		_collect(c, cxf, out, false)


static func _drop_contained(boxes: Array[AABB]) -> Array[AABB]:
	var out: Array[AABB] = []
	for i: int in boxes.size():
		var inside := false
		for j: int in boxes.size():
			if i != j and boxes[j].grow(0.01).encloses(boxes[i]) and (not boxes[i].is_equal_approx(boxes[j]) or j < i):
				inside = true
				break
		if not inside:
			out.append(boxes[i])
	return out


## Merges the pair whose union adds the least volume (keeps L-shapes as long as possible).
static func _merge_cheapest(boxes: Array[AABB]) -> void:
	var best := Vector2i(0, 1)
	var best_cost := INF
	for i: int in boxes.size():
		for j: int in range(i + 1, boxes.size()):
			var cost := boxes[i].merge(boxes[j]).get_volume() - boxes[i].get_volume() - boxes[j].get_volume()
			if cost < best_cost:
				best_cost = cost
				best = Vector2i(i, j)
	boxes[best.x] = boxes[best.x].merge(boxes[best.y])
	boxes.remove_at(best.y)


## Boxes for a slot's visual, honouring the slot's "collision" override.
## `footprint` (x, z) and `height` describe the fallback box.
static func boxes_for(visual: Node3D, slot_id: String, footprint: Vector2, height: float) -> Array[AABB]:
	var mode: Variant = AssetSlots.slot(slot_id).get("collision", "boxes")
	var fallback: Array[AABB] = [AABB(Vector3(-footprint.x * 0.5, 0, -footprint.y * 0.5), Vector3(footprint.x, height, footprint.y))]
	if mode is Array:
		var out: Array[AABB] = []
		for b: Dictionary in mode:
			var s: Array = DictUtil.get_arr(b, "size")
			var p: Array = DictUtil.get_arr(b, "pos")
			if s.size() == 3 and p.size() == 3:
				var size := Vector3(float(s[0]), float(s[1]), float(s[2]))
				out.append(AABB(Vector3(float(p[0]), float(p[1]), float(p[2])) - size * 0.5, size))
		return out if not out.is_empty() else fallback
	match str(mode):
		"none":
			return []
		"footprint":
			return fallback
	var boxes := mesh_boxes(visual)
	return boxes if not boxes.is_empty() else fallback


## StaticBody3D on the "world" layer (captain and camera collide with it).
static func body(boxes: Array[AABB]) -> StaticBody3D:
	var sb := StaticBody3D.new()
	sb.name = "ShapeCollision"
	sb.collision_layer = 1
	sb.collision_mask = 0
	for bb: AABB in boxes:
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = bb.size
		cs.shape = bs
		cs.position = bb.get_center()
		sb.add_child(cs)
	return sb

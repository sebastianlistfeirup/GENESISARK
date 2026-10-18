@tool
class_name VisualSlot
extends Node3D
## Presentation-only node. Shows the mapped Synty scene for `slot_id`, or the
## greybox proxy. Never owns collision or gameplay (bible p.23: vendor files
## are read-only; controller, collision and VisualRig are separate).

@export var slot_id: String = "":
	set(v):
		slot_id = v
		if is_inside_tree():
			rebuild()
## Optional colour override for the proxy (e.g. planet palette, hazard colour).
@export var tint: String = ""
## Stretch the proxy (not imported scenes) to a footprint, e.g. building sizes.
@export var proxy_scale: Vector3 = Vector3.ONE
## Which imported variant to show when a slot has several (Rock_01..Rock_06).
## -1 = pick from the world position: varied, but the same spot always gets the same model.
@export var variant: int = -1

var using_asset := false

## Emitted after the proxy or asset is (re)built, e.g. to refit collision.
signal rebuilt


func _ready() -> void:
	rebuild()


func rebuild() -> void:
	for c: Node in get_children():
		if c.name == "Proxy" or c.name == "Asset":
			remove_child(c)
			c.queue_free()
	if slot_id.is_empty():
		return
	var n := AssetSlots.variant_count(slot_id)
	var idx := variant
	if idx < 0 and n > 1:
		var at := global_position if is_inside_tree() else position
		idx = absi(hash(Vector3i(roundi(at.x * 2.0), roundi(at.y * 2.0), roundi(at.z * 2.0))))
	var ps := AssetSlots.scene_for(slot_id, maxi(idx, 0))
	if ps:
		var inst: Node3D = ps.instantiate()
		inst.name = "Asset"
		var s: Dictionary = AssetSlots.slot(slot_id)
		var sc := DictUtil.get_float(s, "scale", 1.0)
		inst.scale = Vector3.ONE * sc
		var off: Array = DictUtil.get_arr(s, "offset")
		if off.size() == 3:
			inst.position = Vector3(float(off[0]), float(off[1]), float(off[2]))
		inst.rotation_degrees.y = DictUtil.get_float(s, "rotation_y")
		add_child(inst)
		using_asset = true
	else:
		var p := AssetSlots.build_proxy(slot_id, tint)
		p.scale = proxy_scale
		add_child(p)
		using_asset = false
	rebuilt.emit()


static func make(id: String, color_tint: String = "", stretch: Vector3 = Vector3.ONE) -> VisualSlot:
	var v := VisualSlot.new()
	v.slot_id = id
	v.tint = color_tint
	v.proxy_scale = stretch
	v.name = id.replace(".", "_")
	return v

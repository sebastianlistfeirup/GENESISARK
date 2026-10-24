class_name ShadowLod
extends Node
## Shadow casting by size and distance (D-054). Every caster is drawn again in
## each shadow cascade it touches, yet the shadow of a small piece far away is
## a few soft pixels: a crate keeps its shadow while the camera is closer than
## NEAR_PER_M metres per metre of its size (0.5 m -> 50 m, 1 m -> 100 m), then
## stops casting; pieces of MAX_SIZE and up always cast (the sun's shadow
## distance ends first). Registered pieces only (MeshLod), presentation only.
## One small node under the root updates a slice of the list per frame.

const NEAR_PER_M := 80.0
const MAX_SIZE := 1.6
const SLICE := 160
const HYSTERESIS := 1.1

static var _items: Array = []  # [GeometryInstance3D, size (m, -1 = measure), casting setting, on, twin, world AABB, origin]
static var _node: ShadowLod
static var _fresh := 0  # registered since the last frame: all of them are looked at at once
static var enabled := true

var _cursor := 0


## Track a caster whose largest world-space side is `size` metres (-1: measure it
## once it is in the tree). Bigger pieces are ignored. A shadow-only twin
## (MeshLod) is switched by visibility instead (it must never draw normally).
static func register(gi: GeometryInstance3D, size: float = -1.0) -> void:
	if not enabled or gi == null or gi.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
		return
	if size >= MAX_SIZE:
		return
	var twin := gi.has_meta("is_shadow_twin")
	if gi.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY and not twin:
		return  # someone else's shadow proxy: not ours to switch
	_items.append([gi, size, gi.cast_shadow, true, twin, AABB(), Vector3.INF])
	_fresh += 1
	if _node == null or not is_instance_valid(_node):
		var ml := Engine.get_main_loop()
		if ml is SceneTree:
			_node = ShadowLod.new()
			_node.name = "ShadowLod"
			(ml as SceneTree).root.add_child.call_deferred(_node)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null or _items.is_empty():
		return
	var eye := cam.global_position
	# A new scene registers thousands at once: settle them all in one frame, then
	# keep a small slice per frame. Dropping dead entries costs no budget.
	var n := mini(SLICE + _fresh, _items.size())
	_fresh = 0
	var guard := _items.size() + n
	while n > 0 and guard > 0:
		guard -= 1
		if _items.is_empty():
			return
		if _cursor >= _items.size():
			_cursor = 0
		var it: Array = _items[_cursor]
		var gi: GeometryInstance3D = it[0] if is_instance_valid(it[0]) else null
		if gi != null and gi.is_inside_tree():
			var o := gi.global_position
			if o != it[6]:  # moved (or first visit): measure again
				it[6] = o
				it[5] = gi.global_transform * gi.get_aabb()
				if float(it[1]) < 0.0:
					var b0: AABB = it[5]
					it[1] = maxf(b0.size.x, maxf(b0.size.y, b0.size.z))
		# Freed, its shadow now comes from a twin (MeshLod), or too big to matter: drop it.
		if gi == null or gi.has_meta("has_shadow_twin") or float(it[1]) >= MAX_SIZE:
			_items[_cursor] = _items[-1]
			_items.pop_back()
			continue
		_cursor += 1
		n -= 1
		if not gi.is_inside_tree() or float(it[1]) < 0.0:
			continue
		var box: AABB = it[5]
		var size := float(it[1])
		var d := eye.distance_to(eye.clamp(box.position, box.end))
		var reach := NEAR_PER_M * size * (HYSTERESIS if bool(it[3]) else 1.0)
		var on := d < reach
		if on != bool(it[3]):
			_switch(gi, it, on)


## Only undoes what it did itself: a setting another script changed meanwhile
## (a hologram turning its shadow off) is left alone.
static func _switch(gi: GeometryInstance3D, it: Array, on: bool) -> void:
	it[3] = on
	if bool(it[4]):
		gi.visible = on
	elif not on:
		if gi.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			it[3] = true  # already off by someone else: stays theirs
			return
		it[2] = gi.cast_shadow
		gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	elif gi.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
		gi.cast_shadow = int(it[2])


func _exit_tree() -> void:
	if _node == self:
		_node = null

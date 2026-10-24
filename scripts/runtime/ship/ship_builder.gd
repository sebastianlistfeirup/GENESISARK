@tool
class_name ShipBuilder
extends Node3D
## Builds the ark interior from data/levels/ark_interior.json: floors, walls,
## windows, doors, lights and markers, all as VisualSlots (ship.*) plus simple
## box collision. Swap ship.* slots to a Synty modular kit and the whole ship
## updates. @tool: tick "build_now" in the editor to preview/dress the layout.

signal built

const LAYOUT := "res://data/levels/ark_interior.json"

@export var build_now: bool = false:
	set(v):
		build_now = false
		if Engine.is_editor_hint() and is_inside_tree():
			build()

var cell := 4.0
var wall_h := 3.6
var rows: Array = []
var zones: Dictionary = {}
var origin := Vector3.ZERO
var markers: Array = []
var lights: Array = []          # [{light: OmniLight3D, zone: String}]
var interact_markers: Array = []  # [{id, slot, pos, yaw}]
var spawn := Vector3.ZERO
var spawn_yaw := 0.0
var embryo_display_pos := Vector3.ZERO
var ai_pos := Vector3.ZERO


func build() -> void:
	for c: Node in get_children():
		remove_child(c)
		c.queue_free()
	lights.clear()
	interact_markers.clear()
	var d: Variant = DictUtil.load_json(LAYOUT)
	if not d is Dictionary:
		push_error("ShipBuilder: kan ikke læse %s" % LAYOUT)
		return
	cell = DictUtil.get_float(d, "cell_size", 4.0)
	wall_h = DictUtil.get_float(d, "wall_height", 3.6)
	rows = DictUtil.get_arr(d, "rows")
	zones = DictUtil.get_dict(d, "zones")
	markers = DictUtil.get_arr(d, "markers")
	var w := str(rows[0]).length()
	origin = Vector3(-w * cell * 0.5, 0, -rows.size() * cell * 0.5)
	var windows := {}
	for win: Dictionary in DictUtil.get_arr(d, "windows"):
		for c: Variant in DictUtil.get_arr(win, "cols"):
			windows["%d:%d:%s" % [int(c), int(win.get("row")), str(win.get("side"))]] = true
	var geo := Node3D.new()
	geo.name = "Geometry"
	add_child(geo)
	var body := StaticBody3D.new()
	body.name = "Collision"
	body.collision_layer = 1
	add_child(body)
	for r: int in rows.size():
		for c: int in w:
			var z := _zone(c, r)
			if z == "#":
				continue
			var center := _cell_center(c, r)
			var fl := VisualSlot.make("ship.floor")
			fl.position = center
			geo.add_child(fl)
			_box_collider(body, center + Vector3(0, -0.1, 0), Vector3(cell, 0.2, cell))
			_box_collider(body, center + Vector3(0, wall_h + 0.1, 0), Vector3(cell, 0.2, cell))
			var ceil_slot := VisualSlot.make("ship.ceiling")
			ceil_slot.position = center + Vector3(0, wall_h, 0)
			geo.add_child(ceil_slot)
			for dir: Array in [[0, -1, "north"], [0, 1, "south"], [-1, 0, "west"], [1, 0, "east"]]:
				var nz := _zone(c + int(dir[0]), r + int(dir[1]))
				var needs := nz == "#" or (nz != z and z != "D" and nz != "D")
				if not needs:
					continue
				var edge := center + Vector3(float(dir[0]), 0, float(dir[1])) * cell * 0.5
				var slot := "ship.wall_window" if windows.has("%d:%d:%s" % [c, r, dir[2]]) else "ship.wall"
				var wall := VisualSlot.make(slot)
				wall.position = edge
				wall.rotation.y = 0.0 if int(dir[0]) == 0 else PI * 0.5
				if int(dir[1]) == 1 or int(dir[0]) == 1:
					wall.rotation.y += PI  # Face inward
				geo.add_child(wall)
				_box_collider(body, edge + Vector3(0, wall_h * 0.5, 0), Vector3(cell if int(dir[0]) == 0 else 0.3, wall_h, 0.3 if int(dir[0]) == 0 else cell))
				if slot == "ship.wall_window" and not AssetSlots.scene_path("ship.wall_window").is_empty():
					pass  # a real window frame: the nebula sky shows through it
				elif slot == "ship.wall_window":
					var sky := VisualSlot.make("ship.window_space")
					sky.position = edge + Vector3(float(dir[0]), 0, float(dir[1])) * 0.4
					sky.rotation.y = wall.rotation.y
					geo.add_child(sky)
			if z == "D":
				var door := VisualSlot.make("ship.door")
				door.position = center
				var vertical := _zone(c, r - 1) != "#" and _zone(c, r + 1) != "#"
				door.rotation.y = 0.0 if vertical else PI * 0.5
				geo.add_child(door)
			# Lights on a checkerboard so rooms read clearly without dozens of lights.
			if (c + r) % 2 == 0 and z != "D":
				var lamp := VisualSlot.make("ship.ceiling_light")
				lamp.position = center
				geo.add_child(lamp)
				if (c + r) % 4 == 0 or z != ".":
					var ol := OmniLight3D.new()
					ol.position = center + Vector3(0, wall_h - 0.4, 0)
					ol.omni_range = cell * 2.2
					ol.light_energy = 0.9
					ol.omni_attenuation = 1.4
					ol.shadow_enabled = false
					add_child(ol)
					lights.append({"light": ol, "zone": z, "lamp": lamp})
	_place_markers()
	add_child(ShipDresser.dress(self))
	built.emit()


func _place_markers() -> void:
	var props := Node3D.new()
	props.name = "Props"
	add_child(props)
	for m: Dictionary in markers:
		var cpos: Array = DictUtil.get_arr(m, "cell")
		var pos := cell_to_world(float(cpos[0]), float(cpos[1])) if cpos.size() == 2 else Vector3.ZERO
		var yaw := deg_to_rad(DictUtil.get_float(m, "yaw"))
		match str(m.get("type")):
			"spawn":
				spawn = pos
				spawn_yaw = yaw
			"prop", "cryo_pod":
				var v := VisualSlot.make(str(m.get("slot", "ship.cryo_pod")))
				v.position = pos
				v.rotation.y = yaw
				props.add_child(v)
				_prop_collider(props, pos, Vector3(1.2, 1.2, 1.2) if m.get("type") == "prop" else Vector3(1.1, 1.0, 2.3), yaw)
			"interact":
				interact_markers.append({"id": str(m.get("id")), "slot": str(m.get("slot")), "pos": pos, "yaw": yaw})
			"embryo_tanks":
				var spacing := DictUtil.get_float(m, "spacing", 1.6)
				var gap: Array = DictUtil.get_arr(m, "gap")
				for rr: Variant in DictUtil.get_arr(m, "rows"):
					var col := DictUtil.get_float(m, "from_col")
					while col <= DictUtil.get_float(m, "to_col") + 0.01:
						if gap.size() == 2 and col > float(gap[0]) and col < float(gap[1]):
							col += spacing / cell
							continue
						var t := VisualSlot.make("ship.embryo_tank")
						t.position = cell_to_world(col, float(rr))
						props.add_child(t)
						_prop_collider(props, t.position, Vector3(1.0, 2.4, 1.0), 0.0)
						col += spacing / cell
			"embryo_display":
				embryo_display_pos = pos
			"ai":
				ai_pos = pos


func cell_to_world(col: float, row: float) -> Vector3:
	return origin + Vector3(col * cell, 0, row * cell)


func _cell_center(c: int, r: int) -> Vector3:
	return origin + Vector3((c + 0.5) * cell, 0, (r + 0.5) * cell)


func _zone(c: int, r: int) -> String:
	if r < 0 or r >= rows.size():
		return "#"
	var row := str(rows[r])
	if c < 0 or c >= row.length():
		return "#"
	return row[c]


func zone_at(pos: Vector3) -> String:
	var local := pos - origin
	return _zone(int(floor(local.x / cell)), int(floor(local.z / cell)))


func _box_collider(body: StaticBody3D, pos: Vector3, size: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = size
	cs.shape = b
	cs.position = pos
	body.add_child(cs)


func _prop_collider(parent: Node3D, pos: Vector3, size: Vector3, yaw: float) -> void:
	var sb := StaticBody3D.new()
	sb.collision_layer = 1
	sb.position = pos + Vector3(0, size.y * 0.5, 0)
	sb.rotation.y = yaw
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = size
	cs.shape = b
	sb.add_child(cs)
	parent.add_child(sb)


## Emergency (dim red, flicker-free) vs restored (zone colours).
const ATLAS := "res://art/materials/scifi_space_atlas.tres"


## The atlas' painted light strips follow the power: dim amber on emergency power.
static func set_strip_glow(restored: bool) -> void:
	if not ResourceLoader.exists(ATLAS):
		return
	var m := load(ATLAS) as ShaderMaterial
	if m:
		m.set_shader_parameter("glow_tint", Color(1, 1, 1) if restored else Color(1.0, 0.5, 0.1))  # amber: "follow the yellow service lights"
		m.set_shader_parameter("tint_amount", 0.0 if restored else 1.0)
		m.set_shader_parameter("glow_energy", 2.4 if restored else 0.9)


var _flicker: Array = []  # emergency lamps that stutter while the ship is on emergency power
var _flicker_t := 0.0


func set_power(restored: bool) -> void:
	set_strip_glow(restored)
	_flicker.clear()
	if not restored and not FxEffect.reduced_motion():
		for i: int in lights.size():
			if i % 5 == 2:
				_flicker.append(lights[i]["light"])
	set_process(not _flicker.is_empty())
	for l: Dictionary in lights:
		var ol: OmniLight3D = l["light"]
		if restored:
			ol.light_color = Color.from_string(str(zones.get(l["zone"], {}).get("light", "#d8e2e6")), Color.WHITE)
			ol.light_energy = 2.1
		else:
			ol.light_color = Color("c0392b") if l["zone"] != "." else Color("e8a33d")
			ol.light_energy = 0.7 if (lights.find(l) % 2 == 0 or l["zone"] == ".") else 0.0
		(l["lamp"] as Node3D).visible = restored


func _process(delta: float) -> void:
	if _flicker.is_empty() or Engine.is_editor_hint():
		return
	_flicker_t += delta
	for i: int in _flicker.size():
		var ol: OmniLight3D = _flicker[i]
		var n := sin(_flicker_t * 23.0 + i * 7.0) + sin(_flicker_t * 37.0 + i * 3.0)
		ol.light_energy = 0.0 if n > 1.55 else 0.7

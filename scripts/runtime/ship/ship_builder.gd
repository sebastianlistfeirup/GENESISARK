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
var power_nodes: Array = []     # [{node, on: bool} | {node, screen: true}]: dressing that follows the ship's power
var ambient: Dictionary = {}    # ship_dressing.json "ambient": {power: [hex, energy], emergency: [hex, energy]}
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
	power_nodes.clear()
	_graded.clear()
	var d: Variant = DictUtil.load_json(LAYOUT)
	if not d is Dictionary:
		push_error("ShipBuilder: kan ikke læse %s" % LAYOUT)
		return
	cell = DictUtil.get_float(d, "cell_size", 4.0)
	wall_h = DictUtil.get_float(d, "wall_height", 3.6)
	rows = DictUtil.get_arr(d, "rows")
	zones = DictUtil.get_dict(d, "zones")
	markers = DictUtil.get_arr(d, "markers")
	var dressing: Variant = DictUtil.load_json(ShipDresser.PATH)
	ambient = DictUtil.get_dict(dressing, "ambient") if dressing is Dictionary else {}
	var ceil_mat := _graded_atlas(str(dressing.get("ceiling_grade", "")) if dressing is Dictionary else "")
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
			if ceil_mat:
				for mi: Node in ceil_slot.find_children("*", "MeshInstance3D", true, false):
					(mi as MeshInstance3D).material_override = ceil_mat
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
const EMERGENCY_ENERGY := 1.15  # red pools strong enough to carry the darker emergency shade
const ATLAS := "res://art/materials/scifi_space_atlas.tres"


static var _graded: Array[ShaderMaterial] = []  # graded copies of the atlas (ceiling) that follow the power too


## The ceilings sat right above the lamps and filled every wide shot flat pale grey:
## a darker graded copy of the atlas (albedo_mul), still glowing with the power.
func _graded_atlas(hex: String) -> ShaderMaterial:
	if hex.is_empty() or not ResourceLoader.exists(ATLAS):
		return null
	var base := load(ATLAS) as ShaderMaterial
	if base == null:
		return null
	var m := base.duplicate() as ShaderMaterial
	m.set_shader_parameter("albedo_mul", Color(hex))
	_graded.append(m)
	return m


## The atlas' painted light strips follow the power: dim amber on emergency power.
static func set_strip_glow(restored: bool) -> void:
	if not ResourceLoader.exists(ATLAS):
		return
	var all: Array[ShaderMaterial] = [load(ATLAS) as ShaderMaterial]
	all.append_array(_graded)
	for m: ShaderMaterial in all:
		if m == null:
			continue
		m.set_shader_parameter("glow_tint", Color(1, 1, 1) if restored else Color(1.0, 0.5, 0.1))  # amber: "follow the yellow service lights"
		m.set_shader_parameter("tint_amount", 0.0 if restored else 1.0)
		m.set_shader_parameter("glow_energy", 2.4 if restored else 0.9)


var _wave_tween: Tween
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
			ol.light_energy = EMERGENCY_ENERGY if (lights.find(l) % 2 == 0 or l["zone"] == ".") else 0.0
		(l["lamp"] as Node3D).visible = restored
	for p: Dictionary in power_nodes:
		var n: Node3D = p["node"]
		if not is_instance_valid(n):
			continue
		if p.has("screen"):
			(n as HoloScreen).set_powered(restored)
		else:
			n.visible = restored == bool(p["on"])


## Power coming back (D-061): a stutter, a beat of total darkness, then the lights
## and consoles switch on in a wave rolling outward from the coupling, each lamp
## flaring past its level and settling (anticipation, action, follow-through).
## Calls `done` when the last lamp is on. Reduced motion: instant.
func power_wave(origin: Vector3, done: Callable = Callable()) -> void:
	if FxEffect.reduced_motion():
		set_power(true)
		if done.is_valid():
			done.call()
		return
	_flicker.clear()
	set_process(false)
	if _wave_tween and _wave_tween.is_valid():
		_wave_tween.kill()
	var tw := create_tween().set_parallel(true)
	_wave_tween = tw
	var last := 0.0
	var first_lamp: Dictionary = {}  # zone -> [delay, lamp]: one clunk per section, where the wave first lights it (D-064)
	for i: int in lights.size():
		var l: Dictionary = lights[i]
		var ol: OmniLight3D = l["light"]
		var lamp: Node3D = l["lamp"]
		if not is_instance_valid(ol) or not is_instance_valid(lamp):
			continue
		var e0 := ol.light_energy
		# Stutter, then everything drops out.
		tw.tween_property(ol, "light_energy", e0 * 1.6, 0.06).set_delay(0.05 + (i % 3) * 0.04)
		tw.tween_property(ol, "light_energy", 0.0, 0.05).set_delay(0.18 + (i % 3) * 0.04)
		tw.tween_property(ol, "light_energy", e0, 0.04).set_delay(0.3)
		tw.tween_property(ol, "light_energy", 0.0, 0.08).set_delay(0.42)
		var delay := 0.85 + ol.global_position.distance_to(origin) / 42.0
		last = maxf(last, delay)
		if not first_lamp.has(l["zone"]) or delay < float(first_lamp[l["zone"]][0]):
			first_lamp[l["zone"]] = [delay, lamp]
		var col := Color.from_string(str(zones.get(l["zone"], {}).get("light", "#d8e2e6")), Color.WHITE)
		tw.tween_callback(func() -> void:
			ol.light_color = col
			lamp.visible = true).set_delay(delay)
		tw.tween_property(ol, "light_energy", 3.4, 0.09).set_delay(delay)
		tw.tween_property(ol, "light_energy", 2.1, 0.45).set_delay(delay + 0.09).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	for p: Dictionary in power_nodes:
		var n: Node3D = p["node"]
		if not is_instance_valid(n):
			continue
		var d := 0.95 + n.global_position.distance_to(origin) / 42.0
		if p.has("screen"):
			tw.tween_callback((n as HoloScreen).set_powered.bind(true)).set_delay(d)
		else:
			tw.tween_callback(func() -> void: n.visible = bool(p["on"])).set_delay(d)
	tw.tween_callback(set_strip_glow.bind(true)).set_delay(0.85 + (last - 0.85) * 0.4)
	if not Engine.is_editor_hint():
		# Sound (D-064): a rising electrical hum rolls with the wave, and each section's
		# lamps clunk on where the wave reaches them (positional).
		tw.tween_callback(AudioService.play.bind("sfx_power_surge", "SFX", -5.0)).set_delay(0.7)
		for z: Variant in first_lamp.keys():
			var fl: Array = first_lamp[z]
			var lamp_node: Node3D = fl[1]
			tw.tween_callback(func() -> void:
				if is_instance_valid(lamp_node):
					AudioService.play_3d("sfx_lamp_clunk", lamp_node, -3.0, 45.0, randf_range(0.92, 1.06))).set_delay(float(fl[0]))
	if done.is_valid():
		tw.tween_callback(done).set_delay(last + 0.6)


## Ambient light for the power state (ship_dressing.json "ambient"): darker on emergency power.
func ambient_for(restored: bool) -> Array:
	var a: Array = DictUtil.get_arr(ambient, "power" if restored else "emergency")
	return [Color(str(a[0])), float(a[1])] if a.size() == 2 else []


func _process(delta: float) -> void:
	if _flicker.is_empty() or Engine.is_editor_hint():
		return
	_flicker_t += delta
	for i: int in _flicker.size():
		var ol: OmniLight3D = _flicker[i]
		var n := sin(_flicker_t * 23.0 + i * 7.0) + sin(_flicker_t * 37.0 + i * 3.0)
		ol.light_energy = 0.0 if n > 1.55 else EMERGENCY_ENERGY

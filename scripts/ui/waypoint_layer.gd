class_name WaypointLayer
extends CanvasLayer
## Where to go, at a glance (quest markers in the style of Honkai: Star Rail):
##   - the current objective: a pulsing diamond with name and distance; at the
##     screen edge with an arrow when it is behind you or off-screen, plus a soft
##     light beam on the spot in the 3D world
##   - other useful places nearby: a small dot and name that fades in as you get
##     closer and hides when the interaction prompt takes over
## Presentation only: scenes tell it which nodes matter; it never touches state.

const EDGE := 84.0           # px kept free at the screen edge
const PLACE_RANGE := 28.0    # m: places further away stay hidden
const PROMPT_RANGE := 2.6    # m: inside this the interaction prompt speaks instead

var objective: Node3D
var objective_label := ""
var objective_height := 2.2
var places: Array = []       # [{node: Node3D, label: String, height: float}]

var _canvas: Control
var _beam: MeshInstance3D
var _t := 0.0


func _ready() -> void:
	layer = 5  # under the HUD panels (10) and dialogs
	_canvas = Control.new()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_markers)
	add_child(_canvas)
	_beam = MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.2
	cyl.bottom_radius = 0.45
	cyl.height = 9.0
	_beam.mesh = cyl
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = Color(UiKit.AMBER, 0.22)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_beam.material_override = m
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beam.top_level = true
	_beam.visible = false
	add_child(_beam)


## Sets the objective marker. `node` null hides it.
func set_objective(node: Node3D, label: String, height: float = 2.2) -> void:
	objective = node
	objective_label = label
	objective_height = height


func add_place(node: Node3D, label: String, height: float = 2.0) -> void:
	places.append({"node": node, "label": label, "height": height})


func _process(delta: float) -> void:
	_t += delta
	var ok := objective != null and is_instance_valid(objective) and objective.is_inside_tree()
	_beam.visible = ok
	if ok:
		var pulse := 0.0 if bool(SettingsService.get_value("reduced_motion", false)) else sin(_t * 2.2) * 0.06
		_beam.global_position = objective.global_position + Vector3(0, 4.5, 0)
		(_beam.material_override as StandardMaterial3D).albedo_color.a = 0.1 + pulse * 0.5
	_canvas.queue_redraw()


func _draw_markers() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var rect := _canvas.get_rect()
	var font := ThemeDB.fallback_font
	var player_pos := cam.global_position
	var me: Node3D = get_tree().get_first_node_in_group("player") as Node3D
	if me:
		player_pos = me.global_position
	for p: Dictionary in places:
		var n: Node3D = p["node"]
		if not is_instance_valid(n) or not n.is_inside_tree() or n == objective or not n.visible:
			continue
		var d := player_pos.distance_to(n.global_position)
		if d > PLACE_RANGE or d < PROMPT_RANGE:
			continue
		var wp := n.global_position + Vector3(0, float(p["height"]), 0)
		if cam.is_position_behind(wp):
			continue
		var sp := cam.unproject_position(wp)
		if not rect.has_point(sp):
			continue
		var a := clampf(1.0 - (d - 8.0) / (PLACE_RANGE - 8.0), 0.0, 1.0) * 0.85
		_canvas.draw_circle(sp, 6.0, Color(UiKit.PETROL.lightened(0.35), a))
		_canvas.draw_arc(sp, 9.0, 0, TAU, 20, Color(1, 1, 1, a * 0.5), 1.5)
		_text(font, sp + Vector2(0, -16), str(p["label"]), 16, Color(UiKit.TEXT, a))
	if objective == null or not is_instance_valid(objective) or not objective.is_inside_tree():
		return
	var owp := objective.global_position + Vector3(0, objective_height, 0)
	var dist := player_pos.distance_to(objective.global_position)
	if dist < PROMPT_RANGE:
		return
	var behind := cam.is_position_behind(owp)
	var pos := cam.unproject_position(owp)
	var inner := rect.grow(-EDGE)
	var on_screen := not behind and inner.has_point(pos)
	var pulse := 1.0 if bool(SettingsService.get_value("reduced_motion", false)) else 0.85 + sin(_t * 3.0) * 0.15
	var col := Color(UiKit.AMBER, pulse)
	var dist_txt := "%d m" % roundi(dist)
	if on_screen:
		_diamond(pos, 15.0 * pulse + 2.0, col)
		_text(font, pos + Vector2(0, -28), objective_label, 19, Color(UiKit.TEXT, 0.95), true)
		_text(font, pos + Vector2(0, 40), dist_txt, 16, Color(UiKit.AMBER, 0.95), true)
		return
	# Off-screen or behind: pin to the edge in the direction of the target.
	var center := rect.size * 0.5
	var dir := pos - center
	if behind:
		dir = -dir  # unproject mirrors points behind the camera
	if dir.length() < 1.0:
		dir = Vector2(0, 1)
	dir = dir.normalized()
	var half := inner.size * 0.5
	var scale := minf(half.x / maxf(absf(dir.x), 0.001), half.y / maxf(absf(dir.y), 0.001))
	var edge := center + dir * scale
	_canvas.draw_circle(edge, 30.0, Color(0.03, 0.06, 0.08, 0.6))
	_canvas.draw_arc(edge, 30.0, 0, TAU, 32, Color(UiKit.AMBER, 0.5 * pulse), 2.0)
	_diamond(edge, 15.0, col)
	var tip := edge + dir * 46.0
	var side := Vector2(-dir.y, dir.x) * 13.0
	_canvas.draw_colored_polygon(PackedVector2Array([tip, edge + dir * 31.0 + side, edge + dir * 31.0 - side]), col)
	var label_off := Vector2(0, -44) if edge.y > center.y else Vector2(0, 58)
	_text(font, edge + label_off, "%s · %s" % [objective_label, dist_txt], 17, Color(UiKit.TEXT, 0.95), true)


func _diamond(c: Vector2, r: float, col: Color) -> void:
	var pts := PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)])
	_canvas.draw_colored_polygon(pts, Color(0.04, 0.07, 0.09, 0.55 * col.a))
	pts.append(pts[0])
	_canvas.draw_polyline(pts, col, 2.5, true)
	_canvas.draw_circle(c, r * 0.32, col)


## Centred text, kept fully on screen; `plate` adds a dark backdrop for legibility.
func _text(font: Font, at: Vector2, s: String, size: int, col: Color, plate: bool = false) -> void:
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var r := _canvas.get_rect()
	var p := Vector2(clampf(at.x - w * 0.5, 12.0, r.size.x - w - 12.0), at.y)
	if plate:
		var box := Rect2(p + Vector2(-10, -size - 2), Vector2(w + 20, size + 12))
		_canvas.draw_rect(box, Color(0.03, 0.06, 0.08, 0.62 * col.a))
	_canvas.draw_string_outline(font, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 4, Color(0, 0, 0, col.a * 0.8))
	_canvas.draw_string(font, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


## Upper-cases the first letter of an interactable title ("stjernekortet" -> "Stjernekortet").
static func nice(title: String) -> String:
	return title.substr(0, 1).to_upper() + title.substr(1) if not title.is_empty() else title

class_name StarMapView
extends Control
## 2D star map: candidate worlds, routes from the ark's position with their
## fuel cost, the ark marker and the selection. Click a world to select it.

signal planet_selected(location_id: String)

var selected := ""
var _hover := ""


func _ready() -> void:
	custom_minimum_size = Vector2(520, 460)
	mouse_filter = Control.MOUSE_FILTER_STOP


func _pos(loc: String) -> Vector2:
	var sp: Array = DictUtil.get_arr(GameSession.content.locations.get(loc, {}), "star_position")
	var c := size * 0.5
	if sp.size() < 2:
		return c
	return c + Vector2(float(sp[0]), float(sp[1])) * minf(size.x, size.y) * 0.42


func _draw() -> void:
	var content := GameSession.content
	var gs: GameState = GameSession.state
	draw_rect(Rect2(Vector2.ZERO, size), Color("070d12"))
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for i: int in 140:
		draw_circle(Vector2(rng.randf() * size.x, rng.randf() * size.y), rng.randf_range(0.5, 1.4), Color(1, 1, 1, rng.randf_range(0.15, 0.6)))
	var here := gs.campaign.location_id
	var font := get_theme_default_font()
	for loc: String in content.locations.keys():
		if loc == here:
			continue
		var r: Dictionary = content.route_between(here, loc)
		if r.is_empty():
			continue
		var q := GameSession.sim.travel.quote(gs, loc)
		var col := UiKit.PETROL if q["ok"] and not q["risky"] else (UiKit.WARN if q["ok"] else UiKit.DANGER.darkened(0.3))
		var a := _pos(here)
		var b := _pos(loc)
		draw_dashed_line(a, b, Color(col, 0.7 if loc == selected else 0.35), 2.0 if loc == selected else 1.0, 6.0)
		var mid := (a + b) * 0.5
		# Route risk is also a symbol, not only a colour: ▲ risky, ✕ not possible.
		var mark := "" if q["ok"] and not q["risky"] else (" " + UiKit.status_icon("warning") if q["ok"] else " " + UiKit.status_icon("locked"))
		draw_string(font, mid + Vector2(4, -4), "%d ⛽%s" % [int(r.get("fuel", 0)), mark], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(col, 0.9))
	for loc: String in content.locations.keys():
		var p := _pos(loc)
		var pid := str(content.locations[loc].get("planet_id", ""))
		var col := Color("8fa3ad")
		if not pid.is_empty():
			col = Color(str(content.planet(pid).get("palette", {}).get("nature", "#8fa3ad")))
		var rad := 13.0 if not pid.is_empty() else 6.0
		if loc == selected:
			draw_arc(p, rad + 7, 0, TAU, 32, UiKit.AMBER, 2.0)
		elif loc == _hover:
			draw_arc(p, rad + 6, 0, TAU, 32, Color(UiKit.TEXT, 0.5), 1.0)
		draw_circle(p, rad, col)
		if loc in gs.campaign.visited and not pid.is_empty():
			draw_arc(p, rad + 2, 0, TAU, 24, UiKit.TEXT, 1.0)
		draw_string(font, p + Vector2(-60, rad + 18), str(content.locations[loc].get("name", loc)), HORIZONTAL_ALIGNMENT_CENTER, 120, 14, UiKit.TEXT)
	var ark := _pos(here)
	draw_colored_polygon(PackedVector2Array([ark + Vector2(0, -12), ark + Vector2(8, 8), ark + Vector2(0, 4), ark + Vector2(-8, 8)]), UiKit.AMBER)
	draw_string(font, ark + Vector2(12, 4), "ARK", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UiKit.AMBER)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var h := _hit((event as InputEventMouseMotion).position)
		if h != _hover:
			_hover = h
			queue_redraw()
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var h := _hit((event as InputEventMouseButton).position)
		if not h.is_empty() and h != GameSession.state.campaign.location_id:
			selected = h
			AudioService.ui("ui_click")
			planet_selected.emit(h)
			queue_redraw()


func _hit(p: Vector2) -> String:
	for loc: String in GameSession.content.locations.keys():
		if str(GameSession.content.locations[loc].get("planet_id", "")).is_empty():
			continue
		if _pos(loc).distance_to(p) < 22:
			return loc
	return ""

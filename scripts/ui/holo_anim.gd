class_name HoloAnim
extends RefCounted
## Motion helpers for the holo-console look (D-055). Every helper is a no-op
## (the end state is set at once) with reduced motion, and only touches
## scale / modulate / pivot, never layout, so containers and the 1280x720 @1.5
## fit checks see the same sizes with or without animation.
##   HoloAnim.boot_in(panel)            - panel unfolds from a bright line, flickers on
##   HoloAnim.stagger(box)              - children fade + rise in one after another
##   HoloAnim.hover_lift(control)       - hover/focus: slight lift + glow (+ ui_hover sound)
##   HoloAnim.power_off(node, rect)     - CRT-style collapse ghost when a panel closes
##   HoloAnim.pulse(item)               - endless soft brightness pulse (live readouts)


static func calm() -> bool:
	return UiKit.calm()


## The panel unfolds vertically from a thin line, slightly narrow, and
## flickers on (alpha steps), like a holo projector catching. ~0.3 s.
static func boot_in(c: Control, seconds: float = 0.3) -> void:
	if not is_instance_valid(c) or not c.is_inside_tree():
		return
	if calm():
		c.scale = Vector2.ONE
		c.modulate.a = 1.0
		return
	c.scale = Vector2(0.96, 0.03)
	c.modulate.a = 0.0
	var tw := c.create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_method(func(k: float) -> void:
		if not is_instance_valid(c):
			return
		c.pivot_offset = c.size * 0.5
		var ky := ease(k, 0.25)  # fast open, soft landing
		c.scale = Vector2(lerpf(0.96, 1.0, ease(k, 0.4)), lerpf(0.03, 1.0, ky))
		# Flicker: a few hard steps while it opens, then steady.
		var f := 1.0
		if k < 0.55:
			f = [0.35, 0.9, 0.2, 1.0, 0.6, 1.0][int(k / 0.55 * 6.0) % 6]
		c.modulate.a = f, 0.0, 1.0, seconds)
	tw.tween_callback(func() -> void:
		if is_instance_valid(c):
			c.scale = Vector2.ONE
			c.modulate.a = 1.0)


## Children of `box` fade in one after another (alpha only, so containers
## keep their layout).
static func stagger(box: Node, step: float = 0.045, start: float = 0.08, seconds: float = 0.22) -> void:
	if box == null or calm():
		return
	var i := 0
	for n: Node in box.get_children():
		var ci := n as CanvasItem
		if ci == null or not ci.visible:
			continue
		ci.modulate.a = 0.0
		var tw := ci.create_tween()
		tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		tw.tween_interval(start + step * i)
		tw.tween_property(ci, "modulate:a", 1.0, seconds).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		i += 1


## Hover or keyboard/pad focus: the control lifts a touch (scale about its
## centre) and brightens; plays ui_hover on mouse enter. Safe to call once per control.
static func hover_lift(c: Control, amount: float = 0.025, glow: float = 0.18, sound: bool = false) -> void:
	if c == null or c.has_meta("holo_lift"):
		return
	c.set_meta("holo_lift", true)
	var set_on := func(on: bool) -> void:
		if not is_instance_valid(c) or not c.is_inside_tree():
			return
		if on and c is BaseButton and (c as BaseButton).disabled:
			on = false
		c.pivot_offset = c.size * 0.5
		var s := Vector2.ONE * (1.0 + amount) if on else Vector2.ONE
		var m := Color(1.0 + glow, 1.0 + glow, 1.0 + glow, c.modulate.a) if on else Color(1, 1, 1, c.modulate.a)
		if calm():
			c.scale = Vector2.ONE  # no motion; the glow alone marks it
			c.modulate = m
			return
		var tw := c.create_tween().set_parallel(true)
		tw.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(c, "scale", s, 0.12)
		tw.tween_property(c, "modulate", m, 0.12)
	c.mouse_entered.connect(func() -> void:
		set_on.call(true)
		if sound:
			AudioService.ui("ui_hover"))
	c.mouse_exited.connect(func() -> void: set_on.call(c.has_focus()))
	c.focus_entered.connect(func() -> void: set_on.call(true))
	c.focus_exited.connect(func() -> void: set_on.call(false))


## Endless soft pulse of `item`'s brightness between 1 and 1+amount (static with reduced motion).
static func pulse(item: CanvasItem, amount: float = 0.25, period: float = 1.6) -> void:
	if item == null or calm() or not item.is_inside_tree():
		return
	var tw := item.create_tween().set_loops()
	tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	var hi := Color(1.0 + amount, 1.0 + amount, 1.0 + amount, 1.0)
	tw.tween_property(item, "self_modulate", hi, period * 0.5)
	tw.tween_property(item, "self_modulate", Color.WHITE, period * 0.5)


## A closing panel powers off like an old screen: its outline collapses to a
## bright horizontal line, then to a dot, and fades (~0.28 s). Drawn on its own
## short-lived CanvasLayer (`rect` in canvas coordinates, `layer_index` above
## the panel's), so the panel itself can hide at once and every `visible`
## check keeps its meaning.
static func power_off(any_node: Node, rect: Rect2, layer_index: int = 26, tint: Color = Color("7fe8e0")) -> void:
	if any_node == null or calm() or rect.size.x < 4.0 or not any_node.is_inside_tree():
		return
	var cl := CanvasLayer.new()
	cl.layer = layer_index
	var g := _PowerOff.new()
	g.rect = rect
	g.tint = tint
	cl.add_child(g)
	g.tree_exited.connect(cl.queue_free)
	any_node.get_tree().root.add_child(cl)


class _PowerOff extends Control:
	var rect := Rect2()
	var tint := Color.WHITE
	var _k := 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		process_mode = Node.PROCESS_MODE_ALWAYS

	func _process(delta: float) -> void:
		_k += delta / 0.28
		if _k >= 1.0:
			queue_free()
			return
		queue_redraw()

	func _draw() -> void:
		var c := rect.get_center()
		var h := rect.size.y * maxf(0.0, 1.0 - _k / 0.45)
		var w := rect.size.x * (1.0 if _k < 0.45 else maxf(0.0, 1.0 - (_k - 0.45) / 0.55))
		h = maxf(h, 2.0)
		var r := Rect2(c - Vector2(w, h) * 0.5, Vector2(w, h))
		var a := 1.0 - _k * 0.6
		draw_rect(r, Color(tint, 0.12 * a), true)
		draw_rect(r, Color(tint.lightened(0.4), 0.9 * a), false, 2.0)
		if _k > 0.4:
			draw_circle(c, 6.0 * (1.0 - _k) + 2.0, Color(1, 1, 1, a))

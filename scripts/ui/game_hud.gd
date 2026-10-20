class_name GameHud
extends CanvasLayer
## Shared HUD for all gameplay scenes: current objective, interaction prompt,
## hold progress, notices (never only colour), story subtitles, journal (Tab)
## and pause (Esc). Scene-specific widgets go into `top_right` / `bottom`.

var root: Control
var objective_title: Label
var objective_hint: Label
var prompt: Label
var hold_bar: ProgressBar
var toasts: VBoxContainer
var top_right: VBoxContainer
var bottom: HBoxContainer
var story: StoryPlayer
var journal: JournalPanel
var pause_menu: PauseMenu
var nav: NavComms  # NAV, the navigation computer's channel (top centre; silent in the colony)
var _prompt_panel: PanelContainer
var _objective: PanelContainer
var _alarm: PanelContainer  # visual twin of every alarm sound (bible p.26)
var _alarm_label: Label
var _alarm_tween: Tween
var _top_inset := 0.0
var _bottom_inset := 0.0


func _ready() -> void:
	layer = 10
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UiKit.theme()
	add_child(root)
	# Objective (top-left)
	var op := UiKit.panel()
	_objective = op
	op.position = Vector2(24, 20)
	op.custom_minimum_size = Vector2(420, 0)
	op.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ov := UiKit.vbox(2)
	ov.add_child(UiKit.title(Loc.t("Objectives")))
	objective_title = UiKit.label("", 21, UiKit.TEXT, true)
	objective_hint = UiKit.label("", 15, UiKit.MUTED, true)
	ov.add_child(objective_title)
	ov.add_child(objective_hint)
	op.add_child(ov)
	root.add_child(op)
	# Top-right widgets
	top_right = UiKit.vbox(8)
	top_right.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	top_right.position = Vector2(-24, 20)
	top_right.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	top_right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(top_right)
	# Prompt (center-bottom)
	_prompt_panel = UiKit.panel()
	_prompt_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_prompt_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_prompt_panel.position.y -= 210
	_prompt_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pv := UiKit.vbox(4)
	prompt = UiKit.label("", 20, UiKit.TEXT)
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pv.add_child(prompt)
	hold_bar = UiKit.bar(0, 1, UiKit.AMBER, 10)
	hold_bar.visible = false
	pv.add_child(hold_bar)
	_prompt_panel.add_child(pv)
	_prompt_panel.visible = false
	root.add_child(_prompt_panel)
	# Bottom bar for scene widgets
	bottom = UiKit.hbox(10)
	bottom.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	bottom.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bottom.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bottom.position.y -= 20
	root.add_child(bottom)
	# Toasts (left, under objective)
	nav = NavComms.new()
	nav.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	nav.grow_horizontal = Control.GROW_DIRECTION_BOTH
	nav.position.y = 18
	root.add_child(nav)
	toasts = UiKit.vbox(6)
	toasts.position = Vector2(24, 170)
	toasts.custom_minimum_size = Vector2(420, 0)
	toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(toasts)
	_alarm = UiKit.panel()
	_alarm.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_alarm.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_alarm.position.y = 150
	_alarm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_alarm_label = UiKit.label("", 22, UiKit.TEXT)
	_alarm.add_child(_alarm_label)
	_alarm.visible = false
	root.add_child(_alarm)
	AudioService.alarm_raised.connect(show_alarm)
	story = StoryPlayer.new()
	add_child(story)
	journal = JournalPanel.new()
	add_child(journal)
	pause_menu = PauseMenu.new()
	add_child(pause_menu)
	GameSession.objectives_completed.connect(_on_objectives)
	GameSession.state_changed.connect(func(_k: String) -> void: refresh_objective())
	GameSession.command_failed.connect(func(r: CommandResult) -> void:
		AudioService.ui("ui_error")
		toast(r.reason, "warning"))
	GameSession.notice.connect(toast)
	GameSession.story_requested.connect(story.play_scene)
	refresh_objective()


func refresh_objective() -> void:
	if not GameSession.has_game():
		return
	var o := GameSession.sim.objectives.current(GameSession.state)
	objective_title.text = str(o.get("title", Loc.t("The colony is self-sufficient.")))
	objective_hint.text = str(o.get("hint", ""))


func _on_objectives(ids: Array) -> void:
	for id: Variant in ids:
		toast(Loc.t("Objective complete: %s") % GameSession.content.objectives.get(str(id), {}).get("title", id), "ok")
	refresh_objective()


func set_prompt(text: String) -> void:
	prompt.text = text
	_prompt_panel.visible = not text.is_empty()


func set_hold(fraction: float) -> void:
	hold_bar.visible = fraction > 0.0
	hold_bar.value = fraction


## Notice with icon + colour + text (colour is never the only signal).
func toast(text: String, kind: String = "info", seconds: float = 5.0) -> void:
	if text.is_empty():
		return
	var p := UiKit.panel()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var h := UiKit.hbox(8)
	var icon := UiKit.label(UiKit.status_icon(kind), 18, UiKit.status_color(kind))
	h.add_child(icon)
	var l := UiKit.label(text, 16, UiKit.TEXT, true)
	l.custom_minimum_size = Vector2(360, 0)
	h.add_child(l)
	p.add_child(h)
	toasts.add_child(p)
	while toasts.get_child_count() > 4:
		var old := toasts.get_child(0)
		toasts.remove_child(old)
		old.queue_free()
	var t := p.create_tween()
	t.tween_interval(seconds)
	t.tween_property(p, "modulate:a", 0.0, 0.6)
	t.tween_callback(p.queue_free)


## Visual signal for an alarm sound: symbol + text + coloured frame. Blinks
## three times, or stays steady with reduced motion; hides after a few seconds.
func show_alarm(critical: bool) -> void:
	var kind := "critical" if critical else "warning"
	_alarm_label.text = UiKit.status_text(kind, Loc.t("ALARM: critical") if critical else Loc.t("ALARM: warning"))
	var sb := (UiKit.theme().get_stylebox("panel", "PanelContainer") as StyleBoxFlat).duplicate() as StyleBoxFlat
	sb.border_color = UiKit.status_color(kind)
	sb.set_border_width_all(3)
	_alarm.add_theme_stylebox_override("panel", sb)
	_alarm_label.add_theme_color_override("font_color", UiKit.status_color(kind))
	_alarm.visible = true
	_alarm.modulate.a = 1.0
	if _alarm_tween:
		_alarm_tween.kill()
	_alarm_tween = _alarm.create_tween()
	if not bool(SettingsService.get_value("reduced_motion", false)):
		for i: int in 3:
			_alarm_tween.tween_property(_alarm, "modulate:a", 0.35, 0.25)
			_alarm_tween.tween_property(_alarm, "modulate:a", 1.0, 0.25)
	_alarm_tween.tween_interval(3.5)
	_alarm_tween.tween_callback(func() -> void: _alarm.visible = false)


func alarm_visible() -> bool:
	return _alarm.visible


## Scenes with a full-width top bar or a tall bottom bar move the side columns
## and the subtitle/prompt boxes out of the way, so nothing overlaps at large UI
## scales (bible p.26: critical text is never clipped).
func set_insets(top: float, bottom: float) -> void:
	var dt := top - _top_inset
	var db := bottom - _bottom_inset
	if is_zero_approx(dt) and is_zero_approx(db):
		return
	_top_inset = top
	_bottom_inset = bottom
	_objective.position.y += dt
	toasts.position.y += dt
	top_right.position.y += dt
	_alarm.position.y += dt
	_prompt_panel.position.y -= db
	story.shift_up(db)


func objective_rect() -> Rect2:
	return _objective.get_global_rect()


func any_modal_open() -> bool:
	return pause_menu.visible or journal.visible or story.blocking


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("journal") and not pause_menu.visible:
		journal.toggle()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("pause"):
		if journal.visible:
			journal.toggle()
		elif not pause_menu.visible:
			pause_menu.open()
		get_viewport().set_input_as_handled()

extends Node3D
## Main menu over a slow 3D shot of the ark against a candidate world.

var _ark: Node3D
var _cam: Camera3D
var _settings: SettingsPanel
var _credits: CreditsPanel
var _body: VBoxContainer
var _t := 0.0


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	AudioService.set_ambience("amb_space")
	AudioService.set_music("music_hope")
	add_child(SpaceBackdrop.new())
	_ark = Node3D.new()
	_ark.add_child(VisualSlot.make("space.ark_exterior"))
	_ark.rotation_degrees = Vector3(8, 35, -6)
	_ark.position = Vector3(12, 0, 0)
	add_child(_ark)
	var planet := VisualSlot.make("space.planet_green")
	planet.position = Vector3(120, -80, -300)
	add_child(planet)
	_cam = Camera3D.new()
	_cam.position = Vector3(-8, 5, 52)
	_cam.fov = 50
	add_child(_cam)
	_cam.look_at(Vector3(4, -2, 0))
	var layer := CanvasLayer.new()
	add_child(layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.theme = UiKit.theme()
	layer.add_child(root)
	var col := UiKit.vbox(14)
	col.position = Vector2(110, 200)
	root.add_child(col)
	var t := UiKit.label("GENESIS ARK", 76, UiKit.TEXT)
	col.add_child(t)
	col.add_child(UiKit.label(Loc.t("Du er det sidste menneske, der kan give menneskeheden en fremtid."), 22, UiKit.MUTED))
	var sp := Control.new()
	sp.custom_minimum_size = Vector2(0, 30)
	col.add_child(sp)
	_body = UiKit.vbox(10)
	_body.custom_minimum_size = Vector2(360, 0)
	_body.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	col.add_child(_body)
	var foot := UiKit.label(Loc.t("50.000 embryoner. Seks mulige verdener. Ét valg, du skal leve med."), 16, UiKit.AMBER)
	foot.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	foot.position = Vector2(110, -70)
	root.add_child(foot)
	var ver := UiKit.label(Loc.t("v%s · Godot %s · greybox-proxies") % [ProjectSettings.get_setting("application/config/version"), Engine.get_version_info().get("string")], 13, UiKit.MUTED)
	ver.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	ver.position = Vector2(-420, -40)
	root.add_child(ver)
	_settings = SettingsPanel.new()
	_settings.closed.connect(_build)
	add_child(_settings)
	_credits = CreditsPanel.new()
	_credits.closed.connect(_build)
	add_child(_credits)
	_build()


func _build() -> void:
	UiKit.clear(_body)
	if SaveService.has_any():
		var cont := UiKit.button(Loc.t("Fortsæt"), _continue)
		_body.add_child(cont)
		cont.grab_focus.call_deferred()
	var nb := UiKit.button(Loc.t("Ny kampagne"), _new)
	_body.add_child(nb)
	if not SaveService.has_any():
		nb.grab_focus.call_deferred()
	if SaveService.has_any():
		_body.add_child(UiKit.button(Loc.t("Indlæs"), _load_list))
	_body.add_child(UiKit.button(Loc.t("Indstillinger"), func() -> void: _settings.open()))
	_body.add_child(UiKit.button(Loc.t("Krediteringer"), func() -> void: _credits.open()))
	if OS.get_name() != "Web":
		_body.add_child(UiKit.button(Loc.t("Afslut"), func() -> void: get_tree().quit()))


func _new() -> void:
	GameSession.new_campaign()
	AppFlow.goto("ship")


func _continue() -> void:
	var slot := SaveService.latest_slot()
	_try_load(slot, false)


func _load_list() -> void:
	UiKit.clear(_body)
	for slot: String in SaveService.SLOTS:
		if SaveService.store.exists(slot):
			_body.add_child(UiKit.button("%s — %s" % [Loc.t(str(SaveService.SLOT_LABELS[slot])), PauseMenu._describe(SaveService.summary(slot))], func() -> void: _try_load(slot, false)))
	_body.add_child(UiKit.button(Loc.t("Tilbage"), _build))


func _try_load(slot: String, backup: bool) -> void:
	var r := GameSession.load_from(slot, backup)
	if r["ok"]:
		AppFlow.continue_game()
		return
	UiKit.clear(_body)
	_body.add_child(UiKit.label(Loc.t("Kunne ikke indlæse: ") + str(r["error"]), 17, UiKit.WARN, true))
	if r["backup_available"] and not backup:
		_body.add_child(UiKit.button(Loc.t("Indlæs seneste gyldige backup"), func() -> void: _try_load(slot, true)))
	_body.add_child(UiKit.button(Loc.t("Tilbage"), _build))


func _process(delta: float) -> void:
	_t += delta
	_ark.rotation.y += delta * 0.03
	_ark.position.y = sin(_t * 0.4) * 0.4
	_ark.position.x = 12.0


## Evidence captures only (DebugCapture --action=credits|settings).
func debug_action(action: String) -> void:
	match action:
		"credits": _credits.open()
		"settings": _settings.open()

@tool
extends VBoxContainer
## Asset-slots dock: every VisualSlot with its state, the Synty suggestion and
## the matcher's choice, and buttons to map an imported model to the slot.
## Mapping = SyntyWrapperBuilder.build_one (same rules as the command line):
## fit by slot kind, atlas via import settings, wrapper in art/prefabs/.
## Dev tool: text is Danish and not localized.

const SUGGESTIONS := "res://data/art/synty_suggestions.json"
const CHOICES := "res://data/art/synty_choices.json"
const CATEGORIES := ["alle", "ship", "char", "building", "surface", "space", "fx", "ui"]

var _tree: Tree
var _filter: LineEdit
var _category: OptionButton
var _only_proxy: CheckBox
var _count: Label
var _detail: RichTextLabel
var _rot: SpinBox
var _alts: HBoxContainer
var _status: Label
var _selected := ""
var _sugg: Dictionary = {}
var _choices: Dictionary = {}
var _mapped: Dictionary = {}
var _builder := SyntyWrapperBuilder.new()


func _ready() -> void:
	custom_minimum_size = Vector2(320, 400)
	var top := HBoxContainer.new()
	_count = Label.new()
	_count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_count)
	top.add_child(_btn("↻", "Genindlæs slots, forslag og valg", refresh))
	add_child(top)
	var row := HBoxContainer.new()
	_filter = LineEdit.new()
	_filter.placeholder_text = "Søg slot…"
	_filter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_filter.text_changed.connect(func(_t: String) -> void: _fill())
	row.add_child(_filter)
	_category = OptionButton.new()
	for c: String in CATEGORIES:
		_category.add_item(c)
	_category.item_selected.connect(func(_i: int) -> void: _fill())
	row.add_child(_category)
	add_child(row)
	_only_proxy = CheckBox.new()
	_only_proxy.text = "Kun slots, der stadig er proxy"
	_only_proxy.toggled.connect(func(_on: bool) -> void: _fill())
	add_child(_only_proxy)
	_tree = Tree.new()
	_tree.columns = 3
	_tree.column_titles_visible = true
	_tree.set_column_title(0, "Slot")
	_tree.set_column_title(1, "")
	_tree.set_column_title(2, "Model / forslag")
	_tree.set_column_expand(1, false)
	_tree.set_column_custom_minimum_width(0, 170)
	_tree.set_column_clip_content(2, true)
	_tree.set_column_custom_minimum_width(1, 24)
	_tree.hide_root = true
	_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tree.custom_minimum_size = Vector2(0, 220)
	_tree.item_selected.connect(_on_select)
	add_child(_tree)
	_detail = RichTextLabel.new()
	_detail.bbcode_enabled = true
	_detail.fit_content = true
	_detail.custom_minimum_size = Vector2(0, 90)
	add_child(_detail)
	_alts = HBoxContainer.new()
	add_child(_alts)
	var rot_row := HBoxContainer.new()
	var rl := Label.new()
	rl.text = "Drej model (°):"
	rot_row.add_child(rl)
	_rot = SpinBox.new()
	_rot.min_value = -180
	_rot.max_value = 180
	_rot.step = 90
	rot_row.add_child(_rot)
	add_child(rot_row)
	var b1 := HBoxContainer.new()
	b1.add_child(_btn("Brug valgt fil", "Map den model, der er markeret i FileSystem-panelet (.fbx/.glb/.gltf/.tscn), til slottet", _use_selected_file))
	b1.add_child(_btn("Brug valg", "Byg slottet fra synty_choices.json", _use_choice))
	add_child(b1)
	var b2 := HBoxContainer.new()
	b2.add_child(_btn("Åbn wrapper", "Åbn wrapper-scenen i editoren", _open_wrapper))
	b2.add_child(_btn("Fjern", "Fjern mappingen; slottet viser proxyen igen", _unmap))
	b2.add_child(_btn("RigLab", "Åbn figur-testscenen", func() -> void: EditorInterface.open_scene_from_path("res://scenes/tests/RigLab.tscn")))
	add_child(b2)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_status)
	refresh()


func _btn(text: String, tip: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.pressed.connect(cb)
	return b


func refresh() -> void:
	AssetSlots.reload()
	_sugg = DictUtil.get_dict(DictUtil.load_json(SUGGESTIONS), "slots")
	var ch: Variant = DictUtil.load_json(CHOICES) if FileAccess.file_exists(CHOICES) else null
	_choices = DictUtil.get_dict(ch, "choices") if ch is Dictionary else {}
	_mapped = SyntyWrapperBuilder.load_mappings()
	_fill()
	if not _selected.is_empty():
		_show(_selected)


func _fill() -> void:
	_tree.clear()
	var root := _tree.create_item()
	var cat: String = CATEGORIES[_category.selected]
	var total := 0
	var done := 0
	var ids: Array = AssetSlots.slots().keys()
	ids.sort()
	for id: String in ids:
		var has := AssetSlots.has_scene(id)
		total += 1
		done += 1 if has else 0
		if cat != "alle" and not id.begins_with(cat + "."):
			continue
		if _only_proxy.button_pressed and has:
			continue
		if not _filter.text.is_empty() and not _filter.text.to_lower() in id:
			continue
		var it := _tree.create_item(root)
		it.set_text(0, id)
		it.set_metadata(0, id)
		it.set_text(1, "●" if has else "○")
		it.set_custom_color(1, Color("5fae6e") if has else Color("8fa3ad"))
		var c: Dictionary = _choices.get(id, {})
		var src := AssetSlots.scene_path(id) if has else str(c.get("source", ""))
		it.set_text(2, src.get_file() if not src.is_empty() else "—")
		if not has and str(c.get("status", "")) == "weak":
			it.set_custom_color(2, Color("e8a33d"))
		if id == _selected:
			it.select(0)
	_count.text = "%d / %d slots har en model" % [done, total]


## Selects a slot programmatically (plugin automation / tests).
func select(id: String) -> void:
	_selected = id
	_fill()
	_show(id)


func _on_select() -> void:
	var it := _tree.get_selected()
	if it:
		_show(str(it.get_metadata(0)))


func _show(id: String) -> void:
	_selected = id
	var s: Dictionary = _sugg.get(id, {})
	var c: Dictionary = _choices.get(id, {})
	var lines: Array = ["[b]%s[/b]  %s" % [id, "[color=#5fae6e]model[/color]" if AssetSlots.has_scene(id) else "[color=#8fa3ad]proxy[/color]"]]
	if AssetSlots.has_scene(id):
		lines.append("Wrapper: " + AssetSlots.scene_path(id))
	if not s.is_empty():
		lines.append("Pakke: " + str(s.get("pack", "")))
		lines.append("Søg: " + ", ".join(Array(s.get("search", [])).map(func(x: Variant) -> String: return str(x))))
		lines.append("[i]%s[/i]" % str(s.get("notes", "")))
	if not c.is_empty():
		lines.append("Valg: %s (%s)" % [str(c.get("source", "—")), str(c.get("status", ""))])
	lines.append("Tilpasning: " + str(c.get("fit", SyntyWrapperBuilder.fit_mode(id))))
	_detail.text = "\n".join(lines)
	_rot.value = float(c.get("rotation_y", 0.0))
	for ch: Node in _alts.get_children():
		ch.queue_free()
	for alt: Variant in Array(c.get("alternatives", [])).slice(0, 3):
		var a := str(alt)
		_alts.add_child(_btn(a.get_file().get_basename(), "Byg slottet med " + a, func() -> void: _build(a)))


func _use_selected_file() -> void:
	var paths := EditorInterface.get_selected_paths()
	if _selected.is_empty() or paths.is_empty():
		_status.text = "Vælg et slot i listen og en model i FileSystem-panelet."
		return
	_build(paths[0])


func _use_choice() -> void:
	var c: Dictionary = _choices.get(_selected, {})
	if str(c.get("source", "")).is_empty():
		_status.text = "Intet valg for %s i synty_choices.json (kør tools/synty/match.py)." % _selected
		return
	_build(str(c["source"]), true)


## Builds the selected slot from `source` (with the choice's variants when asked).
func _build(source: String, with_variants: bool = false) -> void:
	if _selected.is_empty():
		return
	var c: Dictionary = (_choices.get(_selected, {}) as Dictionary).duplicate()
	c["source"] = source
	c["rotation_y"] = _rot.value
	if not with_variants:
		c.erase("variants")
	var r := _builder.build_slot(_selected, c, SyntyWrapperBuilder.PREFABS)
	if r.get("reimport", false):
		# The atlas material was attached in the import settings: re-import, then build on the new import.
		var files := PackedStringArray()
		for src: Variant in [source] + Array(c.get("variants", [])):
			files.append(str(src) if str(src).begins_with("res://") else "res://assets/imported/" + str(src))
		EditorInterface.get_resource_filesystem().reimport_files(files)
		r = _builder.build_slot(_selected, c, SyntyWrapperBuilder.PREFABS)
	if not r["ok"]:
		_status.text = "✕ " + str(r.get("error", ""))
		return
	_mapped[_selected] = r["scenes"] if r.has("scenes") else r["scene"]
	SyntyWrapperBuilder.save_mappings(_mapped)
	EditorInterface.get_resource_filesystem().scan()
	_status.text = "✓ " + str(r.get("summary", ""))
	refresh()


func _open_wrapper() -> void:
	if AssetSlots.has_scene(_selected):
		EditorInterface.open_scene_from_path(AssetSlots.scene_path(_selected))


func _unmap() -> void:
	if _mapped.erase(_selected):
		SyntyWrapperBuilder.save_mappings(_mapped)
		_status.text = "%s viser proxyen igen (wrapper-filen er beholdt)." % _selected
		refresh()
	elif AssetSlots.has_scene(_selected):
		_status.text = "%s er mappet i asset_slots.json; ret \"scene\" dér." % _selected

extends Node
## Save slots on top of SaveStore. Saves happen only at consistent simulation
## points: GameSession pauses command intake while it snapshots (bible p.22).

const SLOTS := ["auto", "manual_1", "manual_2", "manual_3", "pre_landing"]
const SLOT_LABELS := {"auto": "Autosave", "manual_1": "Slot 1", "manual_2": "Slot 2", "manual_3": "Slot 3", "pre_landing": "Before landing"}

var store := SaveStore.new("user://saves")
var _counter := 0


func _ready() -> void:
	# Evidence captures and perf runs build fixture campaigns whose commands
	# autosave: they keep to their own folder instead of overwriting the
	# player's real slots.
	if DebugCapture.requested() or PerfProbe.requested() or "--playtest" in " ".join(OS.get_cmdline_user_args()):
		store = SaveStore.new("user://saves_debug")


func save_state(slot: String, gs: GameState, content: ContentDB) -> Dictionary:
	_counter += 1
	var env := SaveCodec.encode(gs, content.content_version, "%s-%d-%d" % [slot, Time.get_unix_time_from_system(), _counter])
	return store.write(slot, env, content)


func load_state(slot: String, content: ContentDB, prefer_backup: bool = false) -> Dictionary:
	return store.read(slot, content, prefer_backup)


func has_any() -> bool:
	for s: String in SLOTS:
		if store.exists(s):
			return true
	return false


func latest_slot() -> String:
	var best := ""
	var best_t := ""
	for s: String in SLOTS:
		var sm := store.summary(s)
		if sm.is_empty():
			continue
		if str(sm.get("saved_at", "")) > best_t:
			best_t = str(sm.get("saved_at", ""))
			best = s
	return best


func summary(slot: String) -> Dictionary:
	return store.summary(slot)

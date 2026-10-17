extends Node
## Save slots on top of SaveStore. Saves happen only at consistent simulation
## points: GameSession pauses command intake while it snapshots (bible p.22).

const SLOTS := ["auto", "manual_1", "manual_2", "manual_3", "pre_landing"]
const SLOT_LABELS := {"auto": "Autogem", "manual_1": "Slot 1", "manual_2": "Slot 2", "manual_3": "Slot 3", "pre_landing": "Før landing"}

var store := SaveStore.new("user://saves")
var _counter := 0


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

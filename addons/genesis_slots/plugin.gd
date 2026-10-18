@tool
extends EditorPlugin
## Adds the Asset-slots dock (right side). Editor-only; the game never loads it.

var dock: Control


func _enter_tree() -> void:
	dock = preload("res://addons/genesis_slots/slot_dock.gd").new()
	dock.name = "Asset-slots"
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, dock)
	# Screenshots/automation: GA_SLOTS_DOCK=<slot id> opens the dock with that slot selected.
	var focus := OS.get_environment("GA_SLOTS_DOCK")
	if not focus.is_empty():
		# After the editor has restored its saved layout.
		get_tree().create_timer(3.0).timeout.connect(func() -> void:
			var tabs := dock.get_parent() as TabContainer
			if tabs:
				tabs.current_tab = tabs.get_tab_idx_from_control(dock)
			dock.call("select", focus))


func _exit_tree() -> void:
	if dock:
		remove_control_from_docks(dock)
		dock.queue_free()

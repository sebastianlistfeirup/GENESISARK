class_name ObjectiveService
extends RefCounted
## Objectives complete exactly once; repeated interaction never rewards twice (GA-03).

var content: ContentDB


func _init(db: ContentDB) -> void:
	content = db


func complete(gs: GameState, objective_id: String) -> CommandResult:
	if objective_id in gs.campaign.completed_objectives:
		return CommandResult.fail("already_completed", "Målet er allerede fuldført.")
	gs.campaign.completed_objectives.append(objective_id)
	var def: Dictionary = content.objectives.get(objective_id, {})
	gs.log_journal("Mål fuldført: %s" % def.get("title", objective_id), "objective")
	return CommandResult.success({"objective_id": objective_id})


func is_done(gs: GameState, objective_id: String) -> bool:
	return objective_id in gs.campaign.completed_objectives


## The first not-yet-completed objective for the current phase (drives HUD guidance).
func current(gs: GameState) -> Dictionary:
	var ids: Array = content.objectives.keys()
	ids.sort_custom(func(a: String, b: String) -> bool:
		return int(content.objectives[a].get("order", 0)) < int(content.objectives[b].get("order", 0)))
	var order := ["ARK", "VOYAGE", "SETTLED"]
	var now := order.find(gs.campaign.phase)
	for id: String in ids:
		if id in gs.campaign.completed_objectives:
			continue
		# Objectives of an earlier phase can no longer be completed; skip them.
		if order.find(str(content.objectives[id].get("phase", "ARK"))) < now and now >= 0:
			continue
		return content.objectives[id]
	return {}

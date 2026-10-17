class_name SocietyService
extends RefCounted
## Council, trust and the three young voices (bible p.12, GA-24).
## A council cannot exist before there are adult cohorts.

const COUNCIL_MIN_ADULTS := 10

var content: ContentDB


func _init(db: ContentDB) -> void:
	content = db


func council_blockers(gs: GameState) -> Array:
	var out: Array = []
	if gs.population.adult_workforce() < COUNCIL_MIN_ADULTS:
		out.append("Rådet kræver mindst %d voksne (nu %d)." % [COUNCIL_MIN_ADULTS, gs.population.adult_workforce()])
	if gs.colony == null or gs.colony.count_active("school_hall") == 0:
		out.append("Rådet kræver et færdigt skole- og rådhus.")
	return out


func form_council(gs: GameState, txn: String) -> CommandResult:
	if gs.society.council_formed:
		return CommandResult.fail("already_formed", "Rådet findes allerede.")
	if gs.is_applied(txn):
		return CommandResult.fail("duplicate_txn", "Allerede behandlet.")
	var b := council_blockers(gs)
	if not b.is_empty():
		return CommandResult.fail("council_blocked", " ".join(b), {"blockers": b})
	gs.society.council_formed = true
	gs.society.council_day = gs.campaign.colony_day
	gs.society.autonomy = maxf(gs.society.autonomy, 20.0)
	gs.society.trust = minf(100.0, gs.society.trust + 5.0)
	gs.mark_applied(txn)
	gs.log_journal("Koloniens første råd er samlet.", "society")
	return CommandResult.success({})


## Records one of the generational priority choices (year 20 / 40 chapter decisions).
func choose_priority(gs: GameState, decision_id: String, priority: String) -> CommandResult:
	if not gs.society.priorities.has(priority):
		return CommandResult.fail("unknown_priority", "Ukendt prioritet.")
	for d: Dictionary in gs.society.decisions:
		if d.get("id") == decision_id:
			return CommandResult.fail("already_decided", "Beslutningen er allerede truffet.")
	gs.society.priorities[priority] = int(gs.society.priorities[priority]) + 1
	gs.society.decisions.append({"id": decision_id, "choice": priority, "day": gs.campaign.colony_day})
	match priority:
		"self_determination":
			gs.society.autonomy = minf(100.0, gs.society.autonomy + 20.0)
			gs.society.trust = minf(100.0, gs.society.trust + 8.0)
		"safety":
			gs.society.trust = minf(100.0, gs.society.trust + 4.0)
		"expansion":
			gs.society.autonomy = minf(100.0, gs.society.autonomy + 8.0)
	return CommandResult.success({"priority": priority})


func tick_day(gs: GameState, report: Dictionary) -> Dictionary:
	var s := gs.society
	if bool(report.get("shortage", false)):
		s.trust = maxf(0.0, s.trust - 0.05)
	elif int(gs.colony.stats.get("days_stable", 0)) > 30 and gs.population.alive_count() > 0:
		s.trust = minf(100.0, s.trust + 0.01)
	return {"trust": snappedf(s.trust, 0.01)}

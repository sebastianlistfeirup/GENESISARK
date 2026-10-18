class_name ArkService
extends RefCounted
## Ship systems and the ark's consumables. Owner of ArkState.

var content: ContentDB


func _init(db: ContentDB) -> void:
	content = db


## The emergency power coupling in the workshop. First objective (GA-03).
func restore_power(gs: GameState) -> CommandResult:
	if gs.ark.systems.get("power") != "offline":
		return CommandResult.fail("already_restored", Loc.t("Emergency power is already running."))
	gs.ark.systems["power"] = "emergency"
	gs.ark.systems["starmap"] = true
	if gs.campaign.phase == CampaignState.PHASE_ARK:
		gs.campaign.phase = CampaignState.PHASE_VOYAGE
	gs.log_journal(Loc.t("Emergency power restored. The bridge and the star map are back online."), "ark")
	return CommandResult.success({"power": "emergency"})


func mark_system(gs: GameState, key: String) -> CommandResult:
	if bool(gs.ark.systems.get(key, false)):
		return CommandResult.fail("already_done", Loc.t("Already registered."))
	gs.ark.systems[key] = true
	return CommandResult.success({key: true})


func spend_components(gs: GameState, amount: int) -> CommandResult:
	if amount < 0:
		return CommandResult.fail("invalid_amount", Loc.t("Negative amount."))
	if gs.ark.components < amount:
		return CommandResult.fail("insufficient_components",
			Loc.t("Not enough components (have %d, need %d).") % [gs.ark.components, amount])
	gs.ark.components -= amount
	return CommandResult.success({"components": gs.ark.components})


## Repair hull integrity with components in the workshop: 1 component -> +4 integrity.
## Workbench: repair the oxygen scrubbers with components (bible p.8: what is used here is missing in the colony).
func repair_life_support(gs: GameState, components: int, txn: String) -> CommandResult:
	if gs.is_applied(txn):
		return CommandResult.fail("duplicate_txn", Loc.t("The repair has already been done."))
	if gs.campaign.phase != CampaignState.PHASE_VOYAGE and gs.campaign.phase != CampaignState.PHASE_ARK:
		return CommandResult.fail("wrong_phase", Loc.t("The Ark has landed; life support is now run by the colony."))
	if gs.ark.oxygen >= 100.0:
		return CommandResult.fail("full_oxygen", Loc.t("The oxygen reserve is full."))
	var r := spend_components(gs, components)
	if not r.ok:
		return r
	gs.ark.oxygen = minf(100.0, gs.ark.oxygen + DictUtil.get_float(content.bal("oxygen", {}), "repair_per_component", 4.0) * components)
	gs.mark_applied(txn)
	return CommandResult.success({"oxygen": gs.ark.oxygen})


func repair(gs: GameState, components: int, txn: String) -> CommandResult:
	if gs.is_applied(txn):
		return CommandResult.fail("duplicate_txn", Loc.t("The repair has already been done."))
	if gs.campaign.phase != CampaignState.PHASE_VOYAGE and gs.campaign.phase != CampaignState.PHASE_ARK:
		return CommandResult.fail("wrong_phase", Loc.t("The Ark has landed; repairs now take place in the colony."))
	if gs.ark.integrity >= 100.0:
		return CommandResult.fail("full_integrity", Loc.t("The hull is intact."))
	var r := spend_components(gs, components)
	if not r.ok:
		return r
	gs.ark.integrity = minf(100.0, gs.ark.integrity + 4.0 * components)
	gs.mark_applied(txn)
	return CommandResult.success({"integrity": gs.ark.integrity})

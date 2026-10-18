class_name ArkService
extends RefCounted
## Ship systems and the ark's consumables. Owner of ArkState.

var content: ContentDB


func _init(db: ContentDB) -> void:
	content = db


## The emergency power coupling in the workshop. First objective (GA-03).
func restore_power(gs: GameState) -> CommandResult:
	if gs.ark.systems.get("power") != "offline":
		return CommandResult.fail("already_restored", Loc.t("Nødstrømmen kører allerede."))
	gs.ark.systems["power"] = "emergency"
	gs.ark.systems["starmap"] = true
	if gs.campaign.phase == CampaignState.PHASE_ARK:
		gs.campaign.phase = CampaignState.PHASE_VOYAGE
	gs.log_journal(Loc.t("Nødstrøm genoprettet. Broen og stjernekortet er online igen."), "ark")
	return CommandResult.success({"power": "emergency"})


func mark_system(gs: GameState, key: String) -> CommandResult:
	if bool(gs.ark.systems.get(key, false)):
		return CommandResult.fail("already_done", Loc.t("Allerede registreret."))
	gs.ark.systems[key] = true
	return CommandResult.success({key: true})


func spend_components(gs: GameState, amount: int) -> CommandResult:
	if amount < 0:
		return CommandResult.fail("invalid_amount", Loc.t("Negativ mængde."))
	if gs.ark.components < amount:
		return CommandResult.fail("insufficient_components",
			Loc.t("Ikke nok komponenter (har %d, kræver %d).") % [gs.ark.components, amount])
	gs.ark.components -= amount
	return CommandResult.success({"components": gs.ark.components})


## Repair hull integrity with components in the workshop: 1 component -> +4 integrity.
func repair(gs: GameState, components: int, txn: String) -> CommandResult:
	if gs.is_applied(txn):
		return CommandResult.fail("duplicate_txn", Loc.t("Reparationen er allerede udført."))
	if gs.campaign.phase != CampaignState.PHASE_VOYAGE and gs.campaign.phase != CampaignState.PHASE_ARK:
		return CommandResult.fail("wrong_phase", Loc.t("Arken er landet; reparationer sker nu i kolonien."))
	if gs.ark.integrity >= 100.0:
		return CommandResult.fail("full_integrity", Loc.t("Skroget er intakt."))
	var r := spend_components(gs, components)
	if not r.ok:
		return r
	gs.ark.integrity = minf(100.0, gs.ark.integrity + 4.0 * components)
	gs.mark_applied(txn)
	return CommandResult.success({"integrity": gs.ark.integrity})

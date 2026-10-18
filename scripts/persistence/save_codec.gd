class_name SaveCodec
extends RefCounted
## Save envelope (bible p.22): schema_version, game_id, build_id, content_version,
## save_id, saved_at, seed, rng_state, payload, checksum. The payload is the
## domain only — stable IDs and primitive values, never NodePaths.

const CURRENT_SCHEMA := GameState.SCHEMA_VERSION
const GAME_ID := "genesis_ark"


static func build_id() -> String:
	return "%s+godot%s" % [ProjectSettings.get_setting("application/config/version", "0.0.0"), Engine.get_version_info().get("string", "?")]


static func encode(gs: GameState, content_version: String, save_id: String, saved_at: String = "") -> Dictionary:
	var payload := gs.to_dict()
	return {
		"schema_version": CURRENT_SCHEMA,
		"game_id": GAME_ID,
		"build_id": build_id(),
		"content_version": content_version,
		"save_id": save_id,
		"saved_at": saved_at if not saved_at.is_empty() else Time.get_datetime_string_from_system(true),
		"seed": str(gs.seed_value),
		"rng_state": gs.rng.to_dict(),
		"payload": payload,
		"checksum": checksum(payload),
	}


static func checksum(payload: Variant) -> String:
	return DictUtil.sha256(DictUtil.canonical_json(payload))


## Full validation pipeline. Returns {ok, error, state, migrated_from}.
static func decode(envelope: Variant, content: ContentDB) -> Dictionary:
	var out := {"ok": false, "error": "", "state": null, "migrated_from": 0}
	if not envelope is Dictionary:
		out["error"] = Loc.t("Filen er ikke et gyldigt save (forventede et objekt).")
		return out
	var env: Dictionary = envelope
	if str(env.get("game_id", "")) != GAME_ID:
		out["error"] = Loc.t("Filen tilhører ikke Genesis Ark.")
		return out
	if not env.get("payload") is Dictionary:
		out["error"] = Loc.t("Savet mangler sin payload.")
		return out
	if str(env.get("checksum", "")) != checksum(env["payload"]):
		out["error"] = Loc.t("Checksum passer ikke: filen er beskadiget eller ændret.")
		return out
	var version := int(env.get("schema_version", 0))
	if version > CURRENT_SCHEMA:
		out["error"] = Loc.t("Savet er fra en nyere version (%d > %d).") % [version, CURRENT_SCHEMA]
		return out
	var payload: Dictionary = (env["payload"] as Dictionary).duplicate(true)
	if version < CURRENT_SCHEMA:
		var mig := migrate(payload, version)
		if not mig["ok"]:
			out["error"] = mig["error"]
			return out
		payload = mig["payload"]
		out["migrated_from"] = version
	var gs := GameState.from_dict(payload)
	var errs := gs.validation_errors(content)
	if not errs.is_empty():
		out["error"] = Loc.t("Ugyldig tilstand: ") + "; ".join(errs)
		return out
	out["ok"] = true
	out["state"] = gs
	return out


## Migrates a COPY of the payload step by step: n -> n+1. The original is never touched.
static func migrate(payload_in: Dictionary, from_version: int) -> Dictionary:
	var p := payload_in.duplicate(true)
	var v := from_version
	while v < CURRENT_SCHEMA:
		match v:
			1:
				# v1 kept the embryo ledger flat on the ark ("embryos") and had no society block.
				var ark: Dictionary = DictUtil.get_dict(p, "ark")
				if ark.has("embryos"):
					ark["embryo_ledger"] = ark["embryos"]
					ark.erase("embryos")
				p["ark"] = ark
				if not p.has("society"):
					p["society"] = SocietyState.new().to_dict()
				p["schema_version"] = 2
			_:
				return {"ok": false, "error": Loc.t("Ingen migrering fra schema %d.") % v}
		v += 1
	return {"ok": true, "payload": p}


## Down-converts a current payload to v1 (fixture tooling only).
static func to_v1_fixture(gs: GameState) -> Dictionary:
	var p := gs.to_dict()
	var ark: Dictionary = p["ark"]
	ark["embryos"] = ark["embryo_ledger"]
	ark.erase("embryo_ledger")
	p.erase("society")
	p["schema_version"] = 1
	var env := {
		"schema_version": 1, "game_id": GAME_ID, "build_id": "0.0.1-fixture", "content_version": "0.0.1",
		"save_id": "fixture_v1", "saved_at": "2026-10-17T00:00:00", "seed": str(gs.seed_value),
		"rng_state": gs.rng.to_dict(), "payload": p,
	}
	env["checksum"] = checksum(p)
	return env

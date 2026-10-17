# AGENTS.md — arbejdsregler for kodeagenter på GENESIS ARK

Læs i denne rækkefølge, før du ændrer kode: `docs/BIBLE.md` (s. 3 mandat, s. 14 invarianter, s. 20-22 arbejdsform og save), `docs/STATUS.md`, `docs/DECISIONS.md`, `tasks.json`. Brugerens seneste instruktion går forud for biblen; biblen er baseline; afvigelser dokumenteres i `docs/DECISIONS.md`.

## Arbejdsgang
1. `git status` + seneste commit. Beskyt eksisterende ændringer.
2. `tools/check.sh` (import + domænetests + scenetests) — skal være grøn før og efter din ændring.
3. Tag næste READY-opgave (`python3 tools/validate_plan.py`). Én lille, sammenhængende ændring ad gangen.
4. Gem beviser i `evidence/<task-id>/result.json` (felter: task_id, commit, engine_version, command, exit_code, expected, observed, fixture, status `PASS|FAIL|NOT_RUN`, artifacts). Opfind aldrig kørsler.
5. Opdatér `tasks.json` (status, last_commit, evidence) og `docs/STATUS.md`. Commit.

## Arkitekturregler (bibel s. 14, 21-22)
- `scripts/domain/` må ikke referere noder, autoloads eller scener. Al regel-logik bor her og testes headless.
- UI/3D sender kommandoer via `GameSession.cmd_*` og læser tilstand; de ændrer den aldrig direkte.
- Invarianter: alle ressourcer ≥ 0; viable+incubating+born+lost = 50.000; born er historisk, population er levende; børn arbejder ikke; landing kan kun committes én gang; byggeri kan ikke bruge samme pris to gange; tidsspring stopper ved første uafklarede kritiske hændelse.
- Alle engangsvirkninger har et transaktions-/event-id (`GameState.mark_applied`).
- Save = domæne (stabile id'er, primitive værdier). Afledte caches (`ColonyState.census`, `network_dirty`) gemmes ikke.
- Balance er data (`data/`). Ændr én variabelgruppe ad gangen og kør `tools/balance/run_balance.gd`.
- Grafik er VisualSlots. Vendor-filer er read-only; kollision/interaktion ejes af spillets noder. Rå købte pakker må aldrig committes.
- GDScript med typer, snake_case filer, PascalCase klasser. Ingen addons uden dokumenteret gevinst.

## Kommandoer
```bash
godot --headless --path . --import --quit-after 2000           # opdatér klasse-cache efter nye class_name
godot --headless --path . --script res://tests/run_tests.gd     # domænetests (evidence/test_report.json)
godot --headless --path . res://scenes/tests/scene_smoke.tscn   # scenetests (evidence/scene_smoke.json)
godot --headless --path . res://scenes/tests/compile_all.tscn   # parse-tjek af alle scripts
godot --headless --path . --script res://tools/balance/run_balance.gd [-- --planet=sere --strategy=balanced]
godot --headless --path . --script res://tools/make_fixtures.gd # regenerér save-fixtures
xvfb-run -a godot --path . --rendering-method gl_compatibility -- --capture=evidence/shots/x.png --scene=colony --setup=grown:umbra --action=overview
godot --headless --path . --export-release "Windows Desktop" builds/windows/GenesisArk.exe
```
`--setup` fixtures (DebugFixtures): `fresh`, `power`, `orbit:<planet>`, `expedition:<planet>`, `landed:<planet>`, `colony:<planet>`, `grown:<planet>`, `era:<planet>:<år>`.

## Når noget stopper
Højst tre dokumenterede løsningshypoteser på samme fejl. Gem logs, lav mindste reproduktion, tag en anden READY-opgave. `BLOCKED_ENVIRONMENT` er ikke godkendt.

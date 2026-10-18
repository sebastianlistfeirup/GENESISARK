# STATUS

| Felt | Værdi |
|---|---|
| project | GENESIS ARK |
| spec_version | Udviklingsbibel v1.0 (16.10.2026) |
| engine_version | Godot 4.5.1-stable (official, f62fdbde1) |
| profile | HOLIDAY (cloud-container, headless + Xvfb; ingen Synty-filer, ingen Windows-maskine) |
| current_phase | 1 · Fundament (port ikke bestået endnu) |
| last_passed_gate | — (fase 1-porten kræver GA-11 og GA-12 DONE) |
| active_task | GA-11 / GA-12 (VERIFYING) · grundlag lagt for GA-14, 19, 29, 33 |
| last_commit | se `git log -1` (session 2: lokalisering, controller, lyd, krediteringer, RigLab) |
| next_command | `tools/check.sh` og derefter `godot --path .` |

## Tests kørt (faktiske resultater på dette commit)

| Lag | Kommando | Resultat |
|---|---|---|
| 1 · Domæne | `godot --headless --path . --script res://tests/run_tests.gd` | **54 tests, 0 fejl** → `evidence/test_report.json` |
| 2 · Scener (rigtigt input) | `godot --headless --path . res://scenes/tests/scene_smoke.tscn` | **41 checks, 0 fejl** + touch-føling 6/6 → `evidence/scene_smoke.json` |
| Parse-tjek | `godot --headless --path . res://scenes/tests/compile_all.tscn` | 87 scripts, 0 fejl |
| Balance | `godot --headless --path . --script res://tools/balance/run_balance.gd` | 18 kørsler til år 40 → `evidence/balance/` |
| 3 · Optaget gameplay | — | NOT_RUN (kræver menneske) |
| 4 · Eksport | Windows + Linux eksporteret; Linux-build kørt under Xvfb | Windows-build NOT_RUN |
| Oversættelse | `python3 tools/loc_extract.py --check` | 1069 nøgler, 0 mangler (da → en) |
| Plan | `python3 tools/validate_plan.py` | OK · 10 DONE · 2 VERIFYING · 12 IN_PROGRESS · 12 TODO |

## Opgaver

- **DONE (med beviser i `evidence/GA-xx/result.json`)**: GA-01, GA-02, GA-03, GA-04, GA-05, GA-06, GA-07, GA-08, GA-09, GA-10.
- **VERIFYING**: GA-11 (automatiseret kæde grøn; mangler optaget menneskelig gennemspilning), GA-12 (eksport OK; mangler Windows-kørsel + visuel kontrol + fase 1-tag).
- **IN_PROGRESS — bygget før porten** (data + domæne + UI + tests, ikke kvalitetsgodkendt): GA-15, 16, 17, 18, 21, 22, 23, 24, 25, 28, 29, 33. Se `notes` i `tasks.json`.
- **Grundlag med beviser** (`evidence/GA-xx/groundwork.json`, sætter aldrig DONE): GA-14 (RigLab), GA-19 (alle lyd-cues hooket), GA-29 (controller, settings), GA-33 (lokalisering, krediteringer).
- **TODO**: GA-13/14 (kræver Synty-filer og rig), GA-19 (spiltestere), GA-20, GA-26/27 (art/lyd-pass), GA-30-36 (fase 3-4 porte, beta, release).

## Nyt i session 2 (18.10.2026)

| Område | Hvad | Hvor |
|---|---|---|
| Lokalisering | Dansk/engelsk, sprogvalg i Indstillinger, live genindlæsning. 1069 nøgler, alle oversat. `check.sh` fejler ved manglende nøgle eller afvigende `%d`/`{settlement}`. Saves er sproguafhængige (test). | `scripts/core/loc.gd`, `localization/translations.csv`, `tools/loc_extract.py`, D-017 |
| Controller | Xbox-layout ved siden af tastatur, højre stik = kamera, D-pad/A/B i menuer, byggemarkør i skærmcentrum, hints viser controllerknapper. | `SettingsService.PAD`, D-018 |
| Lyd | Alle 22 planlagte cues hooket (52/53 i alt) med 28 nye proxy-lyde: embryobank-lag, døre, fareområder, jordtrin med varianter, borelyd, relæ, drone, ring, landing, positionel byggeplads, nedrivning, strømudfald, inkubation, krisestinger, epilogmusik pr. slutning. | `AudioService`, `docs/AUDIO_LEDGER.csv` |
| Krediteringer | Menuknap; hold, Synty-pakker (planlagt), lyd, film, Godots MIT-licens og tredjepartskomponenter læst fra motoren. | `data/credits/credits.json`, `scripts/ui/credits_panel.gd` |
| RigLab | Testscene til figurer: 1 m-gitter, 1,8 m-stang, terminal i 1,05 m, prøvepunkt, alle animationstilstande, cirkelbevægelse mod fodglid, audit af skala/fødder/clips. | `scenes/tests/RigLab.tscn` |
| Touch-styring | Rolig, flydende joystick som i Honkai: Star Rail: dødzone, blød kurve, filter, helt ud = løb, dæmpet kamera der glider ind bag kaptajnen. Målt af `tests/touch_feel.gd`. | `TouchControls`, D-019 |
| Vejvisning og fart | Aktuelt mål vises som markør med afstand (pil ved skærmkanten) og lyssøjle; nærliggende steder får navn. Gang 4,2 / løb 7,0 m/s. | `scripts/ui/waypoint_layer.gd`, D-020 |
| Robusthed | `check.sh` parse-tjekker først og har timeout på scenetest (en parsefejl kan ikke længere hænge kørslen). | `tools/check.sh` |

## Balance (fase 3-forløber, `evidence/balance/balance_table.txt`)

Alle seks verdener kan føres til år 40 og en *selvstændig* profil med mindst to af tre strategier (15 af 18 kørsler). Ferrum er sværest (vand, 560 indbyggere); tre strategier kollapser (Viridia power_first, Pelagos lean, Nivalis lean). Lagre har loft (1 års forbrug). Ingen planet dominerer alle felter (test). Fødselsplanen (16/år) gør, at gode strategier lander omkring 650 indbyggere ved år 40. Tuningen er foreløbig.

## Kendte problemer / blokeringer

1. **Synty-pakkerne findes ikke i containeren** → al grafik er registrerede proxies (`data/art/asset_slots.json`). Ikke en spilblokering; GA-13 starter ved hjemkomst.
2. **Windows-build ikke kørt** (ingen Windows-maskine). Linux-build fra samme commit kører.
3. **Generationsprognose** regnes dag for dag (~0,7-1 ms/dag): kører i baggrundstråd; godkendelse genbruger prognosen. Et 20-års spring tager få sekunder.
4. **Ingen eksterne testere** i ferien; agentens gennemgang er ikke spillerbevis (bibel s. 15).
5. Ingen P0/P1 kendt i den automatiserede kæde.

## Næste tre opgaver

1. **GA-11**: spil hele demoen (~20 min) på din maskine, optag den, ret de tre største friktioner.
2. **GA-12**: kør `builds/windows/GenesisArk.exe` (eller eksportér selv), bekræft visuelt, tag `phase-1`.
3. **GA-13**: importér ét skibsmodul, kaptajnen og én terrænprøve via `docs/SCENE_ASSEMBLY.md` → sammenlign med greybox.
4. **GA-14** (når kaptajnen er importeret): åbn `scenes/tests/RigLab.tscn` (F6), ret `scale`/`offset` i `asset_slots.json` til auditten er grøn, og omdøb clips i `animation_map.json`.

## Reproduktion

Fixtures: `fixtures/saves/v1_voyage.json` (seed 4242, migreringstest), `fixtures/saves/v2_colony_start.json` (seed 777). Screenshots: `evidence/shots/` (genskab med `DebugCapture`, se AGENTS.md).

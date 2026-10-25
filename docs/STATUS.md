# STATUS

| Felt | Værdi |
|---|---|
| project | GENESIS ARK |
| spec_version | Udviklingsbibel v1.0 (16.10.2026) |
| engine_version | Godot 4.7.2-stable (official, ed1daf0bf) — se D-033, D-050 |
| profile | HOME (Windows 11, RTX 5090, Vulkan Forward+; Synty-pakker lokalt i `assets/Synty/`) |
| current_phase | 1 · Fundament (port ikke bestået endnu) |
| last_passed_gate | — (fase 1-porten kræver GA-11 og GA-12 DONE) |
| active_task | GA-11 (menneskelig gennemspilning) · GA-12 Windows-kørsel bestået · GA-13/14 Synty + figurer integreret (afventer din visuelle godkendelse) |
| last_commit | se `git log -1` (session 9, 24.10.2026: holo-terminaler og menuer, dyreliv, Meshy-heltemotiver, opvågning, ydelse inden for budget) |
| next_command | `tools/check.sh` og derefter `godot --path .` |

## Tests kørt (faktiske resultater på dette commit)

| Lag | Kommando | Resultat |
|---|---|---|
| 1 · Domæne | `godot --headless --path . --script res://tests/run_tests.gd` | **83 tests, 0 fejl** → `evidence/test_report.json` |
| 2 · Scener (rigtigt input) | `godot --headless --path . res://scenes/tests/scene_smoke.tscn` | **65 checks, 0 fejl** + touch-føling 6/6 → `evidence/scene_smoke.json` |
| Parse-tjek | `godot --headless --path . res://scenes/tests/compile_all.tscn` | 131 scripts, 0 fejl |
| Balance | `godot --headless --path . --script res://tools/balance/run_balance.gd` | 18 kørsler til år 40 → `evidence/balance/` |
| Hel kampagne (bot) | `godot --headless --path . --script res://tools/campaign/campaign_bot.gd` | 6 planeter × 4 spillestile → `evidence/campaign_bot.json` (se session 6) |
| Ydelse | `godot --path . -- --perf [--tris] [--profile=web]` | RTX 5090, Forward+ (D-054): **10/10 cases inden for desktopbudgettet**; colony_era20 6,48 → 2,89 mio. primitiver, surface_hazard 3,61 → 1,12 mio., colony_grown indlæsning 2,9 s; p50 7,8–8,5 ms → `evidence/perf_r2/` |
| 3 · Optaget gameplay | — | NOT_RUN (kræver menneske) |
| 4 · Eksport | Windows eksporteret og **kørt på målmaskinen** (menu, Viridia, Umbra) | PASS → `evidence/GA-12/windows_run.json` |
| Oversættelse | `python3 tools/loc_extract.py --check` | 1191 nøgler, 0 mangler (en → da) |
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

## Nyt i session 3 (18.10.2026): Synty-klar

| Område | Hvad | Hvor |
|---|---|---|
| Synty-import | Pak ud (unitypackage/zip/mappe) → match modeller til 81 slots → kopiér kun valgte → wrapper-scener med tilpasning pr. slot-type og pakkens atlas via importindstillinger. Én kommando: `tools/synty/build.sh`. | `tools/synty/`, D-021 |
| Varianter | Sten, træer, planter, is, kasser, borgere får op til 6 modeller; spillet vælger stabilt pr. placering. | `VisualSlot.variant` |
| Editor-panel | Fanen **Asset-slots** i Godot: status for alle slots, forslag, ét-klik-mapping, drej, åbn wrapper, RigLab. | `addons/genesis_slots/`, D-022 |
| Animationer | Automatisk humanoid retarget (Synty- og Mixamo-navne), klip pr. tilstand samlet i et bibliotek, in-place, afspilles af `CharacterAnimator`. | D-023 |
| Bevis | `tools/synty/selftest.sh`: falsk pakke med modeller, cm-model, hjørne-pivot, rig og Mixamo-klip → hele kæden → 10/10 → oprydning. | `evidence/synty_selftest.json` |

## Nyt i session 4: indflyvning og NAV

| Område | Hvad | Hvor |
|---|---|---|
| Indflyvning | Ringene er væk: hver rute har spredte asteroider, vragrester eller et asteroidebælte. Undvig sideværts, undvigemanøvre (Shift), eller lad NAV flyve (F). Nedslag koster skrog, kraftige lækker ilt. Bogføres én gang, også efter load midt i flyvningen. | `scripts/runtime/flight/flight_scene.gd`, D-024 |
| Iltlager | Ny ressource: forbruges i stasis, lækker ved kraftige nedslag, repareres i værkstedet. Kan blokere en rejse. | `ArkState.oxygen`, `ArkService.repair_life_support` |
| NAV | Tør, følelsesløs navigationscomputer: vurderer ruten før valget (nedslag, skrogtab, brændstof, ilt, reserve) og melder kollisionskurs og nedslag. 24 replikker i data, oversat, i stemmemanuskriptet. | `NavAdvisor`, `data/story/nav.json`, `NavComms` |

## Nyt i session 5: engelsk spil, lys, effekter, NAV på planeten

| Område | Hvad | Hvor |
|---|---|---|
| Sprog | Spillet er 100 % engelsk; engelsk er kildesproget i kode og data, dansk er en valgfri oversættelse (1136 nøgler, alle oversat). Gamle indstillinger med dansk nulstilles én gang. | D-025, `localization/translations.csv` |
| Lys | Himmel, sol, tåge (højdetåge: klart overblik, dis ved jorden), eksponering, glød og SSAO pr. biom/planet i data. Kontaktark over alle seks verdener. | `data/art/lighting.json`, `Lighting`, D-026, `evidence/shots/planets/contact_sheet.png` |
| Effekter | Ti partikeleffekter bygget i Godot (sporer, støv, sne, storm, damp, motor, gnister, strømstød, scanning, landingsstøv), lette nok til mobil, rolig udgave ved "reduceret bevægelse". Fremviser: `--scene=fxlab`. | `art/fx/`, D-029 |
| NAV på planeten | Brief ved landing, farezoner ind/ud, delmål, halv dragt, og hjemturs-varsler beregnet ud fra afstand og gåfart. Testet i domænet. | `NavAdvisor.surface_update`, D-027 |
| Kollision | Bygninger kolliderer efter modellens form (bokse pr. mesh-del), ikke en usynlig footprint-boks. Virker automatisk med Synty-modeller; undtagelser pr. slot. | `ShapeCollider`, D-028 |
| Rettelser | Vejvisningsmarkøren går ikke længere ind over undertekster; rutelabels på overfladen ligger ikke oven i hinanden; `check.sh` fejler på enhver SCRIPT ERROR. | — |
| Web | Mobil-build genbygget med alt ovenstående. | Artifact "Genesis Ark Playtest" |

## Nyt i session 6: klar til hjemkomst

| Område | Hvad | Hvor |
|---|---|---|
| Kampagnebot | Spiller hele spillet headless på alle planeter med fire spillestile, tjekker invarianter efter hvert skridt og gem → indlæs ved hver fasegrænse. Alle 9 hændelser og 27 valg nås. Én kampagne kører i `check.sh`. | `tools/campaign/campaign_bot.gd`, D-031 |
| Balance | Regelfejl rettet: tidsspringet bemandede miner, til intet kunne bygges. 18/18 balancekørsler når år 40. | D-030 |
| Ydelse | `PerfProbe` måler hver hovedscene efter biblens metode mod `data/perf/budget.json`. Ny **grafikkvalitet** (Auto/Høj/Lav; Auto = Lav på telefon/web): én skyggekaskade, grovere terræn, færre sten og partikler. Telefonprofil: overflade 784k → 214k primitiver, koloni år 20 886 → 551 draw calls; 7/7 inden for budget. | `scripts/runtime/common/perf_probe.gd`, `Quality` |
| Epilog | Nævner nu valgene ved år 20 og 40 og kolonistens tillid. | `data/endings/legacy.json` |
| Rettelser | To danske ord i engelsk spillertekst; tydeligere vej ud af robotmangel; distrikternes vækst er nu data. | — |
| Første dag hjemme | Ni trin med kommandoer øverst i `START_HERE.md`. | `START_HERE.md` |
| R10 løst | Kolonien byggede sig inde på Sere: værksteder følger nu vedligeholdelsesregningen. 24/24 kampagner, 18/18 balancekørsler. | D-032 |
| Tekst | 63 linjer poleret (NAV-format, ARK's stemme, terminologi); "1 crisis"; børn arbejder ikke i historierne. | `evidence/text_pass/changes.md` |
| Tilgængelighed | Alt kan ombindes, paneler og HUD passer i 1280×720 ved UI-skala 1,5, symboler ved siden af farver, visuel alarm, undertekststørrelse virker overalt; 5 nye scenetests. Åbent: lille tekst ved skala 1,0 i 1280×720 (standardskala er dit valg), ingen ombinding af controller (D-018), ingen advarsel ved dobbelt-bundne taster. | `evidence/a11y/audit.md` |
| R9-forslag | Tre lag til valg med konsekvens, med målepunkter til kampagnebotten. | `docs/proposals/R9_valg_med_konsekvens.md` |
| R9 implementeret | Lag 1 (varig kurs ved år 20/40), lag 2 (tillid < 35 / > 65 med HUD-symbol og forklaring i Fremtid-fanen), lag 3 (ét efterspil pr. hændelse), skærpet *skærmet*. Bot: befolkning år 40 spreder 21-24 % mellem spillestile, to slutprofiler blandt normale spillestile, 0 fejl; balance 18/18. 81 domænetests. | D-034, `evidence/R9/result.json` |

## Nyt i session 9 (24.10.2026): holo-konsoller, levende planeter, opvågningen, ydelse

| Område | Hvad | Hvor |
|---|---|---|
| Skibets terminaler | Stjernekort, sammenligning, kredsløb, landing, embryobank og værksted som levende holo-konsoller (Synty Sci-Fi Menus + Soldier HUD): opstart med flimmer, drejende planeter, flydende ruter, videnskort med usikkerhedsbjælker, tællere | D-055 |
| Alle andre menuer | Indstillinger (faner, live-forhåndsvisning), gem/indlæs som kort, journal, kolonioversigt som dashboard, bygningskort, hændelser/beslutninger med de tre stemmer, HUD-chips, epilog | D-059 |
| Dyreliv | Flokke og kæmper på alle seks planeter, flygter fra kaptajnen | D-053 |
| Meshy + image-to-3D-skill | Sporetræer (Umbra), malmkrystaller (Ferrum), kronetræer (Viridia), isbuer (Nivalis), havleviathan (Pelagos) – lokale filer | D-057, D-058 |
| Øjeblikke | Opvågning i kryokapslen, strømmen som bølge, dragtscanner [C], skydække, stedskort mellem scener, planeten i broens vindue | D-060–D-062 |
| Ydelse | Alle 10 målescener inden for budget (år-20-kolonien 6,5 → 2,9 mio. trekanter) via automatiske LOD'er, opdelte MultiMeshes og skygge-LOD | D-054 |
| Lyd | ElevenLabs-generatorer for lydeffekter, musik og stemmer (ARK med egen AI-farvet bus); filerne er lokale | tools/audio/ |
| Værktøjskæde | DeepSeek-review af nedstigning og opvågning (rettet), lokal Qwen-kritik af stjernekortet (gennemført), Meshy tekst-til-billede → billede-til-3D | evidence/advisers/ |

## Nyt i session 8 (24.10.2026): landing i realtid, planeterne som nøglebillederne, ny brugerflade, Godot 4.7.2

| Område | Hvad | Hvor |
|---|---|---|
| Landing som No Man's Sky | Fra lavt kredsløb (planetstor klode, tågehimmel, Arken bag dig) gennem brændende indtræden og skydækket til platformen på stedet – ét sammenhængende skud, autopilot eller manuel styring, landingsassistent, kan springes over. Arken lander på kolonistedet på samme måde; ekspeditionen slutter med letning og stigning til kredsløb. | D-049 · `planet_descent.gd`, `descent_hud.gd` |
| Planeterne | Fremmed flora fra Sci-Fi Worlds på alle seks (selvlysende skov på Umbra, kæmpeblomster på Viridia, koraller/tang på Pelagos …), kæmpevrag i Seres klitter (gylden time), skrotplanet Ferrum (væltede paraboler), havhorisont på Pelagos, skelet og spir på Nivalis, fugle med rigtige vinger | D-047 |
| Rummet | Facetterede Synty-planeter med glorie, måner og ringe; levende kredsløbsvisning; nyt stjernekort; cockpit; Arken med lysende motorer | D-044, D-046 |
| Kolonien | Gadeliv pr. stil: markeder, skilte, parkerede køretøjer, røg og giftpøler | D-045 |
| Brugerflade | Ét Synty-sci-fi-tema overalt; hovedmenu som udstillingsvindue | D-048 |
| Motor og plugins | Godot 4.7.2; ejerens plugins installeret korrekt (lokalt, ikke i brug) | D-050 |
| Repo | Historikken renset for Synty-nøglebilleder (force-push godkendt af ejeren); GitHub kan stadig vise den gamle commit via SHA, indtil GitHub Support renser cache | — |

## Nyt i session 7 (24.10.2026): Synty overalt og unikke planeter

| Område | Hvad | Hvor |
|---|---|---|
| Motor | Godot 4.7.2; motoruafhængig save-checksum, gamle saves accepteres | D-033 |
| Synty-integration | Godot-pakker (Sci-Fi Worlds, Sci-Fi City) og kilde-FBX (Sci-Fi Space, Nature Biomes ×4, figurer, animationer) bruges direkte; 55 slots mappet; ingen købte filer i git | `tools/synty/`, `data/art/synty_choices.json`, D-021/D-033 |
| Skib | Modulært Sci-Fi Space-interiør, broens konsolrækker, hologrammer, ARK som holografisk kerne, kryokapsler med sovende kolonister, rigtige vinduer med tågehimmel og planeten man kredser om, nødstrøm i rav → cyan | `ship_dresser.gd`, `data/art/ship_dressing.json`, `hologram.gd` |
| Planeter | Seks unikke verdener: jungle, vandverden, rustmesaer, klitter, isskov, bioluminescent nat; måner, ringplaneter, nordlys | D-039, `data/art/ground_cover.json`, `nature_kit.gd` |
| Lys | Synty-demoernes opskrift (lineær tonemap, dybde-tåge, SSAO), malet tågehimmel, planetshader | D-036 |
| Kolonien | Pods forbundet med korridorer, påklædning, platforme, veje, lamper, droner, køretøjer, gående kolonister (10 kroppe) | D-037 |
| Indflyvning + overflade | Synty-asteroider, stationer, skibe, gaskæmpe; landingslejr og stedspecifik påklædning | D-038 |
| Animation | Målte gangarter (fodglid 36–46 % → 0), stop, drej, læn, konsoltryk, knælende prøvetagning, idle-variationer | D-040 |
| UI | Filmisk hovedmenu, fælles tema med Synty INTERFACE-skin, Exo 2-font, epilog over den koloniserede verden, planeter på stjernekort og i kredsløbspanel | D-035 |
| Gameplay | R9: valg ændrer udfaldet (varige prioriteter, tillidstærskler, skærmet slutning, efterspil) | D-034 |

## Balance (fase 3-forløber, `evidence/balance/balance_table.txt`)

Alle 18 kørsler (6 verdener × 3 strategier) når år 40 med *selvstændig* profil (før 15 af 18). De tre kollaps skyldtes en regelfejl i tidsspringets institutioner: miner og værksted bemandede alle arkens droner, så intet kunne bygges, og maden løb tør (D-030). Gode strategier lander på 650 indbyggere ved år 40 (330 ved år 20); Ferrum er sværest (560, vand). Slutbefolkningen er ens på tværs af strategier, fordi fødselsplanen (16/år) er loftet; strategierne adskiller sig i åbningens længde (36-171 dage) og underskudsdage (Pelagos ~1450 pga. storme). Lagre har loft (1 års forbrug). Ingen planet dominerer alle felter (test). Tuningen er foreløbig.

## Kendte problemer / blokeringer

1. **Visuel godkendelse er din**: alt nyt er vurderet på skærmbilleder af agenten, ikke af dig (bibel s. 25).
2. **Synty-pakkerne ligger kun lokalt** (`assets/Synty/`, gitignored, repoet er offentligt). På en ny maskine: pak zip'erne ud igen (se `tools/synty/build_godot_packs.sh` og `tools/synty/extract_anim_clips.py`); uden dem viser spillet proxies.
3. **Windows-pakken er 1,64 GB** (komprimerede Synty-teksturer); kan trimmes yderligere.
4. **Trekantbudget**: to scener over 3 mio. trekanter (frametid stadig ~9 ms på RTX 5090); mellemklasse-GPU ikke målt.
5. **Ingen eksterne testere** endnu; lyd er stadig proxy-lyde.
6. Stop fra 4,2 m/s-gang og kolonisternes stop kan forbedres (D-040).

## Næste tre opgaver

1. **GA-11**: spil hele kampagnen (~20 min første del) og skriv de tre største irritationsmomenter ned.
2. **Visuel godkendelse** af skib, de seks planeter, kolonien og animation (se `evidence/` og handover-artefaktet).
3. **GA-19/20**: rigtige lyde og stemmer (`docs/AUDIO_LEDGER.csv`, `docs/VO_SCRIPT.csv`) og første eksterne testere.

## Reproduktion

Fixtures: `approach:<planet>` (indflyvning) er ny. `fixtures/saves/v1_voyage.json` (seed 4242, migreringstest), `fixtures/saves/v2_colony_start.json` (seed 777). Screenshots: `evidence/shots/` (genskab med `DebugCapture`, se AGENTS.md).

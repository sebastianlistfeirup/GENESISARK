# START HER — GENESIS ARK

Hej Sebastian. Dette er overdragelsen fra ferie-sessionerne (17.-19. oktober 2026). Alt herunder er afprøvet i containeren med Godot 4.5.1; hvad der *ikke* kunne afprøves, står eksplicit.

## 0. Første dag hjemme (ca. 3-4 timer, i denne rækkefølge)

| # | Hvad | Kommando / sted | Færdig når |
|---|---|---|---|
| 1 | Installér **Godot 4.5.1-stable** (præcis den version) + Python 3 + Git. Klon repoet. | `docs/VERSION_MATRIX.md` | `godot --version` viser 4.5.1 |
| 2 | Kør hele testkæden én gang på din maskine. | `tools/check.sh` (Windows: i Git Bash med `GODOT_BIN=".../Godot_v4.5.1-stable_win64_console.exe" tools/check.sh`) | sidste linje: alle `*_exit=0` |
| 3 | Mål ydelsen på din **referencecomputer** (Forward+, 1080p). Det er første gang, frametider tæller. | `godot --path . -- --perf` | `PERF TOTAL … 0 over budget`; rapport i `evidence/perf/perf_report.json` |
| 4 | Spil demoen (~20 min) og skriv de tre største irritationsmomenter ned (GA-11). | F5 i Godot | tre punkter på papir |
| 5 | Eksportér Windows-build og start den (GA-12). | `godot --headless --path . --export-release "Windows Desktop" builds/windows/GenesisArk.exe` | spillet starter uden editor |
| 6 | Download Synty-pakkerne til `assets/quarantine/` (kommer aldrig i git). | `docs/SYNTY_INTEGRATION.md` §0-2 | pakkerne ligger lokalt |
| 7 | Automatisk import: pak ud → match → kig valg igennem → byg. | `tools/synty/build.sh` (se "Hurtig vej") | `evidence/synty_build.json`, F5 viser Synty-modeller |
| 8 | Figurer: åbn **RigLab** (F6) og ret skala/offset, til auditten er grøn (GA-14). | `scenes/tests/RigLab.tscn` | audit grøn |
| 9 | Kør `tools/check.sh` og `--perf` igen efter importen. Kollision på bygninger følger nu modellerne af sig selv. | | grønt, inden for budget |

Når 1-5 er gjort, kan fase 1-porten lukkes (GA-11/12). 6-9 starter GA-13/14.

## 1. Hvad er der?

Et komplet, spilbart **greybox-spil** fra vågen kaptajn til overdragelse af kolonien:

1. **Arken** (3. person): mørkt skib med nødlys → genopret nødstrøm i værkstedet → embryobanken viser 50.000 → broen.
2. **Stjernekort**: seks kandidatverdener, ruter med brændstof/skrog/dage, minimumsreserve, fjernsonder (3 komp.), sammenligning af *kendt/skøn/ukendt* viden.
3. **Indflyvning**: undvig asteroider og bælter (W/S fart, A/D sideværts, Shift undvigemanøvre, `F` lader navigationscomputeren NAV flyve). NAV vurderer hver rute på stjernekortet og melder farer, brændstof og ilt.
4. **Kredsløb**: orbital scanning, sitesonder, ekspedition og landingspreview med kendte risici, startlager og energiplan. Landing kan kun ske én gang (pre-landing-save).
5. **Ekspedition**: biome-terræn, to ruter, fareområde, dragtenergi (0,12/s, varsel ved 30), 8 s prøvetagning, relæ, dronereserve, varslet tilbagekaldelse.
6. **Kolonien**: overheadkamera (WASD, hjul, Q/E), 12 byggeklasser med ghost-placering og årsager, distrikter, forsyningsnet, strømprioritet, flaskehalse, moduler (filter/varme), vedligehold, pause/1x/3x.
7. **Befolkning**: inkubation med synlige krav, 270 dages gestation, kohorter, børn → voksne ved 18 år, embryoregnskab altid 50.000.
8. **Generationsspring**: prognose → godkend → spring til år 20/40; stopper før uafklarede kriser. Valg ved år 20 (tre unge stemmer), råd, ni hændelser, tre slutprofiler og epilog.
9. **Save/load**: kuvert med checksum, sikker skrivning, backup, korrupt-/afbrudt-gendannelse, v1→v2-migrering. Pausemenu, journal (`Tab`), indstillinger med tasteomlægning, undertekster, UI-skala, reduceret bevægelse.
10. **Sprog, controller og krediteringer**: spillet er på **engelsk**, dansk kan vælges (Indstillinger → Language). Xbox-controller i hele spillet, krediteringer med licenser i hovedmenuen.
12. **Lys, effekter og NAV** (session 5): lys pr. planet i `data/art/lighting.json`, ti partikeleffekter i `art/fx/` (fremviser: `--scene=fxlab`), NAV melder også på planeten, bygninger kolliderer efter modellens form.
11. **Lyd overalt**: alle 53 lydcues er koblet på (52 + alarmvarianten); 42 har midlertidige proxy-lyde. Rigtige lyde erstatter dem automatisk.

## 2. Spil det

1. Installér **Godot 4.5.1-stable** (samme version — se `docs/VERSION_MATRIX.md`).
2. Åbn mappen i Godot → **F5**. Eller kør den eksporterede build i `builds/` (se `docs/STATUS.md`).
3. Taster: WASD, mus, `E` interagér, `Shift` løb, `Tab` journal, `Esc` pause, `B` kaptajn/overhead i kolonien, `R` drej bygning, `Mellemrum/1/3` tid.
4. Controller: venstre stik/D-pad bevæg, højre stik kamera, `A` interagér/bekræft, `B` fortryd, `X` drej bygning/dronereserve, `Y` kolonitilstand/autopilot, `LB/RB` drej kamera, `LT/RT` zoom/højde, `Start` pause, `Back` journal, `L3` løb, `R3` pause tid.
5. Telefon: web-buildet med touch (se `docs/STATUS.md`).

## 3. Næste skridt: Synty (GA-13 →)

**Hurtigst (anbefalet):** følg "Hurtig vej" øverst i `docs/SYNTY_INTEGRATION.md`: `unpack.py` for hver pakke → `match.py` → kig `data/art/synty_choices.json` igennem → `tools/synty/build.sh` → F5. I editoren viser fanen **Asset-slots** hvilke slots der mangler, og mapper en markeret model med ét klik. Figurer og Mixamo-animationer retargetes automatisk.


Spillet er bygget, så du **kun skal samle grafik**:
- `docs/SCENE_ASSEMBLY.md` — hvad der skal ind i hvilken scene (arken, rummet, tre biomer, kolonien, UI), med slot-navne og pakkeforslag.
- `docs/SYNTY_INTEGRATION.md` — trin for trin: download → karantæne → FBX-import → wrapper → slot → ledger.
- `data/art/asset_slots.json` — 81 slots. Skriv stien til en wrapper i `"scene"`, og proxyen skiftes overalt.
- `data/art/synty_suggestions.json` — forslag til pakke og navnemønstre pr. slot (ikke verificeret mod filerne).
- `scenes/tests/RigLab.tscn` — åbn med **F6**, når kaptajnen/Sidekick er importeret: auditten siger med det samme, om skala, fødder og clips passer, og du kan se fodglid mod 1 m-gitteret.

## 3b. Hele produktionsplanen

`docs/PRODUCTION_PLAN.md` — plan fra nu til udgivelse: faser og milepæle, værktøjsmatrix (Synty, Blender, Mixamo, ElevenLabs, HeyGen, Gemini, Grok, Kimi/DeepSeek, Meshy), lyd og musik, stemmer, video og trailer, animation, tekst, lokalisering, UI, test, ydelse, Steam-udgivelse, budget og uge-for-uge-plan.
- `docs/AUDIO_LEDGER.csv` — 53 lydcues med prompts til ElevenLabs. Læg færdige filer i `assets/audio/final/<cue_id>.ogg`, så bruger spillet dem automatisk.
- `docs/VO_SCRIPT.csv` — alle 92 replikker til stemmer. Læg filer i `assets/audio/vo/<line_id>.ogg`, så afspilles de med underteksten.

## 3c. Tekst og oversættelse

Al spillertekst skrives på **engelsk** i koden (`Loc.t("...")`) eller i `data/*.json` (D-025). Kør `python3 tools/loc_extract.py` → nye linjer lander i `localization/translations.csv` med tom dansk kolonne; udfyld dem (eller lad en agent gøre det). `tools/check.sh` fejler, til alt er oversat, og tjekker at `%d`/`{settlement}` følger med. Nyt sprog = ny kolonne + `Loc.LANGUAGES`.

## 4. Kvalitet og beviser

| Lag | Kommando | Resultat |
|---|---|---|
| Alt i ét | `tools/check.sh` (~4 min; `CHECK_FAST=1` springer kampagnen over) | parse-tjek, oversættelse, 65 tests, 49 scenechecks, 6 touch-checks, én hel kampagne |
| Hele kampagnen 6 × 4 | `godot --headless --path . --script res://tools/campaign/campaign_bot.gd` (~7 min) | spiller alt fra arken til epilog på alle planeter; se `evidence/campaign_bot.json` |
| Ydelse | `godot --path . -- --perf [--profile=web]` | budget i `data/perf/budget.json`; rapport i `evidence/perf/` |
| Domænetests | `godot --headless --path . --script res://tests/run_tests.gd` | se `evidence/test_report.json` |
| Scenetests (rigtigt input) | `godot --headless --path . res://scenes/tests/scene_smoke.tscn` | se `evidence/scene_smoke.json` |
| Balance 6 × 3 | `godot --headless --path . --script res://tools/balance/run_balance.gd` | se `evidence/balance/` |
| Screenshots | `DebugCapture` under Xvfb | `evidence/shots/*.png` |

## 5. Ærlig status

Se `docs/STATUS.md` (fase, porte, tests, blokeringer, næste tre opgaver) og `docs/RISKS.md`. Kort: Fase 1-indholdet er implementeret og testet i greybox; porten kræver visuel kontrol på din maskine og en kørsel af Windows-buildet. Meget af fase 2-3-logikken (seks planeter, tolv bygninger, kohorter, generationer, hændelser, slutninger) findes allerede som data + domæne + UI, men er ikke kvalitetsgodkendt med Synty, animation eller spiltestere.

## 6. Dokumenter

`docs/PRODUCTION_PLAN.md` · `README.md` · `AGENTS.md`/`CLAUDE.md` (regler for kodeagenter) · `tasks.json` + `tools/validate_plan.py` · `docs/BIBLE.md` · `docs/STATUS.md` · `docs/DECISIONS.md` · `docs/RISKS.md` · `docs/VERSION_MATRIX.md` · `docs/CAPABILITY_MATRIX.md` · `docs/ASSET_LEDGER.csv` · `docs/ANIMATION_LEDGER.csv`

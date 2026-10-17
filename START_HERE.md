# START HER — GENESIS ARK

Hej Sebastian. Dette er overdragelsen fra den autonome udviklingsnat (17.-18. oktober 2026). Alt herunder er afprøvet i containeren med Godot 4.5.1; hvad der *ikke* kunne afprøves, står eksplicit.

## 1. Hvad er der?

Et komplet, spilbart **greybox-spil** fra vågen kaptajn til overdragelse af kolonien:

1. **Arken** (3. person): mørkt skib med nødlys → genopret nødstrøm i værkstedet → embryobanken viser 50.000 → broen.
2. **Stjernekort**: seks kandidatverdener, ruter med brændstof/skrog/dage, minimumsreserve, fjernsonder (3 komp.), sammenligning af *kendt/skøn/ukendt* viden.
3. **Indflyvning**: kort assisteret pilotsegment (gas, drej, autopilot `F`).
4. **Kredsløb**: orbital scanning, sitesonder, ekspedition og landingspreview med kendte risici, startlager og energiplan. Landing kan kun ske én gang (pre-landing-save).
5. **Ekspedition**: biome-terræn, to ruter, fareområde, dragtenergi (0,12/s, varsel ved 30), 8 s prøvetagning, relæ, dronereserve, varslet tilbagekaldelse.
6. **Kolonien**: overheadkamera (WASD, hjul, Q/E), 12 byggeklasser med ghost-placering og årsager, distrikter, forsyningsnet, strømprioritet, flaskehalse, moduler (filter/varme), vedligehold, pause/1x/3x.
7. **Befolkning**: inkubation med synlige krav, 270 dages gestation, kohorter, børn → voksne ved 18 år, embryoregnskab altid 50.000.
8. **Generationsspring**: prognose → godkend → spring til år 20/40; stopper før uafklarede kriser. Valg ved år 20 (tre unge stemmer), råd, ni hændelser, tre slutprofiler og epilog.
9. **Save/load**: kuvert med checksum, sikker skrivning, backup, korrupt-/afbrudt-gendannelse, v1→v2-migrering. Pausemenu, journal (`Tab`), indstillinger med tasteomlægning, undertekster, UI-skala, reduceret bevægelse.

## 2. Spil det

1. Installér **Godot 4.5.1-stable** (samme version — se `docs/VERSION_MATRIX.md`).
2. Åbn mappen i Godot → **F5**. Eller kør den eksporterede build i `builds/` (se `docs/STATUS.md`).
3. Taster: WASD, mus, `E` interagér, `Shift` løb, `Tab` journal, `Esc` pause, `B` kaptajn/overhead i kolonien, `R` drej bygning, `Mellemrum/1/3` tid.

## 3. Næste skridt: Synty (GA-13 →)

Spillet er bygget, så du **kun skal samle grafik**:
- `docs/SCENE_ASSEMBLY.md` — hvad der skal ind i hvilken scene (arken, rummet, tre biomer, kolonien, UI), med slot-navne og pakkeforslag.
- `docs/SYNTY_INTEGRATION.md` — trin for trin: download → karantæne → FBX-import → wrapper → slot → ledger.
- `data/art/asset_slots.json` — 81 slots. Skriv stien til en wrapper i `"scene"`, og proxyen skiftes overalt.
- `data/art/synty_suggestions.json` — forslag til pakke og navnemønstre pr. slot (ikke verificeret mod filerne).

## 4. Kvalitet og beviser

| Lag | Kommando | Resultat |
|---|---|---|
| Domænetests | `godot --headless --path . --script res://tests/run_tests.gd` | se `evidence/test_report.json` |
| Scenetests (rigtigt input) | `godot --headless --path . res://scenes/tests/scene_smoke.tscn` | se `evidence/scene_smoke.json` |
| Balance 6 × 3 | `godot --headless --path . --script res://tools/balance/run_balance.gd` | se `evidence/balance/` |
| Screenshots | `DebugCapture` under Xvfb | `evidence/shots/*.png` |

## 5. Ærlig status

Se `docs/STATUS.md` (fase, porte, tests, blokeringer, næste tre opgaver) og `docs/RISKS.md`. Kort: Fase 1-indholdet er implementeret og testet i greybox; porten kræver visuel kontrol på din maskine og en kørsel af Windows-buildet. Meget af fase 2-3-logikken (seks planeter, tolv bygninger, kohorter, generationer, hændelser, slutninger) findes allerede som data + domæne + UI, men er ikke kvalitetsgodkendt med Synty, animation eller spiltestere.

## 6. Dokumenter

`README.md` · `AGENTS.md`/`CLAUDE.md` (regler for kodeagenter) · `tasks.json` + `tools/validate_plan.py` · `docs/BIBLE.md` · `docs/STATUS.md` · `docs/DECISIONS.md` · `docs/RISKS.md` · `docs/VERSION_MATRIX.md` · `docs/CAPABILITY_MATRIX.md` · `docs/ASSET_LEDGER.csv` · `docs/ANIMATION_LEDGER.csv`

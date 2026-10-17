# GENESIS ARK

> Du er det sidste menneske, der kan give menneskeheden en fremtid.
> 50.000 embryoner. Seks mulige verdener. Ét valg, du skal leve med.

Singleplayer sci-fi-kolonispil i **Godot 4.5.1 (GDScript)**, bygget efter *Genesis Ark Udviklingsbibel v1* (`docs/BIBLE.md`). Grafikken bliver Synty POLYGON; indtil pakkerne er importeret, kører hele spillet med registrerede greybox-proxies (`data/art/asset_slots.json`).

**Start her:** [`START_HERE.md`](START_HERE.md)

## Hurtigt

```bash
godot --path .                                        # spil (Godot 4.5.1)
tools/check.sh                                        # import + domænetests + scenetests
godot --headless --path . --script res://tests/run_tests.gd
godot --headless --path . res://scenes/tests/scene_smoke.tscn
godot --headless --path . --script res://tools/balance/run_balance.gd
python3 tools/validate_plan.py                        # tasks.json: id'er, afhængigheder, cykler
```

## Struktur (bibel s. 21)

| Sti | Ansvar |
|---|---|
| `scripts/domain/` | Regler og serialiserbar tilstand. Ingen noder. Kommandoer returnerer `CommandResult`. |
| `scripts/persistence/` | Save-kuvert, checksum, sikker skrivning, backup, migrering. |
| `scripts/runtime/` | Kaptajn, kameraer, skib, terræn, koloni, flyvning — præsentationsadaptere. |
| `scripts/ui/` | Skærme og HUD (sender kommandoer, ejer ingen tilstand). |
| `scripts/autoload/` | `AppFlow`, `GameSession`, `SaveService`, `AudioService`, `SettingsService`. |
| `data/` | Planeter, sites, farer, ruter, bygninger, scouting, hændelser, slutninger, mål, historie, balance, asset-slots. |
| `scenes/` | Boot, menu, skib, flyvning, overflade, koloni, epilog, tests, site-dressing. |
| `tests/` + `fixtures/` | Domænetests, scenesmoke, save-fixtures (v1 + v2). |
| `docs/` + `evidence/` | Bibel, status, beslutninger, risici, Synty-guides, ledgers, testrapporter, screenshots, balance. |
| `tools/` | Tjek-script, balance, fixtures, asset-slot-generator, placeholderlyd, planvalidator. |

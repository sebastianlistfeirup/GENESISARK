# builds/

Genererede builds holdes ude af git (bibel s. 21). Byg selv med Godot 4.5.1 + export templates:

```bash
godot --headless --path . --export-release "Windows Desktop" builds/windows/GenesisArk.exe
godot --headless --path . --export-release "Linux" builds/linux/GenesisArk.x86_64
```

Begge presets findes i `export_presets.cfg` (data/*.json inkluderes; tests/tools/docs/evidence udelades).
Status for seneste eksport: se `docs/STATUS.md` og `evidence/GA-12/result.json`.

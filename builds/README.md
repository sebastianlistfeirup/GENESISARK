# builds/

Genererede builds holdes ude af git (bibel s. 21). Byg selv med Godot 4.5.1 + export templates:

```bash
godot --headless --path . --export-release "Windows Desktop" builds/windows/GenesisArk.exe
godot --headless --path . --export-release "Linux" builds/linux/GenesisArk.x86_64
```

Begge presets findes i `export_presets.cfg` (data/*.json inkluderes; tests/tools/docs/evidence udelades).
Status for seneste eksport: se `docs/STATUS.md` og `evidence/GA-12/result.json`.

## Web (test på telefon)

```bash
godot --headless --path . --export-release "Web" builds/web/index.html
python3 tools/build_web_artifact.py <ud-mappe>   # deler .wasm i <15 MB-stykker og inliner engine-JS
```
Web-buildet bruger GL Compatibility uden tråde og får touch-styring (`scripts/autoload/touch_controls.gd`) automatisk på berøringsskærme.

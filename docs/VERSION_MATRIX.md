# Versionsmatrix

| Komponent | Låst version | Kilde / bemærkning |
|---|---|---|
| Godot Engine | **4.5.1-stable (official, f62fdbde1)** | `Godot_v4.5.1-stable_linux.x86_64` fra github.com/godotengine/godot/releases. Samme version skal bruges på Windows (`Godot_v4.5.1-stable_win64.exe`). |
| Export templates | 4.5.1.stable | `Godot_v4.5.1-stable_export_templates.tpz` (windows_release_x86_64.exe, linux_release.x86_64 er afprøvet). |
| Sprog | GDScript (typed) | Ingen C#/.NET, ingen GDExtensions, ingen addons. |
| Renderer | Forward+ (desktop) | Fallback til OpenGL3 er slået til (`rendering_device/fallback_to_opengl3`). CI/screenshots kører `--rendering-method gl_compatibility` under Xvfb + Mesa llvmpipe. |
| Fysik | Godot Physics 3D, 60 Hz | Bibel s. 29. Koloniøkonomi tickes separat (1 dag = 2 s ved 1x). |
| Save schema | 2 | v1 → v2 migrering testet med `fixtures/saves/v1_voyage.json`. |
| Content version | 0.1.0 | `data/balance/baseline.json` |
| Python (værktøjer) | 3.10+ | Kun stdlib: `tools/gen_asset_slots.py`, `tools/gen_placeholder_audio.py`, `tools/validate_plan.py`. |

Engineopgradering midt i en fase kræver en konkret grund, rollback og regressionskørsel (bibel s. 19).

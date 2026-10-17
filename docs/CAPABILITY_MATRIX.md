# Capability-matrix (miljøaudit)

Registreret 17.10.2026 i den autonome ferie-session (cloud-container, Linux x86_64, 4 kerner, 15 GB RAM, ingen GPU).

| Værktøj / service | Status | auth_mode | Tilladte handlinger | Input → output | Bemærkning |
|---|---|---|---|---|---|
| Godot 4.5.1 (Linux) | available | — | import, tests, scenetests, eksport | projekt → builds/evidence | Hentet officielt binær. Headless + Xvfb. |
| Godot export templates 4.5.1 | available | — | Windows + Linux eksport | projekt → `.exe` / `.x86_64` | macOS/web/Android ikke installeret. |
| Xvfb + Mesa llvmpipe | available | — | screenshots via `DebugCapture` | scene → PNG | Softwarerendering; GL Compatibility. Visuel kvalitet ≠ målmaskine. |
| Synty-pakker (9 stk.) | **unavailable her** | købt af ejeren | — | — | Ikke i repo (må aldrig committes). Alle visuals er registrerede proxies (VisualSlots). |
| Blender | unavailable | — | — | — | Ikke nødvendigt for FBX-sporet i Godot 4.5. |
| Mixamo / Sidekick-tool | unavailable | — | — | — | Kræver ejerens konto/Unity. |
| ElevenLabs / billed-/videoværktøjer | unavailable | — | — | — | Lokale placeholderlyde bruges (`assets/audio/placeholder`). |
| Eksterne spiltestere | unavailable | — | — | — | Playtest registreres som udestående (bibel s. 15). |
| Windows-maskine | unavailable | — | — | — | Windows-build er krydseksporteret, ikke kørt på Windows. |
| GitHub (repo) | available | session-token | push til `main` | commits | sebastianlistfeirup/GENESISARK |

Et abonnement beviser ikke API-adgang. Ingen nøgler i kode, screenshots eller prompts.

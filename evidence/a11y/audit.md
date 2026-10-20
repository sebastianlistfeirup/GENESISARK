# GA-29 accessibility audit (bible "Tilgængelighed", p.26)

Engine 4.5.1-stable, renderer gl_compatibility under Xvfb. Base commit `ce43ca5`.

## Method

Every main screen captured with `DebugCapture` at 1280x720 and 1920x1080, UI scale 1.0 and 1.5:

```bash
xvfb-run -a godot --path . --rendering-method gl_compatibility --resolution 1280x720 -- \
  --capture=evidence/a11y/after/<name>_1280x720_s1.5.jpg --scene=<scene> --setup=<fixture> \
  [--action=<a>] --wait=90 --ui_scale=1.5
```

New capture-only flags (never written to `settings.cfg`): `--ui_scale=<f>` sets
`root.content_scale_factor` in memory; `--action=pause|pause_settings|alarm` work in
every gameplay scene through its `GameHud`.

Screens (name | scene | fixture | action): `menu`, `menu_settings`, `menu_credits` (menu, fresh);
`ship`, `ship_starmap`, `pause`, `pause_settings` (ship, power); `ship_orbit` (ship, orbit:viridia, orbit);
`flight` (flight, approach:umbra); `surface`, `surface_alarm` (surface, expedition:viridia);
`colony`, `colony_overview`, `colony_future`, `colony_event`, `colony_decision`, `colony_ghost`,
`colony_alarm` (colony, grown:pelagos); `ending` (ending, era:pelagos:200).

The project renders at 1920x1080 with `stretch=canvas_items, aspect=expand`, so the
*logical* screen is 1920x1080 / ui_scale. Layout depends only on the logical size:
1280x720@1.0 has the same layout as 1920x1080@1.0 (smaller pixels), and 1920x1080@1.5
the same as 1280x720@1.5 (logical 1280x720, the tightest case). `before/` holds all
1280x720 shots (both scales) plus two 1920 references; `after/` holds all 1280x720
shots and 1920x1080@1.0 (plus two 1920@1.5 references). All shots were looked at.

## Result

| Requirement | Status | Evidence |
|---|---|---|
| All actions rebindable | FIXED | All 24 actions were in Settings > Controls, but two inputs were hard-coded keys: subtitle skip (`KEY_ENTER`, story_player.gd) and "hold to keep building" (`KEY_SHIFT`, colony_scene.gd). Both are now actions `skip_line` / `build_repeat` in `SettingsService.ACTIONS` and appear in the remap list. Prompts that printed fixed keys now follow remaps via `SettingsService.primary_key()`: flight controls prompt, colony "Captain [B]" and speed tooltip, overlay "Close [Esc]". Controller layout is fixed by decision D-018 (not remappable in v1). `pause_settings_1280x720_s1.5.jpg` |
| UI scales; tested at 1280x720 and 1920x1080; critical text never clipped | FIXED | See the clipping table below. Automated: `tests/scene_smoke.gd` `_check_a11y_fit()` (5 checks, logical 1280x720 at scale 1.5). |
| Reduce shake / flashes / motion | PASS | `reduced_motion` setting gates fades (app_flow.gd), NAV typewriter (nav_comms.gd), waypoint pulse (waypoint_layer.gd), FX bursts (fx_effect.gd `calm`), colony camera easing, flight camera shake (also its own `camera_shake` toggle). The new alarm banner blinks only without reduced motion (game_hud.gd `show_alarm`). |
| Subtitles have speaker and adjustable size | FIXED | Story lines always show the speaker name (NARRATOR intentionally unnamed); size 16-34 in Settings. The speaker line had a fixed 16 px and now scales with the subtitle size; the NAV channel (also a subtitle channel, speaker "NAV") had a fixed 17 px and now follows the subtitle size (story_player.gd, nav_comms.gd). `surface_alarm_1920x1080_s1.0.jpg` |
| Colour is never the only signal | FIXED | Found colour-only signals and added symbol/text: colony power chip (green/red -> `●`/`■` + sign) and reserve chip (amber -> `▲` when < 30 days) in colony_ui.gd; NAV line severity (red/amber -> `■`/`▲`) in nav_comms.gd and the star-map NAV box (star_map_panel.gd); forecast stop line (green/amber -> `●`/`▲`) in colony_overview.gd; star-map route risk (petrol/amber/red dashed line -> `▲` risky, `✕` impossible next to the fuel cost) in star_map_view.gd; surface route labels (petrol/amber -> `●` safe / `▲` risky) in surface_scene.gd. Already fine: toasts, event titles, knowledge rows, building status labels, ghost placement tip, journal. `ship_starmap_1280x720_s1.5.jpg` (28 ⛽ ▲), `colony_1280x720_s1.5.jpg`, `surface_alarm_1920x1080_s1.0.jpg` |
| Critical sounds have visual signals | FIXED | Alarm sounds (`AudioService.alarm()` and the flight impact alarms) had no visual twin of their own. New `AudioService.alarm_raised(critical)` signal; `GameHud.show_alarm()` shows `■ ALARM: critical` / `▲ ALARM: warning` with a coloured frame, blinks 3x (steady with reduced motion), hides after ~5 s. Smoke check `a11y_alarm_has_visual_signal`. `colony_alarm_1280x720_s1.5.jpg`, `surface_alarm_*` |
| Pause and settings reachable from gameplay | PASS | `GameHud` (ship, flight, surface, colony) owns `PauseMenu` (`pause` action, Esc / pad Start) with Settings inside. `pause_1280x720_s1.5.jpg`, `pause_settings_1280x720_s1.5.jpg` |

### Clipping / overlap at logical 1280x720 (1280x720@1.5)

| Screen | Before | After |
|---|---|---|
| Main menu | Tagline drawn over the Quit button (`before/menu_1280x720_s1.5.jpg`) | Title, menu and tagline in one vertically centred column (main_menu.gd) - `after/menu_1280x720_s1.5.jpg` |
| Star map, orbit, colony overview, event, decision (all `OverlayPanel`) | Panels 1180-1240 x 760 px: header and Close button cut at the top, bottom rows cut (`before/ship_starmap_1280x720_s1.5.jpg`, `before/ship_orbit_…`, `before/colony_overview_…`, `before/colony_future_…`) | `UiKit.fit_layer()` scales the modal layer down about the screen centre until the panel fits (scale stays 1 when it already fits); re-fits on open, content change, window resize and settings change; the dim is oversized so it still covers the screen. Also used by Settings and Credits. `after/ship_starmap_…`, `after/ship_orbit_…`, `after/colony_overview_…`, `after/colony_future_…` |
| Colony HUD | Build bar ran off both screen edges (Solar array and School hidden); resource bar covered the objective panel (`before/colony_1280x720_s1.5.jpg`, `before/colony_ghost_1920x1080_s1.5.jpg`) | Build bar is an `HFlowContainer` limited to the screen width (wraps to 2 rows); when the top bar overlaps the side columns, `GameHud.set_insets()` moves objectives, toasts, info panel and alarm below it, and lifts the subtitle and prompt boxes above a taller bottom bar (colony_scene.gd `_layout_hud`). `after/colony_1280x720_s1.5.jpg`, `after/colony_ghost_1280x720_s1.5.jpg`, `after/colony_ghost_1920x1080_s1.5.jpg` |
| Ending | Buttons below the screen edge at 1.5 (`before/ending_1280x720_s1.5.jpg`, captured before the ending fix) | Epilogue text scrolls, the button row stays on screen (ending_screen.gd) - `after/ending_1280x720_s1.5.jpg` |
| Ship, flight, surface HUD, pause, settings, credits | Fit | unchanged |

Other fixes found on the way: decision buttons showed Danish words in the English game
("Support Noor (ekspansion)") -> `Loc.t("expansion")` etc. (decision_dialog.gd); the
forecast's empty construction list printed "intet" -> `Loc.t("none")` (colony_overview.gd).

### Automated check (deterministic)

`tests/scene_smoke.gd::_check_a11y_fit()` pins the logical screen to 1920x1080 / 1.5 =
1280x720 (`content_scale_aspect = KEEP`, in memory only), loads the colony from
`grown:pelagos` and checks:
`a11y_hud_fits_1280x720_scale_1_5` (every visible HUD Control inside the screen),
`a11y_build_bar_wraps` (bottom bar at most two rows), `a11y_top_bar_clear_of_objectives`,
`a11y_overlays_fit_1280x720_scale_1_5` (overview, event and decision dialogs inside the
screen after fit), `a11y_alarm_has_visual_signal`. With the layout fixes disabled the
overlap and overlay checks fail (verified once by hand).

## OPEN

- **Small text at 1280x720 with UI scale 1.0.** The UI is authored for 1920x1080 and
  scaled down, so 13-15 pt labels (hints, version line, knowledge sources) render at
  9-10 px (`after/flight_1280x720_s1.0.jpg`, `after/colony_1280x720_s1.0.jpg`). Readable,
  and the player can raise UI scale to 1.5 (now clip-free), but the default does not
  adapt to the window. Proposal: pick the default `ui_scale` from the window height on
  first start (e.g. 1.25 at <= 800 px). Not done: changes first-run defaults for all
  players, which is a design call.
- **Controller remapping** is not offered (D-018, documented). Keyboard/mouse is fully
  rebindable.
- **Rebind conflicts** are not detected (two actions on one key is allowed silently).
- **Subtitle toggle** hides only narrator lines; character and NAV lines always show
  (intended "subtitles work without voice", but the toggle label does not say so).
- **3D-only cues** (district rings, route dots, ghost tint) still use colour, but each has
  a text label or tip next to it; no change needed for the bible rule, noted for art.
- `colony_event` / `colony_decision` were captured via debug actions; events reached
  through the real clock also raise the alarm banner (`GameSession._check_new_events`).

# Land lock on Sere (R10) — investigation log

Found by `tools/campaign/campaign_bot.gd` after merging D-030 (era planner keeps one robot unit free).

**Repro:** `godot --headless --path . --script res://tools/campaign/campaign_bot.gd -- --planet=sere --policy=middle --seed=5014`
**Observed:** year 28.8, 450 people, profile shielded; era stops `incubation_stalled` x75; incubation blocker "Requires water and food reserves for 30 days (now 0)". Buildings at the end: solar_array 51, water_plant 40, greenhouse 15, habitat 13. Free greenhouse spots on a 3 m grid: landing 0, resource 0, living 0.
**Before D-030:** the same seed reached year 40 / 650 / independent (bot run 2, pre-merge).

| # | Hypothesis | Change tried | Result |
|---|---|---|---|
| 1 | Comfort power (`surplus < 20` rule) eats land after farms are crowded | Skip comfort generator while greenhouse/water/habitat has no space | Identical: stuck at 28.8. Reverted. |
| 2 | The bot only searches the landing district | Counted free spots in all districts | 0 everywhere: the land really is full. (Diagnosis, kept in the bot as `greenhouse_room_end`.) |
| 3 | Districts stop growing too early (cap 2.2 at year 30) | Moved growth to data (`balance.districts`), tried cap 2.6 | Identical: the lock happens before the cap matters. Cap restored to 2.2; the data move is kept (no behavior change). |

**Next hypothesis (not tried):** the planner should weigh output per square meter: prefer geothermal/batteries over more panels, add water plants only when food is not the bottleneck, and leave room for greenhouses. Run the full bot matrix after any change.

## Resolved (D-032)

| # | Hypothesis | Change | Result |
|---|---|---|---|
| 4 | Component starvation: wear (x2.4 on Sere) outpaces one workshop; worn buildings give half output, power sheds mine/workshop first, planner answers with more panels and pumps until land is full | `--trace` per leap confirmed components 0 from year ~20, shed 8 buildings, 47 panels at ~50 % output. Planner now sizes workshops to the maintenance bill (`EraService.component_balance`, max 6) | Seed 5014: year 40 / 650 / independent, components ~300. Full matrix 24/24, balance 18/18. Seed 5014 now runs in `tools/check.sh`. |

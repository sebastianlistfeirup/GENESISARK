# GA-28 balance iterations

Command: `godot --headless --path . --script res://tools/balance/run_balance.gd` (seeds 1001-1018, Godot 4.5.1).

## Baseline (commit a1c1a17)

15/18 independent. Collapses: Viridia power_first (year 12.7, pop 40), Pelagos lean (year 4.3, pop 60), Nivalis lean (year 3.3, pop 40). All others 650 at year 40, Ferrum 560. Viridia balanced ended with only 140 adults (sign of a long stall).

## Diagnosis (per-run day/leap trace, temporary script, not committed)

Same root cause in all three. It is a rule bug in the leap institutions (`EraService._needs`), not a weak bot:

- Workforce = ark drones (3) × planet `drone_efficiency` + adults/4. Staffed buildings (mine, workshop: workforce 1) take their crew first; construction only gets what is left.
- During the first leap the institutions add a second mine (`mine` wanted while alloy < 120 and fewer than 2 + year/6 mines). They never build a drone hub.
- **Viridia power_first**: 3 drones, 2 mines + workshop leave 0 for construction. From year 1.5 on, nothing completes. The harness keeps ordering water plants and greenhouses (26 sites pile up "constructing"), food runs out at year 11, and incubation never restarts.
- **Pelagos lean** (2.85 drones) and **Nivalis lean** (2.4 drones): 2 mines staffed, workshop unstaffed (0.85 / 0.4 left) → 0 components income. Maintenance eats the 40 starting components, greenhouses (1 component) can't be built, food runs out at year 2-3, and incubation stalls on every leap (80 × "incuba").
- The "successful" runs had the same stall. Viridia balanced built nothing from year 1.6 to about year 18 and was rescued only by the first adults. Survival depended on how much food was stockpiled before the freeze.
- Lean opening strategies differ only in what's in the hand-built queue. Lean has no workshop, so the era put the second mine ahead of the workshop in staffing order.

## Iteration 1: domain rule fix (EraService)

Change: `_needs` puts `drone_hub` first when free workforce < 1. A mine or workshop is only requested if at least one labor unit stays free afterwards (`free_workforce >= need + 1`); otherwise a drone hub is requested instead. New public `free_workforce(gs)`. Unit test `test_era_endings::test_institutions_keep_construction_labor` fails before the fix (no hub, 0.4 free) and passes after it.

Delta: 15/18 → 18/18 independent. Viridia power_first 40 → 650, Pelagos lean 60 → 650, Nivalis lean 40 → 650. Viridia balanced adults 140 → 360. Ferrum unchanged at 560. Every run is 330 at year 20.

## Iteration 2: harness reporting only (no rule/data change)

With collapses gone, every non-Ferrum run ends at 650 because the birth plan (20 + 16/year) is the binding cap. So that strategies stay comparable, the harness now also reports `open` (days of the hand-built opening), `defic` (days with power deficit or shortage) and `pop20`. Table numbers otherwise unchanged.

Stopped here: goal met after one rule change. No `data/` values were changed.

## Final table

```
planet   strategy      year open defic pop20   pop  adult crisis reserve  ownkW   dmd profile
viridia  balanced      40.0  116     0   330   650    360     1     365  312.0 290.0 independent
viridia  power_first   40.0  126     0   330   650    360     1     365  316.0 290.0 independent
viridia  lean          40.0   55     0   330   650    360     1     365  312.0 284.0 independent
pelagos  balanced      40.0  144  1446   330   650    360     0     365  278.4 249.0 independent
pelagos  power_first   40.0  132  1446   330   650    360     0     365  270.8 249.0 independent
pelagos  lean          40.0   57  1455   330   650    360     0     365  278.4 249.0 independent
ferrum   balanced      40.0   77    18   330   560    360     1     365  577.2 557.0 independent
ferrum   power_first   40.0  114     0   330   560    360     1     365  567.6 554.0 independent
ferrum   lean          40.0   40     0   330   560    360     1     365  577.2 557.0 independent
sere     balanced      40.0   76     1   330   650    360     1     365  360.0 340.0 independent
sere     power_first   40.0   92    17   330   650    360     1     365  364.0 340.0 independent
sere     lean          40.0   36     4   330   650    360     1     365  360.0 338.0 independent
nivalis  balanced      40.0  171    10   330   650    360     1     365  398.4 377.0 independent
nivalis  power_first   40.0  157     9   330   650    360     1     365  415.2 377.0 independent
nivalis  lean          40.0   83    32   330   650    360     1     365  415.2 377.0 independent
umbra    balanced      40.0  141    79   330   650    360     1     365  378.0 346.0 independent
umbra    power_first   40.0  121     0   330   650    360     1     365  378.0 342.0 independent
umbra    lean          40.0   55    18   330   650    360     1     365  378.0 342.0 independent
```

## Open points

- End-state strategy differentiation is weak. The leap institutions run the colony for 39 of 40 years and converge every opening. A bad opening could be made to matter more (for example, a cap on how much the institutions may build per review, or a birth plan tied to reserves), but that is a design decision, not a bug fix.
- Pelagos spends about 1450 days in power deficit (storms), yet it still reaches 650. Storm pressure may be too soft or about right; this has not been tuned.

# D-054 perf, back-to-back on the RTX 5090 (1600x900 window, Forward+, Godot 4.7.2)

Before = c2a7210 scripts with the fixed perf probe (load_ms now excludes fixture setup, consecutive colony cases detected correctly); after = this branch.
Budget desktop: 2500 draws, 3,000,000 primitives, 12000 nodes, 4000 ms load, p95 16.7 ms. Primitives include depth prepass and shadow cascades.
Frame times are vsync-locked (120 Hz) and noisy on this machine (other Godot processes running); p50 is the stable figure.

| case | prims before → after | draws before → after | nodes before → after | load ms before → after | p50/p95/p99 before | p50/p95/p99 after | after vs budget |
|---|---|---|---|---|---|---|---|
| ship | 70,135 → 64,978 | 57 → 56 | 4317 → 4317 | 1438 → 1455 | 8.3 / 16.5 / 21.7 | 8.4 / 9.1 / 17.0 | OK |
| ship_orbit_view | 147,847 → 147,173 | 193 → 192 | 4499 → 4499 | 588 → 579 | 8.5 / 20.6 / 21.1 | 8.3 / 8.8 / 9.0 | OK |
| ship_starmap | 109,722 → 109,420 | 211 → 210 | 4534 → 4534 | 476 → 442 | 8.6 / 20.6 / 21.1 | 8.4 / 15.8 / 17.4 | OK |
| flight_belt | 576,838 → 542,188 | 286 → 307 | 1241 → 1241 | 597 → 583 | 8.7 / 9.7 / 10.2 | 8.0 / 9.5 / 9.7 | OK |
| surface_viridia | 2,192,777 → 2,307,838 | 542 → 1125 | 812 → 1400 | 2499 → 2214 | 8.4 / 9.4 / 9.8 | 8.5 / 9.4 / 17.3 | OK |
| surface_hazard | 3,614,729 → 1,123,961 | 491 → 670 | 653 → 920 | 1398 → 1296 | 8.5 / 9.4 / 16.4 | 8.5 / 9.2 / 10.0 | OK |
| colony_grown | 2,891,266 → 2,390,133 | 1299 → 1248 | 1861 → 2291 | 3262 → 2882 | 8.1 / 9.5 / 10.4 | 7.9 / 9.5 / 14.1 | OK |
| colony_overview | 2,574,401 → 1,144,003 | 852 → 774 | 1793 → 2061 | 1854 → 1203 | 8.5 / 9.5 / 9.9 | 7.8 / 9.4 / 11.3 | OK |
| colony_era20 | 6,477,902 → 2,892,605 | 1741 → 1615 | 9032 → 10284 | 1989 → 1635 | 8.3 / 12.5 / 17.7 | 8.3 / 9.8 / 15.4 | OK |
| surface_descent | 58,192 → 57,230 | 55 → 55 | 869 → 1457 | 883 → 883 | 8.3 / 9.2 / 9.6 | 8.2 / 9.1 / 9.5 | OK |

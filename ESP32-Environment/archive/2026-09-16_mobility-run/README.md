# Archive — mobility-scenario run, 2026-09-16

The `-Scenario mobility` captures from 2026-09-16 (~13:45–13:53) plus every analysis
output derived from them, moved here before re-running. Nothing was deleted — this is a
straight move out of `tools/exports/` and `analysis/`, structure preserved.

Second archive of the day; the earlier one is `../2026-09-16_pre-restart/`.

## Layout

```
exports/blackhole/linear/G402/mobility/   raw device CSVs (+ trimmed/, _archive/)
exports/blackhole/linear/home/mobility/   root-only cell — see "Why re-run" below
exports/_ledger/run_ledger.csv            ledger at archive time (was header-only)
analysis/blackhole/linear/G402/mobility/  feature_table, windowed_dataset, eda_output/
analysis/blackhole/linear/home/mobility/  same, root-only
```

## Why this run is being re-done

Two independent problems, both documented in root `MEMORY.md` (2026-09-16):

1. **`G402/mobility` — 3 of 4 victims never reached root.** They were transmitting in
   nearly every window (`probes_count_delta` mean 3.8–4.1) but the root's arrivals log
   records nothing from them **in any phase**, not just during the attack — so it is not
   the blackhole signature. `B4BFE932FE90` changed mesh layer 4→5 mid-run and
   `2805A532D7B4` sits at layer 6, pointing at mobility-triggered mesh reformation
   and/or chain depth. `verify_attack.py` returns NOT CONFIRMED: the capture's own
   *baseline* is degraded (PDR 0.164 ± 0.372), so there is no clean reference to test
   against.
2. **`home/mobility` — only the root's CSVs were exported.** No victim files at all, so
   PDR cannot be computed there by definition. Check that every board uses the same
   `-Location`/`-Scenario` before exporting.

**Next run (decided 2026-09-16):** repeat `blackhole/linear/G402` **without**
`-Scenario mobility`, to isolate whether mobility is the trigger. If a plain run delivers
from all victims, mobility is the cause — a reportable finding about mesh stability, not
a flaw to hide. If it also drops them, investigate chain length / RF placement physically.

## Note on the analysis outputs in here

These were produced **after** the 2026-09-16 PDR attribution fix
(`thesis-deviate.md` **D-8**), so `G402/mobility/feature_table.csv` already shows the
corrected values: PDR non-null 238/446 with 201 genuine `PDR == 0`, and victim PDR by
phase reading baseline 0.217 → attack 0.000 → cooldown 0.750. Any *older* copy of this
cell's analysis predates that fix and should not be compared against these numbers.

Everything here is regenerable from the raw CSVs via `..\..\analyze.ps1`.

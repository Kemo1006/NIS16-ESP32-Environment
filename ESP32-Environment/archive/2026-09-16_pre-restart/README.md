# Archive — pre-restart snapshot, 2026-09-16

Snapshot of every run captured before the team wiped the boards and restarted the
data-collection campaign. Nothing here was deleted — this is a straight move of what
was in `tools/exports/` and `analysis/` at archive time, structure preserved.

## Layout

```
exports/<attack>/<topology>/[<location>/]   raw device CSVs (was tools/exports/)
exports/_ledger/                            run_ledger.csv (+ .bak) and manifest.json
                                             at time of archiving
analysis/<attack>/<topology>/[<location>/]  feature_table.csv, windowed_dataset.csv,
                                             eda_output/ (was analysis/<attack>/...)
analysis/_combined/                         combine_all.py's last combined_all.csv +
                                             the loose top-level feature_table.csv /
                                             windowed_dataset.csv / eda_output/ that
                                             sat directly under analysis/ (not yet
                                             attack/topology-sorted)
```

`<attack>` = baseline / blackhole / wormhole. `<topology>` = linear / star / tree /
partial_mesh. `<location>` = home / G402 / DLSU_lib / GOKS, present only where that
attack+topology combo used the location layer.

## Why

Restarting the run for a clean matrix. Working `tools/exports/` and `analysis/` were
reset to the empty attack/topology scaffold (`.gitkeep` placeholders) right after this
move; `tools/exports/run_ledger.csv` was reset to a header-only file. See root
`STATUS.md` / `memory/MEMORY.md` for the restart rationale.

## Regenerating analysis from this archive

The `feature_table.csv` / `windowed_dataset.csv` / `eda_output/` here are pipeline
output (`preprocess.py` → `features.py` → `eda.py`), not hand-authored — if you need
them back in the working tree, either copy them back or re-run the pipeline against
`exports/<attack>/<topology>/...` in this folder.

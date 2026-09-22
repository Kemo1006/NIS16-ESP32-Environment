# Pre-redesign archive — 2026-09-13

All captures and derived tables from the **old experimental matrix** (the 16/24 run set built Jul 2026) were moved here on **2026-09-13** when the panel ordered a dataset redesign. See `memory/panel-change-2026-09.md`.

**Why archived:** the panel (Peradilla/Solomon/Tiu) found the old dataset unfit for clustering/ML — identical r1..r3 runs (no variance), single-feature-determinable labels, no realistic IoT scenario, no paper-backed attack verification. All runs are being redone from scratch with variance, a defined indoor deployment scenario, multiple locations, and cited verification.

## Contents
- `exports/{baseline,blackhole,wormhole}/` — raw + trimmed per-node CSV captures (old matrix).
- `exports/manifest.json`, `exports/run_ledger.csv` — old run metadata/ledger.
- `analysis/{baseline,blackhole,wormhole}/{topology}/` — old feature tables (`feature_table.csv`), windowed datasets (`windowed_dataset.csv`), and `eda_output/`.

**Do not** feed this into the new dataset. Kept for git history / reference only.

_Note: older per-run archives remain at `tools/exports/_archive/` (desk tests, invalid runs from Jul 2026)._

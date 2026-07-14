# ANALYSIS-Commands.md — copy-paste M6→M7→M8 for every attack × topology

Ready-to-paste pipeline commands for **re-analysing an existing export** (CSVs
already pulled into `../tools/exports/`) — one block per
attack × topology. Sibling of [`ATTACKS-Commands.md`](../../ATTACKS-Commands.md)
(which covers the live capture + `-Analyze` path).

> ⬅️ Pipeline guide: [`analysis_README.md`](analysis_README.md) +
> [`analysis_README_2.md`](analysis_README_2.md).

## Before you paste

- **Run everything from the `analysis/` folder** (once per session):
  ```powershell
  cd "S:\My Work\DLSU\Thesis\NIS16-ESP32-Environment\analysis"
  pip install -r requirements.txt      # first time only
  ```
- Each block is 3 lines: **M6** (`preprocess.py`) → **M7** (`features.py`) →
  **M8** (`eda.py`). Run all three — M6's `windowed_dataset.csv` + its
  discard-fraction report are graded separately.
- The output folders already exist (scaffolded with `.gitkeep`); `eda.py` makes
  its own `eda_output/`. Outputs are git-ignored / regenerable.
- **One dataset per folder.** If an export folder pooled multiple runs (you
  skipped `-Wipe`), clean it first: `python ..\tools\export_logs.py --delete` on
  the boards, or re-capture. Only folders that actually hold `*_telem.csv` produce
  output.
- 💡 **Live capture instead?** Don't run these by hand — `..\run.ps1 -Analyze` on
  the root board runs M6+M7+M8 automatically right after export. See
  [`ATTACKS-Commands.md`](../../ATTACKS-Commands.md).

---

## BASELINE (normal traffic, ground-truth label 0)

```powershell
# baseline — star
python preprocess.py ../tools/exports/baseline/star_topology -o baseline/star_topology/windowed_dataset.csv
python features.py   ../tools/exports/baseline/star_topology -o baseline/star_topology/feature_table.csv
python eda.py        baseline/star_topology/feature_table.csv -o baseline/star_topology/eda_output/

# baseline — tree
python preprocess.py ../tools/exports/baseline/tree_topology -o baseline/tree_topology/windowed_dataset.csv
python features.py   ../tools/exports/baseline/tree_topology -o baseline/tree_topology/feature_table.csv
python eda.py        baseline/tree_topology/feature_table.csv -o baseline/tree_topology/eda_output/

# baseline — linear
python preprocess.py ../tools/exports/baseline/linear_topology -o baseline/linear_topology/windowed_dataset.csv
python features.py   ../tools/exports/baseline/linear_topology -o baseline/linear_topology/feature_table.csv
python eda.py        baseline/linear_topology/feature_table.csv -o baseline/linear_topology/eda_output/

# baseline — partial_mesh
python preprocess.py ../tools/exports/baseline/partial_mesh_topology -o baseline/partial_mesh_topology/windowed_dataset.csv
python features.py   ../tools/exports/baseline/partial_mesh_topology -o baseline/partial_mesh_topology/feature_table.csv
python eda.py        baseline/partial_mesh_topology/feature_table.csv -o baseline/partial_mesh_topology/eda_output/
```

## BLACKHOLE (label 1 — where PDR's real `0.0` attack signature shows)

```powershell
# blackhole — star
python preprocess.py ../tools/exports/blackhole/star_topology -o blackhole/star_topology/windowed_dataset.csv
python features.py   ../tools/exports/blackhole/star_topology -o blackhole/star_topology/feature_table.csv
python eda.py        blackhole/star_topology/feature_table.csv -o blackhole/star_topology/eda_output/

# blackhole — tree
python preprocess.py ../tools/exports/blackhole/tree_topology -o blackhole/tree_topology/windowed_dataset.csv
python features.py   ../tools/exports/blackhole/tree_topology -o blackhole/tree_topology/feature_table.csv
python eda.py        blackhole/tree_topology/feature_table.csv -o blackhole/tree_topology/eda_output/

# blackhole — linear
python preprocess.py ../tools/exports/blackhole/linear_topology -o blackhole/linear_topology/windowed_dataset.csv
python features.py   ../tools/exports/blackhole/linear_topology -o blackhole/linear_topology/feature_table.csv
python eda.py        blackhole/linear_topology/feature_table.csv -o blackhole/linear_topology/eda_output/

# blackhole — partial_mesh
python preprocess.py ../tools/exports/blackhole/partial_mesh_topology -o blackhole/partial_mesh_topology/windowed_dataset.csv
python features.py   ../tools/exports/blackhole/partial_mesh_topology -o blackhole/partial_mesh_topology/feature_table.csv
python eda.py        blackhole/partial_mesh_topology/feature_table.csv -o blackhole/partial_mesh_topology/eda_output/
```

## WORMHOLE (label 2 — tunnel between two endpoints)

```powershell
# wormhole — star
python preprocess.py ../tools/exports/wormhole/star_topology -o wormhole/star_topology/windowed_dataset.csv
python features.py   ../tools/exports/wormhole/star_topology -o wormhole/star_topology/feature_table.csv
python eda.py        wormhole/star_topology/feature_table.csv -o wormhole/star_topology/eda_output/

# wormhole — tree
python preprocess.py ../tools/exports/wormhole/tree_topology -o wormhole/tree_topology/windowed_dataset.csv
python features.py   ../tools/exports/wormhole/tree_topology -o wormhole/tree_topology/feature_table.csv
python eda.py        wormhole/tree_topology/feature_table.csv -o wormhole/tree_topology/eda_output/

# wormhole — linear
python preprocess.py ../tools/exports/wormhole/linear_topology -o wormhole/linear_topology/windowed_dataset.csv
python features.py   ../tools/exports/wormhole/linear_topology -o wormhole/linear_topology/feature_table.csv
python eda.py        wormhole/linear_topology/feature_table.csv -o wormhole/linear_topology/eda_output/

# wormhole — partial_mesh
python preprocess.py ../tools/exports/wormhole/partial_mesh_topology -o wormhole/partial_mesh_topology/windowed_dataset.csv
python features.py   ../tools/exports/wormhole/partial_mesh_topology -o wormhole/partial_mesh_topology/feature_table.csv
python eda.py        wormhole/partial_mesh_topology/feature_table.csv -o wormhole/partial_mesh_topology/eda_output/
```

---

## Bonus — analyse every folder that has data (one paste)

Loops all 12 combos and runs M6→M7→M8 only where an export actually holds
telemetry CSVs. Paste from the `analysis/` folder:

```powershell
foreach ($a in 'baseline','blackhole','wormhole') {
  foreach ($t in 'star_topology','tree_topology','linear_topology','partial_mesh_topology') {
    $src = "../tools/exports/$a/$t"
    if (Test-Path "$src\*_telem.csv") {
      Write-Host "=== $a / $t ===" -ForegroundColor Cyan
      python preprocess.py $src -o "$a/$t/windowed_dataset.csv"
      python features.py   $src -o "$a/$t/feature_table.csv"
      python eda.py        "$a/$t/feature_table.csv" -o "$a/$t/eda_output/"
    }
  }
}
```

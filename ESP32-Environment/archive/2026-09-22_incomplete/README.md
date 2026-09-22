# Archive - incomplete (2026-09-22)

(no reason recorded)

Moved here by `archive.ps1` on 2026-09-22 01:53. Nothing was
deleted or copied: this is the working tree's captured data and generated output,
moved out whole so the next run starts from an empty scaffold.

- `exports/`  - raw device CSVs, in their original
  `<attack>/<topology>/[<location>/][<scenario>/]` layout, plus `run_ledger.csv`
- `analysis/` - `windowed_dataset.csv`, `feature_table.csv` and `eda_output/`
  for the same cells

31 file(s): 11 captured, 20 generated.

Everything here is reproducible from the raw CSVs with:

```powershell
.\analyze.ps1
```

(point it at this folder's `exports/` tree, or copy a cell back into
`tools/exports/` first).
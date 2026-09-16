# Archive - bad-attacker-mac (2026-09-16)

Voided run: BLACKHOLE_ATTACKER_MAC was stale (0c:80) while the attacker board was 1c:38, so victims P2P'd every probe to a board not in the mesh. Root logged ZERO arrivals in all phases; PDR and ForwardingRatio 100% NaN. Redo after reflashing every victim.

Moved here by `archive.ps1` on 2026-09-16 20:54. Nothing was
deleted or copied: this is the working tree's captured data and generated output,
moved out whole so the next run starts from an empty scaffold.

- `exports/`  - raw device CSVs, in their original
  `<attack>/<topology>/[<location>/][<scenario>/]` layout, plus `run_ledger.csv`
- `analysis/` - `windowed_dataset.csv`, `feature_table.csv` and `eda_output/`
  for the same cells

22 file(s): 6 captured, 16 generated.

Everything here is reproducible from the raw CSVs with:

```powershell
.\analyze.ps1
```

(point it at this folder's `exports/` tree, or copy a cell back into
`tools/exports/` first).

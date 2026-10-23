# Archive - redo (oct21)

redo

Moved here by `archive.ps1` on 2026-10-21 14:12. Nothing was
deleted or copied: this is the working tree's captured data and generated output,
moved out whole so the next run starts from an empty scaffold.

- `exports/`  - raw device CSVs, in their original
  `<attack>/<topology>/[<location>/][<scenario>/]` layout, plus `run_ledger.csv`
- `analysis/` - `windowed_dataset.csv`, `feature_table.csv` and `eda_output/`
  for the same cells
- `PCAP/`     - ESP32 sniffer captures (`.pcap` + `.json` sidecar with pauses/loss),
  same cell layout plus `standalone/`. Git-ignored: they exist only on the laptop
  that archived them.
- `run_logs/` - the wizard's console transcripts (`.log`) for the same runs

3577 file(s): 632 captured, 2249 generated, 12 sniffer, 684 run log(s).

Everything here is reproducible from the raw CSVs with:

```powershell
.\analyze.ps1
```

(point it at this folder's `exports/` tree, or copy a cell back into
`datasets/exports/` first).
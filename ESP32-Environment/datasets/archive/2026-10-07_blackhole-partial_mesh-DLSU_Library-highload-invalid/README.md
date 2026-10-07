# Archive - blackhole / partial_mesh / DLSU_Library / highload - INVALID (2026-10-07)

Run r1, oct. 7, 2026 ~15:13-15:25 PHT (Angelo's laptop). Archived by hand (Claude Code) on
user request, because `archive.ps1` only archives the whole working tree, not one cell.
Files were MOVED, not copied or deleted, keeping the `<area>/<attack>/<topology>/<location>/<scenario>/` layout.

**Why it is invalid:** the root's arrival writer took ~398 ms per row (slowest 1211 ms) against
the <=35 ms that highload's ~28 rows/s allows, so **3151 arrival rows were never logged**
(`[RXSTALL] arrival queue FULL`). Root-side PDR undercounts every node, bystanders included.
Child telemetry is fine. Thesis checklist C5 / D5; fixed in commit `643adf8` (highload root
logs arrivals to the SD card only, batched). Recapture this cell with the fixed firmware.

- `exports/`  - 9 device CSVs (root telem + arrivals, 7 children)
- `PCAP/`     - sniffer json + retry csv/json (the `.pcap` itself was open in Wireshark;
  move it here by hand if it is still in `datasets/PCAP/.../highload/`)
- `run_logs/` - wizard console log of the run
- no `analysis/` - this cell was never analysed

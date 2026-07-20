# tools/ — host-side data extraction

Laptop-side scripts for pulling telemetry CSVs off the ESP32 nodes after a run.
This is the counterpart to the on-device serial-export task in
`components/mesh_common/src/csv_logger.c`.

## export_logs.py

Connects to a node over USB serial, asks it to stream its stored CSV file(s),
and saves them locally with run metadata in the filename.

### Before you run it
1. **Close `idf.py monitor`** on that board first. The export task shares UART0
   with the console, so only one program can hold the COM port at a time.
2. The run must have **finished** (root broadcasts TERMINATE). The device only
   starts the export task after the experiment ends — see the
   "Send 'EXPORT_LOGS' via serial" line in the monitor.
3. Run it from the **"ESP-IDF 5.3 PowerShell"** window so `python` already has
   `pyserial`. (Otherwise: `pip install pyserial`.)

### Usage
```powershell
cd "<repo>\NIS16-ESP32-Environment\tools"

# Root node (COM3) — pulls BOTH telem.csv and arrivals.csv
python export_logs.py --port COM3 --role root   --topology star --attack none --repeat 1

# Victim node (COM6) — pulls telem.csv
python export_logs.py --port COM6 --role child  --topology star --attack none --repeat 1

# Just see what's stored on a board, download nothing
python export_logs.py --port COM3 --list
```

Files are routed into `tools/exports/<attack-or-baseline>/<topology>_topology/`
(override the root with `--outdir`, or `--flat` to skip the subfolders), named
with the full run metadata:
```
exports/blackhole/star_topology/root_COM20_star_blackhole_r1_20260629_143022_telem.csv
exports/blackhole/star_topology/root_COM20_star_blackhole_r1_20260629_143022_arrivals.csv
exports/baseline/tree_topology/victim_COM26_tree_none_r1_20260629_143105_telem.csv
```
So each run's CSVs group by attack, then topology, and the four topologies never
mix. The `--topology`, `--attack`, and `--repeat` flags set both the folder and
the filename metadata. (The topology folder names — `star_topology`,
`tree_topology`, `linear_topology`, `partial_mesh_topology` — match the dirs
already under `exports/blackhole/` and `exports/wormhole/`.)

**Control victims:** a plain victim in an attack run is flashed `--attack none`
but belongs with that run's data. Add `--attack-dir blackhole` (or `wormhole`)
so it files under the attack's folder while its filename still reads `none`:
```powershell
python export_logs.py --port COM26 --role child  --topology tree \
    --attack none --attack-dir blackhole --repeat 1
# -> exports/blackhole/tree_topology/victim_COM26_tree_none_r1_..._telem.csv
```
Via `run.ps1`, pass `-DestAttack blackhole` on the control board instead.

### Wiping a board between runs
Each board appends to the *same* `telem.csv` across reboots (the logger opens in
append mode). Before a fresh run, erase the old data so files don't mix:
```powershell
python export_logs.py --port COM3 --delete   # downloads, then erases
# or, to erase without downloading, send DELETE_LOGS once via any serial terminal
```

### How it works (for reference)
The device frames each file like this on the serial line:
```
READY_TO_SEND
timestamp_us,node_id,role,...        <- header
<data rows>
END_OF_FILE
```
The script captures everything between the markers and filters out any
interleaved ESP-IDF log lines (`I (1234) TAG: ...`) before saving.

## validate_integrity.py

Independent integrity check for whatever's in `exports/` — the M5 "integrity
validation" half (extraction is the half above). No hardware needed.

```powershell
python validate_integrity.py                     # validates ./exports, recursive
python validate_integrity.py exports/blackhole    # a subfolder
python validate_integrity.py --strict             # WARNings also fail (exit 1)
python validate_integrity.py --relock             # accept a changed hash as new baseline
```

Checks schema width, per-phase row counts (truncation detection), timestamp
monotonicity, and SHA-256 checksums against a locked `manifest.json`. See
[`../m5_extraction/README.md`](../m5_extraction/README.md) for the full spec
and [`../../thesis-deviate.md`](../../thesis-deviate.md) for the 2026-07-12
sampling-rate change this tool's phase-count check is calibrated against
(pass `--sample-interval-ms 1000` for captures made before that date).

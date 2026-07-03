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
python export_logs.py --port COM6 --role victim --topology star --attack none --repeat 1

# Just see what's stored on a board, download nothing
python export_logs.py --port COM3 --list
```

Files are written to `tools/exports/` (override with `--outdir`), named like:
```
root_COM3_star_none_r1_20260629_143022_telem.csv
root_COM3_star_none_r1_20260629_143022_arrivals.csv
victim_COM6_star_none_r1_20260629_143105_telem.csv
```
The `--topology`, `--attack`, and `--repeat` flags only affect the filename —
they're the run metadata the milestone asks you to store with each CSV.

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

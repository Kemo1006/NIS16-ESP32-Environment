# tools/ — host-side data extraction

Laptop-side scripts for pulling telemetry CSVs off the ESP32 nodes after a run.
This is the counterpart to the on-device serial-export task in
`components/mesh_common/src/csv_logger.c`.

## The seven tools, in the order you use them

| Tool | What it's for |
|---|---|
| [`board_check.py`](#board_checkpy) | Before anything: is this board fine, what firmware is on it, **is its SPIFFS about to break the export** |
| [`export_logs.py`](#export_logspy) | Pull `telem.csv` / `arrivals.csv` off a board over USB |
| [`recover_spiffs.py`](#recover_spiffspy) | 🆘 When a board can no longer read its own files and `export_logs.py` returns 0 rows |
| [`trim_run.py`](#trim_runpy) | Keep only the experiment run; split concatenated/duplicated captures |
| [`validate_integrity.py`](#validate_integritypy) | Schema, phase coverage, timestamp monotonicity, SHA-256 manifest |
| [`verify_topology.py`](#verify_topologypy) | Rebuild the mesh from `parent_mac`/`layer` and assert the intended shape |
| [`run_matrix.py`](#run_matrixpy) | Track the M4 24-run matrix; `--autorecord` ticks off what's on disk |

> ⚠️ **All of these resolve their default `exports` folder next to the SCRIPT, not
> your shell's current directory.** That was not always true — running one from
> the repo root or from `root_node\` used to create/scan a stray `exports\` there,
> and `export_logs.py` once filed a whole baseline-tree run into
> `root_node\exports\` where no analysis command looks. Explicit paths always win.

---

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
sampling-rate changes this tool's phase-count check is calibrated against.
The default is `100` (10 Hz, current since 2026-07-25); pass `200` for the 5 Hz
baseline/linear capture made earlier that day, or
`--sample-interval-ms 50` for 2026-07-12..07-25 captures (20 Hz) or `1000` for
anything earlier (1 Hz).

> ℹ️ **`*_arrivals.csv` gets its own coverage check.** It is an **event log** — one
> row per probe that actually reached the root — not a periodic sample, so scoring
> it against the telemetry rate is meaningless: it flagged every healthy capture at
> ratio ~0.4 and called the attack phase's 0 rows "possible truncation" when that
> zero is the *deliverable*. Since 2026-07-26 arrivals files instead report the
> measured probe rate per phase and test truncation against **their own baseline
> rate**, so a clean run reads:
>
> ```
> [PASS] root_node1_linear_blackhole_r3_..._arrivals.csv
>     info: phase 0 (baseline): 1436 probes from 4 victim(s) over 360s = 3.98/s (reference rate)
>     info: phase 1 (blackhole): 0 probes reached the root — total drop, the expected attack signature
>     info: phase 3 (cooldown): 483 probes from 4 victim(s) over 120s = 4.01/s (101% of baseline)
> ```
>
> `info:` lines never affect status. It still WARNs on what genuinely matters: a
> missing baseline or cooldown, a cooldown rate that collapsed against this run's
> own baseline, a victim that probed at baseline and never came back, and — the
> one that would otherwise pass silently — **probes still arriving during the
> attack window** above `ATTACK_LEAK_TOLERANCE` (50 % of baseline), meaning the
> drop never took hold.

---

## board_check.py

Is this board dead, blank, or fine — **without erasing anything**. Four checks:
serial port, bootloader (also reads the MAC), flash chip, firmware runtime.

```powershell
python board_check.py --list                     # which COM ports exist
python board_check.py --port COM20               # diagnose that one
python board_check.py --port COM20 --wait 75     # also report firmware variant + SPIFFS
```

It additionally reports **which firmware variant** is flashed (ROOT / PLAIN CHILD /
BLACKHOLE ATTACKER / BLACKHOLE VICTIM / WORMHOLE NODE A / WORMHOLE NODE B) and
**SPIFFS usage**, which is the number that predicts an export failure.

`--wait 75` is needed for the last two: `mesh_setup_init()` blocks up to
`PHASE_STABILISE_S` (60 s) when there is no mesh to join, and both the SPIFFS
banner and the blackhole-victim marker are logged *after* it returns.

Full guide: [`../BOARD-CHECK.md`](../BOARD-CHECK.md).

---

## recover_spiffs.py

🆘 **For when a board can no longer read its own files.** Symptom:

```
[####################] 100.0%  0 B/1.1 MB  0 rows  0 B/s
FAILED: device announced 1.1 MB then sent END_OF_FILE with 0 rows
```

The size is right (`ftell` worked) but nothing streams (`fgets` returned NULL).
That is SPIFFS exhaustion — `esp32-issues` I-017 — and **power-cycling does not
help**, because the fault is in the filesystem, not a stuck handle.

```powershell
python recover_spiffs.py --port COM20 -o exports\<attack>\<topology>\<name>_telem.csv
python recover_spiffs.py --dump saved.bin -o out.csv --kind arrivals
```

esptool reads the raw `spiffs` partition off the flash chip, bypassing the ESP32's
filesystem entirely, and the CSV rows are extracted from the dump.

- **~70 % of rows recover, with zero corrupt rows.** Only byte runs delimited by
  `\n` on *both* sides in the raw flash are accepted; rows straddling SPIFFS page
  metadata are dropped rather than spliced. (Stripping the metadata first and
  splitting on newlines welds the tail of one row onto the head of the next and
  fabricates data that passes validation — measured at 303 invented rows before
  this rule was added.)
- **70 % is enough.** M6 downsamples to a 1 Hz grid, so a 10 Hz stream missing 30 %
  still yields a complete window set (measured: 134 windows kept, 1 discarded).
- Partition offset/size are read from `../partitions.csv`, not hard-coded.

> 🚨 Run this **before** `--delete` / `--wipe` / `-Wipe -Flash`. All three format the
> partition and the data is gone.

---

## trim_run.py

Keeps only the experiment run from an exported CSV. See
[**Trimming exports before analysis**](../LINEAR-RUNBOOK.md#-trimming-exports-before-analysis)
for the full rationale.

```powershell
python trim_run.py exports\baseline\linear_topology              # dry run
python trim_run.py exports\baseline\linear_topology --apply      # -> .../trimmed/
```

Splits on **schema first** (a lost `END_OF_FILE` can concatenate two different
streams, or the same file twice, into one capture), then on **boot sessions**
(timestamp regressions), keeping the longest. Files needing no trimming are
**copied across unchanged**, so `trimmed/` is always the complete analysis input —
check the `files in output : N of N` line.

---

## verify_topology.py

Rebuilds the mesh from each node's `parent_mac` + `layer` and asserts the intended
shape.

```powershell
python verify_topology.py --dir exports\baseline\linear_topology\trimmed `
    --topology linear --attack none --repeat 1 --expect linear
```

> ⚠️ `--topology` defaults to `star`. Without the filters it matches **zero files**
> and exits 2 on every other topology.

Parent/layer changes inside the first `PHASE_STABILISE_S` (60 s) count as mesh
**formation**, not baseline re-routing — they are reported separately, and
`--stabilise-s 0` restores the old all-inclusive behaviour.

---

## run_matrix.py

Tracks the Milestone-4 matrix (4 topologies × 2 attacks × 3 repeats = 24 runs).

```powershell
python run_matrix.py --status         # the grid; warns about unrecorded captures
python run_matrix.py --autorecord     # validate + record everything on disk
python run_matrix.py --next           # what to run next
python run_matrix.py --cmds --topology linear --attack blackhole
```

**Prefer `--autorecord` over `--record`.** `--record` needs `--topology`,
`--attack` and `--repeat` typed correctly; getting `--repeat` wrong silently
re-records the *previous* repeat and leaves a finished capture unticked with no
complaint. `--autorecord` scans, validates and records whatever is complete, and
`--status` now flags captured-but-unrecorded cells on its own.

# Baseline Run — Physical Setup & Step-by-Step Guide

This covers a **baseline-only run**: normal mesh operation, no attack. Ground-truth
label is `0` for the entire run. This is the Milestone 1 behavior
(`ACTIVE_ATTACK = ATTACK_NONE` in `mesh_config.h`).

## Boards needed

| Role   | Firmware file      | Count | Build target  |
|--------|---------------------|-------|----------------|
| Root   | `root_main.c`       | 1     | `root_node/`   |
| Victim | `victim_main.c`     | 1+    | `child_node/` |

Minimum: **2 boards** (1 root + 1 victim). You can add more victim boards —
each one just needs its own COM port and its own repeat of the victim flash/export
steps; they don't interact with each other directly, only with the root.

## Timing (from `mesh_config.h` / `root_main.c` — do not need to guess)

| Phase | Duration | Ground-truth label | What's happening |
|---|---|---|---|
| Stabilize | 60 s | (not logged) | Mesh forms, root waits before starting |
| Baseline | 300 s (5 min) | `0` | Normal traffic, telemetry logged |
| *(no attack phase — skipped)* | — | — | — |
| Cooldown | 120 s (2 min) | `0` | Same as baseline, just a separate phase ID |
| Terminate | instant | — | Boards flush/close CSV, start export listener |

**Total run time: 60 + 300 + 120 = 480 seconds ≈ 8 minutes**, measured from the
moment the ROOT board finishes flashing and reboots.

## Physical placement

No specific topology is required for a baseline run. Any placement that lets the
victim board see the root's WiFi signal works — put them a few meters apart on a
desk, or spread further if you want to test range. Nothing about baseline forces
a particular shape; the mesh self-organizes.

---

## Step 1 — One-time environment setup (skip if already done)

**Open:** the **"ESP-IDF 5.3 PowerShell"** shortcut from your Start Menu — not a
plain PowerShell or cmd window. This is where you will type every command below.

```powershell
cd "C:\Users\Angelo Calpoporo\CLionProjects\NIS16-ESP32-Environment\root_node"
idf.py set-target esp32
cd "..\child_node"
idf.py set-target esp32
```

## Step 2 — Flash the ROOT board

**🔌 Connection state: ROOT board plugged into your laptop via USB. Nothing else
connected yet.**

In the same ESP-IDF PowerShell window:

```powershell
cd "C:\Users\Angelo Calpoporo\CLionProjects\NIS16-ESP32-Environment\root_node"
.\..\run.ps1 -Port COM<root_port> -Role root -Attack none -Wipe -Flash
```

Replace `COM<root_port>` with the actual COM number for this board (check
Device Manager → Ports if unsure). This builds, flashes, and opens a live
serial monitor. Watch for:

```
=== ROOT NODE STARTING ===
...
[CTRL] Waiting 60 s for mesh to stabilise...
```

Once you see that line, **press `Ctrl+]`** to close the monitor. The board
keeps running on its own — closing the monitor window does not stop it.

## Step 3 — Flash the VICTIM board

**🔌 Connection state: VICTIM board plugged into your laptop via USB (root can
stay plugged in too, on its own COM port — doesn't matter either way).**

```powershell
cd "C:\Users\Angelo Calpoporo\CLionProjects\NIS16-ESP32-Environment\child_node"
.\..\run.ps1 -Port COM<victim_port> -Role child  -Attack none -Wipe -Flash
```

Watch for:

```
=== VICTIM NODE STARTING ===
...
Probe generator task running at 1000 ms interval.
Telemetry task running at 50 ms interval.
```

**Press `Ctrl+]`** to close this monitor once it looks normal.

If you have additional victim boards, repeat Step 3 for each one, on its own
COM port.

### Do root and victim run "at the same time"?

Yes, automatically — you don't need to start them in a synchronized way by hand.
Once a board is flashed and powered, its `app_main()` starts running
immediately and independently: the root begins its 60-second stabilize
countdown the moment IT boots, and each victim begins generating probes and
sampling telemetry the moment IT boots. They synchronize themselves over the
wireless mesh — the root broadcasts each phase change (baseline, cooldown,
terminate) and every powered-on victim picks it up within about a second and
tags its own log rows with that phase.

**Recommended order:** flash/power the ROOT first (Step 2), then the VICTIM(s)
(Step 3) within the next minute or so, so all boards have joined the mesh
before the root's 60-second stabilize window ends and baseline logging starts.
It's not a hard requirement — a victim that joins a little late will just have
a few missing seconds at the start — but doing it in this order keeps your
data clean.

## Step 4 — Physical placement (do this now)

**🔋 Connection state: both boards need only power from here on — USB data
connection to your laptop is optional.**

At this point both boards are already running their internal timers/tasks.
You may now:
- Leave both plugged into your laptop's USB ports (simplest, no action
  needed), **or**
- Unplug the data cables and move the boards to their intended physical
  positions, powered by USB power banks or wall chargers instead.

Either way, from this point neither board needs your laptop connected for the
experiment to proceed.

## Step 5 — Wait for the run to complete

**🔋 No laptop connection required. Do not touch, reset, or move either board
during this window — doing so breaks the log.**

Start your own clock now (or note the wall-clock time) — the full run takes
**~8 minutes** from when you finished flashing the root in Step 2. If you left
a monitor window open on either board you'll see the phase banners
(`PHASE 0 — BASELINE`, `PHASE 3 — COOLDOWN`, `PHASE 4 — TERMINATE`) scroll by
in real time; if not, just wait out the 8 minutes.

> **⏩ Recommended — auto-export + auto-analyze in one step.** Instead of the manual
> `export_logs.py` calls in Steps 6–7, add **`-Export`** to each victim's `run.ps1`
> flash command (Step 3) and **`-Analyze`** to the **root's** (Step 2) — and run the
> **root LAST**. On monitor exit (Ctrl+] at *terminate*), each board auto-exports its
> own CSV. `-Analyze` implies `-Export` and additionally runs the whole M6→M8 pipeline
> over the run, so put it **only on the root** and make sure every victim has finished
> exporting **before** you exit the root's monitor — otherwise the analysis runs on
> incomplete data. Example (linear):
> ```powershell
> .\..\run.ps1 -Port COM<victim_port> -Role child  -Attack none -Topology linear -Wipe -Flash -Export
> .\..\run.ps1 -Port COM<root_port>   -Role root   -Attack none -Topology linear -Wipe -Flash -Analyze  # root LAST
> ```
> Copy-paste per-topology blocks are in [`ATTACKS-Commands.md`](ATTACKS-Commands.md).
> The manual commands below stay valid as a fallback (or to re-export one board).
> Replace `<topology>` with the run's topology (`star` | `tree` | `linear` | `partial`).

## Step 6 — Reconnect and export the ROOT board

**🔌 Connection state: ROOT board plugged into your laptop via USB.**

```powershell
cd "C:\Users\Angelo Calpoporo\CLionProjects\NIS16-ESP32-Environment"
python tools\export_logs.py --port COM<root_port> --role root --topology <topology> --attack none --repeat 1
```

This pulls two files from the root: `telem.csv` and `arrivals.csv`.

## Step 7 — Reconnect and export the VICTIM board(s)

**🔌 Connection state: VICTIM board plugged into your laptop via USB.**

```powershell
python tools\export_logs.py --port COM<victim_port> --role child  --topology <topology> --attack none --repeat 1
```

Repeat for every additional victim board, one at a time, on its own COM port.

## Step 8 — Verify

Check `tools\exports\baseline\<topology>_topology\` (e.g. `linear_topology\`) — you should have:
- `<root_id>_..._telem.csv`
- `<root_id>_..._arrivals.csv`
- `<victim_id>_..._telem.csv` (one per victim board)

All non-empty. Row count in each `telem.csv` should be roughly
`480 seconds × 20 samples/sec ≈ 9,600 rows` (firmware currently samples at
20 Hz via `SAMPLING_INTERVAL_MS = 50` in `mesh_config.h` — a documented
deviation from the thesis's stated 1 Hz). Every row's last column
(`gt_label`) should read `0` for the entire file, since this was a baseline
run with no attack phase.

---

## Quick reference — connection state at each step

| Step | What's happening | Laptop connection |
|---|---|---|
| 1–3 | Set target, flash root, flash victim(s) | 🔌 Required (one board at a time) |
| 4 | Physical placement | 🔋 Power only, optional |
| 5 | Waiting ~8 min for the run | 🔋 Power only, optional |
| 6–7 | Export CSVs | 🔌 Required (one board at a time) |
| 8 | Verify files on laptop | — |

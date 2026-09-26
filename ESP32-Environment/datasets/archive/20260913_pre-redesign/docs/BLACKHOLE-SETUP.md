# Blackhole Run — Physical Setup & Step-by-Step Guide

This covers a **blackhole attack run** using the **true relay model** (thesis
§4.2.1.2 C / Milestone 2): victim boards address their probes to the **attacker's
MAC**; the attacker forwards them to the root during baseline/cooldown and
**silently drops** them during the attack window. The root sees the victims'
probes stop arriving during the attack (label `1`) and resume in cooldown.

## Boards needed

| Role                 | Firmware / build                         | Count | Build target   |
|----------------------|-------------------------------------------|-------|-----------------|
| Root                 | `root_main.c` (announces the phase)       | 1     | `root_node/`    |
| Attacker (relay)     | `blackhole_victim.c` (`BLACKHOLE_ROLE=0`) | 1     | `child_node/`  |
| Victim (targets attacker) | `victim_main.c` (`BLACKHOLE_ROLE=1`) | 1+    | `child_node/`  |

**Minimum: 3 boards** (root + attacker + 1 victim). Add more victim boards for a
stronger signature — each extra victim just repeats the victim flash/export steps.

## ⚠️ Before you build: set the attacker's MAC

The victim boards need to know the attacker board's MAC address to send probes to
it. **Do this once, before flashing:**

1. Plug in the board you'll use as the attacker.
2. Read its MAC:
   ```powershell
   .\tools\Get-EspMac.ps1 -Port COM<attacker_port>
   ```
   It prints a `CArray` like `{0xF4, 0x2D, 0xC9, 0x73, 0xE6, 0x18}`.
3. Open `components/mesh_common/include/mesh_config.h`, find `BLACKHOLE_ATTACKER_MAC`,
   and paste that array in:
   ```c
   #define BLACKHOLE_ATTACKER_MAC   {0xF4, 0x2D, 0xC9, 0x73, 0xE6, 0x18}
   ```
4. Save. (The attacker also prints its MAC at boot: `Set BLACKHOLE_ATTACKER_MAC ... to my STA MAC: ...` — use it to double-check.)

If you skip this, the victims will send probes to the wrong/placeholder MAC and
nothing reaches the attacker — the run produces no signature.

## Timing (from `mesh_config.h` / `root_main.c`)

| Phase | Duration | Ground-truth label | What's happening |
|---|---|---|---|
| Stabilize | 60 s | (not logged) | Mesh forms, root waits |
| Baseline | 300 s (5 min) | `0` | Victims → attacker → root (normal relay) |
| **Blackhole attack** | 180 s (3 min) | **`1`** | Attacker drops the victims' probes — they never reach root |
| Cooldown | 120 s (2 min) | `0` | Attacker resumes forwarding |
| Terminate | instant | — | Boards flush/close CSV, start export listener |

**Total run time ≈ 11 minutes** from when the root finishes flashing.

## Physical placement

No specific topology is required for the blackhole signature. Place all boards in
normal WiFi range of each other (a few meters apart on a desk is fine). No cables
between boards — blackhole uses only the wireless mesh (unlike wormhole).

---

## Step 1 — One-time environment setup (skip if already done)

**Open:** the **"ESP-IDF 5.3 PowerShell"** shortcut. Type every command below in
this window (or one window per board — see the note in Step 5).

```powershell
cd "C:\Users\Angelo Calpoporo\CLionProjects\NIS16-ESP32-Environment\root_node"
idf.py set-target esp32
cd "..\child_node"
idf.py set-target esp32
```

Also make sure you've set `BLACKHOLE_ATTACKER_MAC` (see the ⚠️ section above).
Because that edits `mesh_common`, clean-rebuild on the first flash below.

## Step 2 — Flash the ATTACKER board (relay)

**🔌 Attacker board plugged into laptop via USB.**

```powershell
cd "C:\Users\Angelo Calpoporo\CLionProjects\NIS16-ESP32-Environment\child_node"
Remove-Item -Recurse -Force build_* -ErrorAction SilentlyContinue
.\..\run.ps1 -Port COM<attacker_port> -Role child  -Attack blackhole -BlackholeRole attacker -Wipe -Flash
```

Watch for:
```
=== BLACKHOLE ATTACKER (relay) STARTING ===
...
This is the blackhole ATTACKER. Set BLACKHOLE_ATTACKER_MAC ... to my STA MAC: XX:XX:...
Relay task running.
```
Confirm the printed MAC matches what you put in `mesh_config.h`. Press **`Ctrl+]`**.

## Step 3 — Flash the VICTIM board(s)

**🔌 Victim board plugged into laptop via USB.**

```powershell
.\..\run.ps1 -Port COM<victim_port> -Role child  -Attack blackhole -BlackholeRole victim -Wipe -Flash
```

Watch for:
```
=== VICTIM NODE STARTING ===
...
Blackhole victim mode: probes -> attacker XX:XX:...
```
The `-> attacker` line confirms it's targeting the attacker's MAC. Press **`Ctrl+]`**.
Repeat this step for any additional victim boards (each on its own COM port).

## Step 4 — Flash the ROOT board

**🔌 Root board plugged into laptop via USB.**

```powershell
cd "..\root_node"
Remove-Item -Recurse -Force build_* -ErrorAction SilentlyContinue
.\..\run.ps1 -Port COM<root_port> -Role root -Attack blackhole -Wipe -Flash
```

`-Attack blackhole` here just makes the root **announce** `PHASE_ID_BLACKHOLE`
during the attack window (it never drops anything itself). Press **`Ctrl+]`**.

> **Recommended order:** attacker + victims first, root LAST — so every board has
> joined the mesh before the root's 60-second stabilize window ends.

### Do all boards run "at the same time"?

Yes — each board runs its own tasks independently once powered, and the root's
wireless phase broadcasts keep every board's ground-truth label in sync. You do
not synchronize them by hand.

## Step 5 — Physical placement + wait

**🔋 Power only from here on — laptop connection optional. Do not touch the boards.**

Full run ≈ **11 minutes**. On the attacker's console (if monitored) you'll see
`BLACKHOLE: dropped victim probe seq=...` lines appear exactly when the attack
phase starts and stop when cooldown begins.

> **Flashing multiple identical victims:** each `run.ps1` now uses a per-COM-port
> build directory, so you *can* flash several victim boards from separate windows
> in parallel. But flashing one at a time is still simplest.

## Step 6 — Export every board

> **⏩ Recommended — auto-export + auto-analyze in one step.** Instead of the manual
> `export_logs.py` calls below, add **`-Export`** to each board's `run.ps1` flash
> command (Steps 2–4) and **`-Analyze`** to the **root's** — and run the **root
> LAST**. When you exit each monitor (Ctrl+] at *terminate*), that board auto-exports
> its own CSV into the right folder. `-Analyze` implies `-Export` and additionally
> runs the whole M6→M8 pipeline over the run, so put it **only on the root** and make
> sure every other board has finished exporting **before** you exit the root's
> monitor — otherwise the analysis runs on incomplete data. Example (linear):
> ```powershell
> .\..\run.ps1 -Port COM<victim_port>   -Role child  -Attack blackhole -BlackholeRole victim   -Topology linear -Wipe -Flash -Export
> .\..\run.ps1 -Port COM<attacker_port> -Role child  -Attack blackhole -BlackholeRole attacker -Topology linear -Wipe -Flash -Export
> .\..\run.ps1 -Port COM<root_port>     -Role root   -Attack blackhole                          -Topology linear -Wipe -Flash -Analyze  # root LAST
> ```
> Copy-paste per-topology blocks are in [`ATTACKS-Commands.md`](ATTACKS-Commands.md).
> The manual commands below stay valid as a fallback (or to re-export one board).

**🔌 One board at a time, plugged into laptop.** Replace `<topology>` with the run's
topology (`star` | `tree` | `linear` | `partial`) so files land in the matching folder.

```powershell
cd "C:\Users\Angelo Calpoporo\CLionProjects\NIS16-ESP32-Environment"
python tools\export_logs.py --port COM<root_port>     --role root   --topology <topology> --attack blackhole --repeat 1
python tools\export_logs.py --port COM<attacker_port> --role child  --topology <topology> --attack blackhole --repeat 1
python tools\export_logs.py --port COM<victim_port>   --role child  --topology <topology> --attack blackhole --repeat 1
```

## Step 7 — Verify the attack signature

Files land in `tools\exports\blackhole\<topology>_topology\` (e.g. `linear_topology\`). Confirm:
- **Root `arrivals.csv`:** for each victim's `src_mac`, arrivals are present during
  `gt_label=0` rows and **absent (a gap) during `gt_label=1` rows**, resuming at
  cooldown. That gap is the blackhole signature.
- **Attacker `telem.csv`:** the `tx_count` column (probes forwarded) climbs during
  baseline/cooldown and **goes flat during `gt_label=1`**, while `retry_count`
  (probes dropped) **climbs during `gt_label=1`**. `probes_count` (received from
  victims) climbs throughout.
- **Victim `telem.csv`:** `probes_count` climbs steadily the whole run (the victim
  keeps sending; it doesn't know they're being dropped).

---

## Quick reference — connection state at each step

| Step | What's happening | Laptop connection |
|---|---|---|
| Pre | Read attacker MAC, set BLACKHOLE_ATTACKER_MAC | 🔌 Required (attacker) |
| 1–4 | Set target, flash attacker / victims / root | 🔌 Required (one board at a time) |
| 5 | Placement + waiting ~11 min | 🔋 Power only, optional |
| 6 | Export CSVs | 🔌 Required (one board at a time) |
| 7 | Verify files + confirm signature | — |

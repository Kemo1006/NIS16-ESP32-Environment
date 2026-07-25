# Wormhole Run — Physical Setup & Step-by-Step Guide

This covers a **wormhole attack run**: two colluding attacker boards (Node A,
Node B) tunnel probes between each other over a **physical wired UART cable**
— separate from the wireless mesh and separate from your laptop's USB
connection — creating a fake "shortcut" that makes the root see duplicate,
suspiciously-fast probe arrivals during the attack window. Ground-truth label
switches from `0` (baseline) → `2` (wormhole) → `0` (cooldown) automatically.

This matches your Milestone 2 form's requirement ("a wired UART link between A
and B acts as the out-of-band tunnel... CRC-protected to detect errors") —
see `child_node/main/wormhole_victim.c` and the `WORMHOLE_UART_*` settings in
`components/mesh_common/include/mesh_config.h`.

## Boards needed

| Role                     | Firmware file        | Count | Build target   |
|---------------------------|------------------------|-------|-----------------|
| Root                      | `root_main.c`         | 1     | `root_node/`    |
| Node A (exit / root-side) | `wormhole_victim.c` (`WORMHOLE_END=0`) | 1 | `child_node/` |
| Node B (entry / leaf-side)| `wormhole_victim.c` (`WORMHOLE_END=1`) | 1 | `child_node/` |

**Minimum: 3 boards**, plus a **UART jumper cable between Node A and Node B**
(3 wires — see wiring section below).

## Timing (from `mesh_config.h` / `root_main.c` — same schedule as blackhole)

| Phase | Duration | Ground-truth label | What's happening |
|---|---|---|---|
| Stabilize | 60 s | (not logged) | Mesh forms, root waits |
| Baseline | 300 s (5 min) | `0` | Node B sends its probes straight to root, like a normal victim |
| **Wormhole attack** | 180 s (3 min) | **`2`** | Node B forwards each probe to root normally AND tunnels a copy to Node A over UART; Node A re-injects it, so the root gets the same probe TWICE (duplicate + latency mismatch) |
| Cooldown | 120 s (2 min) | `0` | Node B stops tunnelling; only the normal single copy reaches root |
| Terminate | instant | — | Boards flush/close CSV, start export listener |

**Total run time: 60 + 300 + 180 + 120 = 660 seconds ≈ 11 minutes.**

## Physical placement — read this before wiring

- **Node A and Node B must be physically close enough for a UART cable to
  directly connect them** — typically within arm's reach on the same desk,
  unless you're using an unusually long cable. This is a hard constraint of
  the wired-tunnel design; it's the whole point (an out-of-band shortcut only
  works if it's genuinely a shortcut).
- **Root can be positioned separately** — near Node A (its "exit" side) is
  the setup this milestone describes, but for a first functional test it's
  fine to have all three boards on the same desk.
- The wireless mesh connection (Node A ↔ Root ↔ Node B, or however they
  self-organize) is completely independent of the UART wire — WiFi range
  rules still apply normally for that part.

---

## Step 1 — One-time environment setup (skip if already done)

**Open:** the **"ESP-IDF 5.3 PowerShell"** shortcut. Type every command below
in this window.

```powershell
cd "C:\Users\Angelo Calpoporo\CLionProjects\NIS16-ESP32-Environment\root_node"
idf.py set-target esp32
cd "..\child_node"
idf.py set-target esp32
```

## Step 2 — Wire Node A and Node B together (do this BEFORE powering them on)

**🔌 No laptop involved in this step — this is a separate physical cable
between the two attacker boards only.**

Using jumper wires, connect Node A and Node B's GPIO pins **crossed**, plus a
shared ground:

| Node A pin | Wire to | Node B pin |
|---|---|---|
| GPIO 17 (TX) | ──────────► | GPIO 16 (RX) |
| GPIO 16 (RX) | ◄────────── | GPIO 17 (TX) |
| GND | ──────────── | GND |

That's 3 wires total. TX always goes to the other board's RX (crossed, not
straight-through) — this is standard UART wiring. Do **not** connect this
cable to your laptop; it only ever runs between the two ESP32 boards.

> ⚠️ If your boards are **WROVER modules with PSRAM**, GPIO16/17 are used
> internally by the PSRAM chip and are NOT safe to use here. Check
> `components/mesh_common/include/mesh_config.h` (`WORMHOLE_UART_TX_PIN` /
> `WORMHOLE_UART_RX_PIN`), change both to a free GPIO pair (e.g. 4 and 5), and
> rebuild before wiring, matching whatever pins you set.

## Step 2b — VERIFY the wire before you commit to a run (strongly recommended)

A wrong tunnel wire (missing GND, or straight-through instead of crossed) makes
the tunnel **silently deliver nothing** — you'd only find out after a full
11-minute run + export. Catch it in seconds with the standalone loopback test:

```powershell
cd "C:\Users\Angelo Calpoporo\CLionProjects\NIS16-ESP32-Environment\uart_link_test"
idf.py set-target esp32          # once
idf.py -p <nodeA_port> flash monitor   # press Ctrl+] at the banner
idf.py -p <nodeB_port> flash monitor   # WATCH this one
```

- `[LINK OK]` on the watched board → wire is good, re-flash the real wormhole
  firmware (Steps 3–5) and continue.
- `RX received=0` (stays 0) → wire is broken; fix GND / the crossing and retry.

Full details: [`uart_link_test/README.md`](uart_link_test/README.md).

## Step 3 — Flash the ROOT board

**🔌 Connection state: ROOT board plugged into your laptop via USB. The A↔B
UART cable from Step 2 is unrelated to this and stays as-is.**

```powershell
cd "C:\Users\Angelo Calpoporo\CLionProjects\NIS16-ESP32-Environment\root_node"
.\..\run.ps1 -Port COM<root_port> -Role root -Attack wormhole -Wipe -Flash
```

`-Attack wormhole` builds with `-DACTIVE_ATTACK=2` — the root announces
`PHASE_ID_WORMHOLE` during the attack window; it doesn't run any attacker
logic itself. Watch for:
```
=== ROOT NODE STARTING ===
...
[CTRL] Waiting 60 s for mesh to stabilise...
```
**Press `Ctrl+]`** once you see that line.

## Step 4 — Flash Node A

**🔌 Connection state: Node A plugged into your laptop via USB (the UART
jumper wires to Node B stay connected the whole time — that's a separate
connection from the USB cable).**

```powershell
cd "C:\Users\Angelo Calpoporo\CLionProjects\NIS16-ESP32-Environment\child_node"
.\..\run.ps1 -Port COM<nodeA_port> -Role child  -Attack wormhole -WormholeEnd A -Wipe -Flash
```

Watch for:
```
=== WORMHOLE NODE A (exit) STARTING ===
...
Wormhole UART tunnel ready: UART1  TX=GPIO17  RX=GPIO16  115200 baud
...
UART tunnel receiver running.
```
**Press `Ctrl+]`** once it looks normal.

## Step 5 — Flash Node B

**🔌 Connection state: Node B plugged into your laptop via USB (UART wires to
Node A stay connected).**

```powershell
.\..\run.ps1 -Port COM<nodeB_port> -Role child  -Attack wormhole -WormholeEnd B -Wipe -Flash
```

Watch for:
```
=== WORMHOLE NODE B (entry) STARTING ===
...
Wormhole UART tunnel ready: UART1  TX=GPIO17  RX=GPIO16  115200 baud
...
Probe generator running at 1000 ms interval.
Tunnel forwarder running.
```
**Press `Ctrl+]`** once it looks normal.

**⚠️ All three boards must be flashed with `-Attack wormhole` (`-DACTIVE_ATTACK=2`),
and the two attacker boards must take opposite `-WormholeEnd` values (one `A`,
one `B`).** Two boards both set to the same end, or a missing `-WormholeEnd`
on one side, means the tunnel never completes.

### Do root, Node A, and Node B run "at the same time"?

Yes — same principle as baseline/blackhole. Each board's firmware starts
running independently the moment it boots; the root's wireless phase
broadcasts keep all three synchronized on ground-truth label. The UART link
between A and B is separate from this synchronization mechanism — it's only
used to carry tunneled probe data during the attack phase itself, not phase
timing. **Recommended order:** flash/power the root first, then A and B
within about a minute, so all three are joined to the mesh before the
60-second stabilize window ends.

## Step 6 — Physical placement

**🔋 Connection state: all three boards need only power from here on. Keep
the A↔B UART cable connected — it must stay wired for the entire run,
including baseline and cooldown, not just the attack window.**

You can leave all three plugged into your laptop, or move them to their
physical positions on power banks/wall power — just don't disconnect the
UART jumper wires between A and B when you do.

## Step 7 — Wait for the run to complete

**🔋 No laptop connection required. Do not touch any board or the UART cable
during this window.**

Full run takes **~11 minutes** from when you finished flashing the root in
Step 3. If monitors are open, you'll see on Node B's console during the
attack phase:
```
Tunnelled probe seq=... -> Node A via UART
```
and on Node A's console:
```
UART tunnel receiver running.
Re-injected probe src=... seq=...
```
appearing exactly when the wormhole phase starts, and stopping when cooldown
begins.

> **⏩ Recommended — auto-export + auto-analyze in one step.** Instead of the manual
> `export_logs.py` calls in Steps 8–10, add **`-Export`** to each board's `run.ps1`
> flash command (Steps 3–5) and **`-Analyze`** to the **root's** — and run the **root
> LAST**. On monitor exit (Ctrl+] at *terminate*), each board auto-exports its own CSV.
> `-Analyze` implies `-Export` and additionally runs the whole M6→M8 pipeline over the
> run, so put it **only on the root** and make sure Node A and Node B have finished
> exporting **before** you exit the root's monitor — otherwise the analysis runs on
> incomplete data. Example (linear):
> ```powershell
> .\..\run.ps1 -Port COM<nodeA_port> -Role child  -Attack wormhole -WormholeEnd A -Topology linear -Wipe -Flash -Export
> .\..\run.ps1 -Port COM<nodeB_port> -Role child  -Attack wormhole -WormholeEnd B -Topology linear -Wipe -Flash -Export
> .\..\run.ps1 -Port COM<root_port>  -Role root   -Attack wormhole                 -Topology linear -Wipe -Flash -Analyze  # root LAST
> ```
> Copy-paste per-topology blocks are in [`ATTACKS-Commands.md`](ATTACKS-Commands.md).
> The manual commands below stay valid as a fallback (or to re-export one board).
> Replace `<topology>` with the run's topology (`star` | `tree` | `linear` | `partial`).

## Step 8 — Reconnect and export ROOT

**🔌 Connection state: ROOT board plugged into your laptop via USB.**

```powershell
cd "C:\Users\Angelo Calpoporo\CLionProjects\NIS16-ESP32-Environment"
python tools\export_logs.py --port COM<root_port> --role root --topology <topology> --attack wormhole --repeat 1
```

## Step 9 — Reconnect and export Node A

**🔌 Connection state: Node A plugged into your laptop via USB.**

```powershell
python tools\export_logs.py --port COM<nodeA_port> --role child  --topology <topology> --attack wormhole --repeat 1
```

## Step 10 — Reconnect and export Node B

**🔌 Connection state: Node B plugged into your laptop via USB.**

```powershell
python tools\export_logs.py --port COM<nodeB_port> --role child  --topology <topology> --attack wormhole --repeat 1
```

## Step 11 — Verify

Check `tools\exports\wormhole\<topology>_topology\` (e.g. `linear_topology\`) for:
- `<root_id>_..._telem.csv`
- `<root_id>_..._arrivals.csv`
- `<nodeA_id>_..._telem.csv`
- `<nodeB_id>_..._telem.csv`

All non-empty, ~660 s × 10 Hz ≈ 6,600 rows in each `telem.csv` (captures from
2026-07-12..07-25 ran at 20 Hz and hold ~13,200 instead). Confirm the
attack signature yourself:
- **In the root's `arrivals.csv` — the DUPLICATE signature:** during rows labeled
  `gt_label=2`, each of Node B's probes appears **TWICE** — two rows with the
  **same `src_mac` and same `seq_num`** but **different `latency_us`** (the normal
  mesh copy vs. the slower tunnel copy) and different `timestamp_us`. During
  `gt_label=0` rows each `seq_num` appears only **once**. That doubling +
  latency mismatch is the wormhole signature (Milestone 2).
- In Node B's `telem.csv`, the `retry_count` column (the "probes tunneled"
  counter — see the header comment in `wormhole_victim.c`) should climb only
  during `gt_label=2` rows, while `tx_count` (probes forwarded to root normally)
  climbs the whole run.
- In Node A's `telem.csv`, `probes_count` (tunneled-probes-received counter)
  and `tx_count` (re-injected-to-root counter) should both climb only during
  `gt_label=2` rows, and stay at 0 elsewhere.
- If either board logged `UART tunnel: bad magic` or `CRC mismatch` warnings
  during the run (check if you kept a monitor open), check your wiring —
  those mean corrupted or missing bytes on the UART link, usually a loose
  jumper or crossed-wrong TX/RX.

---

## Quick reference — connection state at each step

| Step | What's happening | Laptop connection | UART cable (A↔B) |
|---|---|---|---|
| 2 | Wire Node A ↔ Node B | Not involved | Connect now |
| 3–5 | Set target, flash root, A, B | 🔌 Required (one board at a time) | Stays connected |
| 6 | Physical placement | 🔋 Power only, optional | Stays connected |
| 7 | Waiting ~11 min for the run | 🔋 Power only, optional | Stays connected |
| 8–10 | Export CSVs | 🔌 Required (one board at a time) | Stays connected |
| 11 | Verify files + confirm attack signature | — | — |

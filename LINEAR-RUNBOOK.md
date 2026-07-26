# 🧵 LINEAR Topology — Full Runbook (Baseline · Blackhole · Wormhole)

> **What this file is:** one place that walks you through **all three runs** for the
> **linear** topology — with the **same physical placement** every time. You set up the
> boards **once**, then for each run you only **change the commands**. Start with
> Baseline, then Blackhole, then Wormhole.
>
> Companion flat command lists live in [`ATTACKS-Commands.md`](ATTACKS-Commands.md).
> The per-attack deep dives are [`BASELINE-SETUP.md`](BASELINE-SETUP.md),
> [`BLACKHOLE-SETUP.md`](BLACKHOLE-SETUP.md), [`WORMHOLE-SETUP.md`](WORMHOLE-SETUP.md).
>
> 🧩 **6 boards total:** 1 root (COM20) + 5 children (COM26, COM27, COM25, COM21, **COM22**).
>
> 🎯 **Milestone 4 (M4) applies here:** each ATTACK (blackhole + wormhole) must be captured
> **3 times** (r1, r2, r3) to count toward the 24-run matrix. Baseline is the control (not
> in the 24). Read the **🎯 M4 section** below before you start.

---

---

## 🔌 USB port convention — READ FIRST

**One port for everything: `COM20`. You never edit `-Port` again.**

A COM number here identifies the **USB SOCKET, not the board** — these CP210x bridges report
duplicate/blank serials, so Windows assigns COM per socket. Verified on this machine: any
board plugged into the laptop socket enumerates as **COM20**, root or child alike.

### 🚨 The one rule: ONE BOARD PLUGGED IN AT A TIME

Because every board claims COM20, **two boards connected at once = only one enumerates**, and
the other silently "doesn't exist" (`FileNotFoundError: could not open COM26/COM20`). So:

| Phase | What is plugged into the laptop |
|---|---|
| **2. Flash children** | one child at a time — root NOT connected |
| **4. Boot root** | the root only — it must stay connected for **power** all run |
| **5. Watch to `terminate`** | still the root only |
| **6. Export children** | 🔌 **unplug the root FIRST**, then one child at a time |
| **7. Export root** | plug the root back in, alone |

> ✅ Unplugging the root after `terminate` is safe — the run is over and its CSVs are closed
> on SPIFFS. (This is why the **manual** export route matters: with `-Analyze` the root had to
> stay connected and exit last, which is impossible when everything shares one port.)

### 🏷️ Boards are identified by `-Label`, not by COM

Since the port never changes, **`-Label nodeN` is the only thing telling you which physical
board to plug in.** It is echoed on start (`Board: node5 (on COM20)`) and passed to
`export_logs.py` as `--label`, so the CSV is named `child_node5_..._telem.csv`.

| Node | Board | Role |
|---|---|---|
| `node1` | root board | **ROOT** |
| `node2` | | child |
| `node3` | | child |
| `node4` | | child |
| `node5` | | **blackhole ATTACKER** / wormhole Node A |
| `node6` | | wormhole Node B |

The placement diagrams and role tables below still name boards by their **old** COM numbers
(COM20→node1, COM21→node2, COM22→node3, COM25→node4, COM26→node5, COM27→node6). Read them
through this table.

### ✅ Before every flash or export

```powershell
cd tools
python board_check.py --list          # is a port actually there?
python board_check.py --port COM20    # which board is it? (reads the MAC)
```

> ⚠️ **A charge-only USB cable powers the board but creates NO COM port.** It will boot, join
> the mesh and look perfectly alive while being invisible to the laptop. If `--list` shows
> nothing, swap the cable before anything else — keep data cables for the laptop and
> charge-only cables for the power banks.
---

## 📍 THE PLACEMENT — mapped to your 2nd-floor plan (set up once, all three runs)

Linear = a **chain**. Each board only needs to "hear" the **next board in line**, and the
mesh passes messages hop-by-hop back to the root. On your floor plan, root lives in
**Bedroom 2** (your laptop), and the chain snakes out through Bedroom 1 → Family Hall →
Master's Bedroom:

```
        ⬆ NORTH (top of your floor plan)
 ┌─────────────────────┬─────────────────────┐
 │     BEDROOM 1       │     BEDROOM 2        │
 │   COM26  +  COM27   │   COM20  ◄── ROOT    │
 │  (A/attacker + B)   │      (your laptop)   │
 ├─────────────────────┴──────┬──────────────┤
 │                            │  WC / shower │
 │     FAMILY HALL            ├──────────────┤
 │   COM25  +  COM22          │   MASTER'S   │
 │                            │   BEDROOM    │
 │                            │    COM21     │
 └────────────────────────────┴──────────────┘
        ⬇ SOUTH

 Chain order:  ROOT ──► COM26 ──► COM27 ──► COM25 ──► COM22 ──► COM21
               Bed 2   └── Bedroom 1 ──┘   └─ Family Hall ─┘   Master's
```

Which board goes where, and why:
- **Bedroom 2 — COM20 (root)** sits with you on the laptop. This is the head of the chain.
- **Bedroom 1 — COM26 + COM27** (the room next to root). COM26 is a **plain child in
  Baseline**, the **attacker in Blackhole**, and **Node A in Wormhole**; COM27 is its
  partner. They live **in the same room** because the **wormhole run needs a short cable
  between exactly these two** (Run C) — keeping them together means the *same placement*
  works for all three runs.
- **Family Hall — COM25 + COM22** (the central room). Middle of the chain.
- **Master's Bedroom — COM21** (the farthest room). Tail of the chain.

### 🎭 Who plays what in each run (same boards, different roles)
The physical placement never changes — only each board's **job** does, set by the commands:

| Board | Room | Baseline | Blackhole | Wormhole |
|---|---|---|---|---|
| **COM20** | Bedroom 2 | root | root (announces phase) | root (announces phase) |
| **COM26** | Bedroom 1 | **plain child (victim)** | **attacker** (relay/drops) | Node A (exit) |
| **COM27** | Bedroom 1 | **plain child (victim)** | **victim** (sends to attacker) | Node B (entry) |
| **COM25** | Family Hall | plain child (victim) | victim | plain control |
| **COM22** | Family Hall | plain child (victim) | victim | plain control |
| **COM21** | Master's Bedroom | plain child (victim) | victim | plain control |

> ✅ **Baseline = NO attacker.** COM26 and COM27 (and everyone else) are all just plain
> children — nobody drops or tunnels anything. The attacker role *only* exists in the
> Blackhole run, where **COM26 is the attacker and COM27/COM25/COM22/COM21 are victims**.

### 🔑 Placement rules (make or break the run)
- ✅ **Every board must "hear" its neighbour.** If a board won't join later, **move it
  closer** to the one before it (e.g. Master's COM21 toward the Family-Hall doorway). A
  chain is only as strong as its weakest gap.
- ✅ **Don't strand a board.** A board that can't hear *any* other board never joins and
  records nothing — Master's Bedroom (COM21) is the one most at risk since it's farthest.
- ✅ **Tape the boards in place.** You'll do 3 runs on this layout — keep it **identical**
  so the only thing changing is the attack, not the geometry.
- ⚠️ **Radio channel:** the mesh uses **channel 11**. If runs keep dropping / you see lots
  of `ROOT LOST` in the root monitor, your home router may be on channel 11 too — change
  `MESH_CHANNEL` in `components/mesh_common/include/mesh_config.h` to **1** or **6** (pick
  the one your router isn't using) and re-flash all boards.

> 🧵 **Heads-up — linear is the twitchiest topology.** A long chain across rooms is more
> likely to wobble (`ROOT LOST`, re-parenting) than a compact tree. If the root monitor
> shows a lot of that, nudge each board a little **closer** to its neighbour and re-run.
> Steady chain = clean data.

---

## 🔁 The reusable workflow (same 6 phases every run)

Every run — baseline, blackhole, wormhole — follows the exact same rhythm. Only the
**commands in Phase 2** and the **export folder in Phase 6** change.

Always work from the repo root:
```powershell
cd "C:\Users\Angelo Calpoporo\CLionProjects\NIS16-ESP32-Environment"
```

| Phase | What you do | Laptop? |
|---|---|---|
| **1. Prep** | (once ever) set target; (wormhole only) wire + test the A↔B cable | 🔌 |
| **2. Flash children** | plug in each child, flash it, `Ctrl+]`, unplug — **one at a time** | 🔌 |
| **3. Place & power** | put the 5 children in their rooms, power from banks, let mesh form | 🔋 |
| **4. Boot root LAST** | flash the root on the laptop → the clock starts → **leave monitor open** | 🔌 |
| **5. Watch & wait** | watch the scenes roll by (~8 or ~11 min); don't touch anything | 🔋 |
| **6. Export** | plug each board back in, one at a time, pull its CSV | 🔌 |

### ⚡ AUTO-ANALYZE ON THE ROOT — the sequence that saves you the manual analysis
**You export and analyze BY HAND.** The Phase 4 root command carries **no `-Analyze`**, so
nothing fires automatically. The children are on power banks and come to the laptop one at a
time; the root is already there. The sequence:

1. 🎬 Boot the root **last** (attacks also add `-Repeat <N>`).
2. 👀 Watch the root monitor to **`terminate`**, then press **`Ctrl+]`** — it just closes the
   monitor and prints `Monitor closed - run only (no export). Data is safe on the board's SPIFFS.`
3. 🔌 Bring each of the **5 children** to the laptop and export them over USB
   (`export_logs.py … --repeat <N>`), one at a time.
4. 🔌 Export the **root** — `--role root` pulls `telem` **and** `arrivals` in one command.
5. 🔍 **Confirm all 7 files are in the folder**, THEN run M6→M7→M8 →
   `analysis/<attack>/<topology>_topology/{windowed_dataset.csv, feature_table.csv, eda_output/}`.
6. ✅ Record it (M4): `run_matrix.py --record …`.

> ✅ **Why by hand?** `-Analyze` fires the instant you press `Ctrl+]` and runs over whatever
> CSVs happen to be in the folder **at that moment** — a dead monitor, a failed child export,
> or an early `Ctrl+]` silently yields an analysis of an *incomplete* run, and it reports
> 0% discarded either way. Doing it manually means the root's exit is **no longer
> order-critical**, and you verify the folder before anything is computed from it.

> 📖 Full copy-paste commands: [**Manual route without auto analyze**](#-manual-route-without-auto-analyze).

---

## 🎯 M4 — run each ATTACK three times (the 24-run matrix)

Milestone 4 (*Phase-Controlled Experiment Execution*, 15%) needs **24 runs =
4 topologies × 2 attacks × 3 repeats**. For *this* file (linear) that's **6 graded runs**:

| Cell | Runs you owe |
|---|---|
| `linear · blackhole` | r1, r2, r3 |
| `linear · wormhole`  | r1, r2, r3 |

Plus **baseline · linear** once, as the control reference (baseline is **not** in the 24).

**A "repeat" = the whole capture done again on cleared boards.** Each RUN below is **ONE**
repeat. To do the next one you change **one number** — the `--repeat` in the export + record
commands (`1` → `2` → `3`).

> 🔁 **You do NOT restart at Phase 1, and you usually don't re-flash the children either** —
> but their logs **must** be cleared or r1 and r2 fuse into one file. Read
> [**Doing repeat 2 and 3**](#-doing-repeat-2-and-3) before starting r2. It's the single
> easiest thing to get silently wrong.

> 🧊 **Do NOT archive between repeats.** r1/r2/r3 are *meant* to pile up in the same
> `exports/<attack>/linear_topology/` folder (each gets its own `_r1_`/`_r2_`/`_r3_` tag) —
> that's how the matrix counts 3 repeats. Only archive (see [`ARCHIVE-RUNBOOK.md`](ARCHIVE-RUNBOOK.md))
> when you're **throwing a bad run away**.

**Check progress any time:**
```powershell
python tools\run_matrix.py --status     # the 24-cell grid (done vs pending)
python tools\run_matrix.py --next       # what to run next
```
After each attack repeat is exported, **mark it done** — `--record` re-validates the CSVs
first and only ticks the box if they pass:
```powershell
python tools\run_matrix.py --record --topology linear --attack blackhole --repeat 1
```

> ✅ **Easier and safer: `--autorecord`.** It scans `exports/` for captures that are
> complete but not yet ticked off, validates each, and records them — so you never
> type `--topology` / `--attack` / `--repeat` again. Getting that last flag wrong
> silently re-records the PREVIOUS repeat and leaves the matrix unchanged with good
> data sitting on disk (this happened on 2026-07-26):
>
> ```powershell
> python tools\run_matrix.py --autorecord
> ```
>
> `--status` also warns on its own now if it spots captured-but-unrecorded cells.

---

## 🛠️ Manual route without auto analyze

> 📌 **Shared reference** — the tree/star/partial runbooks link here. Swap `linear_topology`
> for `tree_topology` / `star_topology` / `partial_mesh_topology` as needed.

Dropping `-Analyze` decouples the analysis from the root monitor. **Nothing is lost** — the
root still records normally; you just pull and analyze by hand afterwards.

**Why you might prefer this:** with `-Analyze`, the analysis fires the instant you press
`Ctrl+]` and runs over **whatever CSVs happen to be in the folder at that moment**. If the
monitor dies, or a child export failed, or you hit `Ctrl+]` early, you silently get an
analysis of an incomplete run. Manual means you look at the folder first, then analyze.

### Phase 4 — boot the root (manual variant)

Just drop `-Analyze` (attack runs keep `-Repeat <N>` — it still names the root's CSV):

```powershell
# baseline
.\run.ps1 -Port COM20 -Role root -Label node1 -Topology linear -Wipe -Flash
# blackhole
.\run.ps1 -Port COM20 -Role root -Label node1 -Attack blackhole -Topology linear -Wipe -Flash -Repeat 1
# wormhole
.\run.ps1 -Port COM20 -Role root -Label node1 -Attack wormhole  -Topology linear -Wipe -Flash -Repeat 1
```

Watch to `terminate` exactly as before.

### Phase 7 — `Ctrl+]`, then export the root by hand

With no `-Analyze` and no `-Export`, `Ctrl+]` just closes the monitor and prints
`Monitor closed - run only (no export). Data is safe on the board's SPIFFS.`

**The root's `Ctrl+]` is no longer special — it doesn't have to be last.** Export the root
whenever you like; `--role root` pulls **both** `telem` *and* `arrivals`:

```powershell
cd tools
python export_logs.py --port COM20 --role root --label node1 --topology linear --attack none --repeat 1
cd ..
```

> 💡 The root is the busiest node and pulls two files — export it with the other boards
> powered **off**, or it may not answer. See the troubleshooting table.

### Phase 7b — check the folder BEFORE analyzing

This is the step `-Analyze` skips, and the whole reason to go manual:

```powershell
Get-ChildItem tools\exports\baseline\linear_topology
python tools\trim_run.py tools\exports\baseline\linear_topology             # dry run: lists boot sessions
python tools\trim_run.py tools\exports\baseline\linear_topology --apply     # -> ...\linear_topology\trimmed\ (raw untouched)
(Get-ChildItem tools\exports\baseline\linear_topology\trimmed\*.csv).Count   # MUST be 7 — a short count silently NaNs out PDR/latency
Get-Content tools\exports\baseline\linear_topology\trimmed\*_arrivals.csv -TotalCount 1   # MUST list src_mac,seq_num
```

You want **6 boards present** — 5 child `_telem.csv` plus the root's `_telem.csv` *and*
`_arrivals.csv` (7 files). Each in the hundreds of KB. Anything missing → re-export it now,
before the analysis bakes an incomplete run into your feature table.

### Phase 7c — run M6 → M7 → M8 by hand

Identical to what `-Analyze` runs internally (`run.ps1:399, 408, 419`), just typed out:

```powershell
cd analysis
python preprocess.py ..\tools\exports\baseline\linear_topology\trimmed -o baseline\linear_topology\windowed_dataset.csv
python features.py   ..\tools\exports\baseline\linear_topology\trimmed -o baseline\linear_topology\feature_table.csv
python eda.py        baseline\linear_topology\feature_table.csv -o baseline\linear_topology\eda_output
cd ..
```

For an attack run swap **both** `baseline` → `blackhole` (or `wormhole`):

```powershell
cd analysis
python preprocess.py ..\tools\exports\blackhole\linear_topology\trimmed -o blackhole\linear_topology\windowed_dataset.csv
python features.py   ..\tools\exports\blackhole\linear_topology\trimmed -o blackhole\linear_topology\feature_table.csv
python eda.py        blackhole\linear_topology\feature_table.csv -o blackhole\linear_topology\eda_output
cd ..
```

> ⚠️ **`python` must be the one with the analysis deps** (pandas, numpy, matplotlib, seaborn,
> scipy, scikit-learn). The ESP-IDF shell's python often lacks them — `run.ps1` scans for a
> working interpreter, but typing the commands by hand does not. If you get
> `ModuleNotFoundError`, run `pip install -r analysis\requirements.txt`, or use your full
> CPython explicitly (e.g. `C:\Python314\python.exe preprocess.py …`).

**Re-runnable any time.** All three steps only read `tools\exports\…` and overwrite their
outputs — so if you spot a missing board later, re-export it and just run these again.

### ✅ Then verify + record as usual

```powershell
cd tools; python validate_integrity.py exports\baseline\linear_topology\trimmed; python verify_topology.py --dir exports\baseline\linear_topology\trimmed --topology linear --attack none --repeat 1 --expect linear; cd ..
```

---

## 🔌 COM ports, boards, and `--label`

> 📌 **Shared reference** — the tree/star/partial runbooks link here.

### ⚠️ A COM number identifies the USB SOCKET, not the board

These CP210x bridges report **duplicate or blank USB serial numbers**, so Windows cannot
tell the six boards apart. It falls back to assigning COM numbers by **USB socket**, and
Device Manager ends up showing the same COM claimed by several device instances
(COM20 ×4, COM21 ×4, COM26 ×3 … on this machine).

Consequences you have to live with:

- **Move a board to a different socket → its COM changes.**
- **Plug a different board into the same socket → same COM.**
- A COM number in a filename tells you *which socket you used*, not which board.

> 🚫 This is why there is **no `-Node <n>` flag** on `run.ps1`. A fixed node→COM table was
> tried on 2026-07-25 and reverted: with socket-bound COM numbers it would eventually flash
> the **wrong board**. Use `-Port COMxx` and confirm the port first.

**Always check what is actually connected before flashing or exporting:**

```powershell
cd tools
python board_check.py --list
```

### 🏷️ `--label` — keep filenames meaningful

Because the socket decides the COM, you can deliberately use **one socket for all children**
and stop editing `-Port`. But then every export would be named `child_COM26_...` and differ
only by timestamp. `--label` overrides the board tag in the filename:

```powershell
python export_logs.py --port COM20 --label node5 --role child --topology linear --attack blackhole --repeat 1 --delete
#  -> child_node5_linear_blackhole_r1_<date>_telem.csv
```

The node numbers match the floor-plan diagrams (COM ports in ascending order):

| Label | Board | Role |
|---|---|---|
| `node1` | COM20 | **ROOT** |
| `node2` | COM21 | |
| `node3` | COM22 | |
| `node4` | COM25 | |
| `node5` | COM26 | **blackhole ATTACKER** / wormhole Node A |
| `node6` | COM27 | wormhole Node B |

Notes:
- `--label` changes **only the filename**, never what is exported.
- Underscores are converted to `-` — underscore is the filename field separator, so a label
  containing one would shift every downstream parser by a field.
- **Use the same label for a board across r1/r2/r3**, or comparing one board between repeats
  becomes painful.

> ✅ **The analysis never depended on the filename.** Board identity comes from the `node_id`
> (MAC) column *inside* each CSV — `preprocess.py` groups by it and `verify_topology.py`
> rebuilds the tree from it. `--label` is for **your** traceability, which still matters when
> you need to re-export one specific board.

### 🔎 Which physical board is this?

The MAC is the only identifier that truly belongs to the board:

```powershell
python board_check.py --port COM26
#  MAC b0:cb:d8:f3:32:18  ->  COM26 (blackhole ATTACKER / wormhole Node A)
```

Worth confirming for the **attacker** especially — `BLACKHOLE_ATTACKER_MAC` is hard-coded in
`mesh_config.h`, so if the attacker firmware lands on the wrong board every victim will send
probes to a MAC that isn't in the mesh (the `no route found` failure in the troubleshooting
table).

---

## ✂️ Trimming exports before analysis

> 📌 **Shared reference** — the tree/star/partial runbooks link here.
> ⚠️ **This is NOT automatic.** Exporting does not trim. You type the command yourself,
> between Phase 7b (check the folder) and Phase 7c (analyze).

### Why every export needs it

The firmware logs to **one fixed file, `/spiffs/telem.csv`, in APPEND mode**
(`csv_logger.c:84-89`), and the rows carry **no run-id column**. So one exported CSV can hold
several boot sessions stacked together:

| Session | Where it comes from | Typical size |
|---|---|---|
| Phase 2 flash | the ~30 s you watch it boot before `Ctrl+]` | 100–300 rows |
| **THE RUN** | the real experiment, ending at `terminate` | ~4,500–4,850 rows @10 Hz |
| Export plug-in | USB power-cycles the board; it boots and logs until you unplug | 490–550 rows |

That last one is unavoidable — **plugging a board in to export it reboots it**, and with no
root broadcasting phases it never gets a terminate, so it logs continuously at `layer = -1`
(disconnected) with `gt_label = 0` (benign).

### What it breaks if you skip it

Measured on the 2026-07-25 baseline·linear capture, before vs after trimming:

| | untrimmed | trimmed |
|---|---|---|
| `verify_topology --expect linear` | ❌ `WARN {-1: 5, 1: 1}` | ✅ **`PASS linear: one node per layer, depth 6`** |
| `validate_integrity` | ❌ 7 FAIL (timestamp regression) | ✅ 0 FAIL |
| `RSSI_var` max | **1386.2** | **12.96** |
| `RetryRate` mean | 0.0193 | **0.0** |
| Windows discarded | 0 (0.0%) | 4 (0.7%) |

The chain was **always correct** — the trailing rows were masking it, because
`verify_topology.py` reads each node's **final** layer. And nearly every "signal" in the
feature table was the disconnected rows: an `RSSI_var` of 1386 was pure artifact.

### How to run it

```powershell
cd "C:\Users\Angelo Calpoporo\CLionProjects\NIS16-ESP32-Environment"

# 1. DRY RUN first — writes nothing, just lists the boot sessions it found
python tools\trim_run.py tools\exports\baseline\linear_topology

# 2. Apply — writes trimmed COPIES to ...\linear_topology\trimmed\, raw untouched
python tools\trim_run.py tools\exports\baseline\linear_topology --apply
```

Then point Phase 7c's analysis at the **`trimmed`** folder (the commands there already do).
`preprocess.py` globs non-recursively (`preprocess.py:180`), so the `trimmed\` subfolder is
**not** double-counted when it scans the parent.

**`trimmed\` is the COMPLETE analysis input, not just the files that changed.** Anything that
needed no trimming is **copied across untouched**, so the folder always holds every file the
raw folder did. Confirm it on the summary line:

```
  files rewritten  : 6
  files copied as-is: 1
  files in output  : 7 of 7      <-- must equal your file count
```

> ⚠️ **If that second number is short, STOP and re-trim before analysing.** Earlier versions
> skipped copying a file that needed no trimming, so a clean single-session capture silently
> never reached `trimmed\`. When the missing file is the root's `*_arrivals.csv`, the pipeline
> does not error — it just reports **PDR, LatencyHopRatio and TunnelLatency as all-NaN**,
> which reads exactly like a failed run. (Hit for real on the 2026-07-26 blackhole·linear
> capture: `trimmed\` had 6 of 7 files and the arrivals header check errored with
> `An object at the specified path ... does not exist`.)

**It splits on timestamp regressions** — `esp_timer_get_time()` resets to ~0 on every boot, so
a backwards jump is an unambiguous session boundary — and keeps the **longest** segment. A real
run (~8–11 min) dwarfs a flash session (~30 s) and an export session (seconds), so "longest"
is a safe proxy. The dry run prints every segment so you can confirm before applying.

**It also splits on SCHEMA first.** An export can occasionally contain two concatenated
streams — a full copy of `telem.csv` followed by the real arrivals stream, each with its own
`timestamp_us,...` header. (Happens when an `EXPORT_LOGS` stream's `END_OF_FILE` marker is
corrupted: `export_logs.py` keeps capturing and the next stream lands in the same file.) The
telemetry copy is the **longer** block, so plain "keep the longest" would keep the telemetry
and throw away every probe-arrival row. `trim_run.py` now keeps only the block matching what
the filename promises (`_arrivals.csv` → the one with `src_mac`) and prints:

```
  [!] mixed capture: 2 schema block(s); kept arrivals schema (2368 rows),
      separated out 5623 row(s) of the other schema
```

> 🩺 **Seen for real on the 2026-07-25 baseline·linear capture.** The trimmed arrivals file
> came out byte-identical to the trimmed telem file — right name, right size, zero arrival
> rows — and `features.py` died 40 minutes later with `KeyError: 'src_mac'`. Nothing was lost
> on disk; the raw capture always held all 2,368 arrival rows.

**The same glitch has a second form: one file streamed TWICE.** If the lost `END_OF_FILE`
happens on a re-read of the *same* file rather than before a different one, you get two header
blocks of the **same** schema — a duplicated capture rather than a mixed one. Nothing needs
separating; the boot-session split handles it, because a re-read restarts at the run's first
timestamp and therefore reads as a backwards jump. `trim_run.py` says so explicitly:

```
  [!] repeated capture: 2 header block(s), all telem schema — the export
      streamed this file 2x. Nothing separated; the session split below
      picks the real run.
      14737 data rows, 4 boot session(s)
        session 1: rows 6315  span 661.6s  <-- KEEPING (longest)
        session 3: rows 6315  span 661.6s      (the duplicate)
```

> 🩺 **Seen on the 2026-07-26 blackhole·linear root export.** Sessions 1 and 3 were identical
> 6,315-row copies. The kept span (661.6 s) matches the attack timeline exactly
> (60 + 300 + 180 + 120 = 660 s), so **no data was lost** — but check that the kept session's
> span matches your expected run length rather than assuming the longest segment is right.

### 🔍 Sanity-check the trimmed folder (10 seconds, catches both failure modes)

Two different things can go wrong, and they need two different checks — a file count alone
catches neither, because in the mixed-capture case the broken file is present and the right
size.

**1. Is every file there?** Read it off the `trim_run.py` summary (`files in output : 7 of 7`),
or count directly:

```powershell
(Get-ChildItem tools\exports\baseline\linear_topology\trimmed\*.csv).Count   # expect 7
```

❌ Short count → a file didn't reach `trimmed\`. Re-trim with the current tool. If it's the
arrivals file, the pipeline will not error — it will just report PDR / LatencyHopRatio /
TunnelLatency as all-NaN.

**2. Is the arrivals file the real thing?** Check the header:

```powershell
Get-Content tools\exports\baseline\linear_topology\trimmed\*_arrivals.csv -TotalCount 1
```

✅ Must contain `src_mac,seq_num,latency_us`. ❌ If it ends at `...,phase_id,gt_label`, you have
the telemetry copy — re-run `trim_run.py … --apply` with the current tool.
❌ If PowerShell answers `An object at the specified path ... does not exist`, that's failure
mode 1: the file never got copied.

> 🔒 **Provenance:** default `--apply` leaves your raw captures byte-identical, so their
> `manifest.json` hashes still validate. `--in-place` also exists (it saves `<name>.orig`
> backups first), but it changes the raw files, and `validate_integrity` will then demand
> `--relock`. **For the graded M4 runs, prefer the default copy mode.**

---

## 🎯 When to press Ctrl+]

> 📌 **Shared reference** — the tree/star/partial runbooks link here. Applies to every topology.

### ❌ "Green text" is NOT the cue

`idf.py monitor` colours lines by **log level**, not by importance:

| Colour | Means | Example |
|---|---|---|
| 🟢 **Green** | `ESP_LOGI` — routine info | almost every line a healthy board prints |
| 🟡 Yellow | `ESP_LOGW` — warning | mesh hiccups, retries |
| 🔴 Red | `ESP_LOGE` — error | SPIFFS/mount failures |

So green is on screen **the whole time** — it can't tell you when to exit. And the **one green
line `run.ps1` itself prints** (`Monitor closed - run only (no export). Data is safe on the
board's SPIFFS.`) only appears **after** you press `Ctrl+]` — that's your *confirmation*, not
your cue.

> ⚠️ Also ignore the cyan banner's wording *"Ctrl+] when it reaches 'terminate'"*. That line is
> generic and is written for the **root** (Phase 4). A **child in Phase 2 never reaches
> `terminate`** — there's no root broadcasting phases yet, so waiting for it means waiting
> forever.

### ✅ The real cue — Phase 2 children

First let the flash finish: esptool writes, then `Hash of data verified.`, then the board
resets and the boot log scrolls. **Never `Ctrl+]` while it's still writing.**

Then wait for the **last `task running` line** for that board's role:

| Board / role | Wait for this line, then `Ctrl+]` |
|---|---|
| Plain child (baseline; wormhole controls) | `Probe generator task running at <n> ms interval.` → `Telemetry task running at <n> ms interval.` |
| Blackhole **attacker** (COM26) | `=== BLACKHOLE ATTACKER (relay) STARTING ===` → `Relay task running.` → `Telemetry task running…` |
| Blackhole **victim** | `Blackhole victim mode: probes -> attacker b0:cb:d8:f3:32:18` → `Telemetry task running…` |
| Wormhole **end B** (entry) | `=== WORMHOLE NODE B (entry) STARTING ===` → `Tunnel forwarder running.` → `Telemetry task running…` |
| Wormhole **end A** (exit) | `=== WORMHOLE NODE A (exit) STARTING ===` → `Re-inject task running.` → `Telemetry task running…` |

A healthy child also prints, in order:
`=== VICTIM NODE STARTING ===` → `Node ID: … Run ID: …` → `SPIFFS mounted. Total: … Used: …`
→ `Telemetry file: /spiffs/telem.csv` → `Logging to: /spiffs/telem.csv`.

> 🧠 **Rule of thumb:** once you see `Telemetry task running`, the firmware is on the chip and
> alive → `Ctrl+]` → unplug → next board. `Ctrl+]` only closes **your monitor**; it does not
> stop the board, and the firmware is already written permanently. Unplugging right after is safe.

### ✅ The real cue — the ROOT (Phase 4 → Phase 7)

**Do NOT `Ctrl+]` the root when it boots** — that would end the run early. Wait for the
scenes to finish:

1. Boot root → `=== ROOT NODE STARTING ===` → `[CTRL] Waiting 60 s for mesh to stabilise...`
2. Watch the scenes roll to **`terminate`** (~8 min baseline, ~11 min attack).
3. **Then** `Ctrl+]` — with no `-Analyze` it simply closes the monitor and prints
   `Monitor closed - run only (no export).` Nothing is computed, nothing is lost.
4. Export the children and the root by hand (Phase 6/7), then analyze.

> ✅ Since nothing fires on `Ctrl+]`, the root's exit is **not** order-critical — unlike the
> old `-Analyze` flow, where exiting early silently analyzed an incomplete folder.

---

## 🔁 Doing repeat 2 and 3

> 📌 **Shared reference** — the tree/star/partial runbooks link here.

### 🚨 The trap: the boards' logs STACK

Every board logs to **one fixed file, `/spiffs/telem.csv`, opened in append mode**
(`components/mesh_common/src/csv_logger.c`). There is **no run-id column in the rows.** So:

> ❌ If you power-cycle a child for r2 **without clearing its logs**, r2's rows are appended
> under r1's rows in the same file. Your "r2" export then contains **r1 + r2 fused together,
> with no way to separate them** — a silently corrupted repeat that `--record` may still pass.

**Clearing the board between repeats is mandatory. Re-flashing is not** — firmware survives
power-cycles; only the *logs* must go.

### 🧠 First, the mental model — the ROOT is the start button

The phases (`stabilise → baseline → attack → cooldown → terminate`) are **broadcast by the
root**. The children just listen and record. So:

> **"Run the phases again" = boot the root again.** That happens in **Phase 4**, and on a
> repeat the root is the **only** board you flash.

⚠️ **But the children must be power-cycled too.** After `terminate` a child calls
`csv_logger_close()` and drops into export-only mode (`child_node/main/victim_main.c:95-104`).
**A child that is never rebooted records nothing in r2.** Power-cycling is mandatory, not tidiness.

### 🔁 The r2 walkthrough, step by step

Assuming you exported r1 with `--delete` (boards already cleared):

| # | Where | Do this |
|---|---|---|
| 1 | 🔋 in the rooms | **Power-cycle all 5 children** — unplug from the bank, plug back in. Leave them exactly where they are. |
| 2 | 🔋 wait | ~30–60 s for the mesh to re-form |
| 3 | 🔌 **laptop** | **Flash the root** ← the only flash of the whole repeat |
| 4 | 🔌 laptop | Put the root back in place, watch to `terminate`, then `Ctrl+]` (just closes it) |
| 5 | 🔌 laptop | Bring each child over, export with `--repeat 2 --delete` |
| 6 | 🔌 laptop | Export the root (`--role root`), check all 7 files, then run M6→M7→M8 by hand |
| 7 | 🔌 laptop | `run_matrix.py --record … --repeat 2` |

Step 3 in full — **only the `-Repeat` number differs from r1**:

```powershell
.\run.ps1 -Port COM20 -Role root -Label node1 -Attack blackhole -Topology linear -Wipe -Flash -Repeat 2
```

So the repeat loop is **Phase 3 → 4 → 5 → 6 → 7 → 8**. You re-enter at **Phase 3**
(place & power — they're already placed, so it's just the power-cycle) and the flash you're
looking for is **Phase 4**.

### ✅ Answering "do I go back to Phase 1?"

**No — never Phase 1.** `set-target` is once ever. Pick one of these two:

#### 🅰️ Best — clear as you export (no second laptop trip)

Add `--delete` to **every** Phase 6 child export. The board is wiped the moment its CSV is
safely off, so it's already empty for the next repeat:

```powershell
cd tools
python export_logs.py --port COM20 --role child --label node5 --topology linear --attack blackhole --repeat 1 --delete
cd ..
```
> 🚨 **Carry each board back to its room but leave it UNPLUGGED.** A child powered
> now logs benign `layer = -1` rows all the way through Phase 7/8 — and those
> **cannot be trimmed out afterwards** (no reboot = no timestamp regression to split on).
> Plug them in only when you're ready for the next repeat: [why](#-carry-the-children-back--but-dont-power-them-on-until-youre-ready).


Then for **r2** you skip Phases 1–2 entirely:

| Phase | r1 | r2 / r3 |
|---|---|---|
| 1. Prep (`set-target`) | ✅ once ever | ⏭️ skip |
| 2. Flash children | ✅ `-Wipe -Flash` | ⏭️ **skip — just power-cycle them in their rooms** |
| 3. Place & power | ✅ | ✅ (they're already placed — power off, power on) |
| 4. Boot root LAST | ✅ `-Wipe -Flash -Analyze -Repeat 1` | ✅ same but **`-Repeat 2`**; `-Wipe -Flash` clears the root itself |
| 5. Watch to `terminate` | ✅ | ✅ |
| 6. Export children | ✅ `--repeat 1 --delete` | ✅ **`--repeat 2 --delete`** ← the one number you change |
| 7. `Ctrl+]` the root | ✅ | ✅ |
| 8. Record | `--repeat 1` | `--repeat 2` |

So the r2 loop is: **power-cycle the 5 children in their rooms → re-flash only the root on the
laptop → watch → export with `--repeat 2`.** You do *not* carry the children to the laptop
before the run — only after it, to export.

#### 🅱️ Fallback — you already exported r1 WITHOUT `--delete`

The children still hold r1's rows. Clear each one before r2 (firmware kept, no re-flash):

```powershell
python tools\export_logs.py --port COM20 --wipe   # node5
python tools\export_logs.py --port COM20 --wipe   # node6
python tools\export_logs.py --port COM20 --wipe   # node4
python tools\export_logs.py --port COM20 --wipe   # node3
python tools\export_logs.py --port COM20 --wipe   # node2
```

That's a laptop trip for each board — which is exactly what 🅰️ saves you. After wiping,
put them back in their rooms and resume at Phase 3.

> 💡 Prefer the belt-and-braces route? Just redo **Phase 2** (`-Wipe -Flash`) for r2 and r3.
> It's slower and needs every board at the laptop, but `-Wipe -Flash` full-erases the chip, so
> it is always correct. Use it if you're ever unsure whether a board was cleared.

### 🧹 How the children get cleared **without** re-flashing

Clearing a child isn't a flash operation — it's a **serial command**. Every board runs a
`DELETE_LOGS` listener from boot (`run.ps1:173-174`), so the laptop just tells it to erase its
logs while the firmware stays exactly where it is.

| Board | How it gets cleared | Re-flash needed? |
|---|---|---|
| **Root** | `-Wipe -Flash` in Phase 4 — full chip erase + reflash | ✅ yes, every repeat |
| **Children** | `--delete` on the Phase 6 export (or `--wipe` later) | ❌ **no** |

`--delete` only erases **after a successful download** (`export_logs.py:488` —
`if args.delete and not any_failed`), so a failed export never costs you the data.

#### 💡 Why this makes the repeat almost free

You're already carrying each child to the laptop in Phase 6 to export it. So `--delete` costs
**zero extra trips** — and when you carry the board back and plug it into its power bank,
**that plug-in *is* the power-cycle r2 needs.**

> Export with `--delete` → walk it back to its room → **leave it UNPLUGGED** until you're
> ready to start the next repeat. Read the warning below before you plug anything in.

#### 🚨 Carry the children back — but DON'T power them on until you're ready

**This is the single easiest way to silently poison a repeat, and it cannot be cleaned up
afterwards.**

A child logs from the moment it boots. Before any root broadcast reaches it, its rows are
stamped `PHASE_ID_BASELINE` / `GT_LABEL_BASELINE` (`phase_listener.c:33-34`) — i.e.
**benign** — with `layer = -1` (disconnected, no root yet). The usual budget for that is
**~30–60 s**, the time it takes the mesh to re-form before you flash the root.

But if you plug the children in at the end of Phase 6 and *then* do Phase 7 and Phase 8
(root export → trim → M6/M7/M8 → verify → record), those are **many minutes**, and every
one of them is being logged as benign.

Why this one can't be fixed in post, unlike the trailing-session rows Phase 7b trims away:

| | |
|---|---|
| `trim_run.py` | ❌ **cannot** split it. Splitting needs a **timestamp regression** = a reboot. A board powered continuously from Phase 6 into the run never reboots, so the idle rows and the run rows are **one unbroken session**. |
| `preprocess.py` | ❌ **won't** drop it. Its "Rows dropped (contaminated)" counter is only for malformed rows (UART log lines interleaved during export). `layer = -1` rows are well-formed and survive all the way into `windowed_dataset.csv` — verified. |
| Net result | Benign-class windows that were never part of any run, indistinguishable from real baseline. |
| **Worse** | **The oversized log can fill SPIFFS until the board cannot read its own `telem.csv` and the export returns 0 rows.** |

> 🔥 **This is not hypothetical — it cost r2 on 2026-07-26.** The children sat
> powered through Phases 7–8, so `telem.csv` reached **1.1 MB** for an 11-minute
> run that should produce ~490 KB. `export_logs.py` then reported:
>
> ```
> [####################] 100.0%  0 B/1.1 MB  0 rows  0 B/s
> FAILED: device announced 1.1 MB then sent END_OF_FILE with 0 rows
> ```
>
> The size is right (`ftell` worked) but no rows come out (`fgets` returned NULL).
> Power-cycling does **not** help — the fault is in the filesystem, not a stuck
> handle. This is [`esp32-issues`](esp32-issues.md) **I-017** recurring, where the
> cure was a one-time `erase-flash`.
>
> ✅ **Recover it before you wipe anything** — `tools/recover_spiffs.py` dumps the
> raw flash with esptool, bypassing the filesystem entirely:
>
> ```powershell
> cd tools
> python recover_spiffs.py --port COM20 -o exports\<attack>\<topology>\<name>_telem.csv
> ```
>
> ~70 % of raw rows come back with **zero** corrupt rows. That is enough: M6
> downsamples to a 1 Hz grid, so a 10 Hz stream missing 30 % still yields a
> **complete** window set (measured: 134 of 134 windows, 1 discarded).
> `--delete` / `--wipe` FORMAT the partition — do those only after recovering.

✅ **The safe order:**

1. Phase 6 — export each child with `--delete`, carry it back to its room, **leave it unplugged**.
2. Phase 7 + 8 — export the root, analyze, verify, record. Take as long as you need.
3. **Only then** plug all 5 children in, wait ~30–60 s for the mesh to re-form, and go to
   Phase 4 (flash the root with the new `-Repeat` number).

> 💡 Prefer to keep the boards moving? You can defer Phase 7c's analysis — it only reads
> `tools\exports\…` and overwrites its own outputs, so it's re-runnable any time. But still
> confirm the **7 files are present** and the arrivals header lists `src_mac,seq_num` before
> starting the next repeat, so a broken r1 doesn't cost you r2 as well.

#### 🆘 The one case where you *would* re-flash a child

If a board is crash-looping or its storage filled up, the serial listener never gets far enough
to accept `DELETE_LOGS`. Only a bootloader-level erase reaches it — that's `-Wipe -Flash`
(`run.ps1:165-172`). Symptom: the board spams `fprintf failed` or fails to open its log file.
Otherwise, serial clearing is all you ever need.

### 🔧 What you MUST re-do every repeat, regardless

- **The root**, with `-Wipe -Flash` — it stacks `telem.csv` **and** `arrivals.csv` the same way.
  There is no `--delete` shortcut for the root; the `-Wipe -Flash` in Phase 4 already handles it.
- **The repeat number — but only TWO of the three matter.** Where it actually lands:

  | Where | Effect | Get it wrong and… |
  |---|---|---|
  | Phase 4 root `-Repeat <N>` | ⚪ **cosmetic on the manual route.** `run.ps1` uses it in exactly two places (`:321` a printed hint, `:362` the auto-export it only reaches with `-Export`/`-Analyze`). It touches **no build flag, no build folder, no firmware, no CSV column** — the rows have no run-id at all. | nothing. Export with the right `--repeat` and you're fine. |
  | Phase 6/7 export `--repeat <N>` | 🔴 **This one names the file.** | the CSVs land under the wrong repeat tag. |
  | Phase 8 `--record --repeat <N>` | 🔴 **This one ticks the box.** | you re-record the *previous* repeat and the matrix silently stays put. |

  > 🩺 **Both real failures happened on 2026-07-26.** The root was booted with
  > `-Repeat 1` for r2 — harmless, the export was still tagged `_r2_` correctly.
  > But `--record … --repeat 1` then re-recorded r1, and the grid sat at 1/24
  > with a complete r2 on disk and no complaint. Use **`--autorecord`** (below)
  > and the third number stops being a thing you can get wrong.

### 🧊 Do NOT archive between repeats

r1/r2/r3 are *meant* to pile up in the same `exports/<attack>/linear_topology/` folder — that's
how the matrix counts 3 repeats. Only archive
([`ARCHIVE-RUNBOOK.md`](ARCHIVE-RUNBOOK.md)) when **throwing a bad run away**, or when the whole
cell is finished and you're moving to the next attack/topology.

---

# ▶️ RUN A — BASELINE (linear)  ·  the control (not in the M4 24)

**Goal:** a clean "normal" recording, no attacker. Every board is just a plain node.
This run has **no attack scene**, so it's ~8 minutes.

### Phase 1 — Prep (once ever)
```powershell
cd root_node;  idf.py set-target esp32
cd ..\child_node;  idf.py set-target esp32
cd ..
```

### Phase 2 — Flash the 5 children (one at a time)
Plug in one board → run its line → wait for **`Telemetry task running at <n> ms interval.`** →
press **`Ctrl+]`** → unplug → next board.

> 🎯 Green text is *not* the cue — see [**When to press Ctrl+]**](#-when-to-press-ctrl).
> Don't wait for `terminate` here; a Phase 2 child never reaches it.
```powershell
.\run.ps1 -Port COM20 -Role child -Label node5 -Topology linear -Wipe -Flash
.\run.ps1 -Port COM20 -Role child -Label node6 -Topology linear -Wipe -Flash
.\run.ps1 -Port COM20 -Role child -Label node4 -Topology linear -Wipe -Flash
.\run.ps1 -Port COM20 -Role child -Label node3 -Topology linear -Wipe -Flash
.\run.ps1 -Port COM20 -Role child -Label node2 -Topology linear -Wipe -Flash
```

### Phase 3 — Place & power
Put the 5 children in their rooms (see the floor-plan diagram), power each from a bank,
and give them ~30–60 s to find each other.

### Phase 4 — Boot the root LAST (no `-Analyze` — you analyze by hand in Phase 7)
```powershell
.\run.ps1 -Port COM20 -Role root -Label node1 -Topology linear -Wipe -Flash
```
Leave the monitor open. Watch for `[CTRL] Waiting 60 s for mesh to stabilise...`.

### Phase 5 — Watch to terminate (~8 min), then `Ctrl+]` and unplug the root
Scenes: `stabilise → baseline (0) → cooldown (0) → terminate`. At **terminate**, press
**`Ctrl+]`** (it only closes the monitor — nothing fires, nothing is lost) and **unplug the
root**. Every board claims COM20, so the root *must* be disconnected before you can export a
child — see [**USB port convention**](#-usb-port-convention--read-first). Its CSVs are already
closed on SPIFFS; you export it last, in Phase 7.

### Phase 6 — Export the 5 CHILDREN over USB (one at a time)
```powershell
cd tools
python export_logs.py --port COM20 --role child --label node5 --topology linear --attack none --repeat 1 --delete
python export_logs.py --port COM20 --role child --label node6 --topology linear --attack none --repeat 1 --delete
python export_logs.py --port COM20 --role child --label node4 --topology linear --attack none --repeat 1 --delete
python export_logs.py --port COM20 --role child --label node3 --topology linear --attack none --repeat 1 --delete
python export_logs.py --port COM20 --role child --label node2 --topology linear --attack none --repeat 1 --delete
cd ..
```
> 🚨 **Carry each board back to its room but leave it UNPLUGGED.** A child powered
> now logs benign `layer = -1` rows all the way through Phase 7/8 — and those
> **cannot be trimmed out afterwards** (no reboot = no timestamp regression to split on).
> Plug them in only when you're ready for the next repeat: [why](#-carry-the-children-back--but-dont-power-them-on-until-youre-ready).

> 🧹 `--delete` wipes the board **only after its CSV downloaded successfully**
> (`export_logs.py` — `if args.delete and not any_failed`), so a failed export never costs you
> data. It leaves each child cleared for the next run, at zero extra laptop trips.

### Phase 7 — Plug the root back in, export it, then analyze BY HAND

You already `Ctrl+]`'d and unplugged it in Phase 5. Plug the root back in **alone** — with the
5 children powered off, or it may not answer. `--role root` pulls **both** `telem` *and*
`arrivals`:

```powershell
cd tools
python export_logs.py --port COM20 --role root --label node1 --topology linear --attack none --repeat 1
cd ..
```

**Check the folder is complete BEFORE analyzing** — this is the step `-Analyze` skips. Expect
**7 files**: 5 child `_telem.csv` + the root's `_telem.csv` and `_arrivals.csv`.

```powershell
Get-ChildItem tools\exports\baseline\linear_topology
python tools\trim_run.py tools\exports\baseline\linear_topology             # dry run: lists boot sessions
python tools\trim_run.py tools\exports\baseline\linear_topology --apply     # -> ...\linear_topology\trimmed\ (raw untouched)
(Get-ChildItem tools\exports\baseline\linear_topology\trimmed\*.csv).Count   # MUST be 7 — a short count silently NaNs out PDR/latency
Get-Content tools\exports\baseline\linear_topology\trimmed\*_arrivals.csv -TotalCount 1   # MUST list src_mac,seq_num
```

Then run M6 → M7 → M8 (identical to `run.ps1:399, 408, 419`):

```powershell
cd analysis
python preprocess.py ..\tools\exports\baseline\linear_topology\trimmed -o baseline\linear_topology\windowed_dataset.csv
python features.py   ..\tools\exports\baseline\linear_topology\trimmed -o baseline\linear_topology\feature_table.csv
python eda.py        baseline\linear_topology\feature_table.csv -o baseline\linear_topology\eda_output
cd ..
```

### ✅ Verify (baseline = control, not part of the M4 24)
```powershell
cd tools; python validate_integrity.py exports\baseline\linear_topology\trimmed; python verify_topology.py --dir exports\baseline\linear_topology\trimmed --topology linear --attack none --repeat 1 --expect linear; cd ..
```
**What "good" looks like:** every board's `telem.csv` fills the whole run, all rows labelled
`0`, and the root's `arrivals.csv` shows every node's probes arriving steadily start to
finish (no gaps, no duplicates). This is your "normal" reference the attacks are compared against.

---

# ▶️ RUN B — BLACKHOLE (linear)

**Goal:** COM26 becomes a **relay that swallows packets**. Victims
(COM27/COM25/COM22/COM21) send their probes *to COM26*; COM26 forwards them normally during
baseline/cooldown but **silently drops them during the attack scene** — so the root sees
those probes *vanish*.

> ✅ **No cable needed. No MAC editing needed.** `BLACKHOLE_ATTACKER_MAC` in
> `mesh_config.h` is already set to COM26 (`b0:cb:d8:f3:32:18`). **Same placement as
> Baseline.**

### Phase 1 — Prep
Nothing extra. (Target already set from Run A.)

### Phase 2 — Flash the 5 children (one at a time)
Notice COM26 gets `-BlackholeRole attacker`; the other four get `-BlackholeRole victim`.

> 🎯 On each board, `Ctrl+]` once you see its `↳ watch for:` line **plus**
> `Telemetry task running…` — see [**When to press Ctrl+]**](#-when-to-press-ctrl).
> 🔁 On **r2/r3 you normally skip this whole phase** — see [**Doing repeat 2 and 3**](#-doing-repeat-2-and-3).
```powershell
# COM26 = the attacker (relay/drop). Clean-rebuild once for the first child flash:
Remove-Item -Recurse -Force child_node\build_* -ErrorAction SilentlyContinue
.\run.ps1 -Port COM20 -Role child -Label node5 -Attack blackhole -BlackholeRole attacker -Topology linear -Wipe -Flash
#   ↳ watch for: "BLACKHOLE ATTACKER (relay) STARTING" + "Relay task running."
#   ↳ confirm printed STA MAC = b0:cb:d8:f3:32:18

.\run.ps1 -Port COM20 -Role child -Label node6 -Attack blackhole -BlackholeRole victim -Topology linear -Wipe -Flash
#   ↳ watch for: "Blackhole victim mode: probes -> attacker b0:cb:d8:f3:32:18"
.\run.ps1 -Port COM20 -Role child -Label node4 -Attack blackhole -BlackholeRole victim -Topology linear -Wipe -Flash
.\run.ps1 -Port COM20 -Role child -Label node3 -Attack blackhole -BlackholeRole victim -Topology linear -Wipe -Flash
.\run.ps1 -Port COM20 -Role child -Label node2 -Attack blackhole -BlackholeRole victim -Topology linear -Wipe -Flash
```
👉 On each victim, confirm the `-> attacker b0:cb:d8:f3:32:18` line — that's proof it's
aiming at COM26.

### Phase 3 — Place & power
**Exact same positions as Baseline.** Power all 5 children.

### Phase 4 — Boot the root LAST (with `-Repeat 1`; no `-Analyze`)
```powershell
Remove-Item -Recurse -Force root_node\build_* -ErrorAction SilentlyContinue
.\run.ps1 -Port COM20 -Role root -Label node1 -Attack blackhole -Topology linear -Wipe -Flash -Repeat 1
```
The root only **announces** the attack scene; it never drops anything itself.
(`-Repeat 1` here → bump to `2`/`3` for r2/r3.)

### Phase 5 — Watch to terminate (~11 min), then `Ctrl+]` and unplug the root
Scenes: `stabilise → baseline (0) → blackhole (1) → cooldown (0) → terminate`.
If COM26 is on a monitor, it prints `BLACKHOLE: dropped victim probe seq=...` during the attack.
At **terminate**, press **`Ctrl+]`** and **unplug the root** — every board claims COM20, so it
must be off the port before you can export a child ([**USB port convention**](#-usb-port-convention--read-first)).
Nothing fires on `Ctrl+]`; the root's CSVs are safe on SPIFFS and you pull them in Phase 7.

### Phase 6 — Export the 5 CHILDREN over USB (one at a time)
```powershell
cd tools
python export_logs.py --port COM20 --role child --label node5 --topology linear --attack blackhole --repeat 1 --delete
python export_logs.py --port COM20 --role child --label node6 --topology linear --attack blackhole --repeat 1 --delete
python export_logs.py --port COM20 --role child --label node4 --topology linear --attack blackhole --repeat 1 --delete
python export_logs.py --port COM20 --role child --label node3 --topology linear --attack blackhole --repeat 1 --delete
python export_logs.py --port COM20 --role child --label node2 --topology linear --attack blackhole --repeat 1 --delete
cd ..
```
> 🚨 **Carry each board back to its room but leave it UNPLUGGED.** A child powered
> now logs benign `layer = -1` rows all the way through Phase 7/8 — and those
> **cannot be trimmed out afterwards** (no reboot = no timestamp regression to split on).
> Plug them in only when you're ready for the next repeat: [why](#-carry-the-children-back--but-dont-power-them-on-until-youre-ready).


### Phase 7 — Plug the root back in, export it, then analyze BY HAND

You already `Ctrl+]`'d and unplugged it in Phase 5. Plug the root back in **alone** — with the
5 children powered off, or it may not answer. `--role root` pulls **both** `telem` *and*
`arrivals`:

```powershell
cd tools
python export_logs.py --port COM20 --role root --label node1 --topology linear --attack blackhole --repeat 1
cd ..
```

**Check the folder is complete BEFORE analyzing** — this is the step `-Analyze` skips. Expect
**7 files**: 5 child `_telem.csv` + the root's `_telem.csv` and `_arrivals.csv`.

```powershell
Get-ChildItem tools\exports\blackhole\linear_topology
python tools\trim_run.py tools\exports\blackhole\linear_topology             # dry run: lists boot sessions
python tools\trim_run.py tools\exports\blackhole\linear_topology --apply     # -> ...\linear_topology\trimmed\ (raw untouched)
(Get-ChildItem tools\exports\blackhole\linear_topology\trimmed\*.csv).Count   # MUST be 7 — a short count silently NaNs out PDR/latency
Get-Content tools\exports\blackhole\linear_topology\trimmed\*_arrivals.csv -TotalCount 1   # MUST list src_mac,seq_num
```

Then run M6 → M7 → M8 (identical to `run.ps1:399, 408, 419`):

```powershell
cd analysis
python preprocess.py ..\tools\exports\blackhole\linear_topology\trimmed -o blackhole\linear_topology\windowed_dataset.csv
python features.py   ..\tools\exports\blackhole\linear_topology\trimmed -o blackhole\linear_topology\feature_table.csv
python eda.py        blackhole\linear_topology\feature_table.csv -o blackhole\linear_topology\eda_output
cd ..
```

### Phase 8 — Record this repeat (M4)
```powershell
# confirm the chain formed (run from tools\ so it scans the right folder):
cd tools; python verify_topology.py --dir exports\blackhole\linear_topology\trimmed --topology linear --attack blackhole --repeat 1 --expect linear; cd ..
# validate THIS repeat's CSVs and tick it off in the 24-cell matrix:
python tools\run_matrix.py --record --topology linear --attack blackhole --repeat 1
```

> ✅ **Easier and safer: `--autorecord`.** It scans `exports/` for captures that are
> complete but not yet ticked off, validates each, and records them — so you never
> type `--topology` / `--attack` / `--repeat` again. Getting that last flag wrong
> silently re-records the PREVIOUS repeat and leaves the matrix unchanged with good
> data sitting on disk (this happened on 2026-07-26):
>
> ```powershell
> python tools\run_matrix.py --autorecord
> ```
>
> `--status` also warns on its own now if it spots captured-but-unrecorded cells.

```powershell
python tools\run_matrix.py --status
```
> 🔁 **Repeats:** that was **r1**. Do the whole blackhole run again for **r2** and **r3**,
> changing `-Repeat`/`--repeat` `1` → `2` → `3` in the root command (Phase 4), the child
> exports (Phase 6), AND the `--record` line. **Don't clear the folder between them.**

**The "disappearing packets" signature to confirm by eye:**
- **Root `arrivals.csv`:** each victim's probes are present during `gt_label=0`, then
  **vanish during `gt_label=1`**, and come back at cooldown. **That gap = the blackhole.**
- **Attacker COM26 `telem.csv`:** `tx_count` (forwarded) goes **flat during label 1**,
  while `retry_count` (dropped) **climbs**. `probes_count` climbs the whole time.
- **Victim `telem.csv`:** `probes_count` climbs steadily — victims never know they're being dropped.

---

# ▶️ RUN C — WORMHOLE (linear)

**Goal:** two colluding attackers, **COM26 (Node A)** and **COM27 (Node B)**, secretly
connected by a **physical wire**. During the attack, Node B **tunnels a copy** of each
probe to Node A over the wire; Node A **re-injects** it to the root — so the root sees
each probe **twice** (a duplicate + a weird latency). COM25, COM22 and COM21 are **plain
controls** here (no attack firmware).

> 🔌 **This run — and ONLY this run — needs a small cable between COM26 and COM27.**
> That's why they share **Bedroom 1**. Same board positions as the other two runs; you're
> just adding one short cable between the two boards in that room.

### Phase 1 — Prep: wire + TEST the A↔B cable (do this before anything else)

Wire **COM26 ↔ COM27** with 3 jumper wires, **crossed**, before powering them:

| COM26 (Node A) pin | wire to | COM27 (Node B) pin |
|---|---|---|
| GPIO 17 (TX) | ───────► | GPIO 16 (RX) |
| GPIO 16 (RX) | ◄─────── | GPIO 17 (TX) |
| GND | ──────── | GND |

TX always goes to the **other** board's RX (crossed, not straight). This cable is **only
between the two boards** — never to the laptop — and **stays connected for the entire run**.

> ⚠️ **WROVER/PSRAM boards:** GPIO16/17 are taken by the PSRAM chip. If your boards are
> WROVER, change `WORMHOLE_UART_TX_PIN` / `WORMHOLE_UART_RX_PIN` in `mesh_config.h` to a
> free pair (e.g. 4 and 5) and wire those instead.

**Now TEST the wire in seconds** (a bad wire silently tunnels nothing — catch it *before*
an 11-min run):
```powershell
cd uart_link_test
idf.py set-target esp32          # once
idf.py -p COM26 flash monitor    # press Ctrl+] at the banner
idf.py -p COM27 flash monitor    # WATCH this one
cd ..
```
- `[LINK OK]` on the watched board → 🎉 wire is good, continue.
- `RX received=0` (stays 0) → wire is bad; fix the **GND** or the **crossing** and retry.

### Phase 2 — Flash the boards (one at a time)
COM26 = Node A, COM27 = Node B (opposite ends!), COM25 + COM22 + COM21 = plain controls.

> 🎯 On each board, `Ctrl+]` once you see its `↳ watch for:` line **plus**
> `Telemetry task running…` — see [**When to press Ctrl+]**](#-when-to-press-ctrl).
> 🔁 On **r2/r3 you normally skip this whole phase** — see [**Doing repeat 2 and 3**](#-doing-repeat-2-and-3).
```powershell
.\run.ps1 -Port COM20 -Role child -Label node5 -Attack wormhole -WormholeEnd A -Topology linear -Wipe -Flash
#   ↳ watch for: "WORMHOLE NODE A (exit) STARTING" + "Wormhole UART tunnel ready: ..."
.\run.ps1 -Port COM20 -Role child -Label node6 -Attack wormhole -WormholeEnd B -Topology linear -Wipe -Flash
#   ↳ watch for: "WORMHOLE NODE B (entry) STARTING" + "Tunnel forwarder running."
.\run.ps1 -Port COM20 -Role child -Label node4 -Topology linear -Wipe -Flash    # plain control, no attack
.\run.ps1 -Port COM20 -Role child -Label node3 -Topology linear -Wipe -Flash    # plain control, no attack
.\run.ps1 -Port COM20 -Role child -Label node2 -Topology linear -Wipe -Flash    # plain control, no attack
```
⚠️ The two attackers must take **opposite** `-WormholeEnd` values (one `A`, one `B`). Two
of the same, or a missing one, = the tunnel never completes.

### Phase 3 — Place & power
**Same positions as the other runs.** Keep the **A↔B cable connected** between COM26/COM27
in Bedroom 1. Power all 5 children.

### Phase 4 — Boot the root LAST (with `-Repeat 1`; no `-Analyze`)
```powershell
.\run.ps1 -Port COM20 -Role root -Label node1 -Attack wormhole -Topology linear -Wipe -Flash -Repeat 1
```
`-Attack wormhole` makes the root **announce** the wormhole scene (required — it sets the
label); the root does not tunnel anything. (`-Repeat 1` → bump for r2/r3.)

### Phase 5 — Watch to terminate (~11 min), then `Ctrl+]` and unplug the root
Scenes: `stabilise → baseline (0) → wormhole (2) → cooldown (0) → terminate`. During the
attack, if monitored, **Node B** prints `Tunnelled probe seq=... -> Node A via UART` and
**Node A** prints `Re-injected probe src=... seq=...`. At **terminate**, press **`Ctrl+]`** and
**unplug the root** — every board claims COM20, so it must be off the port before you can
export a child ([**USB port convention**](#-usb-port-convention--read-first)). Nothing fires on
`Ctrl+]`; the root's CSVs are safe on SPIFFS and you pull them in Phase 7. **Leave the A↔B
cable wired.**

### Phase 6 — Export the 5 CHILDREN over USB (controls use `--attack wormhole`)
```powershell
cd tools
python export_logs.py --port COM20 --role child --label node5 --topology linear --attack wormhole --repeat 1 --delete
python export_logs.py --port COM20 --role child --label node6 --topology linear --attack wormhole --repeat 1 --delete
python export_logs.py --port COM20 --role child --label node4 --topology linear --attack wormhole --repeat 1 --delete
python export_logs.py --port COM20 --role child --label node3 --topology linear --attack wormhole --repeat 1 --delete
python export_logs.py --port COM20 --role child --label node2 --topology linear --attack wormhole --repeat 1 --delete
cd ..
```
> 🚨 **Carry each board back to its room but leave it UNPLUGGED.** A child powered
> now logs benign `layer = -1` rows all the way through Phase 7/8 — and those
> **cannot be trimmed out afterwards** (no reboot = no timestamp regression to split on).
> Plug them in only when you're ready for the next repeat: [why](#-carry-the-children-back--but-dont-power-them-on-until-youre-ready).

> ℹ️ Exporting the controls (COM25/COM22/COM21) with `--attack wormhole` files them **with
> this run** even though they ran plain — exactly where you want them.

### Phase 7 — Plug the root back in, export it, then analyze BY HAND

You already `Ctrl+]`'d and unplugged it in Phase 5. Plug the root back in **alone** — with the
5 children powered off, or it may not answer. `--role root` pulls **both** `telem` *and*
`arrivals`:

```powershell
cd tools
python export_logs.py --port COM20 --role root --label node1 --topology linear --attack wormhole --repeat 1
cd ..
```

**Check the folder is complete BEFORE analyzing** — this is the step `-Analyze` skips. Expect
**7 files**: 5 child `_telem.csv` + the root's `_telem.csv` and `_arrivals.csv`.

```powershell
Get-ChildItem tools\exports\wormhole\linear_topology
python tools\trim_run.py tools\exports\wormhole\linear_topology             # dry run: lists boot sessions
python tools\trim_run.py tools\exports\wormhole\linear_topology --apply     # -> ...\linear_topology\trimmed\ (raw untouched)
(Get-ChildItem tools\exports\wormhole\linear_topology\trimmed\*.csv).Count   # MUST be 7 — a short count silently NaNs out PDR/latency
Get-Content tools\exports\wormhole\linear_topology\trimmed\*_arrivals.csv -TotalCount 1   # MUST list src_mac,seq_num
```

Then run M6 → M7 → M8 (identical to `run.ps1:399, 408, 419`):

```powershell
cd analysis
python preprocess.py ..\tools\exports\wormhole\linear_topology\trimmed -o wormhole\linear_topology\windowed_dataset.csv
python features.py   ..\tools\exports\wormhole\linear_topology\trimmed -o wormhole\linear_topology\feature_table.csv
python eda.py        wormhole\linear_topology\feature_table.csv -o wormhole\linear_topology\eda_output
cd ..
```

### Phase 8 — Record this repeat (M4)
```powershell
cd tools; python verify_topology.py --dir exports\wormhole\linear_topology\trimmed --topology linear --attack wormhole --repeat 1 --expect linear; cd ..
python tools\run_matrix.py --record --topology linear --attack wormhole --repeat 1
```

> ✅ **Easier and safer: `--autorecord`.** It scans `exports/` for captures that are
> complete but not yet ticked off, validates each, and records them — so you never
> type `--topology` / `--attack` / `--repeat` again. Getting that last flag wrong
> silently re-records the PREVIOUS repeat and leaves the matrix unchanged with good
> data sitting on disk (this happened on 2026-07-26):
>
> ```powershell
> python tools\run_matrix.py --autorecord
> ```
>
> `--status` also warns on its own now if it spots captured-but-unrecorded cells.

```powershell
python tools\run_matrix.py --status
```
> 🔁 **Repeats:** that was **r1**. Do the whole wormhole run again for **r2** and **r3**
> (the A↔B cable stays wired), changing `-Repeat`/`--repeat` `1` → `2` → `3` in the root
> command, the child exports, and the `--record` line. **Don't clear the folder between them.**

**The "double vision" signature to confirm by eye:**
- **Root `arrivals.csv`:** during `gt_label=2` rows, each of Node B's probes appears
  **TWICE** — two rows with the **same `src_mac` + same `seq_num`** but **different
  `latency_us`** (normal copy vs. slower tunnel copy). During `gt_label=0` each appears
  **once**. **That doubling = the wormhole.**
- **Node B (COM27) `telem.csv`:** `retry_count` (probes tunnelled) climbs **only during
  label 2**; `tx_count` (normal forwards) climbs the whole run.
- **Node A (COM26) `telem.csv`:** `probes_count` (tunnelled-in) and `tx_count`
  (re-injected) climb **only during label 2**, and are `0` elsewhere.
- If you saw `CRC mismatch` / `bad magic` in a monitor → loose or mis-crossed cable.

---

## 🆘 Quick troubleshooting

| Symptom | Likely cause → fix |
|---|---|
| A board never joins the mesh | It's out of range → **move it closer** to its neighbour in the chain (usually Master's COM21). |
| Root monitor spams `ROOT LOST` / re-parenting | Chain too wobbly → tighten spacing; or channel clash → set `MESH_CHANNEL` to 1/6, re-flash. |
| `Access is denied` when flashing | A monitor is still holding the port → `run.ps1` auto-frees it; just re-run. Press `Ctrl+]` to close monitors. |
| Export prints `-> EXPORT_LOGS ...` then **hangs with no progress bar** | The board is still meshing and flooding the UART, so the `READY_TO_SEND` handshake is lost — and the 30 s cutoff is an *idle* timeout, so the log spam keeps resetting it and it hangs forever. **`Ctrl+C`, power OFF the other 5 boards, then export one at a time.** The bar only draws after `READY_TO_SEND` (`export_logs.py:198,268`), so **no bar = no stream**. Nothing is lost; just re-run. |
| `can't open file '...\export_logs.py'` | You're in the repo root. Every Phase 6 block starts with `cd tools` — run it from there (that's also where `-Analyze` reads from, `run.ps1:359`). |
| `Failed to open file` / storage full | Old runs filled the chip → `-Wipe -Flash` erases first; it's already in every command above. |
| Blackhole: victims say wrong attacker MAC | `BLACKHOLE_ATTACKER_MAC` ≠ COM26 → it should be `b0:cb:d8:f3:32:18`; re-flash victims. |
| Wormhole: no duplicates at root | Dead tunnel wire → re-run the `uart_link_test` `[LINK OK]` check; fix GND / crossing. |
| Validator flags phase-bleed / duplicates | Usually mesh instability (linear) → tighten spacing and re-run; see `wormhole-working-state.md`. |
| Changed anything in `mesh_common/` | Rebuild **both** `root_node` and `child_node` clean: `Remove-Item -Recurse -Force build*`. |

---

## 🃏 One-glance command card (linear)

| Run | Children flash (COM26 / COM27 / COM25 / COM22 / COM21) | Root flash (COM20, LAST) | Export `--attack` | Extra? |
|---|---|---|---|---|
| **Baseline** | all `-Topology linear` | `-Role root -Topology linear` | `none` | — |
| **Blackhole** | COM26 `-Attack blackhole -BlackholeRole attacker`; COM27/COM25/COM22/COM21 `-Attack blackhole -BlackholeRole victim` | `-Attack blackhole` | `blackhole` | — |
| **Wormhole** | COM26 `-Attack wormhole -WormholeEnd A`; COM27 `-Attack wormhole -WormholeEnd B`; COM25/COM22/COM21 plain | `-Attack wormhole` | `wormhole` | 🔌 A↔B cable + `[LINK OK]` test |

All flash commands also carry `-Wipe -Flash`. Root **always boots last**.

---

## ➡️ Doing the other topologies later

Your plan — *same rooms, just change the command* — works for all four topologies. When you
move on, the **only** change is the `-Topology` word in every command:
`-Topology linear` → `-Topology tree` / `-Topology star` / `-Topology partial`, and the
export `--topology` to match (files auto-sort into that topology's folder). See
[`TREE-RUNBOOK.md`](TREE-RUNBOOK.md), [`STAR-RUNBOOK.md`](STAR-RUNBOOK.md), and
[`PARTIAL-RUNBOOK.md`](PARTIAL-RUNBOOK.md) — each has the placement tuned for that shape.

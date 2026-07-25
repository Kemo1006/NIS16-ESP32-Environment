# 🌳 TREE Topology — Full Runbook (Baseline · Blackhole · Wormhole)

> **What this file is:** one place to run **all three** experiments for the **tree**
> topology on **one fixed placement** — set up the boards once, then just **swap the
> commands** per run. Sibling of [`LINEAR-RUNBOOK.md`](LINEAR-RUNBOOK.md); same mental
> model, different shape.
>
> ⭐ **Tree is the topology to trust.** Per `memory/wormhole-working-state.md`, tree is the
> **only verified-stable** topology — the mesh self-organises comfortably, so you get the
> **cleanest data with the least fuss**. If you want one solid run of each attack, do it here.
>
> 🧩 **6 boards total:** 1 root (COM20) + 5 children (COM26, COM27, COM25, COM21, **COM22**).

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

## 📍 THE PLACEMENT — mapped to your 2nd-floor plan (once, all three runs)

Tree = a **branching family tree**. Unlike linear you do **not** force a single chain — you
let the mesh pick its own parents. On your floor plan, root is in **Bedroom 2**, and the
mesh naturally forms **two branches**: one into Bedroom 1, one down through the Family Hall
to the Master's Bedroom.

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

 Branches:  ROOT ┬─► COM26 ─► COM27                 (Bedroom 1 branch)
            Bed 2└─► COM25 ─► COM22 ─► COM21         (Family Hall → Master's branch)
```

Which board goes where:
- **Bedroom 2 — COM20 (root)** on the laptop; the trunk of the tree.
- **Bedroom 1 — COM26 + COM27**, one branch. Kept **in the same room** because they're
  Node A ↔ Node B in the wormhole run and need a short cable between them — so the same
  placement serves all three runs.
- **Family Hall — COM25 + COM22**, the head of the second branch.
- **Master's Bedroom — COM21**, hanging off the Family-Hall branch (the deepest node).

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

### 🔑 Placement rules
- ✅ **Two branches of depth.** If every board ends up a *direct* child of the root, you've
  accidentally built a **star**, not a tree. Push COM21 (Master's) and COM22 (far side of
  the Family Hall) a bit **further** so they attach *through* a parent, not straight to root.
- ✅ **Every board must hear a parent.** If one won't join, move it **closer** to the board
  above it in the branch.
- ✅ **Tape it down** — you'll reuse this exact layout for all three runs.
- ⚠️ Mesh is on **channel 11**; if it keeps dropping, set `MESH_CHANNEL` to 1 or 6 in
  `mesh_config.h` and re-flash.

> 😌 **Good news:** tree self-heals better than linear, so small placement imperfections are
> forgiven. This is the layout most likely to give you textbook-clean signatures.

---

## 🔁 The reusable 6-phase workflow

Work from the repo root every time:
```powershell
cd "C:\Users\Angelo Calpoporo\CLionProjects\NIS16-ESP32-Environment"
```

| Phase | What you do | Laptop? |
|---|---|---|
| **1. Prep** | (once) set target; (wormhole only) wire + test the A↔B cable | 🔌 |
| **2. Flash children** | plug in each child, flash, `Ctrl+]`, unplug — **one at a time** | 🔌 |
| **3. Place & power** | boards on their branches, power from banks, let the mesh form | 🔋 |
| **4. Boot root LAST** | flash root on the laptop → clock starts → **leave monitor open** | 🔌 |
| **5. Watch & wait** | scenes roll by (~8 or ~11 min); don't touch anything | 🔋 |
| **6. Export** | plug each board back in, one at a time, pull its CSV | 🔌 |

*(We flash **without** `-Export` because your boards live on power banks; you export by hand in Phase 6.)*

---

## ⚡ Export + analyze order  ·  🎯 M4 repeats (read once)

**You export and analyze by hand** — the Phase 4 root command carries no `-Analyze`. Because
the children live on power banks, the order is simply:
1. Boot the root **last** → watch to **terminate** → `Ctrl+]` (this only closes the monitor).
2. Export the **5 children** over USB (`export_logs.py … --repeat <N>`), one at a time.
3. Export the **root** — `--role root` pulls `telem` **and** `arrivals`.
4. **Confirm all 7 files are present**, then run M6→M7→M8 → `analysis/<attack>/tree_topology/`.
> ✅ Nothing fires on `Ctrl+]`, so the root's exit is **no longer order-critical** — and you
> verify the folder is complete *before* analyzing, which `-Analyze` could never do.
> Full commands: [**Manual route without auto analyze**](#-manual-route-without-auto-analyze).

**🎯 M4:** each ATTACK (blackhole + wormhole) needs **3 repeats** (r1/r2/r3) for the 24-run
matrix; baseline is the control (not counted). Bump `-Repeat`/`--repeat` `1`→`2`→`3` each
repeat, **don't archive between repeats** (they pool in the same folder), and after each
attack repeat run `python tools\run_matrix.py --record --topology tree --attack <attack> --repeat <N>`.
Track with `python tools\run_matrix.py --status`.

---

## 🛠️ Manual route without auto analyze

Prefer to export and analyze by hand? **Drop `-Analyze` from the Phase 4 root command.**
Nothing is lost — the root still records normally.

**Why:** with `-Analyze`, the analysis fires the moment you press `Ctrl+]` and runs over
whatever CSVs are in the folder *at that instant* — so a dead monitor, a failed child export,
or an early `Ctrl+]` silently produces an analysis of an incomplete run. Manual lets you check
the folder first. Full detail:
[**Manual route (shared reference)**](LINEAR-RUNBOOK.md#-manual-route-without-auto-analyze)

> 🔌 **A COM number identifies the USB SOCKET, not the board** — these CP210x bridges report
> duplicate/blank serials, so Windows assigns COM per socket. Move a board to another socket
> and its COM changes. Always run `python board_check.py --list` before flashing/exporting,
> and use `--label nodeN` on exports so filenames stay meaningful if several boards share one
> COM. Node numbers: node1=COM20 (root), node2=COM21, node3=COM22, node4=COM25,
> node5=COM26 (attacker), node6=COM27.
> Full detail: [**COM ports, boards, and --label**](LINEAR-RUNBOOK.md#-com-ports-boards-and---label)

> ✂️ **Trim before you analyze — this is NOT automatic, you type it.** Each exported CSV holds
> several boot sessions (Phase-2 flash + the run + the reboot caused by plugging in to export).
> The trailing session logs at `layer = -1`, which makes `verify_topology` read the *final*
> layer as disconnected and WARN on a perfectly good chain, and `validate_integrity` FAIL on
> the timestamp regression. `trim_run.py` keeps only the run. Dry run first (writes nothing),
> then `--apply` (writes copies to `trimmed\`, raw untouched).
> Full detail: [**Trimming exports before analysis**](LINEAR-RUNBOOK.md#-trimming-exports-before-analysis)

```powershell
# Phase 4 — boot root, no -Analyze  (attack runs keep -Repeat <N>)
.\run.ps1 -Port COM20 -Role root -Label node1 -Topology tree -Wipe -Flash
```

`Ctrl+]` now just closes the monitor, so **it no longer has to be last.** Export the root by
hand — `--role root` pulls **both** `telem` and `arrivals`:

```powershell
cd tools
python export_logs.py --port COM20 --role root --label node1 --topology tree --attack none --repeat 1
cd ..
```

**Check the folder before analyzing** — this is the step `-Analyze` skips:

```powershell
Get-ChildItem tools\exports\baseline\tree_topology
python tools\trim_run.py tools\exports\baseline\tree_topology             # dry run: lists boot sessions
python tools\trim_run.py tools\exports\baseline\tree_topology --apply     # -> ...\tree_topology\trimmed\ (raw untouched)
(Get-ChildItem tools\exports\baseline\tree_topology\trimmed\*.csv).Count   # MUST be 7 — a short count silently NaNs out PDR/latency
Get-Content tools\exports\baseline\tree_topology\trimmed\*_arrivals.csv -TotalCount 1   # MUST list src_mac,seq_num
```

Expect **7 files**: 5 child `_telem.csv` + the root's `_telem.csv` and `_arrivals.csv`. Anything
missing → re-export it now.

**Then run M6 → M7 → M8** (identical to `run.ps1:399, 408, 419`, just typed out):

```powershell
cd analysis
python preprocess.py ..\tools\exports\baseline\tree_topology\trimmed -o baseline\tree_topology\windowed_dataset.csv
python features.py   ..\tools\exports\baseline\tree_topology\trimmed -o baseline\tree_topology\feature_table.csv
python eda.py        baseline\tree_topology\feature_table.csv -o baseline\tree_topology\eda_output
cd ..
```

Swap **both** `baseline` → `blackhole` / `wormhole` for attack runs. All three steps only read
`tools\exports\…` and overwrite their outputs, so they're safe to re-run any time.

> ⚠️ `python` here must have pandas/numpy/matplotlib/seaborn/scipy/scikit-learn. The ESP-IDF
> shell's python often doesn't — `run.ps1` auto-scans for a good interpreter, typing by hand
> does not. On `ModuleNotFoundError`: `pip install -r analysis\requirements.txt`.

---

## 🎯 When to press Ctrl+] and how to repeat

Two things that are easy to get silently wrong. Full detail in the shared reference:
[**When to press Ctrl+]**](LINEAR-RUNBOOK.md#-when-to-press-ctrl) ·
[**Doing repeat 2 and 3**](LINEAR-RUNBOOK.md#-doing-repeat-2-and-3)

### `Ctrl+]` on a Phase 2 child

🟢 **Green text is NOT the cue.** In `idf.py monitor`, green just means `ESP_LOGI` (info), so
it's on screen constantly. The one green line `run.ps1` prints (`Monitor closed - run only…`)
appears **after** you press `Ctrl+]` — that's confirmation, not a cue.

Let the flash finish (`Hash of data verified.`, then the board resets and boot logs scroll),
then wait for that board's **last `task running` line**:

| Board / role | Cue → then `Ctrl+]` |
|---|---|
| Plain child | `Telemetry task running at <n> ms interval.` |
| Blackhole **attacker** | `Relay task running.` → `Telemetry task running…` |
| Blackhole **victim** | `Blackhole victim mode: probes -> attacker b0:cb:…` → `Telemetry task running…` |
| Wormhole **end B** (entry) | `Tunnel forwarder running.` → `Telemetry task running…` |
| Wormhole **end A** (exit) | `Re-inject task running.` → `Telemetry task running…` |

⚠️ Ignore the cyan banner's *"Ctrl+] when it reaches 'terminate'"* — that text is for the
**root** (Phase 4). A Phase 2 child never reaches `terminate`; there's no root broadcasting
phases yet, so you'd wait forever.

### Repeat 2 / 3 — what to redo

**The ROOT is the start button.** The phases are broadcast by the root, so *"run the phases
again" = boot the root again* — that's **Phase 4**, and it's the **only** board you flash on a
repeat. You re-enter the runbook at **Phase 3**, so the repeat loop is **3 → 4 → 5 → 6 → 7 → 8**.

⚠️ **Power-cycle all 5 children first.** After `terminate` a child calls `csv_logger_close()`
and drops into export-only mode (`child_node/main/victim_main.c:95-104`) — **a child that isn't
rebooted records nothing in r2.** Unplug/replug each one where it sits, wait ~30–60 s for the
mesh, *then* flash the root with `-Repeat 2`.

🚨 Every board appends to **one fixed `/spiffs/telem.csv`**, and the rows carry **no run-id**.
A child that isn't cleared makes r2's export contain **r1 + r2 fused, inseparably.**

**Clearing is mandatory. Re-flashing the children is not** — firmware survives power-cycles.

- ✅ **Easiest:** add **`--delete`** to every Phase 6 child export. Then r2 =
  **power-cycle the 5 children where they sit → re-flash only the root (`-Wipe -Flash -Analyze`)
  → export with `--repeat 2`.** Phases 1 and 2 are skipped entirely.
- 🅱️ Already exported r1 *without* `--delete`? Clear each child first:
  `python tools\export_logs.py --port COMxx --wipe` (keeps firmware), then resume at Phase 3.
- ❌ **Never go back to Phase 1** — `set-target` is once ever.
- 🔧 The **root** must be `-Wipe -Flash`'d every repeat (it stacks `telem.csv` *and* `arrivals.csv`).

#### 🧹 How the children get cleared without re-flashing

Clearing a child is a **serial command, not a flash** — every board runs a `DELETE_LOGS`
listener from boot (`run.ps1:173-174`), so the firmware stays put.

| Board | Cleared by | Re-flash? |
|---|---|---|
| **Root** | `-Wipe -Flash` in Phase 4 | ✅ every repeat |
| **Children** | `--delete` on the Phase 6 export (or `--wipe` later) | ❌ **no** |

`--delete` erases only **after a successful download** (`export_logs.py:488`), so a failed
export never costs you data.

💡 **This makes the repeat almost free:** you already carry each child to the laptop for Phase 6,
so `--delete` costs zero extra trips. Export with `--delete` → walk it back to its room →
**leave it UNPLUGGED** until you're ready to start the next repeat.

### 🚨 Carry the children back — but DON'T power them on until you're ready

**The easiest way to silently poison a repeat, and it cannot be cleaned up afterwards.**

A child logs from the moment it boots. Before any root broadcast reaches it, its rows are stamped
`PHASE_ID_BASELINE` / `GT_LABEL_BASELINE` (`phase_listener.c:33-34`) — **benign** — with
`layer = -1` (disconnected). The budget for that is the **~30–60 s** of mesh re-forming before you
flash the root. But plug the children in at the end of Phase 6 and *then* run Phase 7 + 8 (root
export → trim → M6/M7/M8 → verify → record) and that is **many minutes**, all logged as benign.

Unlike the trailing-session rows Phase 7b trims away, this one cannot be fixed in post:

| | |
|---|---|
| `trim_run.py` | ❌ **cannot** split it. Splitting needs a **timestamp regression** = a reboot. A board powered continuously from Phase 6 into the run never reboots, so idle rows and run rows are **one unbroken session**. |
| `preprocess.py` | ❌ **won't** drop it. "Rows dropped (contaminated)" counts only malformed rows (UART log lines interleaved during export). `layer = -1` rows are well-formed and survive into `windowed_dataset.csv` — verified. |
| Net result | Benign-class windows that were never part of any run, indistinguishable from real baseline. |

✅ **The safe order:** Phase 6 export with `--delete` → carry each child back, **unplugged** →
Phase 7 + 8 at your own pace → **only then** plug all 5 in, wait ~30–60 s, and go to Phase 4 with
the new `-Repeat` number.

> 💡 You can defer the Phase 7c analysis — it only reads `tools\exports\…` and overwrites its own
> outputs, so it re-runs any time. But confirm the **7 files are present** and the arrivals header
> lists `src_mac,seq_num` before starting the next repeat, so a broken r1 doesn't cost you r2 too.

🆘 **The one case you'd re-flash a child:** a crash-looping or storage-full board never reaches the
serial listener, so only a bootloader-level erase (`-Wipe -Flash`, `run.ps1:165-172`) reaches it.
Symptom: `fprintf failed` spam or a failure to open its log file.
- 🔢 Bump the repeat number in **three** places and keep them matching: the root's `-Repeat <N>`
  (Phase 4), `--repeat <N>` on every child export (Phase 6), and `--repeat <N>` on `--record`.

---

# ▶️ RUN A — BASELINE (tree)

### Phase 1 — Prep (once ever)
```powershell
cd root_node;  idf.py set-target esp32
cd ..\child_node;  idf.py set-target esp32
cd ..
```

### Phase 2 — Flash the 5 children (one at a time → `Ctrl+]` → unplug → next)
Wait for **`Telemetry task running at <n> ms interval.`** on each board before `Ctrl+]`
([why](#-when-to-press-ctrl-and-how-to-repeat)). ⏭️ **Skip this phase on r2/r3.**
```powershell
.\run.ps1 -Port COM20 -Role child -Label node5 -Topology tree -Wipe -Flash
.\run.ps1 -Port COM20 -Role child -Label node6 -Topology tree -Wipe -Flash
.\run.ps1 -Port COM20 -Role child -Label node4 -Topology tree -Wipe -Flash
.\run.ps1 -Port COM20 -Role child -Label node3 -Topology tree -Wipe -Flash
.\run.ps1 -Port COM20 -Role child -Label node2 -Topology tree -Wipe -Flash
```

### Phase 3 — Place & power
Put the 5 children on their branches (diagram above), power each from a bank, wait ~30–60 s.

### Phase 4 — Boot the root LAST
```powershell
.\run.ps1 -Port COM20 -Role root -Label node1 -Topology tree -Wipe -Flash
```
Leave the monitor open; watch for `[CTRL] Waiting 60 s for mesh to stabilise...`.

### Phase 5 — Watch & wait (~8 min)
`stabilise → baseline (0) → cooldown (0) → terminate`.

### Phase 6 — `Ctrl+]` + unplug the ROOT, then export the 5 CHILDREN
At `terminate`, press **`Ctrl+]`** — it only closes the monitor, nothing fires, nothing is lost —
then **unplug the root**. Every board claims COM20, so the root must be off the port before a
child can enumerate ([**USB port convention**](#-usb-port-convention--read-first)); its CSVs are
already closed on SPIFFS. Now export the children, one at a time:
```powershell
cd tools
python export_logs.py --port COM20 --role child --label node5 --topology tree --attack none --repeat 1 --delete
python export_logs.py --port COM20 --role child --label node6 --topology tree --attack none --repeat 1 --delete
python export_logs.py --port COM20 --role child --label node4 --topology tree --attack none --repeat 1 --delete
python export_logs.py --port COM20 --role child --label node3 --topology tree --attack none --repeat 1 --delete
python export_logs.py --port COM20 --role child --label node2 --topology tree --attack none --repeat 1 --delete
cd ..
```
> 🚨 **Carry each board back to its room but leave it UNPLUGGED.** A child powered
> now logs benign `layer = -1` rows all the way through Phase 7/8 — and those
> **cannot be trimmed out afterwards** (no reboot = no timestamp regression to split on).
> Plug them in only when you're ready for the next repeat: [why](#-carry-the-children-back--but-dont-power-them-on-until-youre-ready).

Now plug the **root** back in, alone — with the 5 children powered off, or it may not answer.
`--role root` pulls telem **and** arrivals. Then analyze by hand:
```powershell
cd tools
python export_logs.py --port COM20 --role root --label node1 --topology tree --attack none --repeat 1
cd ..
Get-ChildItem tools\exports\baseline\tree_topology      # expect 7 files BEFORE analyzing
python tools\trim_run.py tools\exports\baseline\tree_topology             # dry run: lists boot sessions
python tools\trim_run.py tools\exports\baseline\tree_topology --apply     # -> ...\tree_topology\trimmed\ (raw untouched)
(Get-ChildItem tools\exports\baseline\tree_topology\trimmed\*.csv).Count   # MUST be 7 — a short count silently NaNs out PDR/latency
Get-Content tools\exports\baseline\tree_topology\trimmed\*_arrivals.csv -TotalCount 1   # MUST list src_mac,seq_num
cd analysis
python preprocess.py ..\tools\exports\baseline\tree_topology\trimmed -o baseline\tree_topology\windowed_dataset.csv
python features.py   ..\tools\exports\baseline\tree_topology\trimmed -o baseline\tree_topology\feature_table.csv
python eda.py        baseline\tree_topology\feature_table.csv -o baseline\tree_topology\eda_output
cd ..
```

### ✅ Verify
```powershell
cd tools; python validate_integrity.py exports\baseline\tree_topology\trimmed; python verify_topology.py --dir exports\baseline\tree_topology\trimmed --topology tree --attack none --repeat 1 --expect tree; cd ..
```
Good = every board records the full run, all rows labelled `0`, steady arrivals at root, no gaps/dupes.

---

# ▶️ RUN B — BLACKHOLE (tree)

COM26 = the packet-swallowing relay; COM27/COM25/COM22/COM21 = victims that send to it.
**No cable, no MAC editing** (`BLACKHOLE_ATTACKER_MAC` already = COM26 `b0:cb:d8:f3:32:18`).
**Same placement as Baseline.**

### Phase 2 — Flash children
`Ctrl+]` each board on its `↳` line **plus** `Telemetry task running…`
([cue table](#-when-to-press-ctrl-and-how-to-repeat)). ⏭️ **Skip this phase on r2/r3.**
```powershell
Remove-Item -Recurse -Force child_node\build_* -ErrorAction SilentlyContinue
.\run.ps1 -Port COM20 -Role child -Label node5 -Attack blackhole -BlackholeRole attacker -Topology tree -Wipe -Flash
#   ↳ "BLACKHOLE ATTACKER (relay) STARTING" + STA MAC = b0:cb:d8:f3:32:18
.\run.ps1 -Port COM20 -Role child -Label node6 -Attack blackhole -BlackholeRole victim -Topology tree -Wipe -Flash
#   ↳ "Blackhole victim mode: probes -> attacker b0:cb:d8:f3:32:18"
.\run.ps1 -Port COM20 -Role child -Label node4 -Attack blackhole -BlackholeRole victim -Topology tree -Wipe -Flash
.\run.ps1 -Port COM20 -Role child -Label node3 -Attack blackhole -BlackholeRole victim -Topology tree -Wipe -Flash
.\run.ps1 -Port COM20 -Role child -Label node2 -Attack blackhole -BlackholeRole victim -Topology tree -Wipe -Flash
```

### Phase 3 — Place & power (same positions as Baseline)

### Phase 4 — Boot root LAST
```powershell
Remove-Item -Recurse -Force root_node\build_* -ErrorAction SilentlyContinue
.\run.ps1 -Port COM20 -Role root -Label node1 -Attack blackhole -Topology tree -Wipe -Flash -Repeat 1
```

### Phase 5 — Watch & wait (~11 min)
`stabilise → baseline (0) → blackhole (1) → cooldown (0) → terminate`.

### Phase 6 — `Ctrl+]` + unplug the ROOT, then export the 5 CHILDREN
At `terminate`, press **`Ctrl+]`** — it only closes the monitor, nothing fires, nothing is lost —
then **unplug the root**. Every board claims COM20, so the root must be off the port before a
child can enumerate ([**USB port convention**](#-usb-port-convention--read-first)); its CSVs are
already closed on SPIFFS. Now export the children, one at a time:
```powershell
cd tools
python export_logs.py --port COM20 --role child --label node5 --topology tree --attack blackhole --repeat 1 --delete
python export_logs.py --port COM20 --role child --label node6 --topology tree --attack blackhole --repeat 1 --delete
python export_logs.py --port COM20 --role child --label node4 --topology tree --attack blackhole --repeat 1 --delete
python export_logs.py --port COM20 --role child --label node3 --topology tree --attack blackhole --repeat 1 --delete
python export_logs.py --port COM20 --role child --label node2 --topology tree --attack blackhole --repeat 1 --delete
cd ..
```
> 🚨 **Carry each board back to its room but leave it UNPLUGGED.** A child powered
> now logs benign `layer = -1` rows all the way through Phase 7/8 — and those
> **cannot be trimmed out afterwards** (no reboot = no timestamp regression to split on).
> Plug them in only when you're ready for the next repeat: [why](#-carry-the-children-back--but-dont-power-them-on-until-youre-ready).

Now plug the **root** back in, alone — with the 5 children powered off, or it may not answer.
`--role root` pulls telem **and** arrivals. Then analyze by hand:
```powershell
cd tools
python export_logs.py --port COM20 --role root --label node1 --topology tree --attack blackhole --repeat 1
cd ..
Get-ChildItem tools\exports\blackhole\tree_topology      # expect 7 files BEFORE analyzing
python tools\trim_run.py tools\exports\blackhole\tree_topology             # dry run: lists boot sessions
python tools\trim_run.py tools\exports\blackhole\tree_topology --apply     # -> ...\tree_topology\trimmed\ (raw untouched)
(Get-ChildItem tools\exports\blackhole\tree_topology\trimmed\*.csv).Count   # MUST be 7 — a short count silently NaNs out PDR/latency
Get-Content tools\exports\blackhole\tree_topology\trimmed\*_arrivals.csv -TotalCount 1   # MUST list src_mac,seq_num
cd analysis
python preprocess.py ..\tools\exports\blackhole\tree_topology\trimmed -o blackhole\tree_topology\windowed_dataset.csv
python features.py   ..\tools\exports\blackhole\tree_topology\trimmed -o blackhole\tree_topology\feature_table.csv
python eda.py        blackhole\tree_topology\feature_table.csv -o blackhole\tree_topology\eda_output
cd ..
```

### ✅ Verify + record this repeat (M4) — "disappearing packets"
```powershell
cd tools; python verify_topology.py --dir exports\blackhole\tree_topology\trimmed --topology tree --attack blackhole --repeat 1 --expect tree; cd ..
python tools\run_matrix.py --record --topology tree --attack blackhole --repeat 1
```
> 🔁 Bump `-Repeat`/`--repeat` `1`→`2`→`3` for r2/r3; don't clear the folder between repeats.
- **Root `arrivals.csv`:** each victim present at `gt_label=0`, **gap during `gt_label=1`**, back at cooldown.
- **Attacker COM26 `telem.csv`:** `tx_count` **flat during label 1**, `retry_count` (dropped) **climbs**.
- **Victim `telem.csv`:** `probes_count` climbs steadily throughout.

---

# ▶️ RUN C — WORMHOLE (tree)

COM26 = Node A, COM27 = Node B, joined by a **physical wire**; COM25/COM22/COM21 = plain
controls. **Only this run needs the A↔B cable** — same board positions, just add the cable
between the two boards in **Bedroom 1**.

### Phase 1 — Wire + TEST the A↔B cable (before anything else)
Wire **COM26 ↔ COM27**, crossed, 3 wires:

| COM26 (A) | → | COM27 (B) |
|---|---|---|
| GPIO 17 (TX) | ──► | GPIO 16 (RX) |
| GPIO 16 (RX) | ◄── | GPIO 17 (TX) |
| GND | ── | GND |

(WROVER/PSRAM boards: GPIO16/17 are taken — change `WORMHOLE_UART_TX_PIN`/`_RX_PIN` in
`mesh_config.h` to a free pair like 4/5 and wire those.) Cable stays on the **whole run**,
never touches the laptop. **Then test it:**
```powershell
cd uart_link_test
idf.py set-target esp32          # once
idf.py -p COM26 flash monitor    # Ctrl+] at the banner
idf.py -p COM27 flash monitor    # WATCH this one → want [LINK OK]
cd ..
```
`[LINK OK]` = good. `RX received=0` = bad wire (fix GND / crossing).

### Phase 2 — Flash boards (opposite `-WormholeEnd`!)
`Ctrl+]` each board on its `↳` line **plus** `Telemetry task running…`
([cue table](#-when-to-press-ctrl-and-how-to-repeat)). ⏭️ **Skip this phase on r2/r3.**
```powershell
.\run.ps1 -Port COM20 -Role child -Label node5 -Attack wormhole -WormholeEnd A -Topology tree -Wipe -Flash
.\run.ps1 -Port COM20 -Role child -Label node6 -Attack wormhole -WormholeEnd B -Topology tree -Wipe -Flash
.\run.ps1 -Port COM20 -Role child -Label node4 -Topology tree -Wipe -Flash    # plain control
.\run.ps1 -Port COM20 -Role child -Label node3 -Topology tree -Wipe -Flash    # plain control
.\run.ps1 -Port COM20 -Role child -Label node2 -Topology tree -Wipe -Flash    # plain control
```

### Phase 3 — Place & power (same positions; keep the A↔B cable connected in Bedroom 1)

### Phase 4 — Boot root LAST
```powershell
.\run.ps1 -Port COM20 -Role root -Label node1 -Attack wormhole -Topology tree -Wipe -Flash -Repeat 1
```

### Phase 5 — Watch & wait (~11 min)
`stabilise → baseline (0) → wormhole (2) → cooldown (0) → terminate`. During attack, Node B
prints `Tunnelled probe ... via UART`, Node A prints `Re-injected probe ...`.

### Phase 6 — `Ctrl+]` + unplug the ROOT, then export the 5 CHILDREN
At `terminate`, press **`Ctrl+]`** — it only closes the monitor, nothing fires, nothing is lost —
then **unplug the root**. Every board claims COM20, so the root must be off the port before a
child can enumerate ([**USB port convention**](#-usb-port-convention--read-first)); its CSVs are
already closed on SPIFFS. Now export the children, one at a time:
```powershell
cd tools
python export_logs.py --port COM20 --role child --label node5 --topology tree --attack wormhole --repeat 1 --delete
python export_logs.py --port COM20 --role child --label node6 --topology tree --attack wormhole --repeat 1 --delete
python export_logs.py --port COM20 --role child --label node4 --topology tree --attack wormhole --repeat 1 --delete
python export_logs.py --port COM20 --role child --label node3 --topology tree --attack wormhole --repeat 1 --delete
python export_logs.py --port COM20 --role child --label node2 --topology tree --attack wormhole --repeat 1 --delete
cd ..
```
> 🚨 **Carry each board back to its room but leave it UNPLUGGED.** A child powered
> now logs benign `layer = -1` rows all the way through Phase 7/8 — and those
> **cannot be trimmed out afterwards** (no reboot = no timestamp regression to split on).
> Plug them in only when you're ready for the next repeat: [why](#-carry-the-children-back--but-dont-power-them-on-until-youre-ready).

*(Controls COM25/COM22/COM21 with `--attack wormhole` file with this run — correct.)*
Now plug the **root** back in, alone — with the 5 children powered off, or it may not answer.
`--role root` pulls telem **and** arrivals. Then analyze by hand:
```powershell
cd tools
python export_logs.py --port COM20 --role root --label node1 --topology tree --attack wormhole --repeat 1
cd ..
Get-ChildItem tools\exports\wormhole\tree_topology      # expect 7 files BEFORE analyzing
python tools\trim_run.py tools\exports\wormhole\tree_topology             # dry run: lists boot sessions
python tools\trim_run.py tools\exports\wormhole\tree_topology --apply     # -> ...\tree_topology\trimmed\ (raw untouched)
(Get-ChildItem tools\exports\wormhole\tree_topology\trimmed\*.csv).Count   # MUST be 7 — a short count silently NaNs out PDR/latency
Get-Content tools\exports\wormhole\tree_topology\trimmed\*_arrivals.csv -TotalCount 1   # MUST list src_mac,seq_num
cd analysis
python preprocess.py ..\tools\exports\wormhole\tree_topology\trimmed -o wormhole\tree_topology\windowed_dataset.csv
python features.py   ..\tools\exports\wormhole\tree_topology\trimmed -o wormhole\tree_topology\feature_table.csv
python eda.py        wormhole\tree_topology\feature_table.csv -o wormhole\tree_topology\eda_output
cd ..
```

### ✅ Verify + record this repeat (M4) — "double vision"
```powershell
cd tools; python verify_topology.py --dir exports\wormhole\tree_topology\trimmed --topology tree --attack wormhole --repeat 1 --expect tree; cd ..
python tools\run_matrix.py --record --topology tree --attack wormhole --repeat 1
```
> 🔁 Bump `-Repeat`/`--repeat` `1`→`2`→`3` for r2/r3; don't clear the folder between repeats.
- **Root `arrivals.csv`:** during `gt_label=2`, each of Node B's probes appears **TWICE**
  (same `src_mac`+`seq_num`, different `latency_us`); **once** during `gt_label=0`.
- **Node B (COM27):** `retry_count` (tunnelled) climbs **only during label 2**; `tx_count` all run.
- **Node A (COM26):** `probes_count` + `tx_count` climb **only during label 2**, else `0`.
- `CRC mismatch` / `bad magic` in a monitor = loose/mis-crossed cable.

---

## 🃏 One-glance command card (tree)

| Run | Children (COM26 / COM27 / COM25 / COM22 / COM21) | Root (COM20, LAST) | Export `--attack` | Extra |
|---|---|---|---|---|
| **Baseline** | all `-Topology tree` | `-Role root -Topology tree` | `none` | — |
| **Blackhole** | COM26 `-Attack blackhole -BlackholeRole attacker`; COM27/COM25/COM22/COM21 `-Attack blackhole -BlackholeRole victim` | `-Attack blackhole` | `blackhole` | — |
| **Wormhole** | COM26 `-Attack wormhole -WormholeEnd A`; COM27 `-Attack wormhole -WormholeEnd B`; COM25/COM22/COM21 plain | `-Attack wormhole` | `wormhole` | 🔌 A↔B cable + `[LINK OK]` |

All flash commands carry `-Wipe -Flash`. Root **always boots last**. Verify with `--expect tree`.

---

## 🆘 Troubleshooting → see the shared table in [`LINEAR-RUNBOOK.md`](LINEAR-RUNBOOK.md#-quick-troubleshooting).
Tree-specific: if every board becomes a **direct** child of the root (looks like a star),
push COM21 (Master's) and COM22 (far Family Hall) **further out** so they attach through a
parent, then re-run.

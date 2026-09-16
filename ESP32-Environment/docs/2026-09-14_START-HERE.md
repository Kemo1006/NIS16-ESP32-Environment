# START HERE - Combined Project Guide (v2026-09-14)

> **Forgot how the project works? Read this page top to bottom once.** It's the map to
> everything else. Every other doc is dated `2026-09-14` = current. Anything without that
> date, or under `_archive/`, is the OLD workflow - ignore it for new runs.

---

## 1. What this project IS (the 30-second refresher)

We built a small **ESP32 Wi-Fi mesh network** (the ESP-WIFI-MESH protocol). A bunch of
little ESP32 boards form a self-organizing mesh: one **root** collects data, the rest are
**victims** (normal nodes that send "probe" packets to the root). We then run **two attacks**
on that mesh and record what happens, to build a **labeled dataset** for exploratory
analysis / clustering.

- **Blackhole attack** = one board becomes an "attacker" relay. Victims send probes through
  it. During the attack window it **silently drops** them, so they never reach the root.
- **Wormhole attack** = two attacker boards (A and B) linked by a **wired UART cable** (an
  out-of-band "tunnel"). Node B secretly tunnels a copy of each probe to Node A, which
  re-injects it, so the root receives the **same probe twice** with a timing mismatch.

Every board logs telemetry to a CSV, tagged with a **ground-truth label**:
`0 = baseline/normal`, `1 = blackhole`, `2 = wormhole`. That labeled CSV is the dataset.

**Our current job (Sept 2026):** the panel told us to **redo all runs** with more realism -
a defined scenario, variation between runs, and paper-backed verification. See
`docs/2026-09-14_SETUP-RULES-CONFIG.md` Part B for the rules. Old data is archived.

## 2. The mental model of one "run"

Every run is one board per role, all powered at once, going through a fixed timeline that
the **root broadcasts** to everyone over the mesh:

```
 [ 60s stabilize ] -> [ 300s BASELINE (label 0) ] -> [ 180s ATTACK (label 1 or 2) ] -> [ 120s COOLDOWN (label 0) ] -> terminate
   mesh forms          normal traffic                 attacker misbehaves               back to normal              logs ready to pull
```
- Baseline-only run (no attack) skips the attack phase: **~8 minutes** total.
- Attack run (blackhole or wormhole): **~11 minutes** total.
- You do NOT start the boards in sync by hand. Each board runs on its own the moment it
  boots; the root's wireless phase broadcasts keep everyone's label in sync.

## 3. Before you touch a board (one-time per laptop)

1. Open the **"ESP-IDF 5.3 PowerShell"** shortcut (NOT plain PowerShell/cmd). Everything
   below is typed there.
2. Set the chip target once per project (replace `<repo>` with wherever you cloned this
   folder, e.g. `C:\Thesis\combined\ESP32-Environment`):
   ```powershell
   cd "<repo>\root_node"
   idf.py set-target esp32
   cd "..\child_node"
   idf.py set-target esp32
   ```
3. Install the analysis Python deps once (for the `-Analyze` / EDA step):
   ```powershell
   pip install -r analysis\requirements.txt
   ```

## 4. The easy way to drive everything: the menu

```powershell
cd "<repo>"
.\menu.ps1
```
It asks you questions (type a number, Enter) and builds the right command for you - no more
long flag strings. If PowerShell blocks it, run `Set-ExecutionPolicy -Scope Process -Bypass`
once in that window, then `.\menu.ps1` again.

The menu can: **run a board**, **run MULTIPLE boards in parallel** (one ESP-IDF window
per board, pre-built so they don't cold-compile at the same time, children flashed
before the root), **export a board**, **wipe/erase a board**, **identify a board**,
**verify a run** (paper-backed 3-sigma check). The old long form
(`.\run.ps1 -Port COM8 -Role root ...`) still works if you prefer it - the menu just prints
the equivalent command so you learn it.

**Saved rosters across repeats, MAC-drift verification, bulk set-location on many
boards, or a firmware self-test**? Use `.\run_wizard.ps1` instead - it is built for
that maintenance workflow; `menu.ps1`'s multi-board option is the simpler on-ramp for
just launching a run.

## 5. Which runbook do I open? (pick your run)

| You want to run... | Open this | Boards needed |
|---|---|---|
| Normal / baseline (no attack) | `docs/runbooks/2026-09-14_BASELINE.md` | root + 1+ victim (2 min) |
| **Blackhole** attack | `docs/runbooks/2026-09-14_BLACKHOLE.md` | root + attacker + 1+ victim (3 min) |
| **Wormhole** attack | `docs/runbooks/2026-09-14_WORMHOLE.md` | root + Node A + Node B + UART cable (3 min) |
| Where to place boards for each **topology** | `docs/runbooks/2026-09-14_TOPOLOGIES.md` | - |
| **Verify** a run is real (paper-backed 3-sigma) | `docs/runbooks/2026-09-15_VERIFY.md` | none - no board touched |
| What's different at each **location** (G402/Library/Goks/Home) | `docs/2026-09-14_LOCATIONS.md` | - |
| Setup / rules / all config knobs | `docs/2026-09-14_SETUP-RULES-CONFIG.md` | - |

## 6. Golden rules (memorize these 5)

1. **Flash every board in a run with the SAME topology and SAME attack.** If one disagrees,
   the shaping is wrong and the run is wasted.
2. **Export the ROOT last, with analysis ON.** The root holds `arrivals.csv` (needed for PDR
   and the attack signatures), so analysis must see it last.
3. **Ctrl+] leaves the serial monitor.** The board keeps running; you're just closing the
   viewer. (Ctrl+Break = hard abort of the whole script.)
4. **Identify boards by MAC, not COM number.** COM numbers name the USB socket, not the
   board. Menu -> "Identify a board" before every session.
5. **Make each repeat DIFFERENT** (panel rule). Move the attacker to a new spot and/or run at
   a different time for r1/r2/r3, and write it on the field log. Identical repeats are wasted.

## 7. First run in 6 lines (baseline sanity check with 2 boards)

Do this once to confirm your setup works before the real matrix:
```powershell
.\menu.ps1
#  -> Run a board -> pick the VICTIM's COM -> role: child -> topology: tree
#     -> attack: none -> Flash yes, Wipe yes, Export yes -> pick a location
.\menu.ps1
#  -> Run a board -> pick the ROOT's COM -> role: root -> topology: tree
#     -> attack: none -> Flash yes, Wipe yes, Export yes -> pick the SAME location
#     -> Analyze YES  (root is last)
```
After ~8 min + export, check `analysis\baseline\tree\<location>\feature_table.csv` exists
and has rows. If yes, your pipeline works end-to-end. Full detail: the BASELINE runbook.

## 8. When something goes wrong (quick triage)

| Symptom | Fix |
|---|---|
| `running scripts is disabled` | `Set-ExecutionPolicy -Scope Process -Bypass` then re-run |
| `Could not open COMxx ... Access is denied` | a stale monitor holds the port; `run.ps1` auto-kills it, or unplug/replug the board |
| Board crash-loops / "storage full" / "Failed to open arrivals file" | run with **Wipe = yes + Flash = yes** (full chip erase, self-heals) |
| Wormhole: root sees no duplicates | UART wire wrong - run the loopback test first (WORMHOLE runbook Step 2b) |
| Blackhole: no signature | you didn't set `BLACKHOLE_ATTACKER_MAC` (BLACKHOLE runbook, the box at the top) |
| Analysis skipped ("no pandas") | `pip install -r analysis\requirements.txt`, re-run with Analyze |
| Which board is which? | `.\menu.ps1` -> Identify a board (reads its MAC/node) |

## 9. Where your data ends up

```
tools\exports\<attack>\<topology>\<location>\      raw + trimmed CSVs   (attack = baseline|blackhole|wormhole;
analysis\<attack>\<topology>\<location>\           windowed_dataset.csv, feature_table.csv, eda_output\   topology = star|tree|linear|partial_mesh;
                                                                                                            location = home|G402|DLSU_Library|Goks)
```
SD-card exports land in the same tree via `tools\import_sdcard.py` — see `2026-09-14_SD-CARD.md`.

## 10. Verify a run is REAL before trusting it (paper-backed)

```powershell
python tools\validate_integrity.py     # schema, phase labels, >=95% sample coverage
python tools\verify_topology.py         # parent/layer structure matches the topology you intended
python tools\verify_attack.py analysis\<attack>\<topology>\<location>\feature_table.csv
#   ^ PAPER-BACKED 3-sigma normal-vs-attack test. Auto-detects blackhole/wormhole,
#     prints a per-feature report + CONFIRMED / NOT CONFIRMED, exits 0 if confirmed.

python tools\verify_attack.py analysis\blackhole\linear\home\feature_table.csv
#   ^ copy-paste example - swap blackhole/linear/home for whatever you actually ran
```
`verify_attack.py` is the paper-cited verification the panel asked for (3-sigma normal-vs-attack,
Zhukabayeva et al. 2025): blackhole -> ForwardingRatio/PDR collapse >3 sigma during label 1;
wormhole -> tunnel activity / duplicate-arrival spread >3 sigma during label 2. Run it on every
attack run's `feature_table.csv`. Full walkthrough (reading the report, troubleshooting a
NOT CONFIRMED/INCONCLUSIVE result): `docs/runbooks/2026-09-15_VERIFY.md` and
`docs/2026-09-14_REFERENCES.md`.

---
*Lost? The single most useful command is `.\menu.ps1`. It walks you through everything.*

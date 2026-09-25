# Session report — sep. 25, 2026

**Who this is for:** everyone on the team. No coding knowledge needed.
**CORRECTION (same day):** the first version of this report said the sep. 24 children lost
power before the experiment and that the run must be re-captured. **That was wrong.** The
root's own file proves all six children were alive and sending the whole run (see section 1).
The "empty" files are other boots. **Do NOT re-capture and do NOT wipe any SD card yet** — the
real run files are most likely still on the cards. Sections 1 and 4 are rewritten.

**Short version:** the imported files for five children only contain "phase 255" rows, but they
are not the run — they are later boots. The run's own files were most likely moved into an
`_archive` folder on each card, which the import tool deliberately skips. We fixed the checking
tools so an empty file can no longer pass as data, and added safeguards to the boards (the root
waits for its children; boards record why they rebooted). We also added run logs and a
delete/restore option for GitHub data.

**Status:** all changes are on Basti's laptop and NOT committed or pushed yet. The firmware
changes only take effect after every board is re-flashed. Nothing here has been tested on
real boards yet — see "What is and is not tested" at the bottom.

---

## 1. What actually happened on sep. 24 (G402, blackhole, linear, repeat 1)

### What we first saw
After the run, the imported CSV files from five children were tiny (1 to 8 minutes) and
contained only **"phase 255"** rows. Phase 255 means "this board has not heard the root's
experiment announcements yet". The wizard also listed them as **ABORTED**. It looked like
five boards had lost power before the experiment started.

### What the root's file shows (this is the proof)
The root records every probe it receives from each child. Its file for this run shows:
- **All six children sent one probe per second for the whole run** — baseline, attack and
  cooldown — with no restarts and no missing probes.
- **The blackhole attack worked exactly as designed.** The three children *behind* the
  attacker received nothing during the attack phase; the three in front were unaffected.
  The attacker's own drop counter reads 540 = 3 children x 180 seconds.

So the children were alive and the experiment was a **good one**.

### So what were the "empty" files?
They are **different boots** of the same boards, not the run. Each time a board starts, it
moves the previous boot's CSV files into an `_archive` folder on the SD card and starts a
fresh file. If a board was restarted after the run (moved, re-powered, re-flashed), the new
boot's short file sits on top and **the real run file is now inside `_archive`**. The import
tool intentionally never reads `_archive`, so it only ever saw the short files.

We can prove some of this from the data: the node5 and node6 short files were recorded by
different boots than the ones the root heard, and node3 and the attacker match the root
probe-for-probe.

### What we still do not know
- Whether the run files really are in each card's `_archive` folder (it is the most likely
  explanation but must be checked on the cards).
- Why the boards restarted after the run, if they did. The new reboot-reason recording
  (section 2B) will answer this next time.
- node8 has a complete file from an **earlier** run (13:41) that does not belong to this one.

### What this means for the fixes below
Because the boards were not actually lost, the "root waits for its children" feature
(2A) **would not have changed this run.** It is a sensible safeguard for the future, but it
is not a fix for what happened on sep. 24. The tool fixes (2C, 2D) and the reboot-reason
recording (2B) are still useful.

---

## 2. What we changed to stop this from happening again

### A. The root now WAITS for all children (firmware — needs re-flash)
- After its 60-second settling time, the root checks how many children are in the mesh.
  It will **not** start the experiment until **all** of them have been connected for 5
  seconds in a row.
- While waiting, its monitor prints a line every 10 seconds, for example
  `WAITING: 5/7 children in the mesh`, plus a reminder of the usual causes (unpowered,
  weak powerbank/cable, out of range).
- **If a board is genuinely gone:** type `START_ANYWAY` and press Enter in the root's
  monitor. The run then starts with whoever is there, and the root prints in red that the
  run is SHORT by that many nodes. Say so wherever that data is used.
- **If a child drops out during the run** (powerbank dies, cable knocked out), the root now
  prints a red warning at the start of the baseline, attack and cooldown phases:
  `only 6/7 children in the mesh - 1 dropped out`. It cannot stop the drop-out — it only
  makes sure nobody finds out days later from the CSVs.
- The run wizard supplies the child count automatically. On a **multi-laptop run** it asks
  once: "How many children run on OTHER laptops?" (plain children flashed on another laptop
  are not in your roster, so the wizard cannot count them by itself — please answer
  honestly, or the root will start too early).

### B. Every board now records WHY it last rebooted (firmware — needs re-flash)
Each board's `status_<node>.txt` on its SD card now says the reason for the last boot:
- **POWERON** — plain power-on or unplug/replug (also normal for flashing)
- **BROWNOUT** — the power supply sagged (weak powerbank, charger or cable)
- **PANIC / TASK_WDT / INT_WDT / WDT** — the firmware crashed or froze
- plus two running totals: **Brownout resets** and **Crash resets**, which keep counting
  across any number of reboot loops.

The same word is written as a new last column in `runs.csv`. Old cards still read fine.

### C. The wizard now explains WHY a file is ABORTED (laptop side — works today)
When you import from an SD card and a file is ABORTED, the wizard now prints a reason:
- "ended by a **POWER CUT**" / "ended by a **BROWNOUT**" / "ended by a **CRASH**" (needs the
  new firmware on the boards), or
- "this was the board's **LAST boot** on this card and it ended without closing" (works on today's cards), or
- "the board booted N more times after this file and never logged again — looks like a
  brownout loop (weak powerbank/cable)".

It also marks a file in red as **NO EXPERIMENT DATA** when it only contains phase 255 rows,
so nobody clicks "import anyway" thinking it is a partial run.

### D. The checking tools no longer treat empty files as valid
Before, these files were quietly accepted. Now:
- **Integrity check** (`validate_integrity.py`): a file with no experiment rows is a **FAIL**
  (it used to be only a warning, and the run still "passed"). On the G402 folder: 3 pass,
  8 fail. Also fixed a wrong warning `'child' doesn't match 'child'` that appeared on every file.
- **Analysis** (`preprocess.py`): skips such files and lists them in the report. It also
  fixes a real hazard: when two files exist for the same board, analysis keeps the
  **newest** one and archives the older one. It could have archived node8's only complete
  capture in favour of a later, empty one. It now prefers the file that has data — **but that
  older file may belong to a different run** (node8's does), so analysis now prints a warning
  whenever it does this. Always confirm the file belongs to the run.
- **`analyze.ps1`**: it used to run its steps (trim, preprocess, features, plots) without
  checking whether each one worked, so a failed step could produce plots from the
  *previous* run. Each step is now checked; a failure stops the chain and says so.

---

## 3. Other work this session (not related to the incident)

### Run logs in the wizard (option 8, "View a saved run log")
- Logs are now saved in folders by attack / topology / location / scenario, like the CSVs.
- You can read the **whole** run from start to end, one screen at a time (Enter = next page,
  `a` = the rest, `q` = stop). Error lines show in red.
- For each log you can: keep it, **archive** it (moved to `run_logs\_archive\`, still viewable,
  never uploaded), or **delete** it (permanent, asks first). Old logs saved before this change
  appear under "NOT FILED".
- After a run, the wizard asks whether to push the log to GitHub (default: no).

### GitHub Data sync menu
- Reorganised into headings: capture data, analysis + EDA, run logs, presets, test.
- New: **push / pull run logs**.
- New: **Delete data from GitHub** and **Restore deleted data**.
  - Delete removes the files you pick from GitHub and then asks whether to delete your
    own copies too. You must type `DELETE` to confirm.
  - It is always undoable: GitHub keeps the history, and Restore brings the exact files back.
  - A teammate's next pull or push **asks** them before removing their copy. Nothing is
    deleted automatically. A push will not quietly re-upload something that was deleted.
  - Only files that are on GitHub can be deleted this way.

---

## 4. What we need from you (the members)

1. **Do NOT re-capture this run and do NOT wipe or reuse the SD cards yet.** The real run files
   are most likely in each card's `_archive` folder. Wiping a card would destroy them.
2. **Look inside `_archive`** (folder `blackhole/linear/G402/_archive/` on each child's card).
   Copy any `..._telem.csv` files out and send them, with the card's `runs.csv` and
   `status_NODE_<mac>.txt`. The `runs.csv` says which boot each file belongs to. Match
   children to the run by their probe numbers in the root's file, not by file times.
3. **Do not analyse the G402 blackhole/linear r1 folder yet.** It currently mixes a different
   run (node8's 13:41 file) with this one. Analysis warns when it keeps an older file over a
   newer empty one, but it cannot prove which run a file belongs to.
4. **Once Basti pushes these changes: `git pull` and re-flash EVERY board (root included).**
   The waiting behaviour and the reboot-reason recording are in the firmware.
5. **Before pressing start on any run:** every child must already be on its **final power**
   (powerbank/charger). Moving a board after the root starts will still cut its data short —
   the software can warn about it but cannot prevent a cable being pulled.
6. **On your first run after re-flashing, please test the waiting:** leave one child
   unplugged when the root starts. The root should say `WAITING: n/N` and only start when it
   joins (or when you type `START_ANYWAY`). Please report if it does not.

## 5. Ideas we did not build (for the team to decide)
- Reading the reason a board rebooted straight from the wizard over USB (today it is only on
  the card).
- The same "why was it aborted" explanation in the older `menu.ps1` launcher (only the
  wizard has it).

## 6. What is and is not tested

| Item | Status |
|---|---|
| All 6 firmware variants + a root with the waiting feature on | **Compiled with 0 warnings, 0 errors** (full clean build) |
| Waiting/START_ANYWAY/reboot-reason behaviour on real boards | **NOT tested** — needs a re-flash and a real run |
| Analysis and integrity fixes | Tested on copies of the real G402 files; existing tests pass |
| Import screen "why aborted" text | Tested with fake cards for the three cases (needs the new firmware for BROWNOUT/CRASH wording) |
| Run-log viewer, archive, delete | Tested with fake logs |
| GitHub push / pull / delete / restore of logs | Tested only against a **local stand-in for GitHub**, not the real repo. Please try one throwaway file first. |

## 7. Files changed (for whoever reviews the commit)
Firmware: `mesh_config.h`, `phase_listener.c/.h`, `sd_status.c/.h`, `csv_logger.c`,
`root_node/main/root_main.c`, `root_node/main/CMakeLists.txt`
Launchers: `run.ps1` (new `-ExpectedChildren`), `run_wizard.ps1`, `analyze.ps1`
Host tools: `validate_integrity.py`, `import_sdcard.py`, `analysis/preprocess.py`, `push_data.py`
Repo settings: `.gitattributes`
Team notes: `STATUS.md`, `MEMORY.md`, `ARCHIVE.md`
One stray file, `archive/manifest.json`, was created by a check run and is safe to delete.

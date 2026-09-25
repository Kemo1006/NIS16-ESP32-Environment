# Status

<!-- Overwrite each session. Hard cap: 40 lines — move "done" items to ARCHIVE.md. First thing a new session reads. -->

**Updated:** sep. 25, 2026 — FIRMWARE FIX for the hidden-run bug: no boot-time archiving + `LOG_ONLY_DURING_RUN` (root PREPARE).
**Next: `git pull`, REFLASH EVERY BOARD, one full test run** (unplug a board after SAFE, confirm its run file still lists over USB).

## ⚠️ Working copies
Angelo's laptop: `A:\Angelo\Excelsior\THESIS\T`. Basti's laptop: `C:\Users\Basti\OneDrive\Documents\Thesis\THESIS3`.
Both are clones of GitHub branch `THESIS3` — `git pull` before editing. Old `C:\...\NIS16-ESP32-Environment` = backup only.

## Next step
1. ⛔ **Until a board is reflashed, do NOT unplug/reset it to export** — old firmware moves the run into `_archive/` at boot.
   New firmware (sep. 25): no boot archiving; logs from the root's PREPARE (stabilisation, phase 255) on. NOT hardware-tested.
2. **Recover the sep. 24 + sep. 25 runs by hand:** pulled card → `blackhole\linear\G402\stationary\_archive\` → the large
   `victim_*_telem.csv`. User chose: the wizard shows LIVE data only, never `_archive/`. Match to the run by seq_num vs root.
3. Formation is now timed from the first PREPARE a child hears (it must have joined), not from boot. Say so for Milestone 3.
4. Import a NEW run under a NEW repeat number — same node+repeat as an older import is skipped as a duplicate over USB.
5. ⚠️ **ROOT COVERAGE ≥95% still to re-measure** (`validate_integrity.py`). Then the campaign (`inventory_cells.py --plan`).

## Blockers / open questions
- ⛔⛔ **Boards DIRECT into the laptop, never dock/hub** (BSOD 0xB8). Verify root power. Never pull an SD card mid-run (wait SAFE / END_RUN).
- Dashboard is NOT hardcoded (each board's heartbeat phase + LOG_CLOSED), but "ALL n BOARDS DONE" ignores boards evicted as offline.
- Run logs hold only wizard text — board serial output (`idf.py monitor`) is NOT captured, so logs cannot prove phases.
- ⚠️ **HT20 (D-14):** HT40 captures (before sep. 23) ≠ HT20 — label, don't pool. Mac pcap data frames still not validated.
- ⛔ **D-12 vs the signed Milestone Form** — adviser decision. Pre-C7 captures NOT comparable to post-C7; PDR alone scores 0.9987.
- **Two unreconciled panel tracks:** `Plan/THESIS3-PANEL-PLAN.md` vs `.../memory/panel-change-2026-09.md`. R-A/R-B unwritten.
- ⚠️ **Committed G402 analysis (`88bf3da`) is built from the WRONG boots** — 1677/3479 windows unlabelled. Re-run after recovery.
- ⚠️ **PAPER still behind the code:** 1 Hz / 5 s (Tables 4.4/4.10, §4.2.4.1) — **10 Hz / 1 s is CORRECT (panel+adviser), keep the code**;
  Table 4.5 calls `retry_count`/`tx_count` MAC stats — they are app-layer (**D-15**). Wormhole B retry overload open.

## Recently done (last 3 max, newest first — older entries roll to ARCHIVE.md)
- sep. 25, 2026 — **END_RUN reply found anywhere in a line** (it glued to log output; the "predates END_RUN" message was false),
  "already imported" over USB says node+repeat match / maybe OLDER run; importer no longer advises "reset it". Fake-serial tested.
- sep. 25, 2026 — **Firmware: no boot-time `_archive/` move + `LOG_ONLY_DURING_RUN` + root PREPARE**; verify_topology NOT MEASURED for logs
  starting inside a phase (old data: identical output). NOT committed - the user pushes it.
- sep. 25, 2026 — **Power-cut/crash prevention:** root ROSTER GATE, reset reason + brownout/crash totals on card. Build-verified.

# Status

<!-- Overwrite each session. Hard cap: 40 lines — move "done" items to ARCHIVE.md. First thing a new session reads. -->

**Updated:** sep. 22, 2026 — **CAPTURE DATES ARE REAL** (board now takes its clock from the laptop; `runs.csv` gained `started`/`clock_src`), plus the earlier export overhaul + D-13. **The working copy moved drives** (below). **Newer work UNCOMMITTED.**

## ⚠️ THE WORKING COPY MOVED — read this first
**Work in `A:\Angelo\Excelsior\THESIS\T`.** `C:\...\NIS16-ESP32-Environment` (old C: path) is a BACKUP only —
do not edit it. Reason + verification: MEMORY.md ("WORKING COPY MOVED" entry, sep. 22).

## Current focus
**Export + data-integrity (D-13)**, independent of any milestone/adviser gate. Next: hardware-test on a real board.

## Next step
1. ✅ **HARDWARE-CONFIRMED sep. 22:** live-flag fix (growing file = STILL RUNNING, finished = ABORTED)
   and `DELETE_SD_FILE` (2 deleted over USB; live file correctly refused). **Left: child clean-stop.**
2. ⚠️ **ROOT SAMPLE COVERAGE 93.7% < the 95% M5 floor is now a MILESTONE BLOCKER** — it is the ONLY
   thing keeping blackhole/linear/home off the checklist. Investigate before the campaign.
3. ⚠️ **RE-FLASH EVERY BOARD** — D-13, `LIST_SD`, v2 (F3), F1, F2, C7, hop rename, leaf guards,
   `jitter`, **+ the sep. 22 CLOCK change. All 6 variants verified CLEAN (`-Clean`, 0 warnings) sep. 22.**
   To rebuild: `. C:\Espressif\Initialize-Idf.ps1 -IdfId esp-idf-20ee62e792ea89630ac6a777ab3ebc57` — **`export.ps1` is
   BROKEN here and falsely reports IDF missing** (MEMORY.md → Failed approaches).
4. **Then the campaign** (128 vs 512 — `inventory_cells.py --plan --repeats N`); re-analyse the 8 complete runs.

## Blockers / open questions
- ⛔⛔ **LAPTOP BSODs (0xB8) ON USB BOARD I/O — THE DOCK.** **Plug boards DIRECT, never the dock/hub.** MEMORY.md.
- ⛔ **D-12 vs the signed Milestone Form** — adviser decision, not ours. See Next step 1.
- ⚠️ **Pre-C7 captures NOT comparable to post-C7**; **PDR alone scores 0.9987 vs 0.7031** (`feature_separability.py`).
- ⚠️⚠️ **D-13: a PRE-fix 0-row card file is LOST DATA**, not evidence the node logged nothing.
- ⚠️⚠️ **ROOT POWER — verify before EVERY capture** (brownout loop); direct laptop USB, never a shared hub.
- ⚠️ **No pcap ever captured.** `docs/WIRESHARK-GUIDE.md` §7/§9. M1 Macs: Wi-Fi OFF first.
- **Two unreconciled panel tracks:** `Plan/THESIS3-PANEL-PLAN.md` vs `.../memory/panel-change-2026-09.md`. **R-A/R-B unwritten**; `run_ledger.csv` header-only.
- ✅ **FIXED sep. 22 (ALL need a REFLASH):** live-run "ABORTED"; SET_LOCATION after hot-swap; sticky STILL RUNNING. MEMORY.md.
- ⚠️ **OPEN — how are CHILDREN exported?** No post-root pass; they get `-Export` at Ctrl+] BEFORE the root drives the phases. **Confirm before the campaign.**

## Recently done (last 3 max, newest first — older entries roll to ARCHIVE.md)
- sep. 22, 2026 — **BOARDS GET A REAL CLOCK.** `SET_TIME` + `/sdcard/clock.txt` anchor; host pushes UTC every
  connect; `runs.csv` += `started`,`clock_src`; pickers date by RUN. MEMORY.md. **6/6 CLEAN build verified — 0 warnings.**
- sep. 22, 2026 — **`jitter` scenario; per-node PDR; build `-Clean`; wormhole warnings; wizard [15] crash; SMART ARCHIVE menu (duplicate + completeness detection).** MEMORY.md.
- sep. 22, 2026 — **Console `LAYER`→`HOP` (root = H00), blackhole header → C7 positional model, leaf/off-path guards, `TOPOLOGY TREE`, USB-export stderr trap. 6/6 build clean.** **NEEDS REFLASH.**

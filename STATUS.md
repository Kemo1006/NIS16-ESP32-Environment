# Status

<!-- Overwrite each session. Hard cap: 40 lines — move "done" items to ARCHIVE.md. First thing a new session reads. -->

**Updated:** sep. 22, 2026 — **Export overhauled + "0 rows off the SD card" root-caused (D-13) + arrivals-over-USB dedup fixed**, and **the working copy moved drives** (below). **Committed `ac2f9d2`; newer work UNCOMMITTED.**

## ⚠️ THE WORKING COPY MOVED — read this first
**Work in `A:\Angelo\Excelsior\THESIS\T`.** `C:\...\NIS16-ESP32-Environment` (old C: path) is a BACKUP only —
do not edit it. Reason + verification: MEMORY.md ("WORKING COPY MOVED" entry, sep. 22).

## Current focus
**Export + data-integrity (D-13)**, independent of any milestone/adviser gate. Next: hardware-test on a real board.

## Next step
1. ✅ **HARDWARE-CONFIRMED sep. 22:** live-flag fix (growing file = STILL RUNNING, finished = ABORTED)
   and `DELETE_SD_FILE` (2 deleted over USB; live file correctly refused). **Left: child clean-stop.**
2. ⚠️ **Hardware-test D-13 + the USB export path** on real hardware (reset a board mid-run; wizard [3]).
3. **Re-flash EVERY board** — D-13 + `LIST_SD` + schema v2 (F3), F1, F2, C7. Old firmware can't answer `LIST_SD`.
4. **Then the campaign** (128 vs 512 — `inventory_cells.py --plan --repeats N`); re-analyse the 8 complete runs.

## Blockers / open questions
- ⛔ **D-12 vs the signed Milestone Form** — adviser decision, not ours. See Next step 1.
- ⚠️ **Pre-C7 captures NOT comparable to post-C7**; **PDR alone scores 0.9987 vs 0.7031** (`feature_separability.py`).
- ⚠️⚠️ **D-13: a PRE-fix 0-row card file is LOST DATA**, not evidence the node logged nothing.
- ⚠️⚠️ **ROOT POWER — verify before EVERY capture** (brownout loop); direct laptop USB, never a shared hub.
- ⚠️ **No pcap ever captured.** `docs/WIRESHARK-GUIDE.md` §7/§9. M1 Macs: Wi-Fi OFF first.
- **Two unreconciled panel tracks:** `Plan/THESIS3-PANEL-PLAN.md` vs `.../memory/panel-change-2026-09.md`. **R-A/R-B unwritten**; `run_ledger.csv` header-only.
- ⚠️ **`LOCATION_WRITE_FAILED` on COM10/COM11 = STALE MOUNT on old firmware** (not a dead card; the
  lock switch is not even read over SPI). Cleared by a power-cycle/reflash. Both now log fine.
- ✅ **FIXED sep. 22, ALL need a REFLASH:** live-run "ABORTED"; SET_LOCATION after a hot-swap; and
  **sticky STILL RUNNING** (`sd_is_live_mirror()` compared paths, not open handles, so a finished run
  stayed unimportable). Until reflashed, read that card in a reader instead. Detail: MEMORY.md.
- ⚠️ **OPEN — how are CHILDREN meant to be exported?** No second export pass exists after the root; children
  get `-Export` at Ctrl+], which fires BEFORE the root drives the phases. Needs a post-root pass or a
  documented separate-export procedure — **confirm before the campaign.**

## Recently done (last 3 max, newest first — older entries roll to ARCHIVE.md)
- sep. 22, 2026 — **Export overhaul + 3 follow-up fixes.** D-13 fsync; `LIST_SD`/`EXPORT_SD_PATH` dual
  source; arrivals dedup; sticky STILL-RUNNING fix; `DELETE_SD_FILE` per-file delete (USB + card);
  children stop cleanly at TERMINATE. All 6 variants build clean. NOTHING hardware-tested. See MEMORY.md.

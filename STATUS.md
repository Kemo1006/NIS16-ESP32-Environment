# Status

<!-- Overwrite each session. Hard cap: 40 lines — move "done" items to ARCHIVE.md. First thing a new session reads. -->

**Updated:** sep. 22, 2026 — **Export overhauled + "0 rows off the SD card" root-caused (D-13) + arrivals-over-USB dedup fixed**, and **the working copy moved drives** (below). **Committed sep. 22 (not pushed).**

## ⚠️ THE WORKING COPY MOVED — read this first
**Work in `A:\Angelo\Excelsior\THESIS\T`.** `C:\...\NIS16-ESP32-Environment` (old C: path) is a BACKUP only —
do not edit it. Reason + verification: MEMORY.md ("WORKING COPY MOVED" entry, sep. 22).

## Current focus
**Export + data-integrity (D-13)**, independent of any milestone/adviser gate. Next: hardware-test on a real board.

## Next step
1. ⛔ **Unblock COM10/COM11 (LOCATION_WRITE_FAILED)** — they record NOTHING to SD; then child-export.
2. ⚠️ **Hardware-test D-13 + the USB export path** on real hardware (reset a board mid-run; wizard [3]).
3. **Re-flash EVERY board** — D-13 + `LIST_SD` + schema v2 (F3), F1, F2, C7. Old firmware can't answer `LIST_SD`.
4. **Then the campaign** (128 vs 512 — `inventory_cells.py --plan --repeats N`); re-analyse the 8 complete runs.

## Blockers / open questions
- ⛔ **D-12 vs the signed Milestone Form** — adviser decision, not ours. See Next step 1.
- ⚠️ **Pre-C7 captures NOT comparable to post-C7.** **PDR alone scores 0.9987 vs 0.7031** — use `tools/feature_separability.py`.
- ⚠️⚠️ **D-13: a PRE-fix 0-row card file is LOST DATA**, not evidence the node logged nothing.
- ⚠️⚠️ **ROOT POWER — verify before EVERY capture** (brownout loop); direct laptop USB, never a shared hub.
- ⚠️ **No pcap ever captured.** `docs/WIRESHARK-GUIDE.md` §7/§9. M1 Macs: Wi-Fi OFF first.
- **Two unreconciled panel tracks:** `Plan/THESIS3-PANEL-PLAN.md` vs `.../memory/panel-change-2026-09.md`. **R-A/R-B unwritten**; `run_ledger.csv` header-only.
- ⛔ **LIVE BLOCKER: COM10/COM11 answer `ERROR:LOCATION_WRITE_FAILED`** — card MOUNTS, write fails. Prime
  suspect: **write-protect lock switch on those two adapters.** Triage + why in MEMORY.md. Unresolved.
- ✅ **FIXED sep. 22: "ABORTED" on a live run, and SET_LOCATION dying after an SD hot-swap.** Both were
  real; see MEMORY.md. ⚠️ **All three fixes need a REFLASH to take effect.**
- ⚠️ **OPEN — how are CHILDREN meant to be exported?** No second export pass exists after the root; children
  get `-Export` at Ctrl+], which fires BEFORE the root drives the phases. Needs a post-root pass or a
  documented separate-export procedure — **confirm before the campaign.**

## Recently done (last 3 max, newest first — older entries roll to ARCHIVE.md)
- sep. 22, 2026 — **D-13 + dual-source export + arrivals dedup fix + manual-path location pre-flight.** `sd_mirror_sync()` fsync fix; `LIST_SD`/
  `EXPORT_SD_PATH`; wizard [3] source chooser (byte-identical CSVs both routes). First real capture attempt
  Host side fully verified (synthetic card + fake-serial LIST_SD); `Confirm-BoardLocations` now shared by
  the preset AND manual run paths. Neither is hardware-tested yet. Full detail: MEMORY.md.
- sep. 21, 2026 — `docs/EXPECTED-RESULTS.md`; stale attacker-MAC alarms fixed; PLACEMENT warning. Pushed.

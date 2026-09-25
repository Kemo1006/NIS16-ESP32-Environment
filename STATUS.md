# Status

<!-- Overwrite each session. Hard cap: 40 lines — move "done" items to ARCHIVE.md. First thing a new session reads. -->

**Updated:** sep. 25, 2026 — wizard port-less-preset fix (UNCOMMITTED) + run-authenticity/alignment audit. **Next: REFLASH EVERY BOARD, then one full test run.**

## ⚠️ Working copies
Angelo's laptop: `A:\Angelo\Excelsior\THESIS\T`. Basti's laptop: `C:\Users\Basti\OneDrive\Documents\Thesis\THESIS3`.
Both are clones of GitHub branch `THESIS3` — `git pull` before editing. Old `C:\...\NIS16-ESP32-Environment` = backup only.

## Next step
1. **REFLASH ALL BOARDS (root included)** — TERMINATE fixes, dashboard, and (sep. 25) reset-reason + ROSTER GATE all live in firmware.
2. **Hardware-test the new safeguards** on one full run (none are tested on boards yet):
   - root dashboard `EXPORT :` line flips to `ALL n BOARDS DONE - SAFE TO EXPORT`, rows show `SAFE`;
   - unplug the root during cooldown → child logs `No TERMINATE received 180 s into cooldown`, card lists it clean;
   - wizard export over USB on a STILL RUNNING file → offers END_RUN → re-export lists it closed.
3. **G402 linear r1 (sep. 24): the RUN IS GOOD, our imported files were the wrong boots.** Root arrivals prove all 6 children ran the
   whole run (blackhole worked). Phase-255 files = later boots; the run files are most likely in each card's `_archive/` (importer skips it).
   **Do NOT re-capture or wipe cards.** Check `_archive/` + runs.csv on each card; match to the run by seq_num vs root, never file times.
4. ⚠️ **ROOT COVERAGE ≥95% still to re-measure** after the reflash (`validate_integrity.py`; `xTaskDelayUntil` fix `7d1e066`).
5. **Then the campaign** (`inventory_cells.py --plan --repeats N`).

## Blockers / open questions
- ⛔⛔ **Boards DIRECT into the laptop, never dock/hub** (BSOD 0xB8). Verify root power. Never pull an SD card mid-run (wait SAFE / END_RUN).
- ⚠️ **HT20 (D-14):** HT40 captures (before sep. 23) ≠ HT20 — label, don't pool. HT20 is NOT the STILL RUNNING cause.
  Mac pcap data frames still not validated (`tools/check_pcap.py`). Table 3.3 RSSI ranges: re-check against HT20 data.
- ⛔ **D-12 vs the signed Milestone Form** — adviser decision.
- ⚠️ Pre-C7 captures NOT comparable to post-C7; PDR alone scores 0.9987 (`feature_separability.py`) — open.
- **Two unreconciled panel tracks:** `Plan/THESIS3-PANEL-PLAN.md` vs `.../memory/panel-change-2026-09.md`. R-A/R-B unwritten.
- ⚠️ **OPEN — how are CHILDREN exported?** Confirm the post-run export flow before the campaign.
- Sep. 25 firmware/tools ARE pushed (`5b8cca7`, `d6660b8`). Untested: roster gate on boards, live logs push/delete/restore.
- ⚠️ **Committed G402 analysis (`88bf3da`) is built from the WRONG boots** — 5/8 files phase-255 only, 1677/3479 windows unlabelled. Re-run after `_archive/`.
- ⚠️ **PAPER still behind the code:** 1 Hz / 5 s (Tables 4.4/4.10, §4.2.4.1) — **10 Hz / 1 s is CORRECT (panel+adviser), keep the code**;
  Table 4.5 calls `retry_count`/`tx_count` MAC stats — they are app-layer (**D-15**). DATA-DICTIONARY §2 now post-C7. Wormhole B retry overload open.

## Recently done (last 3 max, newest first — older entries roll to ARCHIVE.md)
- sep. 25, 2026 — **Wizard: preset board with no port now ASKS "plugged into THIS laptop?"** instead of silently going remote;
  location check runs after the port fix and never says "All boards" when it read none. Block-tested with stubs; not run on boards.
- sep. 25, 2026 — **Power-cut/crash prevention:** root ROSTER GATE (waits for all children, `START_ANYWAY` override,
  per-phase dropout warning), reset reason + brownout/crash totals on card, import shows WHY a file aborted. Build-verified.

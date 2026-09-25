# Status

<!-- Overwrite each session. Hard cap: 40 lines — move "done" items to ARCHIVE.md. First thing a new session reads. -->

**Updated:** sep. 25, 2026 — ABORTED-capture diagnosis CORRECTED + pipeline guards (UNCOMMITTED). **Next: REFLASH EVERY BOARD, then one full test run.**

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
- ⛔⛔ **Plug boards DIRECT into the laptop, never the dock/hub** (BSOD 0xB8). **Root power: verify before every capture.**
- **Never pull an SD card mid-run** — wait for the dashboard's SAFE / `Experiment complete`, or use END_RUN.
- ⚠️ **HT20 (D-14):** HT40 captures (before sep. 23) ≠ HT20 — label, don't pool. HT20 is NOT the STILL RUNNING cause.
  Mac pcap data frames still not validated (`tools/check_pcap.py`). Table 3.3 RSSI ranges: re-check against HT20 data.
- ⛔ **D-12 vs the signed Milestone Form** — adviser decision.
- ⚠️ Pre-C7 captures NOT comparable to post-C7; PDR alone scores 0.9987 (`feature_separability.py`) — open.
- **Two unreconciled panel tracks:** `Plan/THESIS3-PANEL-PLAN.md` vs `.../memory/panel-change-2026-09.md`. R-A/R-B unwritten.
- ⚠️ **OPEN — how are CHILDREN exported?** Confirm the post-run export flow before the campaign.
- `presets/Bas/linear-blackhole-stationary-g402.json` edits are the user's own (committed with other work) — not reviewed.
- **sep. 25 work is ALL UNCOMMITTED** (firmware + wizard/run.ps1 + host tools). 6/6 variants + gated root build CLEAN. Not yet:
  live GitHub test of logs push + delete/restore; hardware test of the roster gate; `menu.ps1` ABORTED prompt; stray `archive/manifest.json`.

## Recently done (last 3 max, newest first — older entries roll to ARCHIVE.md)
- sep. 25, 2026 — **Power-cut/crash prevention:** root ROSTER GATE (waits for all children, `START_ANYWAY` override,
  per-phase dropout warning), reset reason + brownout/crash totals on card, import shows WHY a file aborted. Build-verified.
- sep. 25, 2026 — **Incomplete-capture guards:** validator FAILs phase-255-only files + `child` role fix; preprocess skips them
  and no longer archives a complete capture for a newer empty one; import picker shows NO EXPERIMENT DATA; analyze.ps1 exit gates.

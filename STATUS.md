# Status

<!-- Overwrite each session. Hard cap: 40 lines — move "done" items to ARCHIVE.md. First thing a new session reads. -->

**Updated:** sep. 24, 2026 — scenario rename to `stationary` + multi-laptop wizard fixes, all COMMITTED/PUSHED (THESIS3). **Next: re-run blackhole/linear/home, attacker placed nearest the root — root table must show it at `H01`** (a `NO NODE IS DOWNSTREAM` with all nodes reported = placement, not a bug; MEMORY.md).

## ⚠️ THE WORKING COPY MOVED — read this first
**Work in `A:\Angelo\Excelsior\THESIS\T`.** `C:\...\NIS16-ESP32-Environment` (old C: path) is a BACKUP only —
do not edit it. Reason + verification: MEMORY.md ("WORKING COPY MOVED" entry, sep. 22).

## Current focus
**Export + data-integrity (D-13)**, independent of any milestone/adviser gate. Next: hardware-test on a real board.

## Next step
1. ✅ **HARDWARE-CONFIRMED sep. 22:** live-flag fix (growing file = STILL RUNNING, finished = ABORTED)
   and `DELETE_SD_FILE` (2 deleted over USB; live file correctly refused). **Left: child clean-stop.**
2. ⚠️ **ROOT COVERAGE 93.6% < 95% M5 floor — LIKELY FIXED, RE-MEASURE.** Validator: no gaps, root ran ~9.09 Hz
   (sleep-after-work). `xTaskDelayUntil` fix (`7d1e066`, sep. 23 02:02) postdates that sep. 22 capture. Next export: `validate_integrity.py` ≥95%.
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
- ⚠️ **HT20 firmware — REFLASH any board not on today's fix** (COM3/4/12/15 already are). Boot log must show `RF width (before wifi start): STA 20 MHz, AP 20 MHz`. SD cards hold a short sep. 23 TEST capture (blackhole/linear/home) — next boot archives it; don't import it. Mac pcap: data frames still not validated. Check any capture with wizard **Check a Mac sniffer capture file** (`tools/check_pcap.py`; repairs 'cut short').
- **Two unreconciled panel tracks:** `Plan/THESIS3-PANEL-PLAN.md` vs `.../memory/panel-change-2026-09.md`. **R-A/R-B unwritten**; `run_ledger.csv` header-only.
- 📝 **OTHER MEMBER — [17] TOPOLOGY STRUCTURE, DISPLAY ONLY (the CSVs are CORRECT, do not "fix" them):** it
  prints `parent_mac` (SoftAP MAC) but names nodes by `node_id` (STA MAC), so no column matches; map back via −1.
- ⚠️ **OPEN — how are CHILDREN exported?** No post-root pass; they get `-Export` at Ctrl+] BEFORE the root drives the phases. **Confirm before the campaign.**

## Recently done (last 3 max, newest first — older entries roll to ARCHIVE.md)
- sep. 24, 2026 — **Multi-laptop wizard fix:** "N boards need ports" wrongly counted a remote root/child as needing a LOCAL port. Fixed + clarifying banners added. MEMORY.md.
- sep. 24, 2026 — **Scenario `none` → `stationary` EVERYWHERE, with its own `stationary\` folder** (`none` still accepted). Fixed: jitter runs could not export. 20 py + 19 PS checks + firmware build pass. **REFLASH.** MEMORY.md.
- sep. 23, 2026 — ✅ **FIXED + HARDWARE-VERIFIED: `MESH_FORCE_HT20` had broken mesh joining** (0 nodes in 11 min). HT20 now set BEFORE `esp_wifi_start()` (APSTA mode). 4-board test: all joined, correct chain, all 20 MHz, phases reach children. 4 boards already flashed with it. MEMORY.md.

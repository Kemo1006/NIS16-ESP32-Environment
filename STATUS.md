# Status

<!-- Overwrite each session. Hard cap: 40 lines — move "done" items to ARCHIVE.md. First thing a new session reads. -->

**Updated:** sep. 27, 2026 (pm: 02:05 pcap = linear, attack worked; burst 300) — **ALL DATA NOW UNDER `ESP32-Environment/datasets/`** (code stayed; originals NOT yet deleted); Wireshark view menu now defaults to ALL boards + a MY boards submenu. **Next: user deletes originals, reviews + COMMITS/PUSHES, then Angelo `git pull`s.**

## ⚠️ Working copies
Angelo: `A:\Angelo\Excelsior\THESIS\T`. Basti: `C:\Users\Basti\OneDrive\Documents\Thesis\THESIS3`. Both clone GitHub branch `THESIS3` — `git pull` before editing; old `NIS16-ESP32-Environment` = backup only.

## ⚠️ DATA LAYOUT CHANGED sep. 27 (details: MEMORY.md top entry)
`datasets/exports` (was tools/exports) · `datasets/analysis` (CSV/PNG output; `analysis/` keeps only the .py code) · `datasets/archive` · `datasets/PCAP` · `datasets/run_logs`. Every script/tool writes there now. **FILEMAP.md + guides still show OLD paths (user fixes docs later) — trust the code.**

## ⚠️ UNCOMMITTED on Basti's laptop (sep. 25–27 sessions — the user pushes; details in MEMORY.md, top entries)
- **Sep. 27 data move:** `datasets/` (new), `.gitattributes`, `.gitignore`, `.vscode/settings.json`, `run_wizard/run/menu/analyze/archive.ps1`, `tools/ImportBatch.ps1`, `tools/{export_logs,import_sdcard,run_matrix,verify_topology,validate_integrity,inventory_cells,sniff,push_data,feature_separability}.py`, `slides/refresh_slide_numbers.py`. Stage `.gitattributes` in the SAME commit as the moved CSVs.
- **Sep. 26 late:** `root_node/main/root_main.c` (phase banner wall-clock time; needs root reflash to show).
- **Night session:** `phase_listener.h/.c` (session_id), `analysis/preprocess.py`, `analysis/eda.py`, `analysis/column_legend.py`, regenerated home/stationary output (now under datasets/analysis).
- **Eve session:** `analysis/features.py`, `run.ps1` (`-Trim` + no-child guard), `run_wizard.ps1` (root post-export question), `docs/issue_logs/thesis-deviate.md`.
- Sniffer/WIRESHARK (+ sep. 27 ALL/MY-boards view menu, `run_wizard.ps1` only): `sniffer_node/`, `tools/sniff.py`, `tools/check_pcap.py`, `docs/WIRESHARK-GUIDE.md`, `docs/WIRESHARK-QUICKSTART.md` (NEW). Analysis: `analysis/phase_sync.py` (NEW), `leakage.py`, `verify_attack.py`, docs DATA-DICTIONARY + EXPECTED-RESULTS. Build: `build_all_variants.ps1`. Data sync: `tools/ImportBatch.ps1` (NEW).
- **Sep. 27 pm:** `archive.ps1` + `run_wizard.ps1` archive now moves PCAP + run_logs too. `mesh_config.h` BURST_COUNT 100->300 (+ text in run_wizard/menu/run.ps1, memory/run-scenarios; not built) - it is the OWNER's file, review. NOT mine: `presets/Bas/linear-blackhole-highload-g402.json`. Someone else edited `run_wizard.ps1` on sep. 27 00:16 (+~52 lines) mid-session — review it too.

## Next step
0. **Delete the old data folders** (verified identical copies are in `datasets/`), from `ESP32-Environment`: `Remove-Item -Recurse -Force archive, PCAP, run_logs, tools\exports, analysis\baseline, analysis\blackhole, analysis\wormhole`. Then commit; tell Angelo to pull CODE before his next data push/pull (GitHub paths moved).
1. ⚠️ **REFLASH EVERY BOARD before the next capture** (phase message 17->21 B + root banner time). Then hardware-test: reboot the root mid-stabilise -> children print "Root RESTARTED" and log 255 until the new Phase 0.
2. First real run on the new layout: confirm export/import/sniffer/run log land in `datasets/…` and push/pull finds them. Open its pcap via the new MY boards submenu in real Wireshark once.
3. **Re-run analysis on every OTHER cell** (`analyze.ps1 -All -Verify`): LatencyHopRatio, ParentSwitchRate/HopStability, phase-sync, correlation views changed. Only blackhole/linear/home/stationary is current.
4. Home cell holds the 21:11 run; the GOOD 19:18 run is in `datasets/archive/2026-09-26_tested-4-nodes-at-home-/`; both r1 — rename one before pooling.
5. Docs pass (user, later): FILEMAP.md, WIRESHARK-GUIDE, tools/README, MEMBER-HOWTO, OUTPUT-VERIFICATION -> `datasets/` paths.
6. ⚠️ ROOT COVERAGE ≥95% still to re-measure (`validate_integrity.py`). Then the campaign (`inventory_cells.py --plan`). Watch node3 (20500DE70C80).

## Blockers / open questions
- ⚠️ **PDR (0.9991) and LatencyHopRatio (0.9987) are single-feature perfect** — both exist only outside the attack. Open, needs a framing decision.
- ⛔⛔ **Boards DIRECT into the laptop, never dock/hub** (BSOD 0xB8). Verify root power. Never pull an SD card mid-run.
- Sniffer: **P pauses saving** — check the .json `pauses` before using a pcap. Run logs hold only wizard text, not board serial output.
- ⚠️ HT20 (D-14): HT40 captures (before sep. 23) ≠ HT20 — label, don't pool. ⛔ D-12 vs the signed Milestone Form — adviser decision.
- ⚠️ PAPER behind the code: 10 Hz / 1 s is CORRECT (keep); Tables 4.4/4.10 + §4.2.4.1 say 1 Hz / 5 s; Table 4.5 -> D-15; RetryRate = Table 3.4 miss.

## Recently done (last 3 max, newest first — older entries roll to ARCHIVE.md)
- sep. 27 — **Wireshark view menu: ALL boards by default + MY boards submenu** (member's boards, side-by-side I/O lines); stub-tested, not opened in real Wireshark.
- sep. 27 — **Data moved to `datasets/`** (5 folders + analysis output; 375 files hash-verified; all writers/readers repointed, code untouched).
- sep. 27 pm — **02:05 blackhole pcap verified linear + attack worked** (attacker drop 180/180; node3 -> root 0 in phase 1); burst probes 100->300. Fix `member_boards.json` (20:38 attacker is stale, real = F4:18).

# Status

<!-- Overwrite each session. Hard cap: 40 lines — move "done" items to ARCHIVE.md. First thing a new session reads. -->
**Updated:** oct. 15, 2026 ~4:10 PM (Kyle's laptop, + verifications #31-#32). HEAD `9f53e53`; Kyle's doc edits (verifications #14-#29, checklist, MEMORY, STATUS) are **NOT committed** - commit + push before anyone pulls. Facts + reasons: top ~10 entries of MEMORY.md.

## ⚠️ Working copies / layout
Angelo `A:\Angelo\Excelsior\THESIS\T` · Basti `C:\Users\Basti\OneDrive\Documents\Thesis\THESIS3` · Kyle `D:\NIS16-ESP32-Environment` · branch `THESIS3`. Data in `ESP32-Environment/datasets/{exports,analysis,archive,PCAP,run_logs}`; analysis tables + `eda_output/` force-added (`git add -f`). Board roster: https://claude.ai/artifact/KteBqiYpZedMjG9ppFjreh
- ⚠️ **Pull safely:** `git stash push` (or commit) first, then `git pull --ff-only`, then `git stash pop`. A plain pull on oct. 14 silently dropped Kyle's uncommitted doc edits.

## Where things stand
- **Campaign (D-18/D-19):** 3 sites G402 / DLSU_Library / Yuchengco, 108 runs planned. Plan `tools/campaign_plan.json`; views: wizard Campaign progress, `inventory_cells.py --board / --sessions / --checklist`.
- **Verification log** `docs/dataset-verification.md` (newest first): #32 partial_mesh/Yuch/stationary = RECAPTURE (de-dup) · #31 LOCATION COMPARISON stationary blackhole, 3 sites = equivalent (checklist B-loc) · #30 partial_mesh/G402/highload USABLE (2 victims, plain tree) · #29 wormhole/linear/G402/stationary USABLE (valid wormhole, 5-hop shortcut) · #13 verifier audit (Angelo) · #12 = #28 reversed wormhole run NOT USABLE · #27 `missing_firmware_fields` OK · #26 linear/G402/highload · #25 tree/DLSU/burst · #24 tree/Yuch/burst · #23 linear/DLSU/highload · #21 linear/Yuch/highload · #20 star/Yuch/highload · #19 tree/Yuch/stationary (all USABLE, footnotes in the blocks).
- **Unlogged but checked (user's choice):** tree/DLSU/highload (recapture 11:41 PM oct. 12) and tree/Yuch/highload = USABLE.
- **Verifier (`6fecb46`, Angelo):** setup checks now COUNT - a wormhole with a failed setup check reads `DUPLICATION ONLY - SETUP INVALID`; TunnelBytes is secondary (no double count). TunnelLatency INCONCL + LatencyHopRatio INFEASIBLE are by design (no baseline tunnel / clock offsets) - cite the tunnel-vs-normal copy latency difference instead.
- **Root firmware:** de-dup table cleared at the gate (oct. 11 fix, committed `6932864`); tree gate committed. Wormhole UART safety net + wormhole-run victim build (Angelo, oct. 14) - reflash before wormhole runs.
- **Thesis to-do:** `docs/deviations-limitations/THESIS-UPDATE-CHECKLIST.md` (A21 / D-20: attacks are emulations; paper edits week of oct. 19). Kyle's oct. 11-14 C/A rows were lost in the pull - rebuild from the verification blocks if needed.

## Next step
1. **Commit + push Kyle's doc edits** (dataset-verification.md, checklist, MEMORY, STATUS). Check `git diff --cached --stat` first: the wizard has staged presets, `campaign_plan.json`, `mesh_config.h` (do NOT push the attacker line). Then `git stash drop` the oct. 14 pre-pull stash once happy.
2. **Recapture blackhole/linear/Yuchengco/stationary + partial_mesh/Yuchengco/stationary** (D7; both pre-fix de-dup, #31/#32 - do both in ONE Yuchengco session). linear (oct. 9 run: pre-fix de-dup dropped the victim's first ~60 s of baseline, PDR FAIL; B768 94.5 % coverage = the `[~]`).
3. Recapture wormhole tree/G402 (D3), tree/G402 stationary + burst r2 (D1, D2). Remaining matrix per `inventory_cells.py --sessions`.
4. Verify partial_mesh/DLSU/jitter (analysed, not checked); decide whether the coverage rule should skip phase 255 (partial/DLSU/highload).
5. **Paper edits (week of oct. 19):** A21/D-20 + the footnotes in the verification blocks. Adviser: D-12, D-17..D-20, B3, A20 (home captures).
6. Optional firmware fixes (user's call, need a reflash everywhere): de-dup for a node rebooting MID-run; TERMINATE watchdog that also arms outside cooldown; root dashboard "SD: off" per board.

## Blockers / open questions
- ⛔⛔ BSOD 0xB8: NEVER Ctrl+C an export or SD read; never reset/unplug a board while it is read; boards DIRECT into the laptop.
- ⚠️ A board missing from its card: check flash first (`export_logs.py --port COMx --list`) before redoing a run; root "SAFE TO EXPORT" does not prove a card copy exists.
- ⚠️ Tree runs: reshape the mesh ONLY while the root waits; hands off once "starting the run". Wormhole: check the root's WORMHOLE TUNNEL box (shortcut >= 3 hops, no "ENDS REVERSED") before the baseline.
- ⚠️ Don't reset the highload root before EXPORT_ARRIVALS. Don't run `analyze.ps1` with `2>&1` from PowerShell. Kyle's laptop: analysis needs `C:\Python314\python.exe` (IDF venv has no pandas); board commands need the IDF venv python.

## Recently done (last 2 max, newest first — older entries roll to ARCHIVE.md)
- oct. 11-15 (Kyle) — verifications #14-#29 (renumbered after the oct. 14 merge), de-dup fix confirmed on hardware, COM8 flash-only recovery, wormhole G402 recapture valid, `missing_firmware_fields` audit; pulled `6fecb46` with stash + merge (no data lost on that pull).
- oct. 14 (Angelo) — verifier audit #13 (setup checks, fault-injection tests), wormhole safety net + victim build, #12 reversed wormhole NOT USABLE, D-20 / A21 (attacks = emulations). Pushed `6fecb46`.

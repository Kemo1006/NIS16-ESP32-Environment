# Status

<!-- Overwrite each session. Hard cap: 40 lines — move "done" items to ARCHIVE.md. First thing a new session reads. -->
**Updated:** oct. 7, 2026 night (Angelo, session summary). Everything is on GitHub `THESIS3`. Facts + reasons: top ~20 entries of MEMORY.md (oct. 7).

## ⚠️ Working copies / layout
Angelo `A:\Angelo\Excelsior\THESIS\T` · Basti `C:\Users\Basti\OneDrive\Documents\Thesis\THESIS3` · branch `THESIS3`, `git pull` first. Data in `ESP32-Environment/datasets/{exports,analysis,archive,PCAP,run_logs}`; PCAP + run logs git-ignored. Analysis tables + `eda_output/` are force-added (`git add -f`). Board roster: https://claude.ai/artifact/KteBqiYpZedMjG9ppFjreh
- ⚠️ **Basti, before your next `git pull`:** the 4 duplicate files in `exports/baseline/tree/G402/stationary/` were deleted on GitHub (MEMORY oct. 7 late night). Run `git restore --staged --worktree -- ESP32-Environment/datasets/exports/baseline/tree ESP32-Environment/datasets/exports/wormhole/tree/G402/stationary`, then `git pull`. That pull also brings the full blackhole/linear/DLSU_Library/jitter r1 (root + 7 children; not analysed yet).

## Where things stand
- **Campaign (D-18, D-19):** 3 sites **G402 / DLSU_Library / Yuchengco** (home dropped, "Goks" renamed). 96 attack + **12 benign** (one per location x topology, 4 different scenarios per location, 2 per scenario) = **108 runs**, 11 done, ~31 h left. Plan: `tools/campaign_plan.json` ("cells" + "benign"). Views: wizard Campaign progress, `inventory_cells.py --board / --sessions`. Dashboard: https://claude.ai/artifact/634D6i1UrhLXTNsSuEWMLV (rebuild `python tools/build_campaign_board.py`, then republish).
- **Highload root fix WORKS on hardware** (`643adf8`, verification #9: 0 arrival rows lost). Highload root logs arrivals SD-only, batched; root now built with `-DTRAFFIC_PROFILE=2` on highload. Old 15:13 run archived (`datasets/archive/2026-10-07_..._highload-invalid/`).
- **Wormhole auto-switch WORKS on hardware** (verification #10, wormhole/linear/DLSU/stationary: A at L5, B at L7, 181/181 B probes duplicated). TunnelLatency INCONCL + LatencyHopRatio INFEASIBLE are by design (C8).
- **Analysed + pushed tonight:** blackhole/DLSU linear/stationary, linear/burst, star/stationary (all CONFIRMED), partial_mesh/jitter, wormhole/linear/stationary.
- **Wizard text:** wormhole picker = "wired tunnel board 1/2" (A/B only a fallback); powercycle/mobility box gives WHO/WHAT/WHEN (phone timer 5:10 attack run, 2:30 baseline run).
- **Verification log** `docs/dataset-verification.md`: #10 wormhole/linear/DLSU · #9 partial/DLSU/highload · #8 star/DLSU/stationary (Basti) · #7 partial/DLSU/stationary · #6 wormhole tree/G402 no shortcut.
- **Thesis to-do:** `docs/deviations-limitations/THESIS-UPDATE-CHECKLIST.md`; new tonight: A19 (benign design), A20 (3 sites), C6–C8. D-entries now D-1…D-19.
- Host build tip (Angelo): use `C:\Espressif\Initialize-Idf.ps1 -IdfId <id>` then `python $env:IDF_PATH\tools\idf.py`. Test build dirs left in `C:\eb` (delete by hand).

## Uncommitted on Angelo's laptop (on purpose)
- Never push: root/child `sdkconfig`, `dependencies.lock`, `mesh_config.h` attacker line (`F4:2D:...:18`), `sd_card_test/sdkconfig`.
- 2 presets show DELETED (likely the wizard): `Bas/blackhole-partial_mesh-g402-jitter.json`, `Cal/blackhole-linear-dlsu_library-burst.json` - user's call: restore (`git restore`) or push the deletion.

## Next step
1. Reflash every board (Yuchengco firmware + highload root) before the next session.
2. Session 1 on the board: G402 / linear (BH highload, BH mobility, benign jitter, then wormhole).
3. Verify partial_mesh/DLSU/jitter (analysed, not checked). Inventory flags partial/DLSU/highload as "re-capture" (ED80 coverage incl. stabilise) though #9 says usable - decide whether the coverage rule should skip phase 255.
4. Recapture wormhole tree/G402 (D3), tree/G402 stationary + burst r2 (D1, D2).
5. Adviser: D-12, D-17, D-18, D-19, B3 framing; decide how the old home captures are reported (A20).

## Blockers / open questions
- ⛔⛔ BSOD 0xB8: NEVER Ctrl+C an export or SD read; never reset/unplug a board while it is read; boards DIRECT into the laptop.
- ⚠️ Don't reset the highload root before EXPORT_ARRIVALS (a new boot exports 0 rows; data stays on the SD card).
- ⚠️ Don't run `analyze.ps1` with `2>&1` from PowerShell (numpy warnings kill it) - run it as its own process.
- ⚠️ `git diff --cached --stat` before every commit/pull - the wizard stages files on its own.

## Recently done (last 2 max, newest first — older entries roll to ARCHIVE.md)
- oct. 7 night (Angelo) — deleted bogus benign tree/G402 copies (cell now [ ]); pushed linear/DLSU/jitter root; highload fix verified; auto-switch verified; campaign redesign (benign, 3 sites, board/sessions/dashboard, simplified); wizard wording; 3 DLSU cells analysed; verifications #9, #10; all pushed.
- oct. 7 (Basti) — #8 star/DLSU verified USABLE; Edit preset Attacker row; pink A/B; campaign plan swap; unstuck the pull + pushed.

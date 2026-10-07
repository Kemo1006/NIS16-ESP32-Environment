# Status

<!-- Overwrite each session. Hard cap: 40 lines — move "done" items to ARCHIVE.md. First thing a new session reads. -->
**Updated:** oct. 7, 2026 night (Basti): merged Angelo's late-evening push (highload root fix, wormhole auto-switch, #6/#7) with Basti's oct. 7 work (`d8019ac`); pushed. Basti's local-only files: see the 'Basti oct. 7' bullet. Facts + reasons: top ~15 entries of MEMORY.md (oct. 7).

## ⚠️ Working copies / layout
Angelo `A:\Angelo\Excelsior\THESIS\T` · Basti `C:\Users\Basti\OneDrive\Documents\Thesis\THESIS3` · branch `THESIS3`, `git pull` first. Data in `ESP32-Environment/datasets/{exports,analysis,archive,PCAP,run_logs}`; PCAP + run logs git-ignored. Analysis tables + `eda_output/` of the live cells are on GitHub (force-added); a NEW cell's analysis needs `git add -f`. **Live board roster: https://claude.ai/artifact/KteBqiYpZedMjG9ppFjreh**.

## Where things stand
- **Thesis to-do list:** `ESP32-Environment/docs/deviations-limitations/THESIS-UPDATE-CHECKLIST.md` (A method · B wording · C footnotes · D recaptures). CLAUDE.md rule: add a row the same day for anything that changes the paper. Method changes also get a D-entry (now D-1…D-17).
- **Verification log** `docs/dataset-verification.md`: #9 partial_mesh/DLSU/highload USABLE (highload fix works, 0 rows lost) · #8 star/DLSU/stationary USABLE (Basti; hub `20500DE70C80`, 6/6 victims 1→0, Topology FAIL = root-reflash boot segment) · #7 partial_mesh/DLSU/stationary USABLE (output recomputed by hand, not hardcoded) · #6 wormhole tree/G402 r1 had NO shortcut · #5 FE90 stale firmware · #4 DLSU/stationary · #3 tree/G402/burst · #2 sweep · #1 tree/G402/jitter.
- ⛔ **HIGHLOAD ROOT LOST 3151 ARRIVAL ROWS** (oct. 7 ~15:20 partial_mesh highload; 398 ms/row vs <=35 ms needed). That run's root PDR is invalid (C5) - archived on Angelo's laptop to `datasets/archive/2026-10-07_..._highload-invalid/` (its .pcap not yet - Wireshark had it open; 7 tracked child CSVs show as deleted, not pushed). **FIX PUSHED (`643adf8`), VERIFIED ON HARDWARE (#9):** highload ROOT only now logs arrivals SD-only, 4 KB-buffered, flush/100 rows; root now gets `-DTRAFFIC_PROFILE=2` on highload. Other scenarios untouched. Detail: MEMORY oct. 7 (eve).
- **Wormhole AUTO-SWITCH** (A/B by depth, locked at Phase 0) + error detection + enhanced root WORMHOLE TUNNEL printout + `exposure.py` `not_tunnelled` + verifier WORMHOLE SETUP CHECK: pushed, host test 35/35, all 15 variants build. **Not yet on hardware.**
- **Basti oct. 7:** Edit preset row [7] **Attacker** (star = HUB, other-laptop attacker by MAC; 14 scripted cases, not live yet) · wormhole A/B rows pink · star/DLSU preset attacker fixed · campaign plan DLSU star/blackhole powercycle → stationary (4/144; other off-plan cells left as-is) · BSOD tools: `serial_guard.py` grows the CP210x RX buffer to 1 MiB (not on hardware). Still local on Basti's laptop (user's call): `mesh_config.h` attacker line (`f4:...:18`), modified `presets/Bas/wormhole-linear-dlsu_library-stationary.json`, 3 new `presets/Bas/blackhole-partial_mesh-dlsu_library-*.json`.
- `B4BFE932FE90` (Kyle's) ran a stale image on oct. 2; in-sync again in the oct. 7 partial run (looks reflashed).
- z = `-inf`/`+inf` or a huge finite z (ConsistencyScore 1,178,647 = 1e-6 EPSILON residue) = baseline σ ≈ 0 -> write "z undefined (σ = 0)".
- Host build tip (Angelo's laptop): `idf.py.exe` wrapper rejects `-D`; use `C:\Espressif\Initialize-Idf.ps1 -IdfId <id>` then `python $env:IDF_PATH\tools\idf.py`. C: was full (0.29 GB) on oct. 7 - keep space free; esp32_builds live on C:.

## Uncommitted on Angelo's laptop
- Campaign: 3 sites G402 / DLSU_Library / Yuchengco (home dropped, Goks renamed - D-19; reflash before location.txt=Yuchengco). 96 attack + 12 benign = 108 runs. Board: wizard Campaign progress / `inventory_cells.py --board --sessions`. Dashboard: https://claude.ai/artifact/634D6i1UrhLXTNsSuEWMLV (rebuild: `tools/build_campaign_board.py`).
- DATA not pushed: blackhole/partial_mesh/DLSU_Library/stationary - root telem + arrivals, 4 `victim_..._partial_none` files, and its analysis (verified #7). Its 3 `child_node*` files are already on GitHub (Basti's data sync, `0c5d02a`). The highload run's files once exported.
- Never push: root/child `sdkconfig`, `dependencies.lock`, `mesh_config.h` attacker line, `sd_card_test/sdkconfig`.

## Next step
1. Highload fix WORKS on hardware (verification #9: partial_mesh/DLSU highload r1 USABLE, 0 rows lost). Push that data (user's go); recapture the other highload cells with the new root (D5). Don't reset the root before EXPORT_ARRIVALS.
2. Push partial_mesh/DLSU/stationary data (user's go).
3. Reflash root + both wormhole boards; wizard UART tunnel test; wormhole run -> expect `LOCKED as NODE A/B` + root `OK: ... tunnel skips N hop(s)`. Recapture wormhole tree/G402 (D3).
4. Recapture tree/G402/stationary r2, tree/G402/burst r2 (all 8 boards). Remaining matrix: checklist D4.
5. Adviser: D-12, D-17 (run-time wormhole roles; fill in the proposal's wording), B3 framing.
6. Basti: verify blackhole/star/DLSU_Library/burst r1 (oct. 7 ~11:16 AM; data + analysis on GitHub, no verification block yet); try the Edit preset Attacker row in a real run.

## Blockers / open questions
- ⛔⛔ BSOD 0xB8: NEVER Ctrl+C an export or SD read; never reset/unplug a board while it is read; boards DIRECT into the laptop.
- ⚠️ When cleaning old data, delete only `analysis\baseline|blackhole|wormhole` — NEVER `ESP32-Environment\analysis\` itself.
- ⚠️ Run `git diff --cached --stat` before EVERY commit and pull - the wizard stages files on its own (bundled into `cc430a2` once).
- ⚠️ HT20 vs HT40 don't pool (D-14). Optional: verifier could treat σ < 1e-5 as 0 (not done, user's call).

## Recently done (last 2 max, newest first — older entries roll to ARCHIVE.md)
- oct. 7 (Angelo) — wormhole auto-switch + error detection + verification (host test, 15 builds); exposure fix; D-17 + thesis checklist; analysis/EDA + presets pushed; verifications #6, #7; highload arrival-loss found.
- oct. 7 (Basti) — #8 star/DLSU verified USABLE; preset + junk file fixed; Edit preset Attacker row; pink A/B; campaign plan swap; unstuck the pull (2 merges) + pushed.

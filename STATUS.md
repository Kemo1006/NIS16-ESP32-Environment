# Status

<!-- Overwrite each session. Hard cap: 40 lines — move "done" items to ARCHIVE.md. First thing a new session reads. -->
**Updated:** oct. 17, 2026 ~8 PM (Angelo's laptop, wormhole self-echo fix + GUI audit). HEAD `52da079`; **everything below was PUSHED oct. 18 ~12:10 AM** (local-only: wizard attacker MAC in mesh_config.h, derived archive files) - commit + push before anyone pulls. Kyle's verifications #14-#32 are on HIS laptop only. Facts + reasons: top entries of MEMORY.md.

## ⚠️ Working copies / layout
Angelo `A:\Angelo\Excelsior\THESIS\T` · Basti `C:\Users\Basti\OneDrive\Documents\Thesis\THESIS3` · Kyle `D:\NIS16-ESP32-Environment` · branch `THESIS3`. Data in `ESP32-Environment/datasets/{exports,analysis,archive,PCAP,run_logs}`; analysis tables + `eda_output/` force-added (`git add -f`).
- ⚠️ **Pull safely:** `git stash push` (or commit) first, then `git pull --ff-only`, then `git stash pop`.

## Where things stand
- **Wormhole 'both B' (oct. 17 7:30 PM run) = UART SELF-ECHO:** 0C80 heard its OWN HELLOs and took them for the peer ('UART OK'). Firmware now ignores own-MAC HELLOs and reports `UART ECHO (own TX->RX)`; root names every end's UART state. Host test 71/71, root + wormhole builds 0 warnings. **Not yet on hardware.** Earlier #37 fix (one-way cable, root gate 1 A + 1 B) is on the boards and held Phase 0 correctly. **8:59 PM wormhole/linear/G402/highload r1 set up right (A H01, B H05, UART OK) - verify it.**
- **Manual START gate (both attacks):** after all gates the root prints READY and waits - type `START` in the root monitor. `START_ANYWAY` overrides everything.
- **Verifier redesigned:** RESULT on top, [1] scored 3-sigma table with study tags, [2] measured-not-scored (TunnelLatency, LatencyHopRatio), [3] setup checks, [4] per-node PDR + who is not listed, [5] study basis. Wormhole = 2 independent primaries (TunnelIntensity + root-measured DuplicateRate). Colours in analyze.ps1 + terminal.
- **Preprocess:** `transition` segment for windows spanning 2 phases; anchor fallback keeps a stalled board's baseline (D-21).
- **Redo list:** `python tools/redo_list.py` or wizard Campaign -> [5]: 5 REDO, 1 CHECK, 40 OK, live only, now with [topology] evidence + SHARED FINDINGS (partial_mesh = plain tree, B-pm). New: blackhole/linear/Yuchengco/stationary is NOT linear (#38).
- **GUI = full GUI now (oct. 17):** `run_gui.ps1` - **Live run** page runs the whole capture in the window (compile, park root, wipe+flash+monitor each board via `run.ps1 -GuiMonitor`, root last, export) + ROOT dashboard (phase timeline/countdown, START / START_ANYWAY buttons, mesh table, tunnel, alerts). Import/export page redone (MAC pickers, NEW / ALREADY IMPORTED statuses, auto naming preset, preview). Firmware tests + sniffer flash + analysis run in-window. Port pickers show MAC + nickname (new firmware `GET_ID`, no reset). Self-test passes incl. Live run end-to-end on stand-ins; **nothing tried on real boards yet; GET_ID compile-verified oct. 17 4:40 PM**.
- **GUI audit (oct. 17 ~8:40 PM; Data page 11:55 PM = 'ALREADY IMPORTED' found by scanning ALL of datasets/exports by content - board MAC + rows - whatever the file name/folder):** fixed resume-after-skip root count (could start Phase 0 a child short), crash watch freeing a shared COM port before the next flash, no window close during an SD read/flash, stop + failed flash, and the crash on Compile with 'clean rebuild' ticked ($r = $R), and Identify all silently resetting boards that do not answer GET_ID (-> ABORTED runs; now asks first). Self-test + all suites pass. Details: MEMORY.md. Sniffer no longer blocks MAC reads; sniffer files named after the run (today's 2 renamed into their PCAP run folders). Data-page tables use real check boxes; Campaign tags captured-but-not-analysed cells IN PROGRESS (2 now: analyse them). Campaign refreshes itself after Analyse / Verify.
- **Wizard:** 'b' works on every menu (back one question, or back out of the tool); question chains step back; main menu = short aligned names + hints; Campaign -> [2] checklist redesigned; every tool opens under the same framed title, status lines + prompts aligned. Test `tools/test_wizard_nav.ps1` 15/15.
- **Verification log here:** #33-#40 new (wormhole/tree/DLSU: attack CONFIRMED, cell = recapture/footnote decision D8).
- **Wormhole audit (oct. 17):** linear / tree / partial_mesh OK in firmware, run.ps1, wizard + GUI (host test 62/62, verifier 21/21, every wormhole preset builds 2 ends + controls right). ⛔ **STAR wormhole cannot start**: all children sit 1 hop from the root, so the root's 'A shallower than B' gate never passes (START_ANYWAY only) and the verifier calls it SAME DEPTH. Needs a team/adviser decision (checklist A24). Tree: if both ends land at H01 the root waits - move one board. GUI editor now refuses a burst target on a tunnel end/root. **wormhole/tree/G402/stationary r1 DELETED (user, star-shaped) - cell empty, D3 recapture.**

## Next step
0. GET_ID compiles (verified by the user's oct. 17 4:40 PM builds). Live run now: identical boards compile once, failed ones recompile alone, failed flashes retry/skip, resume after a stop.
1. **Re-wire the tunnel** (0C80 GPIO17 must NOT touch its own GPIO16: crossed TX->other RX both ways + GND), **reflash ROOT + both tunnel boards**, then check the dashboard: 1 A (shallower) + 1 B, `UART OK` on both -> READY -> type `START`.
2. **Commit + push** (firmware: `child_node/main/wormhole_victim.c`, `components/mesh_common/*`, `root_node/main/{root_main.c,CMakeLists.txt}`; analysis: `analysis/{preprocess,exposure,eda,column_legend,test_segments}.py`; tools: `verify_attack.py`, `attack_checks.py`, `test_verify_attack.py`, `redo_list.py`, `test_wormhole_autoswitch/test.c`; `analyze.ps1`, `run_wizard.ps1`; docs + rebuilt wormhole/tree/DLSU tables). Do NOT push `mesh_config.h` attacker-MAC lines if the wizard changed them.
3. Work the redo list (wizard Campaign [5]). wormhole/linear/G402/stationary re-verified = OK (#40, D6 ticked). A Campaign CHECK 'newer capture exists' clears only with a logged verification block, not the Verify button.
4. Optional: re-run `analyze.ps1 -All` so every table uses the `transition` segment (verdicts unchanged, dry-run proven).
5. Decide star wormhole (checklist A24) before anyone runs it. First real GUI run: Run a capture -> Start -> Live run (compile, wipe+flash+run, START on the dashboard, Finish + export root); then Data > Import / export. Check the port pickers show MACs after the reflash (GET_ID).
6. Paper edits week of oct. 19: A21-A23, B-lat, D-20..D-22.

## Blockers / open questions
- ⛔ **Victim crashes (PANIC / INT_WDT)** in blackhole/tree/G402/highload oct. 17 (verification #39 -> recapture D9). Cause unknown: recapture with the Live run's crash watch ON so the backtrace is recorded + decoded, then fix before more highload runs.
- ⛔⛔ BSOD 0xB8: NEVER Ctrl+C an export or SD read; never reset/unplug a board while it is read; boards DIRECT into the laptop.
- ⚠️ Moving boards after Phase 0: tree runs corrupt the baseline; wormhole roles are locked. Use the READY window, then START.
- ⚠️ The oct. 16 telemetry stall on the root's direct children (wormhole/tree/DLSU, 28-32 % bunched rows) is NOT diagnosed - check SD/flash write warnings before recapturing.
- ⚠️ `datasets/exports/wormhole/linear/G402/stationary/trimmed/` holds the OLD reversed run - analyze.ps1 re-trims, don't point tools there by hand.

## Recently done (last 2 max, newest first — older entries roll to ARCHIVE.md)
- oct. 17 (Angelo) — GUI: redesign + speed-ups, then FULL GUI (Live run + root dashboard, import page, in-window tools, GET_ID no-reset board ID); wormhole audit (star blocked, A24).
- oct. 16-17 (Angelo) — verifications #33-#38, wizard 'b' everywhere + redesign, redo-list topology, wormhole firmware fix + root gates + manual START, verifier redesign (2 wormhole primaries, study tags), preprocess transition/anchor fixes, redo list, wizard redo-list + tunnel prompt fixes.

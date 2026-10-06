# Status

<!-- Overwrite each session. Hard cap: 40 lines — move "done" items to ARCHIVE.md. First thing a new session reads. -->
**Updated:** oct. 5, 2026 (Basti): verification #4 (blackhole/linear/DLSU_Library/stationary r1) added; oct. 4 wizard/tooling session still NOT committed (Basti pushes it himself, stage list below). Previous STATUS (oct. 3, Angelo) is at the bottom of ARCHIVE.md. Facts + reasons: top 5 entries of MEMORY.md.

## ⚠️ Working copies / layout
Angelo `A:\Angelo\Excelsior\THESIS\T` · Basti `C:\Users\Basti\OneDrive\Documents\Thesis\THESIS3` · branch `THESIS3`, `git pull` first. Data in `ESP32-Environment/datasets/{exports,analysis,archive,PCAP,run_logs}`; PCAP + run logs + `eda_output/` git-ignored. **Live board roster: https://claude.ai/artifact/KteBqiYpZedMjG9ppFjreh** (wizard still reads `member_boards.json`; ask Claude to sync).

## Where things stand
- **BSOD 0xB8 root-caused:** a bug in the CP210x driver `silabser.sys`, proven from a full crash dump. Trigger: a USB read cut short (Ctrl+C mid-export, or a board reset/unplugged mid-read). See MEMORY oct. 4.
- **NEW wizard option:** MAINTENANCE > Wormhole UART tunnel test (quick 10 s / 2-min soak), with `uart_link_test` rewritten. It has now RUN on real boards: both directions PASS. Q/Enter stops a listen early (the key press itself is untested). Panel answer: `docs/panel-answers/2026-10-04_WORMHOLE-TESTING-EXPLAINER.md`.
- **Presets renamed** to attack-topology-location-scenario on Basti's laptop (24 files, all members). `Bas/blackhole-linear-g402-jitter.json` was named "star" but holds linear.
- **Children skip the export INSTANTLY by default** after Ctrl+] (`run.ps1 -SkipExportNow`; the wizard asks: [1] skip instantly / [2] export over USB). Root unchanged.
- **Node labels:** node1 = root; Add-node fills gaps from node2. Add-node's attacker question was reworded. **Edit preset > Expected children** saves how many children the root waits for (default at the run's "other laptops" question).
- **NEW capture verified (#4, oct. 5): blackhole/linear/DLSU_Library/stationary r1 is USABLE.** Attack CONFIRMED. PDR `-inf` = baseline 1,805/1,805 delivered (σ = 0); quote it as "z undefined", not −∞. Victims 704B/FE90 0/180. Gate 2 Topology FAIL is a false alarm (a parent change during the root-reflash boot segment). Exports are staged, not committed.

## Uncommitted on Basti's laptop
- Code + docs: `ESP32-Environment/run.ps1`, `ESP32-Environment/run_wizard.ps1`, `ESP32-Environment/uart_link_test/` (README + main/uart_link_test.c), `Setups/WORMHOLE-SETUP.md`, `ESP32-Environment/docs/dataset-verification.md` (#4), `verification/2026-10-05_pdr-z-minus-inf.md`, `docs/panel-answers/` (new explainer + REVIEWER-QUESTIONS §10), `FILEMAP.md`, `STATUS.md`, `MEMORY.md`, `ARCHIVE.md`.
- Presets (renames): via DATA SYNC, not a code commit. `push_data.py push --area presets` sends Bas's new names; `delete --area presets` removes the old names on GitHub.
- Not from this session, user's call: `mesh_config.h`, `root_main.c`, `docs/highload-collapse/COOLDOWN-RECOVERY-2026-09-30.md`, `skills/verify.zip`.

## Next step
1. Basti: commit + push the code/docs; sync the presets (push, then delete the old names). Tell Kyle and Cal their presets were renamed here. Until their old names are deleted on GitHub, a presets pull brings them back as duplicates.
2. Tunnel test: a good wire PASSES both ways (done). Still to do: pull the wire into A's GPIO16 to check that B->A then FAILs, and press Q once to confirm the early stop.
3. Try the child instant skip once in a real run (Ctrl+] on a child -> straight to the next board, no export).
4. Everyone `git pull` + REFLASH; recapture tree/G402/stationary r2 (verification #2).
5. Re-run star G402 BURST; a 7-board highload run; wormhole tree once a real tree forms. Still to capture: jitter r2+r3, mobility, powercycle, star burst.
6. Open user calls (MEMORY oct. 2): tree fan-out cap / pinned victims; duplicate controls in `exports/baseline/tree/G402/stationary/`.

## Blockers / open questions
- ⛔⛔ BSOD 0xB8 (CP210x driver): NEVER Ctrl+C an export or SD read; never reset or unplug a board while it is being read; boards DIRECT into the laptop. If it recurs: try SiLabs' legacy 6.7.x driver (untested).
- ⚠️ When cleaning old data, delete only `analysis\baseline|blackhole|wormhole` — NEVER `ESP32-Environment\analysis\` itself.
- ⚠️ BASTI: delete LOCAL `datasets/exports/blackhole/star/G402/burst/` before your next data push.
- ⚠️ PDR/LatencyHopRatio single-feature perfect (framing). HT20 vs HT40 don't pool (D-14). D-12 vs signed Milestone Form — adviser.
- ⚠️ Before any pull: `git diff --cached --stat` - a merge refuses ANY staged change on a path it touches.

## Recently done (last 2 max, newest first — older entries roll to ARCHIVE.md)
- oct. 5 (Basti) — blackhole/linear/DLSU_Library/stationary r1 verified (#4): USABLE; PDR -inf explained from raw data; re-trim is a no-op.
- oct. 4 (Basti) — BSOD root-caused (silabser.sys); UART tunnel test (+ Q/Enter early stop); MACs in target/attacker/Node A-B pickers; wormhole panel explainer; preset rename; child skip-export; node1 = root labels.

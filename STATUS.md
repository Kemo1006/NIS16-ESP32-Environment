# Status

<!-- Overwrite each session. Hard cap: 40 lines — move "done" items to ARCHIVE.md. First thing a new session reads. -->
**Updated:** oct. 6, 2026 (Angelo): merged Basti's oct. 4–5 push (wizard/tooling, presets renamed, DLSU_Library + highload r5 data) with Angelo's verification #5 + tree/G402/jitter data. Everything is on GitHub `THESIS3`. Facts + reasons: top entries of MEMORY.md.

## ⚠️ Working copies / layout
Angelo `A:\Angelo\Excelsior\THESIS\T` · Basti `C:\Users\Basti\OneDrive\Documents\Thesis\THESIS3` · branch `THESIS3`, `git pull` first. Data in `ESP32-Environment/datasets/{exports,analysis,archive,PCAP,run_logs}`; PCAP + run logs git-ignored. **Analysis tables + `eda_output/` of the 10 live blackhole cells are now ON GitHub** (force-added oct. 7, `9ed0ce8`); new cells' analysis is still ignored by default - `git add -f` to share it. **Live board roster: https://claude.ai/artifact/KteBqiYpZedMjG9ppFjreh**.

## Where things stand
- **Verification log** `ESP32-Environment/docs/dataset-verification.md`: #5 FE90 stale firmware · #4 DLSU_Library/stationary USABLE · #3 tree/G402/burst USABLE (caveat) · #2 sweep (tree/G402/stationary DEGRADED) · #1 tree/G402/jitter.
- ⚠️ **`B4BFE932FE90` (Kyle's board) was flashed with a STALE pre-sep-21 image** before the oct. 2 tree burst run (from another laptop) — it addressed its probes to the attacker. **REFLASH it from an up-to-date checkout** and check every laptop has pulled before flashing.
- **PDR `-inf`** = baseline sd 0 (perfect delivery) — by design, PASS; in the thesis say "z undefined (σ = 0)".
- **BSOD 0xB8 root-caused:** CP210x driver `silabser.sys`, triggered by a USB read cut short (MEMORY oct. 4).
- **Wizard (Basti, oct. 4):** UART tunnel test (both directions PASS on boards), MACs in pickers, children skip export by default after Ctrl+], node1 = root, presets store "Expected children".
- **Presets renamed** to `attack-topology-location-scenario.json` (all members, on GitHub). `Bas/blackhole-linear-g402-jitter.json` was named "star" but holds linear.
- **Presets on GitHub are current** (oct. 7, `2a12ac0`): Angelo's newer oct. 1-2 saves moved onto the new names; old stash used up. Still local: `mesh_config.h` attacker line (per-run pick), sdkconfig x2, dependencies.lock.
- EDA PCA fix + sniffer stop confirmation pushed (`4def0f8`). Not yet run on hardware: highload root queue (`cb22106`), hardcode audit (`44a9672`).

## Next step
1. Everyone `git pull` + REFLASH (same commit on every laptop); reflash FE90 first.
2. Recapture tree/G402/stationary r2 (verification #2) and tree/G402/burst r2 with all 8 boards.
3. Tunnel test: pull the wire into A's GPIO16 to confirm B->A FAILs; press Q once to confirm early stop.
4. Try the child instant export-skip once in a real run.
5. Re-run star G402 BURST; 7-board highload; wormhole tree once a real tree forms. Still to capture: jitter r2+r3, mobility, powercycle.
6. Open user calls: firmware-commit check in the roster gate (idea, MEMORY oct. 3); tree fan-out cap / pinned victims; duplicate controls in `exports/baseline/tree/G402/stationary/`.

## Blockers / open questions
- ⛔⛔ BSOD 0xB8: NEVER Ctrl+C an export or SD read; never reset/unplug a board while it is read; boards DIRECT into the laptop.
- ⚠️ When cleaning old data, delete only `analysis\baseline|blackhole|wormhole` — NEVER `ESP32-Environment\analysis\` itself.
- ⚠️ BASTI: delete LOCAL `datasets/exports/blackhole/star/G402/burst/` before your next data push.
- ⚠️ Never commit root/child `sdkconfig` or `dependencies.lock` (IDF 5.3.5 vs 5.5.4 laptops).
- ⚠️ PDR/LatencyHopRatio single-feature perfect (framing). HT20 vs HT40 don't pool (D-14). D-12 vs signed Milestone Form — adviser.
- ⚠️ Before any pull: `git diff --cached --stat` - a merge refuses ANY staged change on a path it touches.

## Recently done (last 2 max, newest first — older entries roll to ARCHIVE.md)
- oct. 6 (Angelo) — FE90 root cause (stale firmware, #5); tree/G402/jitter data pushed; merged Basti's push.
- oct. 5 (Basti) — DLSU_Library/stationary r1 verified (#4): USABLE; PDR -inf explained.

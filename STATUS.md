# Status

<!-- Overwrite each session. Hard cap: 40 lines — move "done" items to ARCHIVE.md. First thing a new session reads. -->
**Updated:** oct. 3, 2026 (Angelo). Oct. 2 session's work COMMITTED + PUSHED to `THESIS3` (see `git log`); only the do-not-commit items below stay local. Previous STATUS in ARCHIVE.md (bottom). Facts + reasons: MEMORY.md top ~6 entries.

## ⚠️ Working copies / layout
Angelo `A:\Angelo\Excelsior\THESIS\T` · Basti `C:\Users\Basti\OneDrive\Documents\Thesis\THESIS3` · branch `THESIS3`, `git pull` first. Data in `ESP32-Environment/datasets/{exports,analysis,archive,PCAP,run_logs}`; PCAP + run logs + `eda_output/` git-ignored. **Live board roster: https://claude.ai/artifact/KteBqiYpZedMjG9ppFjreh** (wizard still reads `member_boards.json`; ask Claude to sync).

## Where things stand
- **Dataset verification log:** `ESP32-Environment/docs/dataset-verification.md` (CLAUDE.md rule: every verify request adds a dated block on top). #2 = sweep of all 9 live cells: 7 USABLE, highload PARTIAL (known), **tree/G402/stationary DEGRADED**.
- **tree/G402/burst r1 verified + pushed** (oct. 3, verification #3): burst FIRED (fix `6b90df5` proven), CONFIRMED; ⚠️ `FE90` = hidden 3rd victim (wrong parent field, unlabelled).
- **tree/G402/jitter r1 captured + verified** (oct. 2 evening): real tree depth 2, 1 victim, jitter 331/206 s, BLACKHOLE CONFIRMED.
- **EDA PCA/t-SNE fix** (`analysis/eda.py`): victim attack windows were dropped; plots regenerated for linear/G402/jitter, linear/home/burst, partial_mesh/G402/jitter, tree/G402/jitter. Teammates must re-run EDA on those (eda_output is git-ignored).
- **Sniffer stop asks 'are you sure'** (`tools/sniff.py`: Enter / Ctrl+C -> Y to stop). Tested with a simulated board only.
- **Wizard pre-build skips unchanged firmware** + explains each build (`9aec136`, pushed).
- Not yet run on hardware: highload root queue (`cb22106`), hardcode audit (`44a9672`). Burst fix proven oct. 2 tree run.

## Uncommitted on Angelo's laptop
- Oct. 2 session files (eda.py, sniff.py, run_wizard.ps1, dataset-verification.md, root docs): pushed oct. 3.
- On purpose, do NOT commit (tree/G402/burst data now pushed): `mesh_config.h` attacker line, `sdkconfig` x2, `dependencies.lock`, presets, `archive/*` folders, untracked datasets.

## Next step
1. Everyone `git pull` + REFLASH (burst + highload + nickname fixes); same attacker on every laptop.
2. **Recapture tree/G402/stationary as r2** (2 boards dropped out mid-run in r1; verification log #2).
3. Try the sniffer confirmation once on a real board (Enter -> Y stops; Enter -> other key keeps recording).
4. Flat tree retry rules + proposed TREE fan-out cap / pinned victims (not built, user's call): MEMORY oct. 2.
5. Duplicate controls in `exports/baseline/tree/G402/stationary/` (Basti's `git mv` or delete) - user's call.
6. Re-run star G402 BURST (`burst : FIRED`); 7-board highload run (`[RXSTALL] ... dropped 0`); wormhole tree once a real tree forms.
7. Jitter: decide whether preprocess keeps the extra baseline; capture jitter r2 + r3. Not yet captured: mobility, powercycle, star burst.

## Blockers / open questions
- ⛔⛔ Boards DIRECT into the laptop, never dock/hub (BSOD 0xB8). Never pull an SD card mid-run.
- ⚠️ When cleaning old data, delete only `analysis\baseline|blackhole|wormhole` — NEVER `ESP32-Environment\analysis\` itself.
- ⚠️ BASTI: delete LOCAL `datasets/exports/blackhole/star/G402/burst/` before your next data push.
- ⚠️ PDR/LatencyHopRatio single-feature perfect (framing). HT20 vs HT40 don't pool (D-14). D-12 vs signed Milestone Form — adviser.
- ⚠️ Before any pull: `git diff --cached --stat` - a merge refuses ANY staged change on a path it touches.

## Recently done (last 2 max, newest first — older entries roll to ARCHIVE.md)
- oct. 2 night (Angelo) — Sniffer stop confirmation; 9-cell dataset verification sweep + verification log doc + CLAUDE.md rule.
- oct. 2 (Angelo) — tree/G402/jitter verified sound; EDA PCA/t-SNE fix, 4 cells' plots regenerated.

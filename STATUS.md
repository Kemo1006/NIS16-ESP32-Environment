# Status

<!-- Overwrite each session. Hard cap: 40 lines — move "done" items to ARCHIVE.md. First thing a new session reads. -->
**Updated:** oct. 7, 2026 (Basti): merged Angelo's oct. 6–7 pushes (FE90 #5, presets synced `2a12ac0`, analysis tables on GitHub `9ed0ce8`) with Basti's oct. 7 commit `d8019ac` (star/DLSU data, wizard Attacker row, BSOD tool fix); pushed. Basti's star/DLSU block is now verification **#6**. Facts + reasons: top entries of MEMORY.md.

## ⚠️ Working copies / layout
Angelo `A:\Angelo\Excelsior\THESIS\T` · Basti `C:\Users\Basti\OneDrive\Documents\Thesis\THESIS3` · branch `THESIS3`, `git pull` first. Data in `ESP32-Environment/datasets/{exports,analysis,archive,PCAP,run_logs}`; PCAP + run logs git-ignored; analysis tables + EDA of the live blackhole cells are force-tracked (MEMORY oct. 7, Angelo). **Live board roster: https://claude.ai/artifact/KteBqiYpZedMjG9ppFjreh** (wizard still reads `member_boards.json`; ask Claude to sync).

## Where things stand
- **Verification log** `ESP32-Environment/docs/dataset-verification.md`: #6 star/DLSU/stationary USABLE · #5 FE90 stale firmware · #4 linear/DLSU/stationary USABLE · #3 tree/G402/burst USABLE (caveat) · #2 sweep · #1 tree/G402/jitter.
- **#6 (oct. 7):** hub attacker `20500DE70C80`, all 6 leaves 1.000 → 0.000; Topology FAIL = root-reflash boot segment (as #4). Star preset fixed (node4 `...0c:80` = attacker), junk tree/DLSU file deleted.
- ⚠️ **`B4BFE932FE90` (Kyle's board) ran a STALE pre-sep-21 image** in the oct. 2 tree burst run — REFLASH it from an up-to-date checkout.
- **PDR `-inf`** = baseline sd 0 (perfect delivery) — PASS; in the thesis say "z undefined (σ = 0)".
- **BSOD 0xB8:** `silabser.sys` crashes when its receive buffer fills (port open, not read). Tools grow it to 1 MiB (`tools/serial_guard.py`); not hardware-tested.
- **Wizard:** UART tunnel test (both directions PASS), MACs in pickers, children skip export by default, node1 = root, Expected children, NEW Edit preset row [7] **Attacker** (star = HUB, other-laptop attacker by MAC; 14 scripted cases, not live yet), wormhole A/B rows pink.
- **Campaign plan:** DLSU star/blackhole slot 1 powercycle → stationary (checklist 4/144); other off-plan cells left as-is (user call, MEMORY oct. 7).
- **Presets on GitHub are current** (`2a12ac0`). EDA PCA fix + sniffer stop confirmation pushed (`4def0f8`). Not yet run on hardware: highload root queue (`cb22106`), hardcode audit (`44a9672`).

## Still local on Basti's laptop (not in the push, user's call)
- `mesh_config.h` attacker line (per-run pick, now `f4:...:18` — never commit), `presets/Bas/wormhole-linear-dlsu_library-stationary.json` (modified), 3 new `presets/Bas/blackhole-partial_mesh-dlsu_library-*.json`, `datasets/analysis/blackhole/star/DLSU_Library/burst/` (the oct. 7 11:16 star burst run — not verified yet).

## Next step
1. Everyone `git pull` + REFLASH (same commit on every laptop); reflash FE90 first.
2. Verify blackhole/star/DLSU_Library/burst r1 (oct. 7, ~11:16 AM), then decide on its analysis folder.
3. Recapture tree/G402/stationary r2 (verification #2) and tree/G402/burst r2 with all 8 boards.
4. Tunnel test: pull the wire into A's GPIO16 to confirm B->A FAILs; press Q once to confirm early stop.
5. Try the child instant export-skip and the Edit preset Attacker row once in a real run.
6. Re-run star G402 BURST; 7-board highload; wormhole tree once a real tree forms. Still to capture: jitter r2+r3, mobility, powercycle.
7. Open user calls: firmware-commit check in the roster gate (idea, MEMORY oct. 3); tree fan-out cap / pinned victims; duplicate controls in `exports/baseline/tree/G402/stationary/`.

## Blockers / open questions
- ⛔⛔ BSOD 0xB8: NEVER Ctrl+C an export or SD read; never reset/unplug a board while it is read; boards DIRECT into the laptop.
- ⚠️ When cleaning old data, delete only `analysis\baseline|blackhole|wormhole` — NEVER `ESP32-Environment\analysis\` itself.
- ⚠️ Never commit root/child `sdkconfig` or `dependencies.lock` (IDF 5.3.5 vs 5.5.4 laptops).
- ⚠️ PDR/LatencyHopRatio single-feature perfect (framing). HT20 vs HT40 don't pool (D-14). D-12 vs signed Milestone Form — adviser.
- ⚠️ Before any pull: `git diff --cached --stat` - a merge refuses ANY staged change on a path it touches.

## Recently done (last 2 max, newest first — older entries roll to ARCHIVE.md)
- oct. 7 (Basti) — #6 star/DLSU r1 USABLE; preset + junk file fixed; Edit preset Attacker row; pink A/B; campaign plan swap; merged with Angelo + pushed.
- oct. 6 (Angelo) — FE90 root cause (stale firmware, #5); tree/G402/jitter data pushed; merged Basti's push.

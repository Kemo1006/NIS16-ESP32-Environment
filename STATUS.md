# Status

<!-- Overwrite each session. Hard cap: 40 lines — move "done" items to ARCHIVE.md. First thing a new session reads. -->
**Updated:** oct. 2, 2026 evening (Angelo, session summary). GitHub `THESIS3` = `36ca4b6` (Basti's 15:37 merge) + this summary. Previous STATUS in ARCHIVE.md (bottom). Facts + reasons: MEMORY.md top ~12 entries.

## ⚠️ Working copies / layout
Angelo `A:\Angelo\Excelsior\THESIS\T` · Basti `C:\Users\Basti\OneDrive\Documents\Thesis\THESIS3` · branch `THESIS3`, `git pull` first. Data in `ESP32-Environment/datasets/{exports,analysis,archive,PCAP,run_logs}`; PCAP + run logs git-ignored. **Live board roster (edit from any laptop): https://claude.ai/artifact/KteBqiYpZedMjG9ppFjreh** - share with Bas + Kyle as Contributor; wizard still reads `member_boards.json` (ask Claude to sync).

## Where things stand
- **Firmware fixes BUILT, NOT YET RUN ON HARDWARE:** burst window (`6b90df5`), highload root writer queue (`cb22106`), hardcode audit (`44a9672`: IDF `%d` fix, nickname now `Board-XX:YY`, phase constants read from mesh_config.h).
- **Captured + verified (live checklist 7/144):** G402 linear/tree/partial/star stationary; linear + partial_mesh jitter (all 9 files each); home linear burst. Checklist staleness is content-based (a pull no longer flips `[x]` to `[~]`).
- **Wormhole tunnel proven on hardware** (Basti, oct. 1 tree/G402) but the tree went FLAT -> tunnel proof only, not a dataset entry. SD importer now files wormhole controls by phase (untested on a real card).
- **Incoming, incomplete:** tree/G402/jitter (Kyle oct. 2, children only; root on another laptop).

## Next step
1. **Everyone `git pull` + REFLASH** (burst + highload + nickname fixes). Every laptop picks the SAME attacker.
2. **Flat tree -> retry:** reposition (victims past the attacker, hearing the root < -80 dBm), then re-run the SAME preset on the SAME ports + same repeat - no recompile, re-flash erases the failed attempt (clean data). Check HOP DEPTH >= 2 at ~30 s. Not built, user's call: lasting fix (A) cap root fan-out in TREE + (B) pin SOME victims under the attacker (D-number); wizard 'Re-run without flashing'. Details: MEMORY oct. 2.
3. **Duplicate controls:** 4 files in `exports/baseline/tree/G402/stationary/` = copies of the wormhole controls. Basti pushes his `git mv`, OR Angelo deletes them - user's call.
4. Re-run star G402 BURST (analysis must print `burst : FIRED`); 7-board highload run (`[RXSTALL] ... dropped 0`).
5. Wormhole tree r1 again once a real tree forms (HOP DEPTH >= 2, B's UPLINK = A). Decide the wormhole EXPOSURE false-alarm fix (Basti, MEMORY oct. 1).
6. Jitter: decide whether preprocess keeps the extra baseline (103 windows); capture jitter r2 + r3.
7. Not yet captured: mobility, powercycle, star burst. Paper: §4.2.2.1 / Fig. 4.17 hub framing (D-16).

## Blockers / open questions
- ⛔⛔ Boards DIRECT into the laptop, never dock/hub (BSOD 0xB8). Never pull an SD card mid-run.
- ⚠️ When cleaning old data, delete only `analysis\baseline|blackhole|wormhole` — NEVER `ESP32-Environment\analysis\` itself.
- ⚠️ **BASTI: delete LOCAL `datasets/exports/blackhole/star/G402/burst/` before your next data push** (re-added 3 times; removed again `3dc7e93`).
- ⚠️ PDR/LatencyHopRatio single-feature perfect (framing). HT20 vs HT40 don't pool (D-14). D-12 vs signed Milestone Form — adviser.
- ⚠️ Before any pull: `git diff --cached --stat` - a merge refuses ANY staged change on a path it touches (bit us oct. 1).
- Uncommitted on Angelo's laptop, on purpose: `mesh_config.h` attacker line, `sdkconfig` x2, `dependencies.lock`, presets, `archive/*` folders.

## Recently done (last 3 max, newest first — older entries roll to ARCHIVE.md)
- oct. 2 (Angelo) — Wizard pre-build skips firmware that hasn't changed (stamp in each build dir) and prints what/why/result + first error; full compile output still shown.
- oct. 2 — Angelo: followed Basti's updates (no conflicts); flat-tree cause found (TREE fan-out 10) + fix proposed; live board roster web page; checklist fixes; star burst duplicates removed (3rd time).
- oct. 2 (Basti/Kyle) — Analysis progress bars (`analysis/progress.py`, outputs identical); checklist "last run" column; campaign plan updated to jitter.

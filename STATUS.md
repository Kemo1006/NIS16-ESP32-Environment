# Status

<!-- Overwrite each session. Hard cap: 40 lines — move "done" items to ARCHIVE.md. First thing a new session reads. -->
**Updated:** oct. 2, 2026 (Basti) — analysis progress bars added. **Uncommitted on Basti's laptop: `tools/import_sdcard.py` + `run_wizard.ps1` (only the hunk at ~2097 is that session's) + wormhole/tree/G402 data + `analysis/{progress,preprocess,features,eda}.py` (progress bars).** Facts + reasons: MEMORY.md top entries.

## ⚠️ Working copies / layout
Angelo `A:\Angelo\Excelsior\THESIS\T` · Basti `C:\Users\Basti\OneDrive\Documents\Thesis\THESIS3` · branch `THESIS3`, `git pull` first. Data in `ESP32-Environment/datasets/{exports,analysis,archive,PCAP,run_logs}`; PCAP + run logs git-ignored (local only). Backup tag: `backup/angelo-2026-10-01`.

## Where things stand
- **TWO FIRMWARE FIXES pushed, both BUILT CLEAN but NOT YET RUN ON HARDWARE:**
  - **Burst** (`6b90df5`): burst never fired on ANY attack run (victim_main.c never got ACTIVE_ATTACK, so it waited for a baseline-only signal). Window now opens at run time.
  - **Highload root overwhelm** (`cb22106`): root wrote arrivals inside its mesh receive task, the RX queue filled, the mesh throttled all children (20/s fell to 3-7/s). Now a queue + separate writer task; root RX queue 64.
- **Burst can't fail silently any more:** `tools/verify_burst.py`; `analyze.ps1` prints `burst : FIRED|NOT FIRED`; wizard blocks a burst target on the attacker and names the sender in the plan.
- **star/G402/stationary r1 = the oct01 2 PM run** (6 victims, integrity/topology PASS, BLACKHOLE CONFIRMED, sniffer paired). Old 12:24 run archived locally (`archive/2026-10-01_star-G402-stationary-replaced/`). star/G402/burst NOT captured yet.
- **linear/G402/jitter r1 ANALYZED + CHECKED (oct. 1 night): integrity 9/9, topology linear OK, BLACKHOLE CONFIRMED 2/2, jitter fired (312.5/190.5 s), pcap PASS.** Root's 2 files now pushed. Full re-verify: analysis rebuilt = identical. EDA PCA/t-SNE bug fixed (attack class was missing; jitter + star stationary plots regenerated). Open: preprocess drops jitter's extra baseline (MEMORY).
- **WORMHOLE TUNNEL WORKS on current firmware (oct. 1 ~16:51, tree/G402):** 180 tunnelled = 180 re-injected = 180 root duplicates, all in phase 2. But the mesh went FLAT (all 7 under root) -> NOT a valid tree run; a child was also unplugged mid-baseline. Files sit in `exports/wormhole/tree/G402/stationary/` (9) — keep as tunnel proof, not a dataset entry. **SD-import bug fixed** (untested on a real board): wormhole controls run plain firmware and were filed under `baseline/`; the importer now files by the rows' phase; all 5 misfiled control CSVs moved to wormhole/ (4 staged via git mv).
- Campaign (live checklist): **7/144** - G402 linear/tree/partial/star stationary, linear+partial jitter; home linear burst. Checklist staleness now content-based, table aligned (pushed).

## Next step
1. **Everyone `git pull` + REFLASH** (both firmware fixes). Every laptop picks the SAME attacker.
2. **Re-run star G402 BURST:** exactly ONE laptop's plan shows a victim `<< burst TARGET`. Analysis must print `burst : FIRED` (= burst fix proven).
3. **7-board highload run:** reflash the ROOT, save the run log. Fixed if arrivals stay ~20/s through cooldown and `[RXSTALL] ... dropped 0` (`docs/highload-collapse/COOLDOWN-RECOVERY-2026-09-30.md` §13).
4. **Decide:** should preprocess keep jitter's extra baseline (103 windows)? Capture linear/G402/jitter r2 + r3. Others: re-run analyze on jitter after pull (feature tables/EDA are git-ignored).
5. **Basti: delete local `datasets/exports/blackhole/star/G402/burst/`** (his push re-added it; removed again in `4a00a3b`) + local `linear/G402/burst` + `linear/G402/highload`.
6. **Wormhole tree r1 again:** get a REAL tree first (HOP DEPTH >= 2, no `WARN flat like a star`, B's UPLINK = A) BEFORE baseline starts. Every board heard the root above -78 dBm = flat. Decide: placement (root < ~-80 dBm at deep boards) vs firmware RSSI threshold vs fixed parents (MEMORY). Don't unplug boards mid-run.
   + Basti: commit/push the importer fix (stage `tools/import_sdcard.py` + run_wizard.ps1 hunk ~2097 only). Decide: fix wormhole EXPOSURE false alarm (mesh_setup.c + exposure.py)?
7. Not yet captured: mobility, powercycle. Paper: §4.2.2.1 / Fig. 4.17 hub framing (D-16).

## Blockers / open questions
- ⛔⛔ Boards DIRECT into the laptop, never dock/hub (BSOD 0xB8). Never pull an SD card mid-run.
- ⚠️ When cleaning old data, delete only `analysis\baseline|blackhole|wormhole` — NEVER `ESP32-Environment\analysis\` itself.
- ⚠️ PDR/LatencyHopRatio single-feature perfect (framing). HT20 vs HT40 don't pool (D-14). D-12 vs signed Milestone Form — adviser.
- ⚠️ **BASTI: delete your LOCAL `datasets/exports/blackhole/star/G402/burst/` BEFORE your next data push.** The 3 duplicates (byte-identical to star/G402/stationary) were re-added by your `589af2d` (3rd time) and removed again oct. 1 night. partial_mesh/G402/jitter r1 children are on GitHub (Basti + ongky).
- Presets with star/burst content under a LINEAR name: `Bas/` + `Cal/linear-blackhole-stationary-g402.json` — not pushed; fix/rename.
- Uncommitted on Angelo's laptop, on purpose: `mesh_config.h` attacker line, `sdkconfig` x2, `dependencies.lock`, 4 presets, `archive/*` folders.

## Recently done (last 3 max, newest first — older entries roll to ARCHIVE.md)
- oct. 2 (Basti) — Progress bar + ETA in M6/M7/M8 analysis (`analysis/progress.py`); outputs byte-identical; shows in wizard/menu/run.ps1, not analyze.ps1.
- oct. 2 — Campaign checklist (`inventory_cells.py --checklist`, wizard "Campaign progress") has a new **last run** column: newest capture date/time + scenario per attack row. Display only; run through the real checklist, not through the wizard menu.
- oct. 1 (night, Basti) — Wormhole tunnel proven on hardware (tree attempt went flat); SD importer files wormhole controls by phase; 5 misfiled control CSVs moved to wormhole/; exposure false alarm diagnosed.

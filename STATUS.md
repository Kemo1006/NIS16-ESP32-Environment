# Status

<!-- Overwrite each session. Hard cap: 40 lines — move "done" items to ARCHIVE.md. First thing a new session reads. -->
**Updated:** oct. 1, 2026 night (Angelo, session summary) — **GitHub `THESIS3` = this session's commit (jitter verified + root files, wizard target ports, EDA fix).** Facts + reasons: MEMORY.md top ~10 entries.

## ⚠️ Working copies / layout
Angelo `A:\Angelo\Excelsior\THESIS\T` · Basti `C:\Users\Basti\OneDrive\Documents\Thesis\THESIS3` · branch `THESIS3`, `git pull` first. Data in `ESP32-Environment/datasets/{exports,analysis,archive,PCAP,run_logs}`; PCAP + run logs git-ignored (local only). Backup tag: `backup/angelo-2026-10-01`.

## Where things stand
- **TWO FIRMWARE FIXES pushed, both BUILT CLEAN but NOT YET RUN ON HARDWARE:**
  - **Burst** (`6b90df5`): burst never fired on ANY attack run (victim_main.c never got ACTIVE_ATTACK, so it waited for a baseline-only signal). Window now opens at run time.
  - **Highload root overwhelm** (`cb22106`): root wrote arrivals inside its mesh receive task, the RX queue filled, the mesh throttled all children (20/s fell to 3-7/s). Now a queue + separate writer task; root RX queue 64.
- **Burst can't fail silently any more:** `tools/verify_burst.py`; `analyze.ps1` prints `burst : FIRED|NOT FIRED`; wizard blocks a burst target on the attacker and names the sender in the plan.
- **star/G402/stationary r1 = the oct01 2 PM run** (6 victims, integrity/topology PASS, BLACKHOLE CONFIRMED, sniffer paired). Old 12:24 run archived locally (`archive/2026-10-01_star-G402-stationary-replaced/`). star/G402/burst NOT captured yet.
- **linear/G402/jitter r1 ANALYZED + CHECKED (oct. 1 night): integrity 9/9, topology linear OK, BLACKHOLE CONFIRMED 2/2, jitter fired (312.5/190.5 s), pcap PASS.** Root's 2 files now pushed. Full re-verify: analysis rebuilt = identical. EDA PCA/t-SNE bug fixed (attack class was missing; jitter + star stationary plots regenerated). Open: preprocess drops jitter's extra baseline (MEMORY).
- Hardcode audit DONE + pushed: IDF `%d` bug, phase constants from mesh_config.h (`tools/mesh_constants.py`), stale firmware nickname table removed (`Board-XX:YY`), board_check/run_matrix no hardcoded MACs/COMs, `.mcp.json` untracked. Firmware nickname change shows after the next reflash.
- Wizard: scenario-TARGET prompts show `plugged in`/`NOT PRESENT` + a 'Detect ports' option (pushed, not yet used on real boards). Attacker picker lists every known board.
- Campaign (live checklist): **7/144** - G402 linear/tree/partial/star stationary, linear+partial jitter; home linear burst. Checklist staleness now content-based, table aligned (pushed).

## Next step
1. **Everyone `git pull` + REFLASH** (both firmware fixes). Every laptop picks the SAME attacker.
2. **Re-run star G402 BURST:** exactly ONE laptop's plan shows a victim `<< burst TARGET`. Analysis must print `burst : FIRED` (= burst fix proven).
3. **7-board highload run:** reflash the ROOT, save the run log. Fixed if arrivals stay ~20/s through cooldown and `[RXSTALL] ... dropped 0` (`docs/highload-collapse/COOLDOWN-RECOVERY-2026-09-30.md` §13).
4. **Decide:** should preprocess keep jitter's extra baseline (103 windows)? Capture linear/G402/jitter r2 + r3. Others: re-run analyze on jitter after pull (feature tables/EDA are git-ignored).
5. **Basti: delete local `datasets/exports/blackhole/star/G402/burst/`** (his push re-added it; removed again in `4a00a3b`) + local `linear/G402/burst` + `linear/G402/highload`.
6. First wormhole run on current firmware (pre-flight passed; test the UART cable with `uart_link_test` first).
7. Not yet captured: mobility, powercycle. Paper: §4.2.2.1 / Fig. 4.17 hub framing (D-16).

## Blockers / open questions
- ⛔⛔ Boards DIRECT into the laptop, never dock/hub (BSOD 0xB8). Never pull an SD card mid-run.
- ⚠️ When cleaning old data, delete only `analysis\baseline|blackhole|wormhole` — NEVER `ESP32-Environment\analysis\` itself.
- ⚠️ PDR/LatencyHopRatio single-feature perfect (framing). HT20 vs HT40 don't pool (D-14). D-12 vs signed Milestone Form — adviser.
- ⚠️ **star/G402/burst duplicates RE-ADDED a 3rd time** by Basti's `589af2d` (oct. 1 15:46, merged `ffe25a5`). Deleted + staged on Angelo's laptop (not by Claude), NOT committed - user to confirm before deleting again; Basti must delete his LOCAL copies first. partial_mesh/G402/jitter r1 children now on GitHub (Basti + ongky).
- Presets with star/burst content under a LINEAR name: `Bas/` + `Cal/linear-blackhole-stationary-g402.json` — not pushed; fix/rename.
- Uncommitted on Angelo's laptop, on purpose: `mesh_config.h` attacker line, `sdkconfig` x2, `dependencies.lock`, 4 presets, `archive/*` folders.

## Recently done (last 3 max, newest first — older entries roll to ARCHIVE.md)
- oct. 1 (night) — linear/G402/jitter fully verified (rebuild = identical, all gates PASS, jitter fired); EDA PCA/t-SNE lost-attack-class bug fixed; wizard target prompt shows port status + Detect ports.
- oct. 1 (eve) — Burst firmware bug found + fixed; highload root fix; verify_burst + wizard burst checks; star stationary replaced by 2 PM run; burst duplicates removed twice.
- oct. 1 — Star hub proven on hardware; attacker MAC from the wizard; split-preset fixes; Basti's merge audited; verifier matrix 33/33; wormhole pre-flight.

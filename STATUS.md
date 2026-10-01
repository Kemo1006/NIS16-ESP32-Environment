# Status

<!-- Overwrite each session. Hard cap: 40 lines — move "done" items to ARCHIVE.md. First thing a new session reads. -->
**Updated:** oct. 1, 2026 (Angelo, session summary) — **GitHub `THESIS3` = `3891315`, everything pushed, laptop in sync.** Previous STATUS archived in ARCHIVE.md (bottom). Facts + reasons: MEMORY.md top ~15 entries.

## ⚠️ Working copies / layout
Angelo `A:\Angelo\Excelsior\THESIS\T` · Basti `C:\Users\Basti\OneDrive\Documents\Thesis\THESIS3` · branch `THESIS3`, `git pull` first. Data in `ESP32-Environment/datasets/{exports,analysis,archive,PCAP,run_logs}`; docs filed by topic (`docs/README.md`). PCAP + run logs are git-ignored (local only). Backup tag of Angelo's work: `backup/angelo-2026-10-01`.

## Where things stand
- **Star + blackhole = attacker is the HUB (D-16), WORKS ON HARDWARE.** `star/G402/stationary` r1 is now the oct01 2 PM run (6 victims, all gates PASS/CONFIRMED) - replaced the 12:24 run (5 victims; archived locally). Star BURST still NOT captured: 2 attempts failed from a firmware bug (fixed oct. 1, untested on hardware).
- **node8 (`F4:2D:C9:73:E6:18`)** telemetry lost from its board: 6 victims, 5 with telemetry. Data unchanged — state it in the write-up.
- **Wizard builds the picked attacker MAC into every blackhole board** (`run.ps1 -AttackerMac`), so `mesh_config.h` no longer decides it. Victims-only laptops get a numbered list of known attackers (newest real run first) PLUS every other known board (to pick a NEW attacker) — type the number.
- Multi-laptop: no crash on a missing burst target (asks y/N); root must be told the TOTAL child count across laptops.
- **Campaign:** 5/144 done (G402: linear/tree/partial/star stationary; home linear burst). Verifier matrix over all 33 runs: 0 crashes, every verdict correct.
- Basti's 7 commits merged + audited: nothing broken (15/15 firmware variants + wormhole root + sniffer build clean, analysis values identical).

## Next step
1. **Everyone `git pull`, then REFLASH via the wizard** (firmware changed: attacker-MAC build flag, Basti's RXSTALL/heartbeat tree). Every laptop picks the SAME attacker.
2. **Re-run star G402 BURST** — burst firmware bug FIXED oct. 1 (victim never opened the window on attack runs). `git pull` + REFLASH the target victim; exactly ONE laptop's plan shows `<< burst TARGET`. Afterwards the analysis prints `burst : FIRED`. Basti/Kyle: delete local `exports/blackhole/star/G402/burst/` first.
3. **Basti: delete local copies** of `linear/G402/burst` + `linear/G402/highload` (`push_data.py delete-local --area exports`) — his push re-added them once already (re-deleted in `ff8059f`).
4. **Highload collapse FIX built (oct. 1, untested):** root writes arrivals from a queue, not the receive task. `git pull`, REFLASH THE ROOT, run 7-board highload, save the run log: `[RXSTALL] … dropped 0` + arrivals ~20/s through cooldown = fixed (doc §13). Old highload r2/r3 baselines stay broken.
5. **First wormhole run on current firmware** (last hardware-confirmed: Jul 20). Pre-flight passed: all 4 wormhole builds clean, analysis tested on archived runs. Test the UART cable with `uart_link_test` first; Node A's end-of-run "TUNNEL CARRIED NOTHING" banner = unusable run.
6. Not yet captured anywhere: jitter, mobility, powercycle scenarios.
7. Paper: §4.2.2.1 / Fig. 4.17 → "hub is the attacker, root one hop behind" (D-16 + framing sentence in `memory/star-hub-forcing-2026-10.md`).

## Blockers / open questions
- ⛔⛔ Boards DIRECT into the laptop, never dock/hub (BSOD 0xB8). Never pull an SD card mid-run.
- ⚠️ When cleaning old data, delete only `analysis\baseline|blackhole|wormhole` — NEVER `ESP32-Environment\analysis\` itself (the code folder was deleted once on oct. 1; restored from git).
- ⚠️ Checklist "analysis older than capture" after a `git pull` = file-time false alarm → re-run `analyze.ps1` for that cell.
- ⚠️ PDR/LatencyHopRatio single-feature perfect (framing decision). LatencyHopRatio direction vs Zhukabayeva — leave as-is.
- ⚠️ HT20 vs HT40 captures don't pool (D-14). D-12 vs the signed Milestone Form — adviser decision.
- `Bas/linear-blackhole-stationary-g402.json` holds STAR/BURST content (name mismatch) — deliberately not pushed; Basti to fix.
- Uncommitted on Angelo's laptop, on purpose: `mesh_config.h` attacker line, `sdkconfig` ×2, `dependencies.lock`, 4 re-saved presets, staged `tools/exports/run_ledger.csv` deletion.

## Recently done (last 3 max, newest first — older entries roll to ARCHIVE.md)
- oct. 1 — Star hub proven on hardware; attacker MAC from the wizard (+ known-attacker list); split-preset fixes; star run moved burst→stationary; Basti's merge audited; verifier matrix 33/33; wormhole pre-flight; `trim_run` cross-drive fix.
- sep. 30 — Star+blackhole hub designed (D-16); verifier/validator fixes (missing attacker → INCONCL, per-source drop check); duplicate/incomplete linear G402 data removed; G402 partial_mesh + tree runs completed on GitHub.
- sep. 30 — Docs reorganized by topic (Basti); highload collapse cause found + RXSTALL instrumentation (Basti).

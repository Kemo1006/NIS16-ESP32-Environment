# Status

<!-- Overwrite each session. Hard cap: 40 lines — move "done" items to ARCHIVE.md. First thing a new session reads. -->

**Updated:** sep. 21, 2026 — **C7 OPTION 1 IS IN (D-12): every node now relays hop-by-hop at the application layer.** Victims send to their PARENT with `MESH_DATA_P2P`; the blackhole attacker runs the *same* shared relay (`components/mesh_common/src/probe_relay.c`) and differs by **one boolean callback**. All 7 firmware variants build clean (`-Wall -Wextra -Werror`, ESP-IDF 5.5.4). Also landed: smart trimmer, `--structure` topology view, `layer`→`hop` (D-11), reviewer answer sheet, Wireshark guide. **Committed, NOT pushed.**

## Current focus
⛔ **BLOCKED ON ADVISER SIGN-OFF, then re-flash.** Do not start the campaign until D-12 is approved — it conflicts with the signed Milestone Form (see Blockers).

## Next step
1. ⛔ **Get adviser sign-off on D-12** (`docs/issue_logs/thesis-deviate.md`). The Milestone Form says *"victims address probes directly to the attacker's MAC"*; Option 1 removes that. **Every milestone CRITERION still passes** (arrival drop, clean phase toggling, all four topologies) — only the mechanism changed, and the form's own *"behavioral equivalent of"* concedes the old model was a substitute. Present it as implementing paper §3.1.3.2's mandated "Forwarding Discipline", not as a shortcut.
2. **Re-flash EVERY board** — schema v2 (F3), F1 `PHASE_ID_UNSET`, F2 runtime MAC and C7 all need it. Mixed old/new boards in one run will NOT work.
3. **One pilot run** (linear · blackhole · G402), then check `ForwardingRatio` immediately: honest nodes ≈ **1.0**, attacker ≈ **0.0**. That single check proves Option 1 worked and the panel's 2:40-4:50 objection is measurably fixed. `analysis/leakage.py` auto-detects the new data and re-admits the relay features — the before/after single-feature score is deliverable **E2**.
4. **Then the campaign.** Decide **128 vs 512** first (`inventory_cells.py --plan --repeats N`): 144 planned ≈ 83 h, 576 ≈ 335 h. The panel explicitly invited shorter runs — `PHASE_BASELINE_S` is now `-D`-overridable.
5. Re-analyse the **8 already-complete runs** (6 are wormhole) — no new capture needed; fastest path to M7's "no feature uniformly NaN".

## Blockers / open questions
- ⛔ **D-12 vs the signed Milestone Form** — see Next step 1. Adviser decision, not ours.
- ⚠️ **Pre-C7 captures are NOT comparable to post-C7 ones** — the traffic model genuinely differs. The sep. 18 G402 cell becomes "previous generation". Cost was near zero now (1 cell, already needing re-capture for v2) and rises with every run.
- ⚠️ **PDR alone still scores 0.9987 vs 0.7031 majority.** Feature exclusion cannot fix it — a 100% drop rate in a fixed window is separable by construction. Needs attack-parameter variation, which collides with scope R-B (§1.4.1 excludes selective forwarding). **Adviser decides.**
- ⚠️⚠️ **ROOT POWER — verify before EVERY capture** (brownout loop). Direct laptop USB, never a shared hub.
- ⚠️ **No pcap has ever been captured**, though the paper commits to Wireshark twice (tools §, ethics form). `docs/WIRESHARK-GUIDE.md` §7 = MacBook walkthrough, §9 = each attack claim mapped to a filter. **M1 Macs: turn Wi-Fi OFF before enabling monitor mode** — the #1 cause of an empty capture.
- **Two unreconciled panel tracks:** `Plan/THESIS3-PANEL-PLAN.md` (aug. 06) vs `ESP32-Environment/memory/panel-change-2026-09.md` (sep. 13).
- **Scope amendments R-A / R-B unwritten**; `run_ledger.csv` still header-only.

## Recently done (last 3 max, newest first — older entries roll to ARCHIVE.md)
- sep. 21, 2026 — **C7 Option 1 (D-12)** + `probe_relay.{h,c}`; `leakage.py` made **dataset-aware** (asks how many roles carry each relay column instead of hardcoding); stale "run will be empty" alarms downgraded in `menu.ps1` + the attacker boot banner (a MAC mismatch is now bookkeeping only); dead `BLACKHOLE_VICTIM_TARGET` removed. Caught in review: the relay first forwarded only `PROBE_MAGIC`, which would have **silently destroyed every wormhole run** by dropping the `PROBE_MAGIC_WORMHOLE` duplicate mid-path.
- sep. 21, 2026 — **Smart trimmer** (scores sessions on phase progression, not length — proven: a 400-row real run beat a 3000-row idle session), **`verify_topology.py --structure`** (parent/child table rebuilt from CSVs, in the wizard's VERIFY menu), **`layer`→`hop` (D-11)**, **`docs/REVIEWER-QUESTIONS.md`** (every adviser/panel side comment answered against verified code).
- sep. 20, 2026 — F1/F2/F3/P5, `inventory_cells.py` (corrected "zero wormhole captures" — 8 complete runs exist), `ATTACK-VALIDATION.md`, `WIRESHARK-GUIDE.md`.

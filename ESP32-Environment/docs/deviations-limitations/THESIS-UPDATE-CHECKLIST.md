# ✅ THESIS-UPDATE-CHECKLIST — what the write-up must change before submission

> **What this is:** ONE running list of everything that changes what the thesis paper
> should say — a wording fix, a table/figure to redo, a footnote on a specific run, a
> capture to redo, or a question for the adviser. Work through it **after the experiment
> campaign is finished**, top to bottom.
>
> **Rule (CLAUDE.md):** any change, finding or decision that affects the paper adds a row
> here the same day — never edit a row's meaning later; tick it ✅ when the paper is updated
> (with the date). The *why* lives in the linked source (deviation D-x, verification #n,
> MEMORY entry); this file is the to-do list, not the explanation.
>
> **Status:** ⬜ open · 🟨 needs adviser · ✅ done in the paper (date)

---

## A. Method / design changes (from `thesis-deviate.md`)

Each D-x entry has its own "Net effect on the thesis" / "Paper edit" row — that row is the
exact wording guidance. Entries with **no paper change** are listed so nobody re-checks them.

| # | Status | Paper part | What to change | Source |
|---|---|---|---|---|
| A1 | ⬜ | §4.2.4.1 sampling | Capture is 10 Hz; say analysis uses the specified grid (see D-9 for the current grid) | D-1 |
| A2 | ⬜ | Eq 4.14 / LatencyHopRatio | Relative one-way delay, not Mean RTT — re-describe the feature | D-2 |
| A3 | ⬜ | TunnelLatency definition | Duplicate-arrival divergence, not UART echo RTT | D-3 |
| A4 | ⬜ | Topology verification | Mesh-formation window excluded from the topology check | D-4 |
| A5 | ⬜ | Baseline control | Each attack run's own phase 0 is the baseline (no separate baseline run) | D-5 |
| A6 | ⬜ | Repeats | Repeats share a topology class, not a fixed parent assignment (A↔B separation varied) | D-6 |
| A7 | — | Dataset schema | `run_repeat` column added — identifier only, no paper change beyond the column list | D-7 |
| A8 | ⬜ | PDR (Eq 4.5) | Same definition; describe per-window attribution | D-8 |
| A9 | ⬜ | Table 4.10 + §4.2.4.1 | **Window length and analysis rate changed — must be amended** | D-9 |
| A10 | — | Dataset schema | attack/topology/location/scenario columns — list them, no value changes | D-10 |
| A11 | ⬜ | Table 4.11 | `layer` → `hop`; show `HopChangeCount` | D-11 |
| A12 | 🟨 | Method + Milestone Form | C7 hop-by-hop relay on every node; pre-C7 captures not comparable. **D-12 vs the signed Milestone Form — adviser** | D-12 |
| A13 | ⬜ | Data collection | SD mirror is fsync()ed (reliability note) | D-13 |
| A14 | ⬜ | §3 / Table 3.3 | Radio pinned to HT20; **re-check Table 3.3's RSSI ranges against HT20 data**; never pool HT20 with HT40 | D-14 |
| A15 | ⬜ | Table 4.5, abstract, §3.4–3.5 | `retry_count`/`tx_count` are application-layer counters — rename/re-describe; RetryRate excluded per §4.2.4.1 pt 3; MAC retransmission evidence comes from the sniffer; Table 3.4's retry rise = tested, not observed | D-15 |
| A16 | ⬜ | §4.2.2.1, Fig. 4.17 | Star blackhole: the hub is the attacker, the root sits one hop behind — rewrite + **redraw Fig. 4.17** | D-16 |
| A17 | 🟨 | Wormhole method section | **A/B ends chosen at run time by mesh depth** (deeper = B entry, shallower = A exit), locked at Phase 0, recorded per capture. **Adviser check.** Also fill in the proposal's exact wording in D-17 (not yet checked) | D-17 (oct. 7 2026) |
| A18 | ⬜ | Wormhole exposure / "victims" | A wormhole run has **no victims**: only Node B's own probes are duplicated; other nodes are `not_tunnelled`. Do not use the blackhole "downstream = victim" rule for wormhole | D-17, MEMORY oct. 7 |
| A19 | ⬜ | Run matrix / data collection | **One matched benign run per location × topology**, the 4 topologies of a location under 4 different scenarios (was: burst cells only). 96 attack + 12 benign = 108 runs, 2 benign per scenario. **Adviser check** | D-18 (oct. 7 2026) |
| A20 | ⬜ | Locations / run matrix | **3 sites: G402, DLSU Library, Yuchengco** (home dropped, "Goks" renamed Yuchengco). Decide how the existing home captures are reported (pilot?) or dropped. **Adviser check** | D-19 (oct. 7 2026) |
| A21 | ⬜ | Scope & Limitations, attack method sections, future work, defense slides | **Attacks are application-layer emulations**: the attack behaviour (dropping; wired tunnel) is real on hardware, but **no routing manipulation** (no false route advertised; ESP-WIFI-MESH tree routing is inside the closed-source library, no API to falsify it). Blackhole traffic reaches the attacker by placement. State it upfront as a scope decision + why + what the data represents; add future work. **Planned for the paper edits the week of oct. 19, 2026**; verify the ESP-IDF API claims and cite the docs | D-20 (oct. 14 2026) |
| A22 | ⬜ | Verification method (D-21) | Wormhole = 2 independent primaries (TunnelIntensity [Zhukabayeva 2025] + root-measured DuplicateRate [Ramirez Gomez 2019]); latency features descriptive; `transition` windows unlabelled | D-21, verification #37 |
| A23 | ⬜ | Run procedure (D-22) | Pre-run gates: roster, tree attacker-child, wormhole setup (1 A + 1 B, UART both ways, A shallower), then operator START | D-22, verification #37 |
| A24 | 🟨 | Wormhole × STAR (method) | **Open decision (oct. 17 audit):** in a star every child is 1 hop from the root (max layer 2), so "A shallower than B" can never hold: the D-22 gate holds Phase 0 forever (START_ANYWAY only) and the verifier marks every star wormhole "SAME DEPTH - no shortcut". Decide: duplication-only star wormhole (relax gate + verifier, D-entry), rebuild the star one hop down like D-16, or drop wormhole/star from the matrix. **Adviser check** | MEMORY oct. 17 (wormhole audit) |
| A25 | ⬜ | Run procedure / phase definitions (Table of phases, D-22 paragraph) | **The stabilisation phase (phase 255) lasts from the root's PREPARE until the operator presses START, not a fixed 60 s.** `PHASE_STABILISE_S` = 60 s is only the *minimum* fixed wait; after it the root keeps broadcasting PREPARE through the roster/attacker/wormhole gates and the READY wait, so every board keeps logging phase 255 while the operator checks the mesh table and repositions boards. Phase 0 (baseline, 300 s) starts only at START. Write: "Stabilisation: ≥ 60 s, extended until all pre-run gates pass and the operator confirms the layout; repositioning happens here, never after Phase 0. Phase-255 rows are excluded from baseline/attack." Stabilisation length therefore varies per run (recoverable from each CSV) | D-22, `root_main.c` (`wait_for_all_children` / `wait_for_operator_start`), MEMORY oct. 18 |

## B. Reporting & wording (how results are stated)

| # | Status | Where | What to change | Source |
|---|---|---|---|---|
| B1 | ⬜ | Every results table with z-scores | A z of `-inf` means baseline σ = 0 (perfectly stable). Write **"z undefined (σ = 0)"** and give the finite primary (PDR) next to it — never print −∞ | Verification #3, #4 |
| B2 | ⬜ | Blackhole results | Quote **per-node PDR** (victim 1.0 → 0.0) rather than the pooled PDR, which mixes victims with bystanders | Verification #1 |
| B3 | 🟨 | Results framing | PDR / LatencyHopRatio separate the classes perfectly on their own — frame as expected for a blackhole, not as a model result | STATUS blockers |
| B5 | ⬜ | Tables with ConsistencyScore z | A **huge finite z** (e.g. 1,178,647) on ConsistencyScore is the same σ ≈ 0 case: `FR = fwd/(recv + 1e-6)` leaves 1e-6/recv residue in a perfect baseline. Report as "z undefined (σ = 0)", never the number. (Optional code fix: treat σ < 1e-5 as 0 in the verifier — not done) | Verification #7 |
| B4 | ⬜ | Blackhole "victims" in a run | Report victims by **exposure** (downstream of the attacker), not by the firmware's build role | exposure.py, verification #1 |
| B-cov | ⬜ | M5 coverage wording | The ≥ 95 % per-node coverage is measured over the **experiment phases only** (baseline, attack, cooldown); setup / mesh-forming rows are excluded, as in the analysis. Say so where M5 is described | MEMORY oct. 7 (night) |
| B-topo | ⬜ | Topology gate (M3 'stable through baseline') | The baseline-stability check now skips parent changes from BEFORE a root restart (the old root session, already excluded from the data as pre_baseline). Topology FAILs written in verifications #4, #8, #11 (and on linear/G402/stationary, tree/G402/burst + jitter) were this false alarm; they now PASS. Don't report them as instability | MEMORY oct. 7 19:40 |
| B-wh | ⬜ | Wormhole results / verification wording | A wormhole run counts as **confirmed only if the setup check passes** (one A + one B, no role switch during the experiment, A shallower than B in the attack, **Node A actually RECEIVED tunnel frames** - B's own count rises even with no cable). Duplicates alone = 'duplication only', not a confirmed wormhole. Re-run `verify_attack.py` on every wormhole cell before quoting a verdict; the oct. 14 reversed-ends linear run is NOT confirmed. If A's windows are unlabelled the verifier prints `-- cannot check UART delivery` - then show A's receipt from its raw `probes_count` (#35: 181/181). TunnelLatency is reported as `N/A` (no baseline by design) - quote its attack value descriptively | MEMORY oct. 14 2026, Verification #35 |
| B-setup | ⬜ | Verification method section | The verifier now also checks the SETUP (topology during the attack, attacker relayed + dropped, victims alive but cut off, non-victims unaffected; wormhole UART delivery + root duplicates) and a minimum effect size beside 3-sigma. Describe these as part of the verification method; a run is 'confirmed' only if both pass | Verification #13 |
| B-lat | ⬜ | Verification method: latency features | TunnelLatency + LatencyHopRatio are now **measured, not scored** in `verify_attack.py` (team decision oct. 16). Paper: "reported descriptively; the 3-sigma test (Zhukabayeva et al. 2025) needs a normal-phase distribution, which TunnelLatency cannot have by construction and LatencyHopRatio's unsynchronised one-way delay is too dispersed to support." Verdict basis = TunnelIntensity + setup checks (root duplicates [Ramirez Gomez 2019], UART delivery). Report also tags each check with its study (Z/A/KW/K/R/H, from `docs/references/2026-09-14_REFERENCES.md`) | MEMORY oct. 16 2026 |
| B-pm | 🟨 | Partial-mesh topology description + results | **All 9 partial_mesh captures are structurally plain trees** - no child used a 2nd parent during the experiment. Either describe them as such (placement-defined, single-parent at capture time) or recapture with re-parenting. **Adviser check** | Verification #13 |
| B-rules | ⬜ | Verification method section (verdict rules) | State the verifier's extra rules, which change verdicts but are not in the proposal: **CONFIRMED = at least ONE primary signature passes 3-sigma** (not all); a primary whose normal phase is broken (PDR / ForwardingRatio mean < **0.90**, or sd/mean > **0.15**) is **EXCLUDED, not counted as a FAIL**; a pass also needs an absolute change ≥ **0.10** (MIN_EFFECT; TunnelBytes ≥ 3) and ≥ **6** attack points; statistics pool **5 windows** per point. | Verification #41 |
| B-force | 🟨 | Per-run notes / limitations | Runs started with **START_ANYWAY** (root safety gate overridden: a child missing, or wormhole ends not A-shallower-than-B) leave NO mark in the SD-card CSVs and the verifier cannot see it - only the root's serial/run log says so. Before final tables: grep each cell's `datasets/run_logs/` for `START_ANYWAY` and footnote / exclude those runs (or add an automatic check). **Oct 18: automatic check added** - `verify_attack.py` setup checks [3] now say OK (normal START) / WARN (force-started) / SKIP (no root run log saved). Today: 3 cells OK, 0 WARN, the rest SKIP (older captures have no run log) - those still need the footnote decision. | Verification #41 |

## C. Per-capture footnotes (cite the run, add the note)

| # | Status | Capture | Footnote / caveat | Source |
|---|---|---|---|---|
| C1 | ⬜ | blackhole/tree/G402/**burst** r1 (oct. 2) | One board (`B4BFE932FE90`) ran an **outdated firmware image** and was excluded from the labelled data; it was a hidden 3rd victim (root arrivals 6→3). Victims in the labelled data = 2 | Verification #3, #5 |
| C2 | ⬜ | blackhole/linear/G402/stationary r1 | Root restarted before the run (harmless WARNs); 2 nodes thinner (min-samples rule) | Verification #2 |
| C3 | ⬜ | blackhole/linear/home/highload r1–r4 | PARTIAL: r2/r3 baselines broken by the 7-board highload collapse; r1 + r4 alone confirm | Verification #2 |
| C4 | ✅ | wormhole/tree/G402/**stationary** r1 (oct. 2) - **DATA DELETED oct. 17 (user; exports + analysis to the Recycle Bin on Angelo's laptop): it was star-shaped, not a tree - nothing of it may be cited; D3 still open** | **Both wormhole ends at hop 1 for the whole attack** — duplicates are real but the tunnel was **no shortcut**, so no latency advantage can show. Use for "duplication" only, or recapture | Verification #6 |
| C5 | ⬜ | blackhole/partial_mesh/?/**highload** (oct. 7, ~15:20) | Root lost ~90 % of its ARRIVAL rows (`[RXSTALL] arrival queue FULL`, ~21 of ~24/s from the attack on; 1,400 by mid-cooldown). Root-side PDR for this run is **invalid** (undercounts every node, not just victims). Child telemetry unaffected. Do not use its PDR | MEMORY oct. 7 |
| C6 | ⬜ | every **highload** capture after oct. 7, 2026 (eve) | Method note: on highload runs the root logs probe arrivals to the **SD card only, buffered (4 KB) and flushed every 100 rows**, instead of SPIFFS + SD every 10 rows - the double write took ~400 ms/row and lost 3,151 rows at ~28 rows/s. Same columns and values; only where/when rows are written changed. Other scenarios unchanged | MEMORY oct. 7 (eve) |
| C7 | ⬜ | blackhole/partial_mesh/DLSU_Library/**highload** r1 (oct. 7, ~17:00) | USABLE, first run with the highload root fix (0 arrival rows lost). Caveats: `MacRetryRate` empty (sniffer retry not placed on the clock); `B4BFE934ED80` has a 4.1 s gap at baseline start; victim = `B4BFE932FE90` only (attacker `F42DC973E618` at L4) | Verification #9 |
| C8 | ⬜ | wormhole/linear/DLSU_Library/stationary r1 (oct. 7, ~18:00) | USABLE. TunnelLatency = INCONCL (no tunnel in baseline, so no 3σ baseline - by design; quote attack value 2–4 ms descriptively); LatencyHopRatio = INFEASIBLE (baseline spread across an 8-hop line, max |z| 0.64; secondary, not in verdict). First hardware run of the A/B auto-switch | Verification #10 |
| C9 | ⬜ | blackhole/linear/DLSU_Library/**jitter** r1 (oct. 7, ~18:41) | USABLE. Jitter fired: baseline 331 s / attack 206 s (only the last 300 s of baseline are labelled; the extra 31 s are excluded). Topology gate FAIL is the **root-reflash false alarm** (`FE90` lost the root while the root was being wiped and reflashed, before the real baseline). 4 victims 0 % in the attack, 2 bystanders 100 % | Verification #11 |
| C10 | ✅ | wormhole/linear/G402/**stationary** r1 (oct. 14, ~1:40 PM) - **superseded by the 3:02 PM recapture (#40)** | **NOT USABLE as a wormhole**: ends reversed all experiment (A hop 6, B hop 1; one-way UART). Duplicates are real (179/181) but no shortcut. Do not cite as a confirmed wormhole; recapture (D6) | Verification #12 |
| C11 | ⬜ | wormhole/linear/**DLSU_Library**/highload r1 (oct. 18, ~3:25 PM) | Every SD card's `location.txt` still said G402, so the cards recorded the site as G402; the site was set by the operator (preset, run log, root USB export) and the 7 card files were filed under DLSU_Library by hand. Footnote: location for this capture is operator-recorded, not card-recorded (panel P4). From oct. 18 run.ps1 rewrites location.txt before each flash, so later captures do not need this note | Verification #42 |
| C12 | 🟨 | blackhole/tree/G402/stationary r1 (oct. 18 recapture, ~7:21 PM) | Victim F4:18 - directly under the attacker - **crashed (PANIC) 152 s into the attack**; its file holds baseline + 152 s of attack, no cooldown. Footnote the shortened attack for that board, and report it with D9 (victim crashes under blackhole) once the cause is known; Its crash also knocked its 2 children (D7B4, ED80) off at attack +158 s → they re-joined elsewhere → verifier: signature PASS but SETUP INVALID (#44); recapture, or 🟨 adviser: verdict on the attack window before the first parent change? 20:38's file opens with 74 s of an earlier root attempt, excluded by the root-restart rule (method note only) | Verification #43, #44 |

## D. Captures to redo / still missing (before the numbers are final)

| # | Status | What | Why | Source |
|---|---|---|---|---|
| D1 | ⬜ | Recapture blackhole/tree/G402/stationary **r2** | r1 DEGRADED: 2 boards dropped out mid-run | Verification #2 |
| D2 | ⬜ | Recapture blackhole/tree/G402/burst **r2** with all 8 boards | r1 lost FE90 (stale firmware) — reflash FE90 first | Verification #5 |
| D3 | ⬜ | Recapture wormhole/tree/G402/stationary with the auto-switch firmware | r1 had no shortcut (C4) and was star-shaped - **deleted oct. 17, the cell is EMPTY now** | Verification #6 |
| D5 | ⬜ | Fix the root's arrival writer (**fix `643adf8` works on hardware - verification #9; partial_mesh/DLSU highload r1 redone**), then recapture every **highload** cell | first hardware run of `cb22106` (arrival queue) shows the writer itself is too slow at highload; read the `[RXSTALL] Saving one probe to storage took …` lines of that run to see whether SPIFFS or the SD mirror is the slow one | MEMORY oct. 7 |
| D4 | ⬜ | Remaining matrix: jitter r2+r3, mobility, powercycle, star burst, 7-board highload, wormhole tree with a real tree | Not captured yet | STATUS next steps |
| D6 | ✅ | Recapture wormhole/linear/G402/stationary | r1 ends reversed (C10). **Done: oct. 14 3:02 PM recapture verified CONFIRMED + usable (A shallower, tunnel 100 %)** | Verification #12, #40 |
| D8 | ⬜ | Recapture wormhole/tree/DLSU_Library/stationary (oct. 16 r1 = tunnel proof only) | Tunnel worked (B 181 → A 181 → root 2×) but A + 3 other root-direct boards logged in bursts (28-32 % rows < 20 ms apart, new vs oct. 11-12) → unlabelled. **#35: attack itself CONFIRMED** (that SETUP INVALID was a verifier false alarm, fixed) - decide: recapture for a complete 8-board cell, or keep with a footnote naming the 4 unlabelled boards. Find the stall first. (D8 not D7: Kyle's D7 is not in this copy yet) | Verification #34, #35 |
| D9 | ⬜ | Recapture blackhole/tree/G402/highload (oct. 17 ~5 PM r1 = SETUP INVALID) | Attack signature strong (attacker 0 % forwarded, victims 0.24 / 0.50) but 3 victims crashed (PANIC / INT_WDT) and B768 re-parented during the attack. Capture again with every child's serial monitored so a crash is recorded; if it recurs, report the crash rate per scenario | Verification #39 |

---

## Done
*(move rows here with the date once the paper is updated)*

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

## B. Reporting & wording (how results are stated)

| # | Status | Where | What to change | Source |
|---|---|---|---|---|
| B1 | ⬜ | Every results table with z-scores | A z of `-inf` means baseline σ = 0 (perfectly stable). Write **"z undefined (σ = 0)"** and give the finite primary (PDR) next to it — never print −∞ | Verification #3, #4 |
| B2 | ⬜ | Blackhole results | Quote **per-node PDR** (victim 1.0 → 0.0) rather than the pooled PDR, which mixes victims with bystanders | Verification #1 |
| B3 | 🟨 | Results framing | PDR / LatencyHopRatio separate the classes perfectly on their own — frame as expected for a blackhole, not as a model result | STATUS blockers |
| B5 | ⬜ | Tables with ConsistencyScore z | A **huge finite z** (e.g. 1,178,647) on ConsistencyScore is the same σ ≈ 0 case: `FR = fwd/(recv + 1e-6)` leaves 1e-6/recv residue in a perfect baseline. Report as "z undefined (σ = 0)", never the number. (Optional code fix: treat σ < 1e-5 as 0 in the verifier — not done) | Verification #7 |
| B4 | ⬜ | Blackhole "victims" in a run | Report victims by **exposure** (downstream of the attacker), not by the firmware's build role | exposure.py, verification #1 |

## C. Per-capture footnotes (cite the run, add the note)

| # | Status | Capture | Footnote / caveat | Source |
|---|---|---|---|---|
| C1 | ⬜ | blackhole/tree/G402/**burst** r1 (oct. 2) | One board (`B4BFE932FE90`) ran an **outdated firmware image** and was excluded from the labelled data; it was a hidden 3rd victim (root arrivals 6→3). Victims in the labelled data = 2 | Verification #3, #5 |
| C2 | ⬜ | blackhole/linear/G402/stationary r1 | Root restarted before the run (harmless WARNs); 2 nodes thinner (min-samples rule) | Verification #2 |
| C3 | ⬜ | blackhole/linear/home/highload r1–r4 | PARTIAL: r2/r3 baselines broken by the 7-board highload collapse; r1 + r4 alone confirm | Verification #2 |
| C4 | ⬜ | wormhole/tree/G402/**stationary** r1 (oct. 2) | **Both wormhole ends at hop 1 for the whole attack** — duplicates are real but the tunnel was **no shortcut**, so no latency advantage can show. Use for "duplication" only, or recapture | Verification #6 |
| C5 | ⬜ | blackhole/partial_mesh/?/**highload** (oct. 7, ~15:20) | Root lost ~90 % of its ARRIVAL rows (`[RXSTALL] arrival queue FULL`, ~21 of ~24/s from the attack on; 1,400 by mid-cooldown). Root-side PDR for this run is **invalid** (undercounts every node, not just victims). Child telemetry unaffected. Do not use its PDR | MEMORY oct. 7 |
| C6 | ⬜ | every **highload** capture after oct. 7, 2026 (eve) | Method note: on highload runs the root logs probe arrivals to the **SD card only, buffered (4 KB) and flushed every 100 rows**, instead of SPIFFS + SD every 10 rows - the double write took ~400 ms/row and lost 3,151 rows at ~28 rows/s. Same columns and values; only where/when rows are written changed. Other scenarios unchanged | MEMORY oct. 7 (eve) |

## D. Captures to redo / still missing (before the numbers are final)

| # | Status | What | Why | Source |
|---|---|---|---|---|
| D1 | ⬜ | Recapture blackhole/tree/G402/stationary **r2** | r1 DEGRADED: 2 boards dropped out mid-run | Verification #2 |
| D2 | ⬜ | Recapture blackhole/tree/G402/burst **r2** with all 8 boards | r1 lost FE90 (stale firmware) — reflash FE90 first | Verification #5 |
| D3 | ⬜ | Recapture wormhole/tree/G402/stationary with the auto-switch firmware | r1 had no shortcut (C4) | Verification #6 |
| D5 | ⬜ | Fix the root's arrival writer (**fix built oct. 7 eve, not on hardware yet - see C6**), then recapture every **highload** cell | first hardware run of `cb22106` (arrival queue) shows the writer itself is too slow at highload; read the `[RXSTALL] Saving one probe to storage took …` lines of that run to see whether SPIFFS or the SD mirror is the slow one | MEMORY oct. 7 |
| D4 | ⬜ | Remaining matrix: jitter r2+r3, mobility, powercycle, star burst, 7-board highload, wormhole tree with a real tree | Not captured yet | STATUS next steps |

---

## Done
*(move rows here with the date once the paper is updated)*

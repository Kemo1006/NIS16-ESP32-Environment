# Fact sheet: Chapters 6 and 7 (for the team to write from)

Fragments only, so the team writes the sentences. Every number was checked on oct. 24, 2026 against `FINAL THESIS3 OFFICIAL (5)`; see `verification/oct. 24, 2026_paper-chapter-7-check.md`. Write each section in your own words and keep the numbers exact.

## Chapter 6: Results and Discussion

**6.1 Dataset collected** (Tables 6.1–6.6)
- 80 runs captured = 36 blackhole + 36 wormhole + 8 benign; none missing
- 4 topologies × 3 sites × 3 scenarios = 36 cells per attack
- benign: 4 stationary, 3 highload, 1 burst
- 8 boards per run (root + 7), except: star benign Yuchengco highload = 6; BH tree G402 highload = 7 (B768 no data)
- schedule: 60 s formation, 300 s baseline, 180 s attack, 120 s cooldown; 10 Hz → 1 s windows
- 456,195 windows total; 369,678 analysed = 266,491 normal + 103,187 attack
- BH: 123 victims, 92 bystanders; WH: 180 untouched boards (5 per run)
- 15 earlier captures (11 cells) replaced: 9 had passed, 4 setup invalid, 2 no verdict (Table 6.5)
- 12 captures outside the plan (5 jitter, 7 home), not counted
- grades: BH 4 strong / 27 good / 5 minor gaps; WH 21 strong / 15 good

**6.2.1 Blackhole**
- attacker FR: 1.000–1.004 baseline → 0.000–0.007 attack (forwarded 0.0–0.7%)
- finite z in 21 runs: min 22.9, median 111; 15 runs infinite z
- victim PDR 0.998 → 0.000 in every run; all 123 victims exactly 0
- bystanders 1.000 in attack (0.996 baseline)
- drop: 121 boards in first second, 2 within 1 s; recovery within 3 s (median 2 s), 122 boards (1 went silent)
- PDR check excluded for partial mesh Yuchengco stationary (baseline 0.930 ± 0.253)
- neighbour check: 32 pass, 4 runs no attack values

**6.2.2 Wormhole**
- 3 checks pass in all 36; topology warning in 9 partial-mesh runs (plain tree)
- entry end deeper than exit end in every run; hops constant
- hops skipped: linear 2–5 (median 4), partial mesh 1–2, star 1, tree 1–2
- exit end received 99–101% of tunnel messages
- 12,448 of 12,465 probes reached the root twice (99.86%); other boards never
- 6,468 of 6,469 attack windows had a duplicate (99.98%); none in baseline/cooldown
- TunnelLatency median 3.9 ms, p90 12.1 ms, p99 417 ms; no link to hops skipped (Spearman 0.25, p = 0.14)
- out-of-order: 232 of 24,913 (0.93%)

**6.2.3 Single-feature audit**
- victims: PDR alone 99.9% vs majority 70.1%; the other features stay at majority
- LatencyHopRatio: its missingness gives the label (99.2%), so it is excluded
- run clock 80.0% (fixed schedule), not used
- WH ends: tunnel features 99.7%; non-attacker nodes: no feature above majority

**6.2.4 Predictions not observed**
- victim retry rate 0.0000 → 0.0004 → 0.0000 (9 of 21,742 windows); attacker still ACKs frames
- ParentSwitchRate ~0 (d = 0.01)
- sniffer (7 runs): no consistent rise, victims −0.10 to +0.33
- WH: 3 of 9 indicators seen (duplicates, arrival pattern, latency mismatch); hop/parent/RSSI unchanged

**6.2.6 Benign**: all 8 BENIGN CONFIRMED (strong); 0 of 21 signature checks passed; PDR 0.9994–1.0000; cooldown within 0.5 sd in 24/24

**6.3 EDA**: victim PDR d = −29.71; every other feature |d| < 0.1; RSSI unaffected (victims −74.7 → −74.9 dBm)

**6.4 Clustering**
- K-Means k = 2, REDUCED: ARI 0.514 (ceiling 0.515) all non-attackers; 0.996 victims only
- without PDR: −0.016 to 0.002 (nothing found)
- why the ceiling is 0.515: bystanders carry the attack label but act normal
- robustness: within 0.03 per site/topology; resample 0.41–0.63; 35 of 36 runs within 0.05
- wormhole: ARI −0.012 to 0.009 without tunnel features
- pooled 3 labels: 0.333 (ceiling 0.334); all 21,733 victim attack windows in one cluster, none of 22,481 benign windows

**6.5 Discussion**: objectives met with 2 qualifications (emulated attacks; partial mesh = branched trees). Published studies: Khan >97% PDR; Airehrour 60–75% loss (14-mote testbed); Ramírez Gómez duplicates; Zhukabayeva 3-sigma. Limits: 1 run per cell, 8 boards, emulation, 8 benign runs only.

## Chapter 7: Conclusion and Recommendations (what each part should cover)

- **7.1 Summary**: problem (ESP32 mesh, no real cross-layer dataset) → what you built (8 boards, 2 attacks) → campaign (80 runs) → analysis (16 features, EDA, 5 clustering algorithms)
- **7.2 Dataset**: what it holds (numbers from 6.1) + why it can be reused (labels written at capture time, run IDs on every row, repo [79])
- **7.3 Why the dataset is valid**: pick the 4–5 strongest points in your own words: labels by design; every run verified; BH victims all at 0 while bystanders stay at 1; WH duplicates 99.86%; benign runs clean; verifier tested (±50% → no change, 53 runs)
- **7.4 Objectives**: one short paragraph each: obj 1 met, obj 2 met, obj 3: blackhole separable only through PDR, wormhole not separable by cross-layer features
- **7.5 Contribution**: dataset, verification procedure, the data-plane finding, open tools
- **7.6 Recommendations**: route-level attacks; repeat each cell; more benign runs; tunnel other nodes' traffic; sniffer in every run; detector tested by leaving out whole runs

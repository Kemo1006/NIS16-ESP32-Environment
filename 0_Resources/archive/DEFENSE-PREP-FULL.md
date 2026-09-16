# NIS16 — Full Panel Question Bank (aim: 90%)

The complete set, grouped by milestone, in plain speakable answers. This is the **exhaustive bank**; [DEFENSE-PREP.md](DEFENSE-PREP.md) is the top-19 to drill first, [DEFENSE-PREP-CODE.md](DEFENSE-PREP-CODE.md) explains the mechanisms + code, [TERMS-GLOSSARY.md](TERMS-GLOSSARY.md) is the vocabulary. ⚠️ = high-risk. Section numbers are kept from the original topic layout, so they are grouped by milestone rather than in numeric order.

**Status to state honestly if asked:** pipeline works end to end on real data; **4 of 24 experiment runs done** (all of `linear·blackhole` ×3, one `linear·wormhole`); tree/star/partial next.

---

# Foundations (read first)

## 0. How to score 90% (read this first)
- **Lead with the one-sentence answer, then the evidence.** Don't ramble toward the point.
- **Own the emulation honestly.** Your attacks are behavioral emulations because the Wi-Fi stack is closed. Say it *before* they corner you — it reads as rigor, not weakness.
- **If you don't know:** say "That's not something we measured — here's what we *can* say, and here's how we'd find out." Never invent a number. A calm "we didn't test that, but the method would be X" scores better than a wrong fact.
- **Separate "exists" from "populated," "done" from "in progress."** Precision about your own status is what makes the rest of your claims believable.
- **Know your three weak spots cold** (§21) so they never surprise you.

## 1. Motivation, problem, gap
**What problem are you solving?** Security research on ESP32 mesh networks mostly relies on simulated data, which misses how real hardware actually behaves across layers. There's no real, labeled dataset of an ESP32 mesh under attack. We build one.
**Why is simulated data not enough?** Simulations make a "closed-world assumption" (Sommer & Paxson) — clean, idealized conditions that don't capture real radio noise, retries, and firmware quirks. A detector trained on that can fail on real hardware.
**Why does a dataset matter more than a detector?** Detectors come and go; a good labeled dataset is reusable infrastructure others build many detectors on. That's the contribution.
**Who benefits?** Researchers and students building or testing IDS for low-cost IoT mesh — they get real ground-truth data instead of simulations.

## 2. Objectives — and are they met?
**General objective:** design, generate, and analyze a cross-layer dataset from a real ESP32 mesh to explore normal vs attack behavior.
**Three specific objectives:** (1) build the testbed, (2) collect cross-layer PHY/MAC/Network features into a labeled dataset, (3) evaluate the dataset via EDA + unsupervised clustering for separability.
**Are they met?** Obj 1 — yes, testbed runs. Obj 2 — yes, the 16-feature labeled dataset is produced end to end. Obj 3 — **partially**: signatures are clear per attack, but the full separability study needs all attack types in one combined table, which is the remaining work.

## 3. Scope, limitations, ethics
**Scope:** two attacks (blackhole, wormhole), 5–10 nodes, controlled indoor lab, offline exploratory analysis — not a live detector.
**Limitations (state them proactively):** small scale (may not reflect large/dense meshes); only two threat types; indoor only (no outdoor/weather/mobility); exploratory, so no accuracy/real-time claims.
**⚠️ Isn't a controlled lab unrealistic?** It's a deliberate trade: control gives clean, repeatable ground-truth labels. We're honest that it doesn't capture environmental variability — that's named as future work.
**Ethics:** fully isolated lab, no connection to any real/production network, researcher-owned boards only; research ethics forms are in Appendix B. No third-party network is ever touched.

## 4. Related literature
**How do you differ from existing IDS work?** Most (e.g. Bhonsle's RNN/LSTM on NSL-KDD, Srinivasan's E-SVM in NS-3, Hanif's ML wormhole review) run on *simulated* or non-mesh data. We contribute *real ESP32 hardware* data — the input they lack.
**Why not just use NSL-KDD or an existing set?** Those are wired/IP-network datasets; they have no ESP32 cross-layer mesh behavior — no RSSI-per-hop, no mesh re-parenting, no ESP-WIFI-MESH forwarding. Wrong domain.
**Isn't ML better than clustering for detection?** For *detection*, often yes — but our goal is dataset characterization, not detection. Clustering tests whether the structure is even there before anyone trains a detector.

## 5. Theoretical framework
**What's the core idea?** Normal operation = "consistent relationships" (closer node → stronger signal; received → forwarded; hop count ↔ latency). An attack = a "broken relationship." Blackhole breaks received→forwarded; wormhole breaks physical↔logical topology.
**Why cross-layer instead of one layer?** A single metric gives false positives — noise can drop one value. A real attack breaks *several* relationships at once across PHY/MAC/Network, so looking cross-layer is more reliable. (Framework is observational, not a detector — §3.5 of the paper.)

---

# Milestone 1 — Firmware Development for All Node Roles

## 6. Testbed, hardware, ESP-WIFI-MESH
**Why ESP32?** It's the actual low-cost chip these IoT meshes use — cheap, Wi-Fi built in, supports ESP-WIFI-MESH. Its limits (closed stack, small memory) are exactly what's worth studying on real hardware.
**What is ESP-WIFI-MESH?** Espressif's self-organizing Wi-Fi mesh: nodes auto-form a tree, each node is both host and router, one root bridges out. No fixed infrastructure.
**Node roles?** Root (controls the experiment timeline + receives probes), victims/children (send probes, log telemetry), attacker (a child that drops or tunnels).
**Hardware list:** up to 10 ESP32 boards, USB cables, 2–3 laptops (≥16 GB RAM) for logging/analysis, a temporary router only for setup, serial monitors for diagnostics.

---

# Milestone 2 — Application-Layer Attack Modules

## 8. Blackhole — attack realism (⚠️ hardest area)
**⚠️ Is this a real blackhole? You told victims to send to the attacker.** It's a behavioral emulation, and we say so. The ESP32's Wi-Fi stack is closed, so we can't inject fake routes to *lure* traffic. Instead we reproduce the observable effect: victims relay through the attacker, and during the attack it stops forwarding. What a monitor sees — forwarding→0, delivery collapse, retries spike — is identical to a real blackhole.
**⚠️ How is it different from a node that just crashed?** The attacker's own counters prove intent: 720 received, 720 dropped, 0 forwarded, with "received" still climbing. It got everything and forwarded nothing on purpose. And there's zero re-routing — a crash would trigger re-parenting.
**Where's the drop in code?** One `if` in `blackhole_victim.c` `relay_task()`: if attack phase, count-and-drop; else forward. Nothing else changes.
**Numbers:** delivery 0.94→0.08, forwarding ~1.0→~0.02, retry 0.004→0.165.
**⚠️ Your root arrivals.csv has NO phase-1 rows — did the attack fail?** The opposite — that absence *is* the signature. arrivals.csv only logs probes that reached the root; during the attack the blackhole dropped every one, so there was nothing to log. It shows as a ~180 s gap in `timestamp_us` (e.g. 365 s → 546 s) with zero rows. Verified: **0 arrivals in phase 1 across all 3 repeats**; baseline ~1436 and cooldown ~483 either side.
**Then why doesn't `probes_received` jump across that gap (1396→1397)?** Because it's a per-row counter on the root ("Nth arrival logged"), not a count of probes sent — it only advances when a row is written, and none were. The column that *does* jump is the victim's own `seq_num` (e.g. F4:2D:C9 goes 367→548, ~180 up): the victims kept sending ~180 probes that never arrived. Time passed, victims transmitted, root logged nothing = the drop.
**⚠️ Some blackhole runs show 1–2 rows in phase 1 while others show 0 — are the runs inconsistent?** No — both mean the same thing. A 180-second attack window should hold ~180 probes; instead you see 0, 1, or 2, i.e. ~99% gone in *every* run. The 1–2 stragglers are probes that were already in flight the microsecond the phase flag flipped to "attack," logged just before the drop engaged — pure boundary timing, the same edge effect as the 181-vs-180 wormhole count. Verified: **tree r1 = 2, star r1 = 1, everything else (linear r1–r3, star r2–r3) = 0.** The proof of the attack is the **~181 s of silence** right after those stragglers (e.g. one arrival at 368 s, next not until 549 s), not the phase-1 row count. Count phase-1 rows to show the *absence* (baseline ~1,400 → attack 0–2), never to decide whether the attack fired.

## 9. Wormhole — attack realism (⚠️)
**⚠️ Your tunnel is your own wire — where's the attack?** A wormhole *is* two colluding nodes on a private out-of-band link — building it is implementing it. Node B (near victims) and Node A (near root) share a UART wire. During the attack, B sends each probe over the mesh *and* down the wire; A replays it to the root.
**What's the signature?** The root logs the same probe twice. Measured: attack window had 901 arrivals, 720 unique, **181 duplicates, all from the tunneled node** (×2.00), others ×1.00.
**Why keep both copies?** We deliberately don't de-duplicate the tunneled copy (`root_main.c` probe callback) — the duplicate + latency gap *is* the signature; suppressing it would hide the attack.
**Why is only ONE node duplicated and the others aren't?** Only the tunneled node (`F4:2D:C9:73:E6:18`, Node B) is behind the wire — its probes are replayed, so each of its seq_nums appears twice (e.g. 451,451 / 452,452). The other three victims relay normally, so each of their probes arrives once. Duplication confined to the one tunneled node is precisely why we attribute it to the tunnel, not to mesh noise.
**Why do the different nodes show different seq_nums (451 vs 387 vs 415)?** Each victim keeps its own independent probe counter, so at any instant they're at different numbers. Only compare a node to *itself* — a repeat of its own seq_num is the duplicate; a repeat across two different MACs would be coincidence.
**⚠️ In cooldown (phase 3) the tunneled node still appears — is the wormhole still active?** No. The node is still a victim and keeps sending, but its probes are no longer duplicated (each seq once). Wormhole activity = duplication, and duplicates go **0 → 181 → 0** (baseline → attack → cooldown). Seeing the node isn't the signature; seeing it *twice* is, and that stops when the attack stops — clean toggle, no leakage.
**Reproducible / consistent across topologies?** Yes: duplicates **181/181/181 on linear** and **180/180/180 on star**, all 3 repeats each, always from the one tunneled node, always 0 in baseline and cooldown. 2 of 4 topologies so far (tree, partial pending); because the tunnel is a physical wire the signature isn't topology-dependent by construction.
**Why 181 on linear but 180 on star — is that an error?** No — a one-probe timing difference at the phase-2→3 boundary (one extra probe tunneled before the toggle on linear). The mechanism is identical; the count differs by one.
**Why doesn't a probe ever arrive 3× in partial mesh (it has redundant paths)?** We checked the multiplicity directly: in partial mesh phase 2 it's 541 probes ×1 and 180 ×2, **zero ×3**. Max is two — one mesh copy + one tunnel copy. The tunneled node shows in many rows because it keeps sending *and* each attack probe doubles, but no single seq_num appears more than twice.

## 9a. Plain-language: explaining the wormhole CSV (say-it-out-loud version)
**The whole idea in one line:** a normal probe = **one row** in the root's arrivals.csv; a wormhole probe = **two rows** with the same `src_mac` *and* the same `seq_num`. The wormhole makes the root write the same probe down twice.
**How to read the file in 3 steps** (a panelist can follow along): (1) filter to the attack, `phase_id = 2`; (2) find the tunneled node `F4:2D:C9:73:E6:18` — its `seq_num` appears **twice in a row** (e.g. 451, 451); (3) check the other three victims — each `seq_num` appears **once**. Only the tunneled node doubles.
**Why the three topology CSVs look almost identical:** arrivals.csv is the **root's** list of what reached it, and the tunnel is a **physical wire**. A wire doesn't care whether the mesh is a line, a star, or a partial mesh, so the root always sees the same "one node doubled" picture. Counts: linear **181**, star **180**, partial **180** — the same thing, off by one probe at the edge.
**The topology itself is NOT in arrivals.csv** — every row there is a root row (layer 1). The mesh *shape* lives in the per-node `telem.csv` (`layer` / `parent_mac`). So don't expect arrivals to look different by topology; it shouldn't.
**If they ask "then why show three topologies?"** — to prove the signature is repeatable, not a fluke of one layout. Same signature on three shapes = confidence.
**The one sentence to lead with:** *"In every topology the attack looks the same in the root's log — one node's probes are written twice — and that sameness is the result: the wormhole runs over a wire, so it doesn't depend on the network's shape."*
**⚠️ But the tunneled node's MAC appears several times in baseline (phase 0) too — isn't the wormhole leaking into baseline?** No — this is the #1 misread of the file. A MAC appearing on **many rows** is normal: every victim sends a probe about once a second, so it shows up once per probe throughout the run. The test for a duplicate is **same MAC AND same `seq_num` on two rows** — not just the same MAC. Look at the seq_num: in baseline `F4:2D:C9:73:E6:18` shows **419, 420, 421, 422** — four *different* probes, each logged once. In the attack it shows **423, 423** — the *same* probe twice. Baseline has zero repeated seq_nums (verified: 0 duplicates), so the tunnel is off; only in phase 2 does a seq_num repeat.
**Rule of thumb:** *same MAC, climbing seq_num* = one node sending normally (fine, any phase). *Same MAC, same seq_num twice* = the wormhole duplicate (attack only). Always compare the `seq_num`, never just the MAC.
**Also — two of the MACs look almost identical (`B4:BF:E9:32:FE:90` vs `B4:BF:E9:34:ED:80`) — is that one node logged twice?** No, they're two **different** victim boards. `B4:BF:E9` is just the shared Espressif vendor prefix (OUI); the last three octets (`32:FE:90` vs `34:ED:80`) are the unique device IDs. Read the full MAC, not the prefix.

## 10. Attack choice & threat model
**Why only blackhole + wormhole?** They're the two fundamentally distinct routing threats: one attacks forwarding compliance (drop), the other attacks topology integrity (fake shortcut). They map exactly to the two "broken relationships" in the framework.
**Why not grayhole, Sybil, selective forwarding?** Out of scope by design — they're variants or different threat classes; two clean, distinct cases are enough to demonstrate the dataset's value.

---

# Milestone 3 — Multi-Topology Testbed Deployment

## 7. Topologies
**Which four and why?** Star, tree, linear chain, partial mesh — they span the realistic shapes a mesh forms, from centralized (star) to multi-hop chains (linear) to redundant (partial mesh). Attack effects differ by shape.
**⚠️ How do you force a shape on a self-organizing mesh?** With mesh constraints. Linear, for example, sets `max_children=1` so each node accepts only one child — the log line `Topology shaping: LINEAR (max_layer=7, max_children=1)` shows it. So the auto-mesh is constrained into the shape we want.
**Which are done?** Linear is verified and captured (blackhole all 3 repeats, wormhole once). Tree, star, partial are next — that's the bulk of the remaining 20 runs.

---

# Milestone 4 — Phase-Controlled Experiment Execution

## 11. Experiment control, phases, labeling
**Phase timeline?** Fixed: 300 s baseline, 180 s attack, 120 s cooldown, then terminate (Table 4.1). Root broadcasts each transition.
**How are labels assigned?** Root broadcasts the active phase; each node maps phase→label and stamps it on every row. `phase_id_to_label()` is the whole rule.
**⚠️ Could labels be contaminated by the data?** No — they come only from the control broadcast, never from a measured value. That's what makes them true ground truth.
**How do nodes stay in sync?** Repeated broadcasts with sequence numbers; each node applies a phase once and ignores repeats (dedup by seq_num). Timestamps are re-aligned offline against the root's phase log.

## 12. Data collection & cross-layer
**What exactly is logged?** Per node per sample: timestamp, node id, role, layer, parent MAC, RSSI, retry/tx/probe counters, phase id, label. The root additionally logs per-probe arrivals (src, seq, latency).
**What does "cross-layer" mean concretely?** One row fuses PHY (RSSI), MAC (retries), and Network (forwarding, delivery, topology). An attack shows in all three at once — single-layer datasets miss that.
**Where is it stored?** On each board's own flash (SPIFFS), pulled off over USB after the run — so an attack that drops mesh traffic can't erase the evidence; logging is local and independent.

---

# Milestone 5 — Raw Data Extraction & Integrity Validation

## 16. Results & validation
**What have you actually shown?** Clean end-to-end pipeline on real data, textbook blackhole and wormhole signatures, and a complete `linear·blackhole` set.
**How do you validate a run is good?** Tools check data integrity (schema, timestamps), verify topology (correct shape, convergence <60 s, no re-parenting), and confirm the attack signature (blackhole = zero arrivals in the window; wormhole = duplicate deliveries).
**How do you know the blackhole drop is the attack, not a dead mesh?** Attacker counters (720/720/0), victims kept sending, zero re-parenting, layer-2/3 victims silent because every victim funnels through the attacker by design.

---

# Milestone 6 — Preprocessing Pipeline

## 13. Preprocessing (M6)
**Why 5-second windows, non-overlapping?** Balance of stable statistics vs catching change (~12 windows/min); non-overlapping so each window is an independent observation with no leakage.
**How do you handle missing samples?** Short gaps (≤2 s): interpolate continuous values (RSSI), forward-fill counters. Longer gaps: discard the window. Any window under 4 of 5 expected samples is dropped.
**Do you report data quality?** Yes — the discarded-window fraction (well under 1% in our runs) is reported as a quality metric.
**Timestamp alignment?** Each board's clock starts at its own boot, so we re-base each node's timestamps against the root's phase log before merging.

---

# Milestone 7 — Feature Engineering

## 14. Features (M7)
**How many features and what layers?** 16, across PHY (RSSI mean/var/stability), MAC (retry rate), Network (forwarding ratio, PDR, parent-switch, layer-change, hop-stability), cross-layer (RSSI-hop, latency-hop, consistency), and auxiliary tunnel (intensity/bytes/latency).
**⚠️ Five are empty in most runs — do you really have 16?** They're blank *by design* where the behavior is absent (relay features need the blackhole attacker; tunnel features need the wormhole). Per run 10–13/16; across the combined dataset, 16/16. Every blank is flagged.
**Do you check for redundant or dominant features?** Yes — low-variance filter, drop one of any pair correlated above 0.85, and PCA to see which carry the variance. We cluster on both the full and reduced sets to be sure no single feature drives the result.
**Explain PDR precisely.** Unique probe sequence numbers the root logged from a victim ÷ probes that victim sent, per window. Zero when the root heard the victim but got nothing (real blackhole); blank when the root never heard it at all (coverage gap) — the two are kept distinct on purpose.
**Explain Retry Rate.** Retransmissions ÷ total attempts — MAC-layer link stress. 0.004 normal, 0.165 under blackhole.
**Explain RSSI-Hop Inconsistency.** Observed RSSI minus the expected RSSI for that layer (the expected value is the baseline median for that layer *in the same run*). Big gap = physical/logical mismatch (wormhole).
**⚠️ Latency features from unsynced clocks — valid?** The clock error is a fixed constant per node, so subtraction cancels it. Latency-per-hop uses each node's own minimum; tunnel latency uses the gap between a probe's two arrivals. No firmware change, no re-capture.

---

# Milestone 8 — Exploratory Data Analysis (clustering)

## 15. Clustering & analysis (M8)
**⚠️ Why cluster when you have labels?** Goal is to show the data has natural structure, not to train a detector that would overfit our small lab set. Labels are used only afterward to score cluster quality.
**Which algorithms and why five?** DBSCAN (density + noise/outliers), K-Means (baseline), GMM (soft overlapping groups), hierarchical and spectral (odd-shaped clusters). Comparing several guards against any one's assumptions.
**How do you evaluate clusters?** Internal (no labels): Silhouette, Davies–Bouldin. External (with labels): Cluster Purity, Adjusted Rand Index.
**Do you normalize?** Yes — z-score, so features on different scales (byte counts vs ratios) contribute fairly to distance-based clustering.
**⚠️ With 4/24 runs, can you show separability?** Not fully yet, and I won't overstate it. Per-attack signatures are strong and repeatable; full between-class separation needs baseline+blackhole+wormhole in one table — the immediate next step.

---

# Defense meta (cross-cutting — rigor, reproducibility, stress questions)

## 17. Deviations from the proposal (know all four)
**D-1 sampling:** capture at 10 Hz, analyze at the spec's 1 Hz (down-sampled). Safety margin against row loss.
**D-2 latency-hop:** relative one-way delay instead of round-trip (no response leg exists); clock offset cancels under subtraction.
**D-3 tunnel latency:** measured as the gap between a probe's duplicate arrivals (tunnel is one-way, no echo); keyed to the affected sender.
**D-4 topology check:** excludes the mesh's initial forming window so first parent-acquisition isn't miscounted as instability.
All four are written up in `thesis-deviate.md` with reason and measured impact.

## 18. Engineering rigor & environment
**What was genuinely hard?** Real-hardware failures: a silent data-loss bug (two logs glued together — fixed by splitting on schema); flash overfilling until unreadable (wrote a raw-memory recovery tool, rebuilt 6,000+ rows); a validator that called a perfect wormhole "broken" (it assumed attacks mean fewer packets, but wormhole means more). Each documented with its fix.
**⚠️ What ESP-IDF version?** The boards now run **v5.5.4**. (Note: the README still says v5.3.5 — reconcile that before defense so what you say matches what ran.)
**What other tools?** ESP-IDF/C for firmware, Wireshark for packet verification, Python (pandas/numpy/scikit-learn/matplotlib/seaborn/scipy) for the pipeline.
**Why is logging trustworthy during an attack?** Logging runs as a separate task, writes to local flash, and never goes over the mesh — so dropping mesh traffic can't corrupt it.

## 19. Reproducibility & statistics
**Can another team reproduce this?** Yes — fixed phase timeline, broadcast phase IDs, per-run empirical baselines, tracked raw captures with checksums. One command runs a full experiment.
**⚠️ Is your sample size enough for statistics?** For the exploratory claim, the signatures are large and consistent across repeats. We don't make statistical-power claims — that's honestly a scale limitation and future work. Repeats (r1–r3) exist to show consistency, not to run hypothesis tests.
**How do you handle randomness between runs?** Repeats per cell, and baselines computed from each run's *own* stable window, so a run is judged against itself, not a fixed nominal.

## 20. Contribution, significance, future work
**Contribution in one line?** The first real, labeled, cross-layer ESP32 mesh attack dataset, plus reproducible tooling and an exploratory separability analysis.
**Significance / SDG?** Supports UN SDG 9 (resilient low-cost infrastructure) by improving empirical understanding of low-cost mesh security.
**Future work?** Finish the 24-run matrix, add topologies, more attack types (grayhole/Sybil), larger/outdoor deployments, and — building on this dataset — an actual detector.

## 21. ⚠️ Your three known weak spots (have these ready)
1. **Attacks are emulations, not protocol-level.** Answer: forced by the closed Wi-Fi stack; we reproduce the observable effect, which is what any analysis sees. Own it first.
2. **Only 4 of 24 runs; separability not fully shown.** Answer: pipeline proven, signatures clear; combined-table separability is the next deliverable. Don't over-claim results.
3. **Small, indoor, controlled scale.** Answer: deliberate trade for clean ground truth; scale/environment generalization is named future work.

## 22. Devil's-advocate / stress questions
**"Why should we pass this?"** It delivers a working real-hardware testbed, a reproducible labeled dataset with clear attack signatures, and honest analysis — the exact gap the literature has. The remaining work is more runs, not a broken method.
**"What's the single biggest risk to your conclusions?"** That the combined multi-attack table doesn't separate as cleanly as single-attack signatures suggest. We mitigate by testing multiple clustering methods and both full/reduced feature sets.
**"If we gave you one more month, what would you do?"** Finish the matrix (the other 20 runs and 3 topologies) and run the full separability study, because that's what turns strong per-attack signatures into the paper's headline claim.
**"Convince me your labels are real."** They come from the root's broadcast schedule, stamped at capture time, independent of any measurement — shown in `phase_id_to_label()`.
**"Can you run it right now?"** Yes — one command flashes, runs the ~8–11 min experiment, exports, and analyzes. Pre-checks: storage not full, boards carried unplugged, never run `set-target`.

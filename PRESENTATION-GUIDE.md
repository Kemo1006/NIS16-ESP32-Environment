# 🎤 Presentation Guide — NIS16 / CTTHES2

> **Status at time of writing: 2026-07-27, matrix at 8/24.**
> Every number in this file is taken from the repo, not estimated. If you re-run
> anything before presenting, refresh the numbers — a wrong figure on a slide is worse
> than a smaller one.

---

## 🎯 The frame to open with (and never lose)

> **"This is a data-collection project. The deliverable is a labelled dataset of mesh
> telemetry under two attacks across four topologies — built so other researchers can
> reuse it."**

This single sentence changes how everything else is judged. You are **not** claiming a
detector works. You are claiming the data is **real, labelled, reproducible and honestly
documented**. Say it in the first minute.

**Two words to avoid all deck:** *"proves"* and *"perfect."* Use **"shows"**, **"measured"**,
**"reproduced."**

---

## 📊 The three numbers to memorise

If you remember nothing else on stage:

| | |
|---|---|
| **8 / 24** | M4 runs collected. Say it openly — an honest partial matrix beats a vague full one. |
| **720 / 720 / 0** | Blackhole: probes received / dropped / forwarded during the attack. Root logged **0** arrivals. |
| **181 · 181 · 180** | Wormhole duplicate deliveries, reproduced across three runs on **two** topologies. |

---

## 🗂️ Slide-by-slide plan (~14 slides)

### Slide 1 — Title + the frame
- Title, name, date
- One line: *"A labelled mesh-telemetry dataset under blackhole and wormhole attacks."*

### Slide 2 — The testbed (one diagram)
- 6 × ESP32 · routerless ESP-WIFI-MESH · channel 11
- 1 root + 5 children
- **Say:** "The root broadcasts the phase ID; every node stamps it into every row. That's
  where the ground-truth label comes from — it isn't added afterwards."

### Slide 3 — The run timeline
```
phase 0 BASELINE 300s  →  phase 1/2 ATTACK 180s  →  phase 3 COOLDOWN 120s
gt_label 0                gt_label 1 or 2           gt_label 0
```
- **Say:** "Every run carries its own benign reference. The attack window is the only thing
  that changes."

### Slide 4 — 🟢 M1 · Firmware (15%)
- `mesh_setup.c` · `phase_listener.c` · `csv_logger.c` · `root_main.c` · `victim_main.c`
- **Killer evidence — a live boot log line:**
  ```
  MESH_SETUP: Topology shaping: STAR (max_layer=2, max_children=10)
  ```
- **Say:** "Topology isn't a filename tag — it's a compile-time constraint the mesh stack
  enforces. Star caps depth at 2, so a board *cannot* become a grandchild."

### Slide 5 — 🟢 M2 · Attack modules (15%) ⭐ **your strongest slide**

Put **both tables** on it. This is the slide that wins the room, because each attack is
measured on **two independent boards** that agree.

**Blackhole** — attacker's own counters vs the root's arrivals log:

| phase | received | forwarded | dropped | root arrivals |
|---|---|---|---|---|
| baseline | 0 → 1439 | 0 → 1439 | 0 | 1436 |
| **attack** | 1439 → **2159** | **1439 → 1439** | 0 → **720** | **0** |
| cooldown | 2159 → 2643 | 1439 → 1923 | 720 | 483 |

**Wormhole** — duplicate `(src_mac, seq_num)` deliveries at the root:

| run | duplicates | multiplicity | source |
|---|---|---|---|
| linear r1 | 181 | ×2.00 | Node B |
| linear r3 | 181 | ×2.00 | Node B |
| star r1 | 180 | — | Node B |
| star r2 | 180 | — | Node B |

- **Say:** "720 received, 720 dropped, zero forwarded — and independently, the root logged
  zero arrivals. Two boards, two files, exact agreement."
- **Say:** "The wormhole is the opposite signature: traffic goes *up*, because Node B's
  probes are tunnelled over a wire and replayed. Zero duplicates in baseline and cooldown,
  every run."

### Slide 6 — 🟡 M3 · Multi-topology (15%)

| Topology | Baseline | Blackhole | Wormhole |
|---|:--:|:--:|:--:|
| Tree | ✅ | ✅ | ✅ |
| Linear | ✅ | ✅ | ✅ |
| Star | ✅ | ✅ | ✅ |
| Partial | ✅ | 🔴 | 🔴 |

- **Killer evidence — the reconstruction, not the intention:**
  ```
  NODE_2805A532D7B4 (layer 1, root)
      NODE_704BCA25B768  (layer 2)   NODE_B0CBD8F33218 (layer 2, wormhole_a)
      NODE_B4BFE932FE90  (layer 2)   NODE_B4BFE934ED80 (layer 2)
      NODE_F42DC973E618  (layer 2, wormhole_b)
  PASS star: all 5 nodes at layer 2 (direct children of root)
  ```
- **Say:** "`verify_topology.py` rebuilds the tree from each node's own `parent_mac` and
  `layer` columns. It's independent of what I intended — it reports what actually formed."

### Slide 7 — 🔴 M4 · Experiment execution (15%) — **be direct**
```
linear ▸ blackhole   ✅✅✅   3/3
linear ▸ wormhole    ✅✅✅   3/3
star   ▸ wormhole    ✅✅⬜   2/3
(5 cells pending)            8/24
```
- **Say, plainly:** "Eight of twenty-four. Two cells fully replicated. Every recorded cell
  is zero-FAIL. The rest is runtime, not unknowns."
- ⚠️ **Do not hide this slide or rush it.** Owning it is what makes the rest credible.

### Slide 8 — 🟢 M5 · Extraction & integrity (10%)
- `validate_integrity.py`: schema · phase coverage · timestamp monotonicity · label
  integrity · **SHA-256 manifest**
- **Killer line:** "Every recorded cell: **0 FAIL**. A cell is only marked done if its CSVs
  pass validation — the ledger can't be ticked by hand."
- Mention the guards briefly (see Slide 12).

### Slide 9 — 🟢 M6 + 🟢 M7 · Pipeline & features (20%)
- M6: per-node re-basing → cumulative-to-delta → 5 s windowing → modal labels
- **Discard fraction 0.2 – 0.8 %** across every dataset
- M7: **16/16 features** present and populated by at least one run type
- **Killer point:** "Two features were NaN in every run three days ago —
  `LatencyHopRatio` and `TunnelLatency`. Both now populate."

### Slide 10 — 🟡 M8 · EDA (10%)
Five analyses per §4.2.6: descriptive stats · distributions · time-series · Pearson +
Spearman correlation · PCA/t-SNE.

| dataset | windows | benign / attack |
|---|---|---|
| blackhole · linear | 2470 | 1820 / 650 |
| wormhole · linear | 2470 | 1819 / 651 |
| wormhole · star | 1674 | 1240 / 434 |

- **Say:** "EDA here is strictly descriptive — the thesis specifies no detection rules are
  derived at this stage, and none are."

### Slide 11 — The plot you must explain before you're asked

Show **both** projections side by side.

- **Whole-mesh PCA** excludes the tunnel features — they exist on 2 of 6 nodes (~67 % NaN),
  above the 50 % cutoff.
- **Tunnel-end projection** keeps them, over the nodes that have a tunnel.

- **Say:** "The first asks *can you see the attack in what every node measures?* — the
  realistic detection question. The second asks *does the tunnel evidence separate?* Both
  are honest; neither replaces the other."

### Slide 12 — Data quality engineering (your differentiator)
Most students don't have this slide. It shows you understand your own failure modes.

- **Wrong-file export** → schema checked at capture; bad file quarantined, `--delete` skipped
- **Stale derived files** → flagged when a raw source disappears
- **Duplicate captures** → flagged before they double-count a node
- **Say:** "Each of these silently corrupted a dataset once. Now each fails at the moment
  it happens, not twenty minutes later in the analysis."

### Slide 13 — Known limitations ⭐ **do not skip this**
Naming these yourself converts every one from an attack into a strength.

1. **Matrix at 8/24** — remaining work is runtime
2. **Repeats share a topology class, not a fixed parent assignment** — parents are chosen by
   signal at boot *(deviation D-6)*
3. **Baseline control = each run's phase 0**, not separate baseline runs *(deviation D-5)*
4. **Star r1 needed ~100 s to stabilise; r2 converged inside 60 s** — cause not established
5. **`TunnelLatency` keying deviates from Table 4.12** *(deviation D-3, deferred to CTTHES3)*

- **Say:** "All five are recorded in `thesis-deviate.md` with reasoning and what each costs."

### Slide 14 — Next steps
1. 16 runs to complete M4
2. `baseline · star` to settle the convergence question
3. M8 separability once the matrix is full
4. RTT leg + wormhole echo frame → CTTHES3

---

## 🛡️ Hard questions — prepared answers

**"How do you know it's really a star / a linear chain?"**
> Two independent things. The build flag sets a compile-time constraint —
> `MESH_TOPOLOGY=0` caps `max_layer` at 2. And `verify_topology.py` rebuilds the actual tree
> from each node's `parent_mac`/`layer` in the telemetry and checks it. One is intent, the
> other is measurement.

**"Are your three repeats identical runs?"**
> The topology class is fixed and verified every run. The specific parent assignment is not
> — parents are chosen by signal strength at boot, which is the mesh behaviour under study.
> Pinning it would mean overriding the thing I'm measuring. It's recorded as deviation D-6.
> The attack signature held across all of them: 181, 181, 180.

**"Why is there no baseline run for star, tree and partial?"**
> Each attack run contains its own 300 s benign phase, and it's a better-matched control:
> same firmware, same roles, same session, so the attack is the only variable. A separate
> baseline run differs in two ways — different firmware, and one fewer probing node, since
> the attacker relays instead of originating. Measured: baseline·linear has 5 victims at
> 4.90 probes/s, attack-run phase 0 has 4 at 3.9/s. Recorded as D-5.

**"Why does star fail the convergence criterion?"**
> ⚠️ *Be honest — this one is unresolved.*
> In the first star run nodes took 99–153 s to settle. I moved the boards closer to the
> root; join times dropped to 1.3–6.7 s, but the run still failed — the mechanism changed
> from *not finding* the root to *dropping and re-attaching*. The **second** repeat then
> converged inside 60 s with no baseline re-routing, same placement. So it isn't a fixed
> property of star. The clean test is a baseline·star run, which I haven't done yet.
> Importantly: **every disturbance is in phase 0. Zero during the attack window** — which is
> why the signature is clean.

**"Why is TunnelIntensity NaN for most rows?"**
> It's attacker-keyed by design — Table 4.12 says tunnel fields are present only for
> attacker nodes. It populates on both tunnel ends and nowhere else: 854 windows on linear,
> and the count matches on star. It's role-exclusive, not missing.

**"Your matrix is only a third complete."**
> Correct — 8 of 24. Two cells are fully replicated and every recorded cell is zero-FAIL.
> The infrastructure and analysis are complete and validated; what remains is runtime.

**"How do we know the data is genuine?"**
> Every capture is SHA-256 hashed into a manifest at validation time, the ledger records
> when each cell was validated, and the whole repository is version-controlled with the
> commit history public. The attack signatures are also cross-verified between independent
> boards — the attacker's counters and the root's arrivals log agree exactly.

**"What would you do differently?"**
> Add the RTT leg to the probe protocol from the start — that's the one firmware gap that
> forced two documented deviations. I deferred it because changing firmware now would
> invalidate every run already captured.

---

## ⏱️ Timing (15-minute slot)

| | |
|---|---|
| Frame + testbed + timeline | 2 min |
| M1 + M2 (attack evidence) | **4 min** ⭐ spend time here |
| M3 + M4 | 3 min |
| M5 + M6 + M7 | 2 min |
| M8 + the two projections | 2 min |
| Limitations + next steps | 2 min |

**If you run short:** cut M6/M7 detail, never the M2 evidence or the limitations slide.

---

## ✅ Final checks before you present

- [ ] Re-run `python tools\run_matrix.py --status` and update slide 7 if the count changed
- [ ] Export the two PCA plots and the correlation heatmap as images
- [ ] Have `verify_topology.py` output ready for **one** run — the reconstruction is the
      most convincing single artifact you own
- [ ] Know your three numbers cold: **8/24 · 720/720/0 · 181-181-180**
- [ ] Practise the star convergence answer out loud — it's the one question where you'll be
      tempted to over-claim

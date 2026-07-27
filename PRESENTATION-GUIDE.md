# 🎤 Presentation Guide — NIS16 / CTTHES2

> **Snapshot: 2026-07-27 · matrix at 15/24.**
> Every figure below was read out of the repo, not estimated. **Re-check the three
> starred numbers on the morning of the defence** — a stale figure on a slide is worse
> than a smaller true one.

---

# PART 0 · Before you build a single slide

## 0.1 The frame — decide this first, everything follows

> **"This is a data-collection project. The deliverable is a labelled dataset of mesh
> telemetry under two attack types across four topologies, built so other researchers can
> reuse it."**

Say it in the **first 45 seconds**. It reframes every question that follows:

| If they think you're claiming… | They will ask… | And you'd be in trouble |
|---|---|---|
| "my detector works" | "What's your accuracy? Precision? F1?" | You have no classifier yet |
| "my mesh is perfect" | "Why did star fail convergence?" | You'd have to defend a failure |
| **"my data is real and honest"** ✅ | "How do you know it's genuine?" | **You have excellent answers** |

You are being judged on **whether the data is trustworthy**, not on whether an attack was
detectable. Every strong artifact you own points at trustworthiness.

## 0.2 Vocabulary discipline

| ❌ Never say | ✅ Say instead |
|---|---|
| "This proves…" | "This shows…" / "This measured…" |
| "Perfect / flawless" | "Zero-FAIL across all recorded cells" |
| "It should work" | "It reproduced across three runs" |
| "The data is clean" | "0.2–0.8 % of windows discarded" |
| "We didn't have time" | "That's remaining runtime, not an unknown" |

## 0.3 Team roles (if presenting as a group)

| Role | Owns | Must be able to answer |
|---|---|---|
| **Lead / framing** | Slides 1–3, 13–14 | "What is the contribution?" "What are the limits?" |
| **Firmware** | Slides 4–5 | "How is the attack implemented?" "How is the label produced?" |
| **Experiment** | Slides 6–8 | "How do you know it's a star?" "Why 15/24?" |
| **Analysis** | Slides 9–12 | "Why is this feature NaN?" "What does the PCA show?" |

**Rule:** whoever owns a slide answers questions on it. Agree this beforehand — hesitation
about *who speaks* reads as uncertainty about the *content*.

## 0.4 The three numbers everyone on the team memorises

| | | Where it comes from |
|---|---|---|
| ⭐ **15/24** | M4 runs collected | `run_matrix.py --status` |
| ⭐ **720 / 720 / 0** | Blackhole: received / dropped / forwarded | attacker telemetry |
| ⭐ **181 · 181 · 180** | Wormhole duplicates across runs | root arrivals log |

## 0.5 Dataset scale (good for slide 2 or 10)

| | |
|---|---|
| Raw captures | **65 files · 36.5 MB · 498,921 telemetry rows** |
| Feature windows | **7,191** across three datasets |
| EDA outputs | **96 files** |
| Boards | 6 × ESP32-D0WD-V3, 4 MB flash |

---

# PART 1 · Slide-by-slide, with what to actually say

> Format: **[LAYOUT]** what's on the slide · **[SAY]** near-verbatim script ·
> **[WHY]** what it earns you · **[TRAP]** what to avoid.

---

## Slide 1 — Title & contribution

**[LAYOUT]** Title · names · date · one subtitle line.

**[SAY]**
> "Good morning. Our project builds a labelled dataset of wireless mesh telemetry under two
> attack types, across four network topologies, using six ESP32 boards. The contribution is
> the dataset itself — captured, validated and documented so other researchers can build
> detection work on top of it. I'll walk through the eight milestones and show the evidence
> behind each."

**[WHY]** Sets the frame before anyone forms a different expectation.

**[TRAP]** Don't open with hardware specs. Open with what you're contributing.

---

## Slide 2 — The testbed

**[LAYOUT]** One diagram: root at centre/top, 5 children, labels `node1`–`node6`. Side panel
with: routerless ESP-WIFI-MESH · channel 11 · 10 Hz sampling · 6 boards.

**[SAY]**
> "Six ESP32s form a routerless mesh — no WiFi router, the boards organise themselves. One
> root, five children. Each node samples its own telemetry at 10 Hz and writes it to internal
> flash. Nothing streams to the laptop during a run; we pull the CSVs over USB afterwards."

**[WHY]** Pre-empts "how do you collect the data?" and explains why an export failure matters.

**[TRAP]** Don't get pulled into ESP-IDF version details. If asked, "ESP-IDF v5.5.4" and move on.

---

## Slide 3 — The phase timeline ⭐ *this is where labels come from*

**[LAYOUT]** A horizontal bar, three coloured segments:

```
┌─────────────────────────┬──────────────────┬────────────┐
│  phase 0 · BASELINE     │ phase 1/2 ATTACK │ phase 3    │
│  300 s   gt_label = 0   │ 180 s  label 1/2 │ COOLDOWN   │
└─────────────────────────┴──────────────────┴────────────┘
        blackhole = label 1 · wormhole = label 2
```

**[SAY]**
> "Every run follows the same timeline. The root broadcasts the current phase ID over the
> mesh, and every node stamps that ID into every telemetry row it writes. So the ground-truth
> label is produced **by the experiment as it runs** — not annotated by hand afterwards. That
> matters for a dataset: the labels can't drift from the data."

**[WHY]** This is the single most important methodological point in the whole talk. A
reviewer who understands it will trust everything downstream.

**[TRAP]** Don't rush this slide to get to results. Spend 45 seconds.

---

## Slide 4 — 🟢 M1 · Firmware (15%)

**[LAYOUT]** Left: component list. Right: a real boot-log screenshot.

```
components/mesh_common/
  mesh_setup.c      — mesh init + topology shaping
  phase_listener.c  — receives/【broadcasts phase IDs
  csv_logger.c      — 10 Hz logging to SPIFFS
root_node/main/root_main.c
child_node/main/victim_main.c · blackhole_victim.c · wormhole_victim.c
```

**Evidence line — put this on the slide verbatim:**
```
I (780) MESH_SETUP: Topology shaping: STAR (max_layer=2, max_children=10)
```

**[SAY]**
> "All node roles are implemented. The point I want to highlight is the topology line: the
> topology isn't a filename tag, it's a **compile-time constraint** the mesh stack enforces.
> For star it caps the maximum layer at 2, so a board physically cannot become a grandchild —
> the stack refuses the association."

**[WHY]** Sets up slide 6 and pre-empts "how do you know it's really a star?"

---

## Slide 5 — 🟢 M2 · Attack modules (15%) ⭐⭐ **YOUR STRONGEST SLIDE**

> Budget **4 of your 15 minutes here.** This is where you win the room.

**[LAYOUT]** Split the slide. Left = blackhole table. Right = wormhole table. A one-line
banner across the top: **"Each attack measured on two independent boards that agree."**

**BLACKHOLE — attacker's counters vs the root's arrivals log**

| phase | received | forwarded | dropped | root arrivals |
|---|---|---|---|---|
| baseline | 0 → 1439 | 0 → 1439 | 0 | 1436 |
| **ATTACK** | 1439 → **2159** | **1439 → 1439** | 0 → **720** | **0** |
| cooldown | 2159 → 2643 | 1439 → 1923 | 720 | 483 |

**WORMHOLE — duplicate `(src_mac, seq_num)` deliveries at the root**

| run | duplicates | source | baseline dupes |
|---|---|---|---|
| linear r1 | 181 | Node B | 0 |
| linear r3 | 181 | Node B | 0 |
| star r1 | 180 | Node B | 0 |
| star r2 | 180 | Node B | 0 |

**[SAY] — blackhole**
> "During the attack window the attacker received 720 probes, dropped 720, and forwarded
> zero. Its `tx_count` is completely flat. Separately — different board, different file — the
> root logged **zero** arrivals in that window. Two independent measurements, exact agreement.
> Then in cooldown it forwards 484 and the root logs 483; one was still in flight."

**[SAY] — wormhole**
> "The wormhole is the **opposite** signature. It doesn't drop traffic, it duplicates it.
> Node B's probes travel over a physical UART cable to Node A, which replays them — so the
> root receives the same packet twice and arrivals go *above* baseline. 181 duplicates,
> reproduced at 181 and 180 on a second topology, with zero duplicates in baseline or cooldown
> in every single run."

**[WHY]** Cross-verification between independent sources is the strongest evidence type you
have. Name it explicitly — say the words *"two independent measurements."*

**[TRAP]** Don't say "the attack worked perfectly." Say "the two measurements agree."

**[IF ASKED "why does the wormhole increase traffic?"]**
> "Because the tunnel is out-of-band. The probes still take their normal mesh path *and* a
> copy arrives through the wire, so the root sees both."

---

## Slide 6 — 🟡 M3 · Multi-topology deployment (15%)

**[LAYOUT]** Coverage matrix at top, `verify_topology.py` output at bottom.

| Topology | Baseline | Blackhole | Wormhole |
|---|:--:|:--:|:--:|
| Tree | ✅ | ✅ | ✅ |
| Linear | ✅ | ✅ | ✅ |
| Star | ✅ | ✅ | ✅ |
| Partial | ✅ | 🔴 | 🔴 |

```
NODE_2805A532D7B4  (layer 1, role root)
    NODE_704BCA25B768   (layer 2, victim)
    NODE_B0CBD8F33218   (layer 2, wormhole_a)
    NODE_B4BFE932FE90   (layer 2, victim)
    NODE_B4BFE934ED80   (layer 2, victim)
    NODE_F42DC973E618   (layer 2, wormhole_b)

PASS star: all 5 nodes at layer 2 (direct children of root)
Converged within 60s : YES        Baseline re-routing free : YES
```

**[SAY]**
> "Three of four topologies are covered for both attacks. What I want to show is *how* we
> verify it. This output isn't our intended diagram — `verify_topology.py` reads each node's
> own `parent_mac` and `layer` columns out of the telemetry and **reconstructs the tree that
> actually formed**. It's an independent check on the physical setup."

**[WHY]** Turns "trust me, I placed them right" into a measurement.

**[TRAP]** Don't show your floor-plan diagram as the *evidence*. Show it as *context*, and
show the reconstruction as evidence.

---

## Slide 7 — 🔴 M4 · Experiment execution (15%) — **be direct**

**[LAYOUT]** The matrix, big and unambiguous.

```
                     r1   r2   r3
linear ▸ blackhole   ✅   ✅   ✅     3/3  ██████████
linear ▸ wormhole    ✅   ✅   ✅     3/3  ██████████
star   ▸ wormhole    ✅   ✅   ⬜     2/3  ███████░░░
star   ▸ blackhole   ⬜   ⬜   ⬜     0/3  ░░░░░░░░░░
tree   ▸ blackhole   ⬜   ⬜   ⬜     0/3  ░░░░░░░░░░
tree   ▸ wormhole    ⬜   ⬜   ⬜     0/3  ░░░░░░░░░░
partial▸ blackhole   ⬜   ⬜   ⬜     0/3  ░░░░░░░░░░
partial▸ wormhole    ⬜   ⬜   ⬜     0/3  ░░░░░░░░░░
                                    15/24
```

**[SAY]**
> "This is the honest state: eight of twenty-four. Two cells are fully replicated at three
> repeats each, and the third is at two. Every recorded cell passed validation with zero
> failures. What remains is runtime — roughly eleven minutes per run plus exports. There are
> no unknowns left in the method, only runs left to do."

**[WHY]** Volunteering a shortfall with a clear plan reads as control. Hiding it and being
caught reads as the opposite.

**[TRAP]** ⚠️ **Do not rush past this slide.** Hold it. Let them read it. The instinct to
skip is exactly what makes it look bad.

---

## Slide 8 — 🟢 M5 · Extraction & integrity (10%)

**[LAYOUT]** Pipeline arrows + a validator output block.

```
board ──USB──▶ export_logs.py ──▶ trim_run.py ──▶ validate_integrity.py ──▶ ledger
                (schema guard)     (session split)   (5 checks + SHA-256)
```

```
21 file(s) — 21 PASS, 0 WARN, 0 FAIL
Manifest: .../trimmed/manifest.json
```

**[SAY]**
> "Every capture passes five checks — schema width, phase coverage, timestamp monotonicity,
> label integrity, and a SHA-256 hash locked into a manifest. A cell is only marked done in
> the matrix if its files pass; the ledger can't be ticked by hand. Every recorded cell is
> zero-FAIL."

**[WHY]** Directly answers "how do we know the data is genuine?" before it's asked.

---

## Slide 9 — 🟢 M6 · Preprocessing (10%)

**[LAYOUT]** Pipeline stages + the quality report.

```
raw 10 Hz ─▶ per-node re-basing ─▶ cumulative→delta ─▶ 5 s windows ─▶ modal labels
```
```
Windows kept: 2470     Discarded (<4 samples): 20     Discard fraction: 0.8 %
```

**[SAY]**
> "Counters in the firmware are cumulative, so we convert them to per-window deltas. Windows
> are five seconds, labelled by the modal phase ID within the window. Across every dataset the
> discard rate is between 0.2 and 0.8 percent — that's the fraction of windows with too few
> samples to be reliable."

---

## Slide 10 — 🟢 M7 · Feature engineering (10%)

**[LAYOUT]** A 16-row feature table, colour-coded by which node role carries it. Then the
recovery table.

| feature | 3 days ago | now |
|---|:--:|:--:|
| `LatencyHopRatio` | 🔴 NaN in every run | 🟢 **1534** windows |
| `TunnelLatency` | 🔴 NaN in every run | 🟢 **114** windows |

**[SAY]**
> "All sixteen Table 4.11 features are implemented. Some are **role-exclusive by design** —
> `ForwardingRatio` only exists on a blackhole relay, tunnel features only on the two wormhole
> ends. Those NaNs are correct, not missing data, and Table 4.12 specifies it. Two features
> were genuinely NaN in every run three days ago; both now populate."

**[TRAP]** If you show the NaN counts, **explain them before** anyone reads them as gaps.
"NaN here means *not applicable to this node role*, not *missing*."

---

## Slide 11 — 🟡 M8 · EDA (10%)

**[LAYOUT]** Five analysis names + dataset table.

| dataset | windows | benign / attack |
|---|---|---|
| blackhole · linear | 2470 | 1820 / 650 |
| wormhole · linear | 2470 | 1819 / 651 |
| wormhole · star | 1674 | 1240 / 434 |

**[SAY]**
> "All five analyses specified in section 4.2.6 run on every dataset: descriptive statistics,
> distributions, time-series, Pearson and Spearman correlation, and PCA with t-SNE. The thesis
> is explicit that EDA at this stage is strictly descriptive — no detection rules or thresholds
> are derived here, and none are."

---

## Slide 12 — The two projections ⭐ *explain before you're asked*

**[LAYOUT]** Two plots **side by side**, captioned.

**[SAY]**
> "These two plots answer different questions, and I want to explain why there are two.
>
> The first uses only features present on **every** node. It asks: can you see the attack in
> what any node can measure? That's the realistic detection question — but it excludes the
> tunnel features, because they exist on only two of six nodes, which is above our 50 percent
> missing-data cutoff.
>
> The second is restricted to the two tunnel-end nodes, with the tunnel features kept in. It
> asks: does the tunnel evidence itself separate the attack window?
>
> Both are honest. Neither replaces the other. We show both because showing only the first
> would look like there's no evidence, and showing only the second would overstate how easy
> detection is."

**[WHY]** This is a sophisticated methodological point delivered voluntarily. It signals you
understand your own analysis rather than just running it.

---

## Slide 13 — Data-quality engineering ⭐ *your differentiator*

**[LAYOUT]** Three failures → three guards.

| Failure that silently corrupted data | Now caught by |
|---|---|
| Device sent the **wrong file** (telemetry named as arrivals) | schema check at capture; file quarantined, `--delete` skipped |
| **Stale derived files** left after a re-export | flagged when a raw source disappears |
| **Duplicate captures** double-counting one node | flagged before analysis runs |

**[SAY]**
> "Each of these silently corrupted a dataset at least once during collection. The duplicate
> one produced no error at all — one node was counted twice and every total still looked
> plausible. Each now fails at the moment it happens rather than twenty minutes later in the
> analysis, and each is documented with the incident that produced it."

**[WHY]** Very few student projects have this slide. It demonstrates that you found your own
mistakes rather than waiting to be told.

---

## Slide 14 — Known limitations ⭐⭐ **NEVER SKIP**

**[LAYOUT]** Five numbered items, each one line, each with its deviation ID.

1. **Matrix at 15/24** — remaining work is runtime, not method
2. **Repeats share a topology class, not a fixed parent assignment** — parents chosen by
   signal at boot *(D-6)*
3. **Baseline control = each run's own phase 0**, not separate baseline runs *(D-5)*
4. **Star r1 took ~100 s to stabilise; r2 converged inside 60 s** — cause not established
5. **`TunnelLatency` keying deviates from Table 4.12** — deferred to CTTHES3 *(D-3)*

**[SAY]**
> "These are the limitations we know about. All five are recorded in `thesis-deviate.md` with
> the reasoning and what each one costs. I'd rather state them than have them found."

**[WHY]** Every item you name yourself is an item that can no longer be used against you. This
slide converts your weakest points into evidence of rigour.

**[TRAP]** Do not soften these into vague phrasing. Specific limitations read as confidence;
vague ones read as evasion.

---

## Slide 15 — Next steps

1. **9 runs** to complete M4
2. **`baseline · star`** — settles the convergence question
3. **M8 separability** once the full matrix exists
4. **RTT leg + wormhole echo frame** → CTTHES3 *(deliberately deferred: changing firmware now
   would invalidate every run already captured)*

**[SAY]**
> "Point four is a deliberate choice, not an oversight. Adding the round-trip leg would fix two
> documented deviations — but it changes the firmware, and every run captured so far would no
> longer be comparable. So it's scheduled for the next phase rather than mid-collection."

---

# PART 2 · Optional live demo (high risk, high reward)

If the room allows it, **one** live command is worth ten slides.

```powershell
cd tools
python verify_topology.py --dir exports\wormhole\star_topology\trimmed `
    --topology star --attack wormhole --repeat 2 --expect star
```

It prints the reconstructed tree and `PASS star` in about two seconds.

**Rules if you do this:**
- ✅ Test it on the presentation machine **beforehand**, in the exact directory
- ✅ Have the output as a **screenshot on a backup slide** in case it fails
- ✅ Pick the run you know passes — **star r2** (converged: YES)
- ❌ Never demo anything involving hardware, exports or COM ports
- ❌ Never demo something you haven't run that morning

---

# PART 3 · Question bank

## Tier 1 — near-certain

**"How do you know it's really a star / a linear chain?"**
> "Two independent things. The build flag sets a compile-time constraint — for star,
> `max_layer` is capped at 2, so the stack refuses a deeper association. And separately,
> `verify_topology.py` rebuilds the actual tree from each node's `parent_mac` and `layer`
> columns in the telemetry. One is intent; the other is measurement of what formed."

**"Your matrix is only a third complete."**
> "Correct — eight of twenty-four. Two cells are fully replicated and every recorded cell is
> zero-FAIL. The infrastructure, validation and analysis pipeline are complete; what remains
> is runtime, about eleven minutes per run."

**"How do we know the data is genuine?"**
> "Three things. Every capture is SHA-256 hashed into a manifest at validation time. The
> ledger records when each cell was validated. And the attack signatures are cross-verified
> between independent boards — the attacker's own counters and the root's arrivals log agree
> exactly, and those are separate devices writing separate files."

**"Why is `TunnelIntensity` NaN for most rows?"**
> "It's attacker-keyed by design. Table 4.12 specifies tunnel fields are present only for
> attacker nodes. It populates on both tunnel ends and nowhere else — 854 windows on linear.
> It's role-exclusive, not missing."

## Tier 2 — likely

**"Are your three repeats identical runs?"**
> "The topology class is fixed and verified every run. The specific parent assignment isn't —
> parents are chosen by signal strength at boot, which is the mesh behaviour we're studying.
> Pinning it would mean overriding the thing being measured. It's recorded as deviation D-6.
> The attack signature held across all repeats regardless: 181, 181, 180."

**"Why no separate baseline run for star, tree and partial?"**
> "Each attack run contains its own 300-second benign phase, and it's a better-matched
> control: same firmware, same node roles, same session, so the attack is the only variable. A
> separate baseline run differs in two ways at once — different firmware, and one fewer probing
> node, because the attacker relays instead of originating. We measured it: baseline·linear has
> five probing victims at 4.90 probes per second; attack-run phase 0 has four at about 3.9.
> Recorded as deviation D-5."

**"Why does star fail the convergence criterion?"** ⚠️ *the honest one*
> "In the first star run nodes took 99 to 153 seconds to settle. We moved the boards closer to
> the root — join times dropped to between 1.3 and 6.7 seconds — but that run still failed, and
> the mechanism had changed: instead of failing to find the root, nodes were dropping and
> re-attaching. Then the **second repeat converged inside 60 seconds** on the same placement,
> with no baseline re-routing. So it isn't a fixed property of star. We haven't established the
> cause. The clean test is a baseline·star run, which we haven't done yet.
>
> What I can say with confidence is that **every disturbance is in phase 0 — zero during the
> attack window** — which is why the attack signature is clean in both runs."

**"What's your detection accuracy?"**
> "We don't report one. This phase produces the dataset; the thesis is explicit that EDA here
> is strictly descriptive and no detection rules are derived at this stage. Building and
> evaluating a classifier is the next phase, and it needs the full matrix."

## Tier 3 — harder / adviser-level

**"Isn't using phase 0 as your control circular? The attacker firmware is running."**
> "It is running, but not attacking — during phase 0 the blackhole relay forwards every probe
> normally, and we can see that in its counters: `tx_count` climbs one-for-one with received.
> The alternative has a bigger problem: a separate baseline run changes firmware *and* traffic
> composition simultaneously. We chose the control that isolates one variable and documented
> the trade-off."

**"Your labels come from the root's broadcast — what if a node misses it?"**
> "Then its rows carry the previous phase ID until the next broadcast arrives, and
> `validate_integrity.py` checks label integrity against the phase-to-label map on every row.
> It's one of the five checks, and no recorded cell has failed it."

**"What would you do differently?"**
> "Add the round-trip leg to the probe protocol from the start. It's the one firmware gap that
> forced two documented deviations. I deferred it deliberately, because changing firmware
> mid-collection would invalidate every run already captured."

**"Why 5-second windows? Why 10 Hz?"**
> "10 Hz is the capture rate; we downsample to a 1 Hz grid for analysis, which is deviation
> D-1. Five-second windows give five samples per window on that grid — enough for variance
> features while keeping the attack window at 36 windows."

## If you genuinely don't know

**Use this sentence. Do not improvise:**
> *"I don't have that measured. What I can tell you is [nearest thing you did measure], and
> the experiment that would answer it is [X]."*

Panels respect this. They do not respect a confident guess that unravels under one follow-up.

---

# PART 4 · Timing & delivery

## 15-minute slot

| Segment | Time | Cumulative |
|---|:--:|:--:|
| Frame + testbed + timeline (1–3) | 2:00 | 2:00 |
| M1 + **M2 evidence** (4–5) | **4:00** ⭐ | 6:00 |
| M3 + M4 (6–7) | 3:00 | 9:00 |
| M5 + M6 + M7 (8–10) | 2:00 | 11:00 |
| M8 + projections (11–12) | 1:30 | 12:30 |
| Quality + limitations + next (13–15) | 2:30 | 15:00 |

**Running short?** Cut M6/M7 detail. **Never** cut slide 5 (evidence), 7 (honest matrix) or
14 (limitations).

## Delivery notes

- **Slow down on slides 3, 5 and 14.** These are the three that decide how you're judged.
- **Point at specific numbers** on the table rather than describing them generally.
- When you say a number, **pause for one second** after it. It lands.
- If a question comes mid-slide, answer it and say *"I'll come back to that on slide 14"* if
  it's covered later — then actually come back to it.

---

# PART 5 · Checklist

## Night before
- [ ] Re-run `python tools\run_matrix.py --status` → update slide 7 if the count moved
- [ ] Export plots as PNG: both projections, correlation heatmap, one time-series
- [ ] Screenshot `verify_topology.py` output for **star r2** (the one that passes)
- [ ] Screenshot a validator run showing `0 FAIL`
- [ ] Screenshot the boot log line showing `Topology shaping: STAR`
- [ ] Backup slides: the NaN table, the deviation list, the raw dataset stats

## Morning of
- [ ] Verify the three starred numbers are still current
- [ ] If demoing: run the command once on the presentation machine
- [ ] Each team member can state the frame sentence from memory
- [ ] Each team member knows which slides they own

## Do not
- [ ] ❌ Claim any detection performance
- [ ] ❌ Say "perfect", "proves", or "clean data"
- [ ] ❌ Skip slide 7 or 14
- [ ] ❌ Improvise an answer about star convergence — use the prepared one

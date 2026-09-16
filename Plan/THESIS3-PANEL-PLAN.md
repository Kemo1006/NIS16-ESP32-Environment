# THESIS 3 — Panel Comment Response Plan (DRAFT for adviser)

**Source:** `Paper/Improvements.pdf` — panelist comments on the CTTHES2 (Thesis 2) presentation.
**Status:** DRAFT — nothing implemented yet. For discussion with Adviser (Cu, Gregory G.) before any code or capture work starts.
**Drafted:** aug. 06, 2026

> **Paths:** relative to the workstation root (`Thesis_workstation/`), *except* in §2's tables and anywhere `analysis/`, `tools/`, `components/`, `root_node/`, `child_node/`, or `run.ps1` appears — those are relative to `NIS16-ESP32-Environment-semi-final/`.

---

## 1. What the panel actually said (7 themes)

The PDF has 8 timestamped rows, but they collapse into 7 distinct problems. Several rows repeat the same one.

| # | Theme | From (timestamp) |
|---|---|---|
| **P1** | Dataset must not be decidable by a **single feature** — if 1 of 16 features says "attack", the other 15 and the ML are pointless | rows 1–2 |
| **P2** | Attacks have **no parameter variation** — hardcoded scripts, identical behavior every run | 2:40–4:50 |
| **P3** | **r1→r3 are redundant** — vary attacker *position* per run; cite a target-deployment paper | 12:45–16:00, 5:15–7:10 |
| **P4** | Only one physical **environment** (the house) — run in public/varied places | 8:40–8:55 |
| **P5** | No declared **IoT deployment scenario** — is this smart farming? smart home? Node placement looks arbitrary; ground it in literature | 9:10–12:00 |
| **P6** | No **attack validation / provenance** — what are the scripts based on? If the topology is right but the attack is wrong, the data is wrong | 17:50–18:30, 44:30–49:00 |
| **P7** | **Benign baseline is not characterized** — benign and attack scenarios are otherwise identical, so clustering is biased; need a *high-legitimate-load* benign class so the model doesn't just learn "high volume = attack". Also: shorter runs, more variations, instead of 1 hour each | 44:30–49:00 |

Plus one bookkeeping ask inside P3: **is the dataset balanced** across the 16-of-24 runs?

---

## 2. Where each one actually bites in our code

This section is the evidence for the adviser — the panel's criticisms are correct, and here is exactly where.

### P1 — Single-feature decidability: **we have a worse version of this problem**

`analysis/features.py:96-106` defines three features as *relay-only*:

```
FEATURES_BLOCKED_ON_FIRMWARE = ("ForwardingRatio", "IngressEgressDelta", "ConsistencyScore")
```

Per the module docstring (`features.py:16-49`):

- `ForwardingRatio` / `IngressEgressDelta` / `ConsistencyScore` are non-NaN **only for the blackhole attacker row**
- `TunnelIntensity` / `TunnelBytes` are non-NaN **only for the wormhole endpoints**

So the question *"is this column NaN?"* is a **perfect label**. That is the single-feature problem in its harshest form — not one feature that correlates with the attack, but a **missingness pattern that IS the ground truth**. Any clustering on this table is trivially separable and proves nothing.

Second instance, from `MEMORY.md:19`: blackhole attack-window PDR ≈ **0.08** vs benign **0.94**, `ForwardingRatio` ≈ 0.02. A single threshold on PDR separates the classes near-perfectly. The panel is right that ML is currently unnecessary.

### P2 — No parameter variation: confirmed, everything is a compile-time constant

| Knob | Where | Current value | Varies? |
|---|---|---|---|
| Blackhole drop rate | `child_node/main/blackhole_victim.c:195-197` | **100%**, silent, whole attack phase | No |
| Probe interval | `components/mesh_common/include/mesh_config.h:334` | `PROBE_INTERVAL_MS 1000U` fixed | No |
| Telemetry rate | `mesh_config.h:327` | `SAMPLING_INTERVAL_MS 100U` | No |
| Phase timeline | `mesh_config.h:129-138` | 60 s stabilise + 300 baseline + 180 attack + 120 cooldown = **11 min** | No |
| Attacker identity | `mesh_config.h:207` | `BLACKHOLE_ATTACKER_MAC` — **compile-time constant** | No |
| Payload size / burstiness | victim firmware | fixed-size periodic probe | No |

`run.ps1` (params at `run.ps1:66-119`) exposes `-Topology`, `-Attack`, `-WormholeEnd`, `-BlackholeRole`, `-Repeat` — **topology and role, but not a single attack-intensity or traffic parameter.** There is literally no way to make r2 differ from r1 today except by physically moving boards.

### P3 — r1→r3 redundancy: confirmed by the ledger

`tools/exports/run_ledger.csv` shows 16 cells recorded, e.g. `linear·blackhole·r1/r2/r3` all `done`. With every parameter above fixed, r1/r2/r3 differ **only in RF noise**. The panel's "waste of resources" judgement is factually correct.

Also: `BLACKHOLE_ATTACKER_MAC` being a compile-time constant means **attacker position cannot be varied per run without re-flashing every victim board**. This is the single biggest engineering blocker for P3.

### P4 — Single environment

Every capture in `tools/exports/` was taken in one location ("spread-out-room", per `STATUS.md:9`). Environment is not recorded as a column anywhere.

### P5 — No declared scenario

Nothing in the repo or `Paper/` declares an application context. The topologies (linear / star / tree / partial) are *graph shapes*, not *deployments*. The traffic model (uniform 1 Hz probe from every node) matches no real IoT profile in particular.

### P6 — Attack provenance not documented

`thesis-deviate.md` documents deviations from our own proposal (D-1…D-4), and `MEMORY.md:19` records the expected signatures — but there is no citation for *why* the blackhole and wormhole are implemented the way they are, and no reconciliation test proving the attack did what we claim.

### P7 — Benign class is thin

`tools/exports/baseline/` has **linear only, r1 only** — one benign run against 15 attack runs. Every benign window comes from the same conditions. There is no high-legitimate-load benign class at all, so "high traffic" and "attack" are perfectly confounded in the current data.

### Bookkeeping notes

- `STATUS.md` is **stale** — says "4 of 24 recorded"; the ledger says 16. Needs an overwrite regardless of this plan.
- Sample math (for the 10k target): 11-min run × 1 Hz analysis × 5 s windows × 6 boards ≈ **790 windows/run**. 16 runs ≈ 12.6k windows — that is the "10k dataset". A 4-min run yields ≈ 290 windows, so **~35 short runs** replace 16 long ones for the same sample count, with **twice the scenario coverage** and roughly the same bench hours. The panel's advice is arithmetically sound.

---

## 3. Proposed plan — 5 workstreams

Ordered so the cheap, evidence-producing work happens **before** any adviser-blocking design decisions or hardware time. §3 is *what to build*; **§4 is what each fix needs that isn't code** (decisions, documents, literature, sites, permissions) and **§5 is the source list for attack provenance.**

### Workstream A — Diagnostics on data we already have (no new captures)

Purpose: walk into the adviser meeting with numbers, not opinions. All of this runs on the existing 16 runs.

- **A1. Leakage audit.** Per-feature single-feature separability: univariate AUC / mutual information / one-level decision-stump accuracy for each of the 16 features against the attack label. Report every feature scoring ≥ 0.95. Expected finding: the 5 role-gated features score 1.00 by missingness alone, and PDR scores ~0.99.
- **A2. Missingness-as-label test.** Train a classifier on **NaN indicators only**. If it hits ~100%, P1 is proven quantitatively.
- **A3. Run-redundancy test.** Per-cell distance between r1/r2/r3 feature distributions (KS / Wasserstein per feature). Expected finding: within-cell variance ≈ measurement noise, confirming P3.
- **A4. Balance table.** Window counts per topology × attack × phase × node role. Answers the panel's "did you balance it?" directly.
- **A5. Confound check.** Show that a threshold on total traffic volume alone reproduces the attack label — the concrete form of P7.
- **A6. Definitional conformance tables** (P6). Fill in the two tables drafted in §5.1: canonical criteria vs. what our implementation actually does, including the criteria we fail. Needs the parent-switch data to settle whether the wormhole distorts topology or only duplicates arrivals. **No recapture, no hardware — probably the best value-per-hour item in the plan**, because it answers "is it really a blackhole/wormhole?" directly.
- **A7. Signature-shape comparison.** Put our PDR-collapse profile next to a published one (WSN-DS or an RPL routing-attack set) and compare *shape*, not absolute values. See §5C usage note 1.

**Output:** one `M9-LEAKAGE-AUDIT.md` + the conformance tables + plots. All of it is paper sections, not throwaway work.

### Workstream B — Design decisions (needs adviser sign-off before B is buildable)

- ~~**B1. Pick the deployment scenario**~~ ✅ **SETTLED aug. 06, 2026 — smart campus (environmental / building monitoring), sited at DLSU Manila.** Grounded in the paper's §1.1 / §1.5 / §1.4; reasoning in §6 Q1. Unblocks C3, C4, and D. Remaining B1 work: the topology → campus-location map, and the two scope amendments in Risks R-A / R-B.
- **B2. Literature basis for node deployment** (P3, P5). Find 2–3 papers on IoT/WSN target deployment + attacker placement strategy; derive our position map from them rather than inventing it. **Candidate sources: §5B.**
- **B3. Literature basis for the attacks** (P6). Cite the source for the blackhole model (selective vs. full drop) and the wormhole model (out-of-band tunnel). Write down the expected signature each source predicts **before** looking at our data, so the paper can show ours matches. **Candidate sources: §5A + §5B; comparison datasets: §5C.**
- **B4. Decide the fate of the existing 16 runs.** Recommendation: **keep them, relabel them as a fixed-parameter control block**, and cite them in the paper as the "no-variance" comparison that motivates the new design. Do not delete — they are tracked git evidence per `MEMORY.md:11`. **Adviser confirms.**
- **B5. Decide the ML framing.** If clustering is retained, decide up front how leakage-prone features are handled: dropped, or kept but reported separately. **Adviser decides.**

### Workstream C — Make variation possible (firmware + tooling)

Nothing here is speculative; each item removes one specific blocker found in §2.

- **C1. Runtime attacker selection.** Move `BLACKHOLE_ATTACKER_MAC` off `#define` — either broadcast the attacker MAC in the phase message from the root, or make it an NVS value settable per run. **Unblocks varying attacker position without re-flashing.** Highest-value change in this workstream.
- **C2. Parameterize the blackhole.** Add drop probability (e.g. 100 / 70 / 40 %) and duty cycle (continuous vs. periodic on/off) as build/run flags; seeded RNG per run so it is reproducible and reportable.
- **C3. Parameterize benign traffic.** Jittered probe interval (e.g. 1000 ms ± 30 %), variable payload size, and a burst mode — driven by whatever B1 says a realistic profile is.
- **C4. Add a high-load benign class** (P7). A benign run where honest traffic is deliberately heavy, so "high volume" stops being a proxy for "attack".
- **C5. Shorter phase timeline** (P7). Proposed: 30 s stabilise + 90 baseline + 90 attack + 30 cooldown = **4 min**. Needs a check that 90 s of attack still fills enough 5 s windows per node — A-workstream data can answer this before we commit.
- **C6. Extend `run.ps1` + `run_matrix.py`.** New flags for drop rate, duty cycle, attacker position, traffic profile, environment; ledger gains columns for all of them so every run is self-describing.
- **C7. Fix the relay-feature gate** (P1). Compute `ForwardingRatio` / `IngressEgressDelta` / `ConsistencyScore` for **every forwarding-capable node**, not just the attacker. In a mesh, every non-leaf node relays — there is no honest reason these are attacker-only. This alone kills the missingness leak.
- **C8. Attack validation harness** (P6). A reconciliation test: victim sent-count vs. attacker received/forwarded/dropped counters vs. root arrivals must balance. Any run that fails is rejected. Slots in next to `validate_integrity.py` / `verify_topology.py`.

### Workstream D — New capture campaign

Design the matrix **after** B1–B3 are settled. Sketch of the variation axes:

| Axis | Levels |
|---|---|
| Topology | linear, star, tree, partial (4) |
| Attack | none, blackhole, wormhole (3) |
| Attacker position | near-root / mid / edge (3) — **new** |
| Attack intensity | full / partial / intermittent (3) — **new** |
| Traffic profile | normal / high-legitimate-load (2) — **new** |
| Environment | DLSU campus locations, ≥2 with contrasting RF profiles (2+) — **new** |

Full crossing is far too large. The plan is a **fractional design**: hold most axes at a default, vary one or two per cell, so every axis is covered without 400 runs. Target ≈ 35–45 short runs. Exact matrix is a deliverable of this workstream, for adviser review before any board is flashed.

Constraint to respect throughout: `MEMORY.md:21` — the I-017 SPIFFS-overfill hazard. More, shorter runs means more export cycles; `board_check.py` discipline matters more, not less.

### Workstream E — Analysis + paper

- **E1.** Re-run M6→M7→M8 on the new dataset.
- **E2.** Re-run the A1–A5 audit on the new dataset and show the leakage scores dropped — this is the direct, quantitative answer to P1.
- **E3.** Paper sections: deployment scenario + citations (P5), attack provenance + validation (P6), variation design + balance table (P2/P3), environment comparison (P4), benign characterization incl. high-load (P7).
- **E4.** Update `thesis-deviate.md`, `FILEMAP.md`, `STATUS.md`, `MEMORY.md` as the changes land.

### Workstream 0 — Housekeeping (DONE — aug. 06, 2026)

All 4 defense scripts, all 3 `DEFENSE-PREP*.md` Q&A banks, and `TERMS-GLOSSARY.md` moved → `0_Resources/archive/`. Inbound links in `ATTACK-MECHANICS.md` and `OUTPUT-VERIFICATION.md` repointed; `FILEMAP.md` and `0_Resources/INDEX.md` updated.

⚠️ `TERMS-GLOSSARY.md` is the vocabulary for paper Tables 4.11/4.12 — likely still wanted during Thesis 3 writing. It is archived, not deleted; pull it back to root if it turns out to be live reference rather than defense-day material.

---

## 4. What each problem needs — the non-code requirements

§3 lists *what to build*. This section lists what has to exist **around** the code for each fix to actually count: decisions, documents, literature, physical resources, permissions, and procedures. Most of these cannot be bought with programming time, and several have lead times — which is why they belong in a plan rather than in a commit.

### P1 — Single-feature decidability

| Need | Why it's not a code problem |
|---|---|
| **A written pass/fail criterion** — e.g. "no single feature exceeds 0.95 AUC / 0.90 stump accuracy against the label" | Without a number you commit to beforehand, "we fixed the leakage" is an opinion. Agree the bar with the adviser, state it in the paper, then report against it. |
| **A feature-provenance table** — for each of the 16 features: which node roles it is defined for, and *why* | The current attacker-only gating has no stated justification anywhere. The panel's question is really "why does this column exist?" |
| **A protocol-level argument about what a relay is in ESP-WIFI-MESH** | Requires reading Espressif's mesh documentation and stating which nodes forward transit traffic. It decides whether computing ForwardingRatio for all non-leaf nodes is *correct* or just convenient. |
| **A decision on unsupervised vs supervised framing** | Changes what leakage even means. In clustering, one dominant feature means clusters form on that axis and the other 15 contribute nothing — which is exactly the panel's complaint. |
| **A leakage section in the paper** | Panels want to see the test was run, not just that the final number looks clean. Reporting the *before* number is what makes the *after* credible. |

### P2 — Attack parameter variation

| Need | Notes |
|---|---|
| **A defensible parameter space** | Drop rates and duty cycles must come from literature, not from taste. Selective-forwarding papers publish the rates they use — cite them rather than picking 70% because it sounds reasonable. |
| **A naming decision: is partial dropping still a "blackhole"?** | In the WSN literature, partial/probabilistic dropping is normally called **grayhole** or **selective forwarding**. If you add it you have arguably introduced a third attack class — decide whether to label and report it as one. This is a taxonomy decision with paper-wide consequences. |
| **A seed-recording discipline** | "Randomised" is only publishable if it is reproducible. Every run needs its seed recorded in the ledger. This is a bookkeeping habit, not a feature. |
| **Bench time + board budget** | More parameter levels = more runs. Needs an honest hours estimate before committing to a matrix. |

### P3 — Run variance / attacker position

| Need | Notes |
|---|---|
| **A node position map per topology** — drawn, measured, named | You need actual distances and a diagram per topology, with attacker positions marked (near-root / mid / edge). This is a tape measure and a drawing tool, not code. The diagrams go straight into the paper. |
| **Literature on attacker placement strategy** | The panel asked in so many words for "a paper that talks about target deployment". See §5B. |
| **A decision: is attacker position a variable or a controlled factor?** | If it's a variable, it needs levels and balance. If controlled, it needs one justified value. Deciding late means recapturing. |
| **A run-labelling scheme** | Every run's full parameter set must be recoverable from its ledger row. Today the filename encodes topology/attack/repeat only — that was fine when nothing else varied and will not survive six axes. |

### P4 — Multiple environments

| Need | Notes |
|---|---|
| **A second physical site** | Requirements are concrete: mains power for 6 boards + laptop, a surface, and permission to occupy it for several hours. Scout before committing. |
| **Permission / booking** | A campus room reservation, a building admin's OK, or a café's tolerance. This has **lead time** — start it early, it is the item most likely to slip. |
| **An RF-context record per run** | AP count, channel occupancy, number of people present, time of day. A phone Wi-Fi analyser app is enough. Without it, "different environment" is an unsupported claim. |
| **An ethics/safety statement** | You are running a deliberately misbehaving mesh in a public space. It runs on its own `MESH_ID` and does not touch anyone else's network — but say so explicitly in the paper, and have the adviser confirm whether any ethics clearance is required. Cheap to do now, awkward to retrofit. |
| **Environment as a recorded field** | Must become a ledger column and a dataset column, decided before capture, not inferred afterwards from timestamps. |
| **Weather/temperature notes if outdoor** | Relevant if the agriculture scenario is chosen — affects RF propagation and is a legitimate covariate. |

### P5 — Deployment scenario

| Need | Notes |
|---|---|
| ~~The scenario decision itself~~ | ✅ **SETTLED: smart campus (environmental / building monitoring), DLSU Manila.** Full reasoning and the paper citations behind it: §6 Q1. |
| **A topology → campus-location map** | Each of the four topologies must be assigned a real named campus space (corridor → linear, room/lobby → star, multi-floor → tree, atrium → partial mesh). Verify against the paper's **§4.2.2 Physical Deployment Topologies** so the siting matches what is already written. This map is what converts "node deployment appears random" into a justified design. |
| **2–3 papers describing a real deployment of that kind** | Node count, physical spacing, what each node transmits, how often, and the duty cycle. |
| **A written traffic-profile spec** | A table: message size, interval, burstiness, per node type — derived from those papers and cited. This becomes the specification the firmware implements, so it must exist first. |
| **An honest scale-down statement** | Six ESP32s on a table are not a 30-node farm. The paper must say what the testbed represents and why the reduction is acceptable. Panels forgive a scaled testbed; they do not forgive an unstated one. |
| **A site diagram per scenario** | Needed for the paper regardless. |

### P6 — Attack validation and provenance

| Need | Notes |
|---|---|
| **Primary-literature citations per attack** | The direct answer to "what is your basis". See §5B. |
| **A public knowledge-base anchor** | The direct answer to "do you have an online database". See §5A — CAPEC is the strongest, since its execution-flow format maps onto the conformance tables. It does not need to be ESP32-specific; see §5's opening on why. |
| **A definitional conformance table per attack** | ⭐ **The core deliverable for this problem.** Criteria from the canonical definition vs. what our implementation does, including the criteria we *don't* meet. Buildable today from existing data — see §5.1, which already drafts both tables. |
| **A written expected-signature statement, produced BEFORE looking at your data** | ✅ **You already have this and may not realise it.** The approved paper contains **§3.4.4 Expected Observable Inconsistencies**, with **Table 3.4 (Expected Observables Under Blackhole Behavior)** and **Table 3.5 (Under Wormhole Behavior)** — written at proposal time, *before* any capture. That is a genuine pre-registered prediction, and it is the strongest possible answer to "how do you know it's really a blackhole". **Do not rewrite these tables to match your results.** Quote them as-published, then show the measured data beside them. Where they disagree, say so — a documented miss is credible; a silently edited prediction is not. Also check §3.3.1.1 / §3.3.2.1 *Theoretical Characterization* for the citations B3 needs. |
| **A ground-truth reconciliation procedure** | Victim sent-counts, attacker received/forwarded/dropped counters, and root arrivals must balance within tolerance. Specify the procedure and the tolerance as a table in the paper; the script is the easy half. |
| **An independent observation channel** | ⚠️ Right now the attacker **counts its own drops** — the evidence that the attack happened comes from the thing performing it. That is circular and a panel can attack it directly. Breaking the circle needs a spare ESP32 in promiscuous/monitor mode, or a laptop with a monitor-mode-capable Wi-Fi adapter, observing from outside. This is a hardware acquisition item, so flag it early. |
| **A signature comparison against a published dataset** | The single strongest available answer to "how do you know it's really a blackhole". See §5C. |

### P7 — Benign characterization

| Need | Notes |
|---|---|
| **A literature-based definition of "normal"** | Normal must come from the scenario literature, not from our own baseline runs — otherwise "benign" is defined as "whatever we recorded when we weren't attacking", which is circular in the same way as P6. |
| **A scenario-grounded story for high legitimate load** | Not "send faster". Something real: every sensor alarming at once, a firmware push, an end-of-day bulk sync. The story is what makes the class defensible. |
| **Benign run parity** | Currently **1 benign run against 15 attack runs**. Needs a stated target ratio before capture. |
| **A ruling on cooldown-phase windows** | Are they benign, or a third "recovery" state? Today it is ambiguous, and counting them as benign quietly pads the benign class with post-attack data that does not look like true normal traffic. |
| **A stated class-balance target** | Answers the panel's "have you balanced the dataset?" directly, and must be set before capture to be achievable. |

---

## 5. Attack provenance — knowledge bases, literature, and comparison datasets

Direct answer to the 44:30–49:00 comment: *"Show how you validated the attacks... do you have documentation or an online database that details the steps of these attacks to verify their accuracy?"*

> ### The sources do NOT need to be ESP32-specific — and that is not a weakness
>
> **Blackhole and wormhole are defined by adversary *behaviour*, not by protocol.** Karlof & Wagner and Hu/Perrig/Johnson define them in terms of what the attacker does to traffic — attract-then-drop, and tunnel-to-fake-proximity — not in terms of AODV, RPL, or 802.11s. Nothing in either definition mentions a routing protocol at all.
>
> So a dataset built on **LEACH, AODV, or RPL is a legitimate comparison point.** You are matching a *behavioural signature*, not a protocol implementation. Say this explicitly to the panel — it converts "your sources aren't ESP32" from an objection into a demonstration that you understand the attack class rather than one vendor's stack.
>
> **What you validate, then, is conformance to a definition** — not resemblance to a product. That makes the question answerable, and §5.1 below is the instrument for answering it.

> ⚠️ **Everything below is a starting list, not a bibliography.** Verify each item on its official site — availability, exact attack classes, and licences change, and some names below need confirming before they reach a citation. Do not cite anything from this list without opening it first.

### 5.1 — Definitional conformance: the actual answer to "is it really a blackhole/wormhole?"

Build this as a table in the paper: **each criterion from the canonical definition, and whether our implementation meets it.** A criterion you *fail* and declare is far stronger than one you quietly omit — and this table is what turns "we called it a blackhole" into "it satisfies the published definition of one".

**First, a large point in your favour that is already in the approved paper:** it does not claim these attacks bare. It names them functionally — **§4.2.1.2 "Forwarding Suppression (Blackhole)"** and **§4.2.1.3 "Topology Distortion (Wormhole-Inspired)"**, carried consistently through Tables 4.6 and 4.7. That *"-Inspired"* is doing real work: the paper never claimed a textbook wormhole, it claimed topology distortion derived from one. **Lead with this.** The claim you have to defend is already the narrower, more defensible one. (⚠️ Verify the body text of §4.2.1.2/4.2.1.3 matches the naming — I confirmed the section titles and table names, not the prose.)

**Blackhole — criteria from Karlof & Wagner / Deng et al.:**

| Criterion | Ours |
|---|---|
| Adversary sits on the forwarding path | ✅ victims address the attacker, which relays to root |
| Receives the packets (not radio jamming) | ✅ |
| Drops instead of forwarding | ✅ `blackhole_victim.c` |
| Stays protocol-compliant at PHY/MAC — the node still looks alive | ✅ the property that makes it hard to detect, and the reason cross-layer data is interesting |
| **Attracts** traffic by falsely advertising a favourable route | ⚠️ **NO — ours is a *placed* relay, configured by MAC, not one that lures traffic.** This is the single most likely "is it really a blackhole?" question. Declare it. The honest framing: we reproduce the *forwarding-suppression* half of the attack and not the *route-advertisement* half — which is precisely why the paper calls it "Forwarding Suppression", and consistent with §3.3.1.2 *Adaptation to ESP-WIFI-MESH Context* |
| Observable: PDR collapse through the node while it remains reachable | ✅ 0.94 → 0.08 |

**Wormhole — criteria from Hu, Perrig & Johnson (packet leashes):**

| Criterion | Ours |
|---|---|
| Two colluding endpoints | ✅ Node A / Node B |
| An out-of-band channel faster than the normal path | ✅ the UART tunnel |
| Packets captured at one end, replayed at the other | ✅ |
| Creates a **false neighbour relationship / illusion of proximity** | ⚠️ **Partially.** We produce duplicate arrivals and distorted path evidence, but whether ESP-WIFI-MESH's parent selection actually re-forms around the fake link needs to be shown from parent-switch data, not assumed. This is the weakest link in the chain — and exactly why "-Inspired" is in the paper's own section title |
| Attacker need not compromise keys or hosts | ✅ |

**Everything above is answerable from data you already hold** — no recapture required. Writing this table is Workstream A work, and it is probably the highest value-per-hour item in this entire plan.

### 5A — Attack-definition knowledge bases (the "online database" the panel asked about)

These give you the **protocol-independent** statement of the attack — which, per the framing above, is exactly what you want.

| Source | What it gives you | Fit for this thesis |
|---|---|---|
| **MITRE CAPEC** (Common Attack Pattern Enumeration and Classification) | Attack *patterns* with **prerequisites, execution flow, and consequences** — the closest thing to "steps of the attack" in a public catalogue, and deliberately written protocol-agnostically | **Best fit of the MITRE family, and the most direct answer to the panel's "online database" question.** Its execution-flow structure maps straight onto the §5.1 conformance tables. Look under interception / redirection / routing-manipulation; Adversary-in-the-Middle is the natural generic parent for wormhole |
| **MITRE EMB3D** | Threat model built specifically for **embedded devices**, mapped to device properties | Strong fit for ESP32-class hardware; relatively new, so it also reads as current |
| **MITRE ATT&CK** (Enterprise + ICS) | Technique taxonomy with IDs you can cite | Partial fit — enterprise/ICS-oriented, with **no clean WSN-routing wormhole entry.** Useful for the manipulation/denial framing; say plainly where it does not map |
| **MITRE CWE** | Weakness taxonomy | Use for *why the protocol permits this*, not for the attack steps |
| **NIST NVD / CVE** | Real reported vulnerabilities | Search ESP32 / ESP-IDF / ESP-WIFI-MESH. Whether you find much or little, both are reportable |
| **Espressif ESP-WIFI-MESH docs + security advisories** | What the protocol actually guarantees | **Non-optional.** This bounds what your attack is allowed to claim — you cannot claim to subvert a guarantee the protocol never made |
| **IETF RFCs — RFC 3561 (AODV), RFC 6550 (RPL)** | The routing behaviour the classical attacks subvert | ESP-WIFI-MESH is neither. Cite as the *origin* of the definitions, then point at the paper's own **§3.3.1.2 / §3.3.2.2 "Adaptation to ESP-WIFI-MESH Context"** — those sections exist precisely to bridge this gap, and they are your prepared answer, not a hole |

### 5B — Canonical primary literature (the "basis" the panel asked for)

These are the citations the question is really fishing for. Verify author/year/venue before citing.

- **Karlof & Wagner (2003), "Secure Routing in Wireless Sensor Networks: Attacks and Countermeasures"** — defines sinkhole, wormhole, and selective forwarding for WSNs. Very likely the single most useful source for **both** of your attacks; start here.
- **Hu, Perrig & Johnson (2003), "Packet Leashes: A Defense against Wormhole Attacks in Wireless Networks"** (IEEE INFOCOM) — the canonical wormhole formulation.
- **Deng, Li & Agrawal (2002), "Routing security in wireless ad hoc networks"** (IEEE Communications Magazine) — blackhole in ad hoc routing.
- **Selective-forwarding / grayhole follow-ups to Karlof & Wagner** — needed if P2 introduces partial dropping, since they publish the drop rates you would be justifying.
- **Target-deployment / node-placement literature** — the explicit 12:45–16:00 ask. Search terms: *WSN node deployment strategy*, *IoT testbed topology design*, *attacker placement wireless sensor network*. Needed for P3 and P5 both.

### 5C — Public datasets to compare signatures against

**None of these is ESP32, and that is fine** — you are matching a behavioural signature across a protocol boundary, which is the whole argument of §5's opening. What matters is that the dataset contains a *labelled blackhole or wormhole*, so you have a published signature to hold yours against. Ordered by relevance. **Not for training on** — see the usage note below.

| Dataset | Why it matters here |
|---|---|
| **WSN-DS** (Almomani et al., 2016) | WSN dataset whose classes include **Blackhole and Grayhole**. Closest published analogue to your blackhole — the top candidate for signature comparison |
| **IRAD / IoT routing-attack datasets** (RPL-based) | Typically include **blackhole, sinkhole, and wormhole**. Verify the exact class list of whichever version you obtain |
| **RPL-NIDDS17** | RPL routing-attack dataset; another routing-layer comparison point |
| **TON_IoT** (UNSW Canberra) | Telemetry **plus** network data — structurally the closest to your cross-layer framing |
| **Bot-IoT** (UNSW Canberra) | Large, heavily cited IoT DoS/botnet dataset; good for related-work positioning |
| **IoT-23** (Stratosphere Lab, CTU Prague) | Real IoT malware captures; useful as a realism benchmark |
| **Edge-IIoTset** | IIoT, many attack classes, recent |
| **CICIoT2023** (Canadian Institute for Cybersecurity) | Large, recent IoT attack dataset |
| **AWID3** | **802.11-specific** — relevant because you are on Wi-Fi, not Zigbee/6LoWPAN like most WSN datasets |
| **N-BaIoT** | IoT botnet traffic; commonly cited baseline |

**How to actually use these — three jobs, none of them training:**

1. **Signature corroboration (P6) — the main job.** Does a published blackhole show the same *shape* of PDR collapse as yours: abrupt onset at attack start, near-total loss for traffic through the adversary, unaffected traffic on other paths, recovery at cooldown? Compare shapes and ratios, not absolute values — the protocols and radios differ, so identical numbers would be suspicious, not reassuring. A match is powerful evidence. A *mismatch* is equally valuable: it tells you something is wrong before the panel does.
2. **Feature-set justification (P1).** Which features do established IoT IDS datasets actually carry, and how do they handle role-specific columns? This gives your 16 features external support instead of self-assertion.
3. **Related-work gap table (P5).** A comparison table of these datasets by protocol, layer coverage, attack classes, and hardware. **None of them is cross-layer ESP-WIFI-MESH on real ESP32 hardware** — that table *is* your contribution statement, and it is the cheapest strong paper section available to you.
   → ✅ **This section already exists**: **§2.8 Existing Wireless Network Datasets** and **Table 2.8**. Extend that table with the datasets above rather than writing a new section — and add the columns that make the gap visible (protocol, hardware-vs-simulated, layers covered, routing-attack classes). Check what §2.8 already cites before adding; some of §5C may be in there.

---

## 6. Questions to bring to the adviser

### Settled by the group (aug. 06, 2026)

**Q1 — Scenario → SMART CAMPUS (environmental / building monitoring), sited at DLSU Manila.**

Derived from the approved paper, not invented. The paper's own framing points here three separate times:

- **§1.1** lists WMN applications as *"smart cities, environmental monitoring, disaster recovery, and rural connectivity"*, and ESP32 mesh specifically as *"smart homes, environmental sensing, and agricultural monitoring"*.
- **§1.5** aligns the work to **UN SDG 9** — *"resilient, low-cost communication infrastructure... in resource-constrained environments"*.
- **§1.4** fixes the testbed at **5–10 ESP32 nodes**, static, no mobility.

Against those constraints plus a DLSU Manila site, smart campus wins clearly:

| Candidate | Verdict |
|---|---|
| Smart **agriculture** | ❌ Not credible from a university corridor. Spacing, obstacles, and outdoor RF profile are all wrong; the scale-down would be a stretch a panel can attack. |
| Smart **home** | ❌ DLSU is not a home, and a home is small and RF-uniform — which contradicts the whole reason for choosing campus (variance). Also too close to the Thesis 2 setup you are being told to move beyond. |
| **Smart campus / building monitoring** | ✅ **Recommended.** |

Why it is the strongest answer:

1. **No scale-down lie needed.** Every other scenario forces the paper to say "6 nodes on a table *represent* a 30-node farm". A campus deployment measured on a campus **is the thing itself** — the most defensible position available, and it removes a whole class of panel questions.
2. **It makes the four topologies physical instead of abstract.** Corridor → linear chain. Single room / lobby → star. Multi-floor or wing-and-branch → tree. Open atrium → partial mesh. This directly answers the 9:10–12:00 comment that *"the node deployment appears random"* — the topologies stop being graph shapes and become named places. ⚠️ Check this mapping against the paper's **§4.2.2 Physical Deployment Topologies** before committing; the paper already describes each topology physically and the campus siting must match what is written there.
3. **The traffic model already fits.** Campus environmental monitoring = periodic telemetry (temperature, humidity, occupancy, air quality) at a constant low rate — which is what the firmware already does at 1 Hz. Minimal churn to justify the benign profile.
4. **It hands you the high-load benign class (P7) for free.** Class-change surges, a scheduled end-of-day sync, an event in an auditorium or gym — real campus phenomena that produce legitimately heavy traffic. That is the story P7 needs, and it is much harder to tell convincingly in a farm.
5. **It supplies the variance the group wants.** Congested 2.4 GHz from campus Wi-Fi, moving people, concrete and glass — and the paper **already has the theory section for it** in **§3.2.2 Environmental Effects on Topology Formation** (physical obstacles, multi-path and interference, chain formation), plus **Table 3.3 Expected RSSI Ranges by Node Position**. The environment work slots into existing theory rather than needing new.
6. **"Smart campus" is an established literature category**, so B2's node-deployment citations are findable.

**Q5 — Environments → DLSU Manila campus.** Chosen by the group for its RF and human variance. This is coherent with Q1: the site and the scenario are now the same thing, which is the point.
Still needed (see §4 P4): per-location permissions, an RF-context record per run, and — see Risk R-A below — an amendment to the paper's stated scope.

### Still open

2. **Existing 16 runs (B4):** keep as a fixed-parameter control block, or discard and start clean?
3. **Leaky features (B5):** drop the role-gated features, or fix them to be computed network-wide (C7 — my recommendation)?
4. **Scope realism:** is a ~40-run recapture campaign feasible in the THES3 timeline, or should the variation axes be cut down?
6. **Does the panel expect supervised results in THES3**, or is unsupervised clustering still the deliverable? Changes how hard we must push on P1.
7. **Independent observation (P6):** the attacker currently counts its own drops, which is circular evidence. Is a sniffer node / monitor-mode adapter worth acquiring, or is root-side accounting a sufficient answer?
8. **Taxonomy (P2) — now urgent, see Risk R-B:** the paper's scope *explicitly excludes* grayhole and selective forwarding. Adding partial drop rates would introduce exactly those. Amend the scope, or get run variance from position/timing/duty-cycle instead?
9. **Ethics (P4):** the paper already has **Appendix B — Research Ethics Forms**. Does moving to public campus spaces require an amendment to what was filed, or is the existing filing sufficient?
10. **Which campus locations**, and who books them? Needed before any capture. Each must map to a topology per Q1 point 2.

---

## 7. Risks

### ⚠️ R-A — The paper's scope says "controlled indoor environment". DLSU campus contradicts it.

**§1.4.1 Limitations** states: *"all experiments are conducted in a **controlled indoor environment** to ensure repeatability and consistent labeling... it may not capture environmental variability such as outdoor interference, mobility-induced topology changes, or weather-related signal effects."* The abstract repeats it.

Moving to campus public spaces **deliberately relaxes a limitation the approved paper committed to**. That is a *good* change — it is exactly what the 8:40–8:55 comment asked for — but it must be written up as an intentional scope amendment, not slipped in. Left unaddressed, a panelist reading §1.4.1 against your new results has an easy contradiction to point at.

**Action:** amend §1.4.1 and the abstract; log it in `thesis-deviate.md` as a new deviation (D-5) with the panel comment as its justification. Cheap now, awkward later.

### ⚠️ R-B — The paper's threat model explicitly excludes grayhole and selective forwarding.

**§1.4.1** states the threat model is *"strictly limited to two specific routing-layer behaviors: blackhole and wormhole. The dataset does not include other routing-layer threats (such as **grayhole, Sybil, or selective forwarding**)."*

The obvious fix for P2 — partial/probabilistic drop rates — **is** selective forwarding, under the name the paper already used to exclude it. This is a direct collision between a panel instruction and an approved scope statement.

Three ways out, for the adviser to pick (Q8):

1. **Amend the scope** to admit grayhole as a third class. Strongest dataset, most paper rewriting, and arguably what the panel wants anyway.
2. **Keep drops binary; get variance elsewhere** — attacker *position*, attack *start time*, on/off *duty cycle*, and traffic profile. Preserves the scope exactly, and still satisfies the 12:45–16:00 comment, which asked specifically for *"different position of the attackers"*, not different drop rates. **Lowest-risk reading of the panel's actual words.**
3. **Duty-cycled full drops** — 100% drop during ON intervals, forwarding during OFF. Debatable whether this is still "blackhole"; needs an explicit definitional paragraph if chosen.

Do not resolve this by quietly implementing option 1.

### Other risks

- **C1 (runtime attacker MAC) is the load-bearing change.** If it can't be made to work, attacker-position variation stays a manual re-flash per run and the campaign cost roughly triples.
- **Recapture invalidates existing figures.** `Paper/figures/` (fig4-16 … fig4-23) all regenerate. Budget time for it.
- **Shorter runs × more variation = more board handling**, which is exactly where the I-017 SPIFFS hazard and the "wrong run recorded" class of error live. Tooling (C6) must land before the campaign, not during.
- ~~B1 is a hard dependency~~ — resolved aug. 06, 2026 (smart campus / DLSU Manila). C3, C4 and D can now be specified.
- **Campus space is shared space.** Room bookings, exam periods, term breaks, and building hours will constrain when you can capture — and a corridor that is empty in the morning and packed at noon is a *variable*, not a nuisance. Record time-of-day and crowd level per run, or the environment axis becomes uncontrolled noise instead of a finding.

---

## 8. Suggested order

```
0. Housekeeping (defense scripts → archive)          — minutes
A. Diagnostics on existing data                      — no hardware, produces meeting evidence
   ↓
[ADVISER MEETING — decide B1…B5 using A's numbers]
   ↓
B. Literature + design write-up
C. Firmware/tooling changes (C1 and C7 first)
   ↓
D. New capture campaign
E. Analysis + paper
```

Workstream A is the only thing worth starting before the adviser meeting — and it is worth starting, because it converts every panel comment from "they said so" into a measured number.

# THESIS 3 — 4-Member Task Split

**Purpose:** turn [THESIS3-PANEL-PLAN.md](THESIS3-PANEL-PLAN.md) (7 problems, 5 workstreams) into four owned lanes that can run in parallel without collisions.
**Drafted:** aug. 19, 2026 — **DRAFT, for group + adviser review.**

> **Paths:** relative to the workstation root, except `analysis/`, `tools/`, `components/`, `root_node/`, `child_node/`, `run.ps1` — those are relative to `NIS16-ESP32-Environment-semi-final/`.
> **Names:** lanes are labelled M1–M4 by role. Swap in real names when the group assigns them.
> **Assumption:** the adviser meeting on the panel plan has **not** happened yet (per `STATUS.md`, aug. 06). Lane work is split into *startable now* vs *blocked on adviser*.
> **Over the 200-line cap on purpose** — §0 below is a plain-language version for members, kept in the same file so nobody has to be told which document to open.

---

## 0. Plain version — read this first

### What happened, in one paragraph

We presented Thesis 2. The panel's main message was: *your dataset is too easy.* Meaning — if a computer can tell "attack" from "normal" by looking at one number, then all our other work (the 16 features, the machine learning) is decoration. They also said our runs are all basically the same run repeated, we only tested in one room, we never said what real-world thing this is supposed to be, and we never proved our attacks are really the attacks we named them after. **None of this means the work was bad.** It means the dataset needs to be harder and better documented before we collect more. That's Thesis 3.

**Four of us, four jobs.** Each person owns one problem from start to finish: you find out how bad it is, you fix it, and you write that part of the paper. You'll be the one the panel asks about it, so it should be the part you personally worked on.

### Your job in one sentence each

**M1 — "Is our data cheating?"**
Right now some columns in our data are only filled in for the attacker board and left empty for everyone else. So you can tell which rows are attacks just by seeing *which cells are blank* — without reading a single actual measurement. It's like a quiz where the answer is written in the margin. Your job: measure exactly how bad this is (with real numbers), then fix it so the blanks stop giving the answer away.
**Start with:** run the existing data through a script that scores each of our 16 features on "how well does this one column alone predict attack vs normal?" Anything scoring near-perfect is a problem.
**Heads-up on the fix:** we checked the firmware, and those blanks can't simply be filled in. The mesh forwards packets *underneath* our code, so an ordinary board genuinely never sees the traffic it passes along — only the attacker does, and only because it's addressed directly. So the fix is a choice between three options (see §3), and one of them is simply "stop using those three columns as inputs." That's a real fix, not giving up.

**M2 — "Is our attack really a blackhole?"**
We wrote code that drops packets and called it a "blackhole attack." The panel asked: says who? Your job is to find the original research papers that define these attacks, list what those papers say a blackhole must do, and check our code line by line against that list — **including the parts where ours doesn't match.** Saying "ours doesn't do X, and here's why" is much stronger than hoping nobody notices.
**Start with:** the two conformance tables already drafted in the panel plan. You're verifying and filling them, not inventing them. Good news you may not know: our approved paper already predicted what the attacks would look like *before* we ran them — that's rare and it's our strongest evidence. Don't edit those predictions to match our results.

**M3 — "Where is this actually supposed to be?"**
The panel said our node placement looks random and we only tested in one room. We've decided the answer: this is a **smart campus** setup at DLSU. Your job is to make that real — assign each of our four layouts to an actual named campus space, get permission to work there, and find papers that back up why nodes go where they go.
**Start with:** the permission requests. Everything else can wait a week; booking rooms cannot. Also: our paper currently promises a "controlled indoor environment," which now contradicts our own plan — you're the one who fixes that wording.

**M4 — "Make every run different."**
Every run we've done is identical except for random radio noise, because everything is hardcoded. Worst of all, which board is the attacker is baked in at compile time, so moving the attacker means re-flashing every single board. Your job is to make these things changeable, and to make the spreadsheet record what each run actually used.
**Start with:** that attacker-MAC problem. It's the one thing everything else waits on. Good news: the storage system needed to fix it is already set up on the boards.

### Words you'll keep hearing

| Word | What it actually means |
|---|---|
| **PDR** | Packet Delivery Ratio — out of the messages sent, how many arrived. Normal ≈ 0.94, during blackhole ≈ 0.08. |
| **Topology** | The shape the boards are arranged in: a line, a star, a tree, a partial mesh. |
| **Baseline / benign** | A run with no attack. Normal traffic. Our "control group." |
| **Leakage** | The data accidentally contains a giveaway, so a model looks smart without learning anything. M1's whole job. |
| **Confounded** | Two things tangled so you can't tell which caused what. Ours: all attack runs are also the busy runs, so "busy" and "attack" look identical. |
| **Provenance** | Where something came from. "Attack provenance" = proof our attack code is based on real published research. |
| **Conformance** | Checking our version against the official definition, point by point. |
| **NaN** | An empty cell in the data. |
| **Window** | We chop recordings into 5-second chunks. Each chunk is one row of data. |
| **The ledger** | `run_ledger.csv` — the spreadsheet listing every run we've ever recorded. |
| **Grayhole** | Dropping *some* packets instead of all. Sounds like a small change; it's actually a different named attack, which is why we can't just add it. |

### The five rules

1. **Stay in your lane's files.** If you need to change someone else's file, ask them. This is how four people avoid overwriting each other.
2. **You write the paper section for the part you did.** Not because it's fair — because the panel will ask *you* about it.
3. **Delete nothing.** Our old runs are evidence, even the flawed ones.
4. **Bring numbers to the adviser meeting, not opinions.** "It's leaky" is an opinion. "This feature scores 1.00 alone" is a number.
5. **Say the bad number out loud first.** Every problem here is one we found ourselves and are fixing. That's a strong position. Hiding one and having the panel find it is not.

### If you only remember one thing

We are not redoing the thesis. We are making the dataset **harder to cheat on** and writing down **why every choice was made**. Most of what's below is just the detailed version of those two sentences.

---

## 1. The splitting principle

Each member owns **one panel problem cluster end-to-end** — audit it, fix it, write its paper section. Not "one person codes, one person writes": that concentrates the paper on one person and leaves three people unable to defend their own chapters.

Three consequences, all deliberate:

- **Every member can answer panel questions in their own lane.** The 44:30 comment ("show how you validated the attacks") has one owner who read the primary literature themselves.
- **File ownership prevents collisions.** Each lane's file list is exclusive; touching another lane's file means asking that member first.
- **Everyone starts today.** No lane is fully blocked on the adviser — every member has pre-meeting work that produces evidence *for* the meeting.

---

## 2. The four lanes

| Lane | Owns | Panel comments answered | Workstream items |
|---|---|---|---|
| **M1 — Data Integrity & Leakage** | Proving and killing the single-feature/leakage problem | **P1**, P7 (analysis half), the "is it balanced?" ask | A1–A5, C7 (joint w/ M4), E2 |
| **M2 — Attack Provenance & Validation** | Proving the attacks really are blackhole/wormhole | **P6**, P2 (taxonomy half) | A6, A7, B3, C8, §2.8 extension |
| **M3 — Scenario, Siting & Environment** | Making deployment non-arbitrary and multi-environment | **P3** (placement), **P4**, **P5** | B1 remainder, B2, the §4 non-code needs for P4/P5 |
| **M4 — Firmware, Tooling & Campaign** | Making variation physically possible, then capturing it | **P2**, **P3** (execution), P7 (capture half) | C1–C6, D |

---

## 3. M1 — Data Integrity & Leakage Lead

**The claim you must be able to defend:** *"No single feature decides our label, and here is the number that proves it — before and after."*

**Start now (no hardware, no adviser):**
- **A1 leakage audit** — univariate AUC + mutual information + one-level decision-stump accuracy for each of the 16 features vs. the attack label, on the existing 16 runs. Report every feature scoring ≥ 0.95.
- **A2 missingness-as-label test** — classifier on NaN indicators only. If it hits ~100%, P1 is proven quantitatively rather than argued.
- **A3 run-redundancy test** — KS / Wasserstein distance between r1/r2/r3 per cell. This is the number that settles B4.
- **A4 balance table** — windows per topology × attack × phase × node role.
- **A5 confound check** — show a threshold on total traffic volume alone reproduces the attack label. The concrete form of P7, and it hands M4 the spec for C4.

**Then (needs a decision):**
- **Pass/fail criterion** — propose the bar (e.g. "no single feature > 0.95 AUC"), get the adviser to agree it, and put it in the paper *before* the fix. Without a number committed beforehand, "we fixed the leakage" is an opinion.
- **C7 relay-feature fix** — ⚠️ **not the mask change it looks like, and now a joint M1 + M4 item.** Verified aug. 29, 2026: honest nodes send via `MESH_DATA_TODS` (`victim_main.c:164`), so the ESP-IDF mesh stack forwards transit traffic *below the application layer* and an honest relay never observes what it forwarded. Only the attacker sees transit packets, because blackhole victims address it explicitly (`victim_main.c:159`). **There is no honest-relay forwarding data to un-gate.** Three options — app-layer relay for every node (firmware, invalidates existing runs), infer forwarding from root arrivals + topology (Python, but a derived estimate), or keep the features attacker-only and exclude them from model input (cheapest, and arguably the real fix). Full detail and costs: [THESIS3-MEMBER-HOWTO.md](THESIS3-MEMBER-HOWTO.md) §1 C7. Adviser Q3 now decides between three concrete options rather than yes/no.
- **Feature-provenance table** — for each of the 16 features: which roles it is defined for, and *why*. The current gating has no stated justification anywhere, and the panel's real question is "why does this column exist?"

**Files you own:** `analysis/features.py`, `analysis/eda.py`, new `M9-LEAKAGE-AUDIT.md`, the paper's leakage section.
**Hand off:** A5 → M4 (shapes C4). A3 → the adviser meeting (settles Q2/B4). A4 → M2's balance claims.

---

## 4. M2 — Attack Provenance & Validation Lead

**The claim:** *"It satisfies the published definition of a blackhole — including the criteria it does not meet, which we declare."*

**Start now — the highest value-per-hour work in the plan, and it needs no recapture:**
- **A6 definitional conformance tables** — panel-plan §5.1 already drafts both. Fill them from existing data. The two rows that matter most are the ⚠️ ones: ours is a *placed* relay, not one that *attracts* traffic; and whether the wormhole actually re-forms parent selection must be shown from parent-switch data, not assumed. **Declare both — a criterion you fail and declare is stronger than one you quietly omit.**
- **Verify the paper's own defence:** confirm the body text of §4.2.1.2 "Forwarding Suppression (Blackhole)" and §4.2.1.3 "Topology Distortion (Wormhole-Inspired)" matches those section titles. The "-Inspired" wording is already the narrower, more defensible claim — lead with it.
- **Extract §3.4.4 + Tables 3.4/3.5** (Expected Observable Inconsistencies) from the approved paper. These are a genuine pre-registered prediction, written before any capture. ⚠️ **Do not edit them to match results.** Quote as-published, put the measured data beside them, and say where they disagree.
- **B3 source verification** — open every item in panel-plan §5A/§5B before it reaches a citation. Karlof & Wagner (2003) and Hu/Perrig/Johnson (2003) first; MITRE CAPEC is the direct answer to the panel's "online database" question.

**Then:**
- **A7 signature comparison** — our PDR-collapse *shape* against a published one (WSN-DS first choice). Shapes and ratios, not absolute values; identical numbers across different radios would be suspicious, not reassuring.
- **§2.8 / Table 2.8 extension** — add the §5C datasets with columns for protocol, hardware-vs-simulated, layers covered, routing-attack classes. The gap that table shows *is* the contribution statement. Check what §2.8 already cites first.
- **C8 validation harness** — reconciliation: victim sent-counts vs. attacker received/forwarded/dropped vs. root arrivals, balancing within a stated tolerance. Sits next to `validate_integrity.py` / `verify_topology.py`; any run that fails is rejected.
- **R-B taxonomy brief** — paper §1.4.1 *explicitly excludes* grayhole and selective forwarding, and partial drop rates ARE that. Write the one-page brief with the three options for adviser Q8. **Do not let M4 quietly implement option 1.**

**Files you own:** new `tools/validate_attack.py`, the conformance tables, paper §2.8 + the provenance/validation sections.
**Hand off:** R-B ruling → M4 (gates C2 entirely). ~~Espressif relay semantics → M1 (C7)~~ — answered from the firmware aug. 29, 2026; see M1's C7 entry.
**Flag in week 1:** independent observation (Q7) is a **hardware purchase**. The attacker currently counts its own drops, which is circular evidence a panel can attack directly. A sniffer ESP32 or monitor-mode adapter has lead time — raise it at the first meeting, not the last.

---

## 5. M3 — Scenario, Siting & Environment Lead

**The claim:** *"Node placement is not arbitrary — each topology is a named campus space chosen from deployment literature."*

**Start now:**
- **Topology → campus-location map.** Corridor → linear, room/lobby → star, multi-floor → tree, atrium → partial mesh. ⚠️ **Read paper §4.2.2 Physical Deployment Topologies first** — the siting must match what is already written there, not contradict it.
- **R-A scope amendment.** §1.4.1 and the abstract say *"controlled indoor environment"*; a DLSU campus site contradicts that. Amend both and log it as **D-5** in `thesis-deviate.md`, with the 8:40–8:55 panel comment as the justification. Cheap now, awkward later.
- **B2 deployment literature** — 2–3 papers on WSN/IoT node deployment *and* attacker placement. Search: *WSN node deployment strategy*, *IoT testbed topology design*, *attacker placement wireless sensor network*. This is the explicit 12:45–16:00 ask.
- **Site scouting + permissions.** Each site needs mains power for 6 boards plus a laptop, a surface, and permission to occupy it for hours. **Permissions have the longest lead time of anything in this plan** — start them in week 1 regardless of what else is settled.
- **Ethics check (Q9).** The paper has Appendix B — Research Ethics Forms. Does running a deliberately misbehaving mesh in public campus space require an amendment to what was filed? Ask at the first adviser meeting.

**Then:**
- **Traffic-profile spec** — message size, interval, burstiness per node type, derived from the smart-campus papers and cited. **This is the input to M4's C3**, so it must exist before that firmware is written.
- **High-load benign story (P7)** — a class-change surge, a scheduled end-of-day sync, an event in the gym. A real phenomenon, not "send faster"; the story is what makes the class defensible.
- **RF-context record protocol** — AP count, channel occupancy, people present, time of day, per run. A phone Wi-Fi analyser is enough. Without it, "different environment" is an unsupported claim.
- **Site diagrams with measured positions** per topology, attacker positions marked (near-root / mid / edge). Tape measure and a drawing tool. These go straight into the paper.

**Files you own:** `thesis-deviate.md` (D-5), paper §1.4.1 + abstract + §4.2.2 + the scenario/environment sections, site diagrams, the traffic-profile spec.
**Hand off:** traffic spec → M4 (C3/C4). Position map + attacker levels → M4 (D matrix). Environment field definition → M4 (ledger column, C6).

---

## 6. M4 — Firmware, Tooling & Campaign Lead

**The claim:** *"Every run differs from every other run in a recorded, reproducible way."*

**Start now — C1 is the load-bearing change in the entire plan:**
- **C1 runtime attacker selection.** `BLACKHOLE_ATTACKER_MAC` at `mesh_config.h:207` is a compile-time `#define`, so attacker position cannot vary without re-flashing every victim board. Move it to NVS, or broadcast it in the root's phase message. **If this can't be made to work, the campaign cost roughly triples** — find out in week 1, not week 6.
- **C6 tooling + ledger.** New `run.ps1` / `run_matrix.py` flags for drop rate, duty cycle, attacker position, traffic profile, environment; a ledger column for each. Plus a **run-labelling scheme** — filenames encode topology/attack/repeat only today, which will not survive six axes — and **seed recording**, since "randomised" is only publishable if it is reproducible.
- **C5 short-timeline check.** Proposed: 30 s stabilise + 90 baseline + 90 attack + 30 cooldown = 4 min. Ask M1 whether 90 s of attack still fills enough 5 s windows per node; A-workstream data answers this before you commit.

**Blocked — do not build until the ruling lands:**
- **C2 blackhole parameterization** — ⛔ **blocked on M2's R-B brief + adviser Q8.** Partial drop rates may be out of scope. Build duty-cycle, position, and start-time variation first: those satisfy the panel's actual words ("different position of the attackers") without touching the scope statement.
- **C3 benign traffic parameters** — needs M3's traffic-profile spec.
- **C4 high-load benign class** — needs M3's story plus M1's A5 confound number.
- **D capture matrix** — fractional design, ~35–45 short runs, for adviser review **before any board is flashed.** Needs M3's position map and the B-workstream decisions.

**Files you own:** `components/mesh_common/`, `root_node/`, `child_node/`, `run.ps1`, `run_matrix.py`, `tools/exports/run_ledger.csv`, the D matrix document.
**Guardrails you are accountable for:** ⚠️ never run `idf.py set-target`. Never wipe a board before its captures are exported and verified. Editing `mesh_common` means rebuilding **both** node types. More short runs means more export cycles, so the I-017 SPIFFS-overfill hazard matters *more*, not less — `board_check.py` discipline is part of this lane.

---

## 7. Dependency map — read before scheduling

```
M2 R-B brief ──────────⛔──> M4 C2 (blackhole parameters)
M3 traffic spec ───────⛔──> M4 C3, C4
M3 position map ───────⛔──> M4 D matrix
M1 A5 confound ────────────> M4 C4 (shapes the high-load class)
M1 A3 redundancy ──────────> adviser Q2 (fate of the existing 16 runs)
C7 ── now JOINT M1+M4 ────⛔──> adviser Q3, which is now a 3-way choice (see M1's C7)
M1 window-count check ─────> M4 C5 (is a 90 s attack phase enough?)
C1 (M4) ── no blockers ── START IT FIRST
```

**Reading of the graph:** M1 and M2 are unblocked and produce the evidence the adviser meeting needs. M3 is unblocked but carries the longest external lead times (permissions, ethics). M4 is the most blocked — which is exactly why C1 and C6, its two unblocked items, should be underway now.

---

## 8. Milestone 1 — before the adviser meeting

Everyone brings a number or a document. Nobody brings an opinion.

| Member | Brings |
|---|---|
| **M1** | A1–A5 results in a draft `M9-LEAKAGE-AUDIT.md` — leakage scores, balance table, redundancy distances |
| **M2** | Both conformance tables filled, §3.4.4 pre-registered predictions extracted, the R-B taxonomy brief with three options |
| **M3** | Topology → campus-location map checked against §4.2.2, the D-5 amendment drafted, permission requests already *sent* |
| **M4** | The C1 verdict — is runtime attacker selection feasible, and at what cost? — plus the draft ledger schema |

**Agenda = panel-plan §6 "Still open".** Each question has an owner: **Q2, Q3 → M1**; **Q6, Q7, Q8 → M2**; **Q9, Q10 → M3**; **Q4 → M4**.

---

## 9. Group rules

- **One lane, one owner, one file list.** Editing outside your list means asking that owner first. This is what keeps four people out of the same `run.ps1`.
- **Everyone writes their own paper sections.** Whoever ran the audit writes the leakage section. This is a defense-readiness rule, not a fairness rule — you will be questioned individually.
- **Nothing is deleted.** The existing 16 runs are tracked git evidence (`MEMORY.md:11`). B4 recommends relabelling them as a fixed-parameter control block, not discarding them.
- **A ledger row per run, always.** A run whose full parameter set isn't recoverable from its ledger row is an unusable run.
- **Every dependency in §7 is a conversation, not a file drop.** Tell the blocked member the ruling directly.
- **Departures from the proposal go in `thesis-deviate.md`** with the panel comment that justified them — that file is what the panel gets shown when they ask why something changed.

---

## 10. What this split does *not* cover

- **E1** (re-run M6→M7→M8 on the new dataset) and **E3/E4** (final paper assembly, doc sync) are post-campaign and shared — assign them once the D matrix is actually running.
- **Timeline feasibility (Q4)** is deliberately unassigned: whether ~40 runs fit the THES3 calendar is a group + adviser call, and an honest hours estimate needs M4's C1 verdict first.
- **Who runs point with the adviser** — pick one person and keep it consistent, so the adviser gets one thread instead of four.

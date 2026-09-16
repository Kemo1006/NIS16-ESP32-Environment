# NIS16 — Defence Presentation Script (spoken, slide-by-slide)

Read-aloud script matched **one block per slide** to `slides/NIS16-defence-slides.html`. Written to be *spoken*, not read silently — short sentences, one idea at a time. Target ~11–12 min for the 16 content slides, leaving room for questions. Companion to [DEFENSE-PREP-FULL.md](DEFENSE-PREP-FULL.md) (the question bank) and [ATTACK-MECHANICS.md](../../Resources/reference/ATTACK-MECHANICS.md).

**Delivery rules:** lead with the point, then the number. Pause after every bold line. Never say "removed/deleted" about the blackhole gap — say **absent / empty**. If you blank, fall back to the slide's banner sentence.

---

## Slide 1 — Title  *(~30 s)*
> "Good morning. Our project is **a labelled dataset of wireless mesh telemetry under blackhole and wormhole attacks.**
> The one line to hold onto for the whole talk: we built **six ESP32 nodes in a routerless mesh, ran two attacks under controlled conditions, and labelled every row at the moment it was captured.**
> I'll walk through what we deliver, how the testbed works, and the evidence for each milestone."

*Transition:* "Let me start with what this project actually contributes."

---

## Slide 2 — Contribution *(~50 s)*
> "The single most important framing: **this is a dataset, not a detector.**
> We capture real mesh telemetry while two attacks run, and we publish it **labelled, validated, and documented**, so that detection research has real hardware data to build on — which is exactly what the literature is missing.
> On the left is **what we claim**: the data is real and cross-verified, the labels are produced by the experiment itself, every capture passes integrity validation, and our limitations are documented, not hidden.
> On the right, just as important, **what we do not claim**: no detection accuracy, no thresholds, no rules. Our analysis is **strictly descriptive** — building a classifier is the next phase, and we're deliberate about not overstating that."

*Transition:* "Here's the hardware that produces it."

---

## Slide 3 — Testbed *(~50 s)*
> "**Six ESP32 nodes, no router.** Node 1 is the root — it controls the experiment and broadcasts the phase. The other five are victims, and two of them are joined by a physical UART wire — that wire is the wormhole tunnel.
> Every node samples telemetry at **10 Hz straight to its own internal flash.** Nothing streams live during the run — we pull the CSVs off over USB afterwards. That matters, because an attack that drops mesh traffic **can't touch data that never travels over the mesh.**
> On the right is the scale so far: **65 raw capture files, about half a million telemetry rows, and just over seven thousand feature windows.** This is real captured data, not simulation."

*Transition:* "The heart of the method is how we label it."

---

## Slide 4 — Labels (the key idea) *(~55 s)*
> "This is the idea I most want the panel to take away. **Labels are produced by the experiment, not annotated afterwards.**
> Every run has a fixed timeline: **300 seconds of baseline, 180 seconds of attack, then 120 seconds of cooldown.** The root broadcasts the current phase ID over the mesh, and **every node stamps that ID into every row it writes.**
> Why this matters for a dataset: **the ground truth can't drift from the data, because the same firmware wrote both, in the same row, at the same instant.** There's no manual labelling step that could be wrong.
> And each run carries **its own benign reference** — 420 seconds of labelled-normal traffic around the attack — so every attack is compared against its own baseline."

*Transition:* "That's the method. Now the milestones — starting with the firmware."

---

## Slide 5 — M1 · Firmware *(~45 s)*
> "**Milestone 1, firmware — complete. All node roles are implemented:** the mesh setup and topology shaping, the phase broadcast, the logger, and the three child roles — plain victim, blackhole, and wormhole.
> One point the panel usually asks about: **topology is a compile-time constraint, not something we impose by hand.** For star, we cap the mesh depth at two layers — so a board **physically cannot** become a grandchild; the mesh stack refuses the association. The log line proves the shape was applied before any data was collected."

*Transition:* "With the firmware in place, here's the first attack."

---

## Slide 6 — M2 · Blackhole *(~60 s)*
> "The blackhole, measured on **two completely independent boards.**
> The banner is the whole story: **720 probes received, 720 dropped, zero forwarded — and the root logged zero arrivals during that window.**
> Read the table across the attack row: the attacker keeps **receiving** — the count climbs past 2,100 — but **forwarding goes completely flat**, and **dropped climbs by exactly 720.** Meanwhile the root's arrivals column for that window is **zero.**
> And the key point — that's **two independent sources agreeing.** Source A is the attacker's own telemetry — it counted what it dropped. Source B is a **different board, a different file** — the root — recording nothing arriving. One could be a glitch; both agreeing is the attack.
> If you ask about the empty attack window: those rows aren't *removed*, they're **empty — because nothing reached the root to log.** That absence *is* the blackhole signature."

*Transition:* "The wormhole is the mirror image of this."

---

## Slide 7 — M2 · Wormhole *(~55 s)*
> "Where the blackhole makes traffic **disappear**, the wormhole makes it **double.**
> Two colluding nodes share an out-of-band UART wire. During the attack, each probe is sent **twice** — once normally over the mesh, once replayed down the tunnel — so the root logs the **same probe twice.**
> The detection is **exact, not statistical**: the root sees the identical **source-MAC and sequence-number pair** arrive twice. In the table, that's **181 duplicates on linear, 180 on star**, always at exactly ×2, always from the one tunnelled node — and **zero duplicates in baseline.**
> And here's a finding in itself: because the tunnel is a **physical wire**, the signature **doesn't depend on mesh distance** — it reproduces the same way across different topologies."

*Transition:* "We don't just assume the topology — we verify it from the data."

---

## Slide 8 — M3 · Topologies *(~45 s)*
> "**Milestone 3 — topology verified from the data, not assumed.**
> The table on the left is our coverage: tree, linear, and star are captured and verified; **partial mesh is the one still pending.**
> On the right is how we prove the shape: `verify_topology.py` **rebuilds the tree from each node's own parent-MAC and layer columns** — an independent check on the physical wiring. For this star run it confirms all five nodes sit at layer 2, the mesh **converged within 60 seconds**, and the baseline had **no re-routing.** So the topology label is earned from the data, not declared by us."

*Transition:* "Here's where the whole experiment matrix stands today."

---

## Slide 9 — M4 · Execution matrix *(~50 s)*  📌 *update numbers morning-of*
> "**Milestone 4 — the execution matrix.** I want to be completely honest about status.
> We have **8 of 24 runs recorded**, and — the number I'd emphasise — **zero failures across every recorded cell.** Two cells are **fully replicated at three repeats each.**
> The important framing: **what remains is runtime, not unknowns.** The method, the tooling, and the analysis pipeline are complete and already exercised end-to-end. Finishing the matrix is a matter of **running more captures**, not solving anything open."

*(If asked why not more:)* "Each run is an ~8-to-11-minute controlled experiment plus extraction and validation, and we don't tick a cell until its files pass every integrity check — so the count is conservative on purpose."

*Transition:* "And nothing reaches the dataset without passing that validation."

---

## Slide 10 — M5 · Integrity *(~45 s)*
> "**Milestone 5 — nothing enters the dataset unvalidated.**
> Every capture flows through the same pipeline: export off the board, trim into clean sessions, then **five integrity checks plus a SHA-256 manifest.**
> The five checks are schema width, phase coverage, timestamp monotonicity, label integrity against the phase map, and a **locked SHA-256 hash per file.**
> The result shown here: **21 files, 21 pass, zero warnings, zero failures.** And the point that makes it trustworthy — **a matrix cell is marked done only if its files pass. The ledger cannot be ticked by hand.**"

*Transition:* "From validated captures, we build the features."

---

## Slide 11 — M6 + M7 · Preprocessing & Features *(~50 s)*
> "**Milestones 6 and 7 — preprocessing and feature engineering.**
> We re-base each node's clock, convert cumulative counters to per-window deltas, cut into **5-second windows**, and take the modal label per window.
> Quality is high: we **discard well under 1% of windows**, and dropped **zero rows to corruption.**
> That produces **16 engineered features.** One thing to pre-empt: some features are **blank for some runs — and that's correct, not missing.** A forwarding ratio only exists on a blackhole relay; tunnel features only exist on the two wormhole ends. That's specified in the thesis. **Across the run types, all 16 features are populated.**"

*Transition:* "Then the exploratory analysis on top of those features."

---

## Slide 12 — M8 · EDA *(~45 s)*  📌 *update numbers after new runs*
> "**Milestone 8 — exploratory data analysis.** Five analyses, exactly as the thesis specifies: descriptive statistics, distributions, time-series trajectories, correlation, and PCA plus t-SNE projections.
> The table shows the datasets analysed so far, split into benign and attack windows.
> And I'll say the boundary out loud, because we hold it firmly: **the EDA is strictly descriptive. No inferential claims, no detection rules** are derived at this stage — and none are. Showing structure is the goal; classifying is the next phase."

*Transition:* "One analysis choice is worth explaining on its own."

---

## Slide 13 — Two projections *(~50 s)*
> "We deliberately show **two projections, not one**, because they answer **different** questions honestly.
> The **whole-mesh** projection asks: *can the attack be seen in what every node measures?* There we **exclude** the tunnel features, because they only exist on 2 of 6 nodes — that's the realistic detection question.
> The **tunnel-end** projection asks a narrower question: *does the tunnel evidence itself separate the attack?* There we keep the tunnel features but restrict to the two tunnel nodes.
> Why both: **showing only the first would look like there's no evidence; showing only the second would overstate how easy detection is.** Neither replaces the other — that's an honesty choice, not a hedge."

*Transition:* "Building this on real hardware also taught us about failure."

---

## Slide 14 — Data quality / engineering *(~50 s)*
> "Three silent corruptions we hit during collection — each now **caught at the source.**
> A device once streamed the **wrong file**; stale derived files were **left after a re-export**; and a node's capture was **duplicated and double-counted.**
> The one I'd single out is the **third — it produced no error at all.** One node was counted twice — 264 windows against about 155 for everyone else — and **every total still looked plausible.** That's the failure mode that matters most for a dataset, because **nothing announces it.**
> So each guard now fires **at the instant the fault happens**, not twenty minutes later in analysis — and each is documented with the real incident that produced it."

*Transition:* "And we state our limitations before anyone has to ask."

---

## Slide 15 — Limitations *(~50 s)*
> "Five limitations, stated up front.
> **One:** the matrix is at 8 of 24 — again, remaining work is runtime, not method.
> **Two and three:** repeats share a topology *class* rather than a fixed parent assignment, and each run's baseline is its own phase 0 — both are logged as formal deviations.
> **Five:** one tunnel-latency feature is keyed differently from the original table — a documented deviation carried to the next phase.
> **And four, which I'll flag as genuinely unresolved:** on one star run the mesh took about 100 seconds to stabilise, where another converged inside 60 — and we **have not established the cause.** The clean test is a baseline-star run we haven't done yet. I'd rather name that openly than paper over it. All five are written up with their reasoning and their cost."

*Transition:* "Which leads directly into what comes next."

---

## Slide 16 — Next steps *(~45 s)*
> "Four things after this milestone: **finish the remaining runs**, which unblocks the separability analysis; **run baseline-star**, which settles that convergence question; then the **cross-topology separability** study once the matrix is full.
> The fourth — adding a round-trip timing leg — I want to be explicit about: **it's a deliberate deferral, not an oversight.** It would resolve two of our deviations, but it **changes the firmware**, and every run we've captured so far would stop being comparable. So we scheduled it for the next phase rather than breaking comparability mid-collection."

*Transition:* "And that's the milestone."

---

## Slide 17 — Close *(~25 s)*
> "To close on the three numbers that carry the work: **8 of 24 runs recorded with zero failures; the blackhole at 720 received, 720 dropped, zero forwarded; and the wormhole duplicates reproduced at 181, 181, 180.**
> A real, labelled, validated ESP32 mesh dataset — with our limitations on the table. **Thank you — we'd be glad to take your questions.**"

---

## Before you present — reconcile these numbers
The slides carry three `📌 UPDATE ME` markers (slides 8/9/12) and one internal mismatch to settle so you never contradict your own deck:
- **Slide 8 (M3)** shows tree/star **blackhole ✔**, but **Slide 9 (M4)** shows star-blackhole and tree **0/3**. Decide which is true and make both slides agree before defence.
- Re-run `python tools\run_matrix.py --status` the morning of and correct the **8/24** and the EDA window counts.
- Your [DEFENSE-PREP-FULL.md](DEFENSE-PREP-FULL.md) still says "4 of 24" and "2 of 4 topologies" — bring it in line with whatever the deck states so your spoken answers match your slides.

# Why a blackhole run can still be CONFIRMED when boards changed position

> **Panel question this answers:** "ESP-WIFI-MESH re-parents by itself. Some of your boards
> changed parent during the attack. Why do you still count some of those runs, and how do we know
> you didn't just pick the rule that saves your data?"
>
> **Code:** `tools/attack_checks.py` (`exposure_timeline`, `topology_issues`, `unresolved_windows`,
> `reroute_onset`) and `tools/verify_attack.py` (`_robustness_issue`, the exclusion step).
> **Paper tracking:** deviation **D-23** (rule) + **D-24** (START lock); checklist **A26** (🟨 adviser),
> **A27**, **A28**, **C13**; verification **#45, #46, #47**. Written oct. 18, 2026; rewritten in plain
> language with checked references on oct. 19, 2026.

---

## 1. In plain words (read this first)

A blackhole attacker **drops every packet that passes through it**. So the only thing that makes a
board a **victim** is that its traffic has to pass through the attacker on the way to the root.

ESP-WIFI-MESH is a **self-healing** network: if a board breaks down, the boards that were hanging
under it look for a new parent **by themselves**. Espressif's own documentation says so (§7).
That means a board can change parent in the middle of the attack, and that is **normal protocol
behaviour**, not a mistake in our setup.

So the question we ask is **not** *"did any board change parent?"* It is:

> **"Did the move change WHO the attack reaches?"**

- If a victim moves but is **still behind the attacker**, the attack still hits the same boards.
  The experiment did not change. → **allowed** (and written in the report as *TOLERATED*).
- If a victim moves to a place **not behind the attacker** (or the other way round), half of its
  attack is a different experiment. → **not allowed** (*SETUP INVALID*).
- While a board has **no working path at all** (its parent died, it is searching for a new one),
  that time is neither proof of the attack nor proof against it. → those seconds are **left out**
  of the test, not counted.

**An everyday picture.** A road is blocked (the attacker). Cars that must use that road never
arrive (victims). If a car's normal street closes and it takes a detour **that still uses the
blocked road**, it still doesn't arrive, and it is still a fair example of "the blocked road
stops cars". If its detour **avoids** the blocked road, it is no longer an example and we
cannot use it. While the car is parked and looking at the map, it tells us nothing either way,
so we don't count those minutes.

## 2. How the checker decides, step by step

For **every board**, in **every 1-second window** of the attack, the checker does this:

1. **Read the board's parent** at that second (from its own telemetry: `parent_mac`).
2. **Follow the chain upward**: the parent's parent, and so on, until it reaches either the
   attacker or the root.
3. **Give the board a label for that second:**

   | Label | Meaning |
   |---|---|
   | **VICTIM** | the chain passes through the attacker |
   | **BYSTANDER** | the chain reaches the root without passing the attacker |
   | **DETACHED** | the board has no parent right now (searching) |
   | **UNKNOWN** | the chain breaks: a board above it has gone silent (crashed / reset) |

4. **Look at each board's labels over the whole attack** and apply the rules in §3.
5. **Remove DETACHED and UNKNOWN seconds** from the 3-sigma test.
6. **Run the 3-sigma test** on what is left.
7. **Robustness re-test:** run the 3-sigma test again on **only** the part of the attack *before*
   the first move. The attack must be confirmed there too (if there are ≥ 60 s of it).

The checker **never looks at the delivery numbers (PDR) to decide** steps 1–5. It decides from
the layout only, then measures.

## 3. The rules

| # | Rule | Limit | If broken |
|---|---|---|---|
| R1 | A board must stay in **one label** (VICTIM or BYSTANDER) for the whole attack. This also covers a board that did not move itself but was **carried** by a parent that moved | fewer than **3** seconds in the other label | **FAIL**: "moved between VICTIM and BYSTANDER" |
| R2 | **No-path seconds** (DETACHED / UNKNOWN) are left out of the test | up to **10 %** of the attack = "brief re-join"; more = "long outage". Both are reported | not a FAIL. The seconds are removed, which can only make the test **harder** (see §4 rule 6) |
| R3 | ~~The **attacker itself** must never move~~ **Changed oct. 20, 2026 (D-31):** the attacker changing its OWN parent is judged by what it changes - tolerated only when no board changed victim / bystander class and the attacker was without an uplink for <= 10 % of its attack; seconds with no working path through the attacker are excluded from the test | 10 % (same budget as R2) | **FAIL** if a board flipped, no victim stayed behind it, or its outage > 10 %; else TOLERATED (footnote) |
| R4 | **Robustness:** the attack must also be confirmed on the seconds **before** the first move | needs ≥ **60 s** before the move | **FAIL** "NOT ROBUST". If under 60 s: a WARNING saying the verdict rests on the layout rule alone |
| R5 | *(Wormhole only)* the A end must stay **closer to the root** than the B end | fewer than 3 seconds otherwise | **FAIL**: "the shortcut changed" |
| R6 | **Phase comparison:** a board's label at the end of the baseline and the start of the cooldown is compared with the attack | — | WARNING only (footnote: its per-board features changed for a non-attack reason) |
| R7 | A **victim drops out** completely (e.g. it crashed) | other victims still present | WARNING. Losing the **attacker**, or **every** victim = **FAIL** |

A tolerated move is **always printed** in the report as a WARNING ("TOLERATED..."). It is footnoted,
never hidden.

### More situations (added oct. 19, 2026) - each can only ADD a warning or a failure

| # | Situation | Limit | Decision |
|---|---|---|---|
| S1 | **Flapping link:** a key board's parent changed many times in one attack | ≥ 4 changes | WARNING "FLAPPED" (allowed only if it never left its role - R1 still applies) |
| S2 | **A victim has no windows for the end of the attack** (crashed / reset / power, or too few samples) | ≥ 10 s before the end | WARNING: its attack is shorter; the other boards carry the rest |
| S3 | **The attacker has no windows for the end of the attack** | ≥ 10 s before the end | WARNING only: the table cannot tell "went silent" from "windows dropped for too few samples" (1C38 on oct. 18 had data to +178 s but windows only to +117 s) - never a failure on that alone |
| S4 | **A board's role changed during the BASELINE** | ≥ 3 s in each role | WARNING (no attack ran then; footnote its per-board features) |
| S5 | **A board appears only in the attack**, not in the baseline | - | WARNING: no normal-phase reference of its own |
| S6 | **Too little victim evidence left** after leaving out no-path seconds | < 60 traceable victim-seconds | **FAIL** |
| S7 | **A large share of the victims' time had no path** | > 25 % | WARNING: the verdict rests on what is left |

## The final verdict: CONFIDENCE grade (added oct. 19, 2026)

Under the VERDICT line (which is unchanged) the report now prints a **CONFIDENCE** grade, worked out
from the checks above by fixed rules:

| Grade | When | Campaign / Verify status | How to report it |
|---|---|---|---|
| **STRONG** | confirmed; all board data present, nothing to note | 🟢 DONE | "BLACKHOLE CONFIRMED" |
| **GOOD** | confirmed; all board data present, notes for the report (e.g. allowed moves, no run log) | 🟢 DONE | "BLACKHOLE CONFIRMED" + N footnotes |
| **MINOR GAPS** | confirmed; some data is missing (a board cut short / short attack / no cooldown) but the **impact check** - the 3-sigma test re-run WITHOUT those boards - still confirms the attack | 🟡 DONE - RECAPTURE ADVISED | "BLACKHOLE CONFIRMED - minor gaps" + footnotes |
| **MAJOR GAPS** | confirmed, but the result relies on missing data: a board never measured in the attack, most victim time with no path, or a FAILED impact check | 🟠 RECAPTURE REQUIRED | "BLACKHOLE CONFIRMED - major gaps" |
| **NOT CONFIRMED** | no signature, too little data, or the setup was invalid | 🔴 REDO | the failed check(s) are the reason |

**Update (verification #53):** gaps INSIDE a phase now count too (each board needs windows for >= 95 % of every phase - the project's coverage floor), the impact check may set aside at most half the boards, and benign runs are verified. Every threshold, its basis and the sensitivity results: [GRADING-AND-THRESHOLDS.md](GRADING-AND-THRESHOLDS.md).

Applied to all 52 analysed attack runs (oct. 19, verification #52): **7 STRONG, 40 GOOD, 1 MINOR GAPS, 2 MAJOR GAPS,
2 NOT CONFIRMED**. No fixed time cut decides minor vs major - the impact check does (an earlier "< 60 s = major" rule
overrode it on tree/G402/stationary and was removed; re-grading with any cut from 30 to 120 s moves no grade).
Any warning lands somewhere (#50), so STRONG means every check passed.

Example (10:11 PM run):

```
 VERDICT: BLACKHOLE CONFIRMED  (2/2 primary signature(s) beyond 3-sigma)
 CONFIDENCE: QUALIFIED - confirmed - report it WITH these 4 footnote(s)
     + signature: 2/2 primary signature(s) beyond 3-sigma
     + setup: no check failed
     ~ a board moved but stayed in the same role (allowed) (ED80)
     ~ a board has no windows for the end of the attack (1C38)
     ~ a board has no windows for the end of the attack (B768)
     ~ the re-test on the part before the first move was not possible
     = REPORT AS: "BLACKHOLE CONFIRMED (qualified: 4 footnote(s))"
```

## 4. Why this is not cheating

| # | Safeguard | What it prevents | Backed by |
|---|---|---|---|
| 1 | **Blind to the result.** Allow/reject is decided from the layout only; PDR is printed with "*shown, not used to decide*". A test forces every attack PDR to 1.0 and checks the decision does not change (`test_decision_ignores_delivery`) | accepting a run *because* the attack looked successful (circular) | MacCoun & Perlmutter 2015 |
| 2 | **Limits fixed in advance**, as constants in the code with their reasons; the same for every run, never tuned to one capture | moving the goalposts after seeing the data | Simmons et al. 2011; Nosek et al. 2018 |
| 3 | **Symmetric:** victim → bystander and bystander → victim both fail | a rule that only ever helps | — |
| 4 | **The attacker may never move** | changing the experiment itself | — |
| 5 | **The result can only make it stricter.** The robustness re-test (R4) can turn CONFIRMED into INVALID, never the reverse | using the outcome to rescue a run | Nosek et al. 2018 (robustness of a planned analysis) |
| 6 | **Removing no-path seconds only makes it harder.** Those seconds show PDR 0 (no path = nothing arrives), which would make the attack look *stronger*. They are dropped, not counted (`test_exclusion_never_makes_it_easier`) | counting a crash as attack evidence | — |
| 7 | **Checked on every capture.** Old vs new checker on all analysed captures: **53 on oct. 18 and 54 on oct. 19, and each time only the run in question changed** (7:21 PM and 10:11 PM). tree/G402/highload is **still rejected** (a real victim ↔ bystander flip) | a rule that quietly passes many runs | verification #46, #47 |
| 8 | **Negative tests:** the data broken on purpose: a forced flip, an attacker that moves, the signature only after the move, a long outage. Each is caught or handled as designed (`tools/test_verify_attack.py`, 34/34) | a rule that never fires | — |

## 5. Worked examples (real runs)

### Example A — oct. 18, **10:11 PM** run (blackhole · tree · G402 · stationary r1) → CONFIRMED

**Layout when the attack started:**

```
ROOT (B0:18)
 ├── 0C80                      BYSTANDER  (not behind the attacker)
 └── 1C38  = ATTACKER
      ├── D7B4                 VICTIM
      ├── F4:18                VICTIM
      └── 70:68                VICTIM
           └── ED80            VICTIM  (behind 70:68, so also behind the attacker)
```

**What happened during the 180 s attack:**

| Attack time | Event | ED80's label |
|---|---|---|
| +0 s | Attack starts. All 4 victims deliver 0 %, 0C80 delivers 100 % | VICTIM |
| **+29 s** | **70:68 goes down** (its file ends here; root marks it OFFLINE at +59 s) | — |
| +29 → +43 s | ED80 still lists 70:68 as its parent: it is **trying to reconnect to it**, exactly as Espressif describes | **UNKNOWN** (10 s) |
| +43 → +53 s | ED80 gives up on 70:68, has no parent, **scans** for a new one | **DETACHED** (10 s) |
| **+53 s** | ED80 joins **F4:18**, which is **still under the attacker** | **VICTIM** again |
| +53 → +180 s | stays under F4:18 | VICTIM |

**How each rule judged it:**

- **R1:** ED80 was VICTIM in all 140 traceable seconds, never BYSTANDER → allowed.
- **R2:** 20 no-path seconds (12 %) → **removed from the test** and reported as a long outage.
- **R3:** the attacker never moved → OK.
- **R4:** only **42 s** of attack happened before the first move (needs 60 s) → robustness could not be
  tested; the report says so (WARNING).
- **R7:** 70:68 dropped out at +29 s, but 3 other victims remained → WARNING.
- **3-sigma test** on what is left: attacker forwarding 1.000 → 0.000, victims' PDR 1.0 → 0.0,
  bystander 0C80 stayed 1.0 → **BLACKHOLE CONFIRMED**.

**Footnotes this run must carry** (checklist C13): 70:68 has only 29 s of attack; ED80's 20 no-path
seconds were excluded; the robustness re-test was not possible (42 s); FE90 not yet collected.

### Example B — oct. 18, **7:21 PM** run (same cell, archived) → CONFIRMED, robust

Victim **F4:18** (under the attacker) crashed **152 s** into the attack. Its two children **D7B4** and
**ED80** re-joined, D7B4 directly under the attacker and ED80 under D7B4, so **both stayed VICTIMS**
(3 s and 5–7 s without a path). The re-test on the **156 s before the first move** confirmed the
attack on its own → **ROBUST**. (Verification #45.)

### Example C — oct. 17, **highload** run (tree · G402) → still REJECTED

Victim **B768** spent **94 s as a VICTIM and then moved to a place not behind the attacker** (BYSTANDER)
for longer than 3 s. Half of its attack is a different experiment → **R1 FAIL → SETUP INVALID**. The
smart rule did **not** rescue this run, and it should not.

## 6. Where the limits come from (our own data)

Measured on **oct. 18, 2026** over all 53 analysed captures (367 board-runs, phases 0–3):

| What | Value |
|---|---|
| Re-joins seen (a board loses its parent and gets one again) | **7** in 367 board-runs |
| How long 6 of the 7 took | **3–6 s** (median 4 s) |
| The 7th | **54 s**: B768 in the highload run above (rejected) |

- **10 %** of a 180 s attack = **18 s**: three times the longest normal re-join (6 s), far below the
  abnormal one (54 s). Under it = "brief re-join"; over it = "long outage". Either way, the no-path
  seconds are left out of the test.
- **3 seconds** for a real flip: windows are 1 s and boards' clocks are aligned to ±1–3 s, so 1–2
  seconds in the other label can be timing noise around a re-join.
- **60 s** for the robustness re-test: one third of the attack, enough points for the 3-sigma test.

Re-measure after the campaign and update this table.

## 7. Supporting studies (checked oct. 19, 2026)

**No paper proves this exact rule. It is our design.** What the thesis must support is the facts
it stands on. Each source below was looked up on oct. 19, 2026 (title, year, volume checked).

| What we claim | Source | What it says, in short | Checked |
|---|---|---|---|
| Boards changing parent after a failure is **normal ESP-MESH behaviour** | **Espressif Systems. *ESP-WIFI-MESH* (API Guides), *ESP-IDF Programming Guide* v5.3, "Overview" and "Managing a Network → Intermediate Parent Node Failure".** https://docs.espressif.com/projects/esp-idf/en/v5.3/esp32/api-guides/esp-wifi-mesh.html | *"ESP-WIFI-MESH is self-organizing and self-healing meaning the network can be built and maintained autonomously."* If an intermediate parent breaks down, its children *"initially attempt to reconnect with the parent node"*, then scan and *"each child node will individually select a new preferred parent node"*; afterwards *"the network is healed, however the network routing has been affected"*. That is **exactly** ED80's +29 → +43 → +53 s sequence in Example A | ✅ quoted from the page. Cite the IDF version you build with (team uses v5.3 and v5.5) |
| A blackhole only harms traffic that **passes through** it, so "who is behind the attacker" is what matters | **Karlof, C., & Wagner, D. (2003). Secure routing in wireless sensor networks: Attacks and countermeasures.** *Ad Hoc Networks*, 1(2–3), 293–315 (also in the IEEE SNPA 2003 workshop) | introduces sinkhole/selective-forwarding attacks; the damage depends on the malicious node sitting on the data flow's path | ✅ already cited in the paper (`ATTACK-VALIDATION.md`). Paper confirmed online; the journal volume/pages were not shown in the search results, so check them once in Google Scholar |
| The decision is made **blind to the result** | **MacCoun, R., & Perlmutter, S. (2015). Blind analysis: Hide results to seek the truth.** *Nature*, 526(7572), 187–189. doi:10.1038/526187a | hide the result while the analysis is designed and finalised, to stop confirmation bias | ✅ |
| The limits were **fixed in advance**, not tuned to save data | **Simmons, J. P., Nelson, L. D., & Simonsohn, U. (2011). False-positive psychology: Undisclosed flexibility in data collection and analysis allows presenting anything as significant.** *Psychological Science*, 22(11), 1359–1366. doi:10.1177/0956797611417632 | choosing rules *after* seeing the data ("researcher degrees of freedom") makes false findings easy | ✅ |
| (same) | **Nosek, B. A., Ebersole, C. R., DeHaven, A. C., & Mellor, D. T. (2018). The preregistration revolution.** *PNAS*, 115(11), 2600–2606. doi:10.1073/pnas.1708274114 | fix the questions and the analysis plan **before** looking at the outcome | ✅ |
| The limit values (10 %, 3 s, 60 s) | **Our own measurement** (§6) | — | ✅ measured; say so plainly |

**Searched for, not recommended:** a blackhole study on a network whose layout changes during the
attack (MANET literature). The ones found are about MANET routing in general (e.g. Tseng, Chiang &
Chao 2018, *JIPS* 14(1):56–78; Raj & Swadas 2009, *IJCSI*). Their pages did not state the point we
need, so they add little. **The Espressif quote is direct evidence for our exact protocol and is
enough.**

## 8. What to write in the thesis (draft paragraph)

> *ESP-WIFI-MESH is self-organizing and self-healing: when an intermediate parent node fails, its
> child nodes first try to reconnect to it and then each selects a new preferred parent, after which
> "the network is healed, however the network routing has been affected" [Espressif, ESP-IDF v5.3].
> A parent change during the attack therefore does not by itself invalidate a run. Instead, every
> node was labelled in each 1-s window as a victim (its route to the root passes through the attacker)
> or a bystander, following the definition that a blackhole only affects traffic routed through it
> [Karlof & Wagner 2003]. A run with parent changes was kept only if (i) no node switched between
> victim and bystander for 3 s or more, (ii) the attacker never moved, and (iii) where at least 60 s
> of attack preceded the first change, the 3-sigma test confirmed the attack on those seconds alone.
> Seconds in which a node had no path to the root (searching for a parent, or its parent had failed)
> were excluded from the test; because such seconds show no delivery, excluding them can only weaken
> the attack evidence. The decision used the topology only and never the delivery being measured,
> and all limits were fixed before being applied, following blind-analysis and pre-registration
> practice [MacCoun & Perlmutter 2015; Simmons et al. 2011; Nosek et al. 2018]. The limits come from
> our own captures (normal re-joins took 3–6 s). Applied to all analysed captures, the rule changed
> the verdict only of the runs it was written for, each reported with its footnotes.*

## 9. One-line answers for the panel

- **"Isn't that just rescuing bad data?"** No. The rule decides from the layout only, never from the
  result. It is strict both ways, and it still rejects the highload run where a victim really moved
  out of the attacker's path.
- **"Why not lock the topology?"** That would switch off the self-healing the protocol is built on
  (Espressif), and a locked child of a crashed parent just loses its data anyway.
- **"A victim's parent crashed mid-attack. What happens to its data?"** Until it re-joins it has no
  path, so those seconds are left out. Once it re-joins under the attacker it counts again
  (10:11 PM run: 20 seconds of ED80 left out).
- **"Why 10 %?"** Normal re-joins in our captures took 3–6 s; 10 % of the attack is 18 s.
- **"Which runs used it?"** The report prints "TOLERATED" for each one: dataset-verification.md
  #45, #46, #47.
- **"Can START be pressed with a bad setup?"** No. Red pre-START checks lock it (D-24). An override
  needs a typed reason, which the verifier reports.

## 10. Verdict, grade and REDO - how they fit together (checked oct. 19, 2026, #51)

Three answers come out of two programs, and they answer **different questions**:

| Answer | Program | Question | Decided by |
|---|---|---|---|
| **VERDICT** | `verify_attack.py` | did the attack happen in this data? | the 3-sigma test on the attack's signature [Zhukabayeva 2025; Airehrour 2018] + the setup checks |
| **CONFIDENCE** | `verify_attack.py` | how cleanly? | STRONG · GOOD (notes) · MINOR GAPS (missing data the result does not need - impact check) · MAJOR GAPS (the result needs it) · NOT CONFIRMED |
| **REDO / CHECK / OK** | `redo_list.py` | is this run good enough to keep for the thesis? | the worst of: capture completeness (all boards, >= 95 % samples), structure on the raw files, analysis freshness, **the verifier above**, the verification log, thesis-checklist D-rows |

So **CONFIRMED + REDO is not a contradiction**: the attack happened, but the dataset is incomplete (e.g. tree/G402/burst:
7 of 8 boards, checklist D2). They line up everywhere else: STRONG / GOOD = OK (🟢 DONE), MINOR GAPS = CHECK (🟡 DONE - RECAPTURE ADVISED), MAJOR GAPS = REDO from `verifier-data` (🟠 RECAPTURE REQUIRED), not confirmed = REDO from `verifier` (🔴 REDO).

**Proof it is not tuned:** moving every threshold by about half up and down (728 re-judgements) changes **no** verdict;
two absurd control settings do change many - so the verdicts sit far from every threshold and are decided by the data.
Re-run any time: `python tools/audit_verdict_sync.py` and `python tools/audit_threshold_sensitivity.py`.

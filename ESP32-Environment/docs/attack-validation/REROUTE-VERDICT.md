# The re-route verdict ("smart decision") — what it is, why it is fair, how to defend it

> **Panel question this answers:** "ESP-WIFI-MESH re-parents by itself. Some of your boards
> changed parent during the attack. Why do you still count some of those runs, and how do we know
> you didn't just pick the rule that saves your data?"
>
> **Source of truth:** `tools/attack_checks.py` (`topology_issues`, `exposure_timeline`,
> `reroute_onset`) and `tools/verify_attack.py` (`_robustness_issue`). Deviation **D-23** (rule) +
> **D-24** (START lock), checklist **A26** (🟨 adviser) / **A27** / **A28**, verification **#45, #46**.
> Written oct. 18, 2026.

---

## 1. The problem in one paragraph

ESP-WIFI-MESH is **self-forming and self-healing**: when a parent node disappears, its children
look for a new parent on their own. That is not a bug, it is the protocol, and our paper describes it.
But the attack experiment assumes **one layout** during the attack. If a board moves mid-attack,
are the attack windows still **one experiment**? Before oct. 18 the verifier said "any parent change
of a victim or the attacker = SETUP INVALID". That rejected runs where nothing that matters changed.
For example, on oct. 18 at 7:21 PM a victim crashed. Its two children re-joined, **still behind
the attacker**, and still delivered 0 %.

## 2. The decision: judge the change by what it did to the attack, not by the fact it happened

We chose this over a **firmware lock** (pinning parents at START). The reasons:

| Option | Why not / why |
|---|---|
| Lock the tree at START | Contradicts the self-healing behaviour the paper describes. It cannot help when the parent itself crashes, because a pinned child of a dead parent just loses its data. It is also a bigger method change than a verifier rule |
| Reject every parent change (old rule) | Throws away runs whose attack reached exactly the same boards. That treats a harmless re-route the same as a broken experiment |
| **Judge by exposure (chosen)** | What defines a blackhole experiment is **who the attack reaches**. If that set never changed, the attack windows are one experiment |

**Exposure class**, per board, per 1-second window, found by walking its parent chain at that moment:

- **victim**: its path to the root runs through the attacker
- **bystander**: it reaches the root without the attacker
- **detached**: it has no parent right now (re-joining)
- **unknown**: the chain cannot be resolved

## 3. The rules (all must hold for a re-route to be TOLERATED)

| # | Rule | Threshold | Fails as |
|---|---|---|---|
| R1 | The board stays in **one class** for the whole attack. A board carried across by a moving parent counts too | < 3 windows in the other class | FAIL "moved between VICTIM and BYSTANDER" |
| R2 | **Re-join budget**: time spent detached or unknown | ≤ 10 % of the attack (18 s of 180 s) | FAIL "too much of its attack is a re-join" |
| R3 | The **attacker** never moves. Its position *is* the experimental treatment | 0 | FAIL always |
| R4 | **Robustness**: the 3-sigma test, re-run on the attack windows **before** the first re-route only, must still confirm | needs ≥ 60 s before the re-route | FAIL "NOT ROBUST"; < 60 s = WARN "rests on the layout rule alone" |
| R5 | Wormhole: the A end stays **shallower** than the B end | < 3 seconds otherwise | FAIL "the shortcut changed" |
| R6 | **Phase comparison**: the class at the end of the baseline (last 60 s) and the start of the cooldown (first 60 s) vs the attack | — | WARN only (a confound for per-board features, to footnote) |
| R7 | A victim that **dropped out** (e.g. crashed) | other victims remain | WARN; losing the attacker or **every** victim = FAIL |

A TOLERATED re-route is still **printed** as a WARN in the report. It is footnoted, never hidden.

## 4. Why it is not cheating: the fairness rules

These are deliberate. Each one maps to a known safeguard from research methodology (§6).

1. **Outcome-blind.** The accept/reject decision reads **only the layout** (`parent_mac`, `hop`).
   The quantities the 3-sigma test scores (PDR, ForwardingRatio) are shown in the message, labelled
   *"shown, not used to decide"*. Accepting a layout because the attack still looked successful
   would be circular. A unit test forces every attack PDR to 1.0 and checks that the decision does
   not change (`test_decision_ignores_delivery`). → *blind analysis*
2. **Thresholds fixed in advance.** The thresholds are constants in the code, each with its reason,
   and they are the same for every run. They are never tuned per capture. → *pre-registration;
   limits "researcher degrees of freedom"*
3. **Symmetric.** Victim → bystander and bystander → victim fail alike.
4. **The treatment is fixed.** The attacker moving is never tolerated.
5. **The result can only downgrade.** The one place the outcome is used, the robustness re-test (R4),
   can turn CONFIRMED into SETUP INVALID, never the reverse. → *sensitivity / robustness analysis*
6. **Checked against every capture.** The old verifier (commit `0e43f7e`) and the new one were run
   on all **53** analysed attack captures. **Exactly 1 verdict changed**: the run the rule was
   designed for. blackhole/tree/G402/highload is **still rejected** because it has a real
   victim ↔ bystander flip. (Verification #46.)
7. **Negative tests.** We broke the data on purpose four ways, and each was caught: a forced flip,
   30 s detached, the signature moved to after the re-route, and the attacker moved
   (`tools/test_verify_attack.py`, 33/33).

## 5. Where the thresholds come from (our own data)

**Measured on oct. 18, 2026 over all 53 analysed captures (367 board-runs, phases 0–3):**

| What | Value |
|---|---|
| Re-join episodes (a board shows no parent, then a parent again) | **7** in 367 board-runs |
| Duration of 6 of the 7 | **3–6 s** (median 4 s) |
| The 7th | **54 s**: B768 in blackhole/tree/G402/highload, the crash run the verifier still rejects |

- **10 % budget (18 s)** sits 3× above the longest normal re-join (6 s) and far below the abnormal one (54 s).
- **3-window flip threshold**: windows are 1 s and boards are aligned to ±1–3 s, so 1–2 windows in
  the other class can be alignment noise around a re-join. 3 or more in **each** class is a real flip.
- **60 s phase edges / 60 s robustness minimum**: one third of the 180 s attack, enough points for the
  3-sigma test's minimum sample rule.

Re-run this measurement after the campaign and update the table. The numbers above are from oct. 18.

## 6. Do we need supporting studies? — Yes, three kinds

The rule itself is **our design**, not borrowed, so no paper "proves" it. Present it as an
engineering decision. The thesis must support three things around it:

| Claim in the thesis | Support it with | Status |
|---|---|---|
| ESP-WIFI-MESH re-parents by itself (self-healing), so re-routes are protocol behaviour, not a setup error | **Espressif, *ESP-WIFI-MESH Programming Guide*, ESP-IDF docs** (self-organising / self-healing network, parent selection). Cite the version you build with (v5.3 / v5.5) | ⬜ find the exact section + cite |
| Decision made blind to the outcome | **MacCoun & Perlmutter (2015), "Blind analysis: Hide results to seek the truth", *Nature* 526** · **Klein & Roodman (2005), "Blind analysis in nuclear and particle physics", *Annu. Rev. Nucl. Part. Sci.* 55** | ⬜ verify + add to references |
| Rules + thresholds fixed in advance, not tuned to rescue data | **Simmons, Nelson & Simonsohn (2011), "False-positive psychology", *Psychological Science* 22(11)** (researcher degrees of freedom) · **Nosek et al. (2018), "The preregistration revolution", *PNAS* 115(11)** | ⬜ verify + add |
| The verdict holds on the clean part alone | Robustness / sensitivity analysis: cite one methods text or the 2 above. Our own evidence is R4 + verification #45 | ⬜ |
| What "victim" means | The blackhole definition already in the paper (**Karlof & Wagner 2003**, see `ATTACK-VALIDATION.md`): the attack affects traffic **routed through** the malicious node | ✅ already cited |
| Threshold values | **Our own measurement** (§5). Say so; no outside source exists for ESP-MESH re-join time on our hardware | ✅ measured |

⚠️ **Look each reference up before citing it.** They are well-known papers, but check the title,
year and volume against the real source; do not copy them from this file blind.

## 7. What to write in the thesis (draft paragraph)

> *ESP-WIFI-MESH is self-healing: when a parent node fails, its children select a new parent
> automatically [Espressif]. A parent change during the attack therefore does not by itself
> invalidate a run. Instead, each node was classified in every 1-s window as a victim (its route to
> the root passes through the attacker), a bystander, or detached. A run with parent changes was kept only if (i) no node
> changed class for ≥ 3 s, (ii) no affected node spent more than 10 % of the attack detached (the
> longest normal re-join measured in our captures was 6 s), (iii) the attacker never moved, and (iv)
> the 3-sigma test, repeated on the attack windows before the first parent change alone, still
> confirmed the attack. The decision used the topology only and never the delivery being measured,
> and the thresholds were fixed before being applied, following blind-analysis and pre-registration
> practice [MacCoun & Perlmutter 2015; Nosek et al. 2018]. Applied to all 53 captures, the rule changed the verdict of one run; it is
> reported with its tolerated re-routes.*

## 8. One-line answers for the panel

- **"Isn't that just rescuing bad data?"** The rule never looks at the attack result to accept a run.
  It changed 1 of 53 verdicts, and the run it accepts also passes on the part before the re-route alone.
- **"Why not lock the topology?"** That would switch off the self-healing the protocol is built on,
  and a locked child of a crashed parent loses its data anyway.
- **"Why 10 %?"** Normal re-joins in our captures took 3–6 s; 10 % is 18 s.
- **"Which runs used it?"** The verifier prints "TOLERATED" for each one; see dataset-verification.md (#45, #46).
- **"Can START be pressed with a bad setup?"** No. Red pre-START checks lock it (D-24). An override needs a typed
  reason, which the verifier reports.

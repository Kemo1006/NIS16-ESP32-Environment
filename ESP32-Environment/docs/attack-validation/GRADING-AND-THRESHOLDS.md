# How a run is judged — verdict, grade, thresholds and their basis

*Written oct. 19, 2026 (verification #53). Plain-language reference for the team and the thesis
write-up. Companion to [REROUTE-VERDICT.md](REROUTE-VERDICT.md) (D-23 board moves).*

---

## 1. Four questions, answered separately

The confusion "the dataset is incomplete, so why did the attack PASS?" comes from mixing four
different questions. The verifier answers each on its own, and the GUI shows them as the four
**VALIDITY** lights (Campaign run panel and Verify page):

| Light | Question | Decided by | Possible answers |
|---|---|---|---|
| **ATTACK** | Did the attack happen in this data? | the 3-sigma test on the signature + the setup checks | seen · not seen · not as designed (setup invalid) · untestable |
| **SIGNATURE** | Which features moved, and by how much? | §3 below — one row per feature | `k/n primary` passed |
| **SETUP** | Did the run go as designed (topology, roles, start)? | the setup checks [3] (D-22..D-24) | as designed · moves allowed (D-23) · check(s) failed |
| **DATASET** | Is the data complete enough to use? | window coverage, silent boards, cooldown, no-path share + the impact check | complete · minor gaps · major gaps |

They combine into **one status** (the colours you already know):

| Verdict (ATTACK) | Grade (DATASET + notes) | Status |
|---|---|---|
| CONFIRMED | STRONG / GOOD | 🟢 DONE |
| CONFIRMED | MINOR GAPS | 🟡 DONE - RECAPTURE ADVISED |
| CONFIRMED | MAJOR GAPS | 🟠 RECAPTURE REQUIRED |
| NOT CONFIRMED / INCONCLUSIVE / SETUP INVALID | NOT CONFIRMED | 🔴 REDO |

So **"attack confirmed + incomplete dataset" is a normal, honest outcome**: the attack is
evident in the data that exists, and the dataset is graded separately. One never overrides the
other: a complete dataset does not confirm an attack whose signature is absent (that run is
NOT CONFIRMED), and a gap never "un-sees" an attack that the remaining data shows clearly.

**PASS / FAIL / INCONCLUSIVE** are already three-way: *CONFIRMED* = a primary signature passed
and the setup held; *NOT CONFIRMED* = tested, no primary passed (or the setup was invalid);
*INCONCLUSIVE* = too little data to test (fewer than `MIN_ATTACK_POINTS` points, or a broken
baseline) — it is never turned into a pass or a fail.

---

## 2. Why missing data cannot make an attack PASS

Missing windows **remove evidence; they never add it**:

1. The test only uses windows that exist. Fewer windows = fewer points = a weaker test, and below
   `MIN_ATTACK_POINTS` (30 s) the feature is not tested at all (INCONCLUSIVE, not PASS).
2. A delivery of 0 is only counted when the board **was associated and sending** (features.py PDR
   attribution rules 1-5): a silent, detached or rebooting board produces *no* PDR, never a fake 0.
3. Windows in which a board had **no path to the root** are left out of the test (D-23) — they
   would only make the attack look stronger.
4. The **impact check** re-runs the test *without* every board that has a gap. If the attack is
   still confirmed, the gaps did not create the result (MINOR). If not — or if the gaps cover more
   than half the network, so too little would be left to prove it — they are MAJOR.
5. Controls that a data gap cannot fake: the attacker must forward < 50 % (a real blackhole: 0 %),
   and boards **not** behind the attacker must keep delivering (the loss is specific to its path).

**Placebo test (new, `tools/audit_false_positives.py`)**: for every run, the *second half of the
baseline* is relabelled as if it were the attack and the identical test is run. Normal traffic
must never "confirm". Result: **104 tests, 0 false positives** for the full verdict. The 3-sigma
score alone passed once (blackhole/linear/home/highload: congestion under high load dropped the
attacker-to-be's forwarding to 86 % *before* any attack) — the attacker check stopped it, which
is exactly why that check exists.

---

## 3. The attack signature — every feature, its formula, its basis

| Feature | Formula (where) | Basis | Role | Correct? |
|---|---|---|---|---|
| ForwardingRatio (attacker) | forward / recv per window (proposal **Eq 4.2**, features.py); the test pools 5 windows as **sum(forward) / sum(recv)** on the attacker's windows only | Airehrour et al. 2018: a blackhole drops what it should forward | PRIMARY (blackhole) | ✅ ratio-of-sums is the right estimator for a rate (mean of per-window ratios is biased by tiny denominators); attacker-scoped because pooling with honest relays dilutes it (0.826 vs 0.002, sept 30) |
| PDR | probes the root logged **by sequence number** / probes the victim sent successfully (features.py) — victims only, 5 attribution rules | Airehrour 2018 (delivery collapses); Khan et al. 2022 (healthy ESP-MESH > 97 %) | PRIMARY (blackhole) | ✅ sequence numbers cross boards without a shared clock; 0/0 is NaN, never 0 |
| NeighbourForwardingRatio | NeighbourOut / NeighbourIn — what the attacker's children handed it vs what the root got from below it | Airehrour 2018 | support | ✅ independent of the attacker's own counters (a second witness) |
| IngressEgressDelta | \|recv − forward\| (**Eq 4.3**) | Airehrour 2018 ("discard, don't forward") | support | ✅ |
| ConsistencyScore | \|ForwardingRatio − 1\| (**Eq 4.15**) | Airehrour 2018 | support | ✅ but it carries the **same information** as ForwardingRatio — that is why it is support only and never counted as a second primary |
| TunnelIntensity | tunnel messages / s (**Eq 4.16**) | Zhukabayeva et al. 2025 (out-of-band tunnel) | PRIMARY (wormhole) | ✅ ~0 in baseline by construction |
| DuplicateRate | share of B's windows in which the root logged the same probe twice | Ramirez Gomez et al. 2019 (duplicate packets) | PRIMARY (wormhole) | ✅ measured by the root, independent of the tunnel boards |
| TunnelBytes | TunnelIntensity × 30 B | Zhukabayeva 2025 | support | ✅ same measurement, never a second primary |
| TunnelLatency, LatencyHopRatio | **measured, not scored** | Hu, Perrig & Johnson 2003 | shown only | ✅ no normal-phase values / spread wider than the mean - a 3-sigma test cannot apply (team decision oct. 16) |

**The test** (Zhukabayeva et al. 2025): a feature passes when its attack-phase mean lies more than
3 standard deviations from the normal-phase mean, in the expected direction, **and** moves by at
least `MIN_EFFECT` (0.10). The attack is CONFIRMED when at least one PRIMARY passes and the setup
held.

**One honest caveat to state in the paper:** on a perfectly stable baseline (sd = 0, e.g. PDR
1.000 ± 0.000) z is infinite for any move, so there the test reduces to the minimum-effect rule.
That is why `MIN_EFFECT` exists, and why a baseline must also be healthy (PDR ≥ 0.90) and quiet
(sd/mean ≤ 0.15) before it counts as a reference.

---

## 4. Every threshold and where it comes from

Four kinds of basis — and only the first needs a research paper:

| Kind | What it means | How to defend it |
|---|---|---|
| **S — study** | the value or rule comes from a published paper | cite it |
| **P — our own proposal / spec** | the value is in the thesis methodology or the project milestones | cite the section |
| **D — platform documentation** | the value follows from how ESP-IDF / FreeRTOS behave | cite the vendor docs |
| **E — engineering bound** | no paper sets this number for a testbed like ours | fixed **before** seeing results [Simmons 2011; Nosek 2018] **and** shown not to matter by a sensitivity analysis (§5) |

| Threshold | Value | Kind | Basis / reasoning |
|---|---|---|---|
| sigma | 3 | S | Zhukabayeva et al. 2025 |
| pooling block | 5 windows | P | proposal Table 4.10 (5 s window; D-9 kept 1 s windows for the dataset) |
| window valid | ≥ 8 of 10 samples, gaps ≤ 2 samples | P | proposal §4.2.4.1 point 4 (80 % completeness) |
| sample may be late by | ≤ 3 ticks (300 ms) | D | FreeRTOS `xTaskDelayUntil`: a held-up task runs each missed period at once, so samples are late, never early; measured p99 lateness 278 ms (D-25) |
| baseline healthy | PDR, FR ≥ 0.90 | S | Khan et al. 2022: healthy ESP-MESH > 0.97; floor set below it so it trips on a broken measurement, not a lossy run |
| baseline quiet | sd/mean ≤ 0.15 | E | a measured broken baseline had 0.39 |
| minimum effect | 0.10 | E | far below any real attack (1 → 0), far above one-probe noise |
| min. attack points | 6 blocks (30 s) | E | |
| attacker forwards | < 50 % | E | Airehrour 2018 defines the drop; 50 % is the midpoint between honest (≈100 %) and attacker (≈0 %) |
| bystanders may lose | ≤ 30 % | E | Karlof & Wagner 2003: only traffic through the attacker is lost |
| victims' PDR | < 0.50 | E | |
| window coverage per phase | ≥ 95 % | P | the project's own sample-coverage floor (Milestone 5) applied to windows |
| impact check may set aside | ≤ half the boards | E | otherwise a minority (often no control group) is left |
| re-route budget, flip windows, flap changes, silent tail, robust re-test, no-path share, cooldown share | 10 %, 3, 4, 10 s, 60 s, 25 %, 50 % | E | D-23 rules ([REROUTE-VERDICT.md](REROUTE-VERDICT.md)) |

**Do we need a paper for every number? No** — and the paper should not pretend we have one. For
the E thresholds the accepted practice is: state the rule, state that it was fixed before the
results were seen, and show a **sensitivity analysis** that the conclusions do not depend on the
exact value (Saltelli et al. 2008, *Global Sensitivity Analysis: The Primer*, Wiley — check the
citation before use). Suggested sentence:

> "Where no published value exists for our testbed, thresholds were set as engineering bounds
> before the results were examined and validated by a one-at-a-time sensitivity analysis
> (each moved by ±~50 %): no verdict and no grade changed (Table X). A placebo test on
> attack-free data produced no false confirmation in 104 tests."

---

## 5. Sensitivity results (re-run any time)

| Tool | What it moves | Result (oct. 19) |
|---|---|---|
| `tools/audit_threshold_sensitivity.py` | 14 verdict thresholds ±~50 % | 0 verdicts flip; two absurd controls flip 31 / 14 (the test can fail) |
| grade sweep (verification #53) | every grade threshold down and up | 0 grade moves, except at extreme values (window floor 80 % / 98 %) |
| `tools/audit_false_positives.py` | placebo: normal vs normal | 0 false positives in 104 |
| `tools/audit_verdict_sync.py` | verifier vs redo list vs GUI | all 5 rules hold |

---

## 6. Missing windows and "stalling" — the real cause, and the fix (D-25)

**What looked like stalling was mostly our own preprocessing.** The boards logged at the full
10 Hz (FE90, tree/G402/stationary: 1,807 rows in 182 s of attack). But the firmware samples with
`xTaskDelayUntil`: when the task is held up (cause not yet measured — SD-card writes and radio work
are the likely candidates; the [HEALTH] line can confirm it), it runs the missed samples
back-to-back — timestamps like 258 ms, 1 ms, 41 ms instead of 100, 100, 100. Preprocessing put
every row on the **nearest** 0.1 s tick, so a bunched pair landed on one tick and left a false
hole; three holes in a second discarded the window. FE90 lost 59 % of its attack windows that way
with no sample actually missing.

**Fix (preprocess.py `_assign_ticks`, D-25):** each sample goes to the earliest free tick it could
have been scheduled for (up to 300 ms late, never early). One sample per tick, nothing invented,
nothing counted twice. Result: FE90 10 % → 0 % windows discarded, ED80 15 % → 0 %, 0C80 3 % → 0 %;
clean boards unchanged.

Re-analysis of all 52 attack runs with the fix (trim → preprocess → features, as analyze.ps1 does): **all 52 verdicts identical**; two grades change — blackhole/linear/G402/stationary MINOR → GOOD (its gaps were this artifact) and blackhole/tree/G402/stationary MAJOR → MINOR (only B768's crash is left).

**What remains is real** and the fix does not hide it:

| Cause | Example | Can it be prevented? |
|---|---|---|
| a board crashes / reboots (PANIC, INT_WDT) | B768 went down 28 s into the attack (D9 pattern) | **Prevent:** find the crash with the Live run's crash watch (backtrace decoded), fix it before more runs |
| the attacker's sampling task is starved while it drops traffic | 1C38: mean interval 101 ms, ~3 % real windows lost | **Mitigate:** telemetry task already above the relay (TASK_PRIO notes); could rise further — needs a firmware test |
| a board stops before the cooldown | no cooldown recorded | **Prevent:** do not collect / power off before the root says SAFE TO EXPORT |
| an old reversed / duplicate session in a folder | `trimmed/` of wormhole/linear/G402/stationary | **Prevent:** analyze.ps1 always re-trims; never point tools at `trimmed/` by hand |

**How to check a fix worked:** `python tools/audit_false_positives.py`, the grade sweep, and the
per-board coverage line the verifier prints (S9) — after a recapture every board should show
≥ 95 % windows per phase.

---

## 7. Benign runs (no attack) — now verified too

A benign capture is the **normal reference**, so it must be shown normal with the same tests
pointed the other way (`verify_attack.py --attack none`, Verify button on a baseline run):

1. **No-attack test** — the 3-sigma test of *both* signatures, the later phase (where an attack
   would run) vs the baseline: **no feature may pass** (the chips read STILL / MOVED).
2. **Health** — every phase delivers PDR ≥ 0.90 [Khan 2022] and every relay forwards ≥ 90 % [Airehrour 2018].
3. **Data** — every board ≥ 95 % windows per phase.

BENIGN CONFIRMED / BENIGN NOT CONFIRMED / INCONCLUSIVE, graded and coloured like attack runs.

**The one benign capture we have (baseline/linear/home/highload, sept 30) is NOT a clean
reference:** its cooldown delivered only 72 % and two relays forwarded 83-85 % with **no
attacker** (high-load congestion) — the blackhole PDR signature "moved" on normal traffic. It
should be recaptured (and D-18's planned benign runs per location × topology captured) before the
benign class is used in the thesis.

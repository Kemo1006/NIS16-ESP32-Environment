# Dataset Verification Log

Every time someone asks Claude to verify the datasets / analysis / EDA, one block is
added **at the top** (newest first). One block = one verification request, boxed by
`════` dividers and headed with its date and time.

**How to read a block:** the first table says WHICH data (attack · topology · location ·
scenario · repeat); the second says WHAT was checked and the result; then the details and
the verdict. ✅ = OK · ⚠️ = OK with a caveat / fixed · ❌ = not usable.

**Checks used:** `tools/validate_integrity.py` (files, sampling, phases) ·
`tools/verify_topology.py` (mesh shape, who is under the attacker) ·
`tools/verify_attack.py` (3-sigma attack test) · analysis tables vs exports ·
EDA plots (time series + PCA/t-SNE).

<!-- ════════════════════════════════════════════════════════════════════════════════ -->
<!-- ════════════════════════════════════════════════════════════════════════════════ -->

## 🔎 VERIFICATION #3 — Oct 3, 2026 · 9:16 PM — blackhole · tree · G402 · burst

> **Requested by:** Angelo · **Laptop:** Angelo's · **Commit:** `4def0f8`
> **Request:** "verify is this is correct [verify_attack output] and if the analysis, eda,
> timeseries are correct and also put it to the verify docs"

| Attack | Topology | Location | Scenario | Repeat | Captured | Files |
|---|---|---|---|---|---|---|
| blackhole | tree | G402 | burst | r1 | Oct 2, 8:05–8:23 PM | 9 (8 telem + root arrivals) |

| Check | Result | Detail |
|---|---|---|
| Integrity (`validate_integrity.py`) | ⚠️ 8 PASS / 1 FAIL | FAIL = `B4BFE932FE90` out of sync with the root (27 % of its probes in the wrong phase) |
| Burst fired | ✅ YES, inside the attack | target `F42DC973E618`: seq 389 → 866 over the 182 s attack ≈ +295 burst probes (firmware fix `6b90df5` now proven on hardware) |
| Topology (`verify_topology.py`) | ⚠️ tree, depth 2 — but FE90's parent is wrong | reported: 2 victims under attacker `20:50:0D:E7:1C:38`; really 3 (FE90, see below) |
| Attack (`verify_attack.py`) | ✅ CONFIRMED 2/2 | FR attacker 1.000 → 0.000 (−inf) · PDR 0.999 → 0.600 (z −23.36) |
| Analysis tables | ✅ match the verifier | 7 nodes labelled (~420 baseline+cooldown / ~180 attack windows each); FE90 unlabelled |
| EDA time series | ✅ correct | attacker FR → 0, both victims' PDR → 0, root arrivals 6 → 3, all recover in cooldown |
| EDA PCA / t-SNE | ✅ correct | attack windows form their own cluster (the Oct 2 fix works here) |

### The verifier output: correct
- **Pooled PDR 0.600** = average of the 5 labelled children: 2 victims at 0.0 (`20500DE70C80`,
  `F42DC973E618`, both hop 2 under the attacker) + 3 at 1.0. That is 2 out of 5 lost, so 0.6. It matches
  the per-node table and `feature_table.csv`.
- **ForwardingRatio (attacker)** 1.0 → 0.0. The one honest relay (`B4BFE934ED80`, which carries
  `704BCA25B768`) stays at 1.0, so the "all relays" row averages to 0.5. Arithmetic is correct.
- **ConsistencyScore 0.5 / IngressEgressDelta 0.654:** these move in the expected direction because the
  attacker's numbers change and the honest relay's don't.
- **Why `-inf`:** in baseline the attacker forwarded exactly 100 % in every 5-window point, so the
  standard deviation is 0. Any drop divided by 0 is infinite. `verify_attack.py:305-316` does this on
  purpose and counts it as a PASS ("baseline sd=0 (perfectly stable)"). This is not a bug. PDR gives a
  finite confirmation at z −23.36.

### ⚠️ Problem found: `B4BFE932FE90` was a hidden third victim
- Its own log says its parent is the root (`B0:CB:D8:F3:32:19`, layer 2) for the whole run, with
  0 send failures, sending 1 probe/s.
- **Not one of its probes reached the root during the root's attack (396–578 s on the root's clock).**
  They resumed the moment cooldown began. Its seq jumped 388 → 568 across that gap, so it did keep sending.
- **The attacker received 835 probes during the attack. The two known victims sent 656 (180 + 476).**
  The extra ~179 match FE90's 180. So FE90's traffic was going through the attacker, and its
  `parent_mac` field is wrong (stale). It also changed phase late (34 s at baseline, 68 s at attack,
  94 s at cooldown, despite a 10 s resync), which suggests the root's messages to it were also slow.
  Why the reported parent was wrong is not known yet. It is a firmware/mesh question, not a data bug.
- **Effect on the data:** preprocess already unlabels FE90 (out of sync), so it is in **no** labelled
  window, no verifier row and no EDA trajectory (the plot's title says so). The labelled data is clean.
  The only trace left is the root's **RootArrivals** feature: it falls 6 → 3 (3 victims), not 6 → 4.
- `verify_topology.py` shows the tree from the nodes' own parent fields, so it puts FE90 under the root.
  Don't quote "2 victims" for this run without this footnote.

### Other notes
- The attacker dropped 11 probes in baseline (queue or send failures, not the attack). Its baseline FR
  is 1.002, and the 5-window points are exactly 1.0.
- `20500DE71C38` (attacker), `704BCA25B768` and FE90 changed parent before baseline, which is the
  pre-baseline idle time and is excluded. No labelled node changes parent or layer inside
  baseline/attack/cooldown.
- PCA dropped IngressEgressDelta as "constant" after removing NaN rows. The verifier still uses it
  (z 19.98). This is the same expected behaviour as earlier cells.

**Verdict: ✅ USABLE (with caveat)**: 7 of 8 nodes are labelled and the attack and burst both fired. Footnote
FE90 as an unlabelled third victim with a wrong parent field. Before r2, watch the root's
PARENT/CHILD dashboard for a board whose reported parent doesn't match how its traffic actually travels.

<!-- ════════════════════════════════════════════════════════════════════════════════ -->
<!-- ════════════════════════════════════════════════════════════════════════════════ -->

## 🔎 VERIFICATION #2 — Oct 2, 2026 · 7:58 PM — sweep of ALL live cells

> **Requested by:** Angelo · **Laptop:** Angelo's · **Commit:** `12207b6`
> **Request:** "fix it and check the previous runs and datasets"
> **Scope:** the 9 cells under `datasets/analysis/` (archive folders not included).

| # | Attack | Topology | Location | Scenario | Repeat(s) | Captured | Integrity | Topology | Attack verdict | Analysis | EDA | Verdict |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | blackhole | linear | G402 | jitter | r1 | Oct 1 | ✅ 9/9 | ✅ | ✅ CONFIRMED | ✅ | ⚠️→✅ fixed | ✅ USABLE |
| 2 | blackhole | linear | G402 | stationary | r1 | Sep 30 | ⚠️ 6 PASS / 3 WARN | ⚠️ | ✅ CONFIRMED | ⚠️ | ✅ | ✅ USABLE (caveat) |
| 3 | blackhole | linear | home | burst | r1 | Sep 30 | ✅ 8/8 | ✅ | ✅ CONFIRMED | ✅ | ⚠️→✅ fixed | ✅ USABLE |
| 4 | blackhole | linear | home | highload | r1–r4 | Sep 27–30 | ⚠️ 26 PASS / 2 WARN | ➖ not measured | ⚠️ INCONCLUSIVE | ✅ | ✅ | ⚠️ PARTIAL |
| 5 | blackhole | partial_mesh | G402 | jitter | r1 | Oct 1 | ✅ 9/9 | ✅ | ✅ CONFIRMED | ✅ | ⚠️→✅ fixed | ✅ USABLE |
| 6 | blackhole | partial_mesh | G402 | stationary | r1 | Sep 30 | ✅ 9/9 | ✅ | ✅ CONFIRMED | ✅ | ✅ | ✅ USABLE |
| 7 | blackhole | star | G402 | stationary | r1 | Oct 1 | ✅ 9/9 | ✅ | ✅ CONFIRMED | ✅ | ✅ | ✅ USABLE |
| 8 | blackhole | tree | G402 | jitter | r1 | Oct 2 | ✅ 9/9 | ✅ (see #1) | ✅ CONFIRMED | ✅ | ⚠️→✅ fixed | ✅ USABLE |
| 9 | blackhole | tree | G402 | stationary | r1 | Sep 30 | ⚠️ 5 PASS / 4 WARN | ⚠️ | ✅ CONFIRMED | ⚠️ | ✅ | ⚠️ DEGRADED — re-capture advised |

**Done in this verification**
- ✅ **EDA PCA/t-SNE fix** (`analysis/eda.py`, `run_dimensionality_reduction`): new rule drops a column
  that is present for a node in one phase but missing in another (its missingness *is* the label).
  Before, those rows were deleted and the victims' PDR = 0 windows vanished from the plot.
  Regenerated `dimensionality_reduction.png` for the 4 affected cells (#1, #3, #5, #8). Every EDA CSV
  stayed byte-identical; `test_segments.py` passes. Victim attack windows now in the plot:
  linear/jitter +191, linear/home/burst +190, partial_mesh/jitter 0 → 403, tree/jitter 0 → 202.
- Every cell: analysis feature table contains exactly the exported telemetry files (none missing, none
  extra), and no node changes parent or layer **inside** the analysed baseline/attack/cooldown
  windows — except tree/G402/stationary (below).

**Per-cell details**

- **#1 linear · G402 · jitter** — Jitter fired: baseline 312.5 s / attack 190.5 s (nominal 300/180).
  Linear chain of 8; attacker `20:50:0D:E7:1C:38`; 5 victims, 1 bystander above the attacker kept
  delivering. FR attacker 0.999 → 0.000 (z −101.5); PDR 1.000 → 0.169 (z −inf, baseline sd 0).
  ConsistencyScore FAIL is secondary (not counted). PCA dropped ForwardingRatio/ConsistencyScore — they
  carried nothing there (the attacker's rows were already dropped for having no PDR).
- **#2 linear · G402 · stationary** — Verdict sound: FR attacker z −137.9, PDR 0.997 → 0.000, 6 victims,
  0 probes reached the root during the attack. ⚠️ 3 victims (`704B…`, `FE90…`, `ED80…`) sat in phase 0
  for ~23 min before the real run (the root restarted) → integrity "4× baseline rows" WARN; that time
  is pre-baseline and excluded, so the WARN is harmless. ⚠️ `FE90` and `ED80` lost about half their
  attack (91 / 104 of 180) and cooldown (54 of 120) windows: their raw samples are complete but
  unevenly timed, so the paper's minimum-samples rule (§4.2.4.1) discarded those windows. Correct
  behaviour; those 2 nodes are thinner in the data.
- **#3 linear · home · burst** — FR attacker z −64.0, PDR 0.994 → 0.203, 4 victims. 3 nodes' logs start
  inside a phase (formation not recorded) — fine. PCA same column change as #1.
- **#4 linear · home · highload (r1–r4)** — ⚠️ INCONCLUSIVE when pooled, already known (MEMORY oct. 1):
  r2/r3 baselines are broken by the 7-board highload collapse (r2 cooldown only 70 % of baseline;
  r4 root logs WARN), so the pooled baseline is noisy. r1 + r4 alone confirm. Root fix (`cb22106`)
  is built but not yet run on hardware. Formation not measured (every log starts inside a phase).
- **#5 partial_mesh · G402 · jitter** — Jitter fired: baseline ~340 s / attack ~202 s. 2 victims
  (`FE90…`, `F42D…`), 4 sources kept delivering. FR attacker z −8.2, PDR 0.997 → 0.667. **Had the same
  PCA bug as tree/jitter** (0 victim attack windows in the plot) — fixed.
- **#6 partial_mesh · G402 · stationary** — FR attacker z −27.7, PDR 0.998 → 0.500, 3 victims. Clean.
- **#7 star · G402 · stationary** — Hub = attacker `20:50:0D:E7:1C:38`, all 6 victims hang off it; 1 probe of
  ~1077 reached the root during the attack. FR attacker z −24.0, PDR 0.995 → 0.000, 6 victims. Clean.
  (Topology check must be run with `--dir datasets/exports` + filters; pointed at the cell folder it
  reports "No captured telem CSVs" — tool quirk, not data.)
- **#8 tree · G402 · jitter** — see VERIFICATION #1 below.
- **#9 tree · G402 · stationary** — ⚠️ **Two boards dropped out mid-run.** `704B…` (child-4) logged only
  304 s and stopped ~53 s before the attack (no attack/cooldown windows). `2805…` (child-5) stopped
  97 s into the attack (no cooldown). `ED80…` lost its parent each time and re-parented
  (704B → 2805 at −50 s, → root at +113 s), so it changes parent **inside** the analysed windows.
  Root arrivals: 2 victims never returned in cooldown (71 % of baseline). The attack verdict still
  holds (FR attacker z −8.9, PDR 0.995 → 0.552, 2 victims), but the cell has 7 of 8 nodes and broken
  cooldowns. **Recommend capturing r2** before relying on this cell.

**Verdict: 7 ✅ usable · 1 ⚠️ partial (highload, known) · 1 ⚠️ degraded (tree/G402/stationary → re-capture r2)**

<!-- ════════════════════════════════════════════════════════════════════════════════ -->
<!-- ════════════════════════════════════════════════════════════════════════════════ -->

## 🔎 VERIFICATION #1 — Oct 2, 2026 · ~7:30 PM — blackhole · tree · G402 · jitter

> **Requested by:** Angelo · **Laptop:** Angelo's · **Commit:** `9aec136`
> **Request:** "check if our dataset is correct, and the verifier, and also check if the analysis,
> eda timeseries are all correct for tree blackhole, g402 jitter. and why there is infinity value"

| Attack | Topology | Location | Scenario | Repeat | Captured | Files |
|---|---|---|---|---|---|---|
| blackhole | tree | G402 | jitter | r1 | Oct 2, 6:56–7:24 PM | 9 (8 telem + root arrivals) |

| Check | Result | Detail |
|---|---|---|
| Integrity (`validate_integrity.py`) | ✅ PASS 9/9 | 10 Hz, 100 % coverage, trimmed = raw |
| Jitter fired | ✅ YES | baseline 331 s / attack 206 s (nominal 300/180), cooldown 120 s |
| Topology (`verify_topology.py`) | ✅ tree, depth 2 | 1 victim under attacker `20:50:0D:E7:1C:38` |
| Attack (`verify_attack.py`) | ✅ CONFIRMED 2/2 | FR attacker z −20.3 · PDR −inf (baseline sd 0) |
| Analysis tables | ✅ match exports | 300 s baseline / ~205 s attack / 120 s cooldown per node |
| EDA time series | ✅ correct | attacker FR → 0, victim PDR → 0, root arrivals 6 → 5 |
| EDA PCA / t-SNE | ⚠️ → ✅ FIXED | victim attack windows were dropped; regenerated (see #2) |

### Dataset: correct
- **Integrity:** all 9 files pass (8 node files plus the root's arrivals). Sampling is a steady
  10 Hz with 100 % coverage. The trimmed copies are byte-identical to the raw exports.
- **Jitter fired:** the root ran a 331 s baseline and a 206 s attack, against the normal 300 s and
  180 s. Cooldown was 120 s.
- **Topology:** a real tree, 2 hops deep, all 8 nodes reachable. The attacker is
  `20:50:0D:E7:1C:38` at hop 1, and one victim, `70:4B:CA:25:B7:68`, sits under it at hop 2.
- **Root arrivals:** 6 sources sent probes in baseline. During the attack exactly one went silent
  (the victim) and the other 5 kept delivering. Cooldown recovered to 100 %.
- **The "parent changed during baseline" warning is harmless.** Every node dropped its parent at
  once about 416 s before the attack and rejoined about 22 s later, which is the root rebooting
  when it was flashed last. The analysis uses only the last 300 s of baseline, so none of this
  enters the data. Hop and layer stay constant for every node through baseline, attack and cooldown.

### Verifier: correct
- **ForwardingRatio (attacker):** dropped from 1.0 to 0.0, z = −20. This is the main evidence.
- **PDR:** the victim went from 1.0 to 0.0, and the other 5 children stayed at 1.0. The pooled
  0.835 is about 5 of 6 nodes, so the pooled number matches the per-node rows.
- **IngressEgressDelta FAIL:** expected, and it doesn't affect the verdict because it's a secondary
  feature. Only the attacker changed (0.013 → 0.985), but the row averages all 8 nodes, which
  waters it down to z = 2.26.
- **Verdict:** BLACKHOLE CONFIRMED (2 of 2 primary checks), and the evidence supports it.

### Why there is `-inf`
z = (attack mean − baseline mean) ÷ baseline standard deviation. For PDR and
NeighbourForwardingRatio, every baseline point was exactly 1.000: no probe was lost during
baseline. That makes the standard deviation 0, and any drop divided by 0 is infinite.
`verify_attack.py:305-316` handles this on purpose: it prints ±inf and adds the note
"baseline sd=0 (perfectly stable)". It means any drop counts as an anomaly, not that there's a
bug. No inf values exist in the feature table or the EDA CSVs.

One caution for the write-up: pooled PDR passes only because the baseline was perfect. With one
victim among 6 children, even a little baseline loss would have made it fail. Quote the victim's
per-node PDR (1.0 → 0.0), which the verifier itself recommends.

### EDA time series: correct
- The combined plot shows what you'd expect: the attacker's forwarding drops to 0 only during the
  attack, the victim's PDR drops to 0 only during the attack, root arrivals go from 6 to 5 per
  window, and everything recovers in cooldown. The individual node plots match.
- **Known quirk:** the plots show a 300 s baseline, not the full 331 s, because the analysis keeps
  only the last 300 s. This was already noted in MEMORY on Oct 1.
- **Minor:** 7 of 2,328 ForwardingRatio windows go above 1 (max 3.0), when "forwarded" lands one
  window after "received". The 5-window plots and the verifier average this out.

### Problem found: the PCA/t-SNE plot missed the attack (fixed in #2)
The plot labelled PDR as "constant (no variance)", which is wrong for this run:
1. The victim's 205 attack windows have no LatencyHopRatio, because no probe reaches the root so
   there's no latency to measure.
2. The PCA step drops every row with a missing value, so all of the victim's PDR = 0 rows
   disappear.
3. The PDR values left are all 1.0, so PDR is thrown out as "constant". ForwardingRatio is also
   excluded because it only exists for relay nodes.

So the PCA/t-SNE plot had no attack signal left in it, which is why the phases looked mixed. It's
the same kind of bug as the one fixed on Oct 1, but the earlier fix didn't catch it because only
1 of 6 nodes is a victim here. It doesn't affect the dataset, the verifier or the time series.

**Verdict: ✅ USABLE** — quote the victim's per-node PDR, not the pooled one.

<!-- ════════════════════════════════════════════════════════════════════════════════ -->
<!-- ════════════════════════════════════════════════════════════════════════════════ -->

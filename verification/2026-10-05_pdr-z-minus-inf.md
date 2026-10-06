# Verification: is "PDR z = -inf" acceptable to report in the thesis?

**Date:** oct. 05, 2026
**Verdict:** 🔶 PARTIALLY CONFIRMED — the PASS is valid; the printed `-inf` is not a number to quote.

## The claim

Split into two sub-claims:

1. **The PDR PASS verdict is legitimate** for blackhole / linear / DLSU_Library / stationary. ✅ CONFIRMED
2. **"z = -inf" is fine to write in the thesis as the PDR result.** ❌ CONTRADICTED

## What this means (plain language)

The blackhole really did collapse PDR, and the baseline really was flawless (zero lost probes), so
the verdict holds. But `-inf` is not a measured z-score. It is a placeholder the script prints when
the baseline standard deviation is exactly 0, because z = (attack mean − baseline mean) / sd divides
by zero. Writing "z = −∞" invites the panel question "so your test divided by zero?" Report it as
*z undefined (σ = 0)* and give the raw evidence instead: 2,518/2,518 baseline windows at PDR 1.000,
and the victims at 0.000 and 0.0055 during the attack.

## Evidence

- **[ESP32-Environment/tools/verify_attack.py:305-318](../ESP32-Environment/tools/verify_attack.py#L305-L318)**:
  when `sd == 0` the function skips the z formula entirely, sets `z = float("-inf")` if the attack
  mean is below the baseline mean by more than `eps = 1e-9·(|μ|+1)`, and marks PASS. So `-inf` is a
  **hard-coded flag**, not the result of a calculation. The real test in this branch is "did the
  mean drop at all", which is true here.
- **The script's [_fmt_z](../ESP32-Environment/tools/verify_attack.py#L422-L429)** prints that flag
  as the string `-inf`. That is the value in the pasted table.
- **The zero spread is real and was not created by clipping.** Recomputed from
  `datasets/analysis/blackhole/linear/DLSU_Library/stationary/feature_table.csv` (written oct. 05 11:19):
  - Baseline (Label 0): 2,518 PDR windows across all 6 children, **min = 1.0, 0 windows < 1.0,
    0 clipped** (`_pdr_clipped` = 0). Every probe sent in baseline reached the root.
  - Attack (Label 1): 1,083 windows, mean 0.6676. NODE_B4BFE932FE90 averaged 0.000 and
    NODE_704BCA25B768 averaged 0.0055. The other 4 children stayed at 1.000.
  - Rerunning `verify_attack.py` on that table reproduces the pasted row exactly
    (`1.000+-0.000 (516) 0.669 (222) -inf PASS`). So the paste came from this table.
- **[features.py:790-794](../ESP32-Environment/analysis/features.py#L790-L794)** clips PDR at 1.0,
  which *could* hide variance in principle (a value >1 rounded down to 1). The `_pdr_clipped` count
  of 0 rules that out for this run.
- **PDR is per-window mean-of-ratios**, not ratio-of-sums (it is absent from `RATIO_OF_SUMS`,
  [verify_attack.py:141-145](../ESP32-Environment/tools/verify_attack.py#L141-L145)). So a single
  lost probe anywhere in baseline would have pulled one 5-window block below 1.0 and made sd > 0.
  An sd of exactly 0 therefore means exactly zero baseline loss, not a rounding artefact.
- **Plausibility:** the script's own docstring cites Khan et al. (2022) for ESP-MESH PDR > 97%
  ([verify_attack.py:41-45](../ESP32-Environment/tools/verify_attack.py#L41-L45)). A loss-free
  baseline of about 420 probes per node, with a fixed topology and no attack running, fits that.

## Dataset trace: why σ = 0 (follow-up, same day)

PDR was rebuilt **from the raw exports only**: telemetry `probes_count + retry_count` gives each
probe's seq number, and those were matched against the root's `*_arrivals.csv` on (src_mac, seq_num).
No pipeline code and no windows were used. Folder:
`datasets/exports/blackhole/linear/DLSU_Library/stationary/`. Raw and `trimmed/` have identical
row counts, so trimming removed nothing.

| Phase (root broadcast) | Honest children: sent → received | Root arrivals in phase |
| --- | --- | --- |
| 255 pre-start (65 s) | 6 × 65 = 390 → 390 | 390 |
| **0 baseline (300 s)** | **1,805 → 1,805** (five at 301/301, 2805A5 at 300/300) | **1,805** |
| 1 attack (180 s) | 4 bystanders 721 → 721; victims 704BCA and B4BFE932FE90 **0/180 each** | 721 |
| 3 cooldown (120 s) | 724 → 724 | 724 |

No duplicate (src, seq) pairs, no counter resets, no `_pdr_clipped` rows. **The baseline lost zero
probes in the raw data**, so σ = 0 is a genuine property of the run. It was not produced by filtering.
`verify_attack.py`'s "baseline" is Label 0, which is baseline + cooldown: 2,399 + 960 = 3,359 windows,
or 516 five-window blocks. Both phases were perfect.

Two things the pipeline did handle, which a reader could otherwise mistake for hidden loss:

- **Leading segment at boot (EXCLUDED, correctly).** Before the root's first broadcast every child
  logs `phase_id = 0` for 16–87 s, depending on when it booted. The root logged **none** of those
  seqs, which would read as PDR 0. `preprocess.assign_segments` tags these windows `pre_baseline`
  with Label NaN (feature table: 476 phase-0 + 519 phase-255 windows), so they never enter the
  baseline. The root's arrivals log only starts at phase 255, so those probes have no delivery
  record at all. That means "not logged", not "lost". Had they been kept, the baseline would have
  been contaminated, which is the same failure as the sep. 18 G402 capture.
- **Victim 704BCA shows 0.0055, not 0.000.** That comes from one window at the phase boundary.
  Window 423 is labelled phase 1, but it holds seq 429, which the node sent while still in phase 0
  (raw: phase 0 ended at seq 429) and which the root received. So 1 of 181 attack windows reads
  1.0. True attack-phase delivery for 704BCA is **0 of 180**.

**Correction (same day).** An earlier version of this section claimed "the root never logs the
attacker's own probes". That was wrong. The seq rebuild was applied to the attacker's
`probes_count`, but on the attacker that column means something else.
[blackhole_victim.c:40](../ESP32-Environment/child_node/main/blackhole_victim.c#L40) says "The
attacker does NOT generate its own probes; it only relays other nodes'". Lines
[49](../ESP32-Environment/child_node/main/blackhole_victim.c#L49) and
[388](../ESP32-Environment/child_node/main/blackhole_victim.c#L388) show that its `probes_count` =
**probes received for relay**. The figure of about 2 per second is exactly its two downstream
victims at 1 Hz each: 602 = 2 × 301 in baseline and 360 = 2 × 180 in the attack. There are no
attacker probes to arrive. PDR also leaves out the `blackhole` role by design (features.py rule 1,
`is_child`), which is why F42DC973E618 is absent from the per-node PDR table.

## Re-run prediction: re-trim + wizard verify (tested on a scratch copy)

The `analyze.ps1` Invoke-Analyze/Invoke-Validate chain was replayed on a scratch copy of the raw
export (trim_run → preprocess → features → 3 gates). The dataset folders were not touched.

- **Trim:** every node had 1 boot session, so 0 rows dropped and all 9 files were copied as-is.
  They are byte-identical to the existing `trimmed/`.
- **Feature table:** identical to the existing one, 5,800 × 71.
- **Gate 1 (integrity): PASS**, 9/9. The "phase 0 ran 381–443 s vs nominal 300 s" lines are
  info-level: the boot segment and the real baseline both carry phase_id 0.
- **Gate 2 (topology): FAIL**, because "Baseline re-routing free: NO". The only change is on
  NODE_20500DE71C38, the root's direct child. It lost its parent at t = 66.4 s (layer −1, parent
  00:..:00) and rejoined the root at 92.7 s. Both happened in the **boot segment**, before the first
  phase-255 broadcast at 96.3 s. The real baseline (161–462 s) has no changes on any node.
  `verify_topology.py` counts the boot segment as baseline because it also reads phase_id 0.
  Read as a timeline, it looks like the root restarted shortly before the run (its log starts at
  phase 255), which would also explain why the arrivals log starts at 255. Not confirmed against the
  run log.
- **Gate 3 (attack): CONFIRMED**, same numbers as before, PDR `-inf`.

## Conflicts between sources

None between the code and the data. There is a **methodological soft spot** to state openly.
With σ = 0 the 3-sigma band has zero width (μ ± 3·0 = μ). The test therefore reduces to "any drop
below 1.0 passes", so one lost probe during the attack would also have returned PASS / -inf. The
verdict here is robust anyway: the victims fell to about 0, which is the strongest effect possible.
The *test* is degenerate for this feature, but the *result* is not marginal.

## What remains unverified

- ~~Raw arrivals vs telemetry not cross-checked~~. **Done** in the dataset trace above: zero
  baseline loss confirmed from the raw files.
- Why the root logs nothing before phase 255 is a firmware question that was not checked here.
  The attacker question is resolved: it sends no probes of its own.
- I did not check how Zhukabayeva et al. (2025) handle a zero-variance baseline. Whether the
  paper addresses it is open.

## Suggested thesis wording (not applied anywhere)

> PDR: baseline 1.000 ± 0.000 (2,518 windows, no probe lost); attack-phase victims 0.000 and
> 0.006. The z-score is undefined because baseline σ = 0. Any sustained drop is therefore outside
> the 3σ band, and the victims dropped to the minimum possible value.

Optional script change for the user to decide on: print `σ=0` instead of `-inf` in the z column.

## Sources

- [verify_attack.py:281-355](../ESP32-Environment/tools/verify_attack.py#L281-L355): `stat_verdict`, the sd=0 branch and the normal z path
- [features.py:627-796](../ESP32-Environment/analysis/features.py#L627-L796): how PDR is computed, attributed and clipped
- `datasets/analysis/blackhole/linear/DLSU_Library/stationary/feature_table.csv`: the table the pasted output came from

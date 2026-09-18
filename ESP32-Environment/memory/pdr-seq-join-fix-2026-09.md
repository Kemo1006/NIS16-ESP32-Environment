---
name: pdr-seq-join-fix-2026-09
description: PDR was joined on time windows across boards that share no clock, silently reporting 0.079 on a run whose true baseline is 0.965 — now joined on probe sequence number; also explains the July "weak PDR" that was misdiagnosed as close-node placement
metadata:
  type: project
---

On **2026-09-18**, `tools/verify_attack.py` reported the `blackhole/linear/G402`
run's PDR as **INVALID-BASE** — baseline mean **0.079**, below the 0.50 sanity
floor — and excluded the thesis's core detection feature from the verdict. The
capture was blamed. **The capture was fine; the join was wrong.**

Rebuilt straight from the raw exports, mapping `seq_num` → phase through each
victim's own `probes_count` (no timestamps anywhere), the true per-phase PDR is a
textbook blackhole signature:

| victim | baseline | attack | cooldown |
|---|---|---|---|
| NODE_704BCA25B768 | 1.000 (2/2) | **0.000** (0/180) | 1.000 (120/120) |
| NODE_2805A532D7B4 | 1.000 (2/2) | **0.000** (0/181) | 1.000 (120/120) |
| NODE_20500DE70C80 | 0.943 (379/402) | **0.000** (0/180) | 0.992 (119/120) |

**Why:** every board runs its own boot-relative `esp_timer`, nothing disciplines
them to a common origin, and `preprocess.rebase_time()` rebases each node to *its
own* first sample. `compute_pdr_features` then joined the root's arrivals log to
each victim on `(mac, window_start)` — a **time** key across boards that do not
share time. Measured offsets on G402: **-56 s, +359 s, +361 s** (the root's own
log records an *impossible negative* one-way latency), i.e. window shifts of
**69, 346 and 347 windows**. Each victim's probes were compared against a slice
of the root's log minutes away, so the numerator was near-empty and PDR
collapsed to noise. Single-node features were never affected — which is exactly
why ForwardingRatio/RetryRate/ConsistencyScore/IngressEgressDelta all looked
clean while PDR alone looked broken. The unsynchronised clock was already known
and written up for latency in [[latency-features-recovered]]; nobody had carried
that same constraint across to the PDR join.

**This also corrects a two-month misdiagnosis.** The 2026-07-25 desk test recorded
"baseline PDR ~0.70, modest attack separation" and blamed close-node placement,
recommending the boards be spread across 4 rooms to "widen PDR separation"
([[linear-blackhole-pipeline-verified]]). Recomputing that archived **baseline**
run (no attack) by sequence number gives per-node PDR of **1.000, 1.000, 1.000,
0.994, 0.994** — delivery was already perfect. It looked like 0.70 because those
boards were USB-tethered and booted within seconds of each other, so the offsets
were only ~70-78 s (13-22 window shifts) instead of 346. Same bug, milder. The
room spread is still worth doing for realism and mesh depth, but it was never
the PDR problem.

**How to apply — the fix (implemented 2026-09-18):**

- `preprocess.build_windows` now emits `<counter>_first` / `<counter>_last`, the
  counter's absolute value at each window edge. A window's sequence range cannot
  be recovered from deltas alone.
- `features.compute_pdr_features` joins on **sequence number**, which carries no
  clock — the join the milestones form specified all along ("joining each node's
  outgoing log with the root's probe-arrival log on `(src_node_id,
  sequence_number)`"). It also now: filters to `node_role == "victim"` (the
  attacker emits probes the root never logs in *any* phase, contributing 298
  all-zero baseline rows); gates root liveness on **phase id**, which is
  mesh-broadcast and therefore comparable without a clock, replacing the old
  arrival-time-span check; skips windows with a counter reset; and **raises**
  rather than silently degrading if handed a windowed dataset built by the old
  preprocess.
- **`seq == probes_count + retry_count`.** `victim_main.c:268` advances `seq` on
  every send *attempt* but `probes_count` only on success, counting failures into
  `retry_count`. Verified: 703 probes + 1 retry = 704 = the highest `seq_num` the
  root logged from that victim. Any future seq reconstruction needs both counters.

**Result:** verdict went from *"BLACKHOLE CONFIRMED (1/1 primary, 1 excluded)"* to
**"BLACKHOLE CONFIRMED (2/2 primary signatures exceed 3-sigma)"** — PDR baseline
**0.965 ± 0.167** (n=154), attack mean **exactly 0.000** (n=111), **z = -5.76**.
Every regenerated per-node value matches the independent raw-data ground truth
above. `feature_table.csv` and `windowed_dataset.csv` were both regenerated; raw
exports untouched.

**The habit that caught it:** never validate a suspicious feature against the
pipeline's own output — rebuild it from the raw exports by a route that shares no
code path with the thing under test. See [[thesis-deviate]] (this warrants a new
D-entry) and the strict-data-path rule this sits under.

⚠️ **Still open:** `features.py` sets `WINDOW_SECONDS = 5` commented "must match
preprocess.py's", but `preprocess.py` is **1** (D-9). It only reaches
`TunnelIntensity` / `TunnelBytes`, so it is harmless until the first **wormhole**
run is analysed — fix it before then, or tunnel rates will be understated 5x.

---
name: latency-features-recovered
description: LatencyHopRatio and TunnelLatency are recoverable from existing arrivals data by cancelling the unsynchronised esp_timer offset — no firmware change, no re-capture
metadata:
  type: project
---

`arrivals.csv`'s `latency_us` (`root_main.c:329`) subtracts the **victim's**
`esp_timer_get_time()` from the **root's**. Both clocks start at their own board's
boot and are never synchronised, so the column is `true_latency − (root_boot −
victim_boot)` — large and negative (−194 s seen), which is why it looked unusable.

**Why:** the offset is *constant per (arrivals file, src_mac)*, so it cancels under
any subtraction inside that group. That makes two features that were believed
firmware-blocked computable from data already on disk (implemented 2026-07-26 in
`features.py :: compute_latency_features`):

- **LatencyHopRatio** — subtract the per-(file, src_mac) minimum → relative one-way
  delay ÷ hop count. Baseline·linear gives a flat 2.4–2.8 ms/hop across layers 2–6.
- **TunnelLatency** — spread between the two arrivals of one probe
  (`max−min` over `(file, src_mac, seq_num)` groups of size > 1). Offset cancels
  *exactly*; no estimation. 102 of 109 populated rows land on `gt_label=2`.

**How to apply:** never treat `latency_us` as an absolute value, and never conclude
a feature is firmware-blocked before checking whether the quantity survives a
*difference* of two logged values. Both deviations from the thesis's "Mean RTT" /
"periodic echo messages" wording are written up as D-2 and D-3 in
`thesis-deviate.md`. Related: [[linear-blackhole-pipeline-verified]].

---
name: wormhole-working-state
description: Wormhole attack confirmed working on COM26/COM27; mesh instability degrades signature separation
metadata:
  type: project
---

As of 2026-07-20, the wormhole attack is **confirmed working** with the current
board layout (see [[board-and-attacker-assignments]]):
- Attackers: **COM26 = Node A (exit)**, **COM27 = Node B (entry)**, UART tunnel
  wired COM26↔COM27 (TX2/GPIO17 ↔ RX2/GPIO16 crossed + GND).
- Verified signature in `exports/wormhole/linear_topology/` (212606 run): Node A
  `probes_count`/`tx_count` climb ~180 during the attack (were flat 0 in all
  broken runs), and the root's `arrivals.csv` shows ~180 duplicated
  `(src_mac, seq_num)` pairs during `gt_label=2`, all Node B's (COM27) probes.

**Why it took so long:** the earlier broken runs had a dead B→A UART wire
(missing GND / not crossed). Confirmed the fix with the `uart_link_test/`
loopback firmware ([LINK OK]) rather than 11-min runs.

**Open data-quality issue (do before final submission):** the linear-topology
mesh is unstable (weak 5-hop chain, ROOT LOST, "too many" re-parenting). This
causes (1) heavy baseline duplicate noise from mesh retransmissions (~361 in
baseline vs ~180 in attack — signature not cleanly separated) and (2) negative/
garbage `latency_us` (root↔node clocks unsynced, latency feature unusable).
**How to apply:** for a clean dataset, re-run with better board spacing and/or
`-Topology tree` (default, only verified-stable topology) so baseline has few
duplicates and the attack's ~180 stand out.

# Verification: paper §4.2.7.4 "Predictions Tested and Not Observed"

**Date:** oct. 21, 2026
**Paper:** `Plan/Paper-Editing/1-Working-Copy/All_in_one_CTHESIS3_no_jitter_8boards v4 (Chapter 5 merged and checked, oct. 21, 2026).docx`
**Data:** S:\ checkout at HEAD `e1380b70`. Current `datasets/analysis/**/feature_table.csv`, plus the tables from before the oct. 19 re-analysis, read from git at `6ecbe3e1~1`. Jitter runs are excluded because jitter is out of the paper.
**Verdict:** 🔶 PARTIALLY CONFIRMED. The main conclusion holds. Two sentences are wrong as worded, and one number cannot be traced to any documented method.

## Sub-claims and verdicts

| # | Claim | Verdict |
|---|---|---|
| 1 | Table 3.4 predicted more victim retransmissions (blackhole). Table 3.5 predicted a distorted topology (wormhole). | ✅ CONFIRMED |
| 2 | 22 runs had sniffer coverage: MacRetryRate rose in 8 and did not rise in 14 | 🔶 PARTIALLY CONFIRMED |
| 3 | "...as expected when the attacker still acknowledges every frame at the link layer" | 🔶 PARTIALLY CONFIRMED |
| 4 | Victim retry counts did not change across the attack window in any of the 34 runs analysed | ❌ CONTRADICTED |
| 5 | [PENDING] The latest re-analysis kept MacRetryRate in only 3 runs | ✅ CONFIRMED |
| 6 | No parent switches or layer changes occur during the wormhole phase | ✅ CONFIRMED |
| 7 | Both tables are kept as they were written at proposal time | ❌ CONTRADICTED |
| 8 | The replay tunnel reproduces the duplicate-delivery signature without the topological signature | ✅ CONFIRMED |

## What this means (plain language)

The paragraph's message is right: the sniffer shows no consistent rise in retransmissions, the wormhole changes no parents or layers, and the duplicates appear only during the attack. Three things need fixing before the defense:
- **Claim 7:** Chapter 3 itself says two rows of Table 3.5 were added later.
- **Claim 4:** one run that counts did log victim retries during the attack.
- **Claim 2:** "8 of 22" comes out only under an unwritten "more than 10%" rule, and 6 of the 8 rises are burst runs.

## Evidence

**1. Table predictions: ✅**
- Table 3.4, MAC row: "Retransmission Count | Increase for victim nodes (repeated attempts with no acknowledgment)". This is the prediction.
- Table 3.5 rows: "Hop Count Consistency: nodes report unexpectedly low hop counts", "Parent-Child Validity: relationships violate physical constraints", and "Routing Table Entries". These are the distorted-topology prediction.

**2. 22 / 8 / 14: 🔶**
- The current tables cannot reproduce it. Only 3 non-jitter runs still have MacRetryRate (see claim 5).
- The pre-re-analysis tables at `6ecbe3e1~1` contain **22 campus non-jitter runs with victim MacRetryRate in both baseline and attack**. star/Yuchengco/burst has baseline coverage only. So the run count of 22 checks out.
- **Rule "attack mean > baseline mean":** 11 rose, 11 did not. This does not match the paper.
- **Rule "attack mean > baseline mean by more than 10%":** exactly 8 rose and 14 did not. These are the 8 risers:

| Run | Change |
|---|---|
| linear/Yuchengco/burst | +26% |
| partial_mesh/DLSU/burst | +52% |
| star/DLSU/burst | +24% |
| star/G402/burst | +35% |
| star/G402/stationary | +52% |
| tree/G402/burst | +14% |
| tree/Yuchengco/burst | +37% |
| tree/Yuchengco/highload | +11% |

  The nearest misses are partial_mesh/Yuchengco/stationary (+8%), partial_mesh/G402/burst (+6%) and linear/Yuchengco/highload (+4%).
- No doc, script or commit message in the repo records the rule behind "8 rose". This report reconstructed the 10% rule; it is not documented as the original method.
- **Confound:** 6 of the 8 burst runs rose, against 2 of the 14 non-burst runs. star/G402/stationary was itself captured as "burst" with no burst fired (ARCHIVE.md, oct. 1). A rise that follows the traffic scenario rather than the attack is worth one sentence in the paper.

**3. "Acknowledges every frame": 🔶**
- The mechanism is right. `child_node/main/blackhole_victim.c:15` says the attacker "silently DROPS" probes, and `:42` says "only the application-layer forward/drop decision is altered". The radio has already received the frame (and so ACKed it) before the application decides to drop it.
- "Every frame" overstates it:
  - §3.3.1.2 itself says ACKs "**may** still occur".
  - In the pre-re-analysis tables, the victims' baseline Retry-bit share is already 0.20–0.45. So many frames need a retransmission even with no attack.
  - 802.11 ACKs only frames received with a correct checksum; a failed reception gets no ACK and is retransmitted. This is a secondary summary; the IEEE text is paywalled.
- Accurate wording: "the attacker's radio acknowledges the frames it receives just as it did before the attack."

**4. Retry counts "did not change in any of the 34 runs": ❌**
- `retry_count_delta` is the per-window change in the application send-failure counter. Summed over victims, current tables:

| Run | Baseline | Attack | Cooldown |
|---|---|---|---|
| blackhole/tree/G402/stationary | 0 | 9 | 0 |
| every other non-jitter run | 0 | 0 | 0 |

- In the pre-re-analysis tables, blackhole/tree/G402/highload also changed (214 / 10 / 22).
- "34" cannot be reproduced. There are 36 campus non-jitter blackhole runs; removing exactly these 2 runs leaves 34. If that is where 34 comes from, the sentence leaves out the very runs that contradict it.
- §5.2.4 of the same paper says the victim retry rate is "0.0015 in the baseline, 0.0006 in the attack", which is a change. The current tables give 0.0 / 0.0105 / 0.0 only for tree/G402/stationary and 0 elsewhere, so §5.2.4 likely comes from older tables.

**5. "Only 3 runs": ✅**
- 7 current analysis folders have any MacRetryRate. 4 of them are jitter runs.
- The non-jitter 3 are partial_mesh/G402/burst, star/DLSU_Library/burst and star/G402/stationary.
- This matches `docs/dataset-verification.md:138` and checklist B-mrr.

**6. No parent/layer changes during the wormhole: ✅**
- Across all 15 current wormhole runs, baseline and attack segments, for all non-root nodes:
  - ParentSwitchRate sums to 0.
  - HopChangeCount sums to 0.
  - Window-to-window layer steps total 0.
- The only role and hop changes (e.g. 1C38, 0C80 in linear/G402/burst) are in the pre-baseline idle period.

**7. "Kept as written at proposal time": ❌**
- §3.4.5 of the same paper: "Tables 3.4 and 3.5 record these expectations as they were formulated before data collection, **except for the last two rows of Table 3.5**." Those rows are Duplicate Arrivals and Latency Mismatch.
- §4.2.7.4 drops that exception.

**8. Duplicates without topology change: ✅**
- In all 15 wormhole runs, Node B's windows with a root-side duplicate (TunnelLatency present, which is what DuplicateRate in `tools/verify_attack.py:1519-1534` uses) number:
  - 179–180 in the attack;
  - 0 in the baseline;
  - 0 in the cooldown.
- None of Node B's values are the pre-run phase-255 artifact found earlier today.
- Together with claim 6, this matches the sentence. It also matches §3 line "the mesh does not use this link for routing".

## Conflicts between sources

- §4.2.7.4 versus §3.4.5: claim 7. The §3.4.5 note wins, because it describes what was actually done.
- §4.2.7.4 versus §5.2.4: "did not change in any run" against non-zero retry rates. §5.2.4 also still says "[PENDING: the predictions tested for the wormhole (Table 3.5)]", while §4.2.7.4 already reports them. One of the two sections is stale.
- Paper "22 / 8 / 14" versus current tables: the tables changed (re-analysis `6ecbe3e1` without PCAPs), not the paper. The figure holds only for the old tables, under the 10% rule.

## What remains unverified

- Which rule actually produced "8 rose". The 10% rule reproduces it, but no record of the original method exists.
- Whether 22 / 8 / 14 survives the B-mrr re-run with the PCAPs.
- Whether the burst traffic falls inside the attack window, which would explain the burst-heavy rises. Burst timing was not checked.
- Where "34 runs" comes from.
- Only this S:\ checkout was checked; the OneDrive THESIS3 working copy may hold newer tables.

## Sources

- Paper v4 (path above): §3.3.1.2, §3.4.5, Tables 3.4/3.5, §4.2.7.4, §5.2.4. Text extracted to scratchpad `paper_v4.txt`.
- `ESP32-Environment/child_node/main/blackhole_victim.c:10-45`: how the blackhole drops probes.
- `ESP32-Environment/tools/verify_attack.py:182-200, 1519-1534`: the wormhole signatures and DuplicateRate.
- `ESP32-Environment/docs/dataset-verification.md:138`, `docs/deviations-limitations/THESIS-UPDATE-CHECKLIST.md:78`: B-mrr.
- `git show 6ecbe3e1~1:ESP32-Environment/datasets/analysis/...`: the pre-re-analysis tables (22-run count).
- Secondary summary of 802.11 ACK/retransmission: https://arxiv.org/pdf/1201.0210 and https://inet.omnetpp.org/docs/tutorials/wireless/doc/step7.html

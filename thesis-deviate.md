# 📐 thesis-deviate.md — where the implementation departs from the proposal

> **What this file is:** every place the built system deliberately differs from the
> thesis proposal (*Cross-Layer Dataset Design and Exploratory Analysis of ESP32-Based
> ESP-WIFI-MESH Network*) or the CTTHES2 Milestones Form, with the reason, the measured
> impact, and what it would take to restore literal compliance.
>
> It exists so a panel question — *"the proposal says Mean RTT, why is this one-way?"* —
> has a written answer that was decided in advance, not improvised at the demo.
>
> `analysis/preprocess.py` and `analysis/features.py` cite this file by name.

---

## D-1 · Telemetry sampling rate: capture at 10 Hz, analyse at 1 Hz

| | |
|---|---|
| **Thesis says** | "Raw telemetry logs collected at **1 Hz**" (§4.2.4.1; Tables 4.4/4.5 list every metric at 1 Hz). |
| **We do** | Firmware samples at **10 Hz** (`SAMPLING_INTERVAL_MS 100U`, `mesh_config.h:327`). `preprocess.py` then **downsamples onto a 1 Hz grid** before windowing. |
| **Why** | A 1 Hz raw rate gives only 5 samples per 5-second window, so a single dropped sample costs 20% of a window and trips the "too few valid samples" discard. Capturing 10× and decimating keeps the thesis's 1 Hz analysis rate while making window formation robust — on the 2026-07-25 baseline·linear run only **6 of 583 windows (1.0%)** were discarded. |
| **Net effect on the thesis** | **None.** Everything downstream of `preprocess.py` sees the specified 1 Hz series. The extra resolution is discarded, not analysed. |
| **To restore literally** | Set `SAMPLING_INTERVAL_MS` to `1000U` and re-flash. The pipeline needs no change — the downsampler becomes a no-op. |

The preprocessing report prints `Rows downsampled to 1Hz grid: N` on every run so this is
never silent.

---

## D-2 · LatencyHopRatio (Eq 4.14): relative one-way delay, not Mean RTT

| | |
|---|---|
| **Thesis says** | Eq 4.14 = **Mean RTT** ÷ hop count, "computed from probe-response exchanges between victim nodes and the root". |
| **We do** | **Relative one-way delay** ÷ hop count. |
| **Why** | There is no response leg to time. Victim→root probes are one-way (`victim_main.c` probe generator); the root logs an arrival and sends nothing back, so **no round trip physically exists** in the captured data. |

**How the one-way figure is recovered.** `root_main.c:329` logs
`latency = now - pkt->send_ts_us`, where `now` is the *root's* `esp_timer_get_time()` and
`send_ts_us` is the *victim's*. Both clocks start at their own board's boot and are never
synchronised, so the raw column is

```
latency_us = true_one_way_latency − (root_boot − victim_boot)
```

— the truth plus a large constant offset, and **hugely negative in practice** because
children are powered before the root (−194 s on the 2026-07-20 wormhole run). Used raw it
is meaningless.

The offset is **constant per (arrivals file, src_mac)**, so subtracting that group's
minimum cancels it, leaving delay relative to that node's fastest observed delivery in the
run. Implemented in `features.py :: compute_latency_features`.

**Measured result — 2026-07-25 baseline·linear**, median LatencyHopRatio per layer:

| layer | hops | ms/hop |
|---|---|---|
| 2 | 1 | 2.72 |
| 3 | 2 | 2.39 |
| 4 | 3 | 2.82 |
| 5 | 4 | 2.44 |
| 6 | 5 | 2.67 |

Flat across the whole chain — which is precisely Eq 4.14's stated normal-operation
interpretation, *"consistent ratio → normal multi-hop forwarding"*. The proposal's
expected band is 10–30 ms/hop, but that is an a-priori estimate for a **round trip**; a
one-way leg on this hardware is roughly half an RTT, and these boards are faster than the
estimate assumed. **The discriminative property the feature exists for — delay that does
not match reported path length — is fully preserved**, because it depends on the ratio
varying, not on its absolute scale.

**Limits, stated plainly.** The zero point is per-node and per-run, so values are *not*
comparable in absolute terms across nodes or across runs; only the shape (ratio vs. hop
count, and its change over phases) is. Clustering uses standardised features, so this does
not affect M9/M10.

| | |
|---|---|
| **To restore literally** | Add a root→victim response message and have the victim log mean RTT into its telemetry row. This is a **firmware change that would invalidate every run already captured** — deferred to CTTHES3 (*Extended Experimental Runs*) rather than re-collecting the matrix. |

---

## D-3 · TunnelLatency: duplicate-arrival divergence, not UART echo RTT

| | |
|---|---|
| **Thesis says** | Table 4.11: "Round-trip latency of the tunnel itself, measured using **periodic echo messages**." (No equation number — the entry is descriptive.) |
| **We do** | The **latency divergence between the two arrivals of one probe** at the root: `max(latency_us) − min(latency_us)` over each `(arrivals file, src_mac, seq_num)` group of size > 1. |
| **Why** | The A↔B tunnel is a **one-way UART write** (B → A, `wormhole_victim.c :: tunnel_forwarder_task`). No echo frame is defined or sent, so no tunnel round trip exists to measure. |

What *does* exist is the signature the Milestones Form itself names for the wormhole:
*"the same logical probe arrives at root twice — once via slow multi-hop, once via fast
wormhole shortcut, with a **measurable latency mismatch**."* `root_main.c:316-320`
deliberately does **not** de-duplicate wormhole copies precisely so both arrivals survive
into `arrivals.csv`.

**This is a real measurement, not an estimate.** Both duplicate rows share one victim clock
and one root clock, so the D-2 offset **cancels exactly** in the subtraction — no
minimum-subtraction, no approximation.

**Measured result — 2026-07-20 wormhole·linear:** 541 duplicate `(src_mac, seq_num)` pairs;
divergence median 12.2 ms, range 1.2–242 ms. In the feature table, **102 of 109 populated
rows fall on `gt_label = 2`** (the wormhole attack window) and only 7 on baseline — the
feature concentrates where the attack is.

**Secondary deviation — keying.** Table 4.12 says tunnel fields are "present only for
attacker nodes". TunnelLatency is instead keyed to the **`src_mac` whose probes were
duplicated**, the same way PDR is keyed. Two reasons: the divergence is a property of the
manipulated *traffic*, and the arrivals row carries **no column marking which copy came
through the tunnel** (the `PROBE_MAGIC_WORMHOLE` flag is checked in firmware but not
logged). TunnelIntensity and TunnelBytes remain attacker-keyed as specified.

| | |
|---|---|
| **To restore literally** | Define an echo frame A→B over the existing (already bidirectional) UART link and have B time the round trip. Also log the wormhole-copy flag as an `arrivals.csv` column, which would additionally allow *signed* divergence — distinguishing "tunnel faster" from "tunnel slower". Both are CTTHES3 items. |

---

## D-4 · verify_topology.py excludes the mesh-formation window

| | |
|---|---|
| **Milestones Form says** | M3: "Each topology converges to its intended parent-child structure within 60 seconds" **and** "Mesh remains stable through a full 5-minute baseline phase (no spontaneous re-routing)." |
| **We do** | Parent/layer changes in the first `PHASE_STABILISE_S` (60 s) of a node's own log are counted as **formation**, not baseline re-routing. Reported separately, never hidden. |
| **Why** | These are two distinct criteria and the tool was conflating them. `phase_listener.c:33-34` stamps rows `PHASE_ID_BASELINE` **before the root's first broadcast arrives**, so a node's *initial parent acquisition* was being counted as a baseline re-route. On the 2026-07-25 baseline·linear run all 6 changes occurred at t = 0–12.8 s — inside the formation window, with **zero re-parenting for the remaining ~470 s**. The mesh was stable; the tool said otherwise. |
| **Net effect** | That run now reports `Converged within 60s: YES` / `Baseline re-routing free: YES`, which is what the data shows. The excluded count is printed on its own line and `--stabilise-s 0` restores the old behaviour for audit. |

---

## Not deviations (recorded so they aren't mistaken for gaps)

- **ForwardingRatio / IngressEgressDelta / ConsistencyScore are NaN in baseline and
  wormhole runs.** They are relay-node features and the only relay in this testbed is the
  blackhole attacker. They populate on its windows in a blackhole run (155/884 rows,
  2026-07-25 blackhole·linear). Correct by design, per thesis §4.2.4.
- **TunnelIntensity / TunnelBytes / TunnelLatency are NaN outside wormhole runs.**
  Table 4.12: "present only for attacker nodes during topology-distortion runs; for all
  other nodes and phases these fields are null or zero."
- **M7's "no feature is uniformly NaN" applies to the assembled dataset**, not to any one
  run. Per run type: baseline 10/16 populated, blackhole 13/16, wormhole 13/16 — and
  **16/16 across the combined matrix**, since every feature is populated by at least one
  run type.

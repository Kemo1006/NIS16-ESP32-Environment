# NIS16 — Technical Terms & Feature Glossary

Every name, its full form, unit, and plain meaning — so you can say them with confidence. Companion to [DEFENSE-PREP.md](DEFENSE-PREP.md). Source: paper Tables 4.11/4.12, Equations 4.2–4.17, and the firmware CSV schema (`csv_logger.c`).

**Pronounce the acronyms in full at least once:**
- **RSSI** = *Received Signal Strength Indicator* (how strong the received radio signal is)
- **dBm** = *decibel-milliwatts* (the unit RSSI is measured in — always negative; closer to 0 = stronger. −40 = strong/near, −80 = weak/far)
- **PDR** = *Packet Delivery Ratio*
- **MAC** = *Medium Access Control* (layer 2)
- **PHY** = *Physical layer* (layer 1 — the radio)
- **MAC address** = the 6-byte hardware ID of a board (e.g. `F4:2D:C9:73:E6:18`) — different meaning from the MAC *layer*

---

## 1. Raw telemetry — what the firmware logs every sample (the vocabulary base)

Each node writes a `*_telem.csv` with **11 columns**; the root also writes `*_arrivals.csv` with 3 extra. These are the raw inputs; the 16 features are computed *from* them.

| Column | Full name / meaning | Unit |
|---|---|---|
| `timestamp_us` | Local timestamp since board boot | microseconds |
| `node_id` | Which board (e.g. `child_node2`, `root_node1`) | — |
| `role` | root / victim / attacker | — |
| `layer` | Mesh **layer** = hop-level in the tree (root = layer 1; each hop down = +1) | integer |
| `parent_mac` | MAC address of this node's **parent** (the node it routes up through) | MAC |
| `rssi_dbm` | Signal strength to the parent | dBm |
| `retry_count` | Cumulative **MAC-layer retransmissions** (how many sends had to be repeated) | running total |
| `tx_count` | Cumulative transmissions sent | running total |
| `probes_count` | Cumulative probe packets received | running total |
| `phase_id` | Experiment phase 0–4 (baseline / blackhole / wormhole / cooldown / end) | — |
| `gt_label` | **Ground-truth label**: 0 = normal, 1 = blackhole, 2 = wormhole | — |
| `src_mac` *(arrivals)* | Original sender of a probe the root received | MAC |
| `seq_num` *(arrivals)* | Sequence number of the probe (used to count unique deliveries) | integer |
| `latency_us` *(arrivals)* | root-receive-time − victim-send-time (carries a clock offset) | microseconds |

> **Attacker counter overloading (know this):** on the blackhole attacker, `probes_count` = probes *received*, `tx_count` = probes *forwarded*, `retry_count` = probes *dropped*. That's how one node's telemetry proves 720 received / 720 dropped / 0 forwarded.

---

## 2. The 16 features — grouped by the layer they represent

Names as they appear in the **feature table** (`feature_table.csv`, Table 4.12). "Normal vs anomaly" = what the value looks like benign vs under attack.

### PHY layer (the radio) — signal behavior
| Feature (column) | Say it as | Unit | Meaning | Normal → Anomaly |
|---|---|---|---|---|
| `RSSI_mean` | RSSI Mean (Eq 4.9) | dBm | Average signal strength in the 5 s window | Decreases predictably with hop count |
| `RSSI_var` | RSSI Variance (Eq 4.10) | dBm² | How much the signal fluctuates | Low = stable link; high = interference/instability |
| `RSSI_stability` | RSSI Stability Duration (Eq 4.11) | seconds | Longest stretch where RSSI stayed within ±3 dB of the mean | Long = steady; short = fluctuating |

### MAC layer — link reliability
| Feature | Say it as | Unit | Meaning | Normal → Anomaly |
|---|---|---|---|---|
| `RetryRate` | Retry Rate (Eq 4.4) = Δretry_count / Δtx_count | ratio 0–1 | Fraction of sends that needed a retransmission | <0.05 normal → >0.15 link stress (e.g. 0.004 → 0.165 in blackhole) |

### Network layer — forwarding & topology
| Feature | Say it as | Unit | Meaning | Normal → Anomaly |
|---|---|---|---|---|
| `ForwardingRatio` | Forwarding Ratio (Eq 4.2) = Δforward / Δrecv | ratio | Share of received transit packets a node forwarded | ~1.0 normal → ~0.0 blackhole (**primary blackhole indicator**) |
| `IngressEgressDelta` | Ingress–Egress Delta (Eq 4.3) = Δrecv − Δforward | packet count | Packets absorbed (received but not forwarded) | ~0 normal → >0 absorption (blackhole) |
| `PDR` | Packet Delivery Ratio (Eq 4.5) | ratio 0–1 | Unique probes reaching root ÷ probes sent by victim | ~0.94 normal → ~0.08 blackhole |
| `ParentSwitchRate` | Parent Switch Rate (Eq 4.6) | events/second | How often a node changed parent | ~0 = stable topology → high = instability |
| `LayerChangeCount` | Layer Change Count (Eq 4.7) | count | Times the node's layer (hop level) changed | 0 = stable → >0 = re-routing/instability |
| `HopStabilityDuration` | Hop Stability Duration (Eq 4.8) | seconds | Longest stretch with same (layer, parent) | Long = stable → short = distortion |

### Cross-layer — the "broken relationship" detectors
| Feature | Say it as | Unit | Meaning | Normal → Anomaly |
|---|---|---|---|---|
| `RSSI_Hop_Diff` | RSSI–Hop Inconsistency (Eq 4.12–4.13) | dB | \|observed RSSI − expected RSSI for that layer\| | <5 dB consistent → >10 dB physical-logical mismatch (wormhole) |
| `LatencyHopRatio` | Latency–Hop Inconsistency (Eq 4.14) | ms per hop | End-to-end delay ÷ hop count | 2.4–2.8 ms/hop flat = normal → abnormally low = shortcut (wormhole) |
| `ConsistencyScore` | Forwarding Consistency Score (Eq 4.15) = \|1.0 − ForwardingRatio\| | unitless | Deviation of forwarding from ideal | ~0 perfect → →1 severe suppression |

### Auxiliary — tunnel activity (wormhole attacker nodes only)
| Feature | Say it as | Unit | Meaning |
|---|---|---|---|
| `TunnelIntensity` | Tunnel Intensity (Eq 4.16) | messages/second | Rate of tunnel relaying |
| `TunnelBytes` | Tunnel Bytes Transferred (Eq 4.17) | bytes | Data volume through the tunnel |
| `TunnelLatency` | Tunnel Latency | ms | Round-trip time of the out-of-band tunnel |

> **The 5 run-type-dependent ones** (NaN by design outside their run type): `ForwardingRatio`, `IngressEgressDelta`, `ConsistencyScore` (relay/blackhole only) and `TunnelIntensity`, `TunnelBytes`, `TunnelLatency` (wormhole attacker only). See DEFENSE-PREP Q9.

---

## 3. Core networking terms a panelist may drop on you

| Term | What it means here |
|---|---|
| **ESP-WIFI-MESH** | Espressif's Wi-Fi mesh protocol; forms a self-organizing tree of ESP32 nodes over standard Wi-Fi |
| **Node roles** | **Root** = top of tree, gateway/receiver + experiment controller; **Victim/child** = sends probes, logs telemetry; **Attacker** = victim's designated relay that drops (blackhole) or tunnels (wormhole) |
| **Layer / hop** | Distance from root in the mesh tree. "Layer 4" = 4 hops from root. More hops = weaker expected RSSI |
| **Parent / parent switching** | Each node routes up through one parent; changing parent = re-parenting, a sign of topology instability |
| **Probe** | The 1-per-second application packet a victim sends toward the root; the measured traffic |
| **Cross-layer** | Reading PHY + MAC + Network signals *together* in one record — a routing attack shows up in all three at once, which single-layer datasets miss |
| **Window / windowing** | Telemetry aggregated into non-overlapping **5-second windows**; one record per node per window; each window is one clustering observation |
| **Delta (Δ)** | A cumulative counter's change across a window (end − start) — see Eq 4.1 |
| **Baseline** | The normal-operation phase (label 0) used as the reference distribution |
| **Ground truth** | The true label, set from the experiment's phase broadcast — independent of any feature value |
| **Blackhole** | Attack that **drops** forwarded traffic (breaks reception→forwarding) |
| **Wormhole** | Attack that **tunnels** traffic out-of-band to create a false shortcut (breaks physical↔logical topology); shows up as **duplicated** deliveries |
| **SPIFFS / LittleFS** | The ESP32's on-chip flash file system where each board stores its own CSV log |
| **EDA** | *Exploratory Data Analysis* — statistics + plots to examine the dataset before/instead of a predictive model |
| **Clustering (unsupervised)** | Grouping windows by feature similarity *without* using labels; labels only validate afterward (purity, ARI) |
| **Silhouette / Davies–Bouldin** | Internal cluster-quality scores (no labels needed) |
| **Cluster Purity / Adjusted Rand Index (ARI)** | External scores that compare clusters to the ground-truth labels |

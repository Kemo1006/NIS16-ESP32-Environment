---
name: resources-papers-assessment
description: Verdict on the 4 RESOURCES/ papers groupmates picked for attack validation/verification — which fit, which don't, and how to cite them
metadata:
  type: reference
---

Assessed 2026-09-13 (read in full) for the panel's demand #6 (paper-backed attack verification, not our own tool). See [[panel-change-2026-09]]. Team's attacks: blackhole = app-layer forwarding suppression; wormhole = out-of-band **UART** tunnel duplicating probe metadata (A near root, B near victims).

**Cross-cutting caveat:** NONE of the four uses ESP32/ESP-WIFI-MESH — they're ZigBee/RPL/generic-IoT. Cite them for *attack concept + signature + verification method*, and pair with Espressif ESP-MESH docs + Khan et al. 2022 for the platform. Framing must be "behavioral/observable equivalence," not "identical mechanism."

1. **`Implementing_a_Wormhole_Attack...XBee S2C` — Ramírez Gómez et al. 2019 (Revista Colombiana de Computación).** XBee/ZigBee, **raw 802.15.4 frame capture+injection** (KillerBee/Scapy), modifies DSR route-record (hop_count/relay_list/seq). Mechanism DIFFERENT from ours (protocol-level, not app-layer tunnel). BUT defines the **duplicate-packet signature** ("two source-routing packets per data packet") = our duplicate-probe signature, + hop/delay signatures. → **Usable for wormhole SIGNATURE, not method equivalence. Secondary wormhole cite.**

2. **`A-Trust-based-Defence...Blackhole...RPL` — Airehrour et al. 2018 (AJTDE).** Telos-B/Contiki/RPL. A defense paper, but codes blackhole as "keep buffer empty, discard packets, don't report forwards"; trust = delivered/sent (= ForwardingRatio/PDR). Signature matches ours (forwarding-ratio↓, PDR↓, parent/rank churn↑). Central thesis: **testbed experiments are a verifiable validation method for simulation** — strong meta-justification for our hardware approach. Smart-home/building setting. → **Primary blackhole basis (signature + testbed-as-validation). Caveat: RPL, false-rank mechanism.**

3. **`REAL-IoT...GNN...Adversarial Attack` — Zhan et al. 2025 (Imperial College, arXiv 2507.10836).** A **GNN-IDS robustness / adversarial-ML** paper. Its "attacks" = PGD/edge-removal/node-injection vs the detector + DoS/portscan (Kali/hping3/nmap, NetFlow). **Does NOT implement or verify routing (blackhole/wormhole) attacks → WRONG paper for attack verification.** Valuable instead for: **stratified sampling to fix class imbalance** (panel's "balance the dataset"), z-score standardization, distribution-drift testing (≈ our multi-location capture), phased benign/attack timeline + timestamped-log ground-truth labeling. → **Repurpose for DATASET/EDA/BALANCING methodology, NOT attack verification.**

4. **`Real-Time-Detection...Wormhole and Sinkhole...WSN` — Zhukabayeva et al. 2025 (Technologies/MDPI, 13,348).** ZigBee + **GSM/GPRS out-of-band tunnel** between two Pi attacker nodes (R4,R5), encapsulate+relay+reinject via socat/Python. **This is the DIRECT analog of our UART tunnel** → BEST match for our wormhole mechanism. Provides a **citable verification method: 3-sigma rule (|x−μ|>3σ) comparing normal vs attack**, with measured signatures (hop 4→3, delay +40%, false data 20-30%). Deployed across a 4-story office building, smart-building **environmental/air-quality monitoring**, linear topology, antenna-shielding to control topology — matches our school+home indoor scenario. → **PRIMARY wormhole basis + primary verification method.**

**Recommended mapping:** Wormhole ← #4 (primary) + #1 (signature). Blackhole ← #2. Verification method to cite ← #4's 3-sigma normal-vs-attack + #2's testbed-validates-sim. Dataset balance/EDA ← #3 (repurposed). Concrete verification the panel wants: compare our measured signatures against these papers' published expected signatures using a 3-sigma test.

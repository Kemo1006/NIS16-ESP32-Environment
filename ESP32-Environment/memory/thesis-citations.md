---
name: thesis-citations
description: Final curated citation set for the thesis edit — which papers to add, their role/chapter, and paste-ready references (APA, matches existing bib style)
metadata:
  type: reference
---

Curated 2026-09-14 from full reading of the 4 RESOURCES/ papers + the Khan 2022 internet find. Rule (user): **everything we claim must be backed by a proven study.** Verdicts from [[resources-papers-assessment]]. Add/keep these in the thesis; drop nothing silently — REAL-IoT is repurposed, not used for attacks.

## ✅ CORE — load-bearing, must cite
1. **Khan et al. (2022)** — ESP-MESH platform + indoor/outdoor deployment basis (already bib [22]/[25]; reinforce). Supports: Ch1 scenario, Ch3 platform, baseline PDR>97%/loss<1.8%, school+home indoor deployment.
   > Khan, A. U., Khan, M. E., Hasan, M., Zakri, W., Alhazmi, W., & Islam, T. (2022). An Efficient Wireless Sensor Network Based on the ESP-MESH Protocol for Indoor and Outdoor Air Quality Monitoring. *Sustainability, 14*(24), 16630. https://doi.org/10.3390/su142416630
2. **Zhukabayeva et al. (2025)** — PRIMARY wormhole basis (out-of-band tunnel = our UART tunnel) + PRIMARY verification method (**3-sigma normal-vs-attack**) + signatures (hop↓, delay↑, duplicates) + indoor smart-building environmental-monitoring scenario. Supports: Ch3/4 wormhole, verification, EDA thresholds.
   > Zhukabayeva, T., Zholshiyeva, L., Mardenov, Y., Buja, A., Khan, S., & Alnazzawi, N. (2025). Real-Time Detection and Response to Wormhole and Sinkhole Attacks in Wireless Sensor Networks. *Technologies, 13*(8), 348. https://doi.org/10.3390/technologies13080348
3. **Airehrour et al. (2018)** — PRIMARY blackhole basis (drop-after-attract; trust = delivered/sent = ForwardingRatio/PDR; parent/rank churn) + **testbed-as-validation** methodology; smart-home/building setting. Supports: Ch3/4 blackhole, "why hardware testbed validates claims."
   > Airehrour, D., Gutierrez, J., & Ray, S. K. (2018). A Trust-based Defence Scheme for Mitigating Blackhole and Selective Forwarding Attacks in the RPL Routing Protocol. *Australian Journal of Telecommunications and the Digital Economy, 6*(1), 41–59. https://doi.org/10.18080/ajtde.v6n1.138

## 🟡 SECONDARY — cite only for the wormhole duplicate-packet SIGNATURE (different mechanism: raw-frame injection, not our tunnel)
4. **Ramírez Gómez et al. (2019)** — wormhole "routing packet duplication" signature (two packets per data unit) = our duplicate-probe signature.
   > Ramírez Gómez, J., Vargas Montoya, H., & León Henao, Á. (2019). Implementing a Wormhole Attack on Wireless Sensor Networks with XBee S2C Devices. *Revista Colombiana de Computación, 20*(1), 41–58. https://doi.org/10.29375/25392115.3606

## 🔵 REPURPOSE — NOT for attack verification; cite ONLY in the dataset/EDA/clustering chapter
5. **Zhan et al. (2025) REAL-IoT** — supports class-imbalance handling (stratified sampling), z-score standardization, distribution-drift (≈ our multi-location capture), phased benign/attack timeline + timestamped-log ground-truth labeling. Do NOT cite it as basis for blackhole/wormhole correctness.
   > Zhan, Z., Zhou, H., & Haddadi, H. (2025). REAL-IoT: Characterizing GNN Intrusion Detection Robustness under Practical Adversarial Attack. *arXiv preprint* arXiv:2507.10836.

## ⚪ OPTIONAL supporting — node placement / topology justification
6. Indoor deployment optimization (Voronoi + Genetic Algorithm). Optional Ch4 support for controlled node placement. https://arxiv.org/abs/2202.13735

**Bottom line:** the "important" papers = #1, #2, #3 (core) + #4 (signature). #5 belongs in the dataset chapter, not the attack chapter. Pair all attack claims with Espressif ESP-MESH docs + Khan for the ESP32 platform, since none of #2–#5 are ESP-MESH (framing = behavioral/observable equivalence).

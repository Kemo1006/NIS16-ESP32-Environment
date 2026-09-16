# Thesis References - Master List (v2026-09-14)

> **This is the list of NEW / reinforced references for the thesis edit.** For each: full
> citation (APA, matching your bibliography style), its tier, WHERE it goes in the thesis, its
> PURPOSE (the claim it backs), and HOW we actually apply it. Rule: every claim is backed by a
> **proven, peer-reviewed study**. Framing = behavioral/observable equivalence (the attack papers
> are ZigBee/RPL, not ESP-MESH; pair them with Espressif docs + Khan for the platform).
>
> Also recorded in `memory/thesis-citations.md` and `memory/resources-papers-assessment.md`.

---

## TIER 1 - CORE (load-bearing; the thesis leans on these)

### [K] Khan et al. (2022) - platform + deployment scenario  *(already in your bib as [22]/[25])*
> Khan, A. U., Khan, M. E., Hasan, M., Zakri, W., Alhazmi, W., & Islam, T. (2022). An Efficient
> Wireless Sensor Network Based on the ESP-MESH Protocol for Indoor and Outdoor Air Quality
> Monitoring. *Sustainability, 14*(24), 16630. https://doi.org/10.3390/su142416630

- **Where:** Ch1 Overview/Scope, Ch3 (ESP-WIFI-MESH platform), Ch4 (baseline expectation), EDA baseline.
- **Purpose:** proves an ESP32 ESP-MESH network is a *real, working, publishable* testbed, and
  that indoor/outdoor multi-site deployment is legitimate.
- **How we apply it (4 concrete ways):**
  1. **Platform justification** - "ESP-WIFI-MESH on ESP32 is a proven hardware testbed" (they ran
     7-8 nodes across a 100x80 m campus + indoor/outdoor).
  2. **Scenario justification** - our **school + home indoor environmental-monitoring** deployment
     mirrors their campus + indoor sites, so our locations are *chosen*, not random.
  3. **Baseline benchmark** - they report **PDR >97%, loss <1.8%** under normal operation. Our
     baseline (label-0) runs should land near this; it's the "normal" reference our attack
     signatures deviate from. Cite it whenever we state the healthy-mesh baseline.
  4. **Traffic model** - their periodic sensor telemetry justifies our fixed-interval probe model.

### [Z] Zhukabayeva et al. (2025) - wormhole mechanism + verification method
> Zhukabayeva, T., Zholshiyeva, L., Mardenov, Y., Buja, A., Khan, S., & Alnazzawi, N. (2025).
> Real-Time Detection and Response to Wormhole and Sinkhole Attacks in Wireless Sensor Networks.
> *Technologies, 13*(8), 348. https://doi.org/10.3390/technologies13080348

- **Where:** Ch3/4 wormhole design, verification methodology, EDA thresholds.
- **Purpose:** a peer-reviewed precedent that (a) a wormhole = an **out-of-band tunnel between two
  nodes** (theirs is GSM/GPRS; ours is UART - same idea), and (b) attacks are verified by a
  **3-sigma normal-vs-attack** anomaly test.
- **How we apply it:** cite it as the basis for our UART-tunnel wormhole; adopt its **3-sigma
  verification** (our `tools/verify_attack.py`) as the paper-backed way to prove the attack is
  real; compare our measured signatures (duplicates, latency mismatch) to its reported ones
  (hop down, delay +40%). Answers the panel's "verify the attack, cite a paper."

### [A] Airehrour et al. (2018) - blackhole signature + "testbed validates claims"
> Airehrour, D., Gutierrez, J., & Ray, S. K. (2018). A Trust-based Defence Scheme for Mitigating
> Blackhole and Selective Forwarding Attacks in the RPL Routing Protocol. *Australian Journal of
> Telecommunications and the Digital Economy, 6*(1), 41-59. https://doi.org/10.18080/ajtde.v6n1.138

- **Where:** Ch3/4 blackhole design, Ch4 feature justification (forwarding/PDR), methodology.
- **Purpose:** codes blackhole as drop-after-attract; trust = **delivered/sent = ForwardingRatio /
  PDR** - exactly our features. Its thesis is that **hardware testbeds validate simulation claims**.
- **How we apply it:** cite it for the blackhole behavioral model and for why ForwardingRatio/PDR
  collapse is the signature; cite the testbed-validates-claims argument to defend our whole
  hardware-dataset approach to the panel.

## TIER 2 - SECONDARY (cite for one specific point)

### [R] Ramirez Gomez et al. (2019) - wormhole duplicate-packet signature
> Ramirez Gomez, J., Vargas Montoya, H., & Leon Henao, A. (2019). Implementing a Wormhole Attack
> on Wireless Sensor Networks with XBee S2C Devices. *Revista Colombiana de Computacion, 20*(1),
> 41-58. https://doi.org/10.29375/25392115.3606

- **Where:** Ch3/4 wormhole observables.
- **Purpose:** documents the **"routing packet duplication" signature** (two packets per data unit).
- **How we apply it:** cite it for our duplicate-arrival signature (same src_mac + seq_num twice).
  **NOT** for the mechanism (theirs is raw-frame injection, ours is an app-layer tunnel).

## TIER 3 - REPURPOSED (dataset chapter ONLY, not the attacks)

### [RI] Zhan et al. (2025) - REAL-IoT (dataset methodology)
> Zhan, Z., Zhou, H., & Haddadi, H. (2025). REAL-IoT: Characterizing GNN Intrusion Detection
> Robustness under Practical Adversarial Attack. *arXiv preprint* arXiv:2507.10836.

- **Where:** Ch4 dataset design / EDA / clustering ONLY.
- **Purpose:** class-imbalance handling (stratified sampling), z-score standardization,
  distribution-drift testing, phased benign/attack timeline + timestamped-log labeling.
- **How we apply it:** cite it for balancing the dataset across topologies/locations and for the
  z-score step; use its drift idea to justify our multi-location captures.
  **Do NOT** cite it as proof any blackhole/wormhole is correct - wrong attack family.

## TIER 4 - SUPPORTING (recommended additions)

### [V] Indoor deployment optimization (Voronoi + Genetic Algorithm) (2022) - answers the panel's "target deployment" ask
> Distributed approach for the indoor deployment of wireless connected objects by the
> hybridization of the Voronoi diagram and the Genetic Algorithm (2022). arXiv:2202.13735.
> https://arxiv.org/abs/2202.13735

- **Where:** Ch4 §4.2.2 physical deployment / node placement.
- **Purpose:** the panel explicitly said *"find a paper that talks about target deployment."* This
  is a peer-style study on **optimal indoor placement of wireless nodes** - it backs our
  topology/placement choices as principled, not arbitrary.
- **How we apply it:** cite it when we justify where boards go per topology (TOPOLOGIES runbook)
  and to answer the panel's deployment-realism comment.

---

## Reinforced (already in your bibliography - lean on them more now)
These need no new entry; just cite them harder where noted:
- **Sommer & Paxson (2010)** [30] - "why hardware-derived, not simulation" (dataset justification).
- **Ring et al. (2019)** [31] - NIDS-dataset gaps -> our contribution.
- **Bhatti et al. (2024)** [4] - behavior-based wormhole detection -> supports our behavioral-signature framing.
- **Hu, Perrig & Johnson (2003)** [46] - canonical wormhole ("packet leashes").
- **Jain (2010)** / DBSCAN / K-Means refs - already cover the clustering methodology (Tier-3 gap is filled by your existing bib, so we don't need a new clustering paper).

## Is more needed?
Between the 6 above + your existing bibliography, every claim is now covered:
platform (Khan), scenario/placement (Khan + Voronoi), blackhole (Airehrour), wormhole (Zhukabayeva
+ Ramirez), verification (Zhukabayeva 3-sigma), dataset/EDA/clustering (REAL-IoT + your existing
bib). **We deliberately stop here** - piling on unvetted papers weakens rather than strengthens.
If a specific gap appears while editing a chapter, tell me the claim and I'll find a proven source
for exactly that.

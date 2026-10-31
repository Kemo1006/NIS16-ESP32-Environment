# Verification: are slides 12 and 19 of defense deck v13 correct?

**Date:** oct. 31, 2026
**Verdict:** 🔶 PARTIALLY CONFIRMED. Every number is right. Six study links on slide 12 and four cells on slide 19 claim more than the paper says.

## The claim

The two slides made in deck v13 (`Paper/Defense/THESIS3-Defense oct. 30, 2026 (final paper, plain graph guides) v13 (studies and signatures).pptx`) are correct:

- **Slide 12**, "Every run is validated before it counts": the four check cards, the six study cards (authors, year, reference number, what each study shows, which check uses it), the verifier-test panel and the banner.
- **Slide 19**, "Two attacks, two signatures": the 7-row comparison of blackhole, wormhole and benign runs, and the "Same in both" strip.

## What this means (plain language)

Every number on both slides matches the submitted paper, and all six references have the right authors, year and reference number. The weak spots are a few sentences about the studies. For those, the slide followed the verifier code's own source list (`verify_attack.py`), and that list says more than the paper does. If a panel member compares the slide with the paper, these are the lines they could challenge:

1. Zhukabayeva is tied to TunnelIntensity, but the paper says tunnel features have no published counterpart.
2. Hu, Perrig and Johnson are tied to a depth check the paper never cites them for.
3. Karlof and Wagner are given the class-change rule, which is D-23.
4. Ramírez Gómez's proposed signature is presented as a measured fact.

On slide 19, four cells need small wording fixes. Nothing on either slide is a wrong number.

## Sources used

| Source | What it is |
|---|---|
| Paper | `Plan/Paper-Editing/1-Working-Copy/NIS16-Full_Thesis_Document.docx`, the submitted version (same as `6- Submit/…pdf`, per `verification/oct. 30, 2026_defense-deck-v2-check.md`). Cited by section number. |
| Verifier code | `ESP32-Environment/tools/verify_attack.py`: `SIGNATURES` (lines 173-200), `STUDIES` (487-509), `FEATURE_STUDY` (510-515), `CHECK_STUDY` (517-522) |
| Originals on disk | `Resources/` PDFs of Airehrour et al. [70], Zhukabayeva et al. [71], Ramírez Gómez et al. [72], Khan et al. [22] |
| Original fetched | Karlof and Wagner [81], course-hosted copy (UMBC), §5.2 |
| Original not obtained | Hu, Perrig and Johnson [46]: every copy tried was unreachable or empty |

## Slide 12: check cards, panel, banner

| Claim on the slide | Evidence | Verdict |
|---|---|---|
| Signature: attack mean ≥ 3 baseline SDs away in the expected direction, change ≥ 0.10 | Paper 4.2.7.7.1: "more than three baseline standard deviations … in the expected direction … at least 0.10 … at least six attack points". The 6-point rule is left off the card, which is fine. | ✅ |
| Topology: tree rebuilt from parent addresses; a board changing class fails the run | Paper 4.2.7.7.2: rebuilds the tree "from the parent address that every board logs"; "the run fails when the board switches between the two (D-23, D-31)" | ✅ |
| Dataset: every board ≥ 95% of each phase; missing boards graded by role | Paper 4.2.7.7.3: "a board below 95% in any phase is reported as a gap"; "Each gap is graded by the role of the board" | ✅ |
| Scenario: probe rate and burst timing match the scenario | Paper 4.2.7.7.4 | ✅ |
| Checks 3 and 4 are "our own rule, fixed in advance" | Paper 4.2.7.7.3 and 4.2.7.7.4 cite no study. 4.2.7.1: "Thresholds for which no published value exists were set as engineering bounds before the results were examined." | ✅ |
| 0 of 106 placebo; 0 verdicts changed at ±50% (53 runs, 14 settings); 1,000 SDs changed 18 | Paper 4.2.7.1, same numbers | ✅ |
| Banner: rules fixed before any result was read; missing data never becomes a pass or a fail | Paper 4.2.7.1 and 4.2.7.7.5 | ✅ |

## Slide 12: the six study cards

| Tag | Claim on the slide | Evidence | Verdict |
|---|---|---|---|
| Z | Zhukabayeva et al. (2025) [71]: ZigBee testbed; normal vs. attack judged by a 3-sigma rule; the wormhole is an out-of-band tunnel | [71] abstract: "A real-time WSN infrastructure was developed using ZigBee and … GSM/GPRS"; Eq. 21: "anomalous if \|x − µ\| > 3σ"; "hidden tunnels between malicious nodes". Paper Table 4.20 gives [71] as the basis of the statistical test. | ✅ |
| Z | "Check 1: the 3-sigma test; **TunnelIntensity**" | The 3-sigma part is confirmed. For TunnelIntensity, the code maps it to Z (`FEATURE_STUDY`), but **paper 4.2.7.2 says: "The tunnel features have no counterpart in these studies, so they rest on the internal check alone."** | ❌ (TunnelIntensity part) |
| A | Airehrour, Gutierrez and Ray (2018) [70]: a blackhole drops what it should forward, so ForwardingRatio and PDR collapse | [70] p. 44: the blackhole node "commences the discard of packets upon receipt"; they measured packet loss of 60 to 75%. "ForwardingRatio" is our feature name, not theirs. Paper 4.2.7.2: "A collapse in delivery under a placed blackhole is therefore consistent with published hardware results." The verifier's primaries are tagged A in the code. | ✅ (small gloss: they measured loss, we call it ForwardingRatio/PDR) |
| R | Ramírez Gómez, Vargas Montoya and León Henao (2019) [72]: "Duplicate packets are the wormhole's signature" | [72] §3.3: "Routing packet duplication … two source routing packets per data packet". Paper 4.2.7.2: "propose duplicated **routing** packets as a signature … related to the duplicate data arrivals that our tunnel produces, but it is a **proposed** signature and not a measured result." | 🔶 (overstated: proposed, and routing packets, not data packets) |
| R | "Check 1: DuplicateRate, seen by the root" | The code tags DuplicateRate R. STATUS item 9 already flags the paper's D-21 "as in [72]" as a source slip. | 🔶 (same caveat) |
| K | Khan et al. (2022) [22]: a healthy ESP-MESH on ESP32 delivers above 97% | [22] p. 18: "more than 97% RPD, except for node H" (one outdoor node, 100 m from the root) | 🔶 ("except one outdoor node" left out) |
| K | "Check 1: broken baseline = excluded (0.90 bound is ours)" | Paper 4.2.7.1: broken baseline = mean below 0.90 or SD above 0.15 of the mean, "excluded and not counted as a failure"; Khan is "the reference for the baseline phase" (4.2.7.2). The code's `BASELINE_FLOOR` comment ties the floor to Khan. | ✅ |
| KW | Karlof and Wagner (2003) [81]: the attacker's position decides who the victims are | [81] §5.2: "a malicious node behaves like a black hole and refuses to forward every packet she sees"; "Selective forwarding attacks are typically most effective when the attacker is explicitly included on the path of a data flow." Paper 4.2.7.1 cites [81] for measuring at the attacker and the root, "with the boards outside the attacker's path as a control group". | ✅ |
| KW | "Check 2: victims vs. bystanders; **class change fails**" | Victim/bystander roles: the code tags `"victim"` and `"behind the attacker"` with KW. The class-change rule is **D-23**. The paper cites no study for it, and the code tags the tolerance rule E (Espressif docs), not KW. | 🔶 ("class change fails" is D-23, not [81]) |
| H | Hu, Perrig and Johnson (2003) [46]: "Wormhole = a shortcut whose copies arrive with a timing mismatch" | This is the code's `STUDIES["H"]` wording. The paper uses [46] only for the definition (3.3.2: "low-latency out-of-band communication channel … illusion that physically remote nodes are direct wireless neighbors") and for Table 4.5. Paper 4.2.1.3 describes the "different delay" as what *our* wire produces, not as [46]'s claim. The original could not be opened. | ⚠️ (not in the paper, original unverified) |
| H | "Check 2: end A above end B; the gap is reported, not scored" | The code tags `"shallower"` with H. **In the paper, "Node A sat shallower than Node B" is part of the separate setup check (4.2.7.7), not the Topology check, and no study is cited for it.** The paper's "Published definitions" row of Table 4.20 is where [46] belongs (Table 4.5, 4 of 5 criteria met). "Gap reported, not scored" is correct (4.2.7.1). | ❌ (wrong check, uncited in the paper) |

**References:** authors, years and numbers of [22], [46], [70], [71], [72] and [81] all match the paper's reference list. ✅

**Colour legend:** Z and K are "both" (the 3-sigma test and the baseline floor serve both attacks), A and KW are blackhole, R and H are wormhole. This matches each study's role. ✅

## Slide 19: comparison table

| Row | Claim | Evidence | Verdict |
|---|---|---|---|
| How it works (blackhole) | Accepts each probe, then drops it; the sender sees no error | Paper 4.2.7.1: "accepts each probe at the link layer and discards it, so the sender sees no failure" | ✅ |
| How it works (wormhole) | End B also sends each of its own probes over a UART wire to end A, which forwards it: every probe of B arrives twice | Paper 6.2.2: 12,448 of 12,465 (99.86%) reached the root twice, "once through the mesh and once through the tunnel" | ✅ ("every" = 99.86%) |
| Grounded in | [70], [81]; [46], [71], [72]; [22] | Each matches its use in paper 4.2.7 and Table 4.20 ([72] = proposed signature, see R above) | ✅ |
| Scored (blackhole) | ForwardingRatio ↓ at the attacker **+** PDR ↓ of the non-attacker boards | Board scope: Table 6.9 says "PDR of all non-attacker nodes", and the code tests PDR wherever it is defined. **But paper 4.2.7.7.1 says "the PDR of the victims"** (the paper contradicts itself). The "+" is also a problem: paper 4.2.7.7.1 says "A run passes the check when **at least one** primary feature passes", so "+" suggests both are needed. | 🔶 |
| Scored (wormhole) | TunnelIntensity ↑ **+** DuplicateRate ↑ (root, D-21) | Same "at least one" rule | 🔶 ("+" should read "or") |
| Scored (benign) | PDR ≥ 0.90 in both phases | Paper 4.2.7.7.5 | ✅ |
| Supporting | Blackhole: IngressEgressDelta, ConsistencyScore, NeighbourForwardingRatio. Wormhole: TunnelBytes; TunnelLatency and LatencyHopRatio measured, not scored "(no tunnel in the baseline)". Benign: every relay ≥ 90% | Paper 4.2.7.7.1 and 4.2.7.7.5 match. But "no tunnel in the baseline" is only TunnelLatency's reason. LatencyHopRatio's reason is a baseline spread too wide (4.2.7.1); 4.2.7.7.1 covers both as "no usable spread". | 🔶 (reason fits TunnelLatency only) |
| Who is hit | Victims lose every probe, bystanders untouched; wormhole: no one loses probes | Paper 6.2.1: "every one of the 123 victim boards has a mean attack-phase PDR of exactly 0"; bystanders 0.996 → 1.000 (d = 0.09). 4.2.7.4: wormhole non-tunnel boards' PDR 0.9999 in both phases. | ✅ |
| What we measured (blackhole) | 36/36; ForwardingRatio ≈ 1.00 → 0.00; victims 0.998 → 0.000 (d = −29.71); bystanders 0.996 → 1.000 | Paper 6.2.1, 6.3.1, Table 6.9 (1.000 to 1.004 → 0.000 to 0.007), 6.5.1 (36 runs: 4 strong, 27 good, 5 minor gaps) | ✅ |
| What we measured (wormhole) | 36/36; 99.86% twice, none in baseline; median gap 3.9 ms; others' PDR 0.9999 | Paper 6.2.2 (baseline 0 of 20,717; median 3.9 ms), 4.2.7.4 (0.9999), 6.5.1 ("the three checks of the verifier passed in all 36 runs") | ✅ |
| What we measured (benign) | 8/8; PDR 0.9994 to 1.0000 | Paper 4.2.7.1 ("all 8 benign runs were confirmed as clean normal traffic"), 6.2.6 "between 0.9994 and 1.0000 in both phases" | ✅ |
| Clustering (blackhole) | K-Means ARI 0.514 (best possible 0.515); 0.996 on victims only | Paper 6.4.3 and 6.5.1, same numbers | ✅ |
| Clustering (wormhole) | ARI −0.012 to 0.003; "the tunnel shows only in the **ends' own counters**" | ARI confirmed (6.4.6). But the root also sees the tunnel, through duplicate arrivals (DuplicateRate is a root-measured primary). Paper 6.4.6: "what the two ends show, the duplicate arrivals of the tunnelled probes, is not one of the features of the cross-layer set." | 🔶 |
| Clustering (benign) | "Third label in the pooled test: ARI 0.333 (best possible 0.334)" | The numbers are right (6.4.7), but that score belongs to a model that "finds the victim attack windows and nothing else". It says nothing about finding benign runs, so the cell is **misleading** in the benign column. | ❌ (misleading placement) |
| Same in both | No attack-caused route, parent or hop-count change; RSSI stays flat (D-20) | Wormhole: "no parent change and no hop change" (4.2.7.4). Blackhole: "Parent switching … the data show **almost none**" (4.2.7.2), and Fig 4.57c shows one victim that moved parent during an attack (tolerated, D-23). RSSI: every non-attack feature \|d\| < 0.1 (6.3.1). Both attacks are application-layer (D-20, 4.2.1.3). | 🔶 ("no … parent change" should be "almost no") |

## Conflicts between sources

1. **Verifier code vs. paper on which study backs what.** Z → TunnelIntensity, H → end depth and the timing mismatch, and KW → the class rule all come from `verify_attack.py` (`STUDIES`, `FEATURE_STUDY`, `CHECK_STUDY`). The paper says the opposite for the tunnel features (4.2.7.2) and cites nobody for the depth check. **The paper should win on the slides**, because it is the document the panel holds.
2. **Paper vs. itself on the blackhole PDR primary.** 4.2.7.7.1 says "PDR of the victims"; Table 6.9 and the code say all non-attacker nodes. The slide follows Table 6.9 and the code, which is what the verifier actually ran. Worth knowing as a weak spot if asked. Per the repo rule, this belongs in `THESIS-UPDATE-CHECKLIST.md`, but it was not added here because this check only reads.

## Suggested fixes (not applied)

| Slide | Now | Suggested |
|---|---|---|
| 12, Z card | Check 1: the 3-sigma test; TunnelIntensity | Check 1: the 3-sigma test (+ the tunnel idea, built as a UART wire) |
| 12, R card | Duplicate packets are the wormhole's signature | Proposes duplicated routing packets as a wormhole signature (not measured) |
| 12, K card | delivers above 97% | delivers above 97% (all but one outdoor node) |
| 12, KW card | Check 2: victims vs. bystanders; class change fails | Check 2: who is a victim and who is the control (bystanders) |
| 12, H card | timing-mismatch wording; Check 2: end A above end B … | Two colluding nodes tunnel packets over an out-of-band link so distant nodes look like neighbours; "Published definition: Table 4.5, 4 of 5 met". Remove the H tag from the Topology card. |
| 19, Scored | "+" between the two primaries | "or" (one primary passing is enough) |
| 19, Supporting (wormhole) | (no tunnel in the baseline) | (no usable baseline spread) |
| 19, Clustering (wormhole) | only in the ends' own counters | only in the tunnel features (the ends' counters, the root's duplicates), which clustering leaves out |
| 19, Clustering (benign) | Third label in the pooled test: ARI 0.333 … | Not separated: the pooled 3-label score (0.333 of 0.334) comes from finding the blackhole victims only |
| 19, Same in both | no attack-caused route, parent or hop-count change | almost no parent or hop-count change |

## What remains unverified

- **Hu, Perrig and Johnson [46] original.** Copies tried: the UHCL course PDF (connection refused), CMU (404), SciSpace (empty), the JSAC 2006 version at FAMU (404). Whether [46] itself frames the wormhole as a timing mismatch could not be checked. The paper does not say it does.
- **Karlof and Wagner [81].** Checked against a course-hosted copy of the paper (UMBC), not the Ad Hoc Networks publisher PDF. The wording matches the known abstract and section structure.
- Visual layout was checked earlier by PowerPoint render. This report checks content only.

## Sources

- [Karlof and Wagner, course copy (UMBC)](https://courses.cs.umbc.edu/graduate/CMSC691A/Spring04/papers/sensor-route.pdf): §5.2 selective forwarding and black hole
- [Hu, Perrig and Johnson, course copy (UHCL), unreachable](https://sceweb.sce.uhcl.edu/yang/teaching/csci5931WSNfall2007/WSN%20Papers/HuPacketLeashes.pdf); [DBLP record](https://dblp1.uni-trier.de/rec/conf/infocom/HuPJ03.html)
- `Resources/Real-Time-Detection-and-Response-to-Wormhole-and-Sinkhole-Attacks-in-Wireless-Sensor-Networks.pdf`: abstract, Eq. 21 (3-sigma)
- `Resources/Implementing_a_Wormhole_Attack_on_Wireless_Sensor_.pdf`: §3.3 signatures
- `Resources/A-Trust-based-Defence-Scheme-for-Mitigating-Blackhole-and-Selective-Forwarding-Attacks-in-the-RPL-Routing-Protocol.pdf`: p. 44 blackhole behaviour
- `Resources/An-Efficient-Wireless-Sensor-Network-Based-on-the-ESP-MESH-Protocol-for-Indoor-and-Outdoor-Air-Quality-Monitoring.pdf`: p. 18, 97% except node H
- `ESP32-Environment/tools/verify_attack.py:487-522`: the study tags and their mapping
- Paper sections 4.2.7 to 4.2.7.7.5, 6.2.1, 6.2.2, 6.2.6, 6.3, 6.4.3, 6.4.6, 6.4.7, Table 4.20, Table 6.9

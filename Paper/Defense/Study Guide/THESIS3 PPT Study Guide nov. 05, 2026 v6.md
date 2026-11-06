# THESIS3 PPT Study Guide: the evidence behind every slide

- **Deck:** [THESIS3-Defense v18](../Ppt/THESIS3-Defense%20v18.pptx), 64 talk slides + 31 backup slides (65 to 95).
- **Spoken text:** [presenter script for the v18 deck](../Ppt/THESIS3-Defense%20SCRIPT%20nov.%205,%202026%20(v18%20deck).md). This guide does not repeat it. It gives the **proof** for what each slide shows.
- **Deeper explanations:** [THESIS3 Defense Study Guide v22](THESIS3%20Defense%20Study%20Guide%20nov.%2005,%202026%20v22.md). Each slide below points to the section that explains the topic in depth.
- **How to use it:** find your slides in the slide map, then read each slide's evidence table. If a panelist asks "where does that number come from?", the answer is in the **Proven by** column. Read the **Fix before the defense** list as a team first.

## Where the evidence comes from

| Short name | What it is | Where |
|---|---|---|
| **Paper** | The submitted thesis. Every slide number was looked up in it | [NIS16-Full_Thesis_Document.docx](../../../Plan/Paper-Editing/1-Working-Copy/NIS16-Full_Thesis_Document.docx) |
| **Deck check A** | Every number of the deck matched to the paper (about 120 read in context), all slides rendered and checked by eye, reference studies checked page by page | `verification/…_defense-deck-v2-check.md` |
| **Deck check B** | The study cards (slide 15) and the two-signature table (slide 16) against the paper, the verifier code and the original studies | `verification/…_defense-deck-v13-check.md` |
| **#89 to #95** | Claim checks logged in the repository. #89 = the blackhole sniffer capture for the defense; #94 = the attacker's blank PDR; #95 = the "What we found" box | `ESP32-Environment/docs/dataset-verification.md`; full reports in `verification/` |
| **Kyle's wormhole capture check** | All 71 wormhole captures rescanned; the defense capture chosen (linear / DLSU Library / stationary, oct. 7); end A and end B rates per phase | On GitHub only (`origin/THESIS3`, commit `454161cf`, numbered #91 there; this laptop's #91 is a different check). Pull before the defense |
| **Sniffer tools** | `pcap_retry.py` reads the Retry bit per link and phase; `sniffer_main.c` is the listening board's firmware | `ESP32-Environment/tools/pcap_retry.py`; `ESP32-Environment/sniffer_node/main/sniffer_main.c`. ⚠️ `tools/macretry_summary.py` and `docs/data-and-results/macretry_summary.txt`, cited by slides 31, 32, 47, 48, are **not in the repository** |
| **Data** | The feature tables of the 80 runs | `ESP32-Environment/datasets/analysis/<attack>/<topology>/<site>/<scenario>/feature_table.csv` |
| **Code** | Firmware and analysis code | `ESP32-Environment/child_node/`, `ESP32-Environment/analysis/`, `ESP32-Environment/tools/` |
| **Sources** | The original PDFs of the reference studies | `Resources/` (Khan [22], Airehrour [70], Zhukabayeva [71], Ramírez Gómez [72]) |

## Status marks

| Mark | Meaning | What to do |
|---|---|---|
| ✅ | Matches the paper, the data or the source | Say it as it is |
| 🔶 | True, but the slide words it more strongly than the evidence | Use the **safe line** given |
| ❌ | The slide or its notes say something the evidence does not support | Fix the slide, or never say it aloud |
| ⚠️ | Open: not in any record yet, or a team decision is pending | Settle it before the defense |

---

## Fix before the defense

These are the places where the **v18 slide text or its speaker notes** disagree with the evidence. They are sorted by slide. Nothing here has been changed in the deck.

| Slide | Mark | What the slide says now | Problem | Suggested fix |
|---|---|---|---|---|
| 13, 31, 32, 47, 48, 56, 61, 62 | ⚠️ | MAC retry numbers from 26 blackhole and 18 wormhole runs; "Source: tools/macretry_summary.py" | The script and its output are not in the repository (not on this laptop, not on GitHub). This laptop has no blackhole retry result, and the repository's `pcap_retry.py` refuses every wormhole capture ("Only blackhole runs can be fitted from traffic") | Whoever made the numbers pushes the script, the newer `pcap_retry.py` and the outputs. Until then, treat every number as unverifiable |
| 13, 31, 32, 47, 48 | 🔶 | Retry numbers beyond the paper's 7 runs | Not in the submitted paper (the footnotes say so); adviser check open | Say "after submission" every time |
| 2 | 🔶 | "Radio and routing features did not move" | True pooled (\|d\| < 0.1), but RSSI_mean drifts 1 to 4 dB in a few single runs, both up and down (#95) | "Radio and routing features showed no consistent change" |
| 4 | ❌ | Gap 3: "on real ESP32 boards it is undocumented" | Absolute claim; our own [70], [71], [72] ran attacks on real (non-ESP32) hardware | "Attacks on real ESP32 hardware: studied in simulation and on ZigBee/RPL testbeds; no labelled attack dataset from ESP-WIFI-MESH found" |
| 4 | 🔶 | "Khan et al. (ESP32 mesh, delivery above 97%)" | Above 97% at every node **except** outdoor node H (about 96.5%) | "delivery about 97% or higher, normal operation only" |
| 7 | 🔶 | "No published blackhole or wormhole measurement exists on ESP-WIFI-MESH" | Same absolute claim as slide 4 | "We found no published blackhole or wormhole measurement on ESP-WIFI-MESH" |
| 7 (notes) | 🔶 | "Real sensor traffic is future work" | Not one of the paper's five recommendations (7.6) | Say it as our own suggestion, or drop it |
| 8 | ⚠️ | "Yuchengo" | Typo | "Yuchengco" |
| 9 | 🔶 | "5 rounds, 100 ms apart, repeated every 10 s" | Matches the paper, but the firmware sends 5 rounds **on a phase change**, then **1 resend every 10 s** (#91 script check) | "5 rounds at each phase change, then a reminder every 10 s" |
| 9 | 🔶 | "label 255, excluded" | 255 is the boards' **phase ID** ("no phase heard yet"); in the feature table the Label of those windows is **blank** (#93) | "phase 255, no label, excluded" |
| 11, 62 | 🔶 | Yuchengco "semi-outdoor"; "three campus sites (one semi-outdoor)" | Paper 1.4 says the 3 sites are **indoor** | Keep "semi-outdoor" only if the team agrees; then say it differs from 1.4 |
| 13 | 🔶 | "RetryRate stays near 0" | True on ordinary boards; on wormhole end B it rises to about 0.50 (tunnel frames, paper 6.3.2) | "stays near 0 on ordinary boards" |
| 14 (notes) | ❌ | "1,077 received and 1 forwarded … as in the paper" | 1,077 / 1 is **not** in the paper. It comes from the feature table and the verification log. The paper gives "1.000 → 0.001" (Table 4.4) | "matches Table 4.4's 1.000 → 0.001" |
| 15 | ❌ | H card: "a shortcut whose copies arrive with a timing mismatch"; "Check 2: end A above end B" | The paper uses [46] only for the **definition** (Table 4.5). "A shallower than B" is the **setup** check, uncited | "Two colluding nodes tunnel packets so distant nodes look like neighbours; Table 4.5, 4 of 5 met". Remove H from the Topology card |
| 15 | 🔶 | R card: "Duplicate packets are the wormhole's signature" | [72] **proposes** duplicated **routing** packets; it measured nothing at a root | "Proposes duplicated routing packets as a wormhole signature" |
| 15 | 🔶 | K card: "delivers above 97%" | All but one outdoor node | "above 97% (all but one outdoor node)" |
| 15, 22, 23 | ⚠️ | Sensitivity "74 runs", stress test "15 verdicts" | The paper (4.2.7.1) says **53 runs** and **18 verdicts**. 74 / 15 comes from a later re-run that is not in any repository record. The script follows the slides and carries a warning | Team decision: quote the paper (53 / 18), or update the paper and records to 74 / 15. Slides and script must say the same |
| 15 | ❌ | "Four checks, in this order (slides 14–18), then a verdict (19) and a test of the verifier (20)" | In deck v18 they are slides 16 to 20, 21 and 22 | "(slides 16–20) … verdict (21) … test (22)" |
| 16 | 🔶 | "Scored": the two primaries joined by "+" | Paper 4.2.7.7.1: a run passes when **at least one** primary passes | Replace "+" with "or" |
| 16 | 🔶 | "no attack-caused route, parent or hop-count change" | Blackhole: "almost none" (4.2.7.2); Figure 4.57c shows one tolerated parent move | "almost no attack-caused parent or hop-count change" |
| 17 | 🔶 | "Baseline: 60 points of 5 windows"; "passes when both hold" (2 rules) | In attack runs the code's reference is **baseline + cooldown** (all Label-0 windows, checklist B-guide04). The paper also has a third rule: at least 6 attack points (never decided a verdict) | Say "the normal windows" if asked; mention the 6-point floor if asked about "all the rules" |
| 17 (notes) | ❌ | "Zhukabayeva et al. [71]: pool every 5 one-second windows into one point" | Pooling is **our** design; [71] gives the 3-sigma rule only (slide 21 notes say so correctly) | Never credit the pooling to [71] |
| 18 | ⚠️ | "THE LAYOUT CHECK: the rebuilt tree must match the topology we designed" | Not in the paper or any record. Paper's Check 2 = rebuild the tree; a board that switches victim/bystander fails (D-23, D-31). Slide 21 still lists "a board changed class" under FAIL | Team decision; make slides 18 and 21 and the script agree |
| 19 to 21 (notes) | ⚠️ | Speaker notes about [70], [22], [71]/[72] | Left over from the old study slides; they do not describe these slides | Replace with notes for each slide, or present from the script |
| 19 | ⚠️ | "No attacker file = FAILED" | Matches the code (`verify_attack.py` line 827), not the paper's D-32 ("major gap") | Keep the slide; know the D-32 wording if a panelist quotes it |
| 22 | ❌ | "Details: backup slide 21" | The backup is slide 23 | "backup slide 23" |
| 24 (notes) | ⚠️ | "the wormhole phase placement (end A uplink step-up, D-43)" (also in the slide 47 and 48 notes) | The paper's deviations end at D-37; no repository record has a D-43. The slide 47 notes themselves say "add a D-entry and a checklist row before quoting it" | Write the D-entry and the checklist row, or drop the number |
| 25 | ❌ | Comment 8: "wormhole runs alone give 6,469 attack windows" | 6,469 = end B's attack windows only; says nothing about rows per run | "about 4,600 rows per run (369,678 in total); 10,000 per run would need runs more than twice as long" |
| 25 (notes) | ⚠️ | Notes start with D-20, D-12, D-15 facts | Copied from the Chapter 5 slide; only the new citation key belongs here | Write notes for this slide, or present from the script |
| 26 | 🔶 | "A blackhole drops packets and a wormhole tunnels and replays them. What a packet carries does not change how it is dropped or tunnelled" | True of **our** two attacks only; [81] and [71] describe content attacks | "Our two attacks act on forwarding, not content" |
| 26 | 🔶 | "test the detector under different loads" | The study builds no detector (1.4) | "test the analysis under different loads" |
| 26 | ❌ | "The traffic is synthetic" + box 6 "synthetic is a named category … not something we invented" | Ring defines "synthetic" as never crossing a real device (Ring IV.D.1); our traffic is real packets in a test bed = **emulated**, with a synthetic payload | Say "emulated traffic on a real mesh, with a synthetic payload"; cite [31] only for the category |
| 26, 33, 50 (notes) | ⚠️ | No speaker notes | — | Add notes, or present from the script |
| 31 | ⚠️ | "†" footnote | Its RSSI row was removed (v17) | Delete the footnote |
| 31 | 🔶 | Row 4 tests Table 3.4's retransmission prediction with "all links" and the attacker's link | The prediction is about the **victims**; the sniffer summary was not split by role | Say so if asked; one hand-checked run shows no rise on the victim's link |
| 33 | 🔶 | DBSCAN tagged "MAIN METHOD" | Main method in the Chapter 4 plan; the headline numbers are K-Means (0.514 / 0.996), DBSCAN 0.485 / 0.940 | Never credit 0.514 to DBSCAN |
| 33 | 🔶 | "If the methods agree, the pattern is in the data" | On the blackhole with PDR, 4 of 5 agree; spectral does not (≈ 0, Table 6.25) | "Four of five agree; spectral does not" |
| 34 | ⚠️ | "Scores: 4" | Only purity and ARI listed; silhouette is on slide 35, Davies–Bouldin only in the backup | "2", or list all four |
| 37 | ❌ | Title "Why 0.514 is the best possible score" | 0.514 is what K-Means reached; the best possible is **0.515** | "Why 0.515 is the best possible score" |
| 44, 45 | 🔶 | Box-plot guide: whiskers reach 1.5 × IQR; the next slide (Fig 6.6) has whiskers at the 5th to 95th percentiles | v18 put the two slides next to each other | Say it when showing Fig 6.6 |
| 47 | ⚠️ | Retransmission count: "No" (sniffer, 18 runs); "One indicator cannot be measured" | The paper's Table 6.16 says "not measurable" (two indicators cannot be measured); the 18-run numbers are after submission and their source is missing | Keep the paper's row, or footnote the change |
| 51 | ⚠️ | "How to read it" box removed in v18 | The figure has no reading guide on the slide; notes start with a stray "1.7.2013" | Put the box back, or present from the script |
| 53 | ⚠️ | "suplementation" | Typo | "supplementation" |
| 53, 62 | 🔶 | The 8-benign-runs limit was removed from both slides | Still in the paper (6.5.4) and behind Recommendation 2 | Fine to leave off; say it if asked |
| 59 (notes) | 🔶 | Khan's figure "from a multi-day stability test" | The 97% / node H figures are from the **campus** test (every 2 min); the 60 s stability test gave above 98% | "their five-day campus test" |
| 59 | ⚠️ | "(D" | Cut-off bracket where the deviation number was deleted | Delete "(D" |
| 61 | ❌ | "Wormhole: through Duplicate Rate (−0.012 to 0.009)" | That range is the cross-layer clustering score | "Wormhole: only through duplicates at the root; cross-layer features −0.012 to 0.009" |
| 61 | 🔶 | Objective 3 "Achieved" | Paper 7.4: the answer differs by attack | "Achieved; differs by attack" |
| 67 (backup) | ⚠️ | "Obersevation" | Typo | "Observation" |
| 76 to 79 (backup) | ⚠️ | Figure 6.1 and the with/without-PDR pair (78, 79) sit under the B2 (wormhole) divider | They are blackhole figures | Move them after slide 75 |
| 88, 92 (backup) | ⚠️ | Both B4 dividers show the circle label "B3" and a corner "16" | Stale labels | "B4"; delete the corner number |
| 89 to 95 (backup) | ❌ | Titled "Figure 6.30: Sniffer …" | In the paper, Figure 6.30 is the pooled 80-run picture (talk slide 57) | "Sniffer, blackhole: …" / "Sniffer, wormhole: …" |
| 89 to 95 (notes) | ⚠️ | "n = 537, 5,425 and 38 windows; C2 mixes every group" | Copied from the Figure 6.29 slide | Replace, or present from the script's backup table |
| 89 | 🔶 | "It doesn't reach zero, because the attacker still sends its own traffic" | The attacker sends **no probes of its own** (#94); what remains is its other mesh traffic | "the board is still a mesh node; only the relaying stops" |
| 91, 93, 94, 95 | ⚠️ | "How to read it" text | Overflows its box (above and below) | Shorten the text or enlarge the box |
| All | ⚠️ | "NEW SLIDE" / "CHANGED" tags (slides 7, 13, 22, 24, 25, 26, 31, 32, 42, 46, 47, 48, 49, 50, 56, 61, 62, 63, 77) and yellow highlights; a stray "1.7.2013" at the top of many speaker notes | Review marks | Remove before presenting |

---

## Slide map

| Slide | Title | Presenter | Evidence | Deep dive in Study Guide v22 |
|---|---|---|---|---|
| 1 | Title | 1 | ✅ | Part 0 |
| 2 | Overview | 1 | ✅ 🔶 | Part 0, 8.3 |
| 3 | Divider: Chapters 1 to 3 | 1 | — | — |
| 4 | The gap and the objectives | 1 | ❌ 🔶 | 1.1, 1.1a, 1.2 |
| 5 | The theory: an attack breaks a relationship | 1 | ✅ 🔶 | 1.4 |
| 6 | Divider: Chapters 4 and 5 | 1 | — | — |
| 7 | Our testbed and what it follows | 1 | ✅ 🔶 | 2.1, 2.2, 12, 13.3 |
| 8 | Testbed Deployments Across Locations | 1 | ⚠️ | 2.8 |
| 9 | How one run works | 1 | ✅ 🔶 | 2.3 |
| 10 | Two attacks, emulated at the application layer | 1 | ✅ | 2.5, 2.6, 1.4 |
| 11 | Topologies as they formed, and the run design | 1 | ✅ 🔶 | 2.7, 2.8 |
| 12 | From raw rows to 16 features | 1 | ✅ | 3.1, 3.1a, 3.2 |
| 13 | Why we read retries at the radio (new in v18) | 1 | ✅ 🔶 ⚠️ | 11.1, 11.2, 11.7 |
| 14 | How to read the dataset: one row | 1 | ✅ (notes ❌) | 3.5, 3.5a, 9.3 |
| 15 | Every run is validated before it counts | 2 | ✅ ❌ ⚠️ | 4.1 to 4.6, 12 |
| 16 | Check 1: Two signatures | 2 | ✅ 🔶 | 4.3, 6.3, 6.4 |
| 17 | Check 1: The 3-sigma rule | 2 | ✅ 🔶 | 4.2 |
| 18 | Check 2: Topology | 2 | ✅ ⚠️ | 4.4 |
| 19 | Check 3: Dataset | 2 | ✅ ⚠️ | 4.4, 4.5 |
| 20 | Check 4: Scenario | 2 | ✅ | 4.4 |
| 21 | The verdict | 2 | ✅ ⚠️ | 4.5 |
| 22 | Testing the verifier | 2 | ❌ ⚠️ | 4.6 |
| 23 | Backup: the 17 sensitivity settings | 2 (if asked) | ⚠️ | 4.6 |
| 24 | Planned vs. actual: the changes that matter (opens with the 37 deviations) | 2 | ✅ ⚠️ | 5.1 to 5.6 |
| 25 | Thesis 2 panel questions: now answered | 2 | ✅ ❌ ⚠️ | 5.3, 3.1, 6.5 |
| 26 | Why synthetic traffic is valid | 2 | ✅ ❌ 🔶 | 2.1, 13.3; deep dive under slide 7 here |
| 27 | Divider: Chapter 6 | 3 | — | — |
| 28 | The dataset: 80 of 80 runs captured | 3 | ✅ | 6.2, 9 |
| 29 | Divider: Blackhole results | 3 | — | — |
| 30 | Blackhole: confirmed in all 36 runs | 3 | ✅ | 6.3 |
| 31 | Blackhole predictions: delivery yes, retries barely | 3 | ✅ 🔶 ⚠️ | 6.6, 11.7 |
| 32 | Blackhole: the real MAC retry rate (new in v18) | 3 | ⚠️ | 11.7 |
| 33 | Five methods, five ideas of a group (new in v18) | 3 | ✅ 🔶 | 7.1, 7.2, 7.5 |
| 34 | Clustering: how the data were asked to sort themselves | 3 | ✅ ⚠️ | 7.1 to 7.4 |
| 35 | How to read the clustering scores | 3 | ✅ | 7.3 |
| 36 | Blackhole clustering: PDR carries all the separation | 3 | ✅ | 7.5, 7.7 |
| 37 | Why 0.514 is the best possible score | 3 | ❌ (title) | 7.6 |
| 38 | PCA and t-SNE: how to read the pictures | 3 | ✅ | 7.8 |
| 39 | Figure 6.22: PCA and t-SNE, FULL set (blackhole) | 3 | ✅ | 7.8 |
| 40 | Figure 6.23: the same windows without PDR | 3 | ✅ | 7.8 |
| 41 | Divider: Wormhole results | 4 | — | — |
| 42 | Wormhole: confirmed in all 36 runs | 4 | ✅ | 6.4 |
| 43 | Figure 6.4: hops skipped by the tunnel | 4 | ✅ | 6.4 |
| 44 | How to read box plots and Cohen's d | 4 | ✅ | 6.8 |
| 45 | Figure 6.6: spread between the two copies of a probe | 4 | ✅ 🔶 | 6.4 |
| 46 | Figure 6.12: wormhole feature distributions by phase | 4 | ✅ | 6.8 |
| 47 | Wormhole predictions: traffic yes, radio and routing no | 4 | ✅ ⚠️ | 6.6 |
| 48 | Wormhole: the real MAC retry rate (new in v18) | 4 | ⚠️ | 11.8 |
| 49 | Wormhole and pooled clustering | 4 | ✅ | 7.9, 7.10 |
| 50 | Why the wormhole hides from cross-layer features | 4 | ✅ ⚠️ | 7.9, 6.8 |
| 51 | Figure 6.25: PCA and t-SNE of the wormhole runs | 4 | ✅ ⚠️ | 7.9 |
| 52 | Divider: Benign runs and both attacks | 4 | — | — |
| 53 | Benign runs: no attack signature | 4 | ✅ 🔶 ⚠️ | 6.7, 6.8 |
| 54 | Can one feature decide it? The single-feature audit | 4 | ✅ | 6.5 |
| 55 | EDA: only the delivery of the victims moves | 4 | ✅ | 6.8 |
| 56 | Discussion: the attacks live in the data plane | 4 | ✅ 🔶 ⚠️ | 7.11 |
| 57 | Figure 6.30: pooled 80 runs, FULL set | 4 | ✅ | 7.10 |
| 58 | Figure 6.31: pooled 80 runs, PDR removed | 4 | ✅ | 7.10 |
| 59 | Compared with published studies | 4 | ✅ 🔶 ⚠️ | 12, 7.11 |
| 60 | Divider: Chapter 7 | 4 | — | — |
| 61 | The three objectives, answered | 4 | ✅ ❌ 🔶 | 8.3 |
| 62 | Limits and what should come next | 4 | ✅ 🔶 | 8.4, 8.5 |
| 63 | Findings and contributions | 4 | ✅ 🔶 | 8.4 |
| 64 | Thank you | 4 | ✅ | 8.6 |
| 65 to 95 | Backup figures (67 Fig 4.58 and 77 Fig 6.24 moved here; 88 to 95 sniffer figures, new) | any | ✅ 🔶 ⚠️ | see the backup table |

---

# Part A: Chapters 1 to 3 (slides 1 to 5, Presenter 1)

## Slide 1: Title

**On the slide:** thesis title, NIS16, the four members, adviser Mr. Gregory G. Cu.

| Claim | Proven by | Mark |
|---|---|---|
| Title "Cross-Layer Dataset Design and Exploratory Analysis of an ESP32-Based ESP-WIFI-MESH Network" | Paper title page | ✅ |
| Adviser Mr. Gregory G. Cu | Paper title page | ✅ |

## Slide 2: Overview

**On the slide:** what we built (8 boards, 2 emulated attacks, 80 runs), what we checked (72 of 72 confirmed, 8 of 8 benign), what we found (blackhole through PDR, wormhole through duplicates, radio and routing flat).

| Claim | Proven by | Mark |
|---|---|---|
| 8 ESP32 boards: 1 root + 7 children | Paper 4.1; Deck check A | ✅ |
| 4 topologies × 3 sites × 3 scenarios: 80 runs | 72 attack runs + 8 benign (paper 6.1, Table 6.1); 36 + 36 + 8 | ✅ |
| Both attacks confirmed in 72 of 72 | Paper 7.3: 72 passed (67 complete, 5 minor gaps); Tables 6.9 and 6.11 | ✅ |
| No attack signature in 8 of 8 benign runs | Paper 6.2.6: 0 of 21 evaluable checks passed | ✅ |
| Blackhole: visible through PDR | #95: victims' attack PDR 0 in 21,733 of 21,733 windows; paper 6.2.1 | ✅ |
| Wormhole: visible through duplicate arrivals | #95: end B duplicates in 5,389 of 5,390 attack windows (30 runs on this laptop), 0 in baseline and cooldown; paper 6.2.2: 99.86% | ✅ |
| Radio and routing features did not move | #95: routing \|d\| < 0.5 in every run; RSSI pooled \|d\| < 0.1, **but** RSSI_mean \|d\| ≥ 0.5 in 6 of 36 victim sets and 3 of 30 wormhole-end sets, both directions | 🔶 |

**Safe line:** "Radio and routing features showed no consistent change."

**If asked:**

- "Your slide says did not move, but RSSI changed in this run." RSSI_mean drifted by 1 to 4 dB in a few single runs, up in some and down in others, so it averages to about zero (victims −0.16 dB). That is drift during a run, not the attack.
- "How can 72 of 72 be confirmed if 5 have gaps?" The 5 are MINOR GAPS: the attack still confirms without the missing boards (slide 19).

## Slide 3: Divider (Chapters 1 to 3)

No claims.

## Slide 4: The gap and the objectives

**On the slide:** three gaps, this study, the general objective, three specific objectives, scope.

| Claim | Proven by | Mark |
|---|---|---|
| Gap 1: most IDS datasets come from simulators or IP networks (KDD, NSL-KDD) | Paper Chapter 2; [29]; Ring et al. [31] | ✅ |
| Gap 2: packet or flow datasets do not hold PHY, MAC and network signals together | Ring et al. [31] (datasets are packet- or flow-based); a flow starts at the IP layer ([RFC 7011](https://www.rfc-editor.org/rfc/rfc7011)) | ✅ |
| Gap 3: "on real ESP32 boards it is undocumented" | Our own references ran real-hardware attacks on other platforms: [70] Telos-B/RPL, [71] and [72] ZigBee | ❌ |
| Setting: campus monitoring, as in Khan et al. | Khan [22] p. 1 (abstract: "deployed at a different location on the college campus"), p. 18 (Section 5.3, 100 m × 80 m campus) | ✅ |
| Khan: "ESP32 mesh, delivery above 97%" | Khan p. 18: "more than 97% RPD, except for node H" (outdoor, about 96.5% in Fig. 20a, p. 19). Their software: PainlessMesh library (p. 13) | 🔶 |
| Objectives unchanged from the proposal | Paper 1.3.2 | ✅ |
| Scope: a dataset and its analysis, not an IDS | Paper 1.4 | ✅ |

**Safe lines:**

- Gap 3: "Blackhole and wormhole attacks have been studied in simulation and on ZigBee or RPL testbeds, but we found no labelled attack dataset from an ESP-WIFI-MESH network."
- Khan: "an ESP32 mesh on a college campus, delivery about 97% or higher, normal operation only."

**If asked:**

- "Khan already ran an ESP32 mesh on campus." Normal operation only: no attacker, no labelled data. We use it as our platform and healthy-baseline reference.
- "Did Khan use your stack?" No: PainlessMesh (their p. 13); we use Espressif's ESP-WIFI-MESH in ESP-IDF.
- "What is a flow?" One summarised conversation between two IP endpoints (packets, bytes, duration). No RSSI, no MAC retries, no mesh parent or hop.

Full defence of this slide: Study Guide v22, 1.1a.

## Slide 5: The theory: an attack breaks a relationship

**On the slide:** four normal relationships (Table 3.7) and the prediction written for each before any data (Tables 3.4 and 3.5).

| Claim | Proven by | Mark |
|---|---|---|
| Normal relationships: received ≈ forwarded, one copy per probe, delay follows hops, placement fits topology | Paper Table 3.7, Section 3.4 | ✅ |
| Blackhole predictions: ForwardingRatio < 1, victims' PDR falls, victims retransmit more | Paper Table 3.4 | ✅ |
| Wormhole predictions: duplicates, latency mismatch, low hop counts, impossible parent links, RSSI not fitting depth | Paper Table 3.5 | ✅ |
| Tables kept as written; Chapter 6 tests every row | Paper 6.2.4, Tables 6.10 and 6.16 | ✅ |

**Careful:** the script says "the topology and radio predictions did not hold". One radio prediction did hold: the blackhole attacker's RSSI stays stable (Table 3.4, row 5; its row was taken off slide 31 in deck v17, see there). Precise version: "the traffic predictions held; the retransmission, topology and radio-change predictions did not."

**If asked:**

- "Why ratios, not raw values?" A ratio measures the broken relationship directly. Raw counts change with the scenario: highload sends 4 probes per second against 1, but forwarded over received is 1.000 in both (paper Table 3.7, 3.5.1).
- "Why emulation?" The ESP32 Wi-Fi stack is closed; an app can read the routing table but not write it (3.5.3, D-20).

### Check-in (Part A)

- **Q:** A panelist says: "Your slide 2 says radio features did not move, but I opened one run and RSSI_mean changed by 4 dB." What is the evidence-backed answer, and what is the safer wording for the slide?

> [!question]- Answer (click to reveal)
> - Pooled over all runs, every RSSI feature moved by \|d\| < 0.1 (paper 6.3.1). In single runs RSSI_mean moved by \|d\| ≥ 0.5 in 6 of 36 victim sets and 3 of 30 wormhole-end sets, **both up and down**, so it averages to about zero (victims −0.16 dB). It is drift during the run (people moving, other Wi-Fi), not an attack effect (#95).
> - Safer wording: "Radio and routing features showed no consistent change."

---

# Part B: The testbed and the data (slides 6 to 14, Presenter 1)

## Slide 6: Divider (Chapters 4 and 5)

No claims.

## Slide 7: Our testbed and what it follows

**On the slide:** the board roles (R, X, A, B, victims, bystanders), "8 ESP32 boards, 3 campus sites, 4 topologies, 3 scenarios", what each part follows, synthetic traffic.

| Claim | Proven by | Mark |
|---|---|---|
| 8 ESP32 boards, 3 sites, 4 topologies, 3 scenarios | Paper 4.1, 4.2.2; Deck check A | ✅ |
| Khan [22]: ESP-MESH on ESP32, campus test, delivery above 97% | Khan p. 18 (campus test); node H exception; PainlessMesh (p. 13) | 🔶 |
| Airehrour [70]: the blackhole definition, 5 of 6 criteria met | Paper Table 4.4 | ✅ |
| Zhukabayeva [71], Hu [46], Ramírez [72]: tunnel, definition (4 of 5 met), duplicate arrivals | Paper Table 4.5 (4 of 5 = our count); [72] **proposes** routing-packet duplication (p. 55) | ✅ 🔶 |
| Karlof and Wagner [81]: the attacker's position decides the victims | [81] §5.2 (course copy): selective forwarding "most effective when the attacker is explicitly included on the path"; paper 4.2.7.1 | ✅ |
| "No published blackhole or wormhole measurement exists on ESP-WIFI-MESH" | Our literature search; an absolute claim | 🔶 |
| Traffic is synthetic: a small test packet about once a second | Paper 4.2.3.1.4 "Probe Generation": a probe every 1000 ms, or 250 ms in highload, holding a sequence number, a send timestamp, a node identifier and a magic value; **no sensor reading** | ✅ |
| "Attacks act on forwarding, not content, and a known steady stream lets us count exactly what went missing" | Reasoning of the slide and its notes. The paper describes the probe (4.2.3.1.4) and the sequence-number join (4.2.3.1.4, 4.2.4) but never uses the word "synthetic" or gives this reason | 🔶 |

**Safe line:** "We found no published blackhole or wormhole measurement on ESP-WIFI-MESH, so we compare direction and size, not exact values."

### Deep dive: why the traffic is synthetic, and why "probes" and not just "packets"

#### 1. A probe *is* a packet. The name says which packet we measure

The mesh carries several kinds of packets at once. Only one kind is counted in the dataset:

| Packet on the air | Sent by | In the dataset? |
|---|---|---|
| **Probe** | Our application on every board, every 1 s (250 ms in highload) | **Yes.** PDR, ForwardingRatio, IngressEgressDelta, latency and duplicates are all counted on probes |
| Mesh control packets (beacons, parent selection, layer assignment) | The ESP-WIFI-MESH stack (the paper's control plane: node discovery, parent selection, layer assignment) | No. The application cannot see or count them |
| Link-layer ACKs | The Wi-Fi radio | No. They are why a victim never notices the blackhole (slide 10) |
| Phase messages | The root (baseline, attack, cooldown) | No. They only drive the schedule |
| Tunnel frames | End B → end A over the UART wire | Counted separately, as TunnelIntensity and TunnelBytes |

"Probe" means a packet sent only to measure the network, like a sonar ping. The paper uses the same word ("probe packets", 4.2.1.2 and 4.2.3.1.4). The probe is 22 bytes (slide 10: a 30-byte tunnel frame = 4-byte "TNL1" + 22-byte probe + 4-byte CRC32).

#### 2. Why not count the packets the mesh already carries?

Because the board's own software cannot see them. Two deviations prove it:

| Deviation | What the platform does | Consequence |
|---|---|---|
| **D-12** (paper 5.3) | The ESP-WIFI-MESH stack relays traffic **out of sight** of the application. Before D-12 only the attacker had relay counters, so an empty column gave the label away | Every node now relays **probes itself** and counts received, forwarded and dropped. Only packets our own code handles can be counted at every hop |
| **D-15** (paper 5.3) | No MAC retry number reaches the application: the only statistics call prints to the log | Real retries could only come from a sniffer, on 7 runs |

A sniffer on the air sees every packet, but it keeps only the first 64 bytes of each data frame, and the probe starts at byte 62 (Study Guide v22, 11.2). So the air capture shows **that** packets flew, not **which** probe they were. Only the probe's own sequence number, read at the root, says which probe arrived, which was lost and which came twice.

#### 3. Why synthetic and not real sensor readings?

| Reason | Evidence | What a real sensor would break |
|---|---|---|
| **Our two attacks, as built, never look inside a packet.** Our blackhole drops every probe it relays; our wormhole copies B's probes. This is true of **our** attacks, not of blackholes and wormholes in general (see 3a) | Paper 4.2.1.2 (attacker drops the probes it relays), 4.2.1.3 (A keeps B's sequence number, timestamp and source MAC; it only swaps the magic value "TNL1" for "PROW") | For these two attacks, nothing gained: a temperature reading would be dropped or copied exactly like a test message |
| **We know exactly what was sent.** Every probe has a sequence number and a fixed send interval | Paper 4.2.3.1.4: delivery = the root's arrivals joined to the sender's counters **on the sequence number** | A sensor that reports only on change, or skips a reading, makes "missing" ambiguous: attack or sensor? |
| **Duplicates are provable.** The same sequence number arriving twice is the wormhole's signature | Paper 6.2.2: 12,448 of 12,465 of B's probes (99.86%) arrived twice | Without a unique number per message, two copies of a reading cannot be told from two readings |
| **Enough samples in a short attack** | Attack phase 180 s: about 180 probes per board (720 in highload). Khan et al. sent one 64-byte packet every 2 minutes, which is 1 or 2 in the same 180 s | 1 or 2 packets cannot fill one-second windows or the 3-sigma test (36 points of 5 windows) |
| **Traffic becomes a controlled variable** | Stationary, burst and highload are set on purpose (paper 4.2.2.5); probe rates measured 1.0, 1.1 and 3.9 per board per second (6.3.3) | Real readings would make traffic volume vary on its own, so volume could look like an attack, or hide one |
| **No clock is needed** | The boards share no clock; delay is measured relative to the sender's fastest delivery (D-2), and delivery by sequence number (4.2.3.1.4) | Real sensor timestamps would need synchronised clocks to compare |

#### 3a. Is dropping or copying the only thing these attacks do? No

The literature, including two of our own references, describes blackholes and wormholes that **do** look at or change what is inside a packet. Synthetic probes are a fair choice **only because our two attacks do not**.

| What the source says | Source | What it means for us |
|---|---|---|
| The black hole is "a simple form" of selective forwarding: a node that "refuses to forward every packet she sees" | Karlof and Wagner [81], §5.2 ([course copy](https://courses.cs.umbc.edu/graduate/CMSC691A/Spring04/papers/sensor-route.pdf), p. 7) | **This is our blackhole.** It drops everything, so content does not matter |
| The "more subtle form": "An adversary interested in suppressing or modifying packets originating from a select few nodes can reliably forward the remaining traffic" | [81] §5.2, p. 7 | Choosing **whose** packets to drop, or **modifying** them, needs the packet's source or content. We did not build this (a grayhole or selective forwarding attack) |
| A sinkhole lets the attacker "selectively suppress or modify packets"; nodes on the path have "many opportunities to tamper with application data" | [81] §5.3, p. 7 | Route attraction plus tampering: excluded by D-20 (no false route) and by the probe having no reading to tamper with |
| "Wormhole attacks would likely be used in combination with selective forwarding or eavesdropping" | [81] §5.5, p. 8 | A real wormhole is often a **means**: get the traffic, then read it or drop some of it. Ours only duplicates |
| The attacker "records a packet, or individual bits from a packet, at one location … tunnels the packet (possibly selectively) to another location, and replays it there" | Hu, Perrig and Johnson [46], [INFOCOM 2003](https://sceweb.sce.uhcl.edu/yang/teaching/csci5931WSNfall2007/WSN%20Papers/HuPacketLeashes.pdf) (quoted from a search excerpt; the original was not opened) | "Possibly selectively" means a real wormhole may choose which packets to tunnel. Ours tunnels every probe of B |
| The wormhole **modified 20 to 30% of the readings** (abstract: false readings in over 30% of cases) | Zhukabayeva et al. [71], Table 7, p. 28; abstract, p. 1 (local PDF in `Resources/`) | **Our own primary wormhole reference attacked the content.** A probe carries no reading, so our dataset **cannot show data falsification** |
| Wormholes and other routing attacks can also be used to eavesdrop, drop or alter traffic | Surveys: [Routing attacks in WSNs (arXiv 1407.3987)](https://arxiv.org/pdf/1407.3987), [Security in WSNs (arXiv 1301.3022)](https://arxiv.org/pdf/1301.3022), [Intrusion detection in WSNs (arXiv 1401.1982)](https://arxiv.org/pdf/1401.1982) | Same point, from secondary sources |

**What this changes in how you defend synthetic traffic:**

- Do **not** say "blackhole and wormhole attacks don't care about content". Say "**our** two attacks, as built, act on forwarding only: the blackhole drops every probe and the wormhole duplicates B's probes. For those two, a probe and a sensor reading are handled the same way."
- Our blackhole is Karlof and Wagner's **simple form** (drop everything). Our wormhole reproduces the **tunnel and replay**, without selective tunnelling, eavesdropping or data modification.
- **The paper already covers this. Point to it:**
  - **1.4 (scope):** "The dataset does not include other routing-layer threats (such as grayhole, Sybil, or selective forwarding), attacks on application payloads, cryptographic exploits, physical tampering, firmware compromise, or adversarial radio interference".
  - **6.5.2 (comparison with [71]):** "The published figure of modified readings has no counterpart here, because this study measures the delivery and the timing of probes and not the integrity of sensor readings."
  - **Chapter 4 wormhole design:** "Probe Duplication, Not Modification: Attackers never modify original packets; they only create additional replicas".
- So content attacks (selective forwarding by source, grayhole, data falsification as in [71], eavesdropping) are **declared out of scope** in the paper. Studying them would need real readings in the packets. Recommendation 4 (7.6) covers "tunnel other nodes' traffic", not content attacks.
- **The paper never links the two decisions:** it excludes payload attacks (1.4) and it uses probes without readings (4.2.3.1.4), but it does not say that the first is what makes the second acceptable. Say it in one sentence if asked: "Because payload attacks are out of scope, the packets do not need real payloads."

#### 4. What to be careful about

- **The paper never says "synthetic".** The reasons above are ours, built from the paper's own facts. Present them as "why we designed it this way", not as a quote.
- **Paper 1.1 can mislead:** it says the campus nodes "send periodic sensor readings". That describes the **setting we model**. Our boards send probes in place of readings.
- **"About once a second" is true for stationary and burst only.** Highload sends a probe every 250 ms (about 4 per second). Say "once a second in most runs".
- **It is a limitation.** We claim nothing about real sensor traffic or real deployments (6.5.4). Real sensor traffic is **not** one of the paper's five recommendations (7.6); if you suggest it, say it is our own suggestion.

#### 5. Ready answers

- **"Is the traffic real?"** "The network, the radio and the attacks are real, on real ESP32 boards. The messages are test packets we call probes, sent at a fixed rate with a sequence number, in place of sensor readings. Our two attacks act on forwarding, not on content: the blackhole drops every probe and the wormhole duplicates them, so a reading would be dropped or copied exactly the same way, and the sequence number lets us count exactly what was lost or duplicated."
- **"Real attackers also read or change the data. Zhukabayeva's wormhole falsified readings. Why can't yours?"** "Correct, and our dataset cannot show that. Our blackhole is the simple form Karlof and Wagner describe, dropping every packet, and our wormhole reproduces the tunnel and replay. Attacks on application payloads are excluded in our scope (1.4), and Section 6.5.2 says the modified readings of [71] have no counterpart here; studying them would need real readings inside the packets."
- **"Why not just measure the normal packets of the mesh?"** "The mesh stack relays its own packets out of sight of our software, and the board gives us no retry count (D-12, D-15). The only traffic we can number, count at every hop and match at the root is traffic our own code sends: the probes."
- **"Why not real sensors?"** "A real sensor sends rarely and irregularly. Khan's nodes sent once every two minutes, which is one or two packets in our three-minute attack. We need a known, steady stream to say exactly what went missing."

**If asked:**

- "Is the traffic real?" See the ready answers above. Khan sends one 64-byte packet every 2 minutes; ours is heavier. Real sensor traffic would be our own suggestion for future work; it is not in the paper's recommendations.
- "Is 'campus' the same as 'indoor'?" The paper (1.4) says indoor; the Yuchengco site is an open area below the building. Say "campus sites" and, if pushed, that Yuchengco is semi-outdoor.

## Slide 8: Testbed Deployments Across Locations

**On the slide:** photos of the board placement at the three sites, now with node labels (ROOT, Node 1 to Node 6). In deck v17 this slide moved before "How one run works".

| Claim | Proven by | Mark |
|---|---|---|
| Board placements per site | Team photos | ✅ |
| "Yuchengo" column | Typo for Yuchengco, still on the slide | ⚠️ |

**Careful:** the speaker notes are a copy of slide 11's. Use the script's slide 8 text.

## Slide 9: How one run works

**On the slide:** the timeline (formation ≥ 60 s, baseline 300 s, attack 180 s, cooldown 120 s), Figure 4.1, five bullets on logging, phases, gates and labels.

| Claim | Proven by | Mark |
|---|---|---|
| Phases 300 / 180 / 120 s; formation at least 60 s | Paper Table 4.1; Deck check A | ✅ |
| Formation "label 255, excluded" | 255 = the boards' phase ID "no phase heard yet" (`mesh_config.h`, `PHASE_ID_UNSET`); in `feature_table.csv` those windows have a **blank** Label (#93) | 🔶 |
| Labels 0 normal, 1 blackhole, 2 wormhole | Paper Table 4.1 | ✅ |
| Every board logs at 10 Hz to flash and a microSD card | Paper 4.2.3 | ✅ |
| Nothing is streamed over the mesh, so an attack cannot erase its evidence | Paper 4.2.3 | ✅ |
| "5 rounds, 100 ms apart, repeated every 10 s" | Paper says so (Deck check A). Firmware: 5 rounds at a phase change, then 1 resend every 10 s (#91 script check, #92: the root's tx_count rises by 5 per phase change only) | 🔶 |
| The attack starts only after the gates pass and START is typed (D-22) | Paper 5.6, D-22; D-24 (failed gate locks START) | ✅ |
| Labels come from the phase schedule, never from a feature | Paper 4.2.4, 6.1 | ✅ |

**Safe lines:** "phase 255, no label, excluded"; "five rounds at each phase change, then a reminder every ten seconds".

**If asked:**

- "Why 255 and not 5?" 255 is the largest value of one byte, used as "not set". A 5 would look like a real next phase; 255 fails safe. It is written in six files of the code (Study Guide v22, 2.3).
- "Is 255 in the dataset label?" No. It is the board's phase ID; the analysis turns it into a blank Label (#93).

## Slide 10: Two attacks, emulated at the application layer

**On the slide:** the blackhole as forwarding suppression (5 of 6 criteria), the wormhole as an out-of-band tunnel (4 of 5), and why emulation (D-20).

| Claim | Proven by | Mark |
|---|---|---|
| The attacker runs the same relay code and stops forwarding in the attack phase | Paper 4.2.1.2; firmware `forward_decision()` returns false in phase 1 | ✅ |
| It still ACKs every frame at the link layer, so victims see no failure | Paper 4.2.7.1: "accepts each probe at the link layer and discards it" | ✅ |
| 5 of 6 criteria of [70] met; not met: attracts traffic with a false route | Paper Table 4.4 | ✅ |
| UART wire, 115200 baud, 30-byte frames with CRC32 | Paper 4.2.1.3; 30 = "TNL1" (4) + probe (22) + CRC32 (4); Deck check A | ✅ |
| End B (deeper) writes its probes into the wire; end A re-injects them | Paper 4.2.1.3 | ✅ |
| The root gets every B probe twice | Paper 6.2.2: 12,448 of 12,465 (99.86%) | ✅ |
| 4 of 5 criteria of [46] met; not met: creates a false neighbour | Paper Table 4.5 (our count, not a claim of [46]) | ✅ |
| The API reads routes but cannot write them (D-20) | Paper 3.5.3, D-20; Espressif docs [21], [75] | ✅ |

**Careful (from the notes):** paper Table 4.4 row 1 still says "victims address the attacker". Since D-12 the victims send to their own parent and the tree routes them through the attacker.

**If asked:**

- "Is it really a blackhole?" Five of six criteria; we call it forwarding suppression and list route attraction as the first limitation.
- "Why does the wormhole have no victims?" Only B's own probes are tunnelled; the damage is duplication, not loss.
- "[46] was never opened?" True: the IEEE original could not be obtained. The record-tunnel-replay core is confirmed by a search excerpt; get it through the DLSU library (Study Guide 12.6).

## Slide 11: Topologies as they formed, and the run design

**On the slide:** three sites, three scenarios, 72 + 8 = 80, the formed trees (Figure 4.57).

| Claim | Proven by | Mark |
|---|---|---|
| Sites: G402 classroom, DLSU Library (heavy Wi-Fi), Yuchengco (open area below the building, semi-outdoor) | Paper 4.2.2.5; paper 1.4 says the sites are **indoor** | ✅ 🔶 |
| Stationary 1 probe/s; burst 300 probes 60 s into the attack; highload 4 probes/s | Paper 4.2.2.5; Deck check A | ✅ |
| 4 × 2 × 3 × 3 = 72 attack runs + 8 benign = 80; one run per cell | Paper 6.1, Table 6.1 | ✅ |
| The star has no bystanders | Paper 4.2.1.2, 6.2.1 | ✅ |
| Linear deepest hop 7; star hub with 6; tree root 2 to 5 children, deepest hop 2 to 4 | Paper Table 6.35; Deck check A | ✅ |
| In (f), end B deeper than end A, so the tunnel skips hops | Paper 6.2.2: B deeper than A in every run | ✅ |

**Careful (paper weak spots):** 4.2.2.1 still says Figure 4.16 is "to be redrawn" and hub-star "not yet usable" (it is redrawn; all 9 star wormhole runs are confirmed). 4.2.2.2 says sticky parents "not yet confirmed on hardware" (only 1 of 132 tree boards changed parent in the labelled phases).

**If asked:**

- "Is your partial mesh a mesh?" No board ever used a second parent, so it behaved as a branched tree (D-29). We claim no adaptive switching.
- "One run per cell?" Yes; the sites act as repeats. Limitation in 6.5.4.

## Slide 12: From raw rows to 16 features

**On the slide:** five steps (align, window, fill, count, join), one row = one board × one second, the six feature groups.

| Claim | Proven by | Mark |
|---|---|---|
| Boards share no clock; each is aligned to its own exit from phase 0 | Paper 4.2.4; D-2 | ✅ |
| 1 s windows on a 10 Hz grid; fewer than 8 of 10 samples = discarded | Paper 4.2.4, D-1, D-9, D-25 | ✅ |
| Gaps of 1 to 2 samples filled | Paper 4.2.4 | ✅ |
| Cumulative counters become per-window deltas | Paper 4.2.4 | ✅ |
| Delivery joins root arrivals on the sequence number, never on time | Paper 4.2.4, D-8; code `analysis/features.py` | ✅ |
| 16 features in six groups | Paper Tables 4.17 and 6.7 | ✅ |
| 457,568 windows formed, 1,372 discarded (0.30%) (notes) | Paper 4.2.3.7; Deck check A | ✅ |

**Careful (paper vs code):** the paper calls IngressEgressDelta and RSSI_Hop_Diff differences ("minus"); the code stores the **absolute** value. RSSI_Hop_Diff's median uses baseline **and** cooldown windows, not baseline only (#91). ForwardingRatio can exceed 1 in a single window (18 of 3,276 relay windows in one benign run, up to 2.2) although Table 6.7 says 0 to 1.

**If asked:**

- "Clocks aren't synchronised, so how do you get delivery or delay?" Join on the sequence number; align each board to its own phase-0 exit; delay is relative to the sender's fastest delivery (D-2).
- "Why 1 s and not 5 s windows?" With 5 samples one loss costs 20% of a window; the panel asked for about 10,000 rows per run (D-1, D-9).

## Slide 13: Why we read retries at the radio

New in deck v18.

**On the slide:** the boards never learn about the radio's resends, so RetryRate stays near 0; why the boards can't see the Retry flag; why a sniffer can; and a table of why many captures have no MAC retry rate (blackhole 43, wormhole 71, baseline 14).

| Claim | Proven by | Mark |
|---|---|---|
| The radio resends below the program; the program only hears "sent OK" | 802.11 link-layer retransmission is done by the Wi-Fi driver and hardware; `tools/pcap_retry.py` header; D-15 | ✅ |
| No call returns a retry count; the only statistics call prints to the log | D-15; `pcap_retry.py` header: "ESP-IDF 5.3.5 and 5.5 only offer `esp_wifi_statis_dump()`, which prints to the log and returns nothing" | ✅ |
| Normal receive calls hand over the payload, not the frame header | ESP-WIFI-MESH receive API (`esp_mesh_recv()`) returns the application data only | ✅ |
| "RetryRate stays near 0" | True on ordinary boards (victims 0.0000 → 0.0004, paper 6.2.4). On wormhole end B it rises to about 0.50 because it also counts tunnel frames (paper 6.3.2) | 🔶 |
| The sniffer runs in monitor (promiscuous) mode, gets every raw frame with its header, never joins or transmits | `sniffer_node/main/sniffer_main.c`: `WIFI_MODE_NULL` + promiscuous, `esp_wifi_set_promiscuous_rx_cb()`, "PASSIVE … never scans"; one channel, 20 MHz; data frames cut to 64 bytes (enough for the header) | ✅ |
| Resent frames carry a Retry tag; rate = retried ÷ data frames heard | 802.11 frame control flag 0x08; `pcap_retry.py`: "frames with the Retry bit / all unicast data frames the sniffer heard" | ✅ |
| The root's clock runs 30 to 40 s behind | `pcap_retry.py` header: the board restores its clock from the SD card at boot, so it lags by the flash time (38.5 s on one run, "~40 s") | ✅ |
| A capture is split only when the attack is found in the traffic | Blackhole: `pcap_retry.py` fits the attacker's uplink drop (`fit_attack_start`). Wormhole: the repository's `pcap_retry.py` refuses ("Only blackhole runs can be fitted from traffic") | ✅ (blackhole) ⚠️ (wormhole) |
| Table: usable 28 / 18 / 0; no run log 5 / 9 / 2; lost phase markers 3 / 21 / 2; incomplete 5 / 4 / 10; not placeable 2 / 19 / 0 | Columns add up (43, 71, 14). 131 captures are on this laptop (46 blackhole, 71 wormhole, 14 baseline). The counts come from a newer tool run that is **not in the repository**: this laptop's 44 `_retry.json` files are all refusals (30 wormhole, 14 baseline) and none is a blackhole result | ⚠️ |
| Counts "as processed by tools/pcap_retry.py" | The wormhole column needs a wormhole fit the repository's script does not have | ⚠️ |

**What to know:**

- **28 captures = 27 runs.** Some runs were captured twice; the summary keeps the latest capture per run. Slide 32 says 27 of 36 blackhole runs have a usable capture and 26 have frames in both phases.
- **Not a model input.** MacRetryRate is context only; RetryRate (the app counter) is also kept out of the clustering.
- **The sniffer is not complete.** One channel, misses some frames; read frame counts as well as percentages (`pcap_retry.py`: "a link it hears poorly gives few frames").

**If asked:**

- "Why not let every board listen in promiscuous mode?" A board logs its own sends and receives, so its log is small and clean. Logging every frame it hears (other boards' frames, other Wi-Fi networks) would make a huge, partly duplicated log.
- "Is there really no retry API?" Three things: a retry counter (doesn't exist, D-15); the normal receive calls (payload only); the promiscuous calls (raw frames with headers, used by the sniffer). The sniffer reads the flag itself.

Deep dive: Study Guide v22, Part 11 (11.1 what the sniffer is, 11.2 what a capture can and cannot show, 11.7 the blackhole seen from the air).

## Slide 14: How to read the dataset: one row

**On the slide:** four real rows (attacker 1C38 baseline and attack, victim D7B4, bystander 0C80) with the exact CSV column names, and three cards: label = phase, blank is not zero, same label different story.

| Claim | Proven by | Mark |
|---|---|---|
| The four rows are real | All four match `datasets/analysis/blackhole/tree/G402/stationary/feature_table.csv` (1C38 at t_anchor_s −100 and +120; D7B4 and 0C80 at +120). Checked when the slide was rebuilt with CSV names | ✅ |
| Headers are the CSV's own column names | Same file; legend `feature_table_legend.csv` | ✅ |
| Row 2: attacker received 3, forwarded 0, dropped 3, ForwardingRatio 0.000 | Same file; received = forwarded + dropped | ✅ |
| The attacker's PDR is blank, even in the baseline | #94: the attacker has no probe generator (`child_node/main/blackhole_victim.c:40`); the root logged **0** probes from it (0 of 2,913 in blackhole/linear/DLSU_Library/burst); its PDR is blank in 666 of 666 windows | ✅ |
| Row 3's 0.000 is real: sent, none arrived | D-8, Equation 4.5: a window gets a PDR only if the board sent, was attached and the root was logging | ✅ |
| Row 4: bystander PDR 1.000 with Label 1 | Same file; the label is set per phase for every board (paper 6.1) | ✅ |
| "That is why no method reaches ARI 1.0 on all nodes" | Paper 6.4.3: ceiling 0.515 because 43.2% of attack-labelled windows are bystanders | ✅ |
| Notes: "1,077 received and 1 forwarded … as in the paper" | Not in the paper; from the feature table and the verification log. The paper gives Table 4.4's 1.000 → 0.001 | ❌ |

**If asked:**

- "Why is the attacker's PDR blank and not 1?" PDR = "how many of **my** probes reached the root". The attacker sends none, so there is nothing to measure. Its health is shown by ForwardingRatio (1.000 in the baseline). Proof: firmware line 40, and zero arrivals from its MAC in the root log (#94).
- "What if a board is just disconnected?" Its PDR is blank, not 0, so a lost board is never mistaken for a victim (D-8). A board missing the whole run is graded by role (D-32).
- "D7B4 says hop 2 but layer 3?" Hop counts links to the root (root = 0); the mesh's layer starts at 1 for the root.

### Check-in (Part B)

- **Q:** Slide 9 says "label 255, excluded" and "5 rounds … repeated every 10 s". Which part of each sentence is exactly right, and what would you say instead if a panelist reads the code?

> [!question]- Answer (click to reveal)
> - **255:** "excluded" is right. But 255 is the boards' **phase ID** ("no phase heard yet"), not a dataset label: in `feature_table.csv` those windows have a blank Label (#93). Say "phase 255, no label, excluded".
> - **Rounds:** the paper says 5 rounds 100 ms apart, repeated every 10 s. The firmware sends the 5 rounds **at a phase change** and then **one** reminder every 10 s (the root's counter rises by 5 per phase change only, #92). Say "five rounds at each phase change, then a reminder every ten seconds".

---

# Part C: The verifier, Chapter 5 and the Thesis 2 panel (slides 15 to 26, Presenter 2)

## Slide 15: Every run is validated before it counts

**On the slide:** four checks (signature, topology, dataset, scenario), the verifier-test panel (placebo, sensitivity, stress test), six study cards (Z, A, R, K, KW, H).

| Claim | Proven by | Mark |
|---|---|---|
| Four checks, in this order, then a verdict | Paper 4.2.7, Figure 4.55, Table 4.24 | ✅ |
| Signature: ≥ 3 baseline SDs in the expected direction, change ≥ 0.10 | Paper 4.2.7.7.1 (also "at least six attack points", left off the card) | ✅ |
| Topology: tree rebuilt from parent addresses | Paper 4.2.7.7.2 | ✅ |
| "It must match the topology we designed for the run" | Not in the paper or any record (see slide 18) | ⚠️ |
| Dataset: every board ≥ 95% of each phase; missing boards graded by role | Paper 4.2.7.7.3, D-32 | ✅ |
| "Four checks, in this order (slides 14–18), then a verdict (19) and a test of the verifier (20)" | In deck v18 the checks are slides 16 to 20, the verdict 21 and the test 22 | ❌ |
| Scenario: probe rate and burst timing match | Paper 4.2.7.7.4 | ✅ |
| Checks 3 and 4: our own rules, fixed in advance | Paper 4.2.7.1: "engineering bounds before the results were examined" | ✅ |
| 0 of 106 false confirmations (placebo) | Paper 4.2.7.1. Repository docs say 104: quote the paper | ✅ |
| Sensitivity: 0 verdicts changed, 14 settings, **74 runs** | Paper says **53 runs** | ⚠️ |
| Stress test: 1,000 SDs changed **15** verdicts | Paper says **18** | ⚠️ |
| Z [71]: "Normal vs. attack judged by a 3-sigma rule; the wormhole is an out-of-band tunnel" (deck v18 wording) | [71] abstract, Eq. 21 (p. 14); paper Table 4.20 | ✅ |
| Z: "Check 1: … TunnelIntensity" | **Removed in deck v18** (it was ❌: paper 4.2.7.2 says the tunnel features have no counterpart in these studies) | ✅ |
| A [70]: ForwardingRatio and PDR collapse | [70] p. 44 (discards packets), p. 53 (60 to 75% loss); "ForwardingRatio" is our name | ✅ |
| R [72]: "Duplicate packets are the wormhole's signature" | [72] p. 55 **proposes** duplicated **routing** packets; nothing measured | 🔶 |
| K [22]: "delivers above 97%" | Khan p. 18: except node H | 🔶 |
| K: "broken baseline = excluded (0.90 bound is ours)" | Paper 4.2.7.1, 4.2.7.2 | ✅ |
| KW [81]: position decides the victims | [81] §5.2; paper 4.2.7.1 | ✅ |
| H [46]: "a shortcut whose copies arrive with a timing mismatch"; "end A above end B" | The paper uses [46] for the definition only (3.3.2, Table 4.5); "A shallower than B" is the setup check, uncited; original never opened | ❌ |

**Where the mismatches come from:** the H, Z-TunnelIntensity and R wording was copied from the verifier code's own source list (`tools/verify_attack.py`, lines 487 to 522), which says more than the paper. The panel holds the paper, so the paper wins (Deck check B).

**If asked:**

- "How do you know a run is valid and not noise?" Four checks, rules fixed in advance, a placebo that never confirmed a fake attack, and a sensitivity test where no verdict changed.
- "Are those all the rules of the 3-sigma test?" There is also a floor of 6 attack points (30 s). Every run has 36, so it never decided a verdict.
- "Placebo: 106 or 104?" 106 is the paper's number; quote it.

## Slide 16: Check 1, two signatures

**On the slide:** a table comparing blackhole, wormhole and benign: how it works, grounded in, scored, supporting, who is hit, what we measured, and a "same in both" strip.

| Claim | Proven by | Mark |
|---|---|---|
| Blackhole: accepts each probe, then drops it; the sender sees no error | Paper 4.2.7.1 | ✅ |
| "ForwardingRatio ↓ at the attacker only (honest relays stay ≈ 1.0, not averaged in)" | Paper 4.2.7.7.1 scores the attacker's ForwardingRatio; honest relays 1.000 (Table 6.9) | ✅ |
| "TunnelBytes ↑ (TunnelIntensity × 30 B)" | 30-byte tunnel frame (paper 4.2.1.3); 0 → 57.5 B/s = 30 × 1.92 (6.3.2) | ✅ |
| Wormhole: every probe of B arrives twice | Paper 6.2.2: 99.86% ("every" = 99.86%) | ✅ |
| Scored: ForwardingRatio "+" PDR; TunnelIntensity "+" DuplicateRate | Paper 4.2.7.7.1: a run passes when **at least one** primary passes | 🔶 |
| Benign: PDR ≥ 0.90 in both phases; every relay forwards ≥ 90% | Paper 4.2.7.7.5 | ✅ |
| Supporting: IngressEgressDelta, ConsistencyScore, NeighbourForwardingRatio | Paper 4.2.7.7.1; Table 6.9 (31, 31, 32 of 36) | ✅ |
| "TunnelLatency is measured, not scored (no tunnel in the baseline)" | Paper 4.2.7.1. Deck v17 dropped LatencyHopRatio from this line, which fixes the old 🔶 | ✅ |
| Victims lose every probe; bystanders untouched | Paper 6.2.1: all 123 victims exactly 0; bystanders 0.996 → 1.000 (d = 0.09) | ✅ |
| Wormhole: no one loses probes | Paper 4.2.7.4: non-tunnel boards 0.9999 in both phases | ✅ |
| 36 / 36, 36 / 36, 8 / 8 | Paper 6.5.1, 6.2.6, Tables 6.9 and 6.11 | ✅ |
| "No attack-caused route, parent or hop-count change, and RSSI stays flat" | Wormhole: no parent or hop change (4.2.7.4). Blackhole: "almost none" (4.2.7.2); one tolerated move in Figure 4.57c. RSSI \|d\| < 0.1 (6.3.1) | 🔶 |

**Numbers in the notes (all ✅, Deck check A):**

- PDR primary 35 of 36 (one excluded, 0.930 ± 0.253).
- NeighbourForwardingRatio 32 of 36.
- 12,448 of 12,465 of B's probes arrived twice.
- Gap median 3.9 ms, 90th percentile 12.1 ms.
- Benign floor moved to 0.80 and 0.95: no verdict changed.

**If asked:**

- "Key difference between the two?" Blackhole = loss behind the attacker, seen in PDR. Wormhole = duplication with no loss, seen in the ends' counters and the root's duplicates.
- "How is NeighbourForwardingRatio computed?" From `analysis/features.py` (`compute_neighbour_forwarding_features`): what the attacker's children handed it against what its parent received. Blank when the parent has several children, because its counter is not split by sender. Likely reason for the 4 missing runs, not confirmed.
- "Can a real attacker fake its counters?" Yes, and this dataset cannot test that. The attacker's counter is ground truth for labelling; PDR and duplicates are the root's view.

## Slide 17: Check 1, the 3-sigma rule

**On the slide:** a schematic band (baseline mean ± 3 SD), "Baseline: 60 points of 5 windows", "Attack: 36 points", two rules, an illustrative z.

| Claim | Proven by | Mark |
|---|---|---|
| 3-sigma rule from Zhukabayeva et al. | [71] Eq. 21, p. 14; paper Table 4.20 | ✅ |
| 5 windows pooled into one point; 36 attack points | Paper 4.2.7.1; 180 s ÷ 5 = 36. Pooling is **our** design | ✅ |
| "Baseline: 60 points" | 300 s ÷ 5 = 60 for the baseline, but in attack runs the code's reference is every Label-0 window, baseline **and** cooldown (#92: 3,355 = 2,398 + 957 in blackhole/linear/DLSU_Library/burst; checklist B-guide04) | 🔶 |
| Passes when both rules hold (≥ 3 SD, change ≥ 0.10) | Paper 4.2.7.7.1 also requires ≥ 6 attack points | 🔶 |
| z = (0.003 − 1.000) ÷ 0.002 = −498.5, illustrative | Arithmetic correct; labelled illustrative (Deck check A) | ✅ |
| SD = 0: any move in the expected direction passes | Paper 4.2.7.1, 6.2 | ✅ |
| Notes: where z was finite (21 runs), at least 22.9 SDs, median 111 | Paper 6.2.1; Deck check A | ✅ |
| Notes: "Zhukabayeva et al. [71]: pool every 5 one-second windows" | Pooling is ours (slide 21 notes say so) | ❌ |

**Careful (paper wording):** 4.2.7.1 calls a zero-SD z "undefined"; 6.2 calls it "infinite". Safe: "the baseline never varied, so any move in the expected direction passes."

**If asked:**

- "With SD = 0, is any tiny change a pass?" No: the change must also be at least 0.10, so one lost probe can never count as an attack.
- "Is the reference only the baseline?" In attack runs the code uses all normal windows, baseline and cooldown; the attack never enters it.

## Slide 18: Check 2, topology

**On the slide:** two figures (Figure 4.57 blackhole panels, Figure 6.2), the rule (victims behind the attacker, bystanders as control), "the layout check", the setup check.

| Claim | Proven by | Mark |
|---|---|---|
| Who is a victim depends on where X sits | Paper 4.2.1.2, Figure 4.57; [81] §5.2 | ✅ |
| Victims lose everything; bystanders do not (Figure 6.2) | Paper 6.2.1: 123 victims at 0; bystanders 0.996 → 1.000 | ✅ |
| The check reads only parent addresses, never the outcome | Paper 4.2.7.7.2 | ✅ |
| "The layout check: the rebuilt tree must match the topology we designed" | Not in the paper or any repository record. Paper's rule: a board that switches between victim and bystander fails the run (D-23, D-31) | ⚠️ |
| Setup: attacker relayed then dropped; victims alive but cut off; one A and one B, A shallower | Paper 4.2.7.7 (setup check) | ✅ |
| "Backed by Karlof and Wagner [81] and Hu et al. [46]" | [81] backs victims vs. bystanders. [46] is not cited for the setup check in the paper | 🔶 |

**Careful:** slide 21 still lists "a board changed class" under FAIL, which is the paper's rule. If slide 18 keeps "the layout check", the two slides describe different rules. Settle it as a team.

**If asked:**

- "Why do you need bystanders?" They are the control group: same run, same time, same radio, not behind the attacker. Their delivery did not change, so the loss is the attack, not the room.
- "What if a board switches parent in the attack?" Tolerated if it keeps its class (D-23); a switch between victim and bystander for 3 s or more fails the run.

## Slide 19: Check 3, dataset

**On the slide (deck v17):** count (≥ 95% of every phase); find the gaps (below 95% = a gap; no file at all: the 3-sigma test decides; no attacker file = FAILED); impact check (re-run automatically without each gap board); the grade, decided by the re-run and the board's role; two new boxes for a disconnected board and a board with no file.

| Claim | Proven by | Mark |
|---|---|---|
| Every board needs ≥ 95% of each phase | Paper 4.2.7.7.3 | ✅ |
| Impact check: re-run the 3-sigma test without the gap boards | Paper 4.2.7.3, Figure 4.58 | ✅ |
| Minor gaps: the attack still confirms and at most half the boards have gaps | `tools/verify_attack.py` line 785 (`IMPACT_MAX_SHARE = 0.5`) and line 713 ("more than half the network" = major) | ✅ |
| No attacker file = FAILED | `tools/verify_attack.py` line 827 ("the attacker's data is missing" is a FAIL reason). The paper's D-32 still calls a missing attacker or tunnel end a **major gap** | ✅ ⚠️ |
| A wormhole end that is missing stays MAJOR (not on the slide) | `tools/verify_attack.py` line 695 | ✅ |
| Gaps in the attacker's own baseline or attack data are always MAJOR (not on the slide) | `tools/verify_attack.py` line 649 | ✅ |
| Disconnected board: layer −1, no parent, PDR blank, never 0 | Paper D-8 (PDR blank when the board is detached) | ✅ |
| Grades STRONG / GOOD / MINOR GAPS / MAJOR GAPS / FAILED | Paper Table 4.24 | ✅ |
| "Our own rule, refined during capture" | D-32 was added during capture (paper 5.6) | ✅ |

**Careful:** this slide's speaker notes are about Airehrour et al. [70], left over from an older slide. Present from the script.

**If asked:** "What is a major gap?" Without the gap boards the attack no longer confirms, or more than half the boards have gaps. Then the run is recaptured.

## Slide 20: Check 4, scenario

**On the slide:** stationary (median ≤ 1.5 probes/s), highload (median baseline ≥ 3 probes/s), burst (≥ 240 extra probes from one child within 10 s); trace found = APPLIED, missing = NOT APPLIED (D-34).

| Claim | Proven by | Mark |
|---|---|---|
| The three scenario checks and their thresholds | Paper 4.2.7.7.4 | ✅ |
| NOT APPLIED = minor gap, footnoted; attack result stands (D-34) | Paper 5.6, D-34; slide 28 notes: linear/G402/burst blackhole burst fired outside the attack | ✅ |
| "Check 4 can only lower a grade, never raise it" | `tools/verify_attack.py` lines 741 to 770: a scenario NOT APPLIED is added to the minor gaps, so STRONG or GOOD becomes MINOR GAPS and MAJOR stays | ✅ |
| Measured probe rates match the scenario: about 1.0, 1.1 and 3.9 per board per second | Paper 6.3.3, Figure 6.14 | ✅ |

**Careful:** the speaker notes are about Khan et al. [22]. Present from the script.

## Slide 21: The verdict

**On the slide:** PASS, FAIL, INCONCLUSIVE; what the signature scores; the Khan 97% line.

| Claim | Proven by | Mark |
|---|---|---|
| PASS = signature confirmed, topology, dataset and scenario hold; graded STRONG, GOOD or MINOR GAPS | Paper 4.2.7.7.5, Table 4.24 | ✅ |
| FAIL = no signature, a board changed class, attacker data missing, or setup failed; redone | Paper 4.2.7.7.2 (D-23, D-31), 4.2.7.7.5 | ✅ |
| INCONCLUSIVE: broken baseline (mean < 0.90 or SD > 0.15 of the mean) excludes that primary | Paper 4.2.7.1 | ✅ |
| "Healthy ESP-MESH delivers above 97% (Khan [22])" | Khan p. 18, except node H | 🔶 |
| Blackhole scores the attacker's ForwardingRatio and the PDR of the non-attacker boards | Table 6.9 and the code; but paper 4.2.7.7.1 says "PDR of the victims" (the paper contradicts itself) | ✅ 🔶 |
| Wormhole scores TunnelIntensity and DuplicateRate (root, D-21) | Paper 4.2.7.7.1, D-21 | ✅ |

**Careful:** the speaker notes are about Zhukabayeva and Ramírez Gómez. They correctly say that pooling 5 windows is **our** design.

**If asked:** "Victims or all non-attacker boards for PDR?" The verifier tests every non-attacker board with a PDR (Table 6.9); 4.2.7.7.1's "victims" is a wording slip.

## Slide 22: Testing the verifier

**On the slide:** placebo 0 of 106; sensitivity 0 verdicts changed (7 rules, 14 settings, 74 runs); stress test 15 verdicts changed (1,000 SDs).

| Claim | Proven by | Mark |
|---|---|---|
| Placebo: 0 of 106 false confirmations (second half of the baseline relabelled as attack) | Paper 4.2.7.1 | ✅ |
| Sensitivity: 0 verdicts changed, 7 rules about ±50%, 14 settings | Paper 4.2.7.1 (with 53 runs) | ✅ |
| "74 runs" | A later re-run of `tools/audit_threshold_sensitivity.py`, not in any repository record; the paper says 53 | ⚠️ |
| Stress test: "15" verdicts changed | Same re-run; the paper says 18 | ⚠️ |
| Rules fixed before any result was read | Paper 4.2.7.1 | ✅ |

**Open questions before quoting (from the slide notes):**

- Which number is final: 53 / 18 (paper) or 74 / 15 (re-run)? The script (v18 deck) follows the slides (74 / 15) and carries a warning.
- The slide says "Details: backup slide 21"; the backup is slide 23.
- The victim-cut 0.0 control changed 14 verdicts in the older log and 0 in the re-run. Only the 1,000-SD control shows that the test can fail; never say both controls changed verdicts.
- Which run is the 1 INCONCLUSIVE ("probably" the 0.930 ± 0.253 baseline)? Confirm before naming it.

**If asked:** "What does ±50% mean?" How far each rule was turned when tested, not a rule itself: half of the rule's own number, down and up. Not exact for every rule (sigma 3 → 2.5 and 3.5).

## Slide 23: Backup, the 17 sensitivity settings

Only if asked "did you tune your thresholds?".

| Claim | Proven by | Mark |
|---|---|---|
| Sigma 3 → 2.5 and 3.5 | Paper 4.2.7.1; `docs/attack-validation/GRADING-AND-THRESHOLDS.md` | ✅ |
| Minimum change 0.10 → 0.05 and 0.20 | Same | ✅ |
| Victim cut 0.50 → 0.25 and 0.75 | Same | ✅ |
| Bystander allowance 0.30 → 0.15 and 0.45 | Same | ✅ |
| Attacker cut 0.50 → 0.25 and 0.75 | Same | ✅ |
| Time in the wrong group 3 s → 2 and 5 s | Same | ✅ |
| Baseline floor 0.90 → 0.80 and 0.95 | Same | ✅ |
| "0 verdicts changed (74 runs); 1,000 SDs: 15 changed" | Same open item as slide 22 | ⚠️ |

**Careful (from the notes):** confirm rule 6's unit (seconds) and rule 2's unit for TunnelIntensity (messages per second, not a 0 to 1 ratio). Cite the floor test as 0.95, not 0.97.

## Slide 24: Planned vs. actual, the changes that matter

**On the slide (deck v18):** the six-row table only. The v17 slide "Chapter 5: 37 deviations, three reasons" was removed; its content moved into this slide's speaker notes ("SAY FIRST") and is spoken at the start of this slide in the script. The "Limits how Chapter 6 is read" line was taken off the slide.

| Claim | Proven by | Mark |
|---|---|---|
| (Spoken, from the notes) 37 deviations, D-1 to D-37 | Paper 5.1, Table 5.2, Appendix C | ✅ |
| (Spoken) 17 modify the proposal, 20 add a rule | Counted in Table 5.2 (Deck check A) | ✅ |
| (Spoken) three reasons: the platform could not measure it (D-15; D-2, D-3); the plan would leak the label or fail to make the attack (D-12; D-17, D-28, D-30); a run needed rules (D-22, D-23, D-32) | Paper 5.2, Table 5.2 | ✅ |
| (Notes) five groups in Table 5.1 | Paper Table 5.1 | ✅ |
| Attacks on routing → app-layer emulation (D-20) | Paper 5.3, 3.5.3 | ✅ |
| Relay counters only on the attacker leaked the label → every node relays and counts (D-12) | Paper 5.3 | ✅ |
| No MAC retry count reaches the app → "App counter kept; sniffer measures real retries on some runs (context only)" (D-15) | Paper 5.3, 6.2.4 (sniffer on 7 runs in the paper; the deck's 27 + 18 runs are after submission, see slides 32 and 48) | ✅ |
| 5 s windows of 5 samples → 1 s windows of 10 samples at 10 Hz (D-1, D-9) | Paper 5.3 | ✅ |
| Flat star, fixed ends → hub = attacker or end A; ends chosen by depth (D-16, D-17, D-28, D-30) | Paper 5.4 | ✅ |
| No benign runs → 8 benign runs (D-18, D-35) | Paper 5.5, 6.2.6 | ✅ |
| (Spoken) four limits on reading Chapter 6: D-20, D-15, D-18/D-35, D-37 | Paper 5.7 | ✅ |
| Notes, retries block: "the wormhole phase placement (end A uplink step-up, D-43)" | The paper's deviations end at D-37; no repository record has a D-43 | ⚠️ |

**If asked:**

- "What is D-12 for?" The Thesis 2 panel said "if one feature decides it, ML is unnecessary". Before D-12, an empty relay column alone identified the attacker.
- "37 deviations means you didn't follow your proposal?" Each was forced by evidence, each lists its cost (Appendix C), and only four limit how the results are read. Several were checked with the adviser (D-19, D-33, D-35).

## Slide 25: Thesis 2 panel questions: now answered

**On the slide:** eight Thesis 2 panel comments, what Thesis 3 did about each, and a status (7 answered, 1 partly).

| Claim | Proven by | Mark |
|---|---|---|
| The eight comments (single feature decides; identical runs; balance and topology; public places; specific IoT context; prove the attacks; benign baseline under load; 10,000 samples and shorter runs) | Thesis 2 panel notes, `ESP32-Environment/memory/panel-change-2026-09.md`, items 1 to 8 | ✅ |
| 1: an empty relay column gave the attacker away; now every board relays and counts | D-12 (paper 5.3) | ✅ |
| 2: 3 different blackhole attackers and 5 different wormhole ends | The team's run plan; not counted in this pass | ⚠️ |
| 3: 4 topologies, 3 sites, 3 loads; 80 of 80 runs; formed topology checked after every run | Paper 6.1, Table 6.1; 4.2.7.7.2 | ✅ |
| 4: 3 campus sites, not a house | Paper 4.2.2; home captures not counted (6.1) | ✅ |
| 5: campus monitoring, 8 boards to one root, as in Khan [22]; attacker position from Karlof and Wagner [81] | Khan pp. 1, 18; [81] §5.2 | ✅ |
| 6: blackhole 5 of 6 criteria [70], wormhole 4 of 5 [46]; 36 of 36 confirmed | Paper Tables 4.4, 4.5, 6.9, 6.11 | ✅ |
| 6 (deck v18): "blackhole, Airehrour et al. (2018), 5 of 6 criteria; wormhole, Hu et al. (2003), 4 of 5. 3-sigma test (Zhukabayeva et al., 2025)" | Fixed in v18: the 4-of-5 count is now tied to [46] only (Table 4.5), and [71] to the 3-sigma test | ✅ |
| v18 cites by author and year on this slide (Khan et al. 2022, Karlof and Wagner 2003, …) | The notes' citation key maps each to the paper's number: [22], [81], [70], [46], [71], [72]. Other slides still use [n], so expect a panelist to ask for the number | ✅ |
| 7: phase 0 of each run sets the 3-sigma limits; 8 benign runs as a cross-check | D-5; paper 4.2.7.1, 6.2.6 | ✅ |
| 8: "wormhole runs alone give 6,469 attack windows" | 6,469 is the attack windows of **end B only** (6.2.2), so it says nothing about rows per run. A run gives about 4,600 analysed rows (369,678 ÷ 80; Table 6.2). The panel asked for about 10,000 per run (D-9) | ❌ |
| 8: status "Partly" | Correct: 1 s windows gave 5 times the rows (577 → 2,894 on a clean test run, D-9), but not 10,000 per run | ✅ |
| Speaker notes | Still start with facts copied from the Chapter 5 slide (D-20, D-12, D-15 …); v18 added a citation key at the end | ⚠️ |

**Safe line for comment 8:** "1 s windows of 10 samples: about 4,600 rows per run (369,678 in total). 10,000 per run would need runs more than twice as long."

**If asked:**

- "So no single feature decides it now?" The relay-column leak is gone (D-12). PDR alone still separates the victims' attack seconds (99.9%, slide 54), because a full delivery collapse is separable by construction; the single-feature audit reports it.
- "Did you add jitter?" Tried and dropped, checked with the adviser (D-33); 5 jitter captures are not counted.

Deep dive: Study Guide v22, 5.3 (D-12), 3.1 (D-9) and 6.5 (single-feature audit).

## Slide 26: Why synthetic traffic is valid

**On the slide (deck v18):** "The traffic is synthetic" (the "Admitted first" wording was dropped); three load profiles; six reasons (attacks act on forwarding; a known stream makes loss measurable; exact labels; varied load; a real network; "Comparison with Prior Work" [31], [22], renamed from "There is precedent"). The "Limit" line was removed.

| Claim | Proven by | Mark |
|---|---|---|
| A small test packet about once a second, not sensor readings | Paper 4.2.3.1.4 (probe every 1,000 ms, 250 ms in highload; sequence number, send time, node id, magic value) | ✅ |
| Stationary 1/s, high load about 4/s, burst 300 probes in about 3 s | Paper 4.2.2.5; measured 1.0, 1.1, 3.9 probes/s (6.3.3) | ✅ |
| 1: "Attacks act on forwarding, not content" | True of **our** two attacks (paper 4.2.1.2, 4.2.1.3: "Probe Duplication, Not Modification"). Not true of blackholes and wormholes in general: [81] §5.2 selective forwarding, [71] modified 20 to 30% of readings | 🔶 |
| 2: sender MAC + sequence number give exact PDR | Paper 4.2.3.1.4, 4.2.4 (join on the sequence number) | ✅ |
| 3: labels set by the firmware's phases | Paper 4.2.3 (phase schedule) | ✅ |
| 4: "High load and burst test the **detector**" | The study builds no detector (scope, paper 1.4). Say "the analysis" | 🔶 |
| 5: real boards, real ESP-WIFI-MESH, real radio and self-healing; only the payload is synthetic | Paper 4.1; 15 captures replaced (6.1) | ✅ |
| 6: [31] compares datasets as real, emulated or synthetic | Ring et al. [31], Section IV.D.1 "Kind of Traffic": 15 properties in five categories (paper 2.9; Study Guide v22, 13.3) | ✅ |
| 6 (v18): "So synthetic is a named category in dataset design, not something we invented" — read together with the top line "The traffic is synthetic" | On Ring's definitions synthetic = "not captured by a real (or virtual) network device". Ours is carried and logged by real boards, so it is **emulated**; only the payload is synthetic (verification report, nov. 05, 2026). Say "emulated traffic on a real mesh, with a synthetic payload" | ❌ |
| 6 (v18): Khan [22] "also sent test packets, one every 2 minutes, in a comparable ESP32 testbed" | Khan p. 18: "a 64 Byte package was transmitted for five days at two-minute intervals" (campus test; every minute in the open-area test). "Comparable" is fair for the board and the campus setting; Khan uses PainlessMesh, not ESP-WIFI-MESH, and does not call them "test packets" | 🔶 |
| 6 (v18): "Ours are sent about once a second, so each run gives far more samples" | Paper 4.2.3.1.4 (1,000 ms; 250 ms in highload) | ✅ |
| "The paper says the traffic is synthetic" (implied) | The paper never uses the word; these are design reasons built from its facts | 🔶 |
| Limit: no generalisation to real deployments | Paper 6.5.4. **Removed from the slide in v18**; the script still says it aloud as the team's own point | ✅ |
| "Real sensor traffic is future work" | Removed in v18 (was 🔶: not one of the paper's five recommendations, 7.6) | ✅ |
| Speaker notes | None yet | ⚠️ |

**Box 6, paste-ready:** "Ring et al. [31] surveyed intrusion-detection datasets and sort their traffic as real, emulated or synthetic, so generated traffic is a recognised category in dataset design. Khan et al. [22] also sent a fixed 64-byte packet every 2 minutes over a campus ESP32 mesh. Ours are sent about once a second, so each run gives far more samples."

**Why each source is there:** Ring et al. [31] answers "is generated traffic a legitimate category in dataset design?" (cited for the category only; it does not accept or endorse our traffic). Khan et al. [22] answers "does anyone else send fixed packets at a steady rate to measure delivery?" (one study on a similar ESP32 campus mesh, different mesh software).

**Safe line for reason 1:** "Our two attacks, as built, act on forwarding only: the blackhole drops every probe and the wormhole duplicates B's probes. For those two, a probe and a sensor reading are handled the same way."

**If asked:** see the deep dive under slide 7 (why probes, why not real sensor readings, what payload attacks would need) and its ready answers.

- **"Ring says synthetic means generated and never captured from a real device. Does that make your ESP32 data useless, or the thesis weak?"** No. That is the label our data does **not** get. Our probes crossed real boards, real radio and a real ESP-WIFI-MESH, and real devices logged them, so on Ring's definitions our traffic is **emulated**: real packets captured in a test bed. Only the content of a probe is generated, which is why we call the payload synthetic. Ring's labels describe where the traffic was recorded; they are not quality grades, and emulated is common (many datasets in Ring's table, such as NSL-KDD and CIDDS-002, are emulated). What still holds: our two attacks act on forwarding, not content; the loss, delay and duplicates come from real radio and mesh behaviour; and the sequence numbers make loss countable and the attack phases exact. The real limit is generalisation: the traffic is not from a live production network and the content is generated, so the results do not carry over to real deployments (paper 6.5.4; since v18 no longer on the slide, so say it yourself). Say: "It is emulated traffic on a real mesh. The labels are exact and the loss is measurable, which real sensor traffic would not give us. The limit is generalisation, and we state it."
- **Same question, three ready versions:** **"Ring calls generated traffic synthetic. Is your data useless?"**
  - **Short (about 15 seconds):** No. Ring's "synthetic" means traffic that never went through a real device, and ours did, so Ring would call it emulated. Only what is inside each probe is generated. The real limit is that we cannot claim it works on live networks, and the slide says so.
  - **Easy to understand:**
    - No. Ring's "synthetic" means traffic that never went through a real device. Ours did, so Ring would call it emulated. Only the content of each probe is generated.
    - Emulated is not a bad grade. It means the traffic was recorded in a test bed, and many known datasets are emulated.
    - The real limit is that this doesn't prove it works on live networks, and we say so on the slide.
  - **Technical (if the panelist presses):** Ring's "Kind of Traffic" property (Section IV.D.1) defines real as captured on a productive network, emulated as real traffic captured in a test bed or emulated environment, and synthetic as traffic "created synthetically (e.g., through a traffic generator) and not captured by a real (or virtual) network device". Our probes are produced by our firmware but are transmitted over ESP-WIFI-MESH and logged by the root, so they are emulated by that definition. The payload (magic value, sequence number, send time, sender MAC) is the synthetic part. The label records the recording environment, not quality. Internal validity holds: the two attacks act on forwarding, the PDR is joined on the sequence number, and the firmware sets the phases. External validity is the limit: no production traffic, so no generalisation to live deployments (paper 6.5.4).

### Check-in (Part C)

- **Q1:** A panelist reads slide 15 and says: "Your card ties Zhukabayeva et al. to TunnelIntensity, and Hu, Perrig and Johnson to 'end A above end B'. Show me where your paper says that." What is the honest answer?
- **Q2:** Slides 15 and 22 say 74 runs and 15 verdicts. The paper says 53 and 18. Which do you quote today?

> [!question]- Answer (click to reveal)
> - **Q1:** It doesn't. Paper 4.2.7.2 says the tunnel features have no counterpart in the published studies; [71] gives the 3-sigma test and the idea of an out-of-band tunnel. [46] is cited for the wormhole **definition** (Table 4.5, 4 of 5 met); "A shallower than B" is part of our setup check, which cites no study. The card wording came from the verifier code's source list (Deck check B).
> - **Q2:** Quote the paper (53 runs, 18 verdicts) unless the team has updated the paper and the records to the re-run. Whatever you choose, the slides and the script must say the same.

---

# Part D: The dataset and the blackhole (slides 27 to 40, Presenter 3)

## Slide 27: Divider (Chapter 6)

No claims.

## Slide 28: The dataset, 80 of 80 runs captured

**On the slide:** 80 / 80 runs; 369,678 windows analysed of 456,195; 0.30% discarded (1,372); 637 log files; 266,491 normal + 103,187 attack; 123 victims, 92 bystanders; the run grid figure; benign by topology.

| Claim | Proven by | Mark |
|---|---|---|
| 80 runs: 36 blackhole, 36 wormhole, 8 benign | Paper 6.1, Table 6.1 | ✅ |
| 369,678 = 266,491 + 103,187 windows analysed | Paper Table 6.2; Deck check A | ✅ |
| 456,195 windows in total | Table 6.2 phase sum. But 457,568 − 1,372 = 456,196: one window apart, not yet traced | ✅ 🔶 |
| 1,372 discarded (0.30%) | Paper 4.2.3.7 | ✅ |
| 637 log files, none empty | Paper 6.1, 7.3 | ✅ |
| 123 victims, 92 bystanders (the star has none) | Paper 6.2.1 | ✅ |
| Benign: linear 3, star 3, tree 1, partial mesh 1 | Paper 6.1 (from 21 / 21 / 19 / 19 per topology) | ✅ |
| Notes: by site G402 28, Library 26, Yuchengco 26 | Paper 6.1; Deck check A | ✅ |
| Notes: every run has 8 boards except benign star/Yuchengco/highload (6) and blackhole tree/G402/highload (7: B768, a bystander) | Paper 6.1, 7.3; D-32 | ✅ |

**Careful (paper weak spot):** the Chapter 4 intro still says "while the remaining runs are captured"; all 80 were captured.

**If asked:**

- "Why are so many feature cells blank?" ForwardingRatio exists only when a node relayed something (36.3% of non-attacker windows); PDR is not scored on the attacker or the tunnel ends (Table 6.8).
- "Were any runs thrown away?" 15 earlier captures of 11 cells were replaced and archived with the reason; 12 captures outside the plan (5 jitter, 7 at home) are not counted. Never open a "home" table in front of the panel (#95 side finding).

## Slide 29: Divider (blackhole results)

No claims.

## Slide 30: Blackhole, confirmed in all 36 runs

**On the slide:** 36 / 36 (4 strong, 27 good, 5 minor gaps); attacker ForwardingRatio 1.000–1.004 → 0.000–0.007; victim PDR 0.998 → 0.000; 121 of 123 cut off in the first second, recovery median 2 s; bystanders 0.996 → 1.000; Figure 6.2.

| Claim | Proven by | Mark |
|---|---|---|
| 36 / 36 = 4 strong + 27 good + 5 minor gaps | Paper 6.5.1, Table 6.9 | ✅ |
| Attacker ForwardingRatio 1.000–1.004 → 0.000–0.007 | Paper Table 6.9 | ✅ |
| Victim PDR 0.998 → 0.000; every one of 123 at exactly 0 | Paper 6.2.1; #95: 0 of 21,733 victim attack windows above 0 | ✅ |
| 121 of 123 in the first second; recovery median 2 s | Paper Table 6.10 | ✅ |
| Bystanders 0.996 → 1.000 | Paper 6.2.1 (d = 0.09) | ✅ |
| Notes: PDR primary 35 of 36 (one excluded, 0.930 ± 0.253, partial/Yuchengco/stationary) | Paper Table 6.9 | ✅ |
| Notes: example run, 1,077 received, 1 forwarded | Feature table of linear/G402/stationary and the verification log; **not** in the paper | 🔶 |

**Safe line for the example:** "In one run the attacker received 1,077 probes during the attack and forwarded one. The paper reports it as 1.000 → 0.001 in Table 4.4."

**If asked:**

- "Why is one run's PDR primary excluded and the run still confirmed?" Its baseline was unstable (0.930 ± 0.253), so that primary is excluded, not failed; the ForwardingRatio primary confirmed it, and one primary is enough.
- "Did any victim recover late?" 122 boards recovered within 3 s; one went silent.

## Slide 31: Blackhole predictions, delivery yes, retries barely

**On the slide (deck v18):** title changed from "retransmissions no"; row 4 is now "Retransmissions rise (MAC), all links | Not clearly | Sniffer, 26 runs …"; the summary line and the footnote mention the sniffer.

| Claim | Proven by | Mark |
|---|---|---|
| ForwardingRatio < 1: yes, 36 of 36 | Paper Table 6.9 | ✅ |
| IngressEgressDelta > 0: yes, 31 of 36; the other 5 rose but stayed under 3 SD (z 0.4 to 2.9) | Paper Table 6.9; Deck check A | ✅ |
| PDR falls: yes, 0.998 → 0.000 | Paper 6.2.1 | ✅ |
| Row 4: "Retransmissions rise (MAC), all links: Not clearly. Sniffer, 26 runs, all links 34.8% to 37.5%, up in 16 of 26; attacker's own link 31.9% to 39.2%" | Not in the paper. The paper's 6.2.4 has 7 runs (victims 0.295 → 0.364 → 0.323; 3 up, 4 down). The 26-run numbers come from `tools/macretry_summary.py`, which is **not in the repository** (see slide 32) | ⚠️ |
| "Not clearly" as the verdict | Fair reading of the slide's own numbers: +2.7 points, up in only 16 of 26, range −7.6 to +15 | ✅ |
| Table 3.4's prediction is about **victims'** retransmissions; the row reports all links and the attacker's link | The sniffer numbers were not split by role (slide notes say so) | 🔶 |
| App counter: victims 0.0000 → 0.0004 (no longer on the slide) | Paper 6.2.4; 9 of 21,742 victim attack windows | ✅ |
| Footnote: "Sniffer row: extends Section 6.2.4 (7 runs in the submitted paper) with captures processed after submission" | Honest and accurate | ✅ |
| Attacker RSSI row | **Removed from the slide in deck v17**, but the "†" footnote that explained it is still on the slide | ⚠️ |

**Safe line:** "The radio retry rate barely moved: 34.8 to 37.5 percent across the network, up in only 16 of 26 runs. Our attacker still acknowledges every frame, so the attack gives the victims' radios nothing extra to resend."

**If asked:**

- "Why so little change in retransmissions?" The attacker still acknowledges every frame at the link layer, so a send to it succeeds and nothing extra is resent. The retries the sniffer sees (about a third of frames) are already there in the baseline.
- "Did the victims retransmit more?" Not split in the 26-run summary. One run checked by hand (linear / DLSU Library / highload, the backup sniffer run): the victim's link into the attacker went 37.8% → 38.8% → 42.0% (baseline / attack / cooldown), no attack-driven rise (Kyle's counts, study guide v10 11.7, on GitHub `origin/THESIS3`, commit `2f5dfad6`).
- "Table 3.4 has five predictions; you show four." The fifth, the attacker's RSSI stays stable, held: −67.1 → −67.8 dBm, within 1 dB in 27 of 36 runs. That number is **not in the paper**; it was computed from the attacker rows of the 36 feature tables. It went beyond 3 baseline SDs in only 1 run (linear / DLSU Library / highload, −5.7 dB).
- "Where is the MAC layer in your cross-layer dataset?" No MAC retry count reaches the app (D-15); the sniffer reads the Retry bit on the runs it could place (7 in the paper, 26 on slide 32); the MAC side also rests on RSSI and link and parent state.

## Slide 32: Blackhole, the real MAC retry rate

New in deck v18.

**On the slide:** a bar chart, % of frames retried by phase (baseline teal, attack orange) for all links, stationary, high load, burst and the attacker's link; a "How to read it" box; a footnote on the method and source.

| Claim | Proven by | Mark |
|---|---|---|
| Method: retried ÷ unicast data frames between mesh boards, pooled per phase; bar = mean of per-run rates; latest capture per run | Matches the definition in `tools/pcap_retry.py` (header and `data_frames()`). The averaging and the "latest capture per run" rule are in `tools/macretry_summary.py`, **not in the repository** | ✅ (definition) ⚠️ (summary) |
| 26 runs with frames in both phases; 1 more with no attack-phase frames; 27 of 36 runs usable | Consistent with slide 13 (28 usable captures = 27 runs). No repository output to check against | ⚠️ |
| All links 34.8% → 37.5%; +2.7 points mean, median +0.8, up in 16 of 26, range −7.6 to +15 | Same: from the missing summary script; not in the paper | ⚠️ |
| Stationary 31.6 → 35.0; high load 37.8 → 39.4; burst 33.6 → 37.3 | Same | ⚠️ |
| Attacker link 31.9 → 39.2; +7.3 mean, median +5.1, up in 20 of 26; median frames 1,063 (attack) vs 3,672 (baseline) | Same. Fewer attack frames fits the attack itself: the attacker stops relaying (paper 6.2.1) | ⚠️ |
| "Extends Section 6.2.4 (7 runs in the submitted paper) with captures processed after submission" | True: paper 6.2.4 reports 7 sniffer runs | ✅ |
| "A plain Wireshark count for one run agrees in direction, within about 4 points" | Not in any repository record. One hand count exists on GitHub for the backup run: victim → attacker 37.8 / 38.8 / 42.0% (Kyle, study guide v10 11.7) | ⚠️ |
| "Context, not a detector" | Fair: the shift is small next to the run-to-run spread; MacRetryRate is not a clustering input | ✅ |

**Must fix before the defense:** push `tools/macretry_summary.py`, its output `docs/data-and-results/macretry_summary.txt` and the `_retry.json` / `_retry.csv` files it read, so "show me" can be answered. On this laptop no capture has a blackhole retry result.

**Safe line:** "Across the network the retry rate moved little, 34.8 to 37.5 percent, up in only 16 of 26 runs. The attacker's own link rose more, but on about a third of the frames. Context, not a detector."

**If asked:**

- "Why does the attacker's link go up?" Not tested. It rests on far fewer frames, so a few extra resends move the percentage a lot. Don't offer a cause.
- "Why not victims only?" The summary was not split by role.
- "Is the sniffer complete?" No: one channel, frames it never heard are unknowable (`pcap_retry.py`). Read frame counts as well as the percentage.
- Don't say "flat" or "no change": the attacker's link rises about 7 points.

Deep dive: Study Guide v22, 11.7 (the blackhole seen from the air; the paper's 7 runs).

## Slide 33: Five methods, five ideas of a group

New in deck v18. A picture slide (one image), no speaker notes.

**On the slide:** five cards (K-Means: round groups around a centre; Ward: merges small groups step by step, keeping each tight; GMM: oval clouds, a window can sit between two; DBSCAN, tagged "MAIN METHOD": crowded areas of any shape, lonely windows are noise; Spectral: links neighbours, cuts the network where it is thinnest) and the line "Same windows, same features, and the label is never shown. If the methods agree, the pattern is in the data, not in the method."

| Claim | Proven by | Mark |
|---|---|---|
| The five algorithms and their one-line ideas | Paper 4.2.5, 6.4.1; Study Guide v22, 7.2 | ✅ |
| DBSCAN = "MAIN METHOD" | Primary in the Chapter 4 plan (Study Guide v22, 7.2: "primary in the plan"). The headline results on slides 35 to 37 are **K-Means** (0.514 / 0.996); DBSCAN scored 0.485 / 0.940 (Table 6.25) | 🔶 |
| "The label is never shown" | Paper 4.3.2, 6.4.1: unsupervised; purity and ARI use the label only afterwards | ✅ |
| "If the methods agree, the pattern is in the data" | Blackhole with PDR: 4 of 5 agree (K-Means 0.514, GMM 0.514, Ward 0.503, DBSCAN 0.485); **Spectral does not** (−0.001 all nodes, 0.008 victims). Without PDR all five sit at chance (−0.016 to 0.002) | 🔶 |
| Speaker notes | None | ⚠️ |

**Safe line:** "Four of the five methods agree on the blackhole when PDR is in; spectral clustering does not. Without PDR, all five sit at chance."

**If asked:**

- "Which method gives 0.514?" K-Means, k = 2, REDUCED set. Don't credit it to DBSCAN.
- "Why was DBSCAN the main method?" It needs no number of groups and marks odd windows as noise; eps comes from the k-distance knee (backup slide 71).

## Slide 34: Clustering, how the data were asked to sort themselves

**On the slide (deck v18):** the algorithm list now starts with DBSCAN; "FULL: 8 features" (the "allowed by the leakage guard" wording and the "6,000 sampled windows …" line were removed).

| Claim | Proven by | Mark |
|---|---|---|
| 5 algorithms: DBSCAN (eps at the k-distance knee), K-Means, Ward, GMM, Spectral | Paper 4.2.5, 6.4.1 | ✅ |
| FULL = 8 features | Paper 6.4.1, Table 6.24 (the 8 the leakage guard allows) | ✅ |
| REDUCED = PDR, RSSI_mean, RSSI_var, RSSI_Hop_Diff | Paper Table 6.24 (low-variance filter removed ParentSwitchRate, HopChangeCount, HopStabilityDuration, RSSI_stability) | ✅ |
| Without PDR: the 3 RSSI features, as a control | Paper Table 6.24 | ✅ |
| Purity and ARI: agreement with the label, computed only afterwards | Paper 4.2.5, Equations 4.21 to 4.24 | ✅ |
| "Scores: 4" with only purity and ARI listed | Silhouette is now on slide 35; Davies–Bouldin is only in backup slide 74. The count still says 4 | ⚠️ |
| (Notes, no longer on the slide) 6,000 sampled windows per seed (42, 7, 123), standardised, k = 2 to 8 | Paper 6.4.1 | ✅ |

**If asked:** "Why are 16 features cut to 8?" The relay features, RetryRate and the tunnel features are kept out because each gives the label away (the paper calls this the leakage guard); LatencyHopRatio's blanks predict the label in 86% of windows (slide 54).

## Slide 35: How to read the clustering scores

**On the slide (deck v18):** a silhouette row was added above purity and ARI.

| Claim | Proven by | Mark |
|---|---|---|
| Score definitions and scales | Paper 4.2.5, Equations 4.21 to 4.24 | ✅ |
| Silhouette: −1 to 1, higher = tighter, never sees the label, "describes shape, not the attack" | Paper 4.2.5; Study Guide v22, 7.3 | ✅ |
| Purity 0.70 = no separation (the majority rate) | Paper 6.4.1 (0.702 = majority rate) | ✅ |
| 0 without PDR (−0.016 to 0.002); 0.514 K-Means all nodes; 0.515 best possible; 0.996 victims only | Paper 6.4.2, 6.4.3, Table 6.25 | ✅ |
| (Notes) a high silhouette does not mean the clusters match the attack: FULL k = 2 silhouette 0.77 / 0.90, ARI 0.172 | Paper 6.4.3; backup slides 73 and 74 | ✅ |

## Slide 36: Blackhole clustering, PDR carries all the separation

| Claim | Proven by | Mark |
|---|---|---|
| K-Means ARI 0.514 on all non-attacker nodes; best possible 0.515 | Paper 6.4.3, Table 6.25 | ✅ |
| ≈ 0 for every algorithm and k without PDR (−0.016 to 0.002) | Paper 6.4.2, Figure 6.18 | ✅ |
| Victims only: K-Means 0.996 | Paper Table 6.25 | ✅ |
| Notes: FULL K-Means 0.172 (0.515, 0, 0 per seed); attack found at k = 4 (0.505) | Paper 6.4.3 | ✅ |
| Notes: inside every site and topology within 0.03 of the ceiling; run-level 0.511 (95% interval 0.41 to 0.63) | Paper 6.4.4; Deck check A | ✅ |

**If asked:** "Why did the silhouette say k = 2 when that split isn't the attack?" The silhouette measures shape, not agreement with the label. On seed 7 the small cluster was 44 windows of extreme RSSI variance; on seed 123 one window with a parent change.

## Slide 37: Why 0.514 is the best possible score

**On the slide:** 38,232 attack-labelled windows of non-attacker nodes = 21,733 victims (56.8%) + 16,499 bystanders (43.2%); the best split scores ARI 0.515 and purity 0.870.

| Claim | Proven by | Mark |
|---|---|---|
| Title: "0.514 is the best possible score" | 0.514 is what K-Means **reached**; the best possible is **0.515** | ❌ |
| 38,232 = 21,733 + 16,499 | Paper 6.4.3; Deck check A | ✅ |
| Every board of a blackhole run is labelled attack, bystanders included | Paper 6.1 | ✅ |
| A bystander's PDR stays at 1.000 | Paper 6.2.1 | ✅ |
| Best split ARI 0.515, purity 0.870 = (21,733 + 89,140) ÷ 127,372 | Paper 6.4.3; Study Guide 7.6 reproduces the ARI exactly | ✅ |

**Safe title:** "Why 0.515 is the best possible score" (or "Why 0.514 is as good as it gets").

**If asked:** "ARI 0.514 is mediocre." The ceiling is 0.515 because 43.2% of attack-labelled windows are bystanders, whom the attack never reached; on victims alone the same method scores 0.996.

## Slide 38: PCA and t-SNE, how to read the pictures

| Claim | Proven by | Mark |
|---|---|---|
| PCA: axis 1 holds the most variance; Figure 6.22 PC1 30%, PC2 18% | Paper 4.4, Figure 6.22; Deck check A (figure-only values match the images) | ✅ |
| PCA squashed into a column by a few extreme RSSI-variance windows | Paper 6.4.3 | ✅ |
| t-SNE: only nearness means anything; perplexity 40 | Paper 4.4 | ✅ |
| A group in a picture is not a cluster | Paper 4.4, 6.4.3 | ✅ |

## Slide 39: Figure 6.22, PCA and t-SNE, FULL set (blackhole)

Moved from the backup into the talk in deck v17.

| Claim | Proven by | Mark |
|---|---|---|
| Red island (victims under attack) in the t-SNE | Paper 6.4.3, Figure 6.22 | ✅ |
| PCA 30% and 18%, squeezed into a column by extreme RSSI variance | Paper 6.4.3, Figure 6.22; Deck check A | ✅ |
| Legend 1,004 / 756 / 2,407 / 1,833 (6,000 windows of non-attacker nodes) | Figure 6.22 | ✅ |

## Slide 40: Figure 6.23, the same windows without PDR

Moved from the backup into the talk in deck v17.

| Claim | Proven by | Mark |
|---|---|---|
| All four colours on top of each other without PDR | Paper 6.4.3, Figure 6.23 | ✅ |
| PCA 38% and 32%; features RSSI_mean, RSSI_var, RSSI_Hop_Diff | Figure 6.23; Table 6.24 | ✅ |

**If asked:** "The red island on the slide before looks like a detector." It is a picture of delivery loss; remove PDR and it disappears. PDR is also the verifier's own check, so this is not independent evidence (slide 56).

### Check-in (Part D)

- **Q:** Slide 37's title says 0.514 is the best possible score. Explain in two sentences why that is wrong and why 0.514 is still an excellent result.

> [!question]- Answer (click to reveal)
> - 0.514 is what K-Means reached; the best possible ARI on these labels is 0.515, the score of the split "victim attack windows vs. everything else" (21,733 vs. 105,639 of 127,372 windows).
> - It is excellent because 43.2% of the attack-labelled windows belong to bystanders the attack never reached, so no feature can place them with the attack; K-Means came within 0.001 of the ceiling, and on victims alone it scores 0.996.

---

# Part E: Wormhole, benign runs and Chapter 7 (slides 41 to 64, Presenter 4)

## Slide 41: Divider (wormhole results)

No claims.

## Slide 42: Wormhole, confirmed in all 36 runs

**On the slide (deck v17):** 36 / 36 (21 strong, 15 good); duplicate rate of end B 0 → 0.986 to 1.000; tunnel traffic ≤ 0.001 → 0.994 to 4.0 messages/s; 99.86% of B's probes twice (12,448 of 12,465); 0 duplicates in baseline, cooldown or from other boards; 3.9 ms median gap; "no victims: the attack is the duplication"; 6,468 of 6,469 attack windows (99.98%); three time-series panels.

| Claim | Proven by | Mark |
|---|---|---|
| 36 / 36 = 21 strong + 15 good | Paper 6.5.1, Table 6.11 (15 good = 9 partial mesh plain-tree notes + 6 runs with no saved root run log) | ✅ |
| 12,448 of 12,465 (99.86%) | Paper 6.2.2 | ✅ |
| 0 duplicates in baseline or cooldown; none from other boards | Paper 6.2.2 (baseline 0 of 20,717); #95: 0 of 8,983 baseline and 0 of 3,595 cooldown windows of B, no other board ever (30 runs here) | ✅ |
| Median gap 3.9 ms | Paper 6.2.2 | ✅ |
| Duplicate rate 0 → 0.986 to 1.000 | Paper Table 6.11 | ✅ |
| Tunnel traffic ≤ 0.001 → 0.994 to 4.0 messages/s | Paper 6.3.2 (0 → 1.92 msg/s on average; highload about 4) | ✅ |
| No victims: only B's own probes are tunnelled | Paper 4.2.1.3, 4.2.7.4 (non-tunnel boards 0.9999) | ✅ |
| Notes: DuplicateRate 36 / 36 (baseline 0, attack 0.986 to 1.000); TunnelIntensity 36 / 36 | Paper Table 6.11 | ✅ |
| Notes: 6,468 of 6,469 attack windows of B held a duplicate | Paper 6.2.2 | ✅ |
| Notes: end A received 99% to 101% of what B sent | Paper 6.2.2 | ✅ |

**Careful:** #95 rechecked the duplicates on 30 of the 36 wormhole runs; the 6 tree wormhole tables were not on that laptop. The paper covers all 36.

**If asked:** "Why does the wormhole have no victims?" Only B's own probes are tunnelled; the attack is the duplication. Other boards' PDR stays at 0.9999.

## Slide 43: Figure 6.4, hops skipped by the tunnel

| Claim | Proven by | Mark |
|---|---|---|
| Hops skipped 1 to 5: linear 2 to 5 (median 4), partial mesh 1 to 2, star 1, tree 1 to 2 | Paper 6.2.2, Table 6.12 | ✅ |
| Gaps between 2 and 10 ms (run medians 2.0 to 9.9 ms) | Paper 6.2.2 | ✅ |
| No clear trend across all runs (Spearman 0.25, p = 0.14) | Paper 6.2.2 | ✅ |

**Careful (paper wording):** 6.2.2 says "the spread does not grow with the hops skipped", but the 4- and 5-hop linear tiles are the highest. Safe: "no relation can be claimed from 36 runs (Spearman 0.25, p = 0.14)".

## Slide 44: How to read box plots and Cohen's d

| Claim | Proven by | Mark |
|---|---|---|
| Box = IQR; whiskers ≤ 1.5 × IQR | Figure titles "boxes: IQR, whiskers 1.5 IQR" | ✅ |
| d = (attack mean − baseline mean) ÷ pooled SD; 0.2 / 0.5 / 0.8 | Paper 6.3 | ✅ |
| Most features \|d\| < 0.1; victim PDR \|d\| = 29.71 | Paper 6.3.1, Table 6.18 | ✅ |
| TunnelIntensity d = 1.83; wormhole non-attacker largest \|d\| = 0.06 | Paper 6.3.2, Table 6.19 | ✅ |
| Worked check: 0.998 ÷ 29.71 ≈ 0.034 pooled SD | Arithmetic; Deck check A | ✅ |
| d is a size, not a significance test (windows are not independent) | Paper 6.5.4 | ✅ |

**Careful (paper weak spot):** the Figure 6.15 paragraph says whiskers "reach the 5th and 95th percentiles", but the plotting script uses the default 1.5 × IQR.

## Slide 45: Figure 6.6, spread between the two copies of a probe

| Claim | Proven by | Mark |
|---|---|---|
| Typical gap a few ms in every topology; rare long delays | Paper 6.2.2: median 3.9 ms, 90th 12.1 ms, 99th 417 ms, 84 windows above 200 ms | ✅ |
| Weak, not significant link with hops skipped (Spearman 0.25, p = 0.14) | Paper 6.2.2 | ✅ |
| Whiskers 5th to 95th percentile (this figure) | Slide's own reading guide | ✅ |

**Careful (new in v18 order):** the box-plot guide (slide 44) now comes right before this figure and says whiskers reach 1.5 × IQR. This figure's whiskers are the 5th to 95th percentiles. Say so when you show it, or a panelist will see the mismatch.

## Slide 46: Figure 6.12, wormhole feature distributions by phase

| Claim | Proven by | Mark |
|---|---|---|
| Only the tunnel panels change, and only on A and B in the attack | Paper 6.3.2, Figure 6.12 | ✅ |
| Signal-strength boxes the same before and during the attack | Paper Table 6.19 (\|d\| ≤ 0.07) | ✅ |
| Flat dashes = never changed or not on that board; PDR only for the other children | Paper Table 6.8 (PDR not scored on the tunnel ends) | ✅ |
| Notes: TunnelBytes 0 → 57.5 bytes (30 bytes × 1.92) | Paper 6.3.2 | ✅ |
| Notes: B's RetryRate 0.00 → 0.50 is the tunnel counter, not retries | Paper 6.3.2, D-15 | ✅ |

## Slide 47: Wormhole predictions, traffic yes, radio and routing no

**On the slide (deck v18):** all nine indicators of Table 3.5, each with observed (No, Not measured, Yes) and the measured value. The retransmission row changed from "Not measurable" to "No" with sniffer numbers; the header now says "One indicator cannot be measured".

| Claim | Proven by | Mark |
|---|---|---|
| Hop count consistency: no, 0 windows with a hop change | Paper 4.2.7.4, Table 6.16 | ✅ |
| Parent-child validity: no, 0 windows with a parent change | Paper 4.2.7.4, Table 6.16 | ✅ |
| Routing table entries: not measured (the firmware does not log them) | Paper Table 6.16 | ✅ |
| RSSI-hop correlation: RSSI_Hop_Diff A 2.79 → 2.76 dB; B 5.41 → 5.68 dB | Paper Table 6.16; Deck check A | ✅ |
| RSSI variance: d −0.03 (A), −0.07 (B) | Paper Table 6.16 | ✅ |
| Frame arrival pattern: yes, 99.86% of B's probes twice | Paper 6.2.2 | ✅ |
| Retransmission count (v18): "No. Sniffer, 18 runs: 29.1% → 28.5%; end A's link 28.9% → 23.2%" | **The paper says "not measurable"** (6.3.2, Table 6.16: B's counter holds the tunnel frames, D-15) and has no wormhole sniffer data. The 18-run numbers come from the missing summary script (slide 48) | ⚠️ |
| "One indicator cannot be measured" (the routing table) | Consistent with the slide's rows; differs from the paper's Table 6.16, which has two | 🔶 |
| Duplicate arrivals: yes, 6,468 of 6,469 (99.98%) | Paper 6.2.2 | ✅ |
| Latency mismatch: yes, median 3.9 ms | Paper 6.2.2 | ✅ |
| Notes (CAUTION block): "add a D-entry and a checklist row before quoting it as a paper result" | The team's own notes say the wormhole phase placement is not yet documented | ⚠️ |

**If asked:** "What cannot be measured?" The routing table: it exists, but our firmware does not log it. If a panelist holds the paper: Table 6.16 lists retransmissions as "not measurable" because the app counter on end B mixes tunnel frames with retries; the slide's "No" comes from the sniffer, added after submission. Out-of-order arrivals were rare (0.93%).

## Slide 48: Wormhole, the real MAC retry rate

New in deck v18.

**On the slide:** the same bar chart as slide 32 for the wormhole (all links, stationary, high load, burst, end A's link), a "How to read it" box, and a footnote: the attack window is found from end A's uplink rate rising for the attack's 181 s; "Not in the submitted paper, which had no wormhole sniffer data".

| Claim | Proven by | Mark |
|---|---|---|
| 18 wormhole runs split by finding the attack in the traffic (end A sends more during the attack) | The idea is backed by one run checked by hand on GitHub (Kyle's verification of `linear-wormhole-stationary-dlsu_library_r1_oct07_0537PM.pcap`: end A's first sends 4.95 → 6.10 → 5.21 /s, step 2.0 s after the attack marker). The 18-run fit itself is **not in the repository**: the repository's `pcap_retry.py` refuses wormhole captures ("Only blackhole runs can be fitted from traffic") | ⚠️ |
| All links 29.1% → 28.5%; −0.7 points mean, up in 10 of 18, range −11.6 to +5.8 | From the missing summary script; not in the paper | ⚠️ |
| Stationary 30.0 → 29.9; high load 30.5 → 29.7; burst 27.0 → 25.8 | Same | ⚠️ |
| End A link 28.9 → 23.2; −5.7 mean, median −1.8, down in 13 of 18; median frames 985 (attack) vs 280 (baseline) | Same. More frames from A in the attack fits the tunnel (A sends B's copies on) | ⚠️ |
| "Weakest step 1.4 times"; attack = 181 s | Not in any repository record. The attack phase is about 180 s (paper 4.2.3) | ⚠️ |
| "Only 18 of 71 wormhole captures could be split, and star has just 2" | Consistent with slide 13 (18 usable of 71) | ⚠️ |
| "Not in the submitted paper, which had no wormhole sniffer data" | True: paper 6.2.4 covers blackhole sniffer runs only | ✅ |
| Notes: the phase placement is "D-43" | The paper's deviations end at D-37; no repository record has a D-43 | ⚠️ |
| Notes: "RetryRate on end B holds the tunnelled frames, the other boards are 0" | Paper 6.3.2 (B's RetryRate 0.00 → 0.50) | ✅ |
| "Context, not a detector" | Fair: no network-wide change | ✅ |

**Must fix before the defense:** push the newer `pcap_retry.py` (wormhole fit), `tools/macretry_summary.py` and its output; write the D-entry (the notes call it D-43) and the checklist row, and get the adviser's check, before calling this a result.

**Safe line:** "Across the network the radio retry rate did not move, 29.1 to 28.5 percent on 18 runs. These numbers are after submission and not in the paper. The radio doesn't see the tunnel any more than the routing does."

**If asked:**

- "Does the sniffer see the tunnel?" Not the wire. It sees about one extra frame a second at end A during the attack, matching the root's 181 duplicates in 180 s (backup slides 93 to 95).
- "Why does end A's rate fall?" Not tested; don't offer a cause.
- "Why only 18 of 71?" 21 run logs lost their phase markers, 9 runs had no run log, 19 captures showed no clear step, 4 runs were incomplete or rebooted.

Deep dive: Study Guide v22, 11.8 (the wormhole seen from the air: what it can and cannot show).

## Slide 49: Wormhole and pooled clustering

| Claim | Proven by | Mark |
|---|---|---|
| Wormhole non-attacker boards: ARI −0.012 to 0.003, every algorithm and k | Paper 6.4.6, Table 6.28 | ✅ |
| Deck v17 heading: "Wormhole: only the tunnel counter shows it" | Paper 6.4.6 (signal only with TunnelIntensity added) | ✅ |
| Tunnel ends with RSSI features: −0.012 to 0.009 | Paper 6.4.6 | ✅ |
| Diagnostic only: DBSCAN 0.827 on B with TunnelIntensity | Paper 6.4.6 (TunnelIntensity is blocked from model inputs by the leakage guard) | ✅ |
| Pooled 80 runs, three labels: K-Means 0.333, best possible 0.334 | Paper 6.4.7, Table 6.32 | ✅ |
| As a detector: 21,733 of 21,733 victim attack windows; 0 of 22,481 benign; 183 of 89,140 normal blackhole-run; 3 of 32,194 wormhole attack | Paper 6.4.7; Deck check A | ✅ |

**If asked:** "Is 0.333 a good score for three labels?" It equals the ceiling: the model finds the blackhole victims and nothing else. The wormhole is not found by the non-attacker features.

## Slide 50: Why the wormhole hides from cross-layer features

**On the slide:** three reasons with a number each (≈ 0 ARI on non-attacker boards; 0.827 with TunnelIntensity, diagnostic; 0.333 pooled, best possible 0.334).

| Claim | Proven by | Mark |
|---|---|---|
| Application-layer relay: 0 hop changes, 0 parent changes | Paper 4.2.7.4, Table 6.16 | ✅ |
| RSSI d −0.03 (end A), −0.07 (end B) | Paper Table 6.16 | ✅ |
| Non-attacker boards: ARI −0.012 to 0.003, every algorithm and k | Paper 6.4.6, Table 6.28 | ✅ |
| No victims: non-attacker PDR 0.9999, largest \|d\| = 0.06 | Paper 6.3.2, Table 6.19 | ✅ |
| TunnelIntensity d = 1.83; duplicate rate 0 before, about 1 during | Paper 6.3.2, Table 6.19; Table 6.11 | ✅ |
| The tunnel counters are kept out of the models | Paper 6.4.1, Table 6.24 (the leakage guard). v18 removed the sentence "The leakage guard keeps them out of the models" from the slide; the script says it in plain words | ✅ |
| DBSCAN 0.827 on end B with TunnelIntensity, a diagnostic only | Paper 6.4.6 | ✅ |
| Pooled 80 runs, K-Means 0.333, best possible 0.334 | Paper 6.4.7, Table 6.32 | ✅ |
| Speaker notes | None yet | ⚠️ |

**If asked:** "So nothing detects your wormhole?" The root's duplicate check finds it in 6,468 of 6,469 attack windows, but DuplicateRate is a verifier primary, so it is not a cross-layer detection.

Figure 6.24 (wormhole clustering against k) moved to backup slide 77 in v18; its evidence is in Part F.

## Slide 51: Figure 6.25, PCA and t-SNE of the wormhole runs

In the talk since deck v17. In v18 the slide lost its "How to read it" box; the figure fills the slide.

| Claim | Proven by | Mark |
|---|---|---|
| Colours mixed except with TunnelIntensity added | Paper 6.4.6, Figure 6.25 | ✅ |
| TunnelIntensity is 0 in every normal second | Paper 6.3.2 | ✅ |
| "How to read it" box | Removed in v18; the notes still start with a stray "1.7.2013" | ⚠️ |

## Slide 52: Divider (benign runs and both attacks)

No claims.

## Slide 53: Benign runs, no attack signature

| Claim | Proven by | Mark |
|---|---|---|
| 8 / 8 confirmed benign, all strong | Paper 6.2.6 | ✅ |
| 0 of 21 evaluable signature checks passed (43 others had no data, as expected) | Paper 6.2.6 | ✅ |
| 24 of 24 cooldown comparisons within 0.5 baseline SD | Paper 6.3.3 | ✅ |
| Mean PDR per run 0.9994 to 1.0000 | Paper 6.2.6 | ✅ |
| 8 runs: enough as a control | Paper 6.5.4 | ✅ |
| "Benign runs were done just for suplementation to the normal activity set on the runs" | Typo ("supplementation"). The paper's main normal reference is each run's own baseline (D-5), so the idea holds | ⚠️ |
| Removed in deck v17: "not enough for a false-alarm rate" and "scenario and site are confounded" | Both still in the paper (6.5.4, Recommendation 2). Say them if asked | 🔶 |

**Moved here from the removed slide "Signal strength separates captures, not attacks" (v16 slide 48):**

| Claim | Proven by | Mark |
|---|---|---|
| 8.1 / 7.1 dB mean baseline RSSI difference between two set-ups of the same cell | Paper 6.3.3, Table 6.23, Figure 6.16 | ✅ |
| RSSI_mean is the only big difference between benign and attack-run normal windows (d = 0.69) | Paper Table 6.22 | ✅ |

**If asked:** "Why is RSSI so different between runs of the same cell?" Each capture is a new set-up; RSSI depends on exactly where each board stands. With one run per cell, site effects cannot be separated from set-up variation.

## Slide 54: Can one feature decide it? The single-feature audit

| Claim | Proven by | Mark |
|---|---|---|
| Majority rate ≈ 70% (420 normal s of 600 s) | Paper 6.2.3; panel majorities 69.96 / 69.97 / 70.06% | ✅ |
| PDR 99.9% on victims, 86.9% on all nodes | Paper Table 6.13; Study Guide 6.5 recomputed every bar from the 36 tables (86.90% = 1 − (16,499 + 84 + 99) ÷ 127,372) | ✅ |
| LatencyHopRatio's blanks give the label away (99.2% on victims), so it is not clustered | Paper 6.2.3 | ✅ |
| Wormhole non-attacker nodes: no feature beats 70% by more than 0.01 | Paper Table 6.14 | ✅ |
| Run clock 80% = the fixed schedule, not a feature | Paper 6.2.3 | ✅ |

**If asked:** "If PDR alone detects the blackhole, why cluster at all?" That is exactly what this audit tests, and we report it. Any future model must beat a plain PDR threshold (Recommendation 5).

## Slide 55: EDA, only the delivery of the victims moves

| Claim | Proven by | Mark |
|---|---|---|
| Victim PDR 0.998 → 0.000, d = −29.71; every other feature \|d\| < 0.1 | Paper 6.3.1, Table 6.18 | ✅ |
| Wormhole non-attacker PDR 0.9999 → 0.9999; largest \|d\| = 0.06 | Paper 6.3.2, Table 6.19 | ✅ |
| On the ends only tunnel features change (0 → 1.92 msg/s) | Paper 6.3.2 | ✅ |
| Notes: victims' RSSI already 2.5 dB weaker in the baseline (−74.7 vs −72.2 dBm) | Paper 6.3.1; Deck check A | ✅ |
| Notes: bystanders' LatencyHopRatio 4.26 → 3.15 → 2.46 ms/hop follows the course of a run (benign runs do the same) | Paper 6.3.1 | ✅ |

## Slide 56: Discussion, the attacks live in the data plane

| Claim | Proven by | Mark |
|---|---|---|
| Blackhole row: FR → 0.000–0.007; victim PDR 0.998 → 0.000; 0.514 (ceiling 0.515), ≈ 0 without PDR | Paper 6.5.1, Table 6.33 | ✅ |
| Wormhole row: 99.86% twice; no cross-layer change (\|d\| ≤ 0.07); ≈ 0 without a tunnel feature | Paper 6.5.1, Table 6.33 | ✅ |
| Benign row: 0 of 21; 24 of 24; 0 of 22,481 in the victim cluster | Paper 6.5.1, Table 6.33 | ✅ |
| Honest qualifier: PDR is also the verifier's check, so clustering is not independent evidence | Paper 6.5.1 | ✅ |
| Main reading (v18): "PHY and network features stay where they were, and the radio retry rate moves little (+2.7 points blackhole, −0.7 wormhole)" | PHY / network: paper 6.5.1. The retry numbers: slides 32 and 48, after submission, source not in the repository | ✅ ⚠️ |
| Notes (v18): limits list "sniffer retry rate on 27 blackhole and 18 wormhole runs only" | Paper 6.5.4 says the sniffer covered 7 runs | 🔶 |

**If asked:** "So your cross-layer features failed?" They did not respond because these attacks never touch radio or routing. Whether they help against routing attacks is Recommendation 1.

## Slide 57: Figure 6.30, pooled 80 runs, FULL set

| Claim | Proven by | Mark |
|---|---|---|
| Only the red dots (blackhole victims under attack) stand apart | Paper 6.4.7, Figure 6.30 | ✅ |
| PCA 30% and 19% | Figure 6.30 (Deck check A: matches the image) | ✅ |

## Slide 58: Figure 6.31, pooled 80 runs, PDR removed

| Claim | Proven by | Mark |
|---|---|---|
| All six groups mixed without PDR; PCA 38% and 31% | Paper 6.4.7, Figure 6.31 | ✅ |
| Notes: pooled ARI without PDR −0.023 to 0.005 | Paper 6.4.7 | ✅ |

## Slide 59: Compared with published studies

| Claim | Proven by | Mark |
|---|---|---|
| Baseline PDR 0.998 victims; 0.9994–1.0000 benign vs > 0.97 Khan [22] | Paper Table 6.34; Khan p. 18 (except node H; campus test, every 2 min) | ✅ 🔶 |
| PDR under blackhole 0.000 vs "25–40% delivery" [70] | [70] p. 53: loss 60 to 75%. "25–40% delivery" is **our** arithmetic (100 − loss), not their wording | ✅ 🔶 |
| Parent changes 0.00000 → 0.00009 per s vs 16 to 246 rank changes [70] | Paper 6.2.4; [70] pp. 51 to 52 | ✅ |
| Reading column "Differs: their attack acts on routing (D" | A cut-off bracket left after the deviation number was deleted | ⚠️ |
| Wormhole hop count constant vs 4 → 3 hops [71] | Paper 4.2.7.4; [71] Table 7, p. 28 | ✅ |
| 3.9 ms spread vs 80–100 → 120–200 ms (about +40%) [71] | Paper 6.2.2; [71] Table 7 p. 28 and abstract p. 1 (the source is not fully consistent) | ✅ |
| 99.86% duplicates vs "proposed as a signature" [72] | Paper 6.2.2; [72] p. 55 (routing packets, proposed) | ✅ |
| Notes: Khan's figure "from a multi-day stability test" | The 97% / node H figures are from the **campus** test; the 60 s stability test gave above 98% | 🔶 |

**If asked:**

- "Your PDR is higher than Khan's, why?" Different counting: they count packages over five days at up to 100 m outdoors; we count per one-second window over 11 minutes.
- "Did Khan use the same stack?" No: PainlessMesh (their p. 13). Same board family, so we compare size only.

## Slide 60: Divider (Chapter 7)

No claims.

## Slide 61: The three objectives, answered

| Claim | Proven by | Mark |
|---|---|---|
| Objective 1 achieved: 80 of 80 runs; 72 of 72 confirmed; 8 of 8 benign; qualifiers: emulated attacks, partial mesh = branched tree | Paper 7.3, 7.4 | ✅ |
| Objective 2 achieved: 16 features, labels from the schedule, every change documented; qualifier (v18): "no MAC retry count on the boards (D-15); a sniffer gives it for 45 runs" | Paper 7.4; D-15. The cut-off "(D" is fixed in v18. 45 = 27 blackhole + 18 wormhole runs from slides 32 and 48 (after submission; the paper says 7) | ✅ 🔶 |
| Objective 3 "Achieved" | Paper 7.4 says the answer **differs by attack** | 🔶 |
| "Wormhole: through Duplicate Rate (−0.012 to 0.009)" | −0.012 to 0.009 is the clustering score **with the cross-layer features** (6.4.6). Duplicates are seen at the root (6.2.2), but DuplicateRate is not a clustering input | ❌ |
| Blackhole through PDR only (0.514 vs 0.515) | Paper 7.4 | ✅ |

**Safe line for objective 3:** "Achieved, and the answer differs by attack: the blackhole through PDR only (0.514 against 0.515); the wormhole only through the duplicates at the root, with the cross-layer features scoring −0.012 to 0.009."

**Careful (paper typos):** 7.3 "he attack" (missing T); 7.6 a stray backtick after "directly".

## Slide 62: Limits and what should come next

| Claim | Proven by | Mark |
|---|---|---|
| Five limitations (deck v17 removed "Only 8 benign runs: no reliable false-alarm rate") | Paper 6.5.4, 7.5 still list the benign limit; Recommendation 2 depends on it | ✅ 🔶 |
| "Three campus sites (one semi-outdoor)" | Paper 1.4 says the sites are indoor | 🔶 |
| (v18) "No direct MAC retry count; sniffer on 27 blackhole and 18 wormhole runs only" | Paper 6.5.4 says 7 sniffer runs; 27 + 18 are after submission (slides 32, 48) | 🔶 |
| Five recommendations | Paper 7.6 | ✅ |

**If asked:** "Do your results generalise?" No claim beyond 8 ESP32 boards, three campus sites, three scenarios and application-layer attacks (6.5.4).

## Slide 63: Findings and contributions

| Claim | Proven by | Mark |
|---|---|---|
| Four findings (delivery loss, duplicates, no parent/hop/signal change, clustering depends on the attack's feature) | Paper 7.5 | ✅ |
| Finding 3 (v18): "radio retries barely moved" | Paper 7.5 says retransmissions did not change (7 sniffer runs). "Barely moved" matches the deck's larger, after-submission numbers | ✅ 🔶 |
| Three contributions: testbed, dataset, verification process | Paper 7.5; firmware and tools in the project repository [79] | ✅ |

## Slide 64: Thank you

| Claim | Proven by | Mark |
|---|---|---|
| Notes: detection depended on delivery and duplication; not proof for routing-level attacks | Paper 7.7 | ✅ |

### Check-in (Part E)

- **Q:** A panelist says: "Your wormhole duplicates are 99.86%, so your clustering should find the wormhole easily. Why is the ARI about zero?"

> [!question]- Answer (click to reveal)
> - The duplicates are seen at the **root** and in the **ends' own counters** (TunnelIntensity, DuplicateRate). Those are tunnel features, which the leakage guard keeps out of the clustering inputs because they are zero in every normal second and would give the label away.
> - The cross-layer features of the clustering (RSSI, hop, parent) did not change, because the tunnel is an application-layer relay: no hop or parent changed (0 windows) and RSSI moved by \|d\| ≤ 0.07. So on those features the ARI stays between −0.012 and 0.009. Adding TunnelIntensity as a diagnostic lets DBSCAN reach 0.827 on end B, which shows the signal exists, but only in the attackers' own counters (6.4.6).

- **Q2 (new in v18):** A panelist points at slides 32 and 48 and asks: "Your paper says retransmissions were measured on 7 runs. Where do 26 and 18 come from, and can you show me?"

> [!question]- Answer (click to reveal)
> - Say it straight: the 26 blackhole and 18 wormhole runs are the same sniffer method (Retry bit ÷ data frames between mesh boards) applied to captures processed **after** the paper was submitted. The slides' footnotes say so. They are context, not a detector, and they do not change any conclusion: the retry rate moved little in both attacks.
> - For "show me": only if the team has pushed `tools/macretry_summary.py`, its output and the newer `pcap_retry.py` by then. Without them, show one capture in Wireshark instead (backup slides 89 to 95) and say the summary is being added to the repository.

---

# Part F: Backup slides (65 to 95)

Not part of the timed talk. Open one only when a panelist asks about that figure. Every paper figure below was matched to the paper or to the figure image in Deck check A. In deck v18, Figure 4.58 (now 67) and Figure 6.24 (now 77) moved here from the talk, and the sniffer figures (88 to 95) are new.

| Slide | Figure | What the slide claims | Proven by | Mark |
|---|---|---|---|---|
| 65 | Divider: the other figures | No claims | — | — |
| 66 | Divider B1: blackhole figures | No claims | — | — |
| 67 | Figure 4.58, dataset check of one run (moved from the talk in v18) | Blackhole, partial mesh, G402, highload; every bar clears 95% except ED80's baseline (88.7%, 266 of 300 s); the impact check reran without ED80, the attack still confirmed; kept as a minor gap | Paper Figure 4.58, 4.2.7.3; Deck check A. The slide text has the typo "Obersevation" | ✅ ⚠️ |
| 68 | Figure 6.3, the attacker's ForwardingRatio | Drops from 1 to 0 for exactly the attack and comes back; baseline and attack values never overlap (1.000–1.004 vs 0.000–0.007) | Paper 6.2.1, Table 6.9. The notes' 1,077 / 1 example is from the feature table, not the paper | ✅ |
| 69 | Figure 6.9, blackhole feature distributions | Only PDR moves; no victim attack box for LatencyHopRatio (no probe arrived, so no delay) | Paper 6.3.1, Table 6.18 | ✅ |
| 70 | Figure 6.10, correlations | Blackhole child boards only; 4 strong pairs, each formula-linked; no other pair past ±0.4 | Paper 6.3.1, Figure 6.10 (−0.94 / 0.12; 0.65 and 0.78; −0.79 / 0.05; 1.00) | ✅ |
| 71 | Figure 6.17, choosing eps for DBSCAN | eps at the knee: 0.79 (FULL), 0.73 (REDUCED), 0.56 (no PDR); 1 to 2% noise | Paper 6.4.1, Figure 6.17 (curves rise to 47, 35 and 33) | ✅ |
| 72 | Figure 6.18, ARI against k | With PDR the methods find the attack; without PDR every line is flat at 0; K-Means REDUCED k = 2: 0.514 and 0.996 | Paper 6.4.2, Table 6.25 | ✅ |
| 73 | Figure 6.19, silhouette against k | FULL k = 2 silhouette 0.77 / 0.90, but ARI only 0.172; attack from k = 4 (0.505) | Paper 6.4.3 | ✅ |
| 74 | Figure 6.20, Davies–Bouldin against k | No single k is best; k chosen from elbow, silhouette and meaning together | Paper 6.4.3 | ✅ |
| 75 | Figure 6.21, K-Means cluster contents | FULL k = 3 clusters 4,980 / 1,008 / 12; REDUCED 4,697 / 303 / 1,000; one cluster almost all victims under attack | Paper 6.4.3, Figure 6.21 (sizes match the image) | ✅ |
| 76 | Divider B2: wormhole figures | No claims. Slides 78 and 79 under it are **blackhole** figures; move them after slide 75 | — | ⚠️ |
| 77 | Figure 6.24, wormhole clustering against k (moved from the talk in v18) | Flat at 0 for non-attacker boards and for the cross-layer features alone; DBSCAN 0.827 on end B with TunnelIntensity; K-Means k = 2 on B splits by signal (−67.6 vs −47.1 dBm), ARI 0.000 | Paper 6.4.6, Table 6.28 | ✅ |
| 78 | Figure 6.1, delivery collapses in every blackhole run | All 36 tiles at 0.00: no victim probe reached the root during the attack, in any run | Paper Figure 6.1, 6.2.1; #95 (21,733 of 21,733 windows at 0) | ✅ |
| 79 | The same windows, with and without PDR (t-SNE) | With PDR the red victim attack windows form their own island; without PDR all four groups mixed | Paper Figures 6.22 and 6.23 | ✅ |
| 80 | Divider B3: shared figures | No claims | — | — |
| 81 | Figure 4.55, order of the verifier's checks | Same path for every run; PASS / FAIL / INCONCLUSIVE; missing data never a pass or a fail | Paper 4.2.7, Figure 4.55, Table 4.24 | ✅ |
| 82 | Figure 6.13, delivery in the 8 benign runs | All runs at 1.00 apart from small dips in one; 4 of 54 boards below 1, all linear/G402/highload, lowest 0.75; axis starts at 0.95 | Paper 6.2.6, 6.3.3 | ✅ |
| 83 | Figure 6.14, effect of the traffic scenario | Probe rate and PDR match between benign and attack runs (about 1.0, 1.1, 3.9 probes/s); PDR axis starts at 0.90 | Paper 6.3.3 | ✅ |
| 84 | Figure 6.15, normal windows, benign vs attack runs | Only RSSI_mean differs (set-up, not attack); PDR below 1 in 0.03% / 0.24% / 0.01% | Paper 6.3.3, Tables 6.22 and 6.23. Paper says whiskers 5th to 95th; the script uses 1.5 × IQR | ✅ 🔶 |
| 85 | Figure 6.26, normal, blackhole and wormhole windows | K-Means reaches the ceiling (0.333 vs 0.334; 0.315 vs 0.317) but never passes it; without PDR every line at 0 | Paper 6.4.7, Table 6.32 | ✅ |
| 86 | Figure 6.27, pooled clusters, K-Means k = 2 | C0 = 537 seconds, 100% blackhole victims, PDR 0.000; without PDR clusters differ only in signal (−77.2 vs −63.9 dBm) | Paper 6.4.7, Figure 6.27 | ✅ |
| 87 | Figure 6.29, feature values per cluster | C0 = PDR 0 (victims); C2 = 38 noisy high-variance seconds; sizes 537 / 5,425 / 38 | Paper 6.4.7, Figure 6.29 | ✅ |
| 88 | Divider B4: sniffer blackhole | No claims. Circle label reads "B3", corner "16" | — | ⚠️ |
| 89 | Sniffer blackhole: attacker uplink (Wireshark I/O graph, `linear-blackhole-highload-dlsu_library_r1_oct11_0331PM.pcap`) | Attacker 0C80's data frames to the root's access point: about 30 to 100/s, a cliff to a few per second at x ≈ 385, recovery at x ≈ 565 | #89: capture chosen for the defense; attack start fitted from the traffic (attacker uplink 27.4 → 3.4 frames/s for 181 s); 74 to 87 frames/s before, a few per second after; cliff at x ≈ 385 and recovery at x ≈ 565, 180 s apart. Not one of the paper's 7 sniffer runs | ✅ |
| 89 | "It doesn't reach zero, because the attacker still sends its own traffic" | The attacker sends **no probes of its own** (#94). The remaining frames are the board's other mesh traffic, not probes. Say "the board is still a mesh node; only the relaying stops" | 🔶 |
| 90 | Sniffer blackhole: attacker still alive | All frames to or from 0C80's two MAC addresses keep going at about 50 to 200/s; a crashed board would go quiet | The figure itself; #89 (verifier confirmed the run 2/2, attacker FR 1.000 → 0.000) | ✅ |
| 91 | Sniffer blackhole: victim keeps sending | Victim 1C38 → attacker's access point: about 46 / 46 / 49 frames/s (baseline / attack / cooldown); "so the probes are dropped inside the attacker" | Kyle's Wireshark counts (study guide v10 11.7, GitHub): 13,841 / 8,220 / 5,917 frames = 46.0 / 45.7 / 49.3 per s. The drop itself is proven by the attacker's counters and the victims' PDR; the mesh payload is encrypted, so the capture cannot show a packet being dropped (#89) | ✅ 🔶 |
| 92 | Divider B4: sniffer wormhole | No claims. Circle label reads "B3", corner "16" | — | ⚠️ |
| 93 | Sniffer wormhole: end A (tunnel exit), `linear-wormhole-stationary-dlsu_library_r1_oct07_0537PM.pcap` | End A 1C38's first sends per 5 s: about 25 → 30 to 35 → 25; 4.94 → 6.10 → 5.22 per s; the extra matches the root's 181 duplicates in 180 s; attack x ≈ 1566 to 1747 | Kyle's verification on GitHub (`origin/THESIS3`, commit `454161cf`, numbered #91 there): markers x = 1265.8 / 1566.3 / 1746.9 / 1867.4 from the root's beacon clock; A's first transmissions 4.95 → 6.10 → 5.21 /s (Kyle's own count 4.94 / 6.10 / 5.22); root duplicates 0 / 181 / 0; A heard 97 to 100% | ✅ |
| 94 | Sniffer wormhole: end B (tunnel entry) | No step at the attack start; dips are stretches heard mostly as resends; B's sequence numbers show 3.18 / 3.19 / 3.19 frames/s | Same verification: end B 3.17 / 3.18 / 3.15 /s by sequence-number advance (Kyle's later count 3.18 / 3.19 / 3.19) | ✅ |
| 95 | Sniffer wormhole: both ends | Only end A steps up during the attack; B doesn't; "an extra stream of about 1 frame per second at the tunnel exit, only during the attack" | Same verification ("Say: an extra stream of about one frame a second appears at end A … only during the attack"). It also says: do not claim the capture shows the tunnel or the duplicates | ✅ |

**Sniffer backup problems (v18):**

- Slides 89 to 95 are titled "Figure 6.30: Sniffer …". In the paper, Figure 6.30 is the pooled 80-run picture (talk slide 57). Retitle them.
- Slides 89 to 95 carry speaker notes copied from the Figure 6.29 slide ("n = 537, 5,425 and 38 windows; C2 mixes every group").
- The "How to read it" text overflows its box on 91, 93, 94 and 95.
- The wormhole verification lives only on GitHub (Kyle's commit `454161cf`), and it is numbered #91 there while this laptop's `dataset-verification.md` has a different #91 (benign CSV check). Pull, then renumber one of the two.

---

# Part G: If a panelist says "show me"

| They ask to see | Open this | What it shows |
|---|---|---|
| A real row of the dataset (slide 14) | `ESP32-Environment/datasets/analysis/blackhole/tree/G402/stationary/feature_table.csv` | The four rows on slide 14: 1C38 at t_anchor_s −100 and +120, D7B4 and 0C80 at +120 |
| What a column means | `feature_table_legend.csv` in the same folder | One line per column |
| That the attacker sends no probes of its own | `ESP32-Environment/child_node/main/blackhole_victim.c`, line 40 | "The attacker does NOT generate its own probes; it only relays other nodes'." |
| A clean blackhole run end to end | `ESP32-Environment/datasets/analysis/blackhole/linear/DLSU_Library/burst/` | Victims 1 → 0 → 1; burst of 301 probes all dropped; walk-through in Study Guide v22, 3.5 |
| The verifier's verdict for a run | Run `ESP32-Environment/tools/verify_attack.py` on that run (no saved report sits in the analysis folder; rehearse the command before the defense) | A per-feature 3-sigma report and the overall verdict |
| The sensitivity test | `ESP32-Environment/tools/audit_threshold_sensitivity.py`; thresholds in `docs/attack-validation/GRADING-AND-THRESHOLDS.md` | The 7 rules and their tested values (settle 53 / 18 vs 74 / 15 first) |
| A reference study's page | `Resources/` PDFs | Pages listed in Study Guide v22, Part 12 |
| The blackhole on the radio (backup 89 to 91) | `ESP32-Environment/datasets/PCAP/blackhole/linear/DLSU_Library/highload/linear-blackhole-highload-dlsu_library_r1_oct11_0331PM.pcap` in Wireshark, I/O graph, 1 s interval; the exact filters are in #89 | The attacker's uplink cliff at x ≈ 385 and recovery at x ≈ 565, 180 s apart |
| The wormhole on the radio (backup 93 to 95) | `ESP32-Environment/datasets/PCAP/wormhole/linear/DLSU_Library/stationary/linear-wormhole-stationary-dlsu_library_r1_oct07_0537PM.pcap`, I/O graph, 5 s interval, first sends only (`wlan.fc.retry == 0`); filters and markers in Kyle's check on GitHub (commit `454161cf`) | End A steps up from about 25 to 30–35 frames per 5 s between x ≈ 1566 and 1747; end B does not. Wireshark 4.x needs commas in set filters (`{a, b}`) |
| The 26-run and 18-run MAC retry numbers (slides 32, 48) | ⚠️ Nothing to open yet: `tools/macretry_summary.py` and its output are not in the repository | Push them first, or show one capture instead |

**Never open** a run under a `home` site folder: those are not thesis runs, and in `blackhole/linear/home/highload` the victims were **not** cut off (attack PDR 0.62 to 1.00, #95). Before the defense, run `analyze.ps1` on the presenting laptop for the 9 cells that have no feature table on GitHub (6 tree wormhole + 3 benign).

---

# Evidence index

| Source | Path | Used for slides |
|---|---|---|
| Submitted paper | `Plan/Paper-Editing/1-Working-Copy/NIS16-Full_Thesis_Document.docx` | All |
| Deck check A (every number vs the paper) | `verification/…_defense-deck-v2-check.md` | All numbered slides |
| Deck check B (study cards, two signatures) | `verification/…_defense-deck-v13-check.md` | 15, 16, 18, 21 |
| #91 (benign CSV, whole study guide, script check) | `ESP32-Environment/docs/dataset-verification.md` | 9, 12, 17 |
| #92 (attack run row by row; 3-sigma reference = baseline + cooldown) | Same file | 9, 17 |
| #93 (phase 255) | Same file | 9 |
| #94 (attacker sends no probes; blank PDR) | Same file; `verification/…_blackhole-attacker-own-probes.md` | 14 |
| #95 ("What we found" box) | Same file; `verification/…_what-we-found-box.md` | 2, 30, 78, 42 |
| Khan et al. [22] | `Resources/An-Efficient-Wireless-Sensor-Network-…-Air-Quality-Monitoring.pdf`; <https://doi.org/10.3390/su142416630> | 4, 7, 15, 21, 59 |
| Airehrour et al. [70] | `Resources/A-Trust-based-Defence-Scheme-…-RPL-Routing-Protocol.pdf` | 7, 10, 15, 59 |
| Zhukabayeva et al. [71] | `Resources/Real-Time-Detection-and-Response-to-Wormhole-and-Sinkhole-Attacks-….pdf` | 15, 17, 59 |
| Ramírez Gómez et al. [72] | `Resources/Implementing_a_Wormhole_Attack_on_Wireless_Sensor_.pdf` | 15, 59 |
| Karlof and Wagner [81] | Course-hosted copy, §5.2 (publisher PDF not opened) | 7, 15, 18 |
| Hu, Perrig and Johnson [46] | **Not opened** (IEEE paywall); get it through the DLSU library | 10, 15 |
| Feature tables | `ESP32-Environment/datasets/analysis/…/feature_table.csv` | 2, 14, 31 |
| Verifier code | `ESP32-Environment/tools/verify_attack.py` (study tags at lines 487 to 522; missing-board grading lines 649 to 827) | 15 to 21 |
| Feature code | `ESP32-Environment/analysis/features.py` | 12, 14, 16 |
| Firmware | `ESP32-Environment/child_node/main/blackhole_victim.c` | 10, 14 |
| #89 (blackhole sniffer capture for the defense) | `ESP32-Environment/docs/dataset-verification.md` | 89 to 91 |
| Kyle's wormhole capture check (numbered #91 on GitHub) | `origin/THESIS3`, commit `454161cf` (`docs/dataset-verification.md` there) | 93 to 95 |
| Sniffer firmware and retry tool | `ESP32-Environment/sniffer_node/main/sniffer_main.c`; `ESP32-Environment/tools/pcap_retry.py` | 13, 32, 48 |
| MAC retry summary (cited by the slides, **missing**) | `tools/macretry_summary.py`, `docs/data-and-results/macretry_summary.txt` (not in the repository) | 13, 31, 32, 47, 48, 56, 61, 62 |

# Defense deck v2 check (oct. 30, 2026)

**Deck checked:** `Paper/Defense/THESIS3-Defense oct. 30, 2026 (final paper, plain graph guides) v2 (changes highlighted).pptx` (70 slides = 69 + change list).

**Checked against:** the submitted paper, `Plan/Paper-Editing/1-Working-Copy/NIS16-Full_Thesis_Document.docx` (same file as `6- Submit/NIS16-Full_Thesis_Document.pdf`).

## Method

1. Pulled the text of every slide, table and speaker note.
2. Looked up every number in the paper text and tables. Every number not found there was traced by hand.
3. Read the paper passage around about 120 key numbers, to check the number is used in the right place (right table, right population, right direction).
4. Rendered all 70 slides through PowerPoint and checked each one by eye. Checked figure legend counts against the slide text, and looked for text overflow, overlaps and broken images.
5. Compared the clean `v2.pptx` with this review copy.
6. Grepped for dates, tool names, commit references and tree-wormhole firmware content.

## Result: correct, with 3 wording errors and 1 file issue

| # | Slide | Where | Problem | Fix |
|---|---|---|---|---|
| 1 | 35 | Title | "Why 0.514 is the best possible score". The best possible score is **0.515**. 0.514 is what K-Means reached. | "Why 0.515 is the best possible score" |
| 2 | 11 | Notes, last KEY FACTS bullet | Says 1,077 received / 1 forwarded is "as in the paper". It is not in the paper. It comes only from `docs/dataset-verification.md` and the feature table. The paper gives "0.0% to 0.7% forwarded" and Table 4.4 gives "1.000 to 0.001". | Replace "as in the paper" with "matches Table 4.4's 1.000 → 0.001" |
| 3 | 20, 50 | Notes, "Example run" bullet | Same 1,077 / 1, listed under a paper SOURCE line. | Say it comes from the feature table, or use Table 4.4's 1.000 → 0.001 |
| 4 | clean `v2.pptx` only | Slide-number fields | The numbers are real fields, so PowerPoint shows the right number. But the clean file's saved text is stale: slides 13 and 14 store "48", and later slides store their old numbers from before slides 13-14 were added (slide 15 stores 13, slide 20 stores 18). Canva may show the stored text on import. The review copy is correct. | Open the clean v2 in PowerPoint and save once before re-importing it into Canva |

Minor, no change needed:

- Slide 12 notes say "Five checks". The slide shows four (signature, topology, dataset, scenario); the fifth is the setup check (Figure 4.55). Say "four checks plus a setup check" if asked.
- Slides 43-44 (Figures 6.30/6.31) sit after the Chapter 7 divider, but they are Chapter 6 figures (Section 6.4.7). This was the team's Canva request.
- The review copy carries "Canva p..." tags and the change-list slide (70). Present the clean v2, not this file.

## Confirmed correct (sample of what was matched)

| Area | Checked |
|---|---|
| Run design | 80 = 36 + 36 + 8; by site 28 / 26 / 26; benign linear 3, star 3, tree 1, partial mesh 1 (from 21 / 21 / 19 / 19 per topology); phases 254 → label 255, 300 / 180 / 120 s; 5 rounds 100 ms apart, repeated every 10 s; burst 300 probes 60 s into the attack |
| Attacks | UART 115200 baud, 22-byte probe, "PROW"; Table 4.4 = 5 of 6 met; Table 4.5 = 4 of 5 met |
| Topology | Linear deepest hop 7; star hub with 6; tree root 2-5 children, deepest hop 2-4 (Table 6.35); 1 of 132 tree boards changed parent |
| Dataset | 457,568 formed, 1,372 discarded (0.30%); 456,195 total = Table 6.2 phase sum; 369,678 = 266,491 + 103,187; 637 files; 123 victims / 92 bystanders; 36.3% |
| Deviations | 37 = 17 Modified + 20 New (counted in Table 5.2 and stated in Ch 5) |
| Verifier | 0 of 106 placebo; ±50%, 53 runs, 14 settings; 1,000 SD → 18 verdicts; \|z\| ≤ 0.64; 0.90 / 0.15 broken-baseline rule |
| Blackhole | 36/36 = 4 strong + 27 good + 5 minor gaps; FR 1.000-1.004 → 0.000-0.007; PDR 35/36 (0.930 ± 0.253); support 31 / 31 / 32 of 36; IngressEgressDelta misses z 0.4-2.9; 22.9 SD, median 111; 121 of 123 first window, recovery median 2 s, 122 boards; ED80 266 of 300 s (88.7%) |
| Wormhole | 21 strong + 15 good (= 9 partial + 6 no root run log); 12,448 / 12,465 = 99.86%; 6,468 / 6,469; 0 in baseline and cooldown; 3.9 / 12.1 / 417 ms, 84 windows > 200 ms; 232 of 24,913; 99-101% over the wire; hops 1-5; Spearman 0.25, p = 0.14 |
| Predictions | Table 3.5 rows: RSSI_Hop_Diff A 2.79 → 2.76, B 5.41 → 5.68; RSSI_var d −0.03 / −0.07; 9 of 21,742; sniffer 0.295 → 0.364 → 0.323 |
| Benign | 0 of 21 evaluable, 43 without data; 24 of 24; 0.9994-1.0000; 4 of 54 boards, lowest 0.75; probe rate 1.0 / 1.1 / 3.9 |
| Audit | Table 6.13 bars match (86.9 / 99.9, 84.3 / 100.0, 71.7 / 70.0, 70.0 / 70.1, 80.0 / 80.0); 99.2%; 99.7%; 0.01 points; 86% missingness |
| EDA | d −29.71 (pooled SD ≈ 0.034); 1.92 msg/s, d 1.83, 57.5 bytes; −74.7 / −72.2 dBm; 4.26 → 3.15 → 2.46; d 0.69; 8.1 / 7.1 dB |
| Correlations | −0.94 / 0.12; 0.65 (0.78); −0.79 / 0.05; 0.36; 40,000 |
| Clustering | 0.514 / 0.515 / 0.996; 0.870 = (21,733 + 89,140) / 127,372; 38,232 = 21,733 + 16,499; 72,687; eps 0.79 / 0.73 / 0.56, curves to 47 / 35 / 33; 0.172 (0.515, 0, 0); 0.77 / 0.90; k = 4 → 0.505; 0.476 / 0.929; 0.511 (0.41-0.63); within 0.03; 1,010 windows 99.4% |
| Wormhole / pooled | −0.012 to 0.003; −0.012 to 0.009; 0.827; 0.141; −67.6 / −47.1 dBm; 257,258; 0.333 / 0.334, 0.315 / 0.317; 0.017; 21,733 / 0 of 22,481 / 183 of 89,140 / 3 of 32,194; C0 537, −77.2 / −63.9 dBm |
| Figure-only values | Legend counts 1,004 / 756 / 2,407 / 1,833 (Fig 6.22); cluster sizes 4,980 / 1,008 / 12 and 4,697 / 303 / 1,000 (Fig 6.21); 537 / 5,425 / 38 (Fig 6.29); 0.03 / 0.24 / 0.01% (Fig 6.15); PCA 30/18, 38/32, 30/19, 38/31%: all match the images |
| Published studies | Khan > 97%; Airehrour 60-75% loss (< 28% trust-based), 16-246 rank changes; Zhukabayeva 4 → 3 hops, 80-100 → 120-200 ms, 20-30% |
| Not in the paper, and marked as such | Slide 27 RSSI row (−67.1 → −67.8 dBm, 27 of 36) has a † and a footnote; slide 11 rows come from the feature table; slide 15 example is labelled illustrative (−498.5 is the right arithmetic) |
| Hygiene | No development dates, tool names, commit references or D-41 / tree-wormhole firmware content. The only years are publication years of cited papers in the notes |
| Sync | Clean v2 and the review copy have the same text on all 69 slides; only the tags and slide 70 differ |

## Slides 13-14 against the original papers (page by page)

Read from the PDFs in `Resources/`. Printed journal page numbers are used; the PDF page is printed page − 40 for [70] and [72], and the same as the printed page for [71].

| Slide claim | Source | Page |
|---|---|---|
| 14 AS-XM1000 (Telos-B) motes, research lab at AUT, about 30 m × 30 m, InstantContiki 3.0, 1 sink / 12 senders / 2 blackhole motes | [70] | 48 |
| Sink connected to a desktop PC running Contiki/Cooja; Table 2 testbed parameters; Figure 4 photo of the motes | [70] | 48-49 |
| RPL with MRHOF | [70] | 47, 49 |
| Blackhole advertises a false, low DIO rank, gets chosen as parent, drops packets | [70] | 45 |
| Rank changes 16-246 (MRHOF) vs. 15-55 (trust-based); Figure 8 | [70] | 51-52 |
| Throughput per mote | [70] | 52 |
| Loss 60-75% (MRHOF) vs. under 28% (trust-based); Figure 10 | [70] | 53 |
| "Delivery 25-40%" | our arithmetic (100 − loss), not their wording | — |
| ZigBee / XBee Series 2 nodes on Arduino Uno | [71] | 21-22 |
| Chain layout (R0-R5, coordinator C) | [71] | 26 (Table 6) |
| Tunnel = two Raspberry Pi (3 or higher) with GSM/GPRS (SIM800/900), TCP/IP link that re-injects ZigBee frames | [71] | 22-24 |
| 3-sigma rule | [71] | 14 (also 1, 9-10, 15) |
| Table 7: 4 → 3 hops, 80-100 → 120-200 ms, 20-30% data modified | [71] | 28 |
| Abstract: delay +40%, false readings in over 30% (not fully consistent with Table 7) | [71] | 1 |
| XBee S2C with source routing; classic and reverse wormhole | [72] | 44, 50 (Table 1) |
| Malicious node = Raspberry Pi 3 + Atmel RZUSBSTICK dongle with KillerBee | [72] | 44, 50 (Table 2) |
| Two test networks, each 1 coordinator + 2 routers | [72] | 50 |
| Figure 2, wormhole with a malicious node | [72] | 43 |
| Results are packet captures, with no delivery, loss or delay figures | [72] | 50-56 |
| Signature: routing packet duplication | [72] | 55 |

Not verified from the original (no local PDF; the publisher blocks direct download):

- Khan et al. [22], "delivery above 97%". A search excerpt of the paper confirms "RPD more than 97%, PMR and PER below 1.8%". The node-H exception was not seen.
- Hu, Perrig and Johnson [46]. A search excerpt confirms the record-tunnel-replay definition. The "4 of 5 criteria" is our own Table 4.5 count, not a claim of [46].

## The submitted paper against the same sources

Every paper sentence citing [22], [46], [70], [71] or [72] was compared with the originals. Khan et al. [22] was checked against the publisher's PDF, now saved as `Resources/An-Efficient-Wireless-Sensor-Network-Based-on-the-ESP-MESH-Protocol-for-Indoor-and-Outdoor-Air-Quality-Monitoring.pdf` (pages "x of 21").

**Matches:** all set-up descriptions, figure and table numbers (Figures 4.48-4.54, Tables 4.21-4.23 adapted from [70] Fig 8/9/10 + Table 2, [71] Fig 4/19 + Table 7, [72] Fig 2, [22] Fig 20 + Table 6), and every number in 4.2.7.6, 6.5.2 and Table 6.34. Khan: campus test p. 18 (7 sensor nodes + root, 64 B every 2 min for 5 days, >97% except node H, <1.8%, node H 100 m / outdoor, healing 4.18 / 3.46 s); open-area test pp. 15-16 (64 B per minute, >98% every node). All reference-list DOIs resolve to the right article. [70]: the PDF prints `10.18080/ajtde.v6n1.138` and the paper uses `jtde`; both resolve, and the publisher now lists the `jtde` form.

**Does not match (not fixed in the paper):**

| Paper location | Problem |
|---|---|
| 4.2.7.6, Khan paragraph | Ties the 97% / node-H figures to "a stability test that sent every 60 s over five days". They come from the campus test (every 2 min, p. 18); the 60 s test gave >98% (pp. 15-16). The Table 6.34 note is correct |
| 2.7 | "seven ESP32 nodes". Khan has seven sensor nodes plus root A ("All eight deployed nodes", p. 18) |
| D-21 (5.6), 6.2.2 | DuplicateRate "measured at the root as in [72]". [72] only proposes routing-packet duplication (p. 55) |
| Reference [46] | `*3*1976–1986` is missing the comma: "3, 1976–1986" |
| Reference [22] | Missing the article number: "14(24), 16630" |
| [46] definition (3.5, 4.2.1.3) | Not checked against the original; no copy could be opened |

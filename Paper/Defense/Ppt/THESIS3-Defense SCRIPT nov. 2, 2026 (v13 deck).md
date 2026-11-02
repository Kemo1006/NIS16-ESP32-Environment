# THESIS3 Defense — Presenter Script

Deck: THESIS3-Defense nov. 1, 2026 (final paper, plain graph guides) v13 (studies and signatures) · 57 talk slides + 23 backup slides

Built from the deck's slide text and speaker notes, and the Study Guide v9 (Part 0, Parts 1 to 8, Part 9 question bank, Part 10 weak spots).

How to use it:

- Slide numbers are the **position in the deck** (what PowerPoint's slide sorter shows). Some slides print a different page number in the corner; ignore that.
- Chapters 1 to 3 are kept short on purpose. Chapters 4 to 7 are written out in full.
- Timing assumes about 140 spoken words per minute. Only the plain paragraphs count; *(stage directions)* and the **If asked** bullets are not spoken.
- Replace [Presenter N] with names. The split below is a suggestion; move the boundaries if one person runs long.
- Say it in your own words. The panel wants the team's voice, not a recital.

| Presenter | Slides | Covers | Time |
|---|---|---|---|
| Presenter 1 | 1–12 | Opening, Chapters 1 to 3, testbed, run, attacks, topologies, features | about 15:05 |
| Presenter 2 | 13–22 | The verifier, Chapter 5 | about 14:25 |
| Presenter 3 | 23–35 | Dataset, blackhole results and clustering | about 12:25 |
| Presenter 4 | 36–57 | Wormhole, benign runs, discussion, Chapter 7 | about 19:40 |
| **Total** | 57 | | **about 61:35** |

**The full script runs about an hour.** If your slot is shorter, these slides can be shown for a few seconds and skipped with one sentence each, because the slide before them already makes the point: 27 (Fig 6.1), 28 (Fig 4.58), 34 (PCA/t-SNE guide), 38 (Fig 6.4), 39 (box plots and d), 40 (Fig 6.12), 41 (Fig 6.6), 53 and 54 (Figs 6.30, 6.31). That saves about 7 minutes (mostly from Presenter 4). For a shorter slot still, say only the first and last paragraph of each "How to read it" slide.

**Check before the defense:** slides 45 and 46 still carry a "To remove" tag in the slide itself. Decide whether they stay, and delete the tag either way. Slides 7, 14, 16 to 20 also show "NEW SLIDE" or "CHANGED" labels; remove them if they are visible in slideshow mode.

---

# Chapters 1 to 3 (brief)

## Slide 1 — Title

**Presenter 1** · about 0:50

Good [morning / afternoon], panel. We are NIS16. I'm [Presenter 1], and with me are [Presenter 2], [Presenter 3] and [Presenter 4]. Our adviser is Mr. Gregory Cu.

Our thesis is "Cross-Layer Dataset Design and Exploratory Analysis of an ESP32-Based ESP-WIFI-MESH Network." In one line: we built a mesh network out of eight ESP32 boards, attacked it in two controlled ways at the application layer, ran 80 experiments, and checked every single run before it was allowed into the dataset.

We'll go through Chapters 1 to 3 briefly, then Chapters 4 and 5 together as "what we planned versus what we actually did," and spend most of the time on the results in Chapter 6 and the conclusion in Chapter 7.

## Slide 2 — Overview

**Presenter 1** · about 1:15

We'll give you the answer first, and the rest of the talk shows how we got it.

What we built: eight ESP32 boards, one root and seven children. Two attacks, a blackhole and a wormhole, emulated at the application layer. Four topologies, three campus sites and three traffic scenarios, for 80 runs in total: 36 blackhole, 36 wormhole and 8 benign.

What we checked: a verifier tests every run before it enters the dataset. Both attacks were confirmed in all 72 attack runs, and none of the 8 benign runs showed an attack signature.

What we found: the blackhole is visible through delivery, the packet delivery ratio. The wormhole is visible through duplicate arrivals at the root. The radio and routing features did not move.

So the one sentence to remember is at the bottom: both attacks left a clear, verified mark on the traffic, but not on the radio or routing features, because they were emulated at the application layer. We treat that as a finding, not a failure.

## Slide 3 — Chapters 1 to 3

**Presenter 1** · about 0:05

First, a short recap of the problem, the objectives and the theory.

## Slide 4 — The gap and the objectives

**Presenter 1** · about 1:20

In a wireless mesh, every node is both a host and a router, so one misbehaving relay can quietly break delivery for everyone behind it. We saw three gaps.

One, simulated data: most intrusion detection datasets, like KDD and NSL-KDD, come from simulators or ordinary IP networks, not mesh hardware. Two, missing layers: packet or flow datasets don't keep the physical, MAC and network signals of a microcontroller mesh together. Three, real attacks: blackhole and wormhole detection is mature in simulation, but on real ESP32 boards it is undocumented.

So our study produces a labelled, cross-layer dataset from a real ESP-WIFI-MESH network, under normal operation and two controlled attacks. The setting is campus monitoring, following Khan et al., who ran ESP-MESH on a campus with delivery above 97 percent.

Our general objective is to design, generate and analyse that dataset. The three specific objectives are: build the testbed, collect the features into a labelled dataset, and evaluate it with exploratory analysis and unsupervised clustering. And to be clear on scope: the output is a dataset and its analysis, not an intrusion detection system.

**If asked:**

- Why no IDS? The objectives are dataset + EDA + clustering; a detector needs the dataset first. Recommendation 5 covers how to evaluate one fairly.
- Why unsupervised? Labelled attack data is scarce in IoT, so we use methods that find structure without being told the answer.

## Slide 5 — The theory: an attack breaks a relationship

**Presenter 1** · about 1:10

Chapter 3 is the idea the dataset rests on. Normal mesh traffic keeps certain relationships. An attack breaks some of them. And before we captured any data, we wrote down which ones each attack should break, in Tables 3.4 and 3.5.

Received roughly equals forwarded: a blackhole breaks that, so we expected the attacker's forwarding ratio to fall and the victims' delivery to fall. One copy per probe: a wormhole breaks that, so we expected duplicates at the root. Delay follows hops: a wormhole should show a latency mismatch between the two copies. And placement fits topology: we expected a wormhole to produce odd hop counts, impossible parent links, or signal strength that doesn't fit the depth.

Chapter 6 tests every row. We kept the tables exactly as written, so you can see what we predicted and what we found. Spoiler: the traffic predictions held, and the topology and radio predictions did not.

That's the recap. Now Chapters 4 and 5.

**If asked:**

- Why emulation? The ESP32 Wi-Fi stack is closed. ESP-WIFI-MESH lets an app read its routing table but not write it (Section 3.5.3, D-20).
- Why ratios and mismatches as features? They measure the broken relationship, not a raw value that changes from site to site.

---

# Chapters 4 and 5: planned vs. actual

## Slide 6 — Chapters 4 and 5: planned vs. actual

**Presenter 1** · about 0:10

This part covers how a run works, how both attacks are built, how every run is checked, and what changed from the proposal.

## Slide 7 — Our testbed and what it follows

**Presenter 1** · about 1:50

On the left is what we built. R is the root, which every probe is heading to. X is the blackhole attacker, a relay placed in the path. The pink boards behind X are its victims, and the light-blue boards are bystanders, which sit outside the attacker's path and act as our control group. For the wormhole, A and B are the two tunnel ends, joined by a UART wire. That wire is the tunnel.

On the right is what each part follows from the literature. The healthy mesh follows Khan et al., who ran ESP-MESH on ESP32 boards on a campus with delivery above 97 percent. Our blackhole is checked against the definition of Airehrour et al., and meets five of their six criteria. The wormhole draws on Zhukabayeva, Hu and Ramírez Gómez for the tunnel, the definition, where we meet four of five criteria, and the duplicate-arrival signature. And Karlof and Wagner give us the idea that the attacker's position decides who the victims are.

Two honest points at the bottom. First, no published blackhole or wormhole measurement exists on ESP-WIFI-MESH, so when we compare with other studies we compare direction and size, not exact values. Second, our traffic is synthetic. Each board sends a small test packet, which we call a probe, about once a second to the root. It is not real temperature or soil data. We did that on purpose: both attacks act on how packets are forwarded, not on what is inside them, and a known, steady stream lets us count exactly what went missing.

**If asked:**

- "Is the traffic real?" No, it's synthetic, on purpose. The attacker drops or tunnels a packet regardless of its content. It is a limitation: Khan et al. send one 64-byte packet every 2 minutes; ours is about 1 per second. Real sensor traffic is future work. Do not claim the results generalise to real deployments.
- Sites: G402 classroom, DLSU Library, and the open area below Yuchengco (semi-outdoor). Say "campus", not "indoor".

## Slide 8 — How one run works

**Presenter 1** · about 1:25

Every run follows the same timeline, read left to right. First, formation: at least 60 seconds while the mesh builds itself. Those rows get label 255 and are excluded. Then a 300-second baseline, label 0, normal. Then the 180-second attack, label 1 for blackhole or 2 for wormhole. A run has one attack, never both. Then a 120-second cooldown, back to label 0.

A few design choices matter here. Every board logs ten times a second to its own flash and to a microSD card. The logs are imported after the run. Nothing is streamed over the mesh, because if it were, a blackhole could drop its own evidence.

The root drives the phases. It sends the phase command in five rounds, 100 milliseconds apart, every ten seconds, so a board that misses one still gets it. The attack can only start after the pre-run gates pass and the operator types START. The gates check things like: did every child join, does the blackhole attacker actually have a child behind it, is the wormhole wire working.

And the most important line on this slide: labels come from the phase schedule, never from a feature. So the label can never be circular.

**If asked:**

- Why label 255 for formation? So rows outside the experiment can be excluded by value, not by guessing a time cut-off.
- What if a gate fails? START is locked (D-24). An override needs a typed reason, which is logged and reported.
- Probe = magic, sequence number, send time, source MAC; every 1000 ms (stationary, burst) or 250 ms (highload).

## Slide 9 — Two attacks, emulated at the application layer

**Presenter 1** · about 1:45

On the left, the blackhole, which we call forwarding suppression. The attacker is a relay that runs the same relay code as every other board. During the attack phase, it simply stops forwarding. It still acknowledges every frame at the link layer, so the victims' radios see no failure at all. They keep sending, and their probes vanish at the attacker. Against the six criteria of Airehrour et al., it meets five. The one it misses is attracting traffic with a false route. In our network, traffic reaches the attacker because of where we place it, not because it lies about routes.

On the right, the wormhole, an out-of-band tunnel. The two ends are joined by a UART wire at 115,200 baud, carrying 30-byte frames with a CRC32 check. End B, the deeper one, writes each of its own probes into the wire. End A, the shallower one, re-injects them toward the root. So the root gets every one of B's probes twice, by two different paths, with different delays. Against the five criteria of Hu, Perrig and Johnson, it meets four. The one it misses is creating a false neighbour.

The reason for both gaps is the box at the bottom, deviation D-20. ESP-WIFI-MESH lets an application read its routing table, but not write it. So both attacks reproduce the traffic effect of the attack, not the routing manipulation. This one decision explains most of what you'll see in Chapter 6.

**If asked:**

- "Is it really a blackhole?" It meets 5 of 6 criteria (Table 4.4). We call it forwarding suppression and list route attraction as the first limitation.
- "Is it a wormhole if the topology never changes?" Two colluding ends, out-of-band channel, capture and replay (Table 4.5). It reproduces the packet-level signature, not the false neighbour.
- "Why not make the root the attacker?" The root is the destination and the referee. It would be grading itself (D-16).
- "Why does the wormhole have no victims?" Only B's own probes are tunnelled; the other boards are untouched. The attack is the duplication, not loss.
- Weak spot: Table 4.4 row 1 still says victims address the attacker. Since D-12, victims send to their own parent; the tree routes them through the attacker.

## Slide 10 — Topologies as they formed, and the run design

**Presenter 1** · about 1:45

We used three sites: G402, a controlled classroom; the DLSU Library, a busy area with heavy Wi-Fi; and the open area below the Yuchengco Building, which is semi-outdoor. And three traffic scenarios: stationary, one probe per second, our reference; burst, where one child fires 300 probes 60 seconds into the attack; and highload, four probes per second for the whole run. The scenarios exist so that traffic volume alone can't give an attack away.

Four topologies, times two attacks, times three sites, times three scenarios gives 72 attack runs, plus 8 benign runs, for 80. One run per cell, so the sites act as repeats.

The drawings show each network as it actually formed when the attack started. Root on top, each line down is one hop. X is the blackhole attacker, A and B the tunnel ends, pink the victims, light blue the bystanders. Two things to notice. The star has no bystanders, because every board sits behind the hub. And in the wormhole panel, end B sits deeper than end A, so the tunnel really does skip hops.

One note: ESP-WIFI-MESH always builds its own tree. So a "topology" for us means where we place the boards plus a configuration option like a depth cap or a children limit, and we check what actually formed after every run. That's why the partial mesh, in practice, behaved as a branched tree. No board ever used a second parent, and we report it that way.

**If asked:**

- "Is your partial mesh really a mesh?" No board used a second parent; reported as a placement-defined branched tree, no adaptive switching claimed (D-29).
- "Why does the star tunnel skip only 1 hop?" A flat star puts every board at hop 1. Making A the hub gives the smallest real shortcut (D-28).
- Weak spot: 4.2.2.1 still says Figure 4.16 is "to be redrawn"; it is redrawn and all 9 star wormhole runs were confirmed. 4.2.2.2 says sticky tree parents "not yet confirmed"; only 1 of 132 tree boards changed parent in the labelled phases.

## Slide 11 — From raw rows to 16 features

**Presenter 1** · about 1:35

Next, how the raw logs become a table, in five steps across the top.

One, align. The boards share no clock, so each board is aligned to its own exit from phase 0. Two, window. We cut the data into one-second windows on a 10-hertz grid. A window needs at least 8 of its 10 samples, or it's discarded. In total we formed 457,568 windows and discarded only 1,372, which is 0.30 percent, and no run lost more than 1 percent. Three, fill. Gaps of one or two samples inside a kept window are filled. Four, count. The boards keep running counters, and we turn them into per-window changes. Five, join. Delivery is computed by joining the root's arrivals to each sender on the sequence number, never on time. That's how we get delivery without synchronised clocks.

The result is one row per board per second, with 16 features in six groups. Forwarding: ForwardingRatio, which is forwarded over received, plus the absolute gap between them and a consistency score. Delivery: PDR, which is blank when nothing was sent, and a retry rate. Topology: parent switches, hop changes, and how long the hop stays stable. Physical: RSSI mean, variance and stability. Cross-layer: the RSSI-versus-hop difference and latency per hop. And tunnel features, which exist only on the two wormhole ends.

**If asked:**

- "Clocks aren't synchronised, so how do you get delay or delivery?" Join on sequence number; align each board to its own phase-0 exit; delay is relative to the sender's fastest delivery (D-2). TunnelLatency is the gap between the two copies at the root, so the offset cancels exactly (D-3).
- Why 1-second windows of 10 samples? With 5 samples one loss cost 20% of a window; the panel asked for about 10,000 rows per run (D-1, D-9).
- RetryRate = app counters (failed sends), not MAC retries (D-15). On end B it counts tunnel frames.
- Weak spot: the paper text says IngressEgressDelta and RSSI_Hop_Diff are differences ("minus"); the dataset stores the absolute value of both.

## Slide 12 — How to read the dataset: one row

**Presenter 1** · about 1:55

To make that concrete, here are four real rows from one run: tree topology, G402, stationary, blackhole. Each board is named by the last four hex digits of its MAC.

Rows 1 and 2 are the same board, 1C38, which is the attacker. In row 1, 100 seconds before the attack, it received 3 probes and forwarded 3, so its forwarding ratio is 1.000 and the label is 0. In row 2, 120 seconds into the attack, it received 3, forwarded 0, dropped 3, and its forwarding ratio is 0.000. The label flipped from 0 to 1 only because the schedule entered the attack phase. No feature decided it. That's the first point on the right.

The second point: blank is not zero. Look at PDR. Row 3 is a victim, D7B4, behind the attacker. Its PDR is 0.000. That's a real measurement: it sent, and nothing arrived. PDR is left blank when we can't judge, meaning the board sent nothing, was disconnected, or the root wasn't logging. That's how we make sure a board that simply lost its connection is never mistaken for a blackhole victim.

The third point: same label, different story. Rows 3 and 4 both carry label 1. But the victim's PDR is 0.000, and row 4, a bystander, 0C80, connected straight to the root, has a PDR of 1.000. The attack never reached it. Keep this in mind, because it is exactly why no clustering method can score a perfect 1.0 on all boards, as you'll see in Chapter 6.

With that, I'll hand over to [Presenter 2] for how every run is checked.

**If asked:**

- "Why is a bystander labelled attack?" The label is set by phase for every board of the run (Section 6.1). No feature of a board the attack never reached can show it, which caps the ARI at 0.515.
- "Why is PDR blank for the attacker?" It is not scored on the attacker or the tunnel ends; the attacker is measured by ForwardingRatio.
- On a relay, received = forwarded + dropped (row 2: 3 = 0 + 3).

## Slide 13 — Every run is validated before it counts

**Presenter 2** · about 1:45

Thank you. Before any run enters the dataset, a verifier checks it. There are four checks, in this order: signature, topology, dataset and scenario. Then a verdict, and then a test of the verifier itself. All the rules were fixed before any result was read.

Check 1, signature, uses the 3-sigma test from Zhukabayeva et al.: the attack mean has to sit at least three baseline standard deviations away from normal, in the expected direction, with a change of at least 0.10. Check 2, topology, rebuilds the tree from the parent addresses, and a board that changes class during the attack fails the run. Check 3, dataset, needs every board to cover at least 95 percent of each phase. Check 4, scenario, confirms the probe rate and burst timing match the scenario the run is filed under. Checks 3 and 4 are our own rules.

At the bottom are the six studies behind the checks; the tags, Z, A, R, K, KW and H, are the same tags the verifier prints in its report. And in the top right, the verifier was tested. In a placebo test where we relabelled half the baseline as "attack", it gave zero false confirmations out of 106. When every threshold moved by plus or minus 50 percent, zero verdicts changed. And with an absurd setting, 1,000 standard deviations, 18 verdicts did change, which shows the test can actually fail. The next slides go through each check.

**If asked:**

- "How do you know a run is valid and not noise?" Four checks plus a setup check, rules fixed in advance, placebo 0 of 106, ±50% sensitivity changed nothing.
- Outcomes: PASS / FAIL / INCONCLUSIVE. Grades: STRONG, GOOD, MINOR GAPS (kept, footnoted), MAJOR GAPS (recaptured).

## Slide 14 — Check 1: Two signatures

**Presenter 2** · about 2:10

This is the one-page summary of what each attack should look like and what we measured. Read it as three columns: blackhole, wormhole and benign.

How it works. The blackhole accepts each probe from the boards behind it, then drops it, and the sender sees no error. In the wormhole, end B also sends each of its own probes over the wire to A, so every probe of B arrives twice. In benign, every board relays normally.

What's scored. For the blackhole, two primary checks: the attacker's ForwardingRatio has to fall, and the PDR of the non-attacker boards has to fall. For the wormhole, also two: TunnelIntensity, which is the ends' own count of tunnel traffic, has to rise, and DuplicateRate, which the root measures independently, has to rise. For benign, PDR has to stay at or above 0.90 in both phases, and every relay has to forward at least 90 percent.

Who is hit. In the blackhole, the victims behind the attacker lose every probe and the bystanders are untouched, so the damage is loss. In the wormhole, nobody loses probes; only B's probes are doubled, so the damage is duplication, not loss. In benign, nobody.

What we measured. Blackhole: 36 of 36 confirmed. The attacker's forwarding ratio went from about 1.00 to 0.00, and the victims' PDR from 0.998 to 0.000, with a Cohen's d of minus 29.7. Wormhole: 36 of 36 confirmed. 99.86 percent of B's probes arrived twice, with none in the baseline, and the other boards' delivery stayed at 0.9999. Benign: 8 of 8 confirmed benign.

And the bottom line, the same for both: no route change, no parent change, no hop change caused by the attack, and RSSI stays flat. Because both attacks are emulated at the application layer, only the traffic features move.

**If asked:**

- "What is the key difference?" Blackhole = loss behind the attacker; wormhole = duplication with no loss. One shows in delivery (PDR), the other only in the ends' counters and the root's duplicates.
- "Can a real attacker fake its own counters?" Yes, and this dataset cannot test that. The attacker's counter is ground truth for labelling, not a detector input; PDR and duplicates are the root's own view.
- NeighbourForwardingRatio = the attacker's forwarding as seen by the boards next to it, a second opinion. Supporting only, 32 of 36 runs; 4 runs have no attack-phase values; none fails.

## Slide 15 — Check 1: The 3-sigma rule

**Presenter 2** · about 1:30

Here's how the 3-sigma test works, on a schematic of one feature, say ForwardingRatio, over one run. It's not to scale.

Following Zhukabayeva et al., we pool every five one-second windows into one point. So the 300-second baseline gives 60 points, and the 180-second attack gives 36. The baseline mean plus or minus three standard deviations is the grey normal band.

A primary check passes when three things hold. One, the attack mean is at least three baseline standard deviations from the baseline mean, in the expected direction. Two, the absolute change is at least 0.10. Three, there are at least six attack points.

The example in the box: a baseline of 1.000 with a standard deviation of 0.002, and an attack mean of 0.003, gives a z of about minus 500. All three rules are met. In the real runs, where z could be computed, the attacker's forwarding ratio sat at least 22.9 standard deviations away, with a median of 111.

One special case: if the baseline never varied, so the standard deviation is zero, then any move in the expected direction passes. But only if it's also a change of at least 0.10, so one lost probe can never count as an attack.

**If asked:**

- A primary with a broken baseline (mean below 0.90 or SD above 0.15 of the mean) is excluded, not failed.
- TunnelLatency and LatencyHopRatio are reported, not scored: no tunnel in the baseline, and LatencyHopRatio's baseline is so spread that |z| could never exceed 0.64.
- Weak spot: 4.2.7.1 calls a zero-SD z "undefined", 6.2 calls it "infinite". Safe phrasing: "the baseline never varied, so any move in the expected direction passes."

## Slide 16 — Check 2: Topology

**Presenter 2** · about 1:30

Check 2 is about who is a victim. On the left, from Figure 4.57: who counts as a victim depends on where X sits. The red boards behind the attacker are victims, the blue ones are bystanders. On the right, from Figure 6.2: during the attack the victims lose everything, and the bystanders don't.

The rule: we rebuild the tree from the parent addresses every board logs. Boards behind the attacker are victims; the rest are bystanders, our control group. Bystanders matter because they're in the same run, at the same time, in the same room, on the same radio, just not behind the attacker. Their delivery didn't change, so the victims' loss is the attack, not the room. And this check reads only parent addresses, never the outcome, so it can't be biased by the result.

The tolerance: a board may change parent during the attack, as long as it stays in the same class. A board that switches between victim and bystander fails the run.

The setup check: for the blackhole, the attacker must have relayed and then dropped, and the victims must have stayed alive but cut off. For the wormhole, there must be exactly one end A and one end B, with A shallower than B.

**If asked:**

- "What if a bystander just disconnects? Does that look like a blackhole?" No. Its PDR is blank in the windows it is detached, not 0 (D-8). A board missing for the whole run is graded by role (D-32).
- Results: victims 0.998 → 0.000, all 123 victim boards at exactly 0 in the attack; bystanders 0.996 → 1.000.
- Karlof and Wagner [81] original was not opened; don't quote it word for word.

## Slide 17 — Check 3: Dataset

**Presenter 2** · about 1:20

Check 3 asks: did every board record enough data? It runs in three steps.

First, count: every board needs windows for at least 95 percent of every phase, baseline, attack and cooldown. Second, find the gaps: a board below 95 percent is a gap, and a board missing entirely is graded by its role. Third, the impact check: we re-run the 3-sigma test without the gap boards and ask, does the attack still confirm?

That decides the grade. Strong or good: all board data is present, and the run is validated. Minor gaps: some data is missing, but it's not what the result needs, because without those boards the attack still confirms. Those runs are kept and footnoted. Major gaps: the result relies on missing data, for example a victim that was never measured during the attack, so we recapture. And failed: the attack can't be confirmed at all, so we redo the run.

This is our own rule, fixed before any result was read. And the principle behind it is the line at the bottom: missing data never becomes a pass or a fail.

**If asked:**

- Missing boards by role (D-32): attacker or tunnel end missing = major (recapture); victim or bystander missing = minor while others of that role remain.
- Example: slide 28 shows a run with one minor gap.

## Slide 18 — Check 4: Scenario

**Presenter 2** · about 0:55

Check 4 asks: did the traffic leave the trace its scenario should leave? If we file a run under highload, it had better look like highload.

Stationary: each child probes about once a second, so the children's median rate must be at most 1.5 probes per second. Highload: a probe every 250 milliseconds, so the median baseline rate must be at least 3 per second. Burst: one child fires 300 probes in about 3 seconds, 60 seconds into the attack, so we need at least 240 extra probes from one child within 10 seconds.

If the trace is found, the scenario is applied and the run counts for that scenario. If it's missing, it's a minor gap and footnoted. The attack result still stands, but that scenario cell needs a recapture.

**If asked:**

- Example of a missing trace: linear / G402 / burst blackhole, where the burst fired outside the attack (D-34). Kept with a minor-gap note.

## Slide 19 — The verdict

**Presenter 2** · about 1:10

The four checks feed one verdict, with three possible outcomes.

PASS: the signature is confirmed by the 3-sigma test on the primary features, and topology, dataset and scenario all hold. The run gets a grade: strong, good, or minor gaps.

FAIL: there's no signature, a board changed class, the attacker's data is missing, or the setup didn't run as designed. The run is redone.

INCONCLUSIVE: the evidence can't decide. In particular, if the baseline itself was broken, meaning its mean was below 0.90 or its spread was more than 15 percent of the mean, that primary check is excluded, not failed. A healthy ESP-MESH delivers above 97 percent, according to Khan et al., so a baseline under 0.90 means something was wrong with the run, not with the attack. The 0.90 bound is ours.

And as a reminder of what's scored: for the blackhole, the attacker's ForwardingRatio and the PDR of the non-attacker boards. For the wormhole, TunnelIntensity, the ends' own count, and DuplicateRate, the root's own view.

**If asked:**

- "Each attack has a different study; why?" No single study runs both attacks on ESP-WIFI-MESH. Blackhole compared with [70], wormhole with [71] and [72], healthy baseline with Khan et al. [22].
- Pooling 5 windows per point is our design, not Zhukabayeva's.

## Slide 20 — Testing the verifier

**Presenter 2** · about 0:55

A validator is only believable if it can say no. So we tested the verifier itself, three ways.

Placebo test: we took the baseline, relabelled its second half as "attack", and ran the verifier. There was no attack there, so it should confirm nothing. It confirmed zero out of 106.

Sensitivity: we moved every threshold up and down by 50 percent, across 53 runs and 14 settings. Zero verdicts changed. So the results don't depend on exactly where we drew the lines.

Stress test: with an absurd setting, requiring 1,000 standard deviations instead of 3, 18 verdicts did change. That's what we want to see: the test can fail, so when it passes, the pass means something.

And again, the rules were fixed before any result was read.

**If asked:**

- "Could packet leashes catch your tunnel?" Not tested; we built no defence. The gap we measure is the kind of timing evidence a temporal leash looks for.

## Slide 21 — Chapter 5: 37 deviations, three reasons

**Presenter 2** · about 1:20

Chapter 5 documents every change from the proposal. There are 37, numbered D-1 to D-37. Seventeen modify something the proposal specified; twenty add a rule the proposal didn't have. Each one lists what was planned, what changed, why, and what it cost, in Appendix C.

None of them were planned in advance. Each came when a capture or a review showed the plan couldn't be followed, or would give untrustworthy data. They fall into three reasons.

One, the platform couldn't measure it. For example, no MAC retry count ever reaches the application, and our probes get no reply, so there is no round-trip time.

Two, the plan would leak the label or fail to make the attack. For example, originally only the attacker had relay counters, so an empty column would have identified the attacker by itself. And two wormhole ends at the same depth skip no hop, so there would be no wormhole.

Three, a run needed rules to count as one valid experiment: the pre-run gates and START, what to do with parent changes during the attack, and how to grade missing boards by role.

**If asked:**

- "37 deviations means you didn't follow your proposal?" Each was forced by evidence, each is documented with its cost, and only four limit how the results are read (next slide).
- Several were scope decisions checked with the adviser (D-19 sites, D-33 jitter out, D-35 benign plan).

## Slide 22 — Planned vs. actual: the changes that matter

**Presenter 2** · about 1:50

These are the six changes that matter most, read across: what the proposal planned, what we did, and why.

Attacks on routing, with a false route or false shortcut, became application-layer emulation, because the API reads routes but can't write them. That's D-20.

The mesh stack relays traffic out of sight. Now every node relays the probes itself and counts them, because when only the attacker had relay counters, that leaked the label. That's D-12, and it answers the Thesis 2 panel's point that if one column decides it, machine learning is unnecessary.

A MAC retry count from the Wi-Fi statistics became application counters kept as a column, plus real retries from a sniffer in 7 runs, because no retry number reaches the app. D-15.

Five-second windows of five samples became one-second windows of ten samples at 10 hertz, because one lost sample cost 20 percent of a window. D-1 and D-9.

A flat star with fixed wormhole ends became a hub that is the attacker or end A, with ends chosen by depth and B always deeper, because the root can't attack and equal depths skip no hop.

And no benign control runs became 8 benign runs across sites and scenarios, as a control for false alarms.

Four of these limit how Chapter 6 should be read, as shown at the bottom: the emulation, no MAC retry count, only 8 benign runs, and the tree's fan-out differing between runs. Keep D-20 especially in mind for the results.

With that, I'll hand over to [Presenter 3] for Chapter 6.

**If asked:**

- D-20 is the most important limitation: no route attraction, no false neighbours, no attacker-caused parent changes in the data. This is why cross-layer features stayed flat.
- Benign plan went 12 → 9 → 12 → 8 (D-33, D-35). Final: 4 stationary, 3 highload, 1 burst; G402 4, Library 2, Yuchengco 2.

---

# Chapter 6: Results and Discussion

## Slide 23 — Chapter 6: Results and Discussion

**Presenter 3** · about 0:15

Thank you. Chapter 6 covers the dataset, whether each attack worked, the exploratory analysis, the clustering, and what it all means. We'll go blackhole first, then wormhole, then the benign runs and both attacks together.

## Slide 24 — The dataset: 80 of 80 runs captured

**Presenter 3** · about 1:05

First, the dataset itself. All 80 of 80 planned runs were captured: 36 blackhole, 36 wormhole and 8 benign. That gives 369,678 analysed windows, out of 456,195 recorded, with only 0.30 percent discarded, and 637 log files, none of them empty. The analysed windows are 266,491 normal and 103,187 attack. Across the blackhole runs there are 123 victim boards and 92 bystanders.

How to read the chart: the left half is blackhole, the right half is wormhole. Each bar is one topology, split by site in different shades, and each segment is three runs, one per traffic scenario.

What you see is that both attacks have the full grid: four topologies, times three sites, times three scenarios, 36 runs each. The 8 benign runs, at the bottom, each share their topology, site and scenario with an attack run: three linear, three star, one tree and one partial mesh.

**If asked:**

- 369,678 analysed vs 456,195 recorded: the difference is mostly the minutes before the baseline (85,435 windows, not analysed) and phase boundaries.
- 15 earlier captures of 11 cells were replaced and archived; 12 captures outside the plan (5 jitter, 7 at home) are not counted.
- Weak spot: 457,568 − 1,372 = 456,196, but Table 6.2 totals 456,195. A one-window bookkeeping difference not yet traced; changes no percentage or result.

## Slide 25 — Blackhole results

**Presenter 3** · about 0:05

The blackhole: did it work, what did it change, and can clustering find it?

## Slide 26 — Blackhole: confirmed in all 36 runs

**Presenter 3** · about 1:30

The blackhole was confirmed in all 36 runs: 4 strong, 27 good and 5 with minor gaps.

The numbers on the left. The attacker's forwarding ratio went from 1.000 to 1.004 in the baseline down to 0.000 to 0.007 in the attack. In one example run, linear, G402, stationary, the attacker received 1,077 probes during the attack and forwarded exactly one. The victims' PDR went from 0.998 to 0.000, and every one of the 123 victims averaged exactly zero. It was also immediate: 121 of the 123 victims were cut off in the very first second of the attack, and once it ended, the median recovery was 2 seconds. The bystanders, meanwhile, went from 0.996 to 1.000. Nothing happened to them.

How to read the graph: time runs left to right, with zero where the attack starts and 180 where it ends, shaded. Height is PDR, the share of probes that reached the root, where 1 means all of them. Red is victims, blue is bystanders.

What you see is that red drops from 1 to 0 the moment the attack starts and comes back right after it ends, while blue stays at 1 the whole time. The star panel has no blue line, because the star has no bystanders.

**If asked:**

- Table 6.9: ForwardingRatio primary 36/36; PDR primary 35/36 (one excluded for an unstable baseline, 0.930 ± 0.253, partial / Yuchengco / stationary).
- Support checks: ConsistencyScore 31/36, IngressEgressDelta 31/36, NeighbourForwardingRatio 32/36 (4 had no attack values, none failed).

## Slide 27 — Figure 6.1: delivery collapses in every blackhole run

**Presenter 3** · about 0:35

This figure shows the same result run by run. Each tile is one run: the panel is the topology, the row is the site, the column is the scenario. The colour and number are the victims' average PDR during the attack, where green is 1, all delivered, and dark red is 0.

All 36 tiles are dark red at 0.00. In no run, in any topology, site or scenario, did a single victim probe reach the root during the attack.

## Slide 28 — Figure 4.58: dataset check, one run

**Presenter 3** · about 0:45

And here's what check 3, the dataset check, looks like on a real run: blackhole, partial mesh, G402, highload. Each group of bars is one board. The height is the percentage of each phase it recorded: blue baseline, red attack, green cooldown. The dashed line is the 95 percent minimum.

Every bar clears 95 percent except one: board ED80's baseline, at 88.7 percent, or 266 of 300 seconds. So the verifier re-ran the test without ED80, the attack was still confirmed, and the run was kept as a minor gap, with a footnote. This is one of the 5 minor-gap blackhole runs.

## Slide 29 — Blackhole predictions: delivery yes, retransmissions no

**Presenter 3** · about 1:25

Now back to Table 3.4, the blackhole predictions we wrote before any data. Read across: the prediction, whether it was observed, and what we measured.

The attacker's forwarding ratio falls below 1: yes, from about 1 to 0, and it passed in all 36 runs. The attacker's ingress-egress delta rises: yes, it passed in 31 of 36, and in the other 5 it rose, but stayed under 3 standard deviations. Victims' PDR falls: yes, 0.998 to 0.000, all 123 victims at zero.

Victims retransmit more at the MAC layer: no. The application counter went from 0.0000 to 0.0004, essentially nothing. And the sniffer, which reads the real 802.11 retry bit, was on 7 runs: in 3 it went up, in 4 it went down. No consistent rise.

And the attacker's RSSI stays stable: yes, from minus 67.1 to minus 67.8 dBm, within 1 dB in 27 of 36 runs.

So the summary at the bottom: the attacker's counters and the victims' delivery moved, but the radio never saw a failure. That's because our attacker still acknowledges every frame at the link layer. From the victim's radio's point of view, every send succeeded. So there's nothing to retransmit.

**If asked:**

- "Where is the MAC layer in your cross-layer dataset?" No MAC retry count in ESP-IDF (D-15); the sniffer Retry bit in 7 runs showed no consistent rise; the MAC side rests on RSSI and link/parent state. Seven runs are too few to rule out a small effect.
- The RSSI row (†) is **not in the paper**: computed from the same feature tables. Say so if asked.

## Slide 30 — Clustering: how the data were asked to sort themselves

**Presenter 3** · about 1:20

Next, objective three: can the data separate normal from attack without being told the answer? This slide is the setup.

Five algorithms: K-Means, Ward hierarchical clustering, a Gaussian mixture model, DBSCAN with its neighbourhood size set at the knee of the k-distance graph, and spectral clustering.

Three feature sets. FULL is the 8 features allowed by our leakage guard; the guard blocks the relay features, the retry rate, the tunnel features and latency per hop, because each of them can give the label away by itself. REDUCED is what's left after removing features that almost never vary: PDR, RSSI mean, RSSI variance, and the RSSI-to-hop difference. And "without PDR" keeps just the three RSSI features, as a control.

Four scores. Silhouette and Davies-Bouldin describe cluster shape and never see the label. Purity and ARI, the adjusted Rand index, compare the clusters to the label, but only afterwards, for grading. For ARI, 1 is an exact match and 0 is chance.

We sampled 6,000 windows per seed, with three seeds, standardised the features, and tried k from 2 to 8. The algorithm never sees the label.

**If asked:**

- Removed by low variance: ParentSwitchRate (100% one value), HopChangeCount (100%), HopStabilityDuration (99.8%), RSSI_stability (98.5%). The correlation filter removed nothing (largest |r| 0.11).
- LatencyHopRatio is excluded because its missingness alone predicts the label in 86% of windows.
- Two populations: all non-attacker boards (127,372 windows) and victims only (72,687).

## Slide 31 — How to read the clustering scores

**Presenter 3** · about 1:20

Since these scores carry the rest of the chapter, here's how to read each one.

Silhouette asks how close a window is to its own cluster compared with the nearest other one. It runs from minus 1 to 1, higher is tighter. But it describes shape, not the attack. Davies-Bouldin asks how compact and how far apart the clusters are; lower is better, same caveat.

Purity asks what share of windows carries the majority label of its cluster. The trap is that you have to compare it with the majority rate. In our sample, about 70 percent of windows are normal, so a purity of 0.70 means no separation at all.

ARI asks whether the clusters agree with the label, corrected for chance. 1 is exact, 0 is chance. That's the one we lean on.

On the scale at the bottom, you can see where our blackhole results land. Without PDR, every algorithm sits around zero, at chance. K-Means on all non-attacker boards scores 0.514, and the best possible on our labels is 0.515. On victims only, K-Means scores 0.996. The next two slides explain both of those.

**If asked:**

- "Why report purity at all?" It's the common score; we always read it against the majority rate, and ARI is the one corrected for chance.

## Slide 32 — Blackhole clustering: PDR carries all the separation

**Presenter 3** · about 0:55

Here are the blackhole clustering results. How to read the chart: one pair of bars per method. Height is ARI, where 0 is chance and 1 is a perfect match. Dark blue is all non-attacker boards, red is victims only. This is the REDUCED set, at k equals 2, averaged over three seeds.

What you see: on victims only, K-Means matches almost perfectly, 0.996. On all boards, every method stops near 0.5. That's the best possible here, because bystanders carry the attack label but behave normally.

And the key line in the middle: without PDR, every algorithm at every k scores between minus 0.016 and 0.002. Basically zero. Remove one feature, and the separation disappears. So the blackhole leaves no mark on signal strength or topology. All of the separation is carried by delivery.

**If asked:**

- "Why did silhouette say k = 2 is best when that split isn't the attack?" Silhouette measures shape, not agreement. On FULL, K-Means and Ward score their best silhouette at k = 2 (0.77, 0.90), but on two seeds that split only cut off a few odd windows. K-Means ARI there is 0.172; the attack appears at k = 4 (0.505). We pick k with elbow, silhouette and interpretability together.
- Robustness: within every site and topology K-Means stays within 0.03 of that subgroup's ceiling. Resampling the 36 runs gives ARI 0.511, 95% interval 0.41 to 0.63.
- Spectral finds the attack on one seed only; reported, not relied on.

## Slide 33 — Why 0.514 is the best possible score

**Presenter 3** · about 1:20

So why do we say 0.514 is essentially perfect?

The bar at the top shows all the attack-labelled windows of the non-attacker boards, 38,232 of them. 56.8 percent are victims, whose delivery is lost. But 43.2 percent are bystanders, whose traffic was never touched.

Three steps. One, the phase label marks every board of a blackhole run as "attack", bystanders included. Two, a bystander's PDR stays at 1.000, so no feature can show an attack that never reached it. Three, so the best possible split is: victim attack windows on one side, and everything else on the other. If you compute the ARI of that perfect split against our labels, you get 0.515, with a purity of 0.870.

K-Means scored 0.514, with the same purity of 0.870. So K-Means found essentially exactly the windows in which the attack is felt. And on victims only, where the bystander problem doesn't exist, it scores 0.996.

This isn't a flaw in the data. It's a property of how the labels are defined, by phase, per run, and that's why the paper reports both populations.

**If asked:**

- "ARI 0.514 is mediocre." The ceiling is 0.515 because 43.2% of attack-labelled windows are bystanders; victims alone score 0.996.
- Contingency of the best split: cluster 1 = 21,733 victim attack windows; cluster 2 = 16,499 bystander attack + 89,140 normal; N = 127,372.

## Slide 34 — PCA and t-SNE: how to read the pictures

**Presenter 3** · about 0:55

The next slide uses two kinds of pictures, so here's how to read them.

PCA rotates the data so that the first axis holds the most variance and the second axis the next most. The axes are in standardised feature units, and the percentage on each axis is the share of variance it holds. A few extreme windows can stretch it into a thin column.

t-SNE places windows with similar features near each other. The axes have no units, and only nearness means anything. You should never read the distance between two far-apart islands.

The most important line is at the bottom: a group in a picture is not a cluster. A cluster is what an algorithm returns. We use these pictures to describe the data; the scores decide whether a separation exists.

## Slide 35 — The same windows, with and without PDR

**Presenter 3** · about 0:55

These are t-SNE pictures of the same 6,000 windows. Each dot is one second of one board. Red is victim under attack, light blue is bystander under attack, orange is victim normal, and dark blue is bystander normal.

On the left, with PDR, using the full 8 features, the red dots form their own island. The light-blue bystander attack windows sit among the normal ones, which is what we'd expect.

On the right, the same windows with PDR removed, using only the three RSSI features. All four colours are mixed. There is no attack group to find.

So the picture tells the same story as the scores: the blackhole is visible through delivery, and only through delivery.

That's the blackhole. I'll hand over to [Presenter 4] for the wormhole.

**If asked:**

- "The red island looks like a detector." It's a picture of delivery loss (PDR). With PDR removed the same windows overlap, and the paper says PDR is also the verifier's own check.

## Slide 36 — Wormhole results

**Presenter 4** · about 0:05

Thank you. The wormhole: did the tunnel work, what did it change, and what does clustering find?

## Slide 37 — Wormhole: confirmed in all 36 runs

**Presenter 4** · about 1:10

The wormhole was confirmed in all 36 runs: 21 strong and 15 good.

The four numbers on the left. 99.86 percent of end B's probes reached the root twice, 12,448 out of 12,465. There were zero duplicates in baseline or cooldown, and none from any other board. And the median gap between the two copies of a probe was 3.9 milliseconds.

How to read the graphs: the shaded area is the 180-second attack. On the left, end B's tunnel messages per second. In the middle, the share of B's seconds that had a duplicate at the root, from 0 to 1. On the right, the gap between the two copies, in milliseconds. The colour is the scenario.

What you see: the left and middle panels are at zero before and after the attack, and jump up only inside it. Highload reaches about four messages a second, because it probes four times as often. And the gap only exists during the attack, at a few milliseconds.

**If asked:**

- Table 6.11: DuplicateRate 36/36 (baseline 0 in every run, attack 0.986 to 1.000); TunnelIntensity 36/36.
- The wire delivered 99% to 101% of what B sent, all 36 runs. B was deeper than A in every run.
- The 15 "good" = 9 partial-mesh plain-tree notes + 6 runs with no saved root run log.

## Slide 38 — Figure 6.4: hops skipped by the tunnel

**Presenter 4** · about 0:45

This figure shows how far the tunnel jumped in each run. Each tile is one run, laid out the same way as Figure 6.1. Darker purple means more hops skipped, from 1 to 5. The second number in each tile is the typical gap between the two copies, in milliseconds.

Only the linear topology skips many hops, 2 to 5. The star always skips exactly 1, because end A is the hub. Tree and partial mesh skip 1 or 2. The gaps stay between about 2 and 10 milliseconds. The 5-hop linear tiles have the largest gaps, but across all runs there's no clear trend, which the next figure shows.

## Slide 39 — How to read box plots and Cohen's d

**Presenter 4** · about 1:30

Before the feature distributions, a quick guide to box plots and Cohen's d.

In a box plot, the line in the middle is the median. The box covers the middle half of the values, from the 25th to the 75th percentile, and the whiskers reach up to 1.5 times that range. Blue is baseline, red is attack. If the boxes overlap, the feature didn't change.

Cohen's d tells us how big a shift is: the attack mean minus the baseline mean, divided by the pooled standard deviation. Under 0.2 is negligible, about 0.5 is medium, 0.8 or more is large. Negative means lower during the attack.

Most of our features have a d under 0.1, so negligible. The victims' PDR has a d of minus 29.71, far off this scale. As a sanity check: a change from 0.998 to 0.000 with d of 29.71 means a pooled spread of about 0.034, so the mean moved almost 30 typical spreads. For the wormhole, TunnelIntensity on the ends has a d of 1.83, and the largest d on the non-attacker boards is only 0.06.

One caution: d is a size, not a significance test. The windows of one board follow each other in time, so they're not independent.

**If asked:**

- "Why no significance test?" Windows follow each other in time; the real sample size is closer to 80 runs than 456,195 windows (Section 6.5.4).

## Slide 40 — Figure 6.12: wormhole feature distributions by phase

**Presenter 4** · about 0:35

Here are the wormhole features. One panel per feature, with boxes for the other children, end A and end B, each baseline in blue, then attack in red. The tunnel features only exist on the two ends.

What you see: only the tunnel panels change, and only on A and B during the attack. The signal-strength boxes are the same before and during the attack. And the delivery of the other boards stays at 0.9999, with no feature moving more than a d of 0.06.

**If asked:**

- B's RetryRate rises 0.00 → 0.50, but on B that counter holds the tunnelled frames, not retries.
- TunnelBytes 0 → 57.5 bytes per second (30 bytes × 1.92).

## Slide 41 — Figure 6.6: spread between the two copies of a probe

**Presenter 4** · about 0:50

This figure asks how far apart the two copies arrive, and whether that grows with the hops skipped.

On the left, one box per topology. The y-axis is logarithmic, so each step is ten times the one below. On the right, one dot per run: hops skipped across, typical gap up.

The typical gap is a few milliseconds in every topology, with rare long delays: the 90th percentile is 12.1 milliseconds, and the 99th is 417. The 4- and 5-hop runs sit a bit higher, but the link is weak and not significant, a Spearman correlation of 0.25 with a p-value of 0.14. So from 36 runs, we can't claim a relationship.

**If asked:**

- Weak spot: 6.2.2 says "the spread does not grow with the hops skipped". Safe phrasing: "no relation can be claimed from 36 runs (Spearman 0.25, p = 0.14)", which is the paper's own next clause.

## Slide 42 — Wormhole predictions: traffic yes, radio and routing no

**Presenter 4** · about 1:00

Now Table 3.5, the wormhole predictions.

Hop counts change: no, zero windows with a hop change in any phase. Impossible parent links: no, zero windows with a parent change. RSSI that doesn't fit the depth: no. End A's RSSI-to-hop difference went from 2.79 to 2.76 dB, and B's from 5.41 to 5.68, basically unchanged. RSSI variance rises: no, Cohen's d of minus 0.03 and minus 0.07.

Duplicate arrivals at the root: yes, in 6,468 of 6,469 attack windows of end B. And a latency mismatch between the copies: yes, a median spread of 3.9 milliseconds.

So the summary line: what belongs to the traffic the tunnel creates was observed. What belongs to routing and radio was not. That's exactly what an application-layer tunnel implies. The routing protocol never knew the tunnel existed, so it never changed anything.

**If asked:**

- Table 3.5 has nine indicators; Table 6.16 covers all of them. Not measurable: routing table entries (firmware doesn't log them); retransmissions near the ends (B's counter holds tunnel frames).
- Out-of-order arrivals: rare, 0.93%.

## Slide 43 — Wormhole and pooled clustering

**Presenter 4** · about 1:15

Clustering on the wormhole, on the left. On the non-attacker boards, every algorithm at every k scores between minus 0.012 and 0.003: chance. On the tunnel ends themselves, using the RSSI features, also chance. Only when we added TunnelIntensity as a diagnostic, which the leakage guard normally keeps out, did DBSCAN reach 0.827 on end B. So the tunnel signal exists, but it lives in the attackers' own counters, not in the cross-layer features.

On the right, we pooled all 80 runs, with three labels: normal, blackhole and wormhole. K-Means scored 0.333, and the best possible is 0.334. In other words, it found the blackhole victims and nothing else.

The table shows what happens if you treat that cluster as a detector. Of the victim attack windows, 21,733 of 21,733 fell in the "victim" cluster. Of the benign windows, zero of 22,481. Of the normal windows from blackhole runs, 183 of 89,140. And of the wormhole attack windows, just 3 of 32,194. So it catches the delivery collapse cleanly, never fires on benign traffic, and is blind to the wormhole.

**If asked:**

- Why K-Means at k = 2 gives 0.000 on B: it splits by signal level (−67.6 vs −47.1 dBm), which varies between runs, not by tunnel activity.
- Pooled set: non-attacker boards of all 80 runs, 257,258 windows. Without PDR: −0.023 to 0.005.

## Slide 44 — Benign runs and both attacks

**Presenter 4** · about 0:10

Now the control runs, the single-feature audit, the two attacks side by side, and what it all means.

## Slide 45 — Benign runs: no attack signature

**Presenter 4** · about 1:10

All 8 benign runs were confirmed benign, all graded strong.

How do you test a run with no attack? We used the same tests, pointed the other way: cooldown against baseline. No signature is allowed to pass, and delivery has to stay healthy, PDR at least 0.90 and every relay forwarding at least 90 percent. Result: of the 21 signature checks that could be evaluated, zero passed. The other checks needed an attacker or a tunnel, so they had no data, as expected. Cooldown stayed within half a baseline standard deviation in 24 of 24 comparisons. And mean PDR per run was 0.9994 to 1.0000.

What 8 runs can and can't show: they're enough as a control, because none of them triggered the verifier. But they're not enough to estimate a false-alarm rate, and the paper says so and recommends more benign runs. Also, within one topology, the benign scenario and site are confounded, since there's only one run per combination.

**If asked:**

- "Are 8 benign runs enough?" As a control, yes; for a false-alarm rate, no (Section 6.5.4, Recommendation 2).
- Only 4 of 54 child boards ever had a window below PDR 1, all in linear / G402 / highload (lowest 0.75).

## Slide 46 — Signal strength separates captures, not attacks

**Presenter 4** · about 1:20

One thing the benign runs revealed is about signal strength.

How to read it: one dot per benign run. Across is the baseline signal of the attack run of the same cell, in dBm; up is the benign run's. On the left, compared with the blackhole run; on the right, with the wormhole run. If two set-ups of the same cell were identical, the dots would sit on the dashed line, and the grey band is within 3 dB.

What you see is that most dots sit outside the band, on both sides. On average, setting up the same cell again shifted the baseline signal by 8.1 dB compared with the blackhole run, and 7.1 dB compared with the wormhole run. That's because each capture is a fresh set-up, and signal strength depends on exactly where each board stands.

Why this matters: RSSI mean is the only big difference between benign and attack-run normal windows, with a d of 0.69. So for clustering, RSSI can split windows by set-up instead of by attack. That's a caution for anyone using this dataset.

**If asked:**

- Consequence: one run per cell cannot separate site effects from capture-to-capture variation.

## Slide 47 — Can one feature decide it? The single-feature audit

**Presenter 4** · about 1:20

This is the single-feature audit. The question: can one feature with one cut-off tell attack seconds from normal ones? If it can, clustering adds nothing, or the feature is an artefact.

How to read it: each bar is the best accuracy a single cut-off on that feature can get. The axis starts at 50 percent. Dark blue is all non-attacker boards, red is victims only.

The most important reference is 70 percent. A run has 420 normal seconds out of 600, so always guessing "normal" already scores 70 percent. Anything near 70 means no information.

PDR stands out: 99.9 percent on victims, because a full delivery collapse is separable by construction. On all boards it's only 86.9 percent, again because of the bystanders. LatencyHopRatio looks good, but only through its blanks: when a probe is dropped, there's no delay to measure, so the blank itself gives the label away. That's why we don't cluster on it. The run clock gets 80 percent, but that's just the fixed schedule, not a feature. And for the wormhole, on non-attacker boards, no feature beats 70 percent by more than 0.01 points.

**If asked:**

- "If PDR alone detects the blackhole, why cluster at all?" That's exactly what this audit tests, and we report it. Any future model must beat a plain PDR threshold (Recommendation 5).
- LatencyHopRatio's missingness alone predicts a victim's label with 99.2% accuracy.

## Slide 48 — EDA: only the delivery of the victims moves

**Presenter 4** · about 0:55

This slide puts the two attacks side by side on delivery.

How to read it: time runs left to right, shaded is the attack. Height is PDR. The solid purple line is the non-attacker boards in the wormhole runs. The dashed red line is the blackhole victims.

Purple stays at 1 for the whole run. Red drops to 0 for the whole attack. The wormhole doesn't stop delivery; the blackhole does.

In numbers, at the top: in the blackhole, the victims' PDR goes from 0.998 to 0.000 with a d of minus 29.71, and every other feature of victims and bystanders has a d under 0.1. In the wormhole, the non-attacker boards' PDR stays at 0.9999, and the largest d is 0.06. On the ends, only the tunnel features change.

**If asked:**

- Victims' RSSI is about 2.5 dB weaker than bystanders' already in the baseline (−74.7 vs −72.2 dBm): they sit deeper.
- Bystanders' LatencyHopRatio falls during the run and keeps falling after the attack; benign runs show the same, so it follows the course of a run, not the attack.

## Slide 49 — Discussion: the attacks live in the data plane

**Presenter 4** · about 1:30

So what does it all mean? This table puts the three run types side by side.

For the blackhole, the direct record shows the attacker's forwarding ratio going to zero and the victims' PDR to zero. The only cross-layer feature that changed was the victims' PDR. And clustering scores 0.514 against a ceiling of 0.515, and about zero without PDR.

For the wormhole, B's probes reached the root twice, 99.86 percent of the time. No cross-layer feature changed: hop and parent stayed the same, and no d went above 0.07. And clustering is about zero without a tunnel feature.

For benign, zero of 21 signature checks passed, cooldown stayed within half a standard deviation in all 24 comparisons, and zero of 22,481 benign windows fell in the victim cluster.

Our main reading: Chapter 4 expected cross-layer evidence. Instead, the evidence sits in delivery for the blackhole and in duplication for the wormhole, and the physical, MAC and network features stay where they were. The attacks live in the data plane.

And one honest qualifier we want to say before you do: PDR is also one of the verifier's own checks. So the clustering finds the effect the verifier measured. It's not independent evidence that cross-layer features detect the blackhole.

**If asked:**

- "So your cross-layer features failed?" They didn't respond to these attacks because these attacks never touch radio or routing. Whether they help against routing attacks is Recommendation 1.
- Limits (6.5.4): one run per cell; windows not independent; partial mesh = plain tree; tree fan-out differs; no routing-table logging; sniffer on 7 runs; 8 boards.

## Slide 50 — Compared with published studies

**Presenter 4** · about 1:30

Here's how our results line up with published studies. Platforms, scales and protocols all differ, so we compare direction and rough size, not equal values.

Baseline delivery: ours is 0.998 for victims and 0.9994 to 1.0000 for benign runs. Khan et al. report above 0.97 on ESP32. Those agree in size, though they count differently.

Delivery under blackhole: ours drops to 0.000. Airehrour et al. report 25 to 40 percent delivery on RPL. Same direction, larger here, because our attacker is on the path by placement.

Parent changes under blackhole: ours essentially don't change. Airehrour et al. saw 16 to 246 rank changes. That differs because their attack acts on routing, and ours can't, D-20.

Wormhole hop count: ours stays constant. Zhukabayeva et al. saw a route go from 4 hops to 3 on ZigBee. Their tunnel is a route; ours is an application relay.

Wormhole delay: we measure a 3.9 millisecond spread between copies. They measured end-to-end delay rising from 80 to 100 milliseconds to 120 to 200. That's a different measure, and their tunnel was GSM, ours a short wire.

And duplicate arrivals: we see them on 99.86 percent of B's probes and none in baseline. Ramírez Gómez et al. proposed duplication as the wormhole signature. Same evidence, at a different layer.

**If asked:**

- "Your PDR is higher than Khan's, why?" Different counting: they count packages over days, up to 100 m outdoors; we count per one-second window over 11 minutes.
- "Was Airehrour's a simulation?" No, 14 real motes in a lab; Contiki/Cooja ran on the desktop attached to the sink.

---

# Chapter 7: Conclusion

## Slide 51 — Chapter 7: Conclusion

**Presenter 4** · about 0:05

Finally, Chapter 7: what the objectives came to, what we contribute, our limits and our recommendations.

## Slide 52 — The three objectives, answered

**Presenter 4** · about 1:05

Objective one: build an ESP32 mesh testbed with normal and attack traffic. Achieved. All 80 of 80 runs were captured, the attacks were confirmed in 72 of 72, and the benign runs in 8 of 8. The qualifiers: the attacks are emulated, and the partial mesh behaved as a branched tree.

Objective two: collect physical, MAC and network features into a labelled dataset. Achieved. 16 features, labels taken from the schedule, and every change documented from D-1 to D-37. The qualifier: there's no MAC retry count on the boards.

Objective three: evaluate separability with EDA and clustering. The answer differs by attack. The blackhole is separable, but only through PDR, 0.514 against a ceiling of 0.515. The wormhole is not separable with cross-layer features, scoring between minus 0.012 and 0.009.

So the expected cross-layer evidence was not found, because both attacks left the radio and the routing unchanged. We report this as a finding, not a failure.

**If asked:**

- Dataset validity (7.3): 72 attack runs passed (67 complete, 5 minor gaps); 1,372 windows (0.30%) dropped; 637 files, none empty; one board (B768, a bystander) recorded nothing.

## Slide 53 — Figure 6.30: pooled 80 runs, FULL set

**Presenter 4** · about 0:30

Two pictures back up objective three. This is all 80 runs pooled, with all 8 features. Each dot is one second, 6,000 sampled. On the left is PCA, on the right t-SNE. The six colours are three kinds of normal second and three kinds of attack second.

Only the red dots, the blackhole victims under attack, stand apart, in both pictures. The other five groups, including the wormhole attack seconds, are mixed together.

## Slide 54 — Figure 6.31: pooled 80 runs, PDR removed

**Presenter 4** · about 0:20

And this is the same pooled picture with PDR removed, using only the three RSSI features. All six groups are mixed, the red one too. Without PDR, the pooled data show no structure at all, with an ARI between minus 0.023 and 0.005.

## Slide 55 — Findings and contributions

**Presenter 4** · about 0:55

Four findings. One: the blackhole causes a clear delivery loss among victims, and PDR is the strongest indicator. Two: the wormhole causes duplicate arrivals at the root, consistently, and only during the attack. Three: retransmissions, parent changes, hop counts and signal-to-hop did not change. Those are the Chapter 3 predictions that didn't hold, and we kept them as written on purpose. Four: clustering depends on the feature tied to the attack. Remove it, and the separation collapses.

And three contributions. First, a testbed: an ESP32 mesh that runs normal operation and two attacks under varied topologies, sites and scenarios. Second, a dataset: 80 runs, with topology, site, scenario, role and phase on every row. Third, a verification process that separates real attack effects from missing data or broken runs, and that was itself tested.

**If asked:**

- Firmware and tools are in the project repository [79].

## Slide 56 — Limits and what should come next

**Presenter 4** · about 1:10

Our limitations, on the left. The attacks are application-layer only. We used only 8 boards, at three campus sites, one of them semi-outdoor. Only 8 benign runs, so no reliable false-alarm rate. No direct MAC retry count, and the sniffer only on some runs. One run per condition. And our strongest results rest on features tied to how the attacks were built.

So, five recommendations. One, attack routing directly, with modifiable routing or forged management frames, to see whether the parent, hop, retry and RSSI features react once an attack really manipulates routing. Two, collect more normal data: benign runs in every cell, with repeats, so a false-alarm rate can be estimated. Three, improve network measurement, with a sniffer on every run. Four, test more wormhole scenarios: tunnel other nodes' traffic, and try other layouts. And five, evaluate detectors fairly: hold out whole runs as test data, and require any model to beat a simple PDR or duplicate baseline, including with the main attack feature removed.

**If asked:**

- "Do your results generalise?" No claim beyond 8 ESP32 boards, three campus sites, three scenarios, and application-layer attacks (6.5.4).

## Slide 57 — Thank you

**Presenter 4** · about 0:25

To close: in our setup, detecting these attacks depended on delivery and on duplication. The other cross-layer features did not separate the attacks. Because the attacks were emulated at the application layer, these results are not proof about routing-level attacks. That's where the next study should go.

Thank you, panel. We're happy to take your questions.

---

# Backup slides (not part of the timed talk)

Open these only when a question calls for them. Each slide already has a "How to read it" box; the line below is what to say once it's on screen.

| Slide | Figure | Open it when asked… | Say |
|---|---|---|---|
| 58 | Backup divider | | |
| 60 | Fig 6.3, attacker ForwardingRatio | "Did the attacker really stop forwarding?" | It drops from 1 to 0 for exactly the 180 s of the attack and comes back; the baseline and attack histograms never overlap. 1,077 received, 1 forwarded in the G402 linear stationary run. |
| 61 | Fig 6.9, blackhole distributions | "Which features changed for victims?" | Only PDR moves; the victims' attack box drops to 0. LatencyHopRatio has no victim attack box because no probe arrived, so there is no delay. |
| 62 | Fig 6.10, correlations | "Are your features redundant?" | Blackhole runs only. Four strong pairs, each explained by the formula (e.g. ConsistencyScore = abs(ForwardingRatio − 1), Spearman −0.94). No other pair of the 8 clustering features passes ±0.4. |
| 63 | Fig 6.17, DBSCAN eps | "How did you pick eps?" | Distance to each window's k-th nearest neighbour, sorted; eps at the bend (0.79 FULL, 0.73 REDUCED, 0.56 no PDR). Above the line is noise, 1 to 2%. |
| 64 | Fig 6.18, ARI vs k | "Does it depend on k?" | With PDR the methods find the attack; without PDR every line is flat at 0. K-Means REDUCED k = 2: 0.514 all nodes, 0.996 victims. |
| 65 | Fig 6.19, silhouette vs k | "Why not just use silhouette?" | On FULL, k = 2 looks best (0.77 / 0.90), but on 2 of 3 seeds that split only cuts off a few odd seconds. ARI there is 0.172; the attack appears at k = 4 (0.505). |
| 66 | Fig 6.20, Davies–Bouldin vs k | Same | No single k is best for every method, so k was chosen from elbow, silhouette and interpretability together, as Chapter 4 planned. |
| 67 | Fig 6.21, cluster contents | "What's inside the clusters?" | With PDR, one cluster of about 1,000 seconds is almost all victims under attack. Without PDR every cluster is a mix. |
| 68 | Fig 6.22, PCA/t-SNE FULL | "Show the blackhole picture" | In t-SNE the victims under attack form their own island. PCA is squeezed into a column by a few extreme RSSI-variance seconds. |
| 69 | Fig 6.23, without PDR | Same | All four colours on top of each other; nothing to find. |
| 71 | Fig 6.24, wormhole clustering vs k | "Can clustering find the wormhole?" | Flat at 0 for non-attacker boards and for cross-layer features. Only with TunnelIntensity added (diagnostic) does DBSCAN reach 0.827 on B. |
| 72 | Fig 6.25, wormhole PCA/t-SNE | Same | Fully mixed in the first two columns; purple splits off only when TunnelIntensity is added, because it is 0 in every normal second. |
| 74 | Fig 4.55, verifier flowchart | "Walk us through the verifier" | Capture, import, features, then four checks side by side, a setup check, and the outcome rules. Missing data is never a pass or a fail. |
| 75 | Fig 6.13, benign delivery | "Did benign delivery stay healthy?" | All runs at 1.00 apart from small dips in one run. Only 4 of 54 boards ever dropped below 1, all linear / G402 / highload. Axis starts at 0.95. |
| 76 | Fig 6.14, scenario effect | "Do scenarios mean the same thing in benign and attack runs?" | Probe rate and PDR match (about 1.0, 1.1 and 3.9 probes/s). Delay per hop differs most in burst, which has only 1 benign run. |
| 77 | Fig 6.15, normal windows compared | "Are benign normal seconds like attack-run normal seconds?" | Only RSSI_mean differs, and that comes from the set-up of each capture (slide 46), not from an attack. |
| 78 | Fig 6.26, pooled ARI vs k | "Can it tell all three apart?" | K-Means reaches the best possible (0.333 vs 0.334) but never passes it, so the wormhole seconds are never found. |
| 79 | Fig 6.27, pooled clusters k = 2 | "What's in the pooled clusters?" | C0 (537 s) is 100% blackhole victims with PDR 0. Without PDR both clusters mix all six kinds and differ only in signal level. No benign second in the victim cluster. |
| 80 | Fig 6.29, features per cluster | Same | C0 = PDR 0 (victims). C2 (38 s) = very high RSSI variance, noisy seconds, not an attack. |

# THESIS3 Defense — Presenter Script

Deck: THESIS3-Defense oct. 20, 2026 · Defense: oct. 24, 2026

Timing assumes about 140 spoken words per minute. Replace [Presenter N] with names.

| Presenter | Slides | Time |
|---|---|---|
| Presenter 1 | 1–7 | about 6:20 |
| Presenter 2 | 8–15 | about 8:25 |
| Presenter 3 | 16–23 | about 7:50 |
| Presenter 4 | 24–33 | about 9:05 |
| **Total** | 33 | **about 31:40** |

## Slide 1 — Slide 1

**Presenter 1** · about 1:05

Good [morning / afternoon], panel. We are NIS16. I'm [Presenter 1], and with me are [Presenter 2], [Presenter 3] and [Presenter 4]. Our adviser is Mr. Gregory Cu.

Our thesis is "Cross-Layer Dataset Design and Exploratory Analysis of an ESP32-Based ESP-WIFI-MESH Network." In short: we built a real mesh network out of ESP32 boards, attacked it in two controlled ways, and recorded what happens at the physical, MAC and network layers, so the result can be used as a labelled dataset.

Since the panel last saw Chapters 1 to 3 several months ago, we'll go through them quickly as a refresher, in about four slides. Most of our time goes to Chapter 4, which is how the dataset is built and checked, and then the results we have so far. I'll cover the recap, [Presenter 2] the research design, [Presenter 3] data processing and validation, and [Presenter 4] the results.

## Slide 2 — Slide 2

**Presenter 1** · about 1:10

Here's where the project has been over nine months, in four steps.

In Thesis 1 we proposed the gap, the objectives, the planned testbed and the features. In Thesis 2 the design paper was approved on March 15, 2026, and the panel gave comments that we carried into this term. Then we built everything: the firmware for both attacks, microSD logging on every board, a radio fixed at 20 megahertz so a sniffer can read the frames, and the verifier and analysis pipeline. Thesis 3 is the data campaign, which started September 30 at three DLSU sites, and this final paper.

The box at the bottom is what changed since you last saw the work. Each run now uses eight boards, a root plus seven children. We collect at three campus sites under three traffic scenarios. Every board mirrors its log to a microSD card. An independent sniffer records the radio traffic. And a 3-sigma verifier checks every run before it is allowed into the dataset.

## Slide 3 — Slide 3

**Presenter 1** · about 0:10

Let's start with the recap of Chapters 1 to 3: the problem, our objectives, the literature, and the theory the dataset rests on.

## Slide 4 — Slide 4

**Presenter 1** · about 0:55

ESP32 boards are cheap, and they're already used for IoT monitoring over ESP-WIFI-MESH. But research on attacking these networks is mostly done in simulation. We see three problems.

First, simulated data. The well-known intrusion detection datasets, KDD, NSL-KDD and UNR-IDD, come from simulators or regular IP networks, not from mesh hardware.

Second, missing layers. Packet or flow datasets don't keep the physical, MAC and network-layer signals of a microcontroller mesh together in one place.

Third, real attacks. Blackhole and wormhole attacks are well studied in theory, but how they actually look on real ESP32 boards isn't documented.

So the gap our study fills is at the bottom: a hardware-derived, labelled, cross-layer dataset from a real ESP-WIFI-MESH network, under normal operation and under two controlled attacks.

## Slide 5 — Slide 5

**Presenter 1** · about 1:00

Our general objective is to design, generate and analyse a cross-layer dataset from an ESP32 mesh, to explore how normal operation differs from controlled attacks.

It breaks into three specific objectives. One, build an ESP32 mesh testbed with normal and attack traffic. Two, collect PHY, MAC and network features into a labelled dataset. Three, check that dataset with exploratory data analysis and unsupervised clustering. These are unchanged from the approved paper.

On scope: we cover two attacks, blackhole, which is forwarding suppression, and wormhole, which is an out-of-band tunnel, both emulated at the application layer. Each run uses eight boards, one root and seven children, at three indoor DLSU sites on an isolated mesh.

And one point we want to be clear on: our output is a dataset and its exploratory analysis. We are not building or deploying an intrusion detection system.

**If asked / prep:**

- Why no IDS? The objectives in the approved paper are dataset + EDA + clustering. An IDS would need the full labelled dataset first; that is future work the dataset enables.

## Slide 6 — Slide 6

**Presenter 1** · about 0:45

Chapter 2 gave us four takeaways.

On attacks: blackhole and wormhole detection is mature in simulation. Bhatti, for example, reports 98 to 99 percent in ns-2. Results on real systems are weaker.

On datasets: the existing ones lack ESP-WIFI-MESH behaviour, cross-layer metrics, real-hardware attacks and multiple topologies. This is the gap we answer directly.

On the platform: ESP32 mesh is proven in the field. Khan and colleagues report delivery above 97 percent on a campus deployment, which is also a benchmark we compare against later.

And on method: labelled attack data is scarce in IoT, which is why we use EDA and unsupervised clustering instead of a supervised classifier.

## Slide 7 — Slide 7

**Presenter 1** · about 1:15

Chapter 3 is the idea the whole dataset rests on. Normal mesh traffic keeps a set of relationships between layers. An attack breaks some of them, and our features are designed to measure that break. There are four.

First, received roughly equals forwarded: every relay passes on what it gets. A blackhole breaks this, because it receives far more than it forwards.

Second, one copy per probe: each probe reaches the root once, by one path. A wormhole breaks this, because a second copy arrives through the tunnel.

Third, delay follows hops: deeper nodes take longer to reach the root. A wormhole's shortcut breaks that pattern.

Fourth, a parent's layer is always lower than its child's, so the tree stays consistent. We watch this one, but we don't expect our attacks to change it, and later we'll show they didn't.

That's why our features are ratios and mismatches rather than raw values: they target the relationship, not a number that changes from site to site.

That ends the recap. I'll hand over to [Presenter 2] for Chapter 4.

## Slide 8 — Slide 8

**Presenter 2** · about 0:10

Thank you. Chapter 4 is our research design: how the testbed runs, how both attacks are built, and how the data is collected, turned into features and checked.

## Slide 9 — Slide 9

**Presenter 2** · about 1:10

This is the architecture, from boards to dataset, left to right.

One: each board logs ten times a second to its internal flash and to a microSD card. Two: after the run, we import the logs by card reader or USB. Three: preprocessing cuts the data into one-second windows and keeps the labels. Four: we compute the features: forwarding, delivery, topology, RSSI and tunnel. Five: EDA and clustering run on that windowed table.

One design choice matters here. Data collection is a file import after the run; nothing is collected live over the mesh. If we collected over the mesh, a blackhole would be dropping its own evidence.

And the attack evidence never rests only on the attacker counting its own drops. The root keeps its own log of every probe that arrives, and the attacker's neighbours keep their own counters, so each drop is confirmed from outside the attacker. A laptop sniffer outside the mesh also records the 802.11 frames.

**If asked / prep:**

- If asked about the sniffer: it is a supporting source. Its MAC retry column is currently missing from most analysis tables and is being restored (slide 30), so don't present it as the main proof.

## Slide 10 — Slide 10

**Presenter 2** · about 1:35

Every run follows the same timeline.

Formation lasts at least 60 seconds while the mesh builds itself. It's labelled 255 and excluded from the dataset. Then 300 seconds of baseline, label 0. Then 180 seconds of attack, label 1 for blackhole or 2 for wormhole. Then 120 seconds of cooldown, label 0 again, and the run terminates.

The root controls the timeline. It sends each phase change to every node in five rounds, 100 milliseconds apart, under one sequence number. It also repeats the current phase every 10 seconds, so a node that drops and rejoins catches up.

Before the attack can start, the run has to pass gates. Every child must be present. In a tree, the attacker must actually have a child to cut off. For a wormhole, both ends must report that the wire works, and end A must be shallower than end B. Then the operator types START. These gates were added on October 17, so they apply to runs from that date on. Earlier runs started on the fixed schedule, and the verifier's setup check, which you'll see shortly, confirms their layout after the fact.

Most importantly, labels come from this schedule. Each row carries the phase it was logged in. A label never comes from a threshold on a feature, so the ground truth is independent of the data we analyse.

**If asked / prep:**

- Why label 255 for formation? It marks rows that are not part of the experiment, so they can be excluded by value instead of by time.

## Slide 11 — Slide 11

**Presenter 2** · about 1:05

The blackhole. Every node in our mesh is a relay: it passes its children's probes one hop up, and it counts what it received, forwarded and dropped.

The attacker runs exactly the same relay code. In the attack phase it simply stops calling esp_mesh_send, so the probes go nowhere. It still acknowledges every frame at the link layer, so its victims never see a send failure. From their side, everything looks normal.

Because received equals forwarded plus dropped on every node, the forwarding features exist on all relays, not just on the attacker.

What we don't reproduce is the luring part, which is advertising a false route to attract traffic. ESP-WIFI-MESH lets an application read its routing table but not write it, so there's no way to fake a route. Instead, the attacker is a placed relay. We put it on the path, and its position is an experimental variable that we record.

**If asked / prep:**

- "Why not route attraction?" There is no ESP-WIFI-MESH API to write the routing table; the stack is closed. So attacker position becomes an experimental variable instead (design decision D-20).

## Slide 12 — Slide 12

**Presenter 2** · about 1:25

The wormhole needs two colluding nodes joined by an out-of-band channel. Ours is a physical UART wire at 115,200 baud, carrying 30-byte frames, each protected by a CRC32 check.

Node B, the deeper end, sends each of its probes normally over the mesh, and during the attack it also writes the probe to the wire. Node A, the shallower end, reads it and re-injects it toward the root, tagged so the root keeps it instead of discarding it as a duplicate. So the root receives every one of B's probes twice, by two paths, with different delays. The two ends are chosen at run time by mesh depth and locked in at phase 0.

What this shows is the packet-level signature of a wormhole: duplicate arrivals and a delay mismatch. What it doesn't show: the mesh never routes over the wire, so no false neighbour appears and the tree doesn't change.

The wire plays the same role as the GSM tunnel in Zhukabayeva and colleagues. One more note: only Node B's own probes are tunnelled, so a wormhole run has no victims in the blackhole sense. Every other node is simply "not tunnelled."

**If asked / prep:**

- Be honest that the false-neighbour effect is not reproduced (D-20). The contribution is the duplicate + delay signature on real hardware.

## Slide 13 — Slide 13

**Presenter 2** · about 1:15

We checked both attacks against published definitions.

For the blackhole, against Airehrour and colleagues: the attacker is on the forwarding path, it receives and then drops, it stays protocol-compliant, and delivery collapses while the node stays reachable. All four are met. The one we don't meet is attracting traffic with a false route, for the reason on the previous slide.

For the wormhole, against Hu, Perrig and Johnson: two colluding endpoints, an out-of-band channel, packets captured at one end and replayed at the other, and no keys or hosts compromised. All met. The one we don't meet is creating a false neighbour.

We list the failed criteria on purpose, because they follow directly from emulating at the application layer.

The evidence is at the bottom. In the G402 linear stationary run, the attacker forwarded 1 of 1,077 probes, and all six victims fell from a PDR of 1.000 to 0.000. In all nine linear wormhole runs, the root logged Node B's probes twice in 179 to 180 attack windows each, and never in baseline or cooldown.

**If asked / prep:**

- These are Tables 4.4 and 4.5 in the paper.

## Slide 14 — Slide 14

**Presenter 2** · about 0:50

We run each attack on four topologies. These are the blackhole layouts: star, tree, linear chain and partial mesh.

The layouts come from where we place the boards plus the ESP-IDF topology option. The mesh still builds its own tree; we don't hard-code it. In the star, the attacker is the hub and the root sits one hop behind it, so every other node depends on the attacker. The attacker's depth and the number of victims vary by run, so the drawings show one example layout.

One finding to flag early: the partial mesh behaved as a plain tree in all nine runs. No node was seen under a second parent during the attack.

**If asked / prep:**

- Figures 4.17, 4.19, 4.21 and 4.23 in the paper.

## Slide 15 — Slide 15

**Presenter 2** · about 0:50

Here are the same four topologies for the wormhole.

The tunnel only means something if it skips hops, so Node A must sit shallower than Node B. That's a problem in a flat star, because both ends are at hop 1 and nothing is skipped. Our proposal is to make end A the hub, with the root behind it, and we're asking our adviser to confirm that design.

We tried the first hub-star runs on October 20. They failed because the hub board browned out, which is a power problem, not a design problem. So far, all nine processed wormhole runs are on the linear chain.

[Presenter 3] will take it from here with the sites and how the data is processed.

**If asked / prep:**

- Hub-star is design decision D-28, still open with the adviser. Figures 4.16, 4.18, 4.20, 4.22.

## Slide 16 — Slide 16

**Presenter 3** · about 1:15

Thank you. We collect at three sites, chosen for their different Wi-Fi interference. G402 in GCCS is our controlled classroom. The DLSU Library is a small area of a busy library with heavy Wi-Fi. And the Yuchengco Building is an area within that building.

We also run three traffic scenarios. Stationary sends a probe every second and is our reference. In burst, one child sends 300 probes back to back, about 100 a second, 60 seconds into the attack window. Highload has every child probe every 250 milliseconds. The scenarios exist so that traffic volume alone can't give away an attack. A model shouldn't be able to learn "more packets means attack."

The full design is 4 topologies, times 2 attacks, times 3 sites, times 3 scenarios, which is 72 attack runs. Add 9 matched benign runs, one per scenario at every site, for 81 in total.

Each cell is run once, so the three sites act as our repeats. That's a limitation we state: we can't separate site effects from run-to-run noise.

**If asked / prep:**

- Why not repeat each cell? Time: each run needs 8 boards set up, flashed, captured and imported. The sites serve as the repeats, and the limitation is stated in the paper.
- "How heavy is the Library's Wi-Fi?" Answer only with what the team actually measured. If nothing was measured, say plainly that the site labels are qualitative descriptions.

## Slide 17 — Slide 17

**Presenter 3** · about 1:10

Here's what each board records, by layer.

PHY: RSSI to the parent, 10 times a second. The radio is fixed at 20 megahertz, called HT20, so the sniffer can decode the frames.

MAC: here we're careful. ESP-IDF doesn't expose a per-link retry counter, so the real MAC retry rate comes from the sniffer, using the Retry bit in each 802.11 frame. The firmware's own retry and transmit counters are application-level. We keep them in the dataset but don't analyse them.

Network: each node's layer or hop count and its parent MAC, plus probes sent, received, forwarded and dropped. The root also logs every probe arrival.

Tunnel: frames written by B, and frames received and re-injected by A. These exist in wormhole runs only.

Storage is flash plus a microSD mirror, synced every five seconds. Nothing is streamed over the mesh during a run, so again, the attack can't destroy its own evidence. And none of the 435 campus capture files is empty.

**If asked / prep:**

- Tables 4.8 to 4.12. App counters are kept but not analysed: design decision D-15.
- If asked whether every SD copy is complete: before the Oct. 20 firmware, a transient card error could lose a board's card copy without warning. That's why the board's flash log is kept as well, and the newer firmware counts any missed rows.

## Slide 18 — Slide 18

**Presenter 3** · about 1:00

Next, how raw rows become one-second windows, in five steps.

Align: the boards share no clock, and their clocks differ by minutes, so each node is aligned to its own exit from phase 0.

Window: non-overlapping one-second windows on a 10-hertz grid. If a window has fewer than 8 of its 10 samples, we discard it.

Fill: small gaps of one or two samples inside a kept window are filled in.

Count: cumulative counters are turned into per-window differences.

Join: PDR is computed by joining the root's arrivals to each node on the probe sequence number. Never on time, because of that clock drift.

The result is that one row equals one node for one second. We keep node-level rows on purpose, because they show the local effect: the attacker's forwarding falls while the nodes behind it lose delivery. A network-wide average would hide both.

**If asked / prep:**

- Section 4.2.4.1. Gap filling is design decision D-9.

## Slide 19 — Slide 19

**Presenter 3** · about 0:50

From those windows we compute features, grouped by what they measure. Each group maps back to a Chapter 3 relationship.

Forwarding: ForwardingRatio, IngressEgressDelta and ConsistencyScore. These test "received roughly equals forwarded."

Delivery: PDR per child per window. It's left blank when nothing was sent, rather than recorded as zero.

Topology: ParentSwitchRate, HopChangeCount and HopStabilityDuration. These test whether the tree stays consistent.

Physical: RSSI mean, variance and stability.

Cross-layer: RSSI_Hop_Diff and LatencyHopRatio. These test "delay follows hops," and whether signal strength agrees with depth.

Tunnel: TunnelIntensity, TunnelBytes, TunnelLatency and DuplicateRate. These test "one copy per probe."

The app-level retry rate stays as a dataset column only. The MAC retry rate comes from the sniffer.

**If asked / prep:**

- Table 4.17 in the paper.

## Slide 20 — Slide 20

**Presenter 3** · about 1:05

The analysis has two stages.

First, exploratory data analysis. We look at the distributions of ForwardingRatio and RSSI_Hop_Diff by phase and by node role; time series of PDR, ForwardingRatio and root arrivals over each run; Pearson and Spearman correlations for all data, baseline only and attack only; and PCA and t-SNE on z-scored features, clipped at plus or minus five. This stage is descriptive only. We make no detection claims.

Second, clustering, which is planned and not yet run. DBSCAN is the primary method, with K-Means, Ward hierarchical, Gaussian mixture and spectral clustering alongside it. We run full and reduced feature sets, with seeds 42, 7 and 123. Quality is measured internally with silhouette and Davies–Bouldin.

The labels are used only afterwards, to compute purity and the adjusted Rand index. Labels never guide the clustering. And if the wormhole windows don't separate, we report that as a finding. Clustering runs once collection ends.

**If asked / prep:**

- Why DBSCAN as primary? It needs no preset number of clusters and marks outliers as noise, which suits unknown attack structure.
- If asked for clustering results or code: there are none yet. The EDA outputs exist for every run; the clustering runs on the pooled table after collection ends (slide 32). Do not imply any clustering has been done.

## Slide 21 — Slide 21

**Presenter 3** · about 1:20

Every run is validated four ways before it enters the dataset.

One, a 3-sigma test, following Zhukabayeva and colleagues. The attack phase is grouped into blocks of five one-second windows, and each block must lie beyond three baseline standard deviations from the baseline mean. If a feature's baseline is itself broken, for example a delivery rate far below what a healthy ESP32 mesh achieves, that feature is excluded rather than scored.

Two, a setup check: what the topology was during the attack, where the attacker sat, and whether the victims were alive but cut off. For the wormhole, it checks that B was deeper than A and that the wire actually carried the probes.

Three, comparison with published studies: Airehrour, Khan, Zhukabayeva and Ramírez Gómez. We compare direction and rough size. That shows consistency, not proof.

Four, a leakage audit: can one feature alone separate attack from normal? If it can, we report it rather than hide it.

Each run comes out PASS, FAIL or INCONCLUSIVE. A run that fails the setup check is "not confirmed," no matter how clear its statistics look.

**If asked / prep:**

- Section 4.1.3.
- Why blocks of 5? At about one probe per second, a ratio over one window is a yes/no draw, which inflates the variance. Five windows matches the thesis's Table 4.10 window.
- "With sd = 0, isn't any tiny change a pass?" No. The verifier also requires a minimum absolute change, 0.10 for PDR and ForwardingRatio, so one lost probe can never count as an attack.

## Slide 22 — Slide 22

**Presenter 3** · about 0:15

Now the results so far: run status, the verified attacks, our first EDA, and how our numbers compare with published work. Everything here is provisional until all 81 runs are in.

## Slide 23 — Slide 23

**Presenter 3** · about 1:00

Here's the campaign as of October 20. The chart shows attack runs per topology, out of 18 planned for each, and what is not yet processed.

44 of 72 attack runs are processed: 35 blackhole and 9 wormhole. Blackhole is complete on linear, star and partial mesh, and 8 of 9 on tree. Wormhole is done on the linear chain at all three sites and all three scenarios. Star, tree and partial mesh wormhole still need captures. We have 0 of the 9 benign runs, and those are next.

Five captures are held out: one tree blackhole at G402 under highload, because one board has no data; a tree wormhole at the DLSU Library, where four boards had under 95 percent coverage; and three wormhole runs not yet analysed. That leaves 37 runs.

[Presenter 4] will now present the verified results.

## Slide 24 — Slide 24

**Presenter 4** · about 1:15

Thank you. We have analysed 46 runs, and 44 of them pass the verifier.

35 of 35 blackhole runs pass: the signature, the setup and the data completeness. 9 of 9 wormhole runs pass on the linear chain. And there were zero parent switches or hop changes inside any wormhole attack window.

In more detail: for the blackhole, the attacker forwards at most 4 probes in any run, which is at most 0.1 percent, and the victims lose delivery while bystanders keep theirs. For the wormhole, the wire delivered 99 to 101 percent of Node B's frames, and the root logged B's probes twice in 179 to 180 attack windows per run, and never outside the attack.

In all nine partial mesh runs, each node stayed under one parent during the attack, so those runs behave as trees. The other two analysed runs were rated INCONCLUSIVE and are held out. We don't count them, and nothing in the processed set relies on them.

These numbers come from our verifier, run on all campus runs on October 20.

**If asked / prep:**

- Which 2 are INCONCLUSIVE: blackhole tree/G402/highload (one board, B768, has no data) and wormhole tree/DLSU_Library/stationary (four boards under 95% coverage). Both are scheduled for recapture.
- "101%?" The frame counts are summed per board over that board's own attack windows, and each board is aligned separately. A difference of about 4 frames out of 720 sits at the phase edges. Say that it has not been traced further, rather than guessing.
- Partial/Yuchengco/stationary passed on ForwardingRatio alone. Its PDR was excluded as a broken baseline: one victim sat at 0.81 and one bystander at 0.78 before the attack. That is the rule from slide 21 working as designed.
- Source: tools/verify_attack.py, re-run on every campus run Oct. 20.

## Slide 25 — Slide 25

**Presenter 4** · about 0:50

Here's one blackhole run in detail: G402, linear chain, stationary traffic. The root, then the attacker, then six victims in a chain behind it.

The chart shows two values per phase. The attacker's ForwardingRatio is 1 in baseline, drops to 0.001 during the attack, and returns to 1 in cooldown. The victims' PDR goes from 1.000 to 0.000, and recovers to 0.999 in cooldown.

In numbers: the attacker received 1,077 probes during the attack and forwarded exactly one. The baseline never varied, so its standard deviation was zero, which puts this change beyond any sigma threshold.

The neighbours confirm it independently: the attacker's children handed it probes that its parent never received.

**If asked / prep:**

- Cooldown PDR 0.999 comes from the cooldown windows of the same feature table.

## Slide 26 — Slide 26

**Presenter 4** · about 1:05

For the wormhole, the signature is the second copy. This table covers all nine linear chain runs. The third column is how many frames went from B to A over the wire. The fourth is how many attack windows had duplicates at the root.

Take the DLSU Library stationary run: the root saw both copies in 180 attack windows, about 3.6 milliseconds apart, and no duplicates in baseline or cooldown. Highload sends four probes a second, which is why those rows show about 720 frames instead of 180.

Both primary signatures rise from zero. DuplicateRate goes from 0 to 1. TunnelIntensity, the tunnel frames per second, goes from 0 to 1, or to 4 under highload. TunnelLatency we report but don't test, because there's no tunnel in the baseline to compare it against. Across the nine runs, the two copies arrive about 4 to 30 milliseconds apart on average.

**If asked / prep:**

- Know this before the defense: in 4 of the 9 runs (G402 burst, Yuchengco stationary and highload, DLSU highload), plain children also have "duplicate" entries early in the baseline. They sit 150 to 370 seconds apart, so they are not the tunnel. Most likely the root's arrival log repeated probes from an earlier boot; this is still being traced. The verifier scores Node B only, so no verdict depends on them. The raw verifier prints 193 windows for G402 burst because it counts these too; Node B's own count is 180, which is what the table shows.
- Wire delivery figures come from the verifier's UART check.

## Slide 27 — Slide 27

**Presenter 4** · about 0:35

This is our first EDA view. On the left is PCA and on the right is t-SNE, for the G402 linear stationary blackhole run, using z-scored features. Red points are attack windows, blue is baseline, orange is cooldown.

The attack windows sit clearly apart from the rest. But we want to be careful with the wording: this describes a picture of one run. It is not a detection result. The pooled clustering across all runs is what will test it.

## Slide 28 — Slide 28

**Presenter 4** · about 1:00

This slide answers a concern from the Thesis 2 panel: could one feature decide everything? We tested that with a leakage audit.

For each feature, we take a single threshold per run and measure how accurately it separates attack from normal. The chart shows the mean over all 35 blackhole runs. The reference is the majority-class rate, about 0.70. That's what you'd get by always guessing the larger class.

PDR averages 0.872 and LatencyHopRatio 0.860, with ConsistencyScore and ForwardingRatio at 0.848. In 12 runs each, 9 star and 3 linear, PDR and LatencyHopRatio reach 0.95 or more. That's expected: a blackhole drops everything, so the collapse is separable by construction. The RSSI and hop features stay at the majority rate.

So yes, in some runs one feature does decide it, and we say so. The pooled audit over all runs follows once collection ends.

**If asked / prep:**

- Table 4.21, provisional. The chart was recomputed Oct. 20 from the current per-run leakage_audit.csv files (35 runs). The paper's older Oct. 15 table said 34 runs, PDR 0.863; same conclusion.
- "And the wormhole?" Its tunnel features alone separate attack from normal at about 0.99. That is also by construction, since they are zero whenever there is no tunnel. Say so if asked.

## Slide 29 — Slide 29

**Presenter 4** · about 1:10

Here's how our numbers compare with published work.

Loss under an unmitigated blackhole: Airehrour reports 60 to 75 percent. We see 100 percent, with six victims going from 1.000 to 0.000. That's above their range, because every routed probe is lost.

Healthy delivery on the same ESP32 platform: Khan reports above 97 percent. Our baseline PDR is 1.000 at G402 and 0.998 on average across all victims, so at or above the benchmark. Note that ours is per one-second window, while Khan's comes from a five-day stability test.

Routing instability under attack: Airehrour sees 16 to 246 rank changes. We see almost no parent switches. That differs because suppression doesn't change routes.

The wormhole effect: Zhukabayeva reports hop count dropping from 4 to 3 and delay rising about 40 percent. We see duplicate arrivals but no hop change. So it partly matches: we reproduce the copy, not the shortcut.

Platforms, scales and protocols differ, so this comparison is about direction and rough size, not equal values.

**If asked / prep:**

- Table 4.23, corrected Oct. 20 (an earlier 76% figure came from an old capture). Do not quote 76%.
- Khan's exact claim is above 97% at every node except one (an outdoor node). The 0.998 average hides a few weaker baselines; the lowest run averaged 0.81 (partial/Yuchengco/stationary). Don't claim every run was at 1.000.
- If asked about the delay direction: Zhukabayeva's tunnel was GSM/GPRS, ours is a short UART wire, so the delay change is not expected to match.

## Slide 30 — Slide 30

**Presenter 4** · about 1:10

We also report predictions we tested and did not see.

First, we expected blackhole victims to retransmit more. We didn't see that, because the attacker still acknowledges every frame at the link layer, so the victims have no reason to retry. The sniffer showed no consistent rise in the runs it covered. We're recomputing the exact count, which I'll explain in a moment. And the app-level counters stayed essentially flat across all 35 runs.

Second, we expected the wormhole to distort the topology. It didn't: there was no parent switch or hop change in any attack window, because the mesh never routes over the wire. The tunnel reproduces the duplicate-delivery signature without the topological one.

Why keep these? Tables 3.4 and 3.5 were written before any capture, so reporting what didn't happen is part of the result. And to be upfront: the sniffer count is being recomputed, because a re-analysis dropped the sniffer column and we're merging the captures back in.

**If asked / prep:**

- Section 4.1.3.4. Do NOT quote "8 of 22": the current tables can't reproduce it. Only 3 runs still have the sniffer column; it comes back when analyze.ps1 is re-run with the PCAPs (checklist B-mrr).
- App counters: the attack-phase retry rate was above baseline in just 1 of 35 runs, by a negligible amount (pooled mean 0.0000 vs 0.0003).

## Slide 31 — Slide 31

**Presenter 4** · about 0:50

These are the limits we state in the paper.

Emulated attacks: no route attraction in the blackhole and no false neighbour in the wormhole.

One run per cell: the sites act as repeats, so site and run noise can't be separated.

Fixed schedule: the attack starts at the same time in every run, so we keep time position out of the model inputs. Otherwise a model could just learn the clock.

Partial mesh equals tree: no node used a second parent in nine runs.

Small testbed: eight boards indoors, not a large or outdoor network.

And two open checks: a test of the SD card sync under a mid-run reset, and the star wormhole design.

**If asked / prep:**

- Sections 1.4.1 and 4.1.3.5. Open checks are D-13 (SD fsync reset test) and D-28 (hub-star wormhole).
- If asked about board resets: four boards hit the same firmware crash (inside the ESP-IDF ipc_task), and one board, 1C38, browns out on weak power. Both are mitigated; the crash root cause is not proven yet. Runs that lost data are the held-out ones, not the 44.

## Slide 32 — Slide 32

**Presenter 4** · about 0:45

Here's what's left before the final paper, in four steps.

Capture: 37 runs, which are the wormhole on star, tree and partial mesh, plus all 9 benign runs.

Re-analyse: merge the sniffer captures back in and recompute the MAC retry results.

Cluster: run the five algorithms on the pooled table and report purity and adjusted Rand index.

Write: Chapter 5, from the final tables only, with the pooled leakage audit and every placeholder cleared.

Two decisions to note. We've dropped the jitter scenario, as a team decision on October 20. And the one open design question for our adviser is the hub-star wormhole.

## Slide 33 — Slide 33

**Presenter 4** · about 0:25

To close: our contribution is a labelled, cross-layer dataset from a real ESP32 mesh. So far that's 44 verified attack runs at three sites: the blackhole on all four topologies, and the wormhole on the linear chain, with the other three wormhole topologies still to capture. Every run is checked before it enters the dataset.

Thank you. We're happy to take your questions.

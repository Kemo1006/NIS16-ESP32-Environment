# "How do you test the wormhole?" — panel answer, plain version

**Created:** oct. 4, 2026. A companion to `docs/attack-validation/ATTACK-VALIDATION.md` §2, which has
the code-cited conformance table. **This is the version you can say out loud.** Read it top to
bottom once and you can answer the question, plus the follow-ups. Every claim was checked against
the firmware and tools on oct. 4, 2026. The source for each one is in the table at the end.

---

## The 20-second answer

**We test it in three layers:**

1. **Before the run:** we prove the tunnel wire actually carries data.
2. **During the run:** the firmware checks every tunnel message and reports if nothing came through.
3. **After the run:** we look for the wormhole's fingerprint in the data and confirm it with a
   statistical test from the literature.

**The fingerprint:** the same probe reaches the root **twice**. That happens only during the
attack window, only for Node B's probes, and never in the baseline or cooldown around it.

---

## Words you need first

| Word | What it means here |
|---|---|
| **Root** | The board at the top of the mesh. Every other board sends its data up to it. It's where we check whether messages arrived. |
| **Probe** | A small "I'm alive" message each board sends to the root once per second. |
| **`seq_num`** | The probe's serial number: 1, 2, 3 … like numbered pages. If page 57 shows up twice, something copied it. |
| **Phase / label** | The run is split into timed parts. Each data row is stamped with which part it was in: **0** = normal, **2** = wormhole attack. This stamp is the "ground truth". |
| **Node A / Node B** | The two attacker boards. **B** (entry) sits among the victims. **A** (exit) sits near the root. |
| **UART wire** | A plain 3-wire cable between A and B (send, receive, ground). It's the **tunnel**, and it has nothing to do with Wi-Fi. |
| **Mesh** | The Wi-Fi network the boards build themselves (ESP-WIFI-MESH). This is the "normal road" for messages. |

---

## The picture: what a wormhole is in our testbed

**An analogy:** think of the mesh as the postal service. Letters hop from post office to post office
until they reach head office (the root). The wormhole is a **secret tube** between two post offices.
Office B drops a copy of every letter into the tube, and it pops out at office A, right next to head
office. Head office now gets **two copies of the same numbered letter**: one by the normal route,
one through the tube.

```
                 normal mesh path (Wi-Fi, hop by hop)
   ┌─────────────────────────────────────────────────────────┐
   │                                                         ▼
 [Node B] ── victims ── ... ── victims ── [Node A] ──────── [ROOT]
 (entry)                                  (exit)       re-sends B's probe
   │                                        ▲
   └──────────── UART wire (the tunnel) ────┘
               not Wi-Fi, a physical cable
```

### One probe's journey, step by step

**In normal time (baseline and cooldown, label 0):**
1. Node B creates probe #57 and sends it to the root over the mesh.
2. The root receives #57 **once**. Nothing unusual.

**During the attack (label 2):**
1. Node B creates probe #57 and still sends it to the root over the mesh, as usual.
2. **At the same time**, B wraps a copy of #57 in a "tunnel envelope" and sends it down the wire to
   Node A.
3. Node A unwraps it, checks it isn't damaged, and sends #57 into the mesh near the root.
4. The root receives #57 **twice**: same sender, same number, but **arriving at different times**,
   because the two copies took different routes.

**That doubling is the wormhole's fingerprint.** It's how you know traffic is being secretly
carried around the normal network.

### The run timeline (fixed in the firmware)

```
| mesh forms | baseline (normal) | WORMHOLE ATTACK | cooldown (normal) |
|   60 s     |      300 s        |     180 s       |      120 s        |
| not logged |     label 0       |    label 2      |     label 0       |
```

The root announces every phase change, so every board stamps its own rows with the right label.
Normal time on **both sides** of the attack matters: if the doubling shows up only in the middle and
stops afterwards, it was caused by the attack, not by a fault that was always there.

---

## Layer 1 — Before the run: does the tunnel wire work?

**Why we need it:** a bad wire fails **silently**. Node B can't tell whether its message reached the
other end. Sending into a loose wire still "succeeds" from B's side, so B looks perfectly healthy.
You'd only find out after an 11-minute run, the export and the analysis. That's how our early July
runs failed: the ground wire was missing.

**An analogy:** it's like testing a phone line before an important call. You say "one, two, three"
and ask the other side to repeat it back.

**What we do:** in the wizard, **MAINTENANCE > Wormhole UART tunnel test**.
1. It flashes a small test program (`uart_link_test`) onto both attacker boards.
2. Each board sends a **numbered ping every 50 ms** (20 per second) down the wire. Each ping
   carries a **checksum**, a small number computed from its contents.
3. Each board listens for the other's pings and counts three things:
   - **received**: pings that arrived,
   - **lost**: a gap in the numbering, meaning a ping never arrived (got #10, then #12, so #11 is lost),
   - **garbled**: the checksum doesn't match, meaning the ping was damaged on the wire.
4. The wizard reads both boards at once and prints one row per direction:

| Verdict | Meaning | What to do |
|---|---|---|
| **PASS** | Everything arrived, nothing lost or garbled | Start the capture |
| **WARN** | It works but drops some pings (shown as % lost) | Reseat the joints, use fewer chained jumpers |
| **FAIL** | Nothing arrived | Check that TX and RX are crossed, that GND is shared, and every joint |

**Two lengths:** a 10-second **quick check** ("is it connected at all?") and a 2-minute **soak
test**. The soak test is for our extended or chained jumper wires, where a loose joint might drop
only one ping in a hundred. Press **Q or Enter** to stop early and still see the results.

**Only B → A really matters.** In the real attack, B only sends and A only receives. A bad A → B
wire won't hurt the capture, but it's a warning that the other wires may be loose too.

**Why the ground wire is needed** (a likely follow-up): a UART bit is read as a voltage, high or low,
**compared to ground**. If the two boards don't share a ground, they disagree on what "0 V" is.
That's like two people measuring height from different floors: the receiver reads garbage or
nothing at all.

---

## Layer 2 — During the run: the firmware checks itself

**1. Every tunnel message is sealed with a checksum (CRC32).**
- **Analogy:** before sending, B does a calculation over the whole message and writes the result on
  the envelope. A redoes the same calculation when the envelope arrives. If the two answers differ,
  the message was damaged on the way.
- A also checks a fixed "magic number" at the start of each message, which marks it as a real
  tunnel message.
- A damaged message is **thrown away, not passed on**. So electrical noise on the wire **cannot
  create fake probes** in our data. At worst it removes some.

**2. The second copy is tagged.**
- A marks its copy with a special tag (`PROBE_MAGIC_WORMHOLE`).
- The root is coded so it does **not** discard this copy as a duplicate. Without that, the root
  would quietly throw one copy away and the fingerprint would vanish from the log.

**3. Node A gives a loud verdict at the end.**
- If A received **zero** tunnel messages during the whole run, it prints:
  `WORMHOLE TUNNEL CARRIED NOTHING - RUN IS UNUSABLE`.
- This check lives on **A**, because A is the only board that can prove a message actually crossed
  the wire. (Remember: B's sends "succeed" even into a dead wire.)

---

## Layer 3 — After the run: is the fingerprint in the data?

We check three independent sources. **They have to agree.**

### 3a. The root's arrival log — the direct evidence

The root writes one row in `arrivals.csv` per probe it receives. Here's what to look for
(**illustrative rows, not real data**):

| Sender (`src_mac`) | `seq_num` | Label | Arrival latency |
|---|---|---|---|
| Node B | 120 | 0 (baseline) | latency 1 |
| Node B | 400 | **2 (attack)** | latency 1 |
| Node B | 400 | **2 (attack)** | latency 2 (**different**) |
| Node B | 650 | 0 (cooldown) | latency 1 |

- In **baseline and cooldown**, every probe number appears **once**.
- In the **attack**, Node B's probe numbers appear **twice**, with different arrival latencies,
  because the two copies took different routes.
- The time gap between the two copies is what we call **TunnelLatency**.

### 3b. The attackers' own counters — do they agree?

Each attacker board keeps running totals in its telemetry log:

| Counter | Baseline | Attack | Cooldown |
|---|---|---|---|
| Node B: probes **tunnelled** to A (`retry_count`) | 0 | climbs (~1 per second) | stops climbing |
| Node B: probes sent the **normal** way (`tx_count`) | climbs | climbs | climbs |
| Node A: tunnel messages **received** (`probes_count`) | 0 | climbs | stops climbing |
| Node A: copies **re-sent** to the root (`tx_count`) | 0 | climbs | stops climbing |

So B's "tunnelled" count, A's "received" count and the root's number of duplicates should all land
around the same value. With 1 probe per second over 180 s, that's **about 180**.

### 3c. The statistical test — is the change big enough to not be chance?

`tools/verify_attack.py` uses the **3-sigma method** from Zhukabayeva et al. (2025), the paper our
wormhole verification is based on. In plain steps:

1. **Learn what "normal" looks like.** From the baseline phase, take each feature's **average** and
   its **normal wobble** (the standard deviation, "sigma").
2. **Measure the attack.** Take the same feature's average during the attack phase.
3. **Ask how many wobbles away it is.** That number is the **z-score**:
   z = (attack average − baseline average) ÷ baseline wobble.
4. **More than 3 wobbles = PASS.** In normal data, about 99.7% of values fall within 3 sigma.
   Landing beyond that is very unlikely to be chance.

**A made-up example to make it concrete:** a feature averages 10 in baseline and wobbles by about 2.
Three wobbles = 6, so anything above 16 or below 4 counts as "too far to be chance". The attack
averages 25: z = (25 − 10) ÷ 2 = **7.5**, so it passes.

**The wormhole features it tests:**

| Feature | Plain meaning | Expected | Role |
|---|---|---|---|
| **TunnelIntensity** | tunnel messages per second | goes **up** (≈0 in baseline) | primary |
| **TunnelBytes** | tunnel data per second | goes **up** | primary |
| **TunnelLatency** | time gap between a probe's two copies | **appears** | primary |
| **LatencyHopRatio** | how fast probes arrive for their distance | goes **down** | secondary (supporting only) |

**Verdict rule:** **CONFIRMED** if at least one *primary* feature passes. **NOT CONFIRMED** if
none does. **INCONCLUSIVE** if there was no usable data to test.

**If a panelist sees "inf" in the output:** in baseline the tunnel is completely silent, so
TunnelIntensity is exactly 0 in every window and the wobble is **zero**. Any real increase is then
"infinitely many wobbles away", and the tool prints **inf**. That's a **pass by design**, not a bug.

**One technical detail, if asked:** the test runs on **5-second blocks**, not single 1-second
windows. With only ~1 probe per window, one-second numbers are too jumpy to measure a fair
"wobble". The dataset itself stays at 1-second windows; only the statistic uses blocks.

---

## What it has actually shown

- **Sep. 2026, linear topology, repeats r2 and r3:** **181 duplicated probes during the attack, 0 in
  baseline, 0 in cooldown, all from one board (Node B). The same 181 in both repeats.**
  181 ≈ 180 s × 1 probe per second, so practically every probe in the attack window was tunnelled,
  and none outside it.
- **Oct. 1, 2026, the first run after the firmware redesign:** exactly **180** duplicates from Node B,
  all labelled 2. Node A's counters went 0 → 180 only during the attack. (That run's *tree shape*
  failed, because every board joined the root directly. So it proves the tunnel works, but it is
  not counted as a dataset entry.)
- **Oct. 4, 2026:** the wizard's tunnel test **passed in both directions** on real boards.

---

## Likely follow-up questions

**"How do you know the duplicates aren't just normal mesh retransmissions?"**
Three reasons:
1. They appear **only** inside the 180 s attack window.
2. They come from **only one board**, Node B.
3. Their count matches the probe rate times the attack length (~180).

A network glitch would show up in baseline too, and on any board. In the clean runs, baseline had
**zero** duplicates. (Our July linear runs *did* have baseline duplicate noise from an unstable
mesh. The September r2 and r3 runs had none.)

**"Does your wormhole change the network topology, like a real one would?"**
**No, and we measured that.** There were 0 parent switches and 0 layer changes during the attack in
both r2 and r3. Here's why. A textbook wormhole tricks the routing protocol into thinking two far-apart
nodes are neighbours, so routes bend toward the tunnel. In ESP-WIFI-MESH, parents are chosen
**below** the application layer, by the mesh stack itself. Our tunnel runs at the application layer,
so the mesh never sees the shortcut and has no reason to re-route. That's why the paper calls it
**"Wormhole-*Inspired*" topology distortion** instead of claiming a textbook wormhole. It's also a
finding in itself: in ESP-WIFI-MESH, the **duplicate-delivery** fingerprint and the
**topology-change** fingerprint can be separated. Full argument: `ATTACK-VALIDATION.md` §2.1.

**"Is the tunnelled copy faster or slower?"**
It depends on what the tunnel is made of. Ours is a short wire, so we expect it to be faster, and
our validator expects **LatencyHopRatio to drop**. Zhukabayeva's tunnel ran over GSM (a mobile
network), which is slower, and they measured delay **going up**. Because the direction depends on
the hardware, we treat this as **supporting evidence only**. It never decides the verdict; the
tunnel features do.

**"What if the wire gets loose in the middle of a run?"**
Lost messages mean **fewer** duplicates, never fake ones, because the checksum throws away anything
damaged. A loose wire weakens the fingerprint but can't invent it. The soak test before the run
catches a flaky wire, and Node A's counters after the run show exactly how many messages got through.

**"Why a wire and not a second radio?"**
The Milestone 2 design specifies a wired UART link between A and B as the out-of-band channel. A
wire is completely separate from the Wi-Fi mesh being attacked, it doesn't add radio traffic to the
mesh's channel, and it behaves the same every run.

**"Has this been validated on every topology?"**
Not yet. The detailed conformance check is done on **linear** only. Star and partial-mesh wormhole
runs are captured but not yet analysed (`ATTACK-VALIDATION.md` §7). Say this plainly if asked.

---

## Sources (where each claim is proven)

| Claim | File |
|---|---|
| B always sends the normal copy and *also* tunnels one during the attack; CRC32 + magic; counter meanings | `child_node/main/wormhole_victim.c` (header comment, `tunnel_forwarder_task`, `uart_tunnel_rx_task`) |
| Node A's "TUNNEL CARRIED NOTHING" check | `wormhole_victim.c`, Node A post-flight (~line 447) |
| Phase lengths 60 / 300 / 180 / 120 s; UART pins + 115200 baud | `components/mesh_common/include/mesh_config.h` |
| Tunnel test: 50 ms numbered pings, lost/garbled, PASS/WARN/FAIL, Q/Enter stop | `uart_link_test/README.md`, `run_wizard.ps1` (`Invoke-UartTunnelTest`, `Read-UartLinkStats`) |
| 3-sigma test, wormhole features, verdict rule, "inf" when baseline wobble is 0, 5-window blocks | `tools/verify_attack.py` (header, `SIGNATURES`, sd = 0 branch, verdict block) |
| TunnelLatency = time gap between a probe's two copies | `analysis/features.py` (TunnelLatency docstring) |
| 181 duplicates, 0 topology change, linear r2/r3 | `docs/attack-validation/ATTACK-VALIDATION.md` §2 |
| 180 duplicates on the oct. 1 run | team `MEMORY.md`, oct. 1, 2026 entry |
| Latency direction (UART faster vs Zhukabayeva's GSM slower) | team `MEMORY.md`, sep. 30, 2026 entry |

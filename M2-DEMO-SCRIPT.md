# 🎬 M2 Demo Script — Application-Layer Attack Modules (15%)

> ## ⚠️ Criteria not yet supplied
> Unlike M1, **I don't have M2's criteria text.** Everything below is built from the milestone
> scope in `2026-07-24.md` and the evidence in your repo. **Paste M2's criteria and I'll map
> each one precisely** — the evidence won't change, only which bullet it answers.
>
> Working assumption: *both attacks implemented at the application layer, producing observable
> and distinguishable signatures at the root.*

> ## 🎯 The framing that wins this milestone
> **Each attack is measured twice — by the attacker's own counters, and independently by the
> root's arrivals log. Different boards. Different files. Agreeing numbers.**
>
> Say the words *"two independent measurements"* out loud. That's the phrase that separates
> "we ran an attack" from "we measured an attack."

---

## 📋 What M2 covers *(and what it doesn't)*

| In scope | Out of scope |
|---|---|
| `blackhole_victim.c` — relay that drops | Multi-topology deployment → **M3** |
| `wormhole_victim.c` — UART tunnel, Node A + Node B | Repeats / the 24-run matrix → **M4** |
| Attack signatures visible in telemetry | Detection rules or thresholds → not this thesis phase |

> 🗣️ *"M1 built the platform with no attack code. M2 adds the two attack modules. Deploying
> them across four topologies is M3, and replicating each three times is M4."*

---

# 🔴 PART 1 · Blackhole — the drop signature

## 📊 SLIDE 1 — Attacker counters, `blackhole · star · r1`

| phase | probes received | tx (forwarded) | retry (dropped) |
|---|---:|---:|---:|
| 0 · baseline | 1 → 1453 | 0 → 1452 | 0 → 1 |
| **1 · ATTACK** | 1455 → **2176** | **1453 → 1453** | 2 → **723** |
| 3 · cooldown | 2176 → 2657 | 1453 → 1934 | 723 → 723 |

> 🗣️ *"During the attack window the relay **received 721 probes and dropped 721**. Look at the
> forwarded column — **1453 to 1453**, flat to the digit, for the full three minutes. Then in
> cooldown it starts forwarding again and the counter resumes climbing."*

💡 **Point at the `tx` column.** A flat counter between two climbing ones is the whole story.

## 📊 SLIDE 2 — The independent confirmation

Same run, **different board, different file** — the root's arrivals log:

| phase | probes arriving at root |
|---|---:|
| 0 · baseline | 1436 |
| **1 · ATTACK** | **0** |
| 3 · cooldown | 483 |

> 🗣️ *"The attacker says it dropped 721. The root — a separate device writing a separate file —
> says **zero probes arrived** during that window. Two independent measurements of the same
> event, in exact agreement. In cooldown the attacker forwards 484 and the root logs 483; one
> was still in flight when the phase ended."*

## 🎥 CLIP CUE — the relay identifying itself *(~15 s)*
```
=== BLACKHOLE ATTACKER (relay) STARTING ===
This is the blackhole ATTACKER. Set BLACKHOLE_ATTACKER_MAC on the victim
boards to my STA MAC: b0:cb:d8:f3:32:18
```
And on any victim:
```
Blackhole victim mode: probes -> attacker b0:cb:d8:f3:32:18
```

> 🗣️ *"Victims are **compiled** to address their probes to the attacker's MAC. That's what makes
> this an application-layer attack — the relay sits in the probe path by addressing, not by
> manipulating mesh routing. It never changes the control plane."*

---

# 🔵 PART 2 · Wormhole — the duplicate signature

## 📊 SLIDE 3 — Both tunnel ends, `wormhole · star · r2`

| node | role | phase 0 | **phase 2 (attack)** | phase 3 |
|---|---|---|---|---|
| node5 | **Node A** (exit) | probes 0 → 0 | probes **0 → 180** | 180 → 180 |
| node6 | **Node B** (entry) | retry 0 → 0 | retry **0 → 180** | 180 → 180 |

> 🗣️ *"Node B is the tunnel entry — its counter climbs by exactly **180** during the attack
> window. Node A is the exit — it replays exactly **180**. Both are zero in baseline. The two
> ends of a physical wire, agreeing."*

## 📊 SLIDE 4 — What the root sees, and how often

| run | duplicate deliveries | multiplicity | source | dupes in baseline |
|---|---:|---:|---|---:|
| linear · r1 | 181 | ×2.00 | Node B | **0** |
| linear · r3 | 181 | ×2.00 | Node B | **0** |
| star · r1 | 180 | ×2.00 | Node B | **0** |
| star · r2 | 180 | ×2.00 | Node B | **0** |

> 🗣️ *"The root receives the identical `(src_mac, seq_num)` pair **twice** — once over the mesh,
> once replayed out of the tunnel. Detection here is **exact, not statistical**. Four runs, two
> different topologies, the same result. And **zero duplicates in baseline or cooldown in every
> single run** — so it isn't background retransmission."*

## 🎥 CLIP CUE — the two tunnel ends booting *(~10 s)*
```
=== WORMHOLE NODE A (exit) STARTING ===
=== WORMHOLE NODE B (entry) STARTING ===
```

---

# ⭐ PART 3 · The slide that shows you understand your own work

## 📊 SLIDE 5 — The two attacks are opposites

| | Blackhole | Wormhole |
|---|---|---|
| **Mechanism** | relay silently drops | out-of-band UART tunnel replays |
| **Effect on root traffic** | ⬇️ falls to **zero** | ⬆️ rises to **125 %** of baseline |
| **Signature** | absence | exact duplication |
| **Detection** | count arrivals | match `(src_mac, seq_num)` |

> 🗣️ *"These are opposite signatures, and that matters for the dataset: a detector tuned to
> 'traffic dropped' would completely miss the wormhole, because wormhole traffic goes **up**.
> Having both in one dataset is what makes it useful."*

> 💡 This slide is why a panel will believe you designed the dataset rather than just collected
> it. It also pre-empts *"why does your attack increase traffic?"* — the most common M2 question.

---

## 📄 OPTIONAL — the code
`child_node/main/blackhole_victim.c`, header comment. Four lines state the relay model:
forward during baseline and cooldown, drop during the attack phase, never touch mesh routing.

---

## 🗣️ The 90-second M2 script

> *"M2 adds the two attack modules to the platform M1 built.*
>
> *The blackhole is a relay. Victims are compiled to send probes to its MAC; it forwards them
> normally, then drops them during the attack window. \[slide 1] **721 received, 721 dropped,
> zero forwarded** — the forwarded counter is flat to the digit. \[slide 2] And independently,
> the root logged **zero arrivals** in that same window. Two boards, two files, exact agreement.*
>
> *The wormhole is the opposite. \[slide 3] Node B captures probes and ships them over a
> physical UART cable to Node A, which replays them — so the root receives the same packet
> twice and traffic goes **up**, not down. \[slide 4] **181, 181, 180, 180 duplicates across
> four runs and two topologies**, with zero duplicates in baseline every time.*
>
> *\[slide 5] Opposite signatures — one is absence, the other is duplication. That's what makes
> both worth having in one dataset."*

---

## 🛡️ M2 questions

**"Why does the wormhole increase traffic instead of decreasing it?"** ⭐ *most likely*
> *"Because the tunnel is out-of-band. Probes still take their normal mesh path **and** a copy
> arrives through the UART wire, so the root sees both. The blackhole removes traffic; the
> wormhole duplicates it."*

**"Could those duplicates just be retransmissions?"**
> *"No. A retransmission would appear in baseline too, and baseline has **exactly zero**
> duplicates in every run. They also all come from one source MAC — Node B, the tunnel entry.
> And both tunnel-end boards independently counted 180."*

**"How do you know the attacker dropped them rather than failing to send?"**
> *"Because `probes_count` kept climbing — it was still receiving. Received rose by 721,
> forwarded stayed flat, and the drop counter rose by exactly 721. A send failure would show
> received flat too, or an error path in the log."*

**"Is this a realistic attack?"**
> *"It's the application-layer form of both attacks. A real blackhole might also poison routing;
> ours drops at the application layer so the mesh control plane stays untouched and the effect is
> cleanly attributable. That's a deliberate scoping choice for a dataset — one variable at a
> time."*

**"Why is the wormhole a physical cable?"**
> *"It models the out-of-band link a wormhole requires. Because it's a wire, its behaviour
> doesn't depend on how far apart the two nodes end up in the mesh — which is why the signature
> reproduced identically on linear and star."*

**"Where's the attacker's own telemetry in the dataset?"**
> *"The attacker logs the same 11-column schema as every node — its `role` column reads
> `blackhole` or `wormhole_a`/`wormhole_b`. The relay-specific features like `ForwardingRatio`
> populate only on those rows, which is by design per Table 4.12."*

---

## ✅ M2 checklist

- [ ] Slides 1 + 2 side by side — the two independent measurements
- [ ] Slides 3 + 4 — tunnel ends and the four-run reproduction
- [ ] Slide 5 — the opposites table *(don't skip; it pre-empts the top question)*
- [ ] Clip cued to the blackhole attacker + victim banners
- [ ] Know cold: **721 / 721 / 0** · **181 · 181 · 180 · 180** · **0 dupes in baseline**
- [ ] Can explain **why wormhole traffic rises** without notes
- [ ] Ready to say *"M3 deploys these across topologies; M4 replicates them"* if asked about coverage

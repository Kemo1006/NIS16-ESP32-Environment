# 🎬 M2 Demo Script — Application-Layer Attack Module Implementation (15%)

> ## 📋 The four criteria *(quoted from your Milestones Form)*
> 1. **Blackhole:** root logs show the expected drop in arrivals during the attack window and
>    normal arrivals before and after.
> 2. **Wormhole:** root logs show duplicate probe arrivals **with measurable latency
>    difference** during the attack window.
> 3. Both attacks **toggle cleanly on phase transitions**; no leakage into baseline windows.
> 4. Behavior is **consistent across all four topologies**.

## 🎯 Verdict: 3 of 4 fully met · criterion 4 is at 3 of 4 topologies

| # | Criterion | Evidence | Status |
|:-:|---|---|:--:|
| 1 | Blackhole drop, normal before/after | root arrivals **1436 → 0 → 483** | ✅ |
| 2 | Duplicates **with latency difference** | 181 pairs, median **9.8 ms** mismatch | ✅ |
| 3 | Clean toggle, no baseline leakage | **0 duplicates** in baseline, every run | ✅ |
| 4 | Consistent across **all four** topologies | linear ✅ star ✅ partial ✅ · tree wormhole pending | ⚠️ **3/4** |

> 🗣️ **Open with the framing:** *"The ESP32 Wi-Fi stack is closed-source binary, so both attacks
> are emulated at the **application layer** using normal `esp_mesh_send` and `esp_mesh_recv` —
> no raw 802.11 frames are touched. That's a deliberate constraint, and it means the mesh
> control plane is never modified: the effect is cleanly attributable to the attack."*

---

# ✅ CRITERION 1 · Blackhole — drop during attack, normal before and after

## 📊 SLIDE 1 — What the root logged *(the criterion asks for root logs specifically)*

`blackhole · linear · r3` — root's `arrivals.csv`:

| phase | probes arriving at root | rate |
|---|---:|---|
| 0 · baseline | **1436** | 3.99 /s |
| **1 · ATTACK** | **0** | — |
| 3 · cooldown | **483** | 4.02 /s |

> 🗣️ *"The criterion asks for a drop during the attack window with normal arrivals either side.
> **1436 in baseline, zero during the attack, 483 in cooldown** — and the cooldown rate matches
> baseline at about four probes per second. That's the drop, and the recovery."*

## 📊 SLIDE 2 — The attacker's own counters agree

`blackhole · star · r1` — the attacker board:

| phase | probes received | tx (forwarded) | retry (dropped) |
|---|---:|---:|---:|
| 0 · baseline | 1 → 1453 | 0 → 1452 | 0 → 1 |
| **1 · ATTACK** | 1455 → **2176** | **1453 → 1453** | 2 → **723** |
| 3 · cooldown | 2176 → 2657 | 1453 → 1934 | 723 → 723 |

> 🗣️ *"**721 received, 721 dropped, zero forwarded.** The forwarded counter is flat to the digit
> for the full three minutes — that's the attacker silently not calling `esp_mesh_send`. Two
> independent measurements: the attacker's own counters and the root's arrivals log, on
> different boards writing different files."*

💡 Say the words **"two independent measurements."**

## 🎥 CLIP CUE — how victims are pointed at the attacker *(~15 s)*
```
=== BLACKHOLE ATTACKER (relay) STARTING ===
Set BLACKHOLE_ATTACKER_MAC on the victim boards to my STA MAC: b0:cb:d8:f3:32:18
```
```
Blackhole victim mode: probes -> attacker b0:cb:d8:f3:32:18
```
> 🗣️ *"Victims are **compiled** to address probes to the attacker's MAC — the behavioural
> equivalent of a false short-route advertisement, without touching routing."*

---

# ✅ CRITERION 2 · Wormhole — duplicates WITH measurable latency difference

> ⚠️ **The latency half of this criterion is easy to forget.** Duplicates alone don't satisfy
> it — the form asks for a *measurable latency mismatch*. You have one. Show it.

## 📊 SLIDE 3 — Duplicate arrivals

| run | duplicate pairs | multiplicity | source | dupes in baseline |
|---|---:|---:|---|---:|
| linear · r1 | 181 | ×2.00 | Node B | **0** |
| linear · r3 | 181 | ×2.00 | Node B | **0** |
| star · r1 | 180 | ×2.00 | Node B | **0** |
| star · r2 | 180 | ×2.00 | Node B | **0** |
| **partial · r1** | **180** | ×2.00 | Node B | **0** |

## 📊 SLIDE 4 — The latency mismatch ⭐ *criterion 2's second half*

Difference in `latency_us` between the **two copies of the same probe**:

| run | pairs | median mismatch | min | max |
|---|---:|---:|---:|---:|
| linear · r1 | 181 | **9.77 ms** | 1.14 ms | 1224 ms |
| linear · r3 | 181 | **8.84 ms** | 0.98 ms | 2187 ms |
| star · r2 | 180 | **12.51 ms** | 4.02 ms | 124 ms |

> 🗣️ *"Both copies are the same logical probe, so they share a send timestamp — which means the
> difference in recorded latency is **purely the difference in arrival time** between the
> multi-hop path and the wormhole shortcut. Median mismatch is **roughly 9 to 12
> milliseconds**, on every run. That's the measurable latency difference the criterion asks
> for.*
>
> *The maxima are outliers where a mesh copy was delayed by retries — which is itself the
> expected behaviour, since the tunnel is a wire and the mesh path is contended."*

## 🎥 CLIP CUE — the two tunnel ends *(~10 s)*
```
=== WORMHOLE NODE A (exit) STARTING ===
=== WORMHOLE NODE B (entry) STARTING ===
```

## 📊 SLIDE 5 — Both ends of the tunnel agree

`wormhole · star · r2`:

| node | role | phase 0 | **phase 2 (attack)** | phase 3 |
|---|---|---|---|---|
| node5 | **Node A** (exit, near root) | 0 → 0 | probes **0 → 180** | 180 → 180 |
| node6 | **Node B** (entry, near victims) | 0 → 0 | retry **0 → 180** | 180 → 180 |

> 🗣️ *"Node B captures probe metadata and ships it over the UART link — CRC-protected. Node A
> reconstructs a replica and re-injects it toward root through the legitimate mesh path. **B
> counted 180 in, A counted 180 out**, and the root then logged 180 duplicates. Three
> independent counts of the same event."*

---

# ✅ CRITERION 3 · Clean toggle, no leakage into baseline

## 📊 SLIDE 6 — The toggle is exact

| | baseline | attack window | cooldown |
|---|---:|---:|---:|
| **Blackhole** — forwarded | climbing | **flat (1453→1453)** | climbing again |
| **Blackhole** — root arrivals | 1436 | **0** | 483 |
| **Wormhole** — duplicates | **0** | **180–181** | **0** |

> 🗣️ *"No leakage in either direction. The blackhole forwards normally right up to the phase
> boundary and resumes immediately after. The wormhole produces **exactly zero** duplicates in
> baseline and cooldown across all four runs — so the duplication is attributable to the attack
> window alone, not to background retransmission."*

💡 This is the slide that makes the labels trustworthy: attack-phase rows really are attack, and
benign rows really are benign.

---

# ⚠️ CRITERION 4 · Consistent across all four topologies — **3 of 4**

## 📊 SLIDE 7 — Be direct about this

| Topology | Blackhole signature | Wormhole signature |
|---|:--:|:--:|
| ➖ Linear | ✅ 720/720/0, root 0 | ✅ 181 dupes |
| ⭐ Star | ✅ 721/721/0, root 1 leaked | ✅ 180 dupes |
| 🕸️ Partial | ✅ r1 | ✅ 180 dupes |
| 🌳 Tree | ✅ r1, 2 leaked | 🟡 exporting |

> 🗣️ *"All four topologies are deployed; three carry both attacks. The substantive point is that
> the signature reproduced **consistently** across structurally different meshes — the wormhole at
> 181 duplicates on linear, 180 on star and 180 on partial; the blackhole dropping to between
> zero and two probes out of about 710 expected. Only tree · wormhole is outstanding.*
>
> *One reason we expect consistency: the blackhole works by **addressing** — victims send to the
> attacker's MAC regardless of mesh position. And the wormhole tunnel is a **physical wire**, so
> its behaviour doesn't depend on how far apart the two nodes end up. Neither mechanism is
> topology-sensitive by construction."*

> 💡 That last paragraph is the strongest thing you can say here. It explains **why** the
> remaining cell is expected to match, without claiming it already does.

---

# ⭐ SLIDE 8 — The two attacks are opposites *(don't cut this)*

| | Blackhole | Wormhole |
|---|---|---|
| **Mechanism** | attacker stops calling `esp_mesh_send` | UART tunnel replays a replica probe |
| **Effect at root** | ⬇️ arrivals fall to **zero** | ⬆️ arrivals rise to **125 %** of baseline |
| **Signature** | absence | exact duplication + latency mismatch |
| **How you detect it** | count arrivals | match `(src_mac, seq_num)` |

> 🗣️ *"Opposite signatures. A detector tuned to 'traffic dropped' would completely miss the
> wormhole, because wormhole traffic goes **up**. Having both in one dataset is what makes it
> useful for detection research."*

---

## 🗣️ The 2-minute M2 script

> *"The ESP32 Wi-Fi stack is closed-source binary, so both attacks are emulated at the
> application layer with normal mesh send and receive calls — no raw 802.11 frames.*
>
> *\[slide 1] Blackhole: the root logged **1436 arrivals in baseline, zero during the attack,
> 483 in cooldown**. \[slide 2] And the attacker's own counters say 721 received, 721 dropped,
> zero forwarded — flat to the digit. Two independent measurements.*
>
> *\[slide 3] Wormhole: **181 duplicate probe arrivals**, reproduced at 181, 180 and 180 across
> four runs. \[slide 4] And the criterion asks for a measurable latency difference — the two
> copies of each probe arrive **about 9 to 12 milliseconds apart**, median, on every run.*
>
> *\[slide 5] Both tunnel ends agree independently: Node B counted 180 in, Node A 180 out.*
>
> *\[slide 6] Both attacks toggle cleanly — **zero duplicates in baseline and cooldown**, so
> there's no leakage into the benign windows.*
>
> *\[slide 7] Two of four topologies so far, with identical signatures on both. Tree and partial
> are pending runtime — and neither mechanism is topology-sensitive by construction, because the
> blackhole works by addressing and the wormhole runs over a wire."*

---

## 🛡️ M2 questions

**"Why does the wormhole increase traffic instead of decreasing it?"** ⭐ *most likely*
> *"Because the tunnel is out-of-band. The probe still takes its normal mesh path **and** a
> replica arrives through the UART shortcut, so the root sees both. Blackhole removes traffic;
> wormhole duplicates it."*

**"You only have two topologies — criterion 4 says four."** ⭐ *expect this*
> *"All four are deployed; three carry both attacks. The signature is consistent across them —
> 181 duplicates on linear, 180 on star, 180 on partial, and the blackhole dropping to between
> zero and two probes out of about 710. Neither mechanism is topology-sensitive by construction:
> the blackhole works by addressing, and the wormhole tunnel is a physical wire. Only tree ·
> wormhole is outstanding, and it's exporting now."*

**"Is 9 milliseconds really 'measurable'?"**
> *"It's measured directly in the data — both copies carry the same send timestamp, so the
> difference in recorded latency is purely the arrival-time gap. Median 9 to 12 milliseconds
> with a minimum around 1 millisecond, across 180-odd pairs per run. And it's consistently
> positive: the tunnel path and the mesh path never arrive together."*

**"Could those duplicates be retransmissions?"**
> *"No. Retransmissions would appear in baseline too, and baseline has **exactly zero**
> duplicates in every run. They all come from one source MAC — Node B, the tunnel entry — and
> both tunnel-end boards independently counted 180."*

**"How do you know the attacker dropped rather than failed to send?"**
> *"`probes_count` kept climbing — it was still receiving. Received rose by 721, forwarded
> stayed flat, drops rose by exactly 721. A send failure would show received flat too."*

**"Is CRC actually checked on the tunnel?"**
> *"Yes — metadata is CRC-protected over the UART link so a corrupted transfer is detected
> rather than replayed as a bad probe."*

**"Isn't application-layer emulation less realistic than a real routing attack?"**
> *"It's a deliberate constraint — the Wi-Fi stack is closed-source binary, so raw frame
> injection isn't available. The upside for a dataset is that the mesh control plane is never
> modified, so the observed effect is cleanly attributable to the attack rather than to routing
> side-effects."*

---

## ✅ M2 checklist

- [ ] Slides 1 + 2 — root log **and** attacker counters *(criterion 1)*
- [ ] Slides 3 + 4 — duplicates **and** latency mismatch *(criterion 2 — don't forget half 2)*
- [ ] Slide 6 — the clean-toggle table *(criterion 3)*
- [ ] Slide 7 — topology coverage, stated plainly *(criterion 4, the gap)*
- [ ] Slide 8 — the opposites table
- [ ] Clip cued: blackhole banner + victim line + both wormhole banners
- [ ] Know cold: **1436 → 0 → 483** · **721/721/0** · **181·181·180·180** · **~9–12 ms**
- [ ] Rehearse the criterion-4 answer — *"identical on both, and neither mechanism is
      topology-sensitive by construction"*

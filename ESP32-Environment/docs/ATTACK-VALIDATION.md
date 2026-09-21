# Attack validation — how we know these are a blackhole and a wormhole

**Created:** sep. 20, 2026 · **Answers:** CTTHES2 panel, 17:50–18:30 and 44:30–49:00

> *"Show how you validated the attacks; if the scripts are based on existing literature, please
> provide your basis. Even if created from scratch, do you have documentation or an online database
> that details the steps of these attacks to verify their accuracy?"*

This is the answer. Every ✅ and ❌ below is checked against the firmware source or measured from
captured data, with the command to reproduce it. **Nothing here is asserted from memory.**

---

## 0. The framing — what "validated" can mean

An attack is not a product you can diff against a reference implementation. Blackhole and wormhole
are defined by **adversary behaviour**, not by a protocol: that is why the canonical papers describe
them for AODV/RPL/LEACH and why those definitions transfer to ESP-WIFI-MESH at all.

So what we validate is **conformance to a published definition** — criterion by criterion, including
the criteria we *fail*. A criterion failed and declared is stronger evidence of rigour than one
quietly omitted.

**This is already the claim the paper makes.** §4.2.1.2 is titled *"Forwarding Suppression
(Blackhole)"* and §4.2.1.3 *"Topology Distortion (Wormhole-**Inspired**)"*, carried through Tables
4.6 and 4.7. The paper never claimed a textbook wormhole; it claimed topology distortion derived
from one. **Lead with that** — the claim to defend is already the narrow, defensible one.

---

## 1. Blackhole — conformance to Karlof & Wagner (2003)

| Criterion | Ours | Evidence |
|---|---|---|
| Adversary sits on the forwarding path | ✅ | Victims address the attacker, which relays to the root — `child_node/main/blackhole_victim.c`, relay task |
| Receives the packets (not radio jamming) | ✅ | The relay queue receives *before* the forward/drop decision — `attacker_recv_cb()` |
| Drops instead of forwarding | ✅ | `phase_listener_get_phase_id() == PHASE_ID_BLACKHOLE` → `s_probes_dropped++`, no send |
| Stays protocol-compliant at PHY/MAC — the node still looks alive | ✅ | It remains a mesh participant and keeps logging telemetry throughout; visible in its own CSV |
| Observable: PDR collapse while the node stays reachable | ✅ **measured** | Root arrivals **6.07/s baseline → 0/s attack → 6.01/s cooldown** (99% recovery). ForwardingRatio **1.002 ± 0.025 → 0.001** (z = −40.22); PDR **0.998 ± 0.025 → 0.000** (z = −39.38) |
| **Attracts traffic by falsely advertising a favourable route** | ❌ **NO — declare this** | Ours is a **placed relay, configured by MAC**. No routing decision is ever fooled. We reproduce the *forwarding-suppression* half of the attack and **not** the *route-advertisement* half — which is exactly why the paper calls it "Forwarding Suppression", consistent with §3.3.1.2 *Adaptation to ESP-WIFI-MESH Context* |

**Reproduce:**
```powershell
python tools\verify_attack.py analysis\blackhole\linear\G402\feature_table.csv --attack blackhole
python tools\validate_integrity.py tools\exports\blackhole\linear\G402
```

⚠️ **The one criterion we fail is the single most likely panel question.** The prepared answer is
above: the paper's own section title already scopes the claim to forwarding suppression.

---

## 2. Wormhole — conformance to Hu, Perrig & Johnson (2003, packet leashes)

| Criterion | Ours | Evidence |
|---|---|---|
| Two colluding endpoints | ✅ | Node A (exit) / Node B (entry) — `child_node/main/wormhole_victim.c`, `-DWORMHOLE_END=0/1` |
| An out-of-band channel outside the normal path | ✅ | Physical UART1 link between the two boards (`mesh_config.h`) |
| Packets captured at one end, replayed at the other | ✅ **measured** | **181 duplicated `(src_mac, seq_num)` arrivals in the attack phase, 0 in baseline, 0 in cooldown, on exactly one MAC** (`F4:2D:C9:73:E6:18` = Node B). **Identical 181 in both r2 and r3.** 181 ≈ `PHASE_ATTACK_S` 180 s × 1 probe/s |
| Attacker need not compromise keys or hosts | ✅ | Application-layer only; no key material touched |
| **Creates a false neighbour relationship / illusion of proximity** | ❌ **NO — measured, twice** | **0 parent switches and 0 layer changes during the wormhole phase in BOTH r2 and r3.** All topology churn (10 in r2, 7 in r3) occurs during baseline mesh formation |

**Reproduce:**
```powershell
# duplicate arrivals, per phase
python -c "..."   # see section 5; or:
python tools\validate_integrity.py archive\2026-09-16_pre-restart\exports\wormhole\linear
python tools\verify_topology.py --dir archive\2026-09-16_pre-restart\exports --topology linear --attack wormhole
```

### 2.1 What that ❌ actually means — and why it is a result, not a failure

ESP-WIFI-MESH's parent selection runs **below the application layer**. Our tunnel is an
application-layer replay path, so the mesh stack never observes it and has nothing to re-route
around. The tree therefore cannot deform — and it did not, in two independent runs.

Stated positively, and this belongs in the results chapter:

> **An application-layer replay tunnel reproduces the wormhole's duplicate-delivery signature
> without producing its topological signature. In ESP-WIFI-MESH, duplicate arrivals and topology
> distortion are separable effects, and only the first is reachable without touching the routing
> layer.**

That is a genuine, defensible finding about the protocol, and it **vindicates the paper's own
naming**: "Wormhole-**Inspired**" was the correct word all along.

### 2.2 Consequence for Chapter 3 — two pre-registered misses

**Table 3.5** predicts unexpectedly low hop counts, parent switches toward distant nodes, and a
"Layer 4 child of Layer 0". **None occurs.** Measured: zero parent switches, zero layer changes.

**Table 3.4** predicts increased retransmissions for victim nodes under blackhole. **None occurs** —
victims' `retry_count` changes by 0 across the attack window. §3.3.1.2 already explains why: the
attacker still ACKs every frame at the link layer, so the victims' radios never see a failure.

⚠️ **Report both as pre-registered misses. Do NOT edit the tables.** They were written at proposal
time, before any capture. A prediction tested and not observed is a finding; a table quietly edited
to match results is misconduct. This is the strongest possible demonstration that the analysis was
not fitted to the data.

---

## 3. The "online database" the panel asked for

| Source | What it gives | Use |
|---|---|---|
| **MITRE CAPEC** | Attack *patterns* with prerequisites, **execution flow**, consequences — protocol-agnostic by design | **Strongest answer.** Its execution-flow format maps directly onto the tables above. Interception / redirection / routing-manipulation; Adversary-in-the-Middle is the generic parent for wormhole |
| **MITRE EMB3D** | Threat model built for **embedded devices**, mapped to device properties | Strong fit for ESP32-class hardware, and reads as current |
| **MITRE ATT&CK** | Technique taxonomy with citable IDs | Partial fit — enterprise/ICS-oriented, **no clean WSN-routing wormhole entry.** Say plainly where it does not map |
| **NIST NVD / CVE** | Reported vulnerabilities | Search ESP32 / ESP-IDF / ESP-WIFI-MESH; a thin result is itself reportable |
| **Espressif ESP-WIFI-MESH docs** | What the protocol actually guarantees | **Non-optional** — it bounds what the attack may claim. You cannot subvert a guarantee never made |
| **RFC 3561 (AODV), RFC 6550 (RPL)** | The routing behaviour the classical attacks subvert | ESP-WIFI-MESH is neither; cite as the *origin* of the definitions, then point at §3.3.1.2 / §3.3.2.2 |

---

## 4. Literature basis — verify author/year/venue before citing

| Claim | Source |
|---|---|
| Blackhole definition + why attacker **position** matters | **Karlof & Wagner (2003)** — also the "target deployment" cite the panel asked for: damage scales with traffic aggregated at the attacker's position |
| Wormhole definition / packet leashes | **Hu, Perrig & Johnson (2003)** |
| 3-sigma normal-vs-attack detection method | **Zhukabayeva et al. (2025)**, *Technologies* 13(8):348 — the method `verify_attack.py` implements |
| Blackhole forwarding-ratio / PDR collapse signature | **Airehrour et al. (2018)** |
| ESP32 + ESP-MESH baseline PDR **> 97%**, loss < 1.8%; campus deployment | **Khan et al. (2022)**, *Sustainability* 14(24):16630 — our corrected baseline **0.998 ± 0.025 lands inside their range**, which is a validation result, not just a citation |

⚠️ Zhukabayeva's "4-storey office building / linear topology" detail came from a teammate's
full-text read and is **not confirmable from the abstract** — re-verify against the PDF before
publishing it.

---

## 5. Everything above, reproduced in three commands

```powershell
# 1. Blackhole: does the signature exceed 3 sigma against its own baseline?
python tools\verify_attack.py analysis\blackhole\linear\G402\feature_table.csv --attack blackhole

# 2. Wormhole: duplicate arrivals per phase, and parent/layer churn per phase
python tools\verify_topology.py --dir archive\2026-09-16_pre-restart\exports `
                                --topology linear --attack wormhole

# 3. Which runs are complete enough to support any of this
python tools\inventory_cells.py --plan
```

---

## 6. Independent corroboration via packet capture (once one exists)

Everything above comes from the boards' **own CSV logs** — a real, valid, and now paper-backed
form of evidence, but a board still reporting on itself. `docs/WIRESHARK-GUIDE.md` §9 maps each
claim in §1 and §2 above to a specific Wireshark filter that proves the same thing from a source
that doesn't depend on any board's telemetry being honest — e.g. the blackhole's PDR collapse
(§1, measured from CSVs) paired with an I/O Graph showing the attacker→root traffic physically
stop on the wire, or the wormhole's "0 parent switches" (§2, measured from CSVs) paired with zero
unencrypted association/reassociation frames during the same window. No pcap has been captured yet
(see `docs/WIRESHARK-GUIDE.md` §0) — this section exists so that once one is, the pairing is a
5-minute exercise instead of a redesign.

---

## 7. What this does NOT yet answer

- **Single-feature decidability (panel 2:40–4:50).** `analysis/leakage.py` removes the leaking
  features, but **PDR alone still scores 0.9987 against a 0.7031 majority baseline.** A 100% drop
  rate inside a fixed 180 s window is separable by construction. The fix is **scenario variation**,
  not feature selection — once `highload` benign data exists, congestion loss puts benign windows
  into the same PDR range as attack windows and the single-feature score must fall. `leakage.py` is
  the instrument that will measure whether it did.
- **Wormhole conformance is established on `linear` only** (r2, r3). Star and partial_mesh captures
  exist and are unanalysed.
- **Blackhole attacker position** is not yet topological — it sat at layer 7 of an 8-node chain with
  5 of 6 victims upstream. F2 makes moving it cheap; C7 Option 1 would make position meaningful.

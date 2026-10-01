---
name: star-hub-forcing-2026-10
description: Star+blackhole pins victims to the attacker (D-16) - why that "forcing" is defensible, what to tell the panel, and what each OTHER topology does/doesn't force
metadata:
  type: project
---

**Decision (Angelo, sep. 30 - oct. 1, 2026):** in star + blackhole builds the attacker is the
hub: root -> attacker -> every victim. Victims are firmware-pinned to the attacker's AP
(`mesh_setup.c` `STAR_HUB_BLACKHOLE`, thesis-deviate D-16, commit b80a663). Placement does
NOT decide the shape; it only decides link quality (attacker ~1 m from root, victims 3-5 m
around the attacker with a clear line - no minimum-RSSI check in the code, so a weak victim
link still pins and shows up as BASELINE loss). Not hardware-tested yet.

**Yes it is "forced" - why that is OK (panel answer):**
1. Every layout is already controlled (§4.2.2: "controlled experimental environments");
   the pin is one more control of the same kind.
2. The thesis itself specifies the outcome: Fig. 4.17 has victims "connecting directly to
   [the attacker] as their parent". We implement that, with the attacker one hop off the root
   (the root cannot be the attacker - it is the destination + referee, see D-16).
3. It models the state AFTER route attraction, not the attraction. Same abstraction the old
   design used (victims compiled to address the attacker's MAC) - which the signed Milestone
   Form calls the "behavioral equivalent of a false short-route advertisement".
4. Cleaner measurement: the tree is identical in baseline, attack and cooldown, so the only
   phase difference is the dropping.
Paste-ready framing (for D-16 / §4.2.2.1): *"Victims are bound to the attacker as their
parent, modelling the state after a successful route-attraction phase; the attraction
mechanism itself is outside the study's scope, as in the earlier MAC-addressed design."*
(Not yet added to D-16 or the paper - user only asked for this note.)

**Panel push-backs + honest answers:**
- "The attacker never had to win the victims?" - Correct: route attraction is out of scope.
- "Does the pin stop victims escaping the blackhole?" - Probably makes no difference: ESP-MESH
  picks parents by link/RSSI, not by delivery, and the attacker keeps its link up while
  dropping. NOT measured - say "the mesh stack has no delivery-based parent switching",
  not "we showed it".
- Side effect: in star runs ParentSwitchRate / HopStability are flat BY CONSTRUCTION - never
  present them as evidence in star.

**What each topology forces (from `mesh_setup.c`, oct. 1 2026):**
| topology | what the firmware forces | what placement/RSSI decides |
|---|---|---|
| star (baseline, wormhole) | max layer 2 = everyone a direct child of the root | link quality only |
| **star + blackhole** | max layer 3 + **victims pinned to the attacker** = the ONLY build that chooses a node's parent | link quality only |
| linear | `MESH_TOPO_CHAIN` + 1 child per node = must be a chain | the ORDER of the chain, so where the attacker sits |
| partial_mesh | max 2 children per node (`MESH_PARTIAL_MAX_CHILDREN`) = forces branching | which parent each node takes, re-parenting |
| tree | nothing (native ESP-MESH self-organising, max layer 25) | everything |
So linear/partial force a SHAPE, never a specific parent. Outside star+blackhole the
attacker's position (and so who is a victim vs "not in path") comes from placement - that is
why `exposure.py` derives victims from the logged tree instead of the build role.

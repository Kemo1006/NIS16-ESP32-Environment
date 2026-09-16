# Runbook: TOPOLOGIES - where to physically place boards - v2026-09-14

> The topology option (menu / `-Topology`) sets a firmware shaping flag, but **physical placement
> matters most** - the mesh self-organizes from RSSI. Space boards so the links you want are the
> strongest. Verify every run with `python tools\verify_topology.py`. Hub: `docs/2026-09-14_START-HERE.md`.
>
> **Rule that never changes:** flash EVERY board in a run with the SAME topology + attack.
> Spacing guide: **~3-5 m between adjacent boards** in the lab (from the thesis setup). Legend:
> `(R)`=root, `(v)`=victim, `(A)`=attacker/Node A, `(B)`=Node B, `~`=Wi-Fi link, `===`=UART cable.

Build flags (menu sets these): star=depth-capped 2, tree=default self-organising, linear=forced
chain, partial=physical placement. Days map: **Mon=Tree, Wed=Linear, Thu=Partial, Fri=Star.**

---

## TREE (default, hierarchical)
Root on top, intermediate nodes relay, leaves at the bottom - the native ESP-WIFI-MESH shape.
```
            (R)
           /   \
        (v)     (v)         <- layer 1 (intermediates)
        / \       \
     (v)  (v)     (v)       <- layer 2+ (leaves)
```
- **Placement:** put the root high/central; spread intermediates ~3-5 m out; leaves another 3-5 m
  past their intermediate so a leaf's strongest link is to its intended parent, not the root.
- **Blackhole:** make the **attacker an intermediate** that leaves must route through (Layer 2
  parent for several victims). Victims still address probes to the attacker MAC.
- **Wormhole:** **Node A at Layer 1 near the root**, **Node B at Layer 3 near the leaves**, so the
  legit path between them is several hops - the tunnel's shortcut is dramatic. UART cable A===B.
- **Vary per repeat:** move the attacker to a different branch / layer each of r1, r2, r3.

## STAR (single-hop hub)
Every node is a direct child of the root (depth capped at 2). Simplest routing.
```
        (v)   (v)   (v)
           \   |   /
            \  |  /
             (R)
            /  |  \
        (v)   (v)   (v)
```
- **Placement:** root in the middle; all others in a ring ~3-5 m around it, each with a clear line
  to the root and weaker links to each other, so everyone parents directly off the root.
- **Blackhole:** place the **attacker centrally** (a strong-signal ring node) so victims prefer it;
  they address probes to its MAC and it drops during the attack.
- **Wormhole:** **Node A adjacent to the root**, **Node B at the far side of the ring** (the
  farthest victim group). The UART cable spans the star diameter - use a longer cable, or accept A
  and B a few meters apart. Root logs the fast tunnel copy vs the slow hub copy.
- **Vary per repeat:** rotate which ring position the attacker occupies.

## LINEAR (forced chain)
Nodes in a straight line; each mainly reaches its neighbor -> long multi-hop path.
```
   (R) ~ (v) ~ (v) ~ (A) ~ (v) ~ (v)        (blackhole: attacker mid-chain)
```
- **Placement:** a straight line (hallway/corridor is ideal), ~3-5 m apart so the strongest RSSI is
  always between *adjacent* devices - that's what forces the chain. Keep non-adjacent boards out of
  strong range of each other.
- **Blackhole:** put the **attacker as a middle link** so ALL traffic between the root end and the
  far end passes through it. Dropping there **partitions** the chain - nodes beyond it go silent.
- **Wormhole:** **Node A at the root end**, **Node B at the far end**; the UART cable runs the
  length of the chain (a long cable, or route it directly A===B). The tunnel collapses a many-hop
  path to ~1, so the latency mismatch is large.
```
   (R) ~ (A) ~ (v) ~ (v) ~ (B) ~ (v)
          \___________________/  === UART tunnel (out-of-band) ===
```
- **Vary per repeat:** shift the attacker one position up/down the chain.

## PARTIAL MESH (most realistic)
Some nodes have several possible parents; the protocol picks by RSSI. Redundant paths.
```
        (R)
       /   \
     (v)===(A)         (A) = high-betweenness relay: preferred parent for several victims
      | \  / |
     (v) (v) (v)
```
- **Placement:** a loose 2D cluster where several nodes can "see" two-plus potential parents. Don't
  line them up; stagger them so parent choice is genuinely ambiguous.
- **Blackhole:** place the **attacker as a high-betweenness node** (central, strong signal) that
  becomes the preferred parent for multiple victims - dropping there also triggers parent-switching
  (topology instability), which is extra signal.
- **Wormhole:** **Node A near the root region**, **Node B near a victim cluster** on the far side;
  multiple legit paths exist, so the tunnel's shortcut competes with them. UART cable A===B.
- **Vary per repeat:** move the attacker to a different high-connectivity spot.

---

## After placement - verify the shape (every run)
```powershell
python tools\verify_topology.py
```
It reads the root log's parent-MAC + layer values and confirms the structure matches the topology
you intended. If a linear run shows everyone parented directly off the root, your spacing was too
tight - spread the boards out and re-run. Also confirm stability: no constant re-parenting during
the baseline phase.

## Placement is also your VARIANCE (panel rule)
Moving the attacker (and shifting node spacing / your own position) between r1, r2, r3 is exactly
the controlled variance the panel asked for. **Write the attacker's position on the field log for
every run** so the variation is documented, not accidental.

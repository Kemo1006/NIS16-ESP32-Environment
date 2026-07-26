# 🎬 M3 Demo Script — Multi-Topology Deployment (15%)

> ## 📋 Criteria *(these two are quoted — from `thesis-deviate.md` D-4)*
> 1. *"Each topology converges to its intended parent-child structure **within 60 seconds**"*
> 2. *"Mesh remains stable through a full 5-minute baseline phase (**no spontaneous
>    re-routing**)"*
>
> ⚠️ If M3's form lists further criteria — e.g. a required number of topologies — **paste them
> and I'll extend this.** The evidence below covers these two plus deployment coverage.

> ## ⚠️ This is the milestone with a real failure in it
> One recorded run reports `Converged: NO`. **Do not hide it, do not lead with it.** The
> prepared answer is in Part 3 — rehearse it out loud. It's the single most likely hard
> question in your whole defence.

---

# 🟢 PART 1 · The evidence that passes

## 📊 SLIDE 1 — Topology is verified from the data, not asserted ⭐ *your best artifact*

```
NODE_2805A532D7B4  (layer 1, role root)
    NODE_704BCA25B768  (layer 2, victim)
    NODE_B0CBD8F33218  (layer 2, wormhole_a)
    NODE_B4BFE932FE90  (layer 2, victim)
    NODE_B4BFE934ED80  (layer 2, victim)
    NODE_F42DC973E618  (layer 2, wormhole_b)

PASS star: all 5 nodes at layer 2 (direct children of root).
Converged within 60s     : YES
Baseline re-routing free : YES
```

> 🗣️ *"This is **not** our intended diagram. `verify_topology.py` reads each node's own
> `parent_mac` and `layer` columns out of the telemetry and **rebuilds the tree that actually
> formed**, then checks it against the expected shape. It's an independent measurement of the
> physical deployment — if a board had ended up two hops out, this would say so."*

## 📊 SLIDE 2 — Two structurally opposite topologies, both passing

| Run | Reconstructed shape | Converged <60 s | No baseline re-routing |
|---|---|:--:|:--:|
| `linear · blackhole · r3` | one node per layer, **depth 6** | ✅ YES | ✅ YES |
| `star · wormhole · r2` | all 5 at **layer 2** | ✅ YES | ✅ YES |

> 🗣️ *"A six-deep chain and a flat five-spoke star — structurally opposite — both converging
> inside sixty seconds with no re-routing during the baseline phase."*

## 📊 SLIDE 3 — How the shape is enforced

| Topology | Build flag | Constraint applied in `mesh_setup.c` |
|---|---|---|
| star | `MESH_TOPOLOGY=0` | `max_layer = 2` |
| tree | `MESH_TOPOLOGY=1` | native multi-hop (default) |
| linear | `MESH_TOPOLOGY=2` | `MESH_TOPO_CHAIN` + `max_children = 1` |
| partial | `MESH_TOPOLOGY=3` | narrowed `max_children` |

Live boot-log line:
```
I (780) MESH_SETUP: Topology shaping: STAR (max_layer=2, max_children=10)
```

> 🗣️ *"Topology isn't a label in a filename — it's a **compile-time constraint the mesh stack
> enforces**. For star, `max_layer` is capped at 2, so a board physically cannot become a
> grandchild; the stack refuses the association. So we have two independent things: the flag
> that constrains it, and the reconstruction that measures what happened."*

## 📊 SLIDE 4 — Deployment coverage

| Topology | Baseline | Blackhole | Wormhole |
|---|:--:|:--:|:--:|
| 🌳 Tree | ✅ | 🔴 pending | 🔴 pending |
| ➖ Linear | ✅ | ✅ | ✅ |
| ⭐ Star | ✅ | ✅ | ✅ |
| 🕸️ Partial | ✅ | 🔴 pending | 🔴 pending |

> 🗣️ *"Two of four topologies are deployed with both attacks. Tree and partial are pending —
> that's M4 runtime, not a method gap."*

> 📌 **Refresh before presenting:** `python slides\refresh_slide_numbers.py`

---

# 🟡 PART 2 · What "converged" actually means

Worth 20 seconds, because it pre-empts a technical challenge.

> 🗣️ *"'Converged' is the timestamp of the **last** parent or layer change in a node's log.
> Changes inside the first 60 seconds are counted as **formation**, not re-routing — the
> criterion has two separate statements, and the tool was originally conflating them. A node's
> initial parent acquisition was being counted as a baseline re-route, which is wrong: it hasn't
> got a parent yet. That's documented as deviation **D-4**, and `--stabilise-s 0` restores the
> old behaviour for audit."*

---

# 🔴 PART 3 · The run that fails — prepare this

**`star · blackhole · r1`** reports:
```
Converged within 60s     : NO
Baseline re-routing free : NO
```

### Do not volunteer it. If asked, answer in this order:

> 🗣️ **1. State it plainly.**
> *"One star run doesn't meet it. Nodes dropped and re-attached during baseline, settling
> around 100 seconds."*
>
> **2. Give the counter-example.**
> *"The next star run, same placement, converged inside sixty seconds with no re-routing — so
> it isn't a fixed property of star."*
>
> **3. Admit the unknown.**
> *"We haven't established the cause. We moved the boards closer to the root and join times
> dropped to under seven seconds, but the mechanism changed rather than disappearing — from
> failing to find the root, to dropping and re-attaching. The clean test is a `baseline · star`
> run, which we haven't done."*
>
> **4. Bound the impact.**
> *"Every disturbance is in phase 0. **Zero during the attack window** — which is why that run's
> attack signature is clean and validated."*

> 💡 **Why this works:** states the failure, gives the counter-example, admits the unknown,
> bounds the impact. Four moves, twenty seconds, nothing hidden. *"I don't know yet, and here's
> the experiment that would settle it"* is a stronger answer than a confident guess that
> unravels on the follow-up.

---

## 🗣️ The 90-second M3 script

> *"M3 deploys the M2 attack modules across multiple topologies.*
>
> *\[slide 3] Topology is a compile-time constraint, not a configuration file — for star the
> mesh stack caps depth at two, so a board can't become a grandchild.*
>
> *\[slide 1] And we verify it from the data. `verify_topology.py` rebuilds the tree from each
> node's own parent and layer columns — this is the structure that actually formed, not the one
> we intended.*
>
> *\[slide 2] Two structurally opposite topologies, a six-deep chain and a flat star, both
> converging inside sixty seconds with no baseline re-routing.*
>
> *\[slide 4] Two of four topologies carry both attacks; tree and partial are pending runtime."*

---

## 🛡️ M3 questions

**"How do you know it's really a star?"** ⭐
> *"Two independent things. The build flag caps `max_layer` at 2, so the stack refuses a deeper
> association. And `verify_topology.py` reconstructs the actual tree from telemetry. One is
> intent, the other is measurement."*

**"What counts as converged?"**
> *(See Part 2 — the formation-window explanation.)*

**"Only two topologies have attack data."**
> *"Correct. Linear and star are complete for both attacks; tree and partial are pending. The
> deployment method is identical — it's the same firmware with a different build flag — so
> what remains is runtime."*

**"Do the boards end up in the same positions each run?"**
> *"The topology class does; the specific parent assignment doesn't. Parents are chosen by
> signal strength at boot, which is the mesh behaviour under study — pinning it would mean
> overriding the thing we're measuring. Recorded as deviation **D-6**. Across linear wormhole
> r1 to r3 the two tunnel ends were adjacent, then two hops apart, then three — and the attack
> signature held at 181, 181, 180 regardless, because the tunnel is a wire."*

**"Why does star behave differently from linear?"**
> *"Different physical demand. Linear only needs each board to hear its neighbour. Star needs
> **every** board to hear the root directly, because the depth cap forbids attaching to a
> sibling. On our floor plan that's a much harder radio requirement, and it's why star was the
> topology that exposed the convergence issue."*

---

## ✅ M3 checklist

- [ ] `verify_topology.py` screenshots — **linear r3** and **star wormhole r2** (both YES/YES)
- [ ] Coverage table refreshed
- [ ] Boot-log line showing `Topology shaping:`
- [ ] Know the four build flags and what each constrains
- [ ] ⚠️ **Star-blackhole-r1 answer rehearsed out loud** — 4 moves, in order
- [ ] Can explain the **formation window** (D-4) in one sentence

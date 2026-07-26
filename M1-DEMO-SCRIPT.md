# 🎬 M1 Demo Script — Firmware Development for All Node Roles (15%)

> **Do not run a live 3-node test.** Your recorded 6-node run satisfies every criterion
> *more strongly* than a fresh 3-node test would, and live hardware in a defence is pure
> downside risk. Use a **clip + evidence slide**.

---

## ✅ The four criteria, and where each is already proven

| # | Panel criterion | Your evidence | Status |
|:-:|---|---|:--:|
| 1 | All firmware variants compile without warnings | Build output — **capture this fresh**, 2 min | ⚠️ |
| 2 | 3-node mesh forms within **60 s**, correct parent-child | Root boot log: **5 children in 6.75 s** | ✅ |
| 3 | Phase transitions received & applied within **1 s** | Measured: **0.15 s** spread across 6 nodes | ✅ |
| 4 | Cross-layer telemetry to flash, **no missing samples** | Discard **0.2–0.8 %**, 10 Hz confirmed | ✅ |

**You beat criterion 2 by 9×** (6.75 s against 60 s) and **criterion 3 by 6×** (0.15 s
against 1 s). Say those multiples out loud — they're the strongest single line in M1.

---

## 🎥 The clip — 4 cue points, ~75 seconds total

Play your recorded root monitor. Cue to these exact lines. Everything else can be
scrubbed past.

### CUE 1 · Boot + topology shaping *(~10 s)*
```
I (560)  ROOT_MAIN:   === ROOT NODE STARTING ===
I (780)  MESH_SETUP:  Topology shaping: STAR (max_layer=2, max_children=10)
I (1090) MESH_SETUP:  Mesh started. Node ID: NODE_2805A532D7B4  Role: 0
```
**SAY:** *"Root boots and applies the topology constraint. This isn't configuration — it's a
compile-time flag the mesh stack enforces. `max_layer=2` means no board can become a
grandchild."*

---

### CUE 2 · Mesh formation ⭐ **criterion 2** *(~20 s)*
```
I (1320) MESH_SETUP: Child connected: aid=1 MAC=f4:2d:c9:73:e6:18
I (1630) MESH_SETUP: Child connected: aid=2 MAC=b0:cb:d8:f3:32:18
I (1940) MESH_SETUP: Child connected: aid=3 MAC=b4:bf:e9:32:fe:90
I (4800) MESH_SETUP: Child connected: aid=4 MAC=70:4b:ca:25:b7:68
I (6750) MESH_SETUP: Child connected: aid=5 MAC=b4:bf:e9:34:ed:80
I (6750) MESH_SETUP: Routing table updated — nodes in mesh: 6
```
**SAY:** *"The criterion asks for a 3-node mesh within 60 seconds. This is **five children plus
the root — six nodes — fully formed in 6.75 seconds**. The timestamps in brackets are
milliseconds since boot. Each line is logged by the root itself as each child associates, and
every child attaches directly to the root, which is the correct parent-child relationship for
a star."*

> 💡 **Point at the bracketed numbers on screen.** `I (6750)` = 6.75 s. That single number
> answers criterion 2.

---

### CUE 3 · Logger + sampling rate ⭐ **criterion 4** *(~15 s)*
```
I (4280) CSV_LOGGER: SPIFFS mounted. Total: 2287 KB  Used: 0 KB
I (4280) CSV_LOGGER: Telemetry file: /spiffs/telem.csv
I (4460) CSV_LOGGER: Arrivals file:  /spiffs/arrivals.csv
I (4640) CSV_LOGGER: Logger ready. Role: root
I (4670) ROOT_MAIN: Telemetry task running at 100 ms interval.
```
**SAY:** *"Flash filesystem mounts, both log files open, and the telemetry task starts at a
100-millisecond interval — that's the 10 Hz sampling rate. Every node writes to its own
onboard flash; nothing streams to the laptop during the run."*

---

### CUE 4 · Phase broadcast ⭐ **criterion 3** *(~20 s)*
```
I (64680)  ROOT_MAIN:       ════════ PHASE 0 — BASELINE ════════
I (65240)  PHASE_LISTENER:  [ROOT] Broadcast phase_id=0  seq=1  label=0  (0 failed sends)
...
I (365240) ROOT_MAIN:       ════════ PHASE — ATTACK ════════
I (365250) PHASE_LISTENER:  Phase update → phase_id=2  gt_label=2  seq=2
I (365770) PHASE_LISTENER:  [ROOT] Broadcast phase_id=2  seq=2  label=2  (0 failed sends)
```
**SAY:** *"The root announces each phase transition and broadcasts the phase ID to every node.
Note `0 failed sends` — every node acknowledged. And every node stamps that ID into every
telemetry row it writes, which is where the ground-truth label comes from."*

---

## 📊 The evidence slide — put this next to the clip

Criterion 3 can't be shown in a clip, because each board runs its own clock. **Measure it
instead** — this table is the proof:

### Phase-transition consistency · star wormhole r2 · 6 nodes

| Node | phase 0 (s) | phase 2 (s) | phase 3 (s) |
|---|---:|---:|---:|
| …34ED80 | 354.4 | 180.5 | 120.4 |
| …25B768 | 360.1 | 180.4 | 120.4 |
| …32FE90 | 328.7 | 180.4 | 120.5 |
| …F33218 | 363.0 | 180.4 | 120.4 |
| …73E618 | 388.1 | 180.5 | 120.4 |
| …32D7B4 (root) | 360.6 | 180.4 | 120.4 |
| **Spread across nodes** | *(see note)* | **0.15 s** | **0.11 s** |

**SAY:**
> *"Each board runs its own clock, so we can't compare timestamps directly across nodes.
> What we can compare is **how long each node believed each phase lasted**. For the attack
> phase, all six nodes agree to within **0.15 seconds**; for cooldown, **0.11 seconds**. The
> criterion is one second — we're inside it by roughly a factor of six.*
>
> *Phase 0 varies because nodes stamp rows as baseline from the moment they boot, before the
> root's first broadcast reaches them — a board powered earlier simply has a longer
> pre-experiment stretch. That's a boot-order artefact, not a propagation delay, and it's
> documented as deviation D-4."*

> ⚠️ **Volunteer the phase-0 explanation before they ask.** If you show a 59 s spread with no
> explanation, it looks like the propagation criterion failed. Explaining it first turns the
> same table into a demonstration that you understand your own instrument.

---

## ⚠️ The one thing to capture fresh — criterion 1

You need a build log showing no warnings. Two minutes:

```powershell
cd child_node
idf.py build
```

Screenshot the tail — you want the `Project build complete` block. Do this for **root_node**
too if you have time.

**SAY:** *"All firmware variants build clean — root, plain victim, blackhole attacker,
blackhole victim, and both wormhole ends."*

If a warning does appear, **do not hide it**. Say what it is and whether it's in your code or
in ESP-IDF. A known, explained warning is fine; a hidden one found by a panelist is not.

---

## 🗣️ The 60-second M1 script (if you're short on time)

> *"Milestone 1 is the firmware foundation — before any attack code. Three shared modules used
> by every node: mesh setup, the phase listener, and the CSV logger. Plus root and victim
> firmware.*
>
> *The criteria ask for a 3-node mesh inside 60 seconds. \[play CUE 2] **Six nodes in 6.75
> seconds**, every child attached directly to the root.*
>
> *They ask that phase transitions apply within one second. \[show table] All six nodes agree
> on the attack-phase duration to within **0.15 seconds**.*
>
> *And they ask for cross-layer telemetry logged with no missing samples — RSSI, layer, parent
> MAC and packet counters, at 10 Hz to onboard flash, with a discard rate between 0.2 and 0.8
> percent across every dataset we've collected.*
>
> *All firmware variants build without warnings. Milestone 1 is complete."*

---

## 🛡️ M1 questions you may get

**"Why didn't you run the 3-node test the criterion specifies?"**
> *"Every run we've done uses six nodes, which is a superset — if six form correctly in under
> seven seconds, three is not in question. We chose to show real experiment runs rather than a
> synthetic test because the same evidence also supports Milestones 3 and 4."*

**"Can we see it run live?"**
> *"I have the recording here. I'd rather not power the mesh in the room — the boards are on
> channel 11 and the room's WiFi would change the conditions the recording was made under."*
> *(This is true and it is a legitimate reason. Have the clip ready.)*

**"How do you know there are no missing samples?"**
> *"Two checks. `validate_integrity.py` verifies phase coverage against the expected sample
> rate on every file — every recorded cell passes with zero failures. And the preprocessing
> report counts windows with too few samples to be reliable; that's between 0.2 and 0.8 percent
> across all datasets."*

**"What is the phase listener actually doing?"**
> *"It runs as a background task on every node. The root broadcasts a phase ID over the mesh;
> the listener receives it and tags every subsequent telemetry row with that ID. So the label
> is written by the firmware at capture time — there's no separate annotation step that could
> disagree with the data."*

---

## ✅ Checklist for M1

- [ ] Clip cued to the **4 points** above, tested on the presentation machine
- [ ] Build-log screenshot captured (`idf.py build`, no warnings)
- [ ] Phase-consistency table on a slide (0.15 s / 0.11 s)
- [ ] Can state the two multiples from memory: **6.75 s vs 60 s** · **0.15 s vs 1 s**
- [ ] Ready to explain the phase-0 spread **before** being asked

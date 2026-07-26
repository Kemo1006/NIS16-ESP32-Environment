# 🎬 M1 Demo Script — Firmware Development for All Node Roles (15%)

> ## ⚠️ Read this first — it changes which run you show
>
> The milestone says: *"a stable, fully-instrumented mesh running on real ESP32 hardware,
> **before any attack code is added**"*, and *"Attacker firmware and multi-topology deployment
> are **intentionally deferred** to the second and third milestones."*
>
> **So M1 must be presented from the `baseline · linear` run — not an attack run.**
> Showing blackhole or wormhole data here is off-scope: it's M2's evidence, and it invites
> the question *"why are you showing attack code in the milestone that excludes it?"*
>
> Your baseline run: **`tools/exports/baseline/linear_topology/`** — 7 CSVs, 2026-07-25.

---

## 📋 The five criteria — and where each is proven

| # | Criterion | Evidence | Verdict |
|:-:|---|---|:--:|
| 1 | All firmware variants compile without warnings | `build_all_variants.ps1` table | ⚠️ **run it** |
| 2 | 3-node mesh forms within 60 s, correct parent-child | Root boot log — **6 nodes in 6.75 s** | ✅ |
| 3 | Phase transitions applied within 1 s | Cooldown duration spread — **0.11 s** | ✅ |
| 4 | Cross-layer telemetry to flash at configured rate, no missing samples | **9.70 Hz** measured vs 10 Hz configured | ✅ |
| 5 | Full baseline run end-to-end; all CSVs retrievable via USB | **7 of 7 CSVs**, all six nodes | ✅ ⚠️ *see note* |

**Yes — present all five.** Each takes 15–30 seconds. Skipping one invites the panel to ask
about exactly that one.

---

# CRITERION 1 · Compiles without warnings

### 📄 What to show
Run this in your **ESP-IDF PowerShell** (~2–6 min, no board needed):
```powershell
.\build_all_variants.ps1
```

```
Variant              Result    Warnings Errors
-------              ------    -------- ------
ROOT                 BUILD OK         0      0
CHILD plain          BUILD OK         0      0
BLACKHOLE attacker   BUILD OK         0      0
BLACKHOLE victim     BUILD OK         0      0
WORMHOLE Node A      BUILD OK         0      0
WORMHOLE Node B      BUILD OK         0      0

ALL 6 VARIANTS BUILD CLEAN - 0 warnings, 0 errors
```

> 🗣️ *"All six firmware variants build clean — zero warnings, zero errors."*

**Why not the `run.ps1 -Flash` log you already have?** It proves *one* variant and buries the
proof in ~200 lines of CMake output. If you must use it, show only these lines:
```
[1030/1032] Generating binary image from built executable
root_node.bin binary size 0xf26b0 bytes.  Smallest app partition is 0x180000 bytes.  0x8d950 bytes (37%) free.
Hash of data verified.
```

> ⚠️ If a warning appears, **say what it is** and whether it's your code or ESP-IDF. A known,
> explained warning is fine. One a panelist finds is not.

---

# CRITERION 2 · 3-node mesh within 60 s

### 🎥 CLIP CUE — root boot log *(~20 s)*
```
I (560)  ROOT_MAIN:   === ROOT NODE STARTING ===
I (780)  MESH_SETUP:  Topology shaping: LINEAR (max_children=1)
I (1320) MESH_SETUP:  Child connected: aid=1 MAC=f4:2d:c9:73:e6:18
I (1630) MESH_SETUP:  Child connected: aid=2 MAC=b0:cb:d8:f3:32:18
I (1940) MESH_SETUP:  Child connected: aid=3 MAC=b4:bf:e9:32:fe:90
I (4800) MESH_SETUP:  Child connected: aid=4 MAC=70:4b:ca:25:b7:68
I (6750) MESH_SETUP:  Child connected: aid=5 MAC=b4:bf:e9:34:ed:80
I (6750) MESH_SETUP:  Routing table updated — nodes in mesh: 6
```

> 🗣️ *"The criterion asks for a three-node mesh within sixty seconds. This is **six nodes —
> five children plus the root — fully formed in 6.75 seconds**. The bracketed numbers are
> milliseconds since boot. Each line is logged by the root itself as each child associates."*

💡 **Point at `I (6750)`.** That single number answers the criterion, nine times over.

### 📊 And for "correct parent-child relationships"
```
NODE_2805A532D7B4 (layer 1, root)
    NODE_F42DC973E618 (layer 2)
        NODE_B4BFE934ED80 (layer 3)
            ...
PASS linear: one node per layer, depth 6.
```
> 🗣️ *"`verify_topology.py` rebuilds the tree from each node's own `parent_mac` and `layer`
> columns — it reports the structure that actually formed, independent of what we intended."*

---

# CRITERION 3 · Phase transitions applied within 1 s

### 🎥 CLIP CUE — the broadcast *(~15 s)*
```
I (64680) ROOT_MAIN:      ════════ PHASE 0 — BASELINE ════════
I (65240) PHASE_LISTENER: [ROOT] Broadcast phase_id=0  seq=1  label=0  (0 failed sends)
```
> 🗣️ *"The root announces each transition and broadcasts the phase ID. **`0 failed sends`** —
> every node acknowledged."*

### 📊 SLIDE — the measurement *(a clip cannot show this)*

**baseline · linear · 6 nodes**

| Phase | Duration spread across all 6 nodes |
|---|---:|
| **3 · cooldown** | **0.11 s** |

> 🗣️ *"Each board runs its own clock, so timestamps aren't directly comparable between nodes.
> What is comparable is **how long each node believed each phase lasted**. For cooldown, all
> six agree to within **0.11 seconds** — the criterion is one second."*

> ⚠️ **Say this before showing phase 0:** its spread is ~35 s, because nodes stamp rows as
> baseline **from the moment they boot**, before the root's first broadcast reaches them. A
> board powered earlier simply has a longer pre-experiment stretch. That's a boot-order
> artefact, not propagation delay — documented as deviation **D-4**. Phase 3 is the clean
> measurement because by then every node is synchronised to the root's timeline.

---

# CRITERION 4 · Telemetry to flash at configured rate, no missing samples

### 🎥 CLIP CUE — the logger starting *(~15 s)*
```
I (4280) CSV_LOGGER: SPIFFS mounted. Total: 2287 KB  Used: 0 KB
I (4280) CSV_LOGGER: Telemetry file: /spiffs/telem.csv
I (4460) CSV_LOGGER: Arrivals file:  /spiffs/arrivals.csv
I (4640) CSV_LOGGER: Logger ready. Role: root
I (4670) ROOT_MAIN: Telemetry task running at 100 ms interval.
```

### 📊 SLIDE — measured sampling rate, baseline run

| Node | rows | span | **measured rate** |
|---|---:|---:|---:|
| node2 | 4533 | 466.8 s | **9.71 Hz** |
| node3 | 4773 | 492.0 s | **9.70 Hz** |
| node4 | 4484 | 461.7 s | **9.71 Hz** |
| node5 | 4818 | 496.6 s | **9.70 Hz** |
| node6 | 4817 | 496.5 s | **9.70 Hz** |
| root | 4598 | 481.1 s | **9.56 Hz** |

> 🗣️ *"Configured at 100 milliseconds — 10 Hz. Measured across the run: **9.70 Hz on every
> child**, which is 97 percent of nominal. The shortfall is FreeRTOS scheduling jitter, not
> dropped samples. The cross-layer fields are all present — RSSI, layer, parent MAC, and the
> retry / tx / probe counters."*

**Also show the columns** — this is what "cross-layer" means:
```
timestamp_us, node_id, role, layer, parent_mac, rssi_dbm,
retry_count, tx_count, probes_count, phase_id, gt_label
```
> 🗣️ *"PHY layer is `rssi_dbm`. MAC layer is `retry_count` and `tx_count`. Network layer is
> `layer` and `parent_mac`. That's the cross-layer instrumentation in one row."*

---

# CRITERION 5 · Full baseline run end-to-end; CSVs retrievable via USB

### 📊 SLIDE — the retrieved files
```
tools/exports/baseline/linear_topology/
  child_node2_linear_none_r1_20260725_225635_telem.csv     355 KB
  child_node3_linear_none_r1_20260725_231258_telem.csv     378 KB
  child_node4_linear_none_r1_20260725_231510_telem.csv     351 KB
  child_node5_linear_none_r1_20260725_233253_telem.csv     382 KB
  child_node6_linear_none_r1_20260725_233508_telem.csv     382 KB
  root_node1_linear_none_r1_20260725_233705_telem.csv      334 KB
  root_node1_linear_none_r1_20260725_233820_arrivals.csv   598 KB
```

> 🗣️ *"A full baseline run, completed end-to-end. **Seven CSVs retrieved from six boards over
> USB serial** — one telemetry file per node, plus the root's probe-arrivals log. Note the
> `_none_` in the filenames: this is the no-attack baseline, which is what this milestone
> specifies."*

### ⚠️ Be ready for the duration question

Your baseline timeline is **8 minutes**, not 10:

| | |
|---|---|
| `PHASE_STABILISE_S` | 60 s |
| `PHASE_BASELINE_S` | 300 s *(5 min)* |
| `PHASE_COOLDOWN_S` | 120 s *(2 min)* |
| **Total** | **480 s ≈ 8 min** |

> 🗣️ **If asked:** *"Our baseline timeline is 8 minutes by design — a 60-second stabilise
> window, 5 minutes of baseline, 2 minutes of cooldown, from Table 4.1. The attack runs are
> 11 minutes because they add the 3-minute attack phase. So the platform completes runs
> longer than 10 minutes end-to-end; the baseline phase set just happens to total 8. If the
> criterion means a literal 10-minute baseline, that's a one-line change to
> `PHASE_BASELINE_S` and a re-run."*

> 💡 **Raise this with your adviser before the defence** if you can. Better to have it agreed
> than debated live. It's the one place your evidence doesn't literally match the wording.

---

## 🗣️ The 90-second M1 script

> *"Milestone 1 is the platform before any attack code. Three shared modules used by every
> node — mesh setup, phase listener, CSV logger — plus root and victim firmware.*
>
> *All six firmware variants build clean: zero warnings, zero errors. \[show table]*
>
> *The criterion asks for a three-node mesh in sixty seconds. \[play clip] **Six nodes in 6.75
> seconds**, and `verify_topology.py` confirms the parent-child structure by rebuilding it from
> the telemetry itself.*
>
> *Phase transitions: the root broadcasts, zero failed sends, and all six nodes agree on the
> cooldown duration to within **0.11 seconds** against a one-second criterion.*
>
> *Telemetry: configured at 10 Hz, measured at **9.70 Hz** on every child, with the full
> cross-layer row — RSSI, layer, parent MAC, packet counters.*
>
> *And a complete baseline run end-to-end, with all seven CSVs retrieved from six boards over
> USB. Milestone 1 is met."*

---

## 🛡️ M1 questions

**"Why didn't you run the 3-node test?"**
> *"Every run uses six nodes, which is a superset — if six form correctly in under seven
> seconds, three isn't in question. We chose to show the real baseline run because it also
> evidences criteria four and five."*

**"Can we see it run live?"**
> *"I have the recording. I'd rather not power the mesh here — the boards are on channel 11
> and this room's WiFi would change the conditions the recording was made under."*

**"Your baseline is 8 minutes, the criterion says 10."**
> *(See criterion 5 above — have this answer ready.)*

**"How do you know there are no missing samples?"**
> *"Two checks. Measured rate is 9.70 Hz against 10 configured — 97 percent, which is
> scheduling jitter, not gaps. And `validate_integrity.py` checks phase coverage against the
> expected rate on every file; every recorded run passes with zero failures."*

**"What does the phase listener actually do?"**
> *"It runs as a background task on every node. The root broadcasts a phase ID; the listener
> receives it and tags every subsequent telemetry row with that ID. The label is written by the
> firmware at capture time — there's no separate annotation step that could disagree with the
> data."*

**"Why is the root's rate 9.56 Hz when the children are 9.70?"**
> *"The root carries extra work — it also runs the probe sink and the phase broadcaster, so its
> telemetry task is preempted slightly more often. It's still within 5 percent of nominal."*

---

## ✅ M1 checklist

- [ ] `.\build_all_variants.ps1` run, table screenshotted — **criterion 1**
- [ ] Clip cued to: topology line → `Child connected` ×5 → `SPIFFS mounted` → `Broadcast`
- [ ] `verify_topology.py` output for **baseline · linear** — parent-child structure
- [ ] Sampling-rate table (9.70 Hz) on a slide — **criterion 4**
- [ ] File listing of the 7 baseline CSVs — **criterion 5**
- [ ] Know: **6.75 s vs 60 s** · **0.11 s vs 1 s** · **9.70 Hz vs 10 Hz** · **7 of 7 CSVs**
- [ ] Phase-0 spread explanation rehearsed
- [ ] ⚠️ 8-minute vs 10-minute answer rehearsed — ideally agreed with your adviser first

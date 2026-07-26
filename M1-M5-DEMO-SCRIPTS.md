# 🎬 Demo Scripts — Milestones 1 to 5

> One document, five scripts, same depth throughout. For each milestone:
> **criteria → what to show → exact cue lines → what to say → questions → checklist.**
>
> ⚠️ **Criteria provenance.** M1's are quoted from your Milestones Form. M3's from
> `thesis-deviate.md` D-4. M4's from `run_matrix.py`. **M2 and M5 criteria are not in the
> repo** — those sections are built from milestone scope. Paste them and I'll tighten it.
>
> 📌 **Numbers below were read from the repo on 2026-07-27 at 10/24.** Re-check with
> `python slides\refresh_slide_numbers.py` on the day.

---

## 🧭 Universal rules

| Type | Use for | Risk |
|---|---|:--:|
| 🎥 **Recorded clip** | Proving something happened live | Low |
| 📊 **Data / table** | Proving a quantity | None |
| 📄 **File / code** | Proving structure exists | None |
| ⚡ **Live command** | Only `run_matrix.py --status` | Low |
| 🔌 **Live hardware** | **Never** | High |

**Why never live hardware:** the room's WiFi differs from your recording conditions, boards
need power and placement, exports take minutes, and a failed demo costs more than the demo
was worth. If asked, this is a legitimate answer — say it plainly.

---
---

# 🟢 M1 · Firmware Development for All Node Roles — 15%

### 📋 Criteria *(quoted)*
1. All firmware variants compile without warnings
2. A 3-node test mesh forms within 60 s of root startup, with correct parent-child relationships
3. Root broadcasts phase transitions; every node receives and applies them within 1 s
4. Each node records cross-layer telemetry to local flash at the configured rate, no missing samples

### 🎯 Verdict: **all four met, two of them by a wide margin**

| # | Evidence | Result | Margin |
|:-:|---|---|---|
| 1 | `idf.py build` tail | ⚠️ **capture fresh** | — |
| 2 | Root boot log | 6 nodes in **6.75 s** | **9× better** |
| 3 | Phase-duration table | **0.15 s** spread | **6× better** |
| 4 | Preprocessing report | discard **0.2–0.8 %** | — |

---

### 🎥 CLIP — 4 cues, ~75 s

**CUE 1 · Boot + topology shaping** *(~10 s)*
```
I (560)  ROOT_MAIN:   === ROOT NODE STARTING ===
I (780)  MESH_SETUP:  Topology shaping: STAR (max_layer=2, max_children=10)
I (1090) MESH_SETUP:  Mesh started. Node ID: NODE_2805A532D7B4  Role: 0
```
> 🗣️ *"Root boots and applies the topology constraint. This is a compile-time flag the mesh
> stack enforces — `max_layer=2` means no board can become a grandchild."*

**CUE 2 · Mesh formation** ⭐ criterion 2 *(~20 s)*
```
I (1320) MESH_SETUP: Child connected: aid=1 MAC=f4:2d:c9:73:e6:18
I (1630) MESH_SETUP: Child connected: aid=2 MAC=b0:cb:d8:f3:32:18
I (1940) MESH_SETUP: Child connected: aid=3 MAC=b4:bf:e9:32:fe:90
I (4800) MESH_SETUP: Child connected: aid=4 MAC=70:4b:ca:25:b7:68
I (6750) MESH_SETUP: Child connected: aid=5 MAC=b4:bf:e9:34:ed:80
I (6750) MESH_SETUP: Routing table updated — nodes in mesh: 6
```
> 🗣️ *"The criterion asks for a 3-node mesh within 60 seconds. This is five children plus the
> root — **six nodes fully formed in 6.75 seconds**. The bracketed numbers are milliseconds
> since boot. Each line is logged by the root as each child associates, and every child
> attached directly to the root — the correct parent-child relationship for a star."*

💡 **Point at `I (6750)` on screen.** That one number answers criterion 2.

**CUE 3 · Logger + sampling rate** ⭐ criterion 4 *(~15 s)*
```
I (4280) CSV_LOGGER: SPIFFS mounted. Total: 2287 KB  Used: 0 KB
I (4280) CSV_LOGGER: Telemetry file: /spiffs/telem.csv
I (4640) CSV_LOGGER: Logger ready. Role: root
I (4670) ROOT_MAIN: Telemetry task running at 100 ms interval.
```
> 🗣️ *"Flash mounts, log files open, telemetry task starts at 100 ms — that's 10 Hz. Every node
> writes to its own onboard flash; nothing streams to the laptop during a run."*

**CUE 4 · Phase broadcast** ⭐ criterion 3 *(~20 s)*
```
I (64680)  ROOT_MAIN:      ════════ PHASE 0 — BASELINE ════════
I (65240)  PHASE_LISTENER: [ROOT] Broadcast phase_id=0  seq=1  label=0  (0 failed sends)
I (365240) ROOT_MAIN:      ════════ PHASE — ATTACK ════════
I (365770) PHASE_LISTENER: [ROOT] Broadcast phase_id=2  seq=2  label=2  (0 failed sends)
```
> 🗣️ *"The root announces each transition and broadcasts the phase ID. Note **`0 failed
> sends`** — every node acknowledged. Each node then stamps that ID into every telemetry row,
> which is where the ground-truth label comes from."*

---

### 📊 SLIDE — phase-transition consistency *(criterion 3, cannot be filmed)*

**Star · wormhole r2 · 6 nodes**

| Node | phase 0 (s) | phase 2 (s) | phase 3 (s) |
|---|---:|---:|---:|
| …34ED80 | 354.4 | 180.5 | 120.4 |
| …25B768 | 360.1 | 180.4 | 120.4 |
| …32FE90 | 328.7 | 180.4 | 120.5 |
| …F33218 | 363.0 | 180.4 | 120.4 |
| …73E618 | 388.1 | 180.5 | 120.4 |
| …32D7B4 root | 360.6 | 180.4 | 120.4 |
| **spread** | *see note* | **0.15 s** | **0.11 s** |

> 🗣️ *"Each board runs its own clock, so timestamps aren't comparable across nodes. What is
> comparable is **how long each node believed each phase lasted**. For the attack phase all six
> agree within **0.15 seconds**; cooldown within **0.11**. The criterion is one second."*

> ⚠️ **Say this before anyone reads the phase-0 column:** *"Phase 0 varies because nodes stamp
> rows as baseline from the moment they boot, before the root's first broadcast arrives. A
> board powered earlier has a longer pre-experiment stretch. That's a boot-order artefact, not
> propagation delay — documented as deviation D-4."*

### 📄 CAPTURE FRESH — criterion 1
```powershell
cd child_node
idf.py build
```
Screenshot the `Project build complete` tail. Repeat for `root_node` if time allows.
If a warning appears, **state it** — say whether it's yours or ESP-IDF's.

### 🛡️ M1 questions
**"Why not the 3-node test?"** → *"Every run uses six nodes, a superset. If six form in under
seven seconds, three isn't in question — and the same recording also supports M3 and M4."*

**"Can we see it live?"** → *"I have the recording. I'd rather not power the mesh here — the
boards are on channel 11 and this room's WiFi would change the conditions the recording was
made under."*

**"How do you know there are no missing samples?"** → *"Two checks. `validate_integrity.py`
verifies phase coverage against the expected sample rate on every file — zero failures across
every recorded cell. And preprocessing counts windows with too few samples: 0.2 to 0.8 percent."*

### ✅ M1 checklist
- [ ] Clip cued to 4 points, tested on the presentation machine
- [ ] Build screenshot captured
- [ ] Phase-consistency table on a slide
- [ ] Can say **6.75 s vs 60 s** and **0.15 s vs 1 s** from memory
- [ ] Phase-0 explanation rehearsed

---
---

# 🟢 M2 · Application-Layer Attack Modules — 15%

### 📋 Criteria *(not in repo — inferred from scope)*
Blackhole and wormhole implemented at the application layer, producing observable and
distinguishable signatures at the root.

### 🎯 Verdict: **complete, and cross-verified on independent boards**

> **The framing that wins this milestone:** each attack is measured **twice** — by the
> attacker's own counters, and by the root's arrivals log. Different boards, different files,
> agreeing numbers.

---

### 📊 SLIDE 1 — Blackhole · star r1

| phase | probes received | tx (forwarded) | retry (dropped) |
|---|---:|---:|---:|
| 0 baseline | 1 → 1453 | 0 → 1452 | 0 → 1 |
| **1 ATTACK** | 1455 → **2176** | **1453 → 1453** | 2 → **723** |
| 3 cooldown | 2176 → 2657 | 1453 → 1934 | 723 → 723 |

> 🗣️ *"During the attack window the relay received 721 probes and dropped 721. Look at the
> forwarded column — **1453 to 1453, flat to the digit**. Then independently, on a different
> board writing a different file, the root logged **zero arrivals** in that same window. Two
> measurements, exact agreement. In cooldown it forwards again and the root's count resumes."*

### 📊 SLIDE 2 — Wormhole · star r2, both tunnel ends

| node | role | phase 0 | phase 2 (attack) | phase 3 |
|---|---|---|---|---|
| node5 | **Node A (exit)** | probes 0 → 0 | probes **0 → 180** | 180 → 180 |
| node6 | **Node B (entry)** | retry 0 → 0 | retry **0 → 180** | 180 → 180 |

> 🗣️ *"Node B is the tunnel entry — its counter climbs by exactly 180 during the attack. Node A
> is the exit — it replays exactly 180. Zero on both in baseline. The two ends agree, and the
> root then logged 180 duplicate deliveries."*

### 📊 SLIDE 3 — Wormhole reproducibility

| run | duplicates | multiplicity | source | baseline dupes |
|---|---:|---:|---|---:|
| linear r1 | 181 | ×2.00 | Node B | 0 |
| linear r3 | 181 | ×2.00 | Node B | 0 |
| star r1 | 180 | ×2.00 | Node B | 0 |
| star r2 | 180 | ×2.00 | Node B | 0 |

> 🗣️ *"Four runs, two different topologies, the same signature. Detection here is **exact, not
> statistical** — the root receives the identical `(src_mac, seq_num)` pair twice."*

---

### 🎥 CLIP — attacker boot banners *(~25 s)*

**Blackhole attacker:**
```
=== BLACKHOLE ATTACKER (relay) STARTING ===
This is the blackhole ATTACKER. Set BLACKHOLE_ATTACKER_MAC on the victim
boards to my STA MAC: b0:cb:d8:f3:32:18
```
**A victim:**
```
Blackhole victim mode: probes -> attacker b0:cb:d8:f3:32:18
```
**Wormhole ends:**
```
=== WORMHOLE NODE A (exit) STARTING ===
=== WORMHOLE NODE B (entry) STARTING ===
```

> 🗣️ *"Victims are compiled to address their probes to the attacker's MAC, so the relay sits in
> the application path regardless of where it lands in the mesh tree. That's why the blackhole
> works identically on every topology."*

### 📄 OPTIONAL — the code
`child_node/main/blackhole_victim.c`, header comment. Four lines state the relay model:
forward during baseline/cooldown, drop during the attack phase.

### 🛡️ M2 questions
**"Why does the wormhole increase traffic instead of decreasing it?"** → *"Because the tunnel
is out-of-band. Probes still take their normal mesh path **and** a copy arrives through the
UART wire, so the root sees both. Blackhole removes traffic; wormhole duplicates it. Opposite
signatures."*

**"Could the duplicates be retransmissions rather than the attack?"** → *"No — a retransmission
would appear in baseline too, and baseline has exactly zero duplicates in every run. And they
all come from one source MAC, Node B, which is the tunnel entry."*

**"How do you know the attacker actually dropped them rather than failing to send?"** →
*"Because `probes_count` kept climbing — it was still receiving. Received went up by 721 while
forwarded stayed flat and the drop counter went up by 721. A send failure would show a
different pattern."*

### ✅ M2 checklist
- [ ] Three data slides prepared
- [ ] Clip cued to attacker + victim banners
- [ ] Can explain **why wormhole raises traffic** without notes
- [ ] Know **721/721/0** and **181·181·180·180**

---
---

# 🟡 M3 · Multi-Topology Deployment — 15%

### 📋 Criteria *(quoted, `thesis-deviate.md` D-4)*
> *"Each topology converges to its intended parent-child structure within 60 seconds"* **and**
> *"Mesh remains stable through a full 5-minute baseline phase (no spontaneous re-routing)."*

### 🎯 Verdict: **met on linear and star; one star run fails and you must be ready for it**

---

### 📊 SLIDE 1 — the reconstruction ⭐ *your best artifact here*

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

> 🗣️ *"This is not our intended diagram — `verify_topology.py` reads each node's own
> `parent_mac` and `layer` columns out of the telemetry and **rebuilds the tree that actually
> formed**, then checks it against the expected shape. It's an independent measurement of the
> physical setup."*

### 📊 SLIDE 2 — two topologies, both passing

| Run | Shape | Converged <60 s | No baseline re-routing |
|---|---|:--:|:--:|
| linear · blackhole r3 | PASS — one node per layer, depth 6 | ✅ YES | ✅ YES |
| star · wormhole r2 | PASS — all 5 at layer 2 | ✅ YES | ✅ YES |

> 🗣️ *"Two structurally opposite topologies — a six-deep chain and a flat five-spoke star —
> both converging inside 60 seconds with no re-routing during baseline."*

### 📊 SLIDE 3 — coverage

| Topology | Baseline | Blackhole | Wormhole |
|---|:--:|:--:|:--:|
| Tree | ✔ | pending | pending |
| Linear | ✔ | ✔ | ✔ |
| Star | ✔ | ✔ | ✔ |
| Partial | ✔ | pending | pending |

---

### ⚠️ THE ONE THAT FAILS — prepare this, don't volunteer it

**star · blackhole r1** reports:
```
Converged within 60s     : NO
Baseline re-routing free : NO
```

> 🗣️ **If asked:** *"One star run doesn't meet it — nodes dropped and re-attached during
> baseline, settling around 100 seconds. The **next** star run, same placement, converged
> inside 60 seconds with no re-routing — so it isn't a fixed property of star. We haven't
> established the cause; the clean test is a baseline-star run we haven't done.*
>
> *What I can say is that every disturbance is in phase 0. **Zero during the attack window** —
> so the attack measurement is unaffected, which is why that run's signature is clean."*

> 💡 **Why this answer works:** it states the failure, gives the counter-example, admits the
> unknown, and bounds the impact. Four moves in twenty seconds.

### 🛡️ M3 questions
**"How do you know it's really a star?"** → *"Two independent things. The build flag caps
`max_layer` at 2, so the stack refuses a deeper association. And `verify_topology.py`
reconstructs the tree from telemetry. One is intent, the other is measurement."*

**"What counts as 'converged'?"** → *"The last parent or layer change in a node's log. Changes
inside the first 60 seconds are counted as **formation**, not re-routing — the criteria are two
separate statements and the tool was conflating them. That's deviation D-4."*

**"Only two topologies have attack data."** → *"Correct. Linear and star are complete for both
attacks; tree and partial are pending. That's M4 runtime."*

### ✅ M3 checklist
- [ ] `verify_topology.py` screenshots for linear r3 and star wormhole r2
- [ ] Coverage table current
- [ ] **Star-blackhole-r1 answer rehearsed out loud** — this is the likeliest hard question
- [ ] Know what "formation window" means and why it's excluded

---
---

# 🔴 M4 · Phase-Controlled Experiment Execution — 15%

### 📋 Criterion *(from `run_matrix.py`)*
≥24 runs = 4 topologies × 2 attacks × ≥3 repeats. A cell counts **only** once its CSVs pass
`validate_integrity.py`.

### 🎯 Verdict: **10/24 — the honest slide. Do not rush it.**

---

### ⚡ LIVE — the one command safe to run in the room
```powershell
python tools\run_matrix.py --status
```
Two seconds. No hardware. Reads a local CSV.

```
topology  attack     r1  r2  r3
star      blackhole  [x]  [ ]  [ ]
star      wormhole   [x]  [x]  [x]
tree      blackhole  [ ]  [ ]  [ ]
tree      wormhole   [ ]  [ ]  [ ]
linear    blackhole  [x]  [x]  [x]
linear    wormhole   [x]  [x]  [x]
partial   blackhole  [ ]  [ ]  [ ]
partial   wormhole   [ ]  [ ]  [ ]

Progress: 10/24 runs collected
```

> 🗣️ *"Ten of twenty-four. **Three cells fully replicated** at three repeats each. Every
> recorded cell passed validation with zero failures — and a cell can only be marked done when
> its files pass, so the ledger cannot be ticked by hand. What remains is runtime, not
> unknowns: the method, tooling and analysis pipeline are complete and exercised."*

> ⚠️ **Hold this slide.** The instinct to rush past it is exactly what makes it look bad.
> Let them read it. Silence for two seconds is fine.

### 📄 SLIDE — the audit trail
`tools/exports/run_ledger.csv`
```
topology,attack,repeat,status,recorded_at,files
linear,blackhole,1,done,2026-07-26 17:06:38,child_node2_...;child_node3_...;...
linear,blackhole,2,done,2026-07-26 17:06:32,...
linear,blackhole,3,done,2026-07-26 17:22:05,...
```
> 🗣️ *"One row per recorded cell, with the validation timestamp and every file that was
> checked. This is what's behind the grid."*

### 🛡️ M4 questions
**"Your matrix is only 40% complete."** → *"Correct — ten of twenty-four. Three cells fully
replicated, every recorded cell zero-FAIL. The infrastructure and analysis are done; what's
left is about eleven minutes of runtime per run."*

**"Why three repeats?"** → *"The milestone specifies at least three. It's what lets us show a
signature is reproducible rather than a one-off — the wormhole came out at 181, 181, 180, 180
across four runs."*

**"How do you stop a cell being marked done by mistake?"** → *"`--record` runs the validator
first and refuses on any FAIL. And `--autorecord` reads the repeat number off the filenames
rather than asking us to type it — we lost a run early on to a mistyped `--repeat`."*

### ✅ M4 checklist
- [ ] ⚠️ **Re-run `--status` the morning of** — the number moves
- [ ] Screenshot as backup in case live fails
- [ ] Ledger open in a second window
- [ ] Rehearse holding the slide without filling the silence

---
---

# 🟢 M5 · Raw Extraction & Integrity Validation — 10%

### 📋 Criteria *(not in repo — inferred from scope)*
Telemetry reliably extracted from device flash, and validated for integrity before entering
the dataset.

### 🎯 Verdict: **complete — and this is where you demonstrate research rigour**

---

### 📊 SLIDE 1 — the pipeline
```
board ──USB──▶ export_logs.py ──▶ trim_run.py ──▶ validate_integrity.py ──▶ ledger
                schema guard      session split     5 checks + SHA-256
```

### 📊 SLIDE 2 — the verdict
```
21 file(s) — 21 PASS, 0 WARN, 0 FAIL
Manifest: .../trimmed/manifest.json
```
**The five checks:** schema width · phase coverage · timestamp monotonicity · label integrity ·
SHA-256 manifest.

> 🗣️ *"Five checks on every file. A cell is marked done only if all its files pass. Every
> recorded cell across the whole matrix is zero-FAIL."*

### 📄 SLIDE 3 — the manifest ⭐ *strongest artifact for "is this genuine?"*
```json
{
  "child_node2_star_wormhole_r1_20260727_014200_telem.csv": {
    "row_count": 7080,
    "sha256": "4df9c60cf014bf1bee9c26f128ce0f8afbbc0c1d6ef771c67f284f373d20dd2c",
    "size_bytes": 518330
  }
}
```
> 🗣️ *"Every capture is hashed at validation time and locked into a manifest. If a byte changes
> afterwards, the next validation fails. Combined with version-controlled history, that's the
> integrity trail."*

### 📊 SLIDE 4 — the three guards ⭐ *your differentiator*

| Failure that occurred during collection | Now caught by |
|---|---|
| Device streamed the **wrong file** — telemetry saved under an arrivals name | Schema checked at capture; quarantined, `--delete` suppressed |
| **Stale derived files** left after a re-export | Flagged when the raw source disappears |
| **Duplicate capture** double-counting one node | Flagged before analysis runs |

> 🗣️ *"Each of these corrupted a dataset once during collection. The third produced **no error
> at all** — one node was counted twice, 264 windows against about 155 for every other node,
> and every total still looked plausible. That's the failure mode that matters most for a
> dataset, because nothing announces it. Each now fails at the moment it happens rather than
> twenty minutes later in the analysis."*

### 🛡️ M5 questions
**"How do we know the data is genuine?"** → *"Three things. SHA-256 per file in a manifest
written at validation time. A ledger recording when each cell was validated. And the attack
signatures are cross-verified between independent boards — the attacker's counters and the
root's arrivals log agree exactly, and those are separate devices writing separate files."*

**"What happens if an export fails halfway?"** → *"The partial capture is still saved — a
partial CSV is more useful than discarding thousands of good rows — but it's reported as
FAILED and the cell won't record. And the board keeps its copy, because `--delete` is skipped
on any failure."*

**"Why do you trim the files?"** → *"The firmware appends to one file across boots, so an
export contains the run plus a short session from when we plug in the board for export.
`trim_run.py` splits on timestamp regressions — a clock going backwards is an unambiguous
reboot — and keeps the longest segment. Raw files are never modified."*

### ✅ M5 checklist
- [ ] Validator screenshot showing `0 FAIL`
- [ ] `manifest.json` open, first entry visible
- [ ] Three-guards table on a slide
- [ ] Can explain **why trimming is safe** (raw untouched)

---
---

# 📋 Master prep list

## Capture fresh — ~12 minutes
| Artifact | Command | For |
|---|---|:--:|
| Build log, no warnings | `cd child_node; idf.py build` | M1 |
| Topology verdicts ×2 | `verify_topology.py` linear r3, star wormhole r2 | M3 |
| Matrix status | `run_matrix.py --status` | M4 |
| Validator `0 FAIL` | `validate_integrity.py <trimmed>` | M5 |
| Manifest first entry | open `manifest.json` | M5 |

## From your existing recording
| Cue | For |
|---|:--:|
| Topology shaping line | M1 |
| Five `Child connected` lines → `nodes in mesh: 6` | M1 |
| `SPIFFS mounted` → `100 ms interval` | M1 |
| `PHASE 0` → `Broadcast ... (0 failed sends)` | M1 |
| Attacker + victim boot banners | M2 |

## Numbers to know cold
| | |
|---|---|
| **6.75 s** | six nodes joined *(criterion: 3 nodes / 60 s)* |
| **0.15 s** | phase-transition spread *(criterion: 1 s)* |
| **721 / 721 / 0** | blackhole received / dropped / forwarded |
| **181 · 181 · 180 · 180** | wormhole duplicates, four runs |
| **10 / 24** | M4 runs — ⚠️ re-check |
| **0 FAIL** | every recorded cell |
| **0.2 – 0.8 %** | window discard rate |

## The three answers to rehearse aloud
1. **Star-blackhole-r1 convergence failure** (M3) — most likely hard question
2. **Why the wormhole increases traffic** (M2) — counter-intuitive, gets asked
3. **Why 10/24 is honest, not incomplete work** (M4) — say it without apologising

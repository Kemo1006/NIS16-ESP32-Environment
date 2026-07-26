# 🎯 What to show for Milestones 1–5

> **How to read this:** for each milestone — the criterion, the **artifact type** (clip /
> data / file / live), the **exact thing to put on screen**, and the **line to say**.
>
> ⚠️ **Criteria caveat.** M1's criteria are quoted from your Milestones Form. M3's come from
> `thesis-deviate.md` D-4. **M2, M4 and M5 criteria are not stored in the repo** — the
> mapping below is built from your milestone scope. **Paste those three criteria to me and
> I'll tighten the mapping**; the evidence itself won't change.

---

## 🧭 The rule for all five

| Artifact type | Use it when | Risk |
|---|---|---|
| 🎥 **Recorded clip** | Proving something *happened live* — mesh forming, attack starting | Low ✅ |
| 📊 **Data / table** | Proving a *quantity* — counts, rates, durations | None ✅ |
| 📄 **File / code** | Proving something *exists and is structured* | None ✅ |
| ⚡ **Live run** | Almost never | High ❌ |

**Never demo hardware.** Room WiFi differs, boards need power, exports take minutes. A clip
shows the same thing and cannot fail.

---

# 🟢 M1 · Firmware — All Node Roles (15%)

> Full script in **`M1-DEMO-SCRIPT.md`** — this is the summary.

| Criterion | Show | Type |
|---|---|:--:|
| Compiles without warnings | `idf.py build` tail — **capture fresh** | 📄 |
| 3-node mesh <60 s, correct parent-child | Root boot log: **5 children in 6.75 s** | 🎥 |
| Phase applied within 1 s | Phase-duration table: **0.15 s** spread | 📊 |
| Telemetry to flash, no missing samples | `SPIFFS mounted` + `100 ms interval` lines | 🎥 |

**🎥 Clip cues** — 4 points, ~75 s:
1. `MESH_SETUP: Topology shaping: STAR (max_layer=2, max_children=10)`
2. The five `Child connected: aid=N MAC=...` lines → `nodes in mesh: 6` at **I (6750)**
3. `CSV_LOGGER: SPIFFS mounted` → `Telemetry task running at 100 ms interval`
4. `PHASE 0 — BASELINE` → `[ROOT] Broadcast phase_id=0 ... (0 failed sends)`

**🗣️ Line:** *"The criterion asks for three nodes in sixty seconds. This is six nodes in
6.75 seconds, and all six agree on phase duration to within 0.15 seconds."*

---

# 🟢 M2 · Application-Layer Attack Modules (15%)

**Type: 📊 data first, 🎥 clip second.** The numbers are the proof; the clip shows the attack
starting.

## 📊 Primary evidence — cross-verified counters

**Blackhole · star r1** *(fresh — use this, it's your newest)*

| phase | probes received | tx (forwarded) | retry (dropped) |
|---|---:|---:|---:|
| 0 baseline | 1 → 1453 | 0 → 1452 | 0 → 1 |
| **1 ATTACK** | 1455 → **2176** | **1453 → 1453** | 2 → **723** |
| 3 cooldown | 2176 → 2657 | 1453 → 1934 | 723 → 723 |

**721 received during the window, 721 dropped, zero forwarded.** `tx_count` is flat to the
digit.

**Wormhole — duplicate deliveries, four runs, two topologies**

| run | duplicates | source | baseline dupes |
|---|---:|---|---:|
| linear r1 | 181 | Node B | 0 |
| linear r3 | 181 | Node B | 0 |
| star r1 | 180 | Node B | 0 |
| star r2 | 180 | Node B | 0 |

## 🎥 Clip cues — attacker boot banners *(~20 s)*
```
=== BLACKHOLE ATTACKER (relay) STARTING ===
   Set BLACKHOLE_ATTACKER_MAC on the victim boards to my STA MAC: b0:cb:d8:f3:32:18
```
and on a victim:
```
Blackhole victim mode: probes -> attacker b0:cb:d8:f3:32:18
```

**🗣️ Line:** *"Victims are compiled to address their probes to the attacker's MAC. The
attacker relays them during baseline and drops them during the attack window — 721 received,
721 dropped, zero forwarded. And independently, on a different board writing a different file,
the root logged zero arrivals in that same window."*

## 📄 Optional — the code
`child_node/main/blackhole_victim.c` — show the header comment block. It states the relay
model in four lines. Good if a panelist asks *how* the attack works.

---

# 🟡 M3 · Multi-Topology Deployment (15%)

**Criteria (from `thesis-deviate.md` D-4):**
> *"Each topology converges to its intended parent-child structure within 60 seconds"* **and**
> *"Mesh remains stable through a full 5-minute baseline phase (no spontaneous re-routing)."*

**Type: 📊 tool output.** This is the one place a tool's own verdict is the cleanest evidence.

## 📊 Show `verify_topology.py` output — two runs, side by side

**Linear · blackhole r3**
```
PASS linear: one node per layer, depth 6.
Converged within 60s     : YES
Baseline re-routing free : YES
```

**Star · wormhole r2**
```
PASS star: all 5 nodes at layer 2 (direct children of root).
Converged within 60s     : YES
Baseline re-routing free : YES
```

**🗣️ Line:** *"This isn't our intended diagram — `verify_topology.py` rebuilds the tree from
each node's own `parent_mac` and `layer` columns in the telemetry, then checks it against the
expected shape. Two different topologies, both converging inside 60 seconds with no baseline
re-routing."*

## ⚠️ Be ready for the one that fails

**Star · blackhole r1** currently reports:
```
Converged within 60s     : NO
Baseline re-routing free : NO
```

**Do not show this slide unprompted.** But have the answer ready:

> *"One star run doesn't meet it — nodes dropped and re-attached during baseline. The very
> next star run, same placement, converged inside 60 seconds with no re-routing, so it isn't
> a fixed property of star. We haven't established the cause; the clean test is a baseline-star
> run we haven't done yet. What I can say is that every disturbance is in phase 0 — **zero
> during the attack window** — so the attack measurement is unaffected."*

## 📊 Coverage table
| Topology | Baseline | Blackhole | Wormhole |
|---|:--:|:--:|:--:|
| Tree | ✔ | pending | pending |
| Linear | ✔ | ✔ | ✔ |
| Star | ✔ | ✔ | ✔ |
| Partial | ✔ | pending | pending |

---

# 🔴 M4 · Phase-Controlled Experiment Execution (15%)

**Criterion (from `run_matrix.py`):** ≥24 runs = 4 topologies × 2 attacks × ≥3 repeats. A cell
counts only once its CSVs **pass `validate_integrity.py`**.

**Type: 📊 live tool output — this one is safe to run live.**

## 📊 The one command worth running in the room
```powershell
python tools\run_matrix.py --status
```
Two seconds, no hardware, reads a local CSV ledger. If you demo anything, demo this.

```
topology  attack     r1  r2  r3
star      blackhole  [x]  [ ]  [ ]
star      wormhole   [x]  [x]  [x]
linear    blackhole  [x]  [x]  [x]
linear    wormhole   [x]  [x]  [x]
...
Progress: 10/24 runs collected
```

**🗣️ Line:** *"Ten of twenty-four. Three cells fully replicated at three repeats each. Every
recorded cell passed validation with zero failures — the ledger can't be ticked by hand, a cell
is only marked done when its files pass. What remains is runtime, not unknowns."*

## 📄 Also show — `run_ledger.csv`
One row per recorded cell with a validation timestamp. It's the audit trail behind the grid.

> ⚠️ **Re-run `--status` the morning of.** You've moved from 8 to 10 in the last few hours.

---

# 🟢 M5 · Raw Extraction & Integrity Validation (10%)

**Type: 📊 tool output + 📄 file.**

## 📊 Evidence 1 — the validator verdict
```
21 file(s) — 21 PASS, 0 WARN, 0 FAIL
Manifest: .../trimmed/manifest.json
```

**The five checks:** schema width · phase coverage · timestamp monotonicity · label integrity ·
SHA-256 manifest.

## 📄 Evidence 2 — the manifest itself ⭐ *strongest artifact for "is this genuine?"*
```json
{
  "child_node2_star_wormhole_r1_20260727_014200_telem.csv": {
    "row_count": 7080,
    "sha256": "4df9c60cf014bf1bee9c26f128ce0f8afbbc0c1d6ef771c67f284f373d20dd2c",
    "size_bytes": 518330
  },
  ...
}
```

**🗣️ Line:** *"Every capture is hashed at validation time and locked into a manifest. If a byte
changes afterwards, the next validation fails. Combined with the version-controlled history,
that's the integrity trail."*

## 📊 Evidence 3 — the three guards *(your differentiator)*

| Failure that occurred during collection | Now caught by |
|---|---|
| Device streamed the **wrong file** — telemetry saved under an arrivals name | Schema checked at capture; file quarantined, `--delete` suppressed |
| **Stale derived files** left after a re-export | Flagged when the raw source disappears |
| **Duplicate capture** double-counting one node | Flagged before analysis runs |

**🗣️ Line:** *"Each of these corrupted a dataset once during collection. The duplicate one
produced no error at all — one node counted twice, and every total still looked plausible.
That's the failure mode that matters most for a dataset, because nothing announces it."*

---

# 📋 Prep checklist

## Capture fresh (~10 min total)
- [ ] `idf.py build` tail, no warnings — **M1** *(the only genuinely missing artifact)*
- [ ] Screenshot `run_matrix.py --status` — **M4**
- [ ] Screenshot `validate_integrity.py` showing `0 FAIL` — **M5**
- [ ] Screenshot `verify_topology.py` for **linear r3** and **star wormhole r2** — **M3**
- [ ] Open `manifest.json`, screenshot the first entry — **M5**

## From your existing recording
- [ ] Cue the 4 M1 points *(see `M1-DEMO-SCRIPT.md`)*
- [ ] Cue the attacker boot banner — **M2**

## Numbers to know cold
| | |
|---|---|
| **6.75 s** | six nodes joined (criterion: 3 nodes / 60 s) |
| **0.15 s** | phase-transition spread (criterion: 1 s) |
| **721 / 721 / 0** | blackhole received / dropped / forwarded, star r1 |
| **181 · 181 · 180 · 180** | wormhole duplicates, four runs |
| **10 / 24** | M4 runs — ⚠️ re-check the morning of |
| **0 FAIL** | across every recorded cell |

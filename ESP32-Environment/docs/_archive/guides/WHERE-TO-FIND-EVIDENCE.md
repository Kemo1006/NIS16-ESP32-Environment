# 📍 Where to find every piece of evidence — M1 to M5

> For each criterion: **the exact command to run**, or **the exact log line to cue in your
> recording**. Nothing here needs hardware.
>
> 🔄 **Numbers current as of 2026-07-27, matrix at 11/24.** Re-check before presenting.

---

## 🎬 Cue sheet for your recorded video

Every M1/M2 clip cue is in the **root monitor recording**. Search the log for these strings:

| Search for this string | Shows | Criterion |
|---|---|:--:|
| `=== ROOT NODE STARTING ===` | boot start | M1 context |
| `Topology shaping:` | the compile-time constraint | M1-2, M3 |
| `Child connected: aid=` | each child joining (5 lines) | **M1-2** |
| `Routing table updated — nodes in mesh: 6` | full mesh formed | **M1-2** |
| `SPIFFS mounted. Total:` | flash logging starts | **M1-4** |
| `Telemetry task running at 100 ms interval` | the configured rate | **M1-4** |
| `PHASE 0 — BASELINE` | phase controller starts | M1-3, **M4-3** |
| `Broadcast phase_id=0` … `(0 failed sends)` | every node ACKed | **M1-3**, **M4-3** |
| `=== BLACKHOLE ATTACKER (relay) STARTING ===` | attacker identifies itself | **M2-1** |
| `Blackhole victim mode: probes -> attacker` | victim addressing | **M2-1** |
| `=== WORMHOLE NODE A (exit) STARTING ===` | tunnel exit | **M2-2** |
| `=== WORMHOLE NODE B (entry) STARTING ===` | tunnel entry | **M2-2** |

💡 The mesh-formation block is the highest-value 20 seconds you own — `I (1320)` through
`I (6750)` shows all five children joining in **6.75 seconds** against a 60-second criterion.

---

# 🟢 M1 · Firmware Development for All Node Roles

### Criterion 1 — All firmware variants compile without warnings
```powershell
.\build_all_variants.ps1
```
📍 **Where:** run in your **ESP-IDF PowerShell**. ~2–6 min, no board needed.
📋 **Screenshot:** the final table — 6 variants × `BUILD OK` / 0 warnings / 0 errors.

### Criterion 2 — 3-node mesh within 60 s, correct parent-child
🎥 **Clip:** the five `Child connected: aid=N MAC=...` lines, ending at
`I (6750) ... nodes in mesh: 6`.

📍 **Plus the structure check:**
```powershell
cd tools
python verify_topology.py --dir exports\baseline\linear_topology\trimmed --topology linear --attack none --repeat 1 --expect linear
cd ..
```
📋 **Screenshot:** the reconstructed tree + `PASS linear`.

### Criterion 3 — Phase transitions applied within 1 s
🎥 **Clip:** `[ROOT] Broadcast phase_id=0  seq=1  label=0  (0 failed sends)`

📍 **The measurement** (paste into PowerShell from the repo root):
```powershell
cd tools\exports\baseline\linear_topology\trimmed
python -c "import csv,glob,os;d={};[d.setdefault(list(csv.DictReader(open(f)))[0]['node_id'][-6:],[(lambda t:(max(t)-min(t))/1e6)([int(r['timestamp_us']) for r in csv.DictReader(open(f)) if r['phase_id']=='3'])]) for f in glob.glob('*telem.csv')];v=[x[0] for x in d.values()];print('phase 3 duration spread across %d nodes: %.2f s'%(len(v),max(v)-min(v)))"
cd ..\..\..\..\..
```
📋 **Result:** `0.11 s` — against a 1-second criterion.

### Criterion 4 — Telemetry to flash at configured rate, no missing samples
🎥 **Clip:** `SPIFFS mounted` → `Telemetry task running at 100 ms interval`

📍 **The measurement — now built into the validator:**
```powershell
python tools\validate_integrity.py tools\exports\baseline\linear_topology\trimmed
```
📋 **Screenshot the `info: sample coverage` lines:**
```
info: sample coverage 97.1% of expected (4533 rows over 467s)
info: sample coverage 95.6% of expected (4598 rows over 481s)
```

### Criterion 5 — Full baseline run end-to-end; CSVs retrievable via USB
```powershell
Get-ChildItem tools\exports\baseline\linear_topology\*.csv | Select-Object Name, Length
```
📋 **Screenshot:** 7 files. Point at `_none_` in the names — that's the no-attack baseline.

> ⚠️ **Duration:** your baseline is 8 min (60 s + 300 s + 120 s). Per M4's stated timeline
> (1+5+3+2), a **full** run is 11 min with 10 min of logged phases. Say: *"the baseline phase
> set totals 8 minutes; the full timeline including the attack phase is 11, and our attack runs
> measure 661 seconds end-to-end."*

---

# 🟢 M2 · Application-Layer Attack Modules

### Criterion 1 — Blackhole: drop during attack, normal before/after
```powershell
python tools\validate_integrity.py tools\exports\blackhole\linear_topology\trimmed
```
📋 **Screenshot the arrivals `info:` lines:**
```
info: phase 0 (baseline): 1436 probes from 4 victim(s) over 360s = 3.99/s
info: phase 1 (blackhole): 0 probes reached the root — total drop, the expected attack signature
info: phase 3 (cooldown): 483 probes from 4 victim(s) over 120s = 4.02/s (101% of baseline)
```
> ⚠️ **Say "zero on linear and star r2; one leaked probe on star r1 out of ~720."** Don't claim
> a blanket zero — volunteering the exception is stronger than being asked.

📍 **The attacker's own counters** (the independent second source):
```powershell
cd tools\exports\blackhole\star_topology\trimmed
python -c "import csv,glob;rows=list(csv.DictReader(open(glob.glob('child_node5_*_r1_*telem.csv')[0])));[print('ph%s  probes %5s->%-5s  tx %5s->%-5s  retry %5s->%-5s'%(p,[x for x in rows if x['phase_id']==p][0]['probes_count'],[x for x in rows if x['phase_id']==p][-1]['probes_count'],[x for x in rows if x['phase_id']==p][0]['tx_count'],[x for x in rows if x['phase_id']==p][-1]['tx_count'],[x for x in rows if x['phase_id']==p][0]['retry_count'],[x for x in rows if x['phase_id']==p][-1]['retry_count'])) for p in ['0','1','3']]"
cd ..\..\..\..\..
```
📋 **Result:** `tx 1453→1453` flat during the attack, `retry 2→723`.

### Criterion 2 — Wormhole: duplicates **with measurable latency difference**
```powershell
python tools\validate_integrity.py tools\exports\wormhole\star_topology\trimmed
```
📋 **Screenshot:** `180 of them are DUPLICATE deliveries of 712 unique probes (x1.25) from
F4:2D:C9:73:E6:18 — the expected wormhole signature`

📍 **The latency half — this is the part people forget:**
```powershell
cd tools\exports\wormhole
python -c "import csv,glob,collections,statistics as st;f=glob.glob('linear_topology/trimmed/*_r1_*arrivals.csv')[0];rows=[r for r in csv.DictReader(open(f)) if r['phase_id']=='2'];g=collections.defaultdict(list);[g[(r['src_mac'],r['seq_num'])].append(int(r['latency_us'])) for r in rows];d=[max(v)-min(v) for v in g.values() if len(v)==2];print('%d duplicate pairs, median latency mismatch = %.0f us (%.1f ms)'%(len(d),st.median(d),st.median(d)/1000))"
cd ..\..\..
```
📋 **Result:** `181 duplicate pairs, median latency mismatch = 9768 us (9.8 ms)`

### Criterion 3 — Clean toggle, no leakage into baseline
📋 Same validator output as criterion 1 & 2 — point at **`0` duplicates in phase 0 and phase 3**.

### Criterion 4 — Consistent across all four topologies ⚠️ *2 of 4*
```powershell
python tools\run_matrix.py --status
```
📋 Linear ✅ · Star ✅ · Tree and Partial pending.

---

# 🟡 M3 · Multi-Topology Testbed Deployment

### Criterion 1 & 3 — Converges <60 s · stable through baseline
```powershell
cd tools
python verify_topology.py --dir exports\wormhole\star_topology\trimmed --topology star --attack wormhole --repeat 2 --expect star
cd ..
```
📋 **Screenshot the verdict block:**
```
PASS star: all 5 nodes at layer 2 (direct children of root).
Converged within 60s     : YES
Baseline re-routing free : YES
```

📍 **Do the same for linear** (a structurally opposite topology):
```powershell
cd tools
python verify_topology.py --dir exports\blackhole\linear_topology\trimmed --topology linear --attack blackhole --repeat 3 --expect linear
cd ..
```

> ⚠️ **`star · blackhole · r1` reports `Converged: NO`.** Don't volunteer it. If asked: *"one
> star run doesn't meet it; the next run on the same placement converged inside 60 seconds. We
> haven't established the cause. Every disturbance is in phase 0 — zero during the attack
> window."*

### Criterion 2 — Structure verified by parent-MAC and layer values
📋 The **reconstructed tree** at the top of that same output. Say: *"this is rebuilt from each
node's own `parent_mac` and `layer` columns — not our intended diagram."*

### Criterion 4 — Both attacks show signatures in all four topologies ⚠️ *2 of 4*
```powershell
python tools\run_matrix.py --status
```

### Setup constraint — 5 to 10 nodes, positions documented
📄 **Show:** `LINEAR-RUNBOOK.md` / `STAR-RUNBOOK.md` — the floor-plan diagram and placement
table. 6 nodes, positions fixed and documented per topology.

---

# 🔴 M4 · Phase-Controlled Experiment Execution

### Criterion 1 — At least 24 complete runs ⚠️ *11 of 24*
```powershell
python tools\run_matrix.py --status
```
📋 **This is safe to run live** — 2 seconds, no hardware.

### Criterion 2 — Every run's per-node CSV logs intact
```powershell
python tools\validate_integrity.py tools\exports\wormhole\star_topology\trimmed
```
📋 **Screenshot:** `21 file(s) — 21 PASS, 0 WARN, 0 FAIL`

📄 **And the audit trail:**
```powershell
Get-Content tools\exports\run_ledger.csv | Select-Object -First 5
```

### Criterion 3 — Phase IDs match root's broadcast timeline within tolerance
🎥 **Clip:** `Broadcast phase_id=2  seq=2  label=2  (0 failed sends)`

📍 **The measurement:**
```powershell
cd tools\exports\wormhole\star_topology\trimmed
python -c "import csv,glob;d=[];[d.append([(lambda t:(max(t)-min(t))/1e6)([int(r['timestamp_us']) for r in csv.DictReader(open(f)) if r['phase_id']==p]) for p in ['2','3']]) for f in glob.glob('*_r2_*telem.csv')];print('attack phase spread: %.2f s   cooldown spread: %.2f s'%(max(x[0] for x in d)-min(x[0] for x in d),max(x[1] for x in d)-min(x[1] for x in d)))"
cd ..\..\..\..\..
```
📋 **Result:** `attack phase spread: 0.15 s   cooldown spread: 0.11 s`

### The timeline itself
📄 **Show `components/mesh_common/include/mesh_config.h`:**
```c
#define PHASE_STABILISE_S   60U
#define PHASE_BASELINE_S    300U   /* 5 minutes */
#define PHASE_COOLDOWN_S    120U   /* 2 minutes */
```
> 🗣️ *"1 + 5 + 3 + 2 = 11 minutes, exactly as specified — and our runs measure 661 seconds
> end-to-end. These are compile-time constants, not stopwatch estimates."*

---

# 🟢 M5 · Raw Data Extraction and Integrity Validation

### The stated validation checks
```powershell
python tools\validate_integrity.py tools\exports\wormhole\star_topology\trimmed
```

| Criterion's required check | Where it appears in the output |
|---|---|
| **Sample coverage ≥95%** | `info: sample coverage 97.1% of expected (...)` |
| **Phase labels populated for every row** | label-integrity check — silent when clean |
| **No corruption or premature truncation** | schema width + timestamp monotonicity |

📋 **Screenshot both** the `sample coverage` lines and the `0 FAIL` summary.

### Criterion — Validation report confirms ≥24 clean runs ⚠️ *11 of 24*
```powershell
python tools\run_matrix.py --status
```
> 🗣️ *"Eleven cells validated clean. A cell can't be ticked by hand — `--record` runs the
> validator first and refuses on any failure."*

### Criterion — Any run failing validation is flagged for repeat collection
📄 **Show the guards.** These are your strongest M5 material:

```powershell
python tools\trim_run.py tools\exports\blackhole\star_topology
```
📋 Shows the duplicate/stale detection and the session split.

> 🗣️ *"Three failures during collection each now fail at the moment they happen: a device that
> streamed the wrong file — quarantined, and the board's copy preserved; stale derived files
> after a re-export; and a duplicate capture that double-counted a node with **no error at
> all**. We also added a check today that refuses to record a cell whose files were never
> trimmed — that one had marked a run done against another repeat's data."*

### Extraction with run metadata
```powershell
Get-ChildItem tools\exports\wormhole\star_topology\*.csv | Select-Object -First 3 Name
```
📋 **Point at a filename:**
`child_node5_star_wormhole_r2_20260727_022510_telem.csv`
> 🗣️ *"Role, node, topology, attack, repeat number and collection date — all encoded in the
> filename, which is what the tooling parses."*

### The manifest
```powershell
Get-Content tools\exports\wormhole\star_topology\trimmed\manifest.json | Select-Object -First 8
```
📋 Shows `row_count`, `sha256`, `size_bytes` per file.

---

# ✅ One-shot capture session (~15 min)

Run these in order and screenshot each. That's your entire evidence pack.

```powershell
cd "C:\Users\Angelo Calpoporo\CLionProjects\NIS16-ESP32-Environment"

# M1-1  (ESP-IDF PowerShell)
.\build_all_variants.ps1

# M1-4, M1-5, M2-1, M5
python tools\validate_integrity.py tools\exports\baseline\linear_topology\trimmed
python tools\validate_integrity.py tools\exports\blackhole\linear_topology\trimmed
Get-ChildItem tools\exports\baseline\linear_topology\*.csv | Select-Object Name, Length

# M2-2
python tools\validate_integrity.py tools\exports\wormhole\star_topology\trimmed

# M1-2, M3
cd tools
python verify_topology.py --dir exports\baseline\linear_topology\trimmed --topology linear --attack none --repeat 1 --expect linear
python verify_topology.py --dir exports\wormhole\star_topology\trimmed --topology star --attack wormhole --repeat 2 --expect star
cd ..

# M4, M5
python tools\run_matrix.py --status
Get-Content tools\exports\run_ledger.csv | Select-Object -First 5
Get-Content tools\exports\wormhole\star_topology\trimmed\manifest.json | Select-Object -First 8
```

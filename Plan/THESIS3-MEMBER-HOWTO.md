# THESIS 3 — Member How-To (execution manual)

**Companion to** [THESIS3-TASK-SPLIT.md](THESIS3-TASK-SPLIT.md) (who owns what) and [THESIS3-PANEL-PLAN.md](THESIS3-PANEL-PLAN.md) (why).
**This file is the *how*.** Step-by-step, with real commands, real file paths, and a done-check per task.
**Drafted:** aug. 19, 2026 — DRAFT.

> ⚠️ **Over the 200-line house cap on purpose.** A single detailed manual was requested; splitting it would defeat that. Treat it like the DEFENSE-PREP docs — one file, keep adding.
> **Paths:** repo-relative (`NIS16-ESP32-Environment-semi-final/`) unless the line says otherwise.
> **Line numbers were verified aug. 19, 2026.** If code moved, trust the symbol name over the number.

---

## 0. One-time setup — everyone does this first

```powershell
# Open the "ESP-IDF 5.3 PowerShell" shortcut, NOT a plain terminal.
cd "<repo>\analysis"
pip install -r requirements.txt        # first time only
```

**⚠️ Trim before analysing anything.** Exporting does not trim, and an untrimmed folder still holds the flash session and the export plug-in session. Skipping this makes `verify_topology` WARN and inflates `RSSI_var` from ~13 to ~1386 — a pure artifact that will corrupt every number in M1's audit.

```powershell
python ..\tools\trim_run.py ..\tools\exports\<attack>\<topology> --apply
```

**The pipeline, three stages** (full copy-paste set per attack × topology is already written in `analysis/ANALYSIS-Commands.md` — use it, don't retype):

```powershell
python preprocess.py ../tools/exports/blackhole/linear_topology/trimmed -o blackhole/linear_topology/windowed_dataset.csv
python features.py   ../tools/exports/blackhole/linear_topology/trimmed -o blackhole/linear_topology/feature_table.csv
python eda.py        blackhole/linear_topology/feature_table.csv       -o blackhole/linear_topology/eda_output/
```

**⚠️ Never run `idf.py set-target`** — it silently breaks data logging. This is the repo's single most important rule.

**What a `feature_table.csv` actually contains:** every column of the windowed dataset (`node_role`, `window_start`, `window_idx`, …), plus the 16 Table 4.11 features, plus `Label` (copied from `window_label`, `features.py:846`) and `missing_firmware_fields`. The 16 features, exact spelling (`features.py:891-895`):

```
ForwardingRatio  IngressEgressDelta  RetryRate            PDR
ParentSwitchRate LayerChangeCount    HopStabilityDuration RSSI_mean
RSSI_var         RSSI_stability      RSSI_Hop_Diff        LatencyHopRatio
ConsistencyScore TunnelIntensity     TunnelBytes          TunnelLatency
```

---

## 1. M1 — Data Integrity & Leakage

### Step 0 (do this before A1) — build one pooled dataset

**Why this step exists:** `feature_table.csv` is written **per attack × topology folder**, and it does **not** carry `topology`, `attack`, or `repeat` columns. An audit across all 16 runs needs them, so you have to add them from the folder path yourself. Every task below assumes this pooled file.

```python
# analysis/pool_features.py  (new file — you own it)
import glob, os, pandas as pd
rows = []
for p in glob.glob("*/*/feature_table.csv"):          # e.g. blackhole/linear_topology/feature_table.csv
    attack, topo = p.split(os.sep)[:2]
    df = pd.read_csv(p)
    df["attack"]   = attack                            # baseline | blackhole | wormhole
    df["topology"] = topo.replace("_topology", "")
    df["run_id"]   = f"{attack}-{topo}"
    rows.append(df)
pooled = pd.concat(rows, ignore_index=True)
pooled.to_csv("pooled_features.csv", index=False)
print(pooled.groupby(["attack","topology"]).size())
```

⚠️ **Repeat number is not recoverable from the folder path** — r1/r2/r3 land in the same folder. For **A3 you need it**, so pool from the per-run source CSV filenames instead (they encode `..._r1_...`), or re-run the pipeline per repeat into separate output folders. Decide this before starting A3, not during.

**Done-check:** the printed group counts match the M4 matrix in `STATUS.md` (16 recorded cells, baseline = linear only).

### A1 — Leakage audit

**Question you are answering:** does any single feature already decide the label?

1. Load `pooled_features.csv`. Define the label: `y = (df["Label"] != 0)` — confirm against `preprocess.py`'s `window_label` that non-zero really means "attack window" before you trust a single number.
2. For each of the 16 features, compute three scores:
   - **Univariate AUC** — `sklearn.metrics.roc_auc_score(y, x)` on non-NaN rows; take `max(auc, 1-auc)` so an inverted feature still scores high.
   - **Mutual information** — `sklearn.feature_selection.mutual_info_classif`.
   - **Decision stump accuracy** — `DecisionTreeClassifier(max_depth=1)`, 5-fold cross-validated.
3. Write a table sorted by AUC descending. **Flag every feature ≥ 0.95.**
4. For each flagged feature add one sentence: *is this leakage, or a legitimately strong signal?* PDR collapsing 0.94 → 0.08 is a real physical effect; `ForwardingRatio` being non-NaN only on the attacker is not.

⚠️ **The trap:** dropping NaN rows per feature means each feature is scored on a different subset. A relay-only feature evaluated on attacker rows alone can look perfect for a reason that has nothing to do with signal. **Report the non-NaN row count beside every score** — without it the table is misleading, and a panelist who notices will discount the whole audit.

**Output:** table + one bar chart → `M9-LEAKAGE-AUDIT.md` §1.
**Done-check:** the 5 role-gated features and PDR all appear, each with its support count.

### A2 — Missingness-as-label test

**This is the one that proves P1 quantitatively.** If it works, the dataset is decidable without reading a single measured value.

1. Build an indicator frame: `X = pooled[FEATURES].isna().astype(int)` — 16 binary columns, nothing else.
2. Add `missing_firmware_fields` as a 17th column and note that it exists; it is an even more direct giveaway.
3. Train `LogisticRegression` **and** `DecisionTreeClassifier(max_depth=3)`, 5-fold CV, report accuracy and F1.
4. Print the depth-3 tree. The expected result is a one-question tree: *"is `ForwardingRatio` NaN?"*

**Interpretation to write down:** ~100% accuracy means the label is recoverable from the *shape* of the table, before any measurement is read. That is P1 in its harshest form, and it is a stronger statement than "one feature correlates".
**Done-check:** you can state the accuracy in one sentence to the adviser, with the tree as the evidence.

### A3 — Run-redundancy test

**Question:** do r1, r2, r3 differ by anything other than RF noise?

1. Use the repeat-aware pooling from Step 0.
2. Per cell (e.g. `linear·blackhole`) and per feature, compute pairwise **KS statistic** (`scipy.stats.ks_2samp`) and **Wasserstein distance** (`scipy.stats.wasserstein_distance`) across r1/r2/r3.
3. Build a reference distance: split **one single run** in half by time and compare the halves. That is your noise floor.
4. Compare. If between-repeat distance ≈ within-run distance, the repeats add nothing.

**Why the noise floor matters:** without it, "the distances are small" is an opinion. With it, "between-repeat variation is indistinguishable from within-run variation" is a measurement — and that sentence is what settles adviser Q2 on the fate of the 16 runs.
**Done-check:** one number per cell, plus the floor, in a single table.

### A4 — Balance table

`pooled.groupby(["topology","attack","phase","node_role"]).size().unstack()` → windows per combination.

Report explicitly: **benign = linear r1 only, 1 run against 15.** Do not soften it. The panel asked whether the dataset is balanced; the honest answer right now is no, and stating it first is what makes the fix credible.
**Done-check:** the table's total row count equals `len(pooled)`.

### A5 — Confound check

**Question:** does "high traffic volume" alone reproduce the attack label?

1. Build a volume proxy per window from the windowed dataset — probe/tx counts summed per window, **not** a feature that already encodes forwarding behaviour.
2. Fit a depth-1 stump on that single column. Report accuracy and the threshold it picked.
3. If accuracy is high, write the finding as: *"volume and attack are confounded in the current design — a model can score well without learning anything about routing behaviour."*

**Hand this number to M4 directly.** It is the specification for C4 (the high-load benign class): the class has to be heavy enough to break exactly this threshold.
**Done-check:** M4 has the threshold value written down.

### C7 — Fix the relay-feature gate ⛔ *blocked on adviser Q3* — **hardest item in the plan, joint M1 + M4**

> ⚠️ **Read this before planning C7 as a Python change. It isn't one.** Verified against the firmware aug. 29, 2026 — an earlier draft of this section assumed the fix was widening a mask. It is not.

**What was checked and what it showed:**

1. The gate is the mask at **`features.py:156-157`** — `windowed["node_role"] == "blackhole"` — with the blocked list at `features.py:96-106`.
2. The 11-column telemetry schema (`csv_logger.h:63`) *does* give every node `probes_count`, `tx_count`, `retry_count`. **But the columns mean different things per role.** On an honest victim, `probes_count` counts probes that node *originated* (`victim_main.c:169`, `s_probes_sent++`). On the blackhole attacker, the same column counts packets *received for relay*.
3. The reason for that difference is the blocker: honest victims send with `esp_mesh_send(NULL, &mdata, MESH_DATA_TODS, ...)` (**`victim_main.c:164`**) — "route this to the root" — and the ESP-IDF mesh stack forwards it **below the application layer**. An intermediate node's application code never sees the transit traffic it relays. The attacker only sees it because blackhole victims explicitly address the attacker instead (**`victim_main.c:159`**, `esp_mesh_send(&bh_dest, ...)`), which is what puts those packets in its own relay queue (`blackhole_victim.c:109`).

**So there is no honest-relay forwarding data to un-gate.** The numbers don't exist, anywhere, for any node but the attacker.

**Three ways out — a design decision for the group + adviser, not a coding choice:**

| Option | What it means | Cost |
|---|---|---|
| **1. App-layer relay for everyone** | Every node explicitly addresses its parent instead of using `MESH_DATA_TODS`, so each one observes and counts transit traffic | Firmware change (M4) that alters the traffic model the whole dataset was built on. **All existing runs become non-comparable.** Highest fidelity, highest cost. |
| **2. Infer forwarding, don't measure it** | Reconstruct per-node forwarding from root arrivals + the known topology + per-node send counts | Python only (M1), no recapture. But it is a *derived estimate*, and the paper must say so plainly. |
| **3. Redefine the feature honestly** | Keep the features attacker-only, drop them from any clustering/ML input, and report them separately as attacker-side diagnostics | Cheapest and fully honest. Costs 3 of 16 features as model inputs — which may be fine, since they were never legitimate inputs anyway. |

⚠️ **Option 3 is not a cop-out.** If those columns only ever exist for the attacker, using them as model features *is* the leakage. Removing them is a real fix, not a retreat — and it is the only option that requires no recapture and no firmware risk. Present it to the adviser as a serious candidate, not a fallback.

**Whichever is chosen:** re-run A1 + A2 afterwards. The leakage scores must drop, and that before/after delta *is* deliverable E2.
**Done-check:** A2 accuracy falls from ~100% to near chance, and you can show both numbers side by side with the option you took written next to them.

### Feature-provenance table

One row per feature: name, equation number from Table 4.11, which node roles it is defined for, **why** it is undefined elsewhere, and its NaN rate in the current dataset. The "why" column is the point — today's gating has no written justification anywhere in the repo.

---

## 2. M2 — Attack Provenance & Validation

### A6 — Definitional conformance tables ⭐ start here

Panel-plan §5.1 already drafts both tables. Your job is to verify each row against code and data, not to invent rows.

**Blackhole — verify these against the source:**

| Criterion | Where to check |
|---|---|
| Adversary is on the forwarding path | `child_node/main/blackhole_victim.c` relay task; victims address the attacker via `BLACKHOLE_ATTACKER_MAC` |
| Receives packets (not jamming) | the relay queue receives before deciding — `blackhole_victim.c:190-193` |
| Drops instead of forwarding | **`blackhole_victim.c:194-198`** — `PHASE_ID_BLACKHOLE` → `s_probes_dropped++`, no send |
| Stays protocol-compliant at PHY/MAC | the node stays in the mesh and keeps logging telemetry — show it from its own CSV |
| **Attracts traffic by false route advertisement** | ⚠️ **NO.** Ours is a *placed* relay, configured by MAC. **Declare this.** |
| Observable: PDR collapse while reachable | your own data, 0.94 → 0.08 |

**Wormhole:** same treatment against `wormhole_victim.c`. The weak row is *"creates a false neighbour relationship"* — you must settle it from **parent-switch data**, not assumption. Concretely: pull `ParentSwitchRate` and `LayerChangeCount` for wormhole runs from the feature tables and check whether nodes actually re-parent around the fake link during the attack phase. If they don't, say so.

**How to write the failing rows:** state the criterion, state that the implementation does not meet it, and give the reason in one sentence. A declared miss is credible; a silent omission is what gets a thesis torn apart at 44:30.

**Done-check:** every row has a code reference or a data reference. No row says "presumably".

### Extract the paper's pre-registered prediction

1. Open the approved paper PDF in `Paper/`. Find **§3.4.4 Expected Observable Inconsistencies**, **Table 3.4** (blackhole) and **Table 3.5** (wormhole).
2. Transcribe them **verbatim** into your working doc, with a note of the date they were written.
3. ⚠️ **Do not edit them to match your results.** Put measured values in a column beside them and mark each row match / miss.
4. Also read **§3.3.1.1 / §3.3.2.1 Theoretical Characterization** — the citations B3 needs are likely already there.
5. Verify the body text of **§4.2.1.2 "Forwarding Suppression (Blackhole)"** and **§4.2.1.3 "Topology Distortion (Wormhole-Inspired)"** matches those titles. Confirmed so far: the section titles and table names, **not** the prose.

**Why this is your strongest asset:** a prediction written before capture is a real pre-registration. Very few undergraduate theses have one. Lead with it.

### B3 — Verify sources before citing

Open every one. Do not cite from panel-plan §5A/§5B without opening it.

- **Karlof & Wagner (2003)** — "Secure Routing in Wireless Sensor Networks" — defines both attacks. Start here.
- **Hu, Perrig & Johnson (2003)** — "Packet Leashes" — canonical wormhole.
- **Deng, Li & Agrawal (2002)** — blackhole in ad hoc routing.
- **MITRE CAPEC** — the direct answer to "do you have an online database". Its prerequisites / execution-flow / consequences structure maps straight onto your A6 tables. Record the CAPEC ID.
- **Espressif ESP-WIFI-MESH docs** — non-optional. This bounds what your attack is allowed to claim: you cannot claim to subvert a guarantee the protocol never made.

**The framing to rehearse out loud:** *the sources do not need to be ESP32-specific.* Blackhole and wormhole are defined by adversary behaviour, not by protocol — neither definition mentions a routing protocol at all. You validate **conformance to a definition**, not resemblance to a product.

### A7 — Signature comparison

1. Obtain **WSN-DS** (Almomani et al., 2016) — it has labelled Blackhole and Grayhole classes.
2. Extract its blackhole PDR/delivery collapse over time.
3. Plot it beside yours, **normalised**. Compare four shape properties: abrupt onset at attack start, near-total loss through the adversary, unaffected traffic on other paths, recovery at cooldown.
4. Compare **shapes and ratios, never absolute values** — different radios and protocols mean identical numbers would be suspicious, not reassuring.

A mismatch is as valuable as a match: it tells you something is wrong before the panel does.

### C8 — Attack validation harness

New file `tools/validate_attack.py`, sitting next to `validate_integrity.py` and `verify_topology.py` (read both first — match their CLI and exit-code style).

The reconciliation, per run: **victim sent-counts** (`tx_count` on victim boards) vs **attacker counters** (`probes_count` = received, `tx_count` = forwarded, `retry_count` = dropped, per the mapping documented in `features.py:16-49`) vs **root arrivals** (`*_arrivals.csv`).

Two identities to assert, with a stated tolerance:
```
attacker_received  ≈ Σ victim_sent            (within loss tolerance)
attacker_received  =  attacker_forwarded + attacker_dropped   (exact — same board's counters)
root_arrivals      ≈ attacker_forwarded      (within loss tolerance)
```
Pick the tolerance, justify it from baseline-run loss, and **put it in the paper as a table**. Exit non-zero on failure so it can gate a run.

⚠️ **State the limitation in the same breath:** these are all the attacker's *own* counters. This narrows the circularity, it does not remove it. Only an independent observer does that — which is adviser Q7, and a **hardware purchase with lead time**. Raise it at the first meeting.

### R-B taxonomy brief

One page, for adviser Q8. Quote paper §1.4.1's exclusion of *"grayhole, Sybil, or selective forwarding"*, show that partial drop rates ARE selective forwarding, then lay out the three options from panel-plan §7 R-B with your recommendation. **Deliver it to M4 directly** — C2 is frozen until it lands.

---

## 3. M3 — Scenario, Siting & Environment

### Topology → campus-location map

1. **Read paper §4.2.2 Physical Deployment Topologies first.** Write down what it already says about each topology's physical arrangement — spacing, obstacles, node count.
2. Only then assign campus spaces: corridor → linear, room/lobby → star, multi-floor or wing-and-branch → tree, atrium → partial mesh.
3. **Where your assignment contradicts §4.2.2, the paper wins or the paper gets amended** — pick one explicitly per topology. Do not leave a silent contradiction.
4. Produce a table: topology → named DLSU space → why that space realises that graph shape → what §4.2.2 says → match / amend.

**Done-check:** a panelist reading §4.2.2 and your map together finds no unexplained difference.

### R-A scope amendment + D-5

1. Locate the exact sentence in **§1.4.1**: *"all experiments are conducted in a controlled indoor environment…"* and the matching claim in the abstract.
2. Draft replacement text: the study now deliberately includes environmental variability, **because** the panel asked for it (8:40–8:55).
3. Append **D-5** to `thesis-deviate.md`, matching the existing D-1…D-4 format exactly. Include: what changed, why, which panel comment drove it, what it costs.

**Framing:** this is not an admission of error. It is a documented, justified scope change — which is the only kind a panel accepts.

### B2 — Deployment literature

Search terms: *WSN node deployment strategy*, *IoT testbed topology design*, *attacker placement wireless sensor network*, *smart campus wireless sensor deployment*.

Extract from each paper: node count, physical spacing, what each node transmits, how often, duty cycle, and **how attacker position was chosen** if it is a security paper. Target 2–3 solid sources. Record them in a table with the specific number you are borrowing from each — a citation with no borrowed number is decoration.

### Site scouting + permissions — **start week 1, this has the longest lead time**

Per candidate site, record: mains power for 6 boards + a laptop, a usable surface, hours you can occupy it, who grants permission, booking lead time, and building hours / term-break constraints.

⚠️ **Campus space is shared space.** A corridor empty at 8am and packed at noon is a **variable, not a nuisance** — record time-of-day and crowd level per run or the environment axis becomes uncontrolled noise instead of a finding.

**Send the permission requests before the adviser meeting.** They can be withdrawn; weeks of waiting cannot be recovered.

### Ethics check (Q9)

The paper already has **Appendix B — Research Ethics Forms**. Read what was filed. Then ask the adviser one specific question: *does moving from a private indoor space to public campus spaces require an amendment to what we filed?*

Prepare the safety paragraph either way: the mesh runs on its own `MESH_ID` and does not touch anyone else's network. Cheap to write now, awkward to retrofit after capture.

### Traffic-profile spec — **M4 is blocked until this exists**

A table: node type → message size → interval → burstiness → duty cycle, each cell traceable to a B2 source.

Then compare against what the firmware does today: `PROBE_INTERVAL_MS 1000U` (`mesh_config.h:334`), `PROBE_PAYLOAD_LEN 32U`, `SAMPLING_INTERVAL_MS 100U` (`mesh_config.h:327`). Campus environmental monitoring is periodic low-rate telemetry, so the current 1 Hz probe may already be close — **if so, say so**; a justified "no change needed" is a legitimate and cheap result.

Also write the **high-load benign story** (P7): a class-change surge, a scheduled end-of-day sync, an auditorium event. Real phenomena with a number attached, not "send faster".

### RF-context record + site diagrams

Per run, logged by hand: AP count, channel occupancy, people present, time of day, weather if it matters. A phone Wi-Fi analyser app is sufficient. Hand the field list to M4 so it becomes a **ledger column**, decided before capture rather than inferred afterwards from timestamps.

Per topology, one diagram: measured inter-node distances, obstacles, node roles, and the three attacker positions (near-root / mid / edge) marked. Tape measure and a drawing tool. These go straight into the paper — draw them at publication quality once.

---

## 4. M4 — Firmware, Tooling & Campaign

### C1 — Runtime attacker selection ⭐ **do this first, it is load-bearing**

**The problem:** `mesh_config.h:207` — `#define BLACKHOLE_ATTACKER_MAC {0xB0, 0xCB, ...}`. Only blackhole *victim* builds read it, but it is compiled in, so changing which board is the attacker means **re-flashing every victim board**.

**Option A — NVS (recommended).** ✅ **NVS is already initialised on every board** (`mesh_setup.c`, `root_main.c`, `victim_main.c`, `blackhole_victim.c`, `wormhole_victim.c`) — so this needs no new subsystem.
1. Read the MAC from an NVS key at boot, falling back to the `#define` if the key is absent. Backwards compatible: existing behaviour is unchanged when nothing is set.
2. Add a small write path — a serial command or a provisioning step in `run.ps1`.
3. Still one flash per board, but **the MAC then changes without rebuilding**.

**Option B — broadcast it in the phase message.** `phase_msg_t` (`phase_listener.h:37-42`) is a packed struct of `magic / phase_id / seq_num / timestamp_us`. Adding a 6-byte `attacker_mac` changes the wire format, so **every board must be reflashed once** — after which the root controls attacker identity per run with no reflash at all. Bump `PHASE_MSG_MAGIC` so a mixed-version mesh fails loudly instead of silently misparsing.

**Test before you trust it:** one linear blackhole run with the attacker set to a *different* board than the `#define`, verified from the exported CSVs — the new attacker's counters must show drops and the old one's must not.

⚠️ Editing anything in `components/mesh_common/` means rebuilding **both** `root_node` and `child_node`.

**Deliverable for Milestone 1:** a verdict — feasible or not, which option, and how many hours. If C1 fails, campaign cost roughly triples and the whole matrix must shrink. That answer is needed *at* the meeting.

### C6 — Tooling and ledger

**Current schema** (`tools/exports/run_ledger.csv`): `topology,attack,repeat,status,recorded_at,files` — six columns, which was fine when nothing else varied and will not survive six axes.

Add columns: `attacker_position`, `attacker_mac`, `drop_rate`, `duty_cycle`, `traffic_profile`, `environment`, `seed`, `time_of_day`, `crowd_level`, `firmware_hash`. Take the environment field list from M3 verbatim.

⚠️ **sep. 12, 2026 — `environment` already has a working implementation, not just a spec to invent.** The firmware now records site at `/sdcard/location.txt` (`home`/`G402`/`DLSU_Library`/`Goks`, `mesh_common/src/sd_status.c`), and the ledger + `export_logs.py`/`run_matrix.py`/`run.ps1` already gained a `location` column/flag threaded the same way this section describes for the other five columns (see `run_ledger.csv`'s new column and `MEMORY.md`). M3 should reconcile its field list against this column name (`location` here vs. `environment` above) rather than defining it from scratch — a rename is one `LEDGER_COLS` edit, but two different names for the same concept is a worse outcome.

Then: extend `run.ps1` and `tools/run_matrix.py` with a flag per new column, and replace the run-labelling scheme — filenames encode topology/attack/repeat only today. **Rule to enforce: a run whose full parameter set is not recoverable from its ledger row is an unusable run.**

⚠️ **Seed discipline.** Anything randomised gets a seed recorded in the ledger. "Randomised" is only publishable if it is reproducible.

**Ship C6 before the campaign, not during.** Shorter runs × more variation = far more board handling, which is exactly where the I-017 SPIFFS-overfill hazard and the wrong-run-recorded class of error live.

### C5 — Short-timeline check

Current: 60 s stabilise + 300 baseline + 180 attack + 120 cooldown = **11 min** (`mesh_config.h:129-138`). Proposed: 30 + 90 + 90 + 30 = **4 min**.

Before changing it, ask M1 for the arithmetic on real data: at 5 s windows, a 90 s attack phase gives **18 windows per node**, ~108 across 6 boards. Is that enough for the per-node statistics M8 computes? M1 can answer from the existing runs — get the number, then commit.

### Blocked items — do not start

| Item | Blocked on |
|---|---|
| **C2** blackhole parameterization | ⛔ M2's R-B brief + adviser Q8. Partial drop rates may be **out of scope**. |
| **C3** benign traffic parameters | M3's traffic-profile spec |
| **C4** high-load benign class | M3's story + M1's A5 threshold |
| **D** capture matrix | M3's position map + the B-workstream decisions |

**While blocked, build the variation that is *not* in dispute:** attacker **position** (needs C1), attack **start time**, and **duty cycle**. The 12:45–16:00 comment asked specifically for *"different position of the attackers"* — not different drop rates. That is the lowest-risk reading of the panel's actual words and it does not touch the scope statement.

### Capture-day discipline (when D finally runs)

1. `python tools/board_check.py` before every run — SPIFFS headroom.
2. Run. 3. Export **immediately**: `python tools/export_logs.py`.
4. `python tools/validate_integrity.py` + `tools/verify_topology.py` + M2's `validate_attack.py`.
5. Only after all pass: `trim_run.py --apply`, then record the ledger row.
6. **Only then** wipe for the next run.

⚠️ If a board returns `0 rows` on export, run `tools/recover_spiffs.py` **before** anything wipes it. Raw captures in `tools/exports/` are the thesis's primary evidence and are tracked in git on purpose.

---

## 5. Conventions everyone follows

- **Outputs land in `Plan/` or the repo, never the workstation root.** Analysis scripts go in `analysis/`, tools in `tools/`, planning docs in `Plan/` with a row added to `Plan/INDEX.md`.
- **Every number gets its source.** A figure in the paper traces to a script, which traces to a run in the ledger. If you cannot walk that chain backwards, the number is not usable.
- **Report the ugly numbers first.** The before-fix leakage score, the failed conformance criterion, the 1-vs-15 class imbalance. Panels forgive a declared weakness; they do not forgive a discovered one.
- **Nothing is deleted.** The existing 16 runs are tracked git evidence (`MEMORY.md:11`).
- **When blocked, say so out loud to the person blocking you** — §7 of the task split is a conversation map, not a file drop.
- **After meaningful work:** overwrite `STATUS.md`, add one dated line to `MEMORY.md`, roll completed items to `ARCHIVE.md`.

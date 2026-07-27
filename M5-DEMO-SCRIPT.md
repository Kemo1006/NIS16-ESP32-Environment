# 🎬 M5 — Raw Data Extraction and Integrity Validation (10%)

> ## 📋 Scope + criteria *(quoted)*
> **Extraction:**
> - Pull CSV files from each ESP32 via USB serial after each run.
> - Store with run metadata (topology, attack type, repeat number, collection date).
>
> **Validation script checks:**
> - **Sample coverage** — at least **95 %** of expected samples per node at the configured rate.
> - **Phase labels populated** for every log row.
> - **No file corruption or premature truncation.**
>
> **Criteria:**
> - Validation report confirms **at least 24 clean runs** in the final dataset.
> - Any run failing validation is **flagged for repeat collection**.

## 🎯 Verdict

| Requirement | Result | Status |
|---|---|:--:|
| Pull CSVs via USB serial | `export_logs.py`, 7 files per run | ✅ |
| Store with run metadata | encoded in every filename | ✅ |
| **Check: coverage ≥95 %** | measured **95.5–97.3 %** | ✅ |
| **Check: phase labels every row** | label-integrity check, 0 failures | ✅ |
| **Check: no corruption / truncation** | schema + monotonicity, 0 failures | ✅ |
| ≥24 clean runs | **16 of 24** | ⚠️ |
| Failing runs flagged for repeat | 4 guards, all fire at source | ✅ |

> 🎯 **Framing:** *"Nothing enters the dataset unvalidated."* This is the milestone where you
> demonstrate rigour rather than results — and it pre-answers *"how do we know your data is
> genuine?"*

---

## 📦 EXTRACTION · Pull via USB + store with metadata

### 📍 COMMAND — show the filenames
```powershell
Get-ChildItem tools\exports\wormhole\star_topology\*.csv | Select-Object -First 3 Name
```
```
child_node5_star_wormhole_r2_20260727_022510_telem.csv
   │        │      │        │    │        │       └ kind
   │        │      │        │    │        └ collection time
   │        │      │        │    └ collection date
   │        │      │        └ repeat number
   │        │      └ attack type
   │        └ topology
   └ role + node
```

> 🗣️ *"Every file carries its run metadata **in the filename** — role, node, topology, attack
> type, repeat number and collection date. That's not just for humans: the tooling parses it,
> which is how `--autorecord` knows which matrix cell a capture belongs to."*

### 🎥 CLIP — the export itself
Search your recording for `EXPORT_LOGS`:
```
-> EXPORT_LOGS ...
   [####################] 100.0%  528 KB/469 KB  7301 rows  4 KB/s
   saved 7300 data rows -> ...\child_node5_star_wormhole_r2_...telem.csv
```

---

## ✅ CHECK 1 · Sample coverage ≥ 95 %

### 📍 COMMAND
```powershell
python tools\validate_integrity.py tools\exports\baseline\linear_topology\trimmed
```

### 📋 SCREENSHOT
```
[PASS] child_node2_linear_none_r1_20260725_225635_telem.csv
    info: sample coverage 97.1% of expected (4533 rows over 467s)
[PASS] root_node1_linear_none_r1_20260725_233705_telem.csv
    info: sample coverage 95.6% of expected (4598 rows over 481s)
```

> 🗣️ *"The criterion names a 95 percent floor, so the validator measures it directly — actual
> rows against span times the configured 10 Hz. Across every capture we get **95.5 to 97.3
> percent**. The shortfall is FreeRTOS scheduling jitter, not lost samples, and the root sits
> lowest because it also runs the probe sink and the phase broadcaster."*

💡 Honest detail worth adding: *"this check is separate from phase coverage, which uses a wider
tolerance and targets a different failure — a missing phase. A node logging the whole run at 8
Hz would pass that one and fail this one."*

---

## ✅ CHECK 2 · Phase labels populated for every row

### 📍 COMMAND — same run, look at what passes silently
```powershell
python tools\validate_integrity.py tools\exports\blackhole\linear_topology\trimmed
```
📋 `21 file(s) — 21 PASS, 0 WARN, 0 FAIL` — the label check is one of the five.

### 📄 SHOW the columns it validates
```powershell
Get-Content tools\exports\blackhole\linear_topology\trimmed\child_node2_linear_blackhole_r3_20260726_164256_telem.csv -TotalCount 2
```
```
timestamp_us,...,phase_id,gt_label
4752825,...,0,0
                ↑    ↑
          phase_id  gt_label
```

> 🗣️ *"Every row carries a `phase_id` and a `gt_label`, and the validator checks the label
> against the phase-to-label map on **every row** — baseline and cooldown must be 0, blackhole
> 1, wormhole 2. A single mislabelled row would fail the file."*

---

## ✅ CHECK 3 · No corruption or premature truncation

📋 Same output. Two of the five checks cover this:

| Check | Catches |
|---|---|
| **Schema width** | a truncated or garbled row |
| **Timestamp monotonicity** | an un-split reboot mid-file |

### 📍 COMMAND — show truncation being caught in practice
```powershell
python tools\trim_run.py tools\exports\wormhole\star_topology
```
📋 Screenshot a `[!] repeated capture` block and a session split:
```
[!] repeated capture: 2 header block(s), all telem schema — the export streamed this file 2x.
    session 1: rows 6321  span 661.6s  <-- KEEPING (longest)
```

> 🗣️ *"The firmware appends to one file across boots, so an export contains the run **plus** the
> short session from plugging the board in. `trim_run.py` splits on timestamp regressions — a
> clock going backwards is an unambiguous reboot — and keeps the longest segment. It's a **dry
> run by default** and writes **copies**, so raw captures are never modified."*

---

## ⚠️ CRITERION · Validation report confirms ≥24 clean runs — **16 of 24**

### 📍 COMMAND ⚡ *safe to run live*
```powershell
python tools\run_matrix.py --status
```
```
Progress: 16/24 runs collected (Milestone-4 minimum is 24)
```

### 📄 AND the report behind it
```powershell
Get-Content tools\exports\run_ledger.csv | Select-Object -First 5
```

> 🗣️ *"Sixteen cells validated clean. A cell **can't be ticked by hand** — `--record` runs the
> validator first and refuses on any failure. So this number means sixteen runs whose data passed
> every integrity check, not sixteen attempts."*

---

## ✅ CRITERION · Failing runs flagged for repeat collection ⭐ *your strongest slide*

Four guards, each from a real failure during collection:

| Failure | Guard | Where it fires |
|---|---|---|
| Device streamed the **wrong file** | schema checked at capture; quarantined as `.rejected`, `--delete` suppressed so the board keeps its copy | `export_logs.py` |
| **Stale derived files** after a re-export | flagged when a raw source disappears | `trim_run.py` |
| **Duplicate capture** double-counting a node | flagged before analysis | `trim_run.py` |
| **Cell recorded whose files were never trimmed** | refuses to record; prints the trim command | `run_matrix.py` |

### 📍 COMMAND — show a guard actually firing
```powershell
python tools\run_matrix.py --record --topology tree --attack blackhole --repeat 1
```
📋 Refuses — no capture exists for that cell.

### 📋 The manifest — the audit trail
```powershell
Get-Content tools\exports\wormhole\star_topology\trimmed\manifest.json | Select-Object -First 8
```
```json
{
  "child_node2_star_wormhole_r1_20260727_014200_telem.csv": {
    "row_count": 7080,
    "sha256": "4df9c60cf014bf1bee9c26f128ce0f8afbbc0c1d6ef771c67f284f373d20dd2c",
    "size_bytes": 518330
  }
```

> 🗣️ *"Each of these corrupted a dataset at least once during collection. The duplicate-capture
> one produced **no error at all** — one node counted twice, 264 windows against about 155 for
> every other node, and every total still looked plausible. That's the failure mode that matters
> most for a dataset, because nothing announces it.*
>
> *The fourth we added today: a cell was recorded while its files had never been trimmed, so the
> validator checked a **different repeat's** data and passed. Now it refuses and tells you which
> files are missing.*
>
> *And every validated file is SHA-256 hashed into a manifest — if a byte changes afterwards,
> the next validation fails."*

---

## 🗣️ 90-second script

> *"M5 is extraction and integrity.*
>
> *\[filenames] CSVs are pulled from each board over USB after every run, and stored with the run
> metadata encoded in the filename — topology, attack, repeat, collection date.*
>
> *\[trim output] `trim_run.py` separates the experiment from the export session by splitting on
> timestamp regressions, writing copies so raw captures are never modified.*
>
> *\[validator] The criteria name three checks. Sample coverage: measured at **95.5 to 97.3
> percent** against a 95 percent floor. Phase labels: validated on every row against the
> phase-to-label map. Corruption and truncation: schema width and timestamp monotonicity. Every
> recorded cell is zero-FAIL.*
>
> *\[matrix] Sixteen runs validated clean of twenty-four.*
>
> *\[guards] And failing runs are flagged at source — four guards, each added after a real
> corruption during collection, including one that produced no error at all."*

---

## 🛡️ Questions

**"How do we know the data is genuine?"** → *"Three things. SHA-256 per file in a manifest
written at validation time. A ledger recording when each cell was validated. And the attack
signatures are cross-verified between independent boards — the attacker's counters and the
root's arrivals log agree exactly, on separate devices writing separate files."*

**"Why trim? Isn't that discarding data?"** → *"It separates the run from the export session —
the firmware appends across boots. The raw capture is never modified; trimmed copies go to a
separate folder, and it's a dry run by default so you see what would be dropped first."*

**"You need 24 clean runs and you have 16."** → *"Correct. Sixteen validated clean, zero failures
among them. The validation pipeline is complete and proven — what remains is runtime."*

**"What happens if an export fails halfway?"** → *"The partial capture is saved — more useful
than discarding thousands of good rows — but it's reported as FAILED and the cell won't record.
And the board keeps its copy, because the delete step is skipped on any failure. That's how we
recovered a run where the device streamed the wrong file."*

**"Has a run ever failed validation?"** → *"Yes, and each failure produced a guard. The most
instructive was a duplicate capture that produced **no error at all** — a node counted twice
with plausible-looking totals. That's why the checks now fire at the moment the fault happens
rather than in analysis twenty minutes later."*

**"Could someone tamper with the CSVs after validation?"** → *"They'd fail the next validation —
the manifest hash wouldn't match. And the repository history is version-controlled and
timestamped."*

---

## ✅ Checklist
- [ ] `validate_integrity.py` on **baseline·linear** — coverage lines screenshotted
- [ ] `validate_integrity.py` on **blackhole·linear** — `21 PASS, 0 WARN, 0 FAIL`
- [ ] `trim_run.py` dry run — session split + `[!] repeated capture` visible
- [ ] `manifest.json` first entry — `sha256`, `row_count`, `size_bytes`
- [ ] `run_matrix.py --status` — the 16/24 count
- [ ] `run_ledger.csv` first rows
- [ ] A filename annotated with its metadata fields
- [ ] Four-guards table on a slide *(don't cut — it's the differentiator)*
- [ ] Know: **95.5–97.3 %** · **0 FAIL** · **16/24** · **5 checks** · **4 guards**

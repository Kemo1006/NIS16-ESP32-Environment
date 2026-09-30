# 📦 ARCHIVE Runbook — safely tuck a run away before the next one

> **What this file is:** copy-paste PowerShell to **move a finished run out of the
> live folders** so tomorrow's capture doesn't get mixed in — without ever *deleting*
> your raw data. Works for **any** attack × topology by changing two lines.

---

## 🧠 Why we archive instead of delete

Think of the live folders as your **kitchen counter** 🍳 and the archive as the
**fridge** 🧊:

- Your pipeline **pools every CSV** sitting in `tools\exports\<attack>\<topology>_topology\`
  into one dataset. Leave an old run's CSVs on the counter and tomorrow's run gets
  **stirred into the same pot** → contaminated dataset.
- But raw captures are **irreplaceable** — the boards get `-Wipe`'d for the next run,
  so a deleted capture is **gone forever**.

So the rule is simple: **clear the counter, but put the food in the fridge — don't throw it out.** 🧊

### 🔑 The golden rule of what to MOVE vs COPY
| Thing | Action | Why |
|---|---|---|
| **Raw CSVs** (`tools\exports\...`) | **MOVE** (must leave!) | Irreplaceable + would pool into the next run |
| **Analysis outputs** (`feature_table.csv`, `windowed_dataset.csv`, `eda_output\`) | **MOVE or COPY** (your call) | Auto-overwrite next run anyway — regenerable, so optional |

> ❌ **Never** `Remove-Item` the raw `tools\exports\...` CSVs, and **never** auto-delete
> on every export (it wipes the *other boards'* files from the same run). Archive = safe.

---

## 🎛️ Step 0 — Set your three variables (the ONLY things you change)

Paste this block, editing the three values to match the run you just finished:

```powershell
cd "C:\Users\Angelo Calpoporo\CLionProjects\NIS16-ESP32-Environment"

$Attack   = "blackhole"     # baseline | blackhole | wormhole
$Topology = "linear"        # star | tree | linear | partial
$Label    = "desk-test"     # a short tag for THIS run (e.g. desk-test, run1, actual)
```

> ⚠️ **Partial gotcha:** the export folder for partial is `partial_mesh_topology`, not
> `partial_topology`. The script below handles it automatically — you still just type
> `partial` above.

---

## 🚀 Step 1 — Run the archiver (copy-paste as-is, no edits needed)

```powershell
# resolve the partial folder-name quirk automatically
$topoDir = if ($Topology -eq "partial") { "partial_mesh_topology" } else { "${Topology}_topology" }

$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$base  = "tools\exports\_archive\${stamp}_${Label}\${Attack}_${Topology}"
New-Item -ItemType Directory -Force "$base\raw", "$base\analysis" | Out-Null

# RAW exports -> archive  (MOVE: clears the live folder for the next run)
Move-Item "tools\exports\$Attack\$topoDir\*.csv" "$base\raw\" -Force -ErrorAction SilentlyContinue

# ANALYSIS + EDA outputs -> archive  (MOVE; keeps .gitkeep in place)
Move-Item "analysis\$Attack\$topoDir\feature_table.csv"    "$base\analysis\" -Force -ErrorAction SilentlyContinue
Move-Item "analysis\$Attack\$topoDir\windowed_dataset.csv" "$base\analysis\" -Force -ErrorAction SilentlyContinue
Move-Item "analysis\$Attack\$topoDir\eda_output"           "$base\analysis\" -Force -ErrorAction SilentlyContinue

Write-Host "✅ Archived to: $base"
```

*(Want to keep the analysis outputs in place instead of moving them? Swap the three
`Move-Item` analysis lines for `Copy-Item`. The raw line stays `Move-Item`.)*

---

## ✅ Step 2 — Verify (counter clean, fridge full)

```powershell
Write-Host "=== 🧊 ARCHIVE CONTENTS ==="
Get-ChildItem "$base\raw"
Get-ChildItem "$base\analysis"

Write-Host "=== 🍳 LIVE FOLDERS (should show ONLY .gitkeep) ==="
Get-ChildItem "tools\exports\$Attack\$topoDir" -Force
Get-ChildItem "analysis\$Attack\$topoDir" -Force
```
- **Raw** → `tools\exports\_archive\<stamp>_<label>\<attack>_<topology>\raw\`
- **Analysis** → `...\<attack>_<topology>\analysis\` (`feature_table.csv`, `windowed_dataset.csv`, `eda_output\`)
- **Live folders** → empty except `.gitkeep` ✅ ready for the next run.

---

## 🕹️ Concrete example — the 2026-07-25 linear-blackhole desk test

```powershell
cd "C:\Users\Angelo Calpoporo\CLionProjects\NIS16-ESP32-Environment"
$Attack = "blackhole"; $Topology = "linear"; $Label = "desk-test"
# ...then paste Step 1 + Step 2 exactly as above.
# -> tools\exports\_archive\20260725_HHMMSS_desk-test\blackhole_linear\{raw,analysis}\
```

---

## ⏪ Bonus — restore a run FROM the archive (if you ever need it back)

Say you want to re-analyze an archived run. Point the pipeline straight at the
archived `raw\` folder — no need to move it back:

```powershell
cd "C:\Users\Angelo Calpoporo\CLionProjects\NIS16-ESP32-Environment\analysis"
python features.py "..\tools\exports\_archive\20260725_HHMMSS_desk-test\blackhole_linear\raw" `
    -o blackhole\linear_topology\feature_table.csv
python eda.py blackhole\linear_topology\feature_table.csv -o blackhole\linear_topology\eda_output
```
Or, to physically restore it into the live folder:
```powershell
Move-Item "tools\exports\_archive\<stamp>_<label>\blackhole_linear\raw\*" `
          "tools\exports\blackhole\linear_topology\" -Force
```

---

## 🧭 Quick reference card

| Situation | Do this |
|---|---|
| Finished a run, about to do another **same** attack/topology | **Archive it** (this file) — clears the counter |
| Finished a run, next run is a **different** cell | Optional — folders don't collide, but archiving keeps things tidy |
| Want fresh EDA charts only (no stale per-feature plots) | Deleting `eda_output\` alone is safe (it regenerates) |
| Tempted to delete raw `tools\exports\...` CSVs | 🚫 **Don't** — archive instead; captures are irreplaceable |

> 🧊 **Mantra:** *Clear the counter, fill the fridge.* Raw data gets moved, never thrown out.

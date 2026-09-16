# ANALYSIS-Commands.md — trim → analyse → validate

How to turn captured CSVs in `../tools/exports/` into a feature table, plots, and a
paper-backed attack verdict. **No board needed** — this is all host-side, on data
already exported.

Covers the live-capture path's sibling: during a run, `..\run.ps1 -Analyze` does M6→M7→M8
automatically right after export. This file is for **re-analysing** what's already on disk.

> **Updated 2026-09-16.** Earlier versions of this file used `star_topology`-style folder
> names and predated the `<location>` and `<scenario>` layers. Those paths no longer exist.

What each stage actually computes is in [`analysis_README.md`](analysis_README.md) and
[`analysis_README_2.md`](analysis_README_2.md); this file is just the commands.

**First time on this machine:** `pip install -r requirements.txt`

---

## 1. The short way — `analyze.ps1`

One command does trimming, M6, M7, M8, and (optionally) validation, and it figures out the
folder layout for you. Run it from `ESP32-Environment\`:

```powershell
.\analyze.ps1
```

With no arguments it opens a menu (same style as `menu.ps1`) and lets you pick runs from a
numbered list:

```
  ANALYSIS + VALIDATION  (M6 -> M7 -> M8, 3-sigma verify)
  Captured runs: 2     Analyzed rows: 578 / 10,000
   [1] Analyze ALL captured runs
   [2] Analyze ONE run (pick from list)
   [3] Validate ONE run (3-sigma attack check)
   [4] Analyze + validate ONE run
   [5] Show what is captured (row counts)
   [6] Re-analyze ALL from scratch (clears trimmed/ first)
   [7] Quit
```

Scripted forms, if you'd rather not use the menu:

```powershell
.\analyze.ps1 -List                       # what's captured + row counts, then exit
.\analyze.ps1 -All                        # analyse everything, no prompts
.\analyze.ps1 blackhole linear home       # one run, positional
.\analyze.ps1 -Attack blackhole -Topology linear -Location G402 -Scenario mobility -Verify
```

| Flag | Does |
|---|---|
| `-List` | Table of every captured run + rows analysed + running total. Changes nothing. |
| `-All` | Analyse every captured run without prompting. |
| `-Verify` | Also run `verify_attack.py` on each attack run afterwards. |
| `-SkipTrim` | Skip trimming (use only if you've already trimmed by hand). |
| `-Menu` | Force the menu even when other flags are given. |

`Get-Help .\analyze.ps1 -Full` has the rest.

---

## 2. Where things live

Captures are found at **any depth** under `<attack>/<topology>/`, because a run may or may
not carry a location and a scenario:

```
../tools/exports/<attack>/<topology>/[<location>/][<scenario>/]*_telem.csv
```

- `<attack>` — `baseline` · `blackhole` · `wormhole`
- `<topology>` — `linear` · `star` · `tree` · `partial_mesh`  ← no `_topology` suffix
- `<location>` — e.g. `home`, `G402` (whatever `-Location` was passed)
- `<scenario>` — `burst` · `highload` · `mobility` · `powercycle`.
  **`none` gets no folder at all** — most runs have no scenario segment.

Analysis output mirrors that subpath exactly, under `analysis/`:

```
analysis/<attack>/<topology>/[<location>/][<scenario>/]
    windowed_dataset.csv     M6
    feature_table.csv        M7
    eda_output/              M8 plots + tables
```

`trimmed/` and `_archive/` are **never** treated as captures — `_archive/` holds
superseded SD mirrors, `trimmed/` is derived output.

---

## 3. Trimming — do this before analysing

A raw export still contains the Phase-2 flash session and the export-plug-in session on
top of the real run. Analysing untrimmed data makes `verify_topology.py` WARN and inflates
`RSSI_var` from ~13 to ~1386 — a pure artefact.

`analyze.ps1` trims automatically. By hand:

```powershell
python ..\tools\trim_run.py ..\tools\exports\<attack>\<topology>\<location>\<scenario> --apply
```

- Writes to a **`trimmed\` subfolder** — the raw export is never modified.
- Without `--apply` it's a dry run that just reports what it would keep.
- It keeps the **longest boot session** per file and copies single-session files through
  untouched. The output folder is the complete analysis input.

> **Gotcha — stale files in `trimmed/`.** Re-trimming does not clear the folder first, so
> leftovers from an earlier partial run stay and **every analysis tool will load them**.
> `trim_run.py` prints a `[!] N STALE file(s)` warning when it detects this. Delete the
> `trimmed\` folder and re-trim, or use the menu's option **[6] Re-analyze ALL from
> scratch**, which clears it for you.

---

## 4. Manual M6 → M7 → M8

Only needed if you're debugging a stage or want non-default paths. Run from `analysis\`.
Set `$src` and `$out` once, then the three stages are identical for every run:

```powershell
# EDIT THESE TWO. Drop the trailing segments a given run doesn't have.
$src = "../tools/exports/blackhole/linear/G402/mobility/trimmed"
$out = "blackhole/linear/G402/mobility"

python preprocess.py $src -o "$out/windowed_dataset.csv" --report   # M6
python features.py   $src -o "$out/feature_table.csv"               # M7
python eda.py        "$out/feature_table.csv" -o "$out/eda_output/" # M8
```

Notes:

- **Point M6/M7 at `trimmed/`**, not the raw folder (see §3).
- `--report` on M6 prints the quality report (files loaded/skipped, windows formed vs
  discarded, per-node window counts). Worth reading every time — a node missing from the
  per-node list never made it into the dataset.
- M7 finds `*_arrivals.csv` in the same `$src` folder automatically; `--arrivals-dir` only
  if the root's log lives elsewhere. **No arrivals file ⇒ PDR is NaN for every row** (by
  design — a missing root log is not a delivery failure).
- **One run per folder.** If an export folder pooled several runs (you skipped `-Wipe`, or
  raw SD files were copied in by hand) the tables silently merge them. That exact mistake
  produced a false `BLACKHOLE CONFIRMED` on 2026-09-15.

---

## 5. Validation — `verify_attack.py`

The panel-cited check: 3-sigma normal-vs-attack (Zhukabayeva et al. 2025; blackhole
signature from Airehrour et al. 2018). Compares each run's own attack-phase windows
(`Label 1`) against its benign windows (`Label 0`).

```powershell
python ..\tools\verify_attack.py <path-to>\feature_table.csv --attack blackhole
```

| Flag | Meaning |
|---|---|
| `--attack` | `blackhole` · `wormhole` · `auto` (infer from the Label column). Default `auto`. |
| `--sigma` | Threshold, default `3`. |

Or just let `analyze.ps1` do it: menu option **[3]** / **[4]**, or `-Verify`.

### Reading the output

Each feature is scored `z = (attack_mean − baseline_mean) / baseline_sd`, with an arrow
showing the expected direction (`v` = should fall under attack, `^` = should rise):

| Verdict | Means |
|---|---|
| **PASS** | Moved the expected way by more than 3 sigma — signature present. |
| **FAIL** | Did not clear 3 sigma. Not necessarily broken data — see below. |
| **SKIP** | No usable values in the attack phase for that feature. |

`VERDICT: CONFIRMED` needs a **primary** feature (`ForwardingRatio`, `PDR`) to clear the
bar; the secondary ones are supporting evidence only.

**A FAIL is not automatically a code problem.** The common cause is a noisy *baseline*: if
the benign phase already had erratic delivery, `baseline_sd` is large and nothing can clear
3 sigma. Check the baseline mean ± sd printed in the table — e.g. `PDR 0.164 ± 0.372` means
the run's own control was broken, so the run needs redoing, not the analysis.

`SKIP` on every primary feature means the attack-phase data isn't there at all — check that
all boards exported to the same `-Location`/`-Scenario`, and that the root's
`*_arrivals.csv` is present in the folder.

---

## 6. Other checks worth running

```powershell
python ..\tools\validate_integrity.py          # schema/row sanity across exports
python ..\tools\verify_topology.py             # parents/layers match the intended topology
```

`verify_topology.py` warning about "No root node identified" / "Unresolved parents" is the
classic tell that a folder pooled unrelated sessions.

---

## 7. Two things that look like errors but aren't

- **Red `RuntimeWarning: Mean of empty slice` from numpy.** PowerShell 5.1 renders any
  native-command stderr as a red `NativeCommandError` block. The stage still completed —
  check that the output file exists before assuming it failed.
- **NaN columns.** Several are correct by design, not gaps: `ForwardingRatio` /
  `IngressEgressDelta` / `ConsistencyScore` are relay-node-only (populate on the blackhole
  attacker's windows); `TunnelIntensity` / `TunnelBytes` / `TunnelLatency` are
  wormhole-only; `PDR` is undefined for the **root**, which receives probes rather than
  sending them. "No feature is uniformly NaN" is a claim about the **assembled** dataset
  (16/16 across the matrix), not about any single run. See
  `..\docs\issue_logs\thesis-deviate.md`, "Not deviations".

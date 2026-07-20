# NIS16 Data Pipeline

Preprocessing and feature engineering for the cross-layer ESP32 mesh
intrusion-detection dataset. Covers CTTHES2 Milestones 6 and 7.

> Thesis: *Cross-Layer Dataset Design and Exploratory Analysis of
> ESP32-Based ESP-WIFI-MESH Network* — De La Salle University, CCS.
> Section references below (e.g. "Section 4.2.4.1", "Table 4.10") point
> to the approved thesis document.

> 📖 **This file covers M6 + M7 (preprocessing → features).** The M8 EDA
> stage, the full M6→M8 run recipe, testing, and requirements are in its
> companion **[`analysis_README_2.md`](analysis_README_2.md)** (split out to keep
> each file under 200 lines). Read this first, then that.

> 📂 **Where to run these.** All pipeline scripts (`preprocess.py`, `features.py`,
> `eda.py`, the `generate_*` fixtures) and `requirements.txt` live in this
> `analysis/` folder — `cd` into it first, then run the commands below as written.
> Real captured CSVs live one level up in `../tools/exports/`.

## What's in here

| File | Milestone | What it does |
|---|---|---|
| `preprocess.py` | M6 | Raw `*_telem.csv` files → cleaned, windowed dataset |
| `features.py` | M7 | Windowed dataset → 16-feature table (Table 4.11) |
| `generate_fake_data.py` | both | Synthetic CSVs for testing without real hardware data |

`features.py` imports `preprocess.py` directly (`from preprocess import
run_pipeline`) — both files need to stay in the same folder, and both
need to be on the same version. `run_pipeline()` returns three values
(`windowed`, `report`, `filled`); if you see an error about unpacking
two values into three or vice versa, you have a version mismatch
between the two files — pull both fresh.

## Recommended: capture → features in one step (`run.ps1 -Analyze`)

You don't have to type these commands by hand. From the ESP-IDF PowerShell,
`..\run.ps1 -Analyze` exports a board's CSVs **and then** runs the whole pipeline
for you — M6 (`windowed_dataset.csv`), M7 (`feature_table.csv`), **and** M8/EDA
(`eda_output/`). The raw CSVs stay in `../tools/exports/<attack>/<topology>_topology/`;
all three analysis outputs are written to the mirroring
`analysis/<attack>/<topology>_topology/` folder. Add `-Analyze` on the **last**
board you export (the root), so every node's CSV — plus the root's
`arrivals.csv` that PDR needs — is present when it runs:

```powershell
# victims first (export only), root LAST with -Analyze (exports THEN analyzes):
..\run.ps1 -Port COM25 -Role child  -Attack blackhole -Wipe -Flash -Export
..\run.ps1 -Port COM20 -Role root   -Attack blackhole -Wipe -Flash -Analyze
# -> analysis/blackhole/tree_topology/{windowed_dataset.csv, feature_table.csv, eda_output/}
```

`-Analyze` implies `-Export`. The `analysis/{baseline,blackhole,wormhole}/` tree
(one `<topology>_topology/` subfolder each) mirrors `tools/exports/` exactly, so
each run's outputs land next to where its raw CSVs live. (M8 needs the extra
`requirements.txt` deps — matplotlib/seaborn/scipy/scikit-learn; without them
`-Analyze` does M6+M7 and skips M8.) The commands below are the standalone
fallback (synthetic data, or re-analysing an export without re-flashing).

## Quick start

```bash
cd analysis                     # all scripts + requirements.txt live here
pip install -r requirements.txt

# Generate synthetic test data (skip this once you have real CSVs)
python generate_fake_data.py --output-dir fake_data

# M6: raw CSVs -> windowed dataset
python preprocess.py fake_data -o windowed_dataset.csv

# M7: windowed dataset -> 16-feature table
python features.py fake_data -o feature_table.csv
```

### Manual fallback (re-run analysis on real data without re-flashing)

To (re)build a feature table by hand, point `features.py` at **one run's**
exports subfolder and write into its mirror under `analysis/`:

```bash
# blackhole-on-tree run — M6+M7 then M8:
python features.py ../tools/exports/blackhole/tree_topology \
    -o blackhole/tree_topology/feature_table.csv
python eda.py blackhole/tree_topology/feature_table.csv \
    -o blackhole/tree_topology/eda_output
```

Scripts read a folder **non-recursively**, so each `<attack>/<topology>_topology/`
is one dataset — run them one at a time (a folder may pool multiple runs if you
skipped `-Wipe`). `features.py` re-runs M6 internally (it needs the `windowed`
*and* gap-filled tables, not just the final CSV), so pointing it at a raw-CSV
folder is enough — no separate `preprocess.py` step.

## Where your CSVs need to come from

Both scripts expect the exact file naming and schema written by
`csv_logger.c` in the firmware repo:

- `<node_id>_<run_id>_telem.csv` — every node writes this (11 columns:
  `timestamp_us, node_id, role, layer, parent_mac, rssi_dbm,
  retry_count, tx_count, probes_count, phase_id, gt_label`)
- `<node_id>_<run_id>_arrivals.csv` — **root only** (14 columns: the
  above plus `src_mac, seq_num, latency_us`). Needed for PDR (M7); M6
  runs fine without it, M7's PDR column will just be `NaN` everywhere.

Point both scripts at a folder containing pulled CSVs from all nodes
in a run (or multiple runs — both scripts handle a folder of many runs
at once, distinguishing them via `source_file` and a per-run relative
clock).

## M6 output — `windowed_dataset.csv`

One row per (node, 5-second window). Columns: `window_start, node_id,
source_file, node_role, layer, parent_mac, n_samples_present,
n_samples_expected, rssi_dbm_mean, rssi_dbm_var, rssi_dbm_min,
rssi_dbm_max, retry_count_delta, tx_count_delta, probes_count_delta`
(plus a `_reset_detected` flag alongside each delta column), `
window_label, window_phase_id`.

This is the raw windowed aggregate — means, deltas, event counts. It
deliberately does **not** contain the 16 named features from Table
4.11; that's M7's job, scored separately on the milestones form.

Implements Section 4.2.4.1 exactly:
- per-node timestamp re-basing (each node's clock starts at 0)
- missing-sample handling — linear interpolation (continuous metrics)
  or forward-fill (cumulative counters) for gaps ≤2 samples; longer
  gaps are left unfilled
- non-overlapping 5-second windows (Table 4.10)
- any window with <4 of the expected 5 samples is discarded
- modal phase-label assignment per window

Run `preprocess.py` with `--report` (or just look at the printed
summary, it always prints) to see the discard fraction — the thesis
requires this be reported as a dataset quality metric.

## M7 output — `feature_table.csv`

`windowed_dataset.csv` plus the 16 Table 4.11 feature columns, plus a
`missing_firmware_fields` column.

### Read this before trusting a feature column blindly

Of the 16 features, **11 are real numbers computed from data the
firmware already logs**: `RetryRate`, `PDR`, `ParentSwitchRate`,
`LayerChangeCount`, `HopStabilityDuration`, `RSSI_mean`, `RSSI_var`,
`RSSI_stability`, `RSSI_Hop_Diff`, plus the two raw `RSSI_mean`/`RSSI_var`
M6 already computed (just renamed to match Table 4.12's column names).

**5 are structurally present but currently `NaN` for every row**, for
three different reasons — these are not bugs, they're documented gaps:

1. **`ForwardingRatio`, `IngressEgressDelta`, `ConsistencyScore`** —
   blocked on firmware. Equation 4.2/4.3 need separate `recv_count`
   and `forward_count` for transit packets specifically; the current
   firmware only logs one generic `probes_count`. This resolves once
   the attacker firmware's `recv_counter`/`forward_counter`/
   `drop_counter` state variables (Milestone 2's own deliverable) are
   logged to CSV and wired into `preprocess.py`'s
   `CUMULATIVE_COLUMNS`.
2. **`LatencyHopRatio`** — needs a Mean RTT from a probe/response
   round trip; the current probe design is one-way (victim → root),
   so there's no response leg to time. Would need a firmware change
   to add one, not just a logging change.
3. **`TunnelIntensity`, `TunnelBytes`, `TunnelLatency`** — correctly
   `NaN`/attacker-only per the thesis's own Table 4.12 note ("present
   only for attacker nodes during topology-distortion runs"). These
   populate once `attacker_node/` firmware exists and logs tunnel
   counters.

Every NaN column is still emitted with the correct name, so the
milestone criterion "feature table contains all 16 columns" is met
structurally. "All 16 columns exist" and "all 16 columns currently
have real numbers" are different claims — check
`missing_firmware_fields` (or the NaN-count summary `features.py`
prints after running) before assuming a column is populated.

### A note on PDR specifically

PDR distinguishes two situations that could easily get conflated:

- A node the root **has never logged anything for** in a run → `PDR`
  is `NaN`. This is a coverage gap (wrong topology, node never
  associated, root CSV wasn't pulled, etc.) — not a delivery problem.
- A node the root **does** have data for, but zero arrivals landed in
  one particular window → `PDR` is `0.0`. This is the real blackhole
  signature.

If you ever see a blackhole run come out with `NaN` instead of `0.0`
during the attack window, that's a real regression — `features.py`'s
`generate_blackhole_pdr_fixtures()` test fixture exists specifically
to catch it.

---

➡️ **Continue in [`analysis_README_2.md`](analysis_README_2.md)** for M8 (the five
EDA analyses from §4.2.6), the full M6→M8 run recipe, testing, and requirements.

# NIS16 Data Pipeline

Preprocessing and feature engineering for the cross-layer ESP32 mesh
intrusion-detection dataset. Covers CTTHES2 Milestones 6 and 7.

> Thesis: *Cross-Layer Dataset Design and Exploratory Analysis of
> ESP32-Based ESP-WIFI-MESH Network* — De La Salle University, CCS.
> Section references below (e.g. "Section 4.2.4.1", "Table 4.10") point
> to the approved thesis document.

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

## Quick start

```bash
pip install -r requirements.txt

# Generate synthetic test data (skip this once you have real CSVs)
python generate_fake_data.py --output-dir fake_data

# M6: raw CSVs -> windowed dataset
python preprocess.py fake_data -o windowed_dataset.csv

# M7: windowed dataset -> 16-feature table
python features.py fake_data -o feature_table.csv
```

`features.py` re-runs the M6 pipeline internally (it needs `windowed`
*and* the intermediate gap-filled table, not just the final CSV), so
you can run it directly on a raw CSV folder without running
`preprocess.py` first — that's not redundant, it's `features.py` doing
M6 silently as a setup step before doing M7's actual work.

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

## M8 output — `eda_output/` (plots + tables)

`eda.py` implements the five analyses from thesis Section 4.2.6 against
`feature_table.csv` (M7's output):

1. **Descriptive statistics** — `descriptive_statistics.csv` (whole
   dataset) and `descriptive_statistics_by_phase.csv` (broken out by
   baseline/blackhole/wormhole) — mean, median, variance, min, max,
   and NaN fraction per feature.
2. **Distribution visualization** — `distribution_<feature>.png` for
   `ForwardingRatio`, `RetryRate`, `RSSI_Hop_Diff` (the three the
   thesis names), each a histogram + box plot stratified by phase and
   node role.
3. **Time-series plots** — `timeseries_<run_id>.png`, one figure per
   run with `ParentSwitchRate` and `PDR` trajectories for every node in
   that run overlaid, attack windows shaded in red.
4. **Cross-layer correlation** — `correlation_pearson.png/.csv` and
   `correlation_spearman.png/.csv`.
5. **PCA / t-SNE** — `dimensionality_reduction.png`, z-score
   standardized first per Equation 4.18, colored by ground-truth label.

```bash
python eda.py feature_table.csv -o eda_output/
```

### Inherited from M7: 5 of 16 feature columns are still NaN

Every one of the five analyses above touches at least one of the NaN
columns from M7 (see M7's section above for why they're NaN).
`eda.py` handles this consistently rather than crashing or silently
dropping the analysis:

- Analysis #2's `distribution_ForwardingRatio.png` still gets
  generated — it just shows a labeled "no data available" placeholder
  instead of an empty plot that looks like nothing ran.
- Analyses #4 and #5 automatically exclude any column that's all-NaN
  (correlation and PCA/t-SNE are mathematically undefined on them
  otherwise) and print/label exactly which columns were excluded, so
  the exclusion is never silent. This generalizes Section 4.2.5.1's own
  documented tunnel-feature exclusion option to all currently-NaN
  columns, not just the tunnel ones.
- Once M2's firmware closes the `recv_count`/`forward_count` gap and
  those columns start having real values, re-running `eda.py` against
  fresh `feature_table.csv` output picks them up automatically — the
  exclusion list is computed from which columns are actually all-NaN
  at run time, not hardcoded.

### Two real bugs found while building this — both now covered by `generate_eda_fake_data.py`

The M6/M7 test fixtures (`generate_fake_data.py`) are small,
targeted unit tests — they don't have enough rows or label diversity
to make a distribution plot or PCA projection show anything
meaningful. `generate_eda_fake_data.py` builds a larger synthetic
dataset (324 rows, 4 synthetic runs, all three labels, with
baseline/attack separation modeled on the thesis's own stated expected
ranges — Section 4.3.1.2's baseline retry rate <5% and PDR ~0.97) so
the plots can be checked against data that's actually supposed to show
something.

Two bugs only became visible once real plots were inspected:

1. **Time-series grouping bug.** `plot_time_series()` originally
   grouped by `source_file`, but every node writes its own file, so
   each node ended up alone in its own figure — defeating the entire
   point of the analysis (seeing whether phase transitions align
   *across* nodes within one run). Fixed by extracting the run ID from
   the filename and grouping on that instead.
2. **Correlation heatmap title clipping.** The excluded-columns list
   in the plot title ran past the figure edge and got cut off
   mid-word. Fixed with explicit text wrapping.

If a future change makes `timeseries_*.png` start producing one file
per node again instead of one per run, that's bug #1 coming back.

## Full pipeline, M6 → M7 → M8

```bash
pip install -r requirements.txt

python generate_fake_data.py --output-dir fake_data           # M6/M7 unit-test fixtures
python generate_eda_fake_data.py -o eda_fake_data/feature_table.csv  # M8-scale fixture

python preprocess.py fake_data -o windowed_dataset.csv
python features.py fake_data -o feature_table.csv
python eda.py eda_fake_data/feature_table.csv -o eda_output/
```

## Testing

`generate_fake_data.py` produces 9 synthetic CSVs (7 telemetry files +
2 arrivals files) covering: clean baseline data, a node with injected
1s and 3s gaps (tests the interpolate-vs-discard logic), a run with a
real phase transition (tests modal-label assignment), a node with a
mid-window layer/parent switch (tests `ParentSwitchRate`/
`LayerChangeCount`/`HopStabilityDuration`), and two matched
victim/root pairs — one where every probe arrives, one simulating a
blackhole drop (tests PDR's coverage-vs-zero distinction described
above).

```bash
python generate_fake_data.py --output-dir fake_data
python preprocess.py fake_data -o windowed_dataset.csv
python features.py fake_data -o feature_table.csv
```

Both pipelines are deterministic — running either twice against the
same input folder produces byte-identical output. If a change you
make breaks that, something is iterating over an unordered Python
`set` or `dict` somewhere; that's the exact bug class that bit this
codebase once already (see git history / commit messages around the
`CUMULATIVE_COLUMNS` tuple-not-set comment in `preprocess.py`).

## Requirements

See `requirements.txt`. Developed against pandas 3.0.2 / numpy 2.4.4;
should work on any reasonably recent pandas 2.x/3.x.

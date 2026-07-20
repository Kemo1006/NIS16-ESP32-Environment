# NIS16 Data Pipeline — M8 EDA, running end-to-end, testing

> ⬅️ **Back to [`analysis_README.md`](analysis_README.md)** — the first half
> (overview, M6 preprocessing, M7 feature engineering + the feature-column
> caveats). This file is the back half: the **M8 EDA stage**, the full M6→M8 run
> recipe, testing, and requirements. Split out to keep each file under 200 lines.
> Read `analysis_README.md` first (M6/M7), then this.

> 📂 **All commands below run from the `analysis/` folder** (where `eda.py` and the
> `generate_*` scripts live). `cd analysis` first. Real captured CSVs are one level
> up in `../tools/exports/`.

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
- Analysis #5 (PCA/t-SNE) **also excludes role-exclusive sparse columns**
  (NaN fraction > 50%). Several features are defined for only ONE role —
  `ForwardingRatio`/`IngressEgressDelta`/`ConsistencyScore` on the attacker,
  `PDR` on victims — so no single window is non-NaN in all of them at once.
  Without this, `dropna` across a common matrix wiped **every** row and the
  projection came out an empty red placeholder. Now the broadly-defined
  cross-layer features project over the windows that share them (e.g. a
  blackhole run cleanly separates baseline vs attack victim windows in t-SNE).
  The excluded columns are split into "all-NaN" vs "role-sparse" in the plot
  subtitle so the reason is explicit.
- Once M2's firmware closes the `recv_count`/`forward_count` gap and
  those columns start having real values, re-running `eda.py` against
  fresh `feature_table.csv` output picks them up automatically — the
  exclusion list is computed from which columns are actually all-NaN
  at run time, not hardcoded.

### Wormhole tunnel features now populate (M7)

`TunnelIntensity` and `TunnelBytes` are computed for the wormhole attacker
endpoints (`node_role` `wormhole_a`/`wormhole_b`) from the tunnel-message
counts their firmware logs into the shared schema (Node B `retry_count` =
frames tunnelled, Node A `probes_count` = frames received). They stay NaN for
victim/root and for baseline/blackhole runs, and ~0 in a wormhole run's
baseline phase — matching Table 4.12's "null or zero for all other nodes and
phases". `TunnelLatency` stays NaN by design: the A↔B UART tunnel is one-way,
so no round trip exists to time.

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

> 💡 **One-step shortcut:** `..\run.ps1 -Analyze` runs all three stages into the
> right `analysis/<attack>/<topology>_topology/` folder automatically (see the
> "Recommended" section of [`analysis_README.md`](analysis_README.md)). The
> commands below are the manual equivalent — synthetic fixtures, or re-analysing
> an existing export by hand without re-flashing.

```bash
cd analysis
pip install -r requirements.txt

# --- synthetic fixtures (no hardware needed) ---
python generate_fake_data.py --output-dir fake_data                 # M6/M7 unit-test fixtures
python generate_eda_fake_data.py -o eda_fake_data/feature_table.csv # M8-scale fixture
python preprocess.py fake_data -o windowed_dataset.csv
python features.py   fake_data -o feature_table.csv
python eda.py        eda_fake_data/feature_table.csv -o eda_output/
```

### Real captured data — one `<attack>/<topology>_topology/` at a time

Outputs **mirror the exports tree**: read
`../tools/exports/<attack>/<topology>_topology/` and write into the matching
`analysis/<attack>/<topology>_topology/`. Those output folders already exist (the
scaffold ships a `.gitkeep`; `eda.py` creates its own `eda_output/`), so no
`mkdir` is needed. `<attack>` = `baseline | blackhole | wormhole`; `<topology>` =
`star | tree | linear | partial_mesh`.

```bash
# --- BASELINE on the tree topology — M6 -> M7 -> M8 ---
python preprocess.py ../tools/exports/baseline/tree_topology -o baseline/tree_topology/windowed_dataset.csv   # M6
python features.py   ../tools/exports/baseline/tree_topology -o baseline/tree_topology/feature_table.csv      # M7
python eda.py        baseline/tree_topology/feature_table.csv -o baseline/tree_topology/eda_output/           # M8

# --- BLACKHOLE on the tree topology (same pattern, swap baseline -> blackhole) ---
python preprocess.py ../tools/exports/blackhole/tree_topology -o blackhole/tree_topology/windowed_dataset.csv
python features.py   ../tools/exports/blackhole/tree_topology -o blackhole/tree_topology/feature_table.csv
python eda.py        blackhole/tree_topology/feature_table.csv -o blackhole/tree_topology/eda_output/
```

For any other run, substitute the `<attack>` and `<topology>_topology` names on
**both** the input (`../tools/exports/…`) and output paths — e.g.
`baseline/partial_mesh_topology`, `wormhole/star_topology`.

Run all three steps (don't collapse to `features` → `eda`). `features.py` re-runs
M6 internally, so the 2-step form still *computes* the same thing — but running
`preprocess.py` explicitly is what writes the M6 deliverable
`windowed_dataset.csv` and prints the **window discard-fraction quality report**
the thesis requires you to report. M6 is graded separately, so produce its artifact.

The scripts read a folder **non-recursively**, and there is **one dataset per
`<topology>_topology/` folder**, so run each attack/topology as its own pass into
its own output folder — never point a single `eda.py` run at two runs at once. The
blackhole set is where `PDR`'s real `0.0` attack signature shows up (vs. the
baseline/wormhole runs where it stays near 1.0).

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

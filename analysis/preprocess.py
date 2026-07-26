"""
preprocess.py — NIS16 Milestone 6: Cross-Layer Data Preprocessing Pipeline

Converts raw per-node CSV telemetry logs (1 Hz samples) into a clean,
windowed, analyzable DataFrame.

Implements thesis Section 4.2.4.1 "Preprocessing" and Table 4.10
"Window Aggregation":
  - Per-node timestamp re-basing (each node's clock starts at 0)
  - Missing-sample handling (interpolate / forward-fill / discard, per the
    rules in Section 4.2.4.1 "Handling Missing Values")
  - Cumulative-counter → per-window delta conversion (Equation 4.1)
  - 5-second non-overlapping window aggregation (Table 4.10)
  - Modal phase-label assignment per window (ground truth for downstream
    clustering — Milestone 8 onward)
  - Window-completeness threshold: discard any window with < 4 of the
    expected 5 one-second samples (Section 4.2.4.1, point 4)

This module is deliberately decoupled from real hardware: it operates on
any folder of CSVs matching the schema written by csv_logger.c, so it can
be developed and unit-tested against synthetic data (see generate_fake_data.py)
while Milestone 1 hardware bring-up is still in progress.

Scope note: this script produces the *windowed aggregate* table (raw
per-window statistics — means, deltas, event counts). The 16 named
features from Table 4.11 (ForwardingRatio, RetryRate, PDR, etc.) are
Milestone 7's responsibility and are computed from this table's output,
not inside it. Keeping the boundary here matches how the two milestones
are scored separately on the CTTHES2 milestones form.
"""

from __future__ import annotations

import argparse
import glob
import os
import re
import sys
from dataclasses import dataclass, field

# Windows consoles default to a codepage (e.g. cp1252) that can't encode the
# box-drawing characters (─) used in the printed quality report below.
# Reconfigure to UTF-8 so this script's own diagnostic output never crashes
# the run after the real work (the output CSV) is already written.
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

import numpy as np
import pandas as pd

# ─────────────────────────────────────────────────────────────────────────
# Constants — kept here rather than scattered through the code so any
# future window-length sensitivity analysis (CTTHES3) only touches one
# place.
# ─────────────────────────────────────────────────────────────────────────

WINDOW_SECONDS = 5                  # Table 4.10
EXPECTED_SAMPLES_PER_WINDOW = 5     # 1 Hz logging rate × 5 s window
MIN_VALID_SAMPLES = 4               # Section 4.2.4.1 point 4 — discard if < 4
MAX_INTERP_GAP_SAMPLES = 2          # "gap of 1-2 consecutive missing samples"
EPSILON = 1e-6                      # Equation 4.2 divide-by-zero guard
MAX_SESSION_SECONDS = 24 * 3600    # 86400 — captures run for minutes, so a
                                   # per-node relative time beyond a full day
                                   # means a corrupt timestamp_us (esp_timer
                                   # glitch), not real data. See _fill_node_gaps.
# HARD CEILING on the dense 1 Hz reindex grid, in rows. This is a safety
# tripwire, not a tuning knob: the sole place this pipeline can allocate an
# unbounded array is the per-node reindex in _fill_node_gaps, and a corrupt
# timestamp once made it try to allocate ~30 GiB and freeze the machine. Legit
# per-node grids are <= MAX_SESSION_SECONDS+1 rows (86401), so this ceiling is
# never hit by real data; if it ever would be, we refuse to densify instead of
# risking the host's memory. 500k int64 rows is ~a few MB — trivially safe.
MAX_GRID_ROWS = 500_000

# Columns that are CUMULATIVE counters (monotonically increasing on the
# node) — these get delta-converted per window (Equation 4.1).
# Columns NOT in this set are treated as CONTINUOUS metrics (mean/var/min/max).
#
# NOTE: this is a tuple, not a set. Iteration order over a Python set is
# not guaranteed stable across runs/processes, and the thesis requires
# "pipeline is deterministic — same inputs always produce the same
# output" (Milestone 6 criteria). Using sets here silently violated that
# by reordering output columns between runs even though row values were
# identical. Membership tests (`col in CUMULATIVE_COLUMNS`) work fine on
# a tuple, so nothing else needs to change.
CUMULATIVE_COLUMNS = (
    "retry_count",
    "tx_count",
    "probes_count",
    "probes_received",
)

# Columns that are CONTINUOUS metrics — aggregated as mean/var/min/max
# per window rather than delta'd. Same ordering note as above.
CONTINUOUS_COLUMNS = (
    "rssi_dbm",
)

# Columns carried through as metadata / identity — not aggregated
# numerically, just used for grouping or taken as the first value in
# the window. Tuple for the same determinism reason as above.
IDENTITY_COLUMNS = (
    "node_id", "role", "layer", "parent_mac",
)

# Schema columns the firmware always writes as integers. A non-numeric value
# in any of these means the row is contaminated (see _coerce_and_drop_malformed)
# and must be dropped before any numeric step. node_id/role/parent_mac are
# genuinely textual, so they're deliberately excluded here.
NUMERIC_COLUMNS = (
    "timestamp_us", "layer", "rssi_dbm",
    "retry_count", "tx_count", "probes_count",
    "phase_id", "gt_label",
)


@dataclass
class PreprocessReport:
    """
    Quality-tracking record. Thesis Section 4.2.4.1 explicitly requires
    that "the fraction of discarded windows is reported as a dataset
    quality metric" — this dataclass is that report.
    """
    files_loaded: int = 0
    files_skipped: list[str] = field(default_factory=list)
    rows_dropped_malformed: int = 0
    rows_dropped_downsampled: int = 0
    rows_dropped_corrupt_timestamp: int = 0
    raw_rows_total: int = 0
    windows_total: int = 0
    windows_discarded_incomplete: int = 0
    windows_discarded_gap: int = 0
    windows_kept: int = 0
    per_node_window_counts: dict[str, int] = field(default_factory=dict)

    def discard_fraction(self) -> float:
        if self.windows_total == 0:
            return 0.0
        discarded = self.windows_discarded_incomplete + self.windows_discarded_gap
        return discarded / self.windows_total

    def summary(self) -> str:
        lines = [
            "── Preprocessing Quality Report ──────────────────────────",
            f"  Files loaded:               {self.files_loaded}",
            f"  Files skipped (bad/empty):  {len(self.files_skipped)}",
            f"  Rows dropped (contaminated):{self.rows_dropped_malformed}",
            f"  Rows dropped (corrupt ts):  {self.rows_dropped_corrupt_timestamp}",
            f"  Rows downsampled to 1Hz grid: {self.rows_dropped_downsampled} "
            f"(expected — see current SAMPLING_INTERVAL_MS in thesis-deviate.md)",
            f"  Raw rows ingested:          {self.raw_rows_total}",
            f"  Windows formed:             {self.windows_total}",
            f"  Windows discarded (<4 smp): {self.windows_discarded_incomplete}",
            f"  Windows discarded (gap>2s): {self.windows_discarded_gap}",
            f"  Windows kept:               {self.windows_kept}",
            f"  Discard fraction:           {self.discard_fraction():.1%}",
        ]
        if self.files_skipped:
            lines.append(f"  Skipped files: {self.files_skipped}")
        lines.append("  Per-node window counts:")
        for node, count in sorted(self.per_node_window_counts.items()):
            lines.append(f"    {node}: {count}")
        lines.append("───────────────────────────────────────────────────────────")
        return "\n".join(lines)


# ─────────────────────────────────────────────────────────────────────────
# Step 1 — Load raw CSVs
# ─────────────────────────────────────────────────────────────────────────

_REPEAT_RE = re.compile(r"_r(\d+)_\d{8}_\d{6}_(?:telem|arrivals)\.csv$")


def _repeat_from_filename(source_file: str):
    """Pull the M4 repeat number out of an export filename, or NaN.

    An analysis folder deliberately holds all three repeats at once (the M4
    matrix counts them by the _r1_/_r2_/_r3_ tag), and this loader globs the
    whole folder — so every window from r1, r2 and r3 lands in one table with
    no way to tell them apart. That is fine for M8 separability, which pools
    benign vs attack windows regardless of run, but it makes per-repeat
    variance impossible to recover downstream: a reader can always pool, but
    cannot un-pool.

    Carrying the repeat as its own column costs nothing and keeps the dataset
    usable for reproducibility questions ("does the signature hold across
    runs?") that the pooled table cannot answer. NaN for any file that does
    not follow the export naming convention.
    """
    m = _REPEAT_RE.search(source_file or "")
    return int(m.group(1)) if m else np.nan


def load_raw_telemetry(input_dir: str, report: PreprocessReport) -> pd.DataFrame:
    """
    Load every *_telem.csv file in input_dir into one long DataFrame.

    Each row is one 1 Hz telemetry sample from one node. Probe-arrival
    files (*_arrivals.csv, root-only) are intentionally NOT loaded here —
    PDR computation (Milestone 7) joins them separately on
    (src_node_id, seq_num), per the thesis's "Implementation note" under
    the Feature Engineering milestone.
    """
    pattern = os.path.join(input_dir, "*_telem.csv")
    files = sorted(glob.glob(pattern))

    if not files:
        raise FileNotFoundError(
            f"No *_telem.csv files found in {input_dir!r}. "
            f"Expected files like NODE_AABBCC..._RUN_001_telem.csv "
            f"(see csv_logger.c naming convention)."
        )

    frames = []
    for fp in files:
        try:
            df = pd.read_csv(fp)
        except (pd.errors.EmptyDataError, pd.errors.ParserError) as e:
            report.files_skipped.append(os.path.basename(fp))
            print(f"  [WARN] Skipping unreadable file {fp}: {e}", file=sys.stderr)
            continue

        if df.empty:
            report.files_skipped.append(os.path.basename(fp))
            print(f"  [WARN] Skipping empty file {fp}", file=sys.stderr)
            continue

        required_cols = {
            "timestamp_us", "node_id", "role", "layer", "parent_mac",
            "rssi_dbm", "retry_count", "tx_count", "probes_count",
            "phase_id", "gt_label",
        }
        missing = required_cols - set(df.columns)
        if missing:
            report.files_skipped.append(os.path.basename(fp))
            print(
                f"  [WARN] Skipping {fp}: missing columns {missing}",
                file=sys.stderr,
            )
            continue

        df["_source_file"] = os.path.basename(fp)
        frames.append(df)
        report.files_loaded += 1

    if not frames:
        raise ValueError(
            "All discovered files were skipped (empty/unreadable/malformed). "
            "Nothing to preprocess."
        )

    raw = pd.concat(frames, ignore_index=True)
    raw = _coerce_and_drop_malformed(raw, report)
    report.raw_rows_total = len(raw)
    return raw


def _coerce_and_drop_malformed(
    raw: pd.DataFrame, report: PreprocessReport
) -> pd.DataFrame:
    """
    Force the schema's numeric columns to numbers and drop any row where one
    failed to parse.

    Such rows are contamination, not real samples: an ESP-IDF log line printed
    asynchronously over the same UART (a mesh ``<assoc>``/``[SCAN]`` event, etc.)
    gets interleaved into the CSV during serial export, so the row's fields shift
    and a numeric column ends up holding a text token like ``" channel:11"`` or
    ``" MAP:0"``. Even one such value makes pandas type the whole column as
    ``object``, which then blows up interpolation downstream (``TypeError: Series
    cannot interpolate with object dtype``). The firmware always writes every
    numeric field as an integer, so a non-numeric value there means the row isn't
    a genuine 1 Hz sample — dropping it keeps a single stray log line from
    aborting the entire run, consistent with this pipeline's skip-bad-input,
    report-the-count philosophy.

    Clean data is unaffected: with no non-numeric tokens nothing is dropped and
    the already-integer columns coerce back to the same dtype, so output stays
    byte-identical (the determinism criterion).

    The drop count (and, on request, the affected filenames) is recorded on
    `report` rather than raised as a `warnings.warn()` — this can legitimately
    fire on every real capture (any stray async log line interleaved over the
    shared UART during export), so it belongs in the one-line quality summary
    every run already prints, not as a console warning per run.
    """
    coerced = raw.copy()
    bad_mask = pd.Series(False, index=coerced.index)
    for col in NUMERIC_COLUMNS:
        if col not in coerced.columns:
            continue
        as_num = pd.to_numeric(coerced[col], errors="coerce")
        # Flag only values that were present but un-parseable (a genuinely
        # empty cell stays NaN and is handled later as a normal missing sample).
        bad_mask |= as_num.isna() & coerced[col].notna()
        coerced[col] = as_num

    n_bad = int(bad_mask.sum())
    if n_bad:
        report.rows_dropped_malformed += n_bad
        coerced = coerced.loc[~bad_mask].reset_index(drop=True)

    return coerced


# ─────────────────────────────────────────────────────────────────────────
# Step 2 — Per-node timestamp re-basing
# ─────────────────────────────────────────────────────────────────────────

def rebase_timestamps(raw: pd.DataFrame) -> pd.DataFrame:
    """
    "Per-node timestamp re-basing (each node's clock starts at 0)."

    timestamp_us comes from esp_timer_get_time() on each board, which
    starts counting from that board's own boot, not a shared wall clock.
    We convert to seconds and subtract each node's own first sample so
    every node's timeline starts at t=0, then window on that relative
    time. This sidesteps needing real cross-node clock alignment (the
    thesis notes phase-broadcast markers are used for that offline step,
    which is a separate, optional refinement layered on top of this if
    multi-node drift turns out to matter empirically).
    """
    df = raw.copy()
    df["timestamp_s"] = df["timestamp_us"] / 1_000_000.0
    df = df.sort_values(["node_id", "timestamp_s"]).reset_index(drop=True)

    node_start = df.groupby("node_id")["timestamp_s"].transform("min")
    df["t_rel"] = df["timestamp_s"] - node_start

    return df


# ─────────────────────────────────────────────────────────────────────────
# Step 3 — Missing-sample handling (per-node, before windowing)
# ─────────────────────────────────────────────────────────────────────────

def _fill_node_gaps(node_df: pd.DataFrame, report: PreprocessReport) -> pd.DataFrame:
    """
    Apply the thesis's missing-value rules to one (node, run) timeline,
    operating on a synthetic 1 Hz grid built from t_rel (Table 4.10 windows
    are defined at 1 Hz regardless of the firmware's raw sampling rate — see
    SAMPLING_INTERVAL_MS / thesis-deviate.md; a faster raw rate, e.g. the
    current 20 Hz, is downsampled to this grid, not resampled to match it).

    Continuous metrics (rssi_dbm): linear interpolation for gaps of
    1-2 consecutive missing samples; longer gaps are left as NaN (the
    window-level discard logic in build_windows() handles those).

    Cumulative counters: forward-fill for gaps <= 2s (counter assumed
    unchanged — Section 4.2.4.1 point 2); longer gaps left as NaN, also
    handled by window-level discard.

    Note: this must be called per (node_id, run) pair, not just per
    node_id — a node's t_rel resets to 0 at the start of every run, so
    grouping by node_id alone across multiple concatenated runs would
    produce duplicate t_rel values and corrupt the reindex below. The
    caller (handle_missing_values) enforces this grouping.
    """
    import warnings
    node_df = node_df.copy()
    t_int = node_df["t_rel"].round().astype(int)

    # Guard against a corrupt timestamp. A single garbage timestamp_us value
    # (e.g. 4.0e15 µs seen from an esp_timer glitch) survives numeric coercion
    # but makes t_int.max() astronomical, so the RangeIndex/reindex below tries
    # to allocate tens of GiB and aborts the run (numpy _ArrayMemoryError). Real
    # captures span minutes; drop any sample whose relative time exceeds
    # MAX_SESSION_SECONDS before the grid is built. Anchored on min(), which is a
    # legitimate small value (the outlier is a large positive, unsigned micros).
    span_ok = (t_int - t_int.min()) <= MAX_SESSION_SECONDS
    if not span_ok.all():
        n_bad = int((~span_ok).sum())
        node_id_val = node_df["node_id"].iloc[0] if "node_id" in node_df.columns else "?"
        report.rows_dropped_corrupt_timestamp += n_bad
        warnings.warn(
            f"[preprocess] {node_id_val}: dropped {n_bad} sample(s) with a corrupt "
            f"timestamp_us (relative time > {MAX_SESSION_SECONDS}s — esp_timer glitch). "
            f"This should never happen on real data — investigate the source file."
        )
        node_df = node_df.loc[span_ok]
        t_int = t_int.loc[span_ok]

    if t_int.duplicated().any():
        # Two or more raw samples can round to the same integer second —
        # expected whenever the firmware's raw sampling rate is faster than
        # the 1 Hz analysis grid (current rate: see SAMPLING_INTERVAL_MS /
        # thesis-deviate.md), plus ordinary esp_timer jitter on top. Keep the
        # row closest to its integer second, discard the rest. This preserves
        # the 1 Hz grid Table 4.10 windows are defined on. Expected to fire on
        # every real capture at rates > 1 Hz, so it's tallied on `report` and
        # shown once in the quality summary rather than warned per node/file.
        node_df["_t_int"] = t_int
        node_df["_t_frac_err"] = (node_df["t_rel"] - t_int).abs()
        node_df = (
            node_df
            .sort_values(["_t_int", "_t_frac_err"])
            .drop_duplicates(subset="_t_int", keep="first")
            .sort_values("_t_int")
        )
        n_dropped = len(t_int) - len(node_df)
        report.rows_dropped_downsampled += n_dropped
        t_int = node_df["_t_int"]
        node_df = node_df.drop(columns=["_t_int", "_t_frac_err"])

    # Build the dense 1 Hz grid — but never allocate an absurd one. The outlier
    # drop above already bounds the span to MAX_SESSION_SECONDS, so this ceiling
    # is a belt-and-suspenders tripwire: even if some future/edge path let a huge
    # span through, we refuse to densify (which is what tried to grab ~30 GiB and
    # froze the laptop) and fall back to the observed timestamps only, so the
    # allocation can never exceed the number of real samples.
    grid_rows = int(t_int.max()) - int(t_int.min()) + 1
    if grid_rows > MAX_GRID_ROWS:
        node_id_val = node_df["node_id"].iloc[0] if "node_id" in node_df.columns else "?"
        warnings.warn(
            f"[preprocess] {node_id_val}: dense 1 Hz grid would be {grid_rows:,} "
            f"rows (> MAX_GRID_ROWS={MAX_GRID_ROWS:,}) — corrupt timestamps. "
            f"Refusing to densify; using observed timestamps only, no gap-fill."
        )
        full_index = pd.Index(sorted(t_int.unique()))
    else:
        full_index = pd.RangeIndex(t_int.min(), t_int.max() + 1)

    grid = node_df.set_index(t_int).reindex(full_index)

    for col in CONTINUOUS_COLUMNS:
        if col in grid.columns:
            grid[col] = grid[col].interpolate(
                method="linear", limit=MAX_INTERP_GAP_SAMPLES, limit_area="inside"
            )

    for col in CUMULATIVE_COLUMNS:
        if col in grid.columns:
            grid[col] = grid[col].ffill(limit=MAX_INTERP_GAP_SAMPLES)

    for col in IDENTITY_COLUMNS:
        if col in grid.columns:
            grid[col] = grid[col].ffill().bfill()

    if "phase_id" in grid.columns:
        grid["phase_id"] = grid["phase_id"].ffill().bfill()
    if "gt_label" in grid.columns:
        grid["gt_label"] = grid["gt_label"].ffill().bfill()

    grid["t_rel"] = grid.index.astype(float)
    grid["_was_missing"] = node_df.set_index(t_int).reindex(full_index)[
        "timestamp_us"
    ].isna()

    return grid.reset_index(drop=True)


def handle_missing_values(df: pd.DataFrame, report: PreprocessReport) -> pd.DataFrame:
    """
    Apply _fill_node_gaps() independently per (node_id, run).

    Grouping must include the source file (one file = one run for one
    node) rather than node_id alone, because t_rel resets to 0 at the
    start of every run — two runs from the same node concatenated
    together would otherwise collide on relative timestamp.
    """
    filled = []
    for (node_id, source_file), group in df.groupby(["node_id", "_source_file"]):
        filled.append(_fill_node_gaps(group, report))
    return pd.concat(filled, ignore_index=True)


# ─────────────────────────────────────────────────────────────────────────
# Step 4 — Window aggregation (Table 4.10)
# ─────────────────────────────────────────────────────────────────────────

def _modal_label(series: pd.Series):
    """
    Modal phase-label assignment per window. pandas mode() can return
    multiple values on a tie; we take the first (earliest-occurring in
    sort order) deterministically so the pipeline stays reproducible,
    per the thesis's "Pipeline is deterministic" criterion.
    """
    series = series.dropna()
    if series.empty:
        return np.nan
    modes = series.mode()
    return modes.iloc[0]


def build_windows(df: pd.DataFrame, report: PreprocessReport) -> pd.DataFrame:
    """
    Aggregate the gap-filled 1 Hz samples into non-overlapping 5-second
    windows per node, applying Table 4.10's aggregation rules:

      Continuous metrics    → mean, variance, min, max per window
      Cumulative counters   → delta per window (Equation 4.1)
      Event counts          → total events per window
      Phase label           → modal value per window

    Windows with fewer than MIN_VALID_SAMPLES valid (non-imputed-beyond-gap)
    samples are discarded, per Section 4.2.4.1 point 4.
    """
    df = df.copy()
    df["window_idx"] = (df["t_rel"] // WINDOW_SECONDS).astype(int)
    df["window_start"] = df["window_idx"] * WINDOW_SECONDS

    rows = []

    for (node_id, source_file, window_idx), wdf in df.groupby(
        ["node_id", "_source_file", "window_idx"]
    ):
        report.windows_total += 1

        n_present = (~wdf["_was_missing"]).sum()
        n_total = len(wdf)

        # Discard rule: fewer than MIN_VALID_SAMPLES actually-observed
        # samples (out of the expected EXPECTED_SAMPLES_PER_WINDOW).
        if n_present < MIN_VALID_SAMPLES:
            report.windows_discarded_incomplete += 1
            continue

        # Discard rule: any single gap inside this window longer than
        # MAX_INTERP_GAP_SAMPLES consecutive missing samples invalidates
        # the whole window (can't reliably interpolate/ffill across it).
        missing_flags = wdf.sort_values("t_rel")["_was_missing"].to_numpy()
        max_run = _max_consecutive_true(missing_flags)
        if max_run > MAX_INTERP_GAP_SAMPLES:
            report.windows_discarded_gap += 1
            continue

        row = {
            "window_start": wdf["window_start"].iloc[0],
            "node_id": node_id,
            "source_file": source_file,
            "run_repeat": _repeat_from_filename(source_file),
            "node_role": wdf["role"].mode().iloc[0] if not wdf["role"].mode().empty else wdf["role"].iloc[0],
            "layer": wdf["layer"].mode().iloc[0] if "layer" in wdf and not wdf["layer"].mode().empty else np.nan,
            "parent_mac": wdf["parent_mac"].iloc[-1] if "parent_mac" in wdf else None,
            "n_samples_present": int(n_present),
            "n_samples_expected": EXPECTED_SAMPLES_PER_WINDOW,
        }

        # Continuous metrics: mean / var / min / max
        for col in CONTINUOUS_COLUMNS:
            if col not in wdf.columns:
                continue
            vals = wdf[col].dropna()
            row[f"{col}_mean"] = vals.mean() if len(vals) else np.nan
            row[f"{col}_var"] = vals.var(ddof=0) if len(vals) > 1 else 0.0
            row[f"{col}_min"] = vals.min() if len(vals) else np.nan
            row[f"{col}_max"] = vals.max() if len(vals) else np.nan

        # Cumulative counters: delta = last - first valid value in window
        # (Equation 4.1). If the window also includes one sample from
        # just before window start due to ffill carry-in, that's fine —
        # we delta strictly within this window's own valid samples.
        wdf_sorted = wdf.sort_values("t_rel")
        for col in CUMULATIVE_COLUMNS:
            if col not in wdf_sorted.columns:
                continue
            vals = wdf_sorted[col].dropna()
            if len(vals) >= 2:
                delta = vals.iloc[-1] - vals.iloc[0]
                # Counters are monotonic; a negative delta means a
                # device reboot occurred mid-window (counter reset).
                # Flag rather than silently emit a negative value.
                row[f"{col}_delta"] = max(delta, 0)
                row[f"{col}_reset_detected"] = delta < 0
            elif len(vals) == 1:
                row[f"{col}_delta"] = 0
                row[f"{col}_reset_detected"] = False
            else:
                row[f"{col}_delta"] = np.nan
                row[f"{col}_reset_detected"] = False

        # Event counts: total events in window. layer_change_count and
        # parent_switch counts are derived in Milestone 7 from the raw
        # layer/parent_mac sequence; this pipeline carries the raw
        # per-sample layer/parent sequence forward implicitly via the
        # underlying long-format table, so M7 can recompute event counts
        # without needing them duplicated here.

        row["window_label"] = _modal_label(wdf["gt_label"])
        row["window_phase_id"] = _modal_label(wdf["phase_id"])

        rows.append(row)

    report.windows_kept = len(rows)

    windowed = pd.DataFrame(rows)
    if not windowed.empty:
        for node_id, count in windowed["node_id"].value_counts().items():
            report.per_node_window_counts[str(node_id)] = int(count)

    return windowed


def _max_consecutive_true(flags: np.ndarray) -> int:
    """Length of the longest run of True values in a boolean array."""
    if flags.size == 0:
        return 0
    max_run = run = 0
    for f in flags:
        run = run + 1 if f else 0
        max_run = max(max_run, run)
    return max_run


# ─────────────────────────────────────────────────────────────────────────
# Step 5 — Orchestration
# ─────────────────────────────────────────────────────────────────────────

def run_pipeline(
    input_dir: str,
) -> tuple[pd.DataFrame, PreprocessReport, pd.DataFrame]:
    """
    Full pipeline entry point. Accepts a folder of raw *_telem.csv files,
    returns (windowed_dataframe, quality_report, gap_filled_long_df).

    The third return value is the gap-filled long-format table (one row
    per node per second, post missing-value-handling, pre-windowing).
    Milestone 6 itself only needs the first two — the windowed output is
    the M6 deliverable. The long-format table exists for Milestone 7,
    which needs the raw per-sample (layer, parent_mac) SEQUENCE to detect
    transitions (ParentSwitchRate, LayerChangeCount, HopStabilityDuration)
    — information that is necessarily lost once samples are collapsed to
    one modal value per 5-second window. Returning it here avoids
    re-running steps 1-3 a second time inside the M7 module.
    """
    report = PreprocessReport()

    raw = load_raw_telemetry(input_dir, report)
    rebased = rebase_timestamps(raw)
    filled = handle_missing_values(rebased, report)
    windowed = build_windows(filled, report)

    return windowed, report, filled


# ─────────────────────────────────────────────────────────────────────────
# CLI
# ─────────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(
        description="NIS16 Milestone 6 — Cross-Layer Data Preprocessing Pipeline"
    )
    parser.add_argument(
        "input_dir",
        help="Folder containing raw *_telem.csv files (one or more experiment runs)",
    )
    parser.add_argument(
        "-o", "--output",
        default="windowed_dataset.csv",
        help="Output path for the windowed CSV (default: windowed_dataset.csv)",
    )
    parser.add_argument(
        "--report",
        action="store_true",
        help="Print the quality report to stdout after running",
    )
    args = parser.parse_args()

    print(f"Loading raw telemetry from: {args.input_dir}")
    windowed, report, _ = run_pipeline(args.input_dir)

    windowed.to_csv(args.output, index=False)
    print(f"Wrote {len(windowed)} windowed rows to: {args.output}")

    if args.report or True:  # always show report — it's cheap and useful
        print()
        print(report.summary())


if __name__ == "__main__":
    main()

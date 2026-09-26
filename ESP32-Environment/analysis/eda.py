"""
eda.py — NIS16 Milestone 8: Exploratory Data Analysis

Implements the five analyses specified in thesis Section 4.2.6:

  1. Descriptive statistics — mean/median/variance/range per feature,
     across all nodes and phases.
  2. Distribution visualization — histograms/box plots for
     ForwardingRatio, RetryRate, RSSI-Hop Diff, stratified by phase
     and node role.
  3. Time-series plots — selected feature trajectories (parent switch
     events, PDR) over run duration.
  4. Cross-layer correlation analysis — Pearson and Spearman matrices
     across PHY/MAC/Network features.
  5. Dimensionality reduction — PCA and t-SNE projections, per Section
     4.2.5.1's normalization spec (z-score standardize before either).

Per the thesis: "EDA ... is strictly descriptive; no inferential claims
or detection rules are derived from this stage." This module produces
plots and tables; it does not draw conclusions or set thresholds.

────────────────────────────────────────────────────────────────────────
INHERITED SCOPE NOTE — read this before trusting any plot blindly
────────────────────────────────────────────────────────────────────────
Three of the five analyses the thesis names use features that are
currently NaN for every row, because the underlying firmware doesn't
log the fields they need yet (see features.py's module docstring for
the full explanation — short version: ForwardingRatio, IngressEgressDelta,
and ConsistencyScore need a recv_count/forward_count split the firmware
doesn't currently provide; LatencyHopRatio needs a round-trip response
leg the probe protocol doesn't have).

Analysis #2 (distribution viz) is explicitly specified against
ForwardingRatio by name in the thesis text — one of its three named
features is currently empty. This module still produces that plot, but
it will show "no data" rather than silently being skipped, so the gap
stays visible rather than vanishing from the output.

Analysis #4 (correlation) and #5 (PCA/t-SNE) both default to EXCLUDING
the NaN columns automatically — not because the thesis says to drop
them, but because correlation coefficients and PCA/t-SNE are
mathematically undefined on all-NaN columns, and Section 4.2.5.1
itself offers exactly this kind of exclusion as a documented option
("auxiliary tunnel features may be excluded before normalization").
This module generalizes that allowance to all currently-NaN columns,
not just the tunnel ones, and labels every output with which columns
were excluded and why.

When the firmware fields these features depend on are added (M2's
attacker counters, primarily), re-running this module against fresh
feature_table.csv output will pick the columns up automatically — no
code change needed here, since exclusion is computed from which
columns are actually all-NaN at run time, not from a hardcoded list.
────────────────────────────────────────────────────────────────────────

Usage:
    python eda.py feature_table.csv -o eda_output/
"""

from __future__ import annotations

import glob
import os
import sys
import textwrap
import warnings

# Windows consoles default to a codepage (e.g. cp1252) that can't encode the
# box-drawing characters (─) used in the printed summaries below. Reconfigure
# to UTF-8 so this script's own diagnostic output never crashes the run after
# all the real work (CSVs/plots) is already done. No-op on Python < 3.7 or
# non-console stdout (piped/redirected), where reconfigure isn't available.
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

import matplotlib
matplotlib.use("Agg")  # headless — no display required, just writes files
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
import seaborn as sns
from scipy import stats
from sklearn.decomposition import PCA
from sklearn.manifold import TSNE
from sklearn.preprocessing import StandardScaler

sns.set_theme(style="whitegrid")

# Host-side leakage guard. leakage.py owns the single definition of which
# columns a MODEL may see; this module only consumes it. See its docstring for
# the panel comment (2:40-4:50) that made it necessary. Imported by path
# because eda.py is run as a script from analyze.ps1, not as a package module.
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import leakage  # noqa: E402

# The 16 Table 4.11 feature names, in the order the thesis presents them.
# Used to decide which columns count as "features" for stats/correlation/
# PCA purposes, as opposed to identity/metadata columns like node_id.
FEATURE_COLUMNS = [
    "ForwardingRatio", "IngressEgressDelta", "RetryRate", "PDR",
    "ParentSwitchRate", "HopChangeCount", "HopStabilityDuration",
    "RSSI_mean", "RSSI_var", "RSSI_stability",
    "RSSI_Hop_Diff", "LatencyHopRatio", "ConsistencyScore",
    "TunnelIntensity", "TunnelBytes", "TunnelLatency",
]

# Layer grouping for the correlation analysis (Section 4.2.6: "PHY, MAC,
# and Network layer features"). Cross-layer features aren't assigned a
# single layer; they're left out of the per-layer grouping but still
# appear in the full correlation matrix.
LAYER_GROUPS = {
    "PHY": ["RSSI_mean", "RSSI_var", "RSSI_stability"],
    "MAC": ["RetryRate"],
    "Network": [
        "ForwardingRatio", "IngressEgressDelta", "PDR",
        "ParentSwitchRate", "HopChangeCount", "HopStabilityDuration",
    ],
}

LABEL_NAMES = {0: "Baseline", 1: "Blackhole", 2: "Wormhole"}

# Plain-language axis text, so a plot can be read without opening features.py.
# Windows are 1 s (preprocess.WINDOW_SECONDS), so "per window" = "per second".
FEATURE_DESCRIPTIONS = {
    "ForwardingRatio": "forwarded ÷ received per 1 s window (>1 = backlog from the previous window)",
    "ForwardingRatio_5w": "forwarded ÷ received, summed over the last 5 windows",
    "RootArrivals": "probes arriving at the root per window",
    "IngressEgressDelta": "packets received − forwarded",
    # App-layer (D-15): retry_count = failed esp_mesh_send() calls, not 802.11
    # retransmissions - the paper's "MAC" name is what Table 4.5 must amend.
    "RetryRate": "failed sends ÷ send attempts (0–1, app-layer)",
    "PDR": "share of probes that reached the root (0–1)",
    "ParentSwitchRate": "parent changes per second",
    "HopChangeCount": "tree-depth changes in the window",
    "HopStabilityDuration": "longest run with same parent & depth (s)",
    "RSSI_mean": "mean signal strength to parent (dBm)",
    "RSSI_var": "signal strength variance (dBm²)",
    "RSSI_stability": "longest run within ±3 dBm of the mean (s)",
    "RSSI_Hop_Diff": "|RSSI − baseline median for this depth| (dB)",
    "LatencyHopRatio": "relative one-way delay per hop",
    "ConsistencyScore": "|ForwardingRatio − 1|",
    "TunnelIntensity": "tunnelled packets per second",
    "TunnelBytes": "tunnelled bytes per second",
    "TunnelLatency": "delay added by the tunnel",
}

# preprocess.py's `segment` column, shown by name. Only baseline/attack/cooldown
# carry a ground-truth label; the rest are NaN in Label by design and were
# previously plotted as a class literally called "nan".
SEGMENT_DISPLAY = {
    "pre_baseline": "Pre-baseline (unlabelled)",
    "baseline": "Baseline",
    "cooldown": "Cooldown (after attack)",
    "baseline_rebroadcast": "Rebroadcast (unlabelled)",
    "no_phase_seen": "No phase seen (unlabelled)",
}
PHASE_ORDER = [
    "Baseline", "Blackhole attack", "Wormhole attack", "Cooldown (after attack)",
    "Pre-baseline (unlabelled)", "Rebroadcast (unlabelled)",
    "No phase seen (unlabelled)", "Unlabelled",
]
PHASE_COLORS = {
    "Baseline": "#1f77b4",
    "Blackhole attack": "#d62728",
    "Wormhole attack": "#9467bd",
    "Cooldown (after attack)": "#ff7f0e",
}
UNLABELLED_COLOR = "#9e9e9e"
# Why a feature that is flat across every labelled window is a finding, printed
# on its distribution plot so the empty-looking figure explains itself.
FLAT_RESULT_NOTES = {
    "RetryRate": ("No send failed in baseline, attack or cooldown: the attacker still\n"
                  "accepts every frame, so a victim's send never fails (paper 3.3.1.2).\n"
                  "Table 3.4 predicted a rise - a pre-registered MISS to report\n"
                  "(docs/EXPECTED-RESULTS.md 6a)."),
}
# PCA/t-SNE input is standardised, then clipped to +-this many sd (see
# run_dimensionality_reduction for why).
PCA_Z_CLIP = 5.0
# A distribution plot draws its KDE curve only when every phase has at least
# this many distinct values (see plot_distributions).
MIN_KDE_DISTINCT = 5
# Fixed per role so "victim" is the same colour in every figure; seaborn's
# default assigns colours by first appearance, which differs per feature.
ROLE_COLORS = {"victim": "#4c72b0", "child": "#4c72b0", "root": "#55a868", "blackhole": "#dd8452",
               "wormhole": "#8172b3", "wormhole_entry": "#8172b3",
               "wormhole_exit": "#937860"}


def _phase_names(df: pd.DataFrame) -> pd.Series:
    """
    One readable phase name per row: "Baseline", "Blackhole attack",
    "Cooldown (after attack)", "Pre-baseline (unlabelled)", ...

    Uses preprocess.py's `segment` column when present, because Label alone
    folds cooldown into Baseline (both 0) and shows every unlabelled window as
    NaN. Falls back to Label for older tables without a segment column.
    """
    label_col = "Label" if "Label" in df.columns else "window_label"
    labels = pd.to_numeric(df[label_col], errors="coerce")
    attack = labels.map(lambda v: f"{LABEL_NAMES.get(v, str(v))} attack"
                        if pd.notna(v) and v != 0 else None)
    if "segment" in df.columns:
        seg = df["segment"].astype(str)
        names = seg.map(SEGMENT_DISPLAY)
        names = names.where(seg != "attack", attack)
        return names.fillna("Unlabelled")
    return labels.map(lambda v: "Unlabelled" if pd.isna(v)
                      else ("Baseline" if v == 0
                            else f"{LABEL_NAMES.get(v, str(v))} attack"))


def _is_unlabelled(name: str) -> bool:
    return name not in PHASE_COLORS and not name.endswith(" attack")


def _phase_order_palette(names) -> tuple[list[str], dict]:
    present = set(names)
    order = [p for p in PHASE_ORDER if p in present]
    order += sorted(present - set(order))
    palette = {p: PHASE_COLORS.get(p, UNLABELLED_COLOR if _is_unlabelled(p) else "#2ca02c")
               for p in order}
    return order, palette


def _axis_label(feat: str) -> str:
    desc = FEATURE_DESCRIPTIONS.get(feat)
    return f"{feat}\n{desc}" if desc else feat


def _leaking_for(df: pd.DataFrame) -> set[str]:
    """Columns kept out of correlation and PCA for THIS dataset.

    leakage.leaking_columns_for(), not the fixed LEAKING_COLUMNS: since C7 every
    node relays, so ForwardingRatio / IngressEgressDelta are real multi-role
    measurements and leakage.py's own audit already treats them that way. The
    fixed list dropped the one primary signature that measures the attacker.
    ConsistencyScore stays out whenever ForwardingRatio is in: it IS
    |ForwardingRatio - 1| (Eq 4.15), so keeping both adds a duplicate axis and a
    correlation that is the formula, not the network.
    """
    out = set(leakage.leaking_columns_for(df))
    if "ForwardingRatio" not in out:
        out.add("ConsistencyScore")
    return out


def _ensure_dir(path: str):
    os.makedirs(path, exist_ok=True)


def _detect_allnan_columns(df: pd.DataFrame, columns: list[str]) -> list[str]:
    """
    Columns that are NaN for every row in df, among the given candidate
    list. Computed fresh each run (not hardcoded) so this automatically
    adapts once firmware gaps close and a column starts having real data.
    """
    return [c for c in columns if c in df.columns and df[c].isna().all()]


# ─────────────────────────────────────────────────────────────────────────
# 1. Descriptive statistics
# ─────────────────────────────────────────────────────────────────────────

def descriptive_statistics(df: pd.DataFrame) -> pd.DataFrame:
    """
    Mean, median, variance, min, max, and NaN fraction for each of the
    16 Table 4.11 features, across the whole dataset (all nodes, all
    phases combined) — this is the "identify baseline ranges and detect
    potential logging anomalies" pass the thesis describes, not a
    per-phase breakdown (that's analysis #2).
    """
    present = [c for c in FEATURE_COLUMNS if c in df.columns]
    rows = []
    for col in present:
        series = df[col]
        n_valid = series.notna().sum()
        rows.append({
            "feature": col,
            "mean": series.mean(),
            "median": series.median(),
            "variance": series.var(),
            "min": series.min(),
            "max": series.max(),
            "n_valid": int(n_valid),
            "n_total": len(series),
            "nan_fraction": 1.0 - (n_valid / len(series)) if len(series) else np.nan,
        })
    return pd.DataFrame(rows)


def descriptive_statistics_by_phase(df: pd.DataFrame) -> pd.DataFrame:
    """
    Same statistics as above, but broken out per ground-truth label
    (baseline/blackhole/wormhole) AND node role — useful for spotting which
    features shift between phases before formal distribution plots.

    Per role because a phase-only mean describes no real node: on G402
    (sep. 25, 2026) "attack ForwardingRatio 0.80" averaged the attacker's 0.0
    with every honest relay's ~1.0.
    """
    present = [c for c in FEATURE_COLUMNS if c in df.columns]
    label_col = "Label" if "Label" in df.columns else "window_label"
    keys = [label_col] + (["node_role"] if "node_role" in df.columns else [])

    rows = []
    for key, group in df.groupby(keys):
        label_val, role = (key if isinstance(key, tuple) else (key,)) + ((None,) if len(keys) == 1 else ())
        label_name = LABEL_NAMES.get(label_val, str(label_val))
        for col in present:
            series = group[col]
            n_valid = series.notna().sum()
            if not n_valid:
                continue    # a feature undefined for this role is not a statistic
            rows.append({
                "label": label_name,
                "node_role": role,
                "feature": col,
                "mean": series.mean(),
                "median": series.median(),
                "variance": series.var(),
                "n_valid": int(n_valid),
                "n_total": len(series),
            })
    return pd.DataFrame(rows)


# ─────────────────────────────────────────────────────────────────────────
# 2. Distribution visualization
# ─────────────────────────────────────────────────────────────────────────

def plot_distributions(
    df: pd.DataFrame,
    output_dir: str,
    features: list[str] | None = None,
) -> list[str]:
    """
    Histogram + box plot, stratified by phase label and node role, for
    the features the thesis names explicitly: ForwardingRatio,
    RetryRate, RSSI-Hop Diff (Section 4.2.6). Defaults to exactly those
    three; pass `features` to plot others.

    If a named feature is entirely NaN (e.g. ForwardingRatio right now),
    the plot is still produced — it will show empty axes with a visible
    "no data available" annotation rather than being silently skipped.
    Skipping it would make the gap invisible; showing an empty labeled
    plot keeps it visible exactly where the thesis says this analysis
    should exist.
    """
    if features is None:
        features = ["ForwardingRatio", "ForwardingRatio_5w", "RetryRate", "RSSI_Hop_Diff"]

    role_col = "node_role" if "node_role" in df.columns else "role"

    written = []
    for feat in features:
        if feat not in df.columns:
            warnings.warn(f"plot_distributions: '{feat}' not in dataframe, skipping")
            continue

        fig, axes = plt.subplots(1, 2, figsize=(14, 5.5))

        # Unlabelled windows (mostly pre-baseline: the node was up before the
        # experiment started) have no phase to be compared under. Leave them
        # out of the phase comparison, and say how many were left out.
        phase_all = _phase_names(df)
        has_value = df[feat].notna()
        unlabelled = phase_all.map(_is_unlabelled)
        n_hidden = int((has_value & unlabelled).sum())
        valid = df[has_value & ~unlabelled]
        phase = phase_all[valid.index]

        suptitle = f"{feat} — {FEATURE_DESCRIPTIONS.get(feat, 'distribution')}"
        suptitle += f"\nDistribution by experiment phase and node role · {len(valid)} windows"
        if n_hidden:
            suptitle += f" ({n_hidden} unlabelled pre-baseline windows not shown)"
        fig.suptitle(suptitle, fontsize=11)

        if valid.empty:
            for ax in axes:
                ax.text(
                    0.5, 0.5, "No data available\n(see eda.py module docstring —\n"
                    "this feature is currently NaN for every row\n"
                    "due to a firmware logging gap)",
                    ha="center", va="center", fontsize=11, color="gray",
                    transform=ax.transAxes,
                )
                ax.set_xticks([])
                ax.set_yticks([])
        else:
            order, palette = _phase_order_palette(phase)
            hist_df = valid.assign(Phase=phase.values)
            # Cap the bin count explicitly. Seaborn's automatic (Freedman–Diaconis)
            # bin rule sets width from the IQR, which collapses toward zero when a
            # feature is nearly constant with a few outliers — RetryRate is 0.0
            # everywhere, ForwardingRatio piles at 0 and 1. A near-zero bin width
            # over a non-zero range asks for astronomically many bins and seaborn
            # tries to allocate gigabytes for the step polygons, killing the whole
            # M8 run. A fixed, distinct-value-aware cap keeps the histogram honest
            # and bounded.
            nbins = int(min(50, max(10, valid[feat].nunique())))
            # A KDE only means something for a phase whose values actually
            # spread. On a (nearly) constant phase gaussian_kde does not always
            # raise: with one or two outliers it fits a ~1e-16 bandwidth and
            # draws a ~1e15 spike that flattens every other phase to nothing
            # (2026-09-26 21:11 home run: ForwardingRatio 1.0 in almost every
            # baseline window, attack all 0 and invisible). Draw it only when
            # every phase has MIN_KDE_DISTINCT distinct values.
            use_kde = all(g.nunique() >= MIN_KDE_DISTINCT
                          for _, g in valid[feat].groupby(phase.values))
            try:
                sns.histplot(
                    data=hist_df,
                    x=feat, hue="Phase", hue_order=order, palette=palette,
                    kde=use_kde, ax=axes[0], bins=nbins,
                    element="step", stat="density", common_norm=False,
                )
            except (np.linalg.LinAlgError, MemoryError, ValueError):
                # A phase group with zero variance (e.g. a feature that's constant
                # across a clean baseline run, like RetryRate = 0 everywhere) gives
                # seaborn's gaussian_kde a singular covariance matrix (LinAlgError);
                # a degenerate spread can also blow up bin allocation (MemoryError)
                # or trip a ValueError. In any of these, drop the KDE overlay and
                # redraw a plain capped-bin histogram so the plot is still produced
                # instead of taking down the whole M8 run.
                axes[0].clear()
                sns.histplot(
                    data=hist_df,
                    x=feat, hue="Phase", hue_order=order, palette=palette,
                    kde=False, ax=axes[0], bins=nbins,
                    element="step", stat="density", common_norm=False,
                )
            axes[0].set_title("How often each value occurs, per phase\n"
                              "(each phase scaled to the same area)", fontsize=10)
            axes[0].set_xlabel(_axis_label(feat))
            axes[0].set_ylabel("Density (share of that phase's windows)")

            roles = valid[role_col].astype(str).unique().tolist()
            sns.boxplot(
                data=hist_df.assign(**{"Node role": valid[role_col].astype(str).values}),
                x="Phase", y=feat, hue="Node role", order=order, ax=axes[1],
                hue_order=sorted(roles), palette={r: ROLE_COLORS.get(r, "#8c8c8c")
                                                  for r in roles},
            )
            axes[1].set_title("Spread per phase and node role\n"
                              "(box = middle 50%, line = median, dots = outliers)",
                              fontsize=10)
            axes[1].set_xlabel("")
            axes[1].set_ylabel(_axis_label(feat))
            axes[1].tick_params(axis="x", labelsize=9)

            if valid[feat].nunique() == 1:
                value = valid[feat].iloc[0]
                n_other = int((has_value & unlabelled & (df[feat] != value)).sum())
                note = (f"Every labelled window has {feat} = {value:g}: a flat RESULT,\n"
                        "not missing data - there is no spread to draw.")
                if n_other:
                    note += (f"\n{n_other} unlabelled window(s) outside the experiment "
                             "differ and are not shown.")
                if feat in FLAT_RESULT_NOTES:
                    note += "\n" + FLAT_RESULT_NOTES[feat]
                for ax in axes:
                    ax.text(0.5, 0.5, note, ha="center", va="center", fontsize=10,
                            color="darkred", transform=ax.transAxes,
                            bbox={"facecolor": "white", "alpha": 0.85, "edgecolor": "none"})

        fig.tight_layout()
        out_path = os.path.join(output_dir, f"distribution_{feat}.png")
        fig.savefig(out_path, dpi=120)
        plt.close(fig)
        written.append(out_path)

    return written


# ─────────────────────────────────────────────────────────────────────────
# 3. Time-series plots
# ─────────────────────────────────────────────────────────────────────────

def _extract_run_id(source_file: str) -> str:
    """
    Extract the run identifier from a source_file name.

    csv_logger.c writes files as <node_id>_<run_id>_telem.csv, where
    run_id follows the RUN_%03lu format from build_run_id() (root_main.c
    / victim_main.c). Each node writes its OWN file, so source_file is
    unique per (node, run) pair — grouping time-series plots directly by
    source_file therefore puts every node in its own separate figure,
    which defeats the point of this analysis (seeing whether phase
    transitions align ACROSS nodes within one run). This function pulls
    just the run_id back out so multiple nodes' files from the same run
    can be grouped together correctly.

    Falls back to the full source_file if the expected RUN_xxx pattern
    isn't found, so a non-conforming filename still produces a plot
    (one node per figure, same as before) rather than crashing.
    """
    import re
    match = re.search(r"(RUN_\w+?)_telem", source_file)
    return match.group(1) if match else source_file


def _align_to_baseline(run_df: pd.DataFrame) -> pd.DataFrame:
    """Add `_t`: seconds relative to the moment THIS node entered phase 0.

    window_start is each node's OWN run clock, restarting at 0 when that board
    boots -- and boards are flashed one at a time, so the same wall-clock instant
    is a different window_start on every node. Measured on blackhole/linear/home
    r1 (2026-09-22), phase 0 began at window_start 60s on the root, 153s on one
    victim, 222s on the attacker and 670s on the victim that was powered up
    first. Plotting all four against a shared x-axis therefore drew each line
    ~10 minutes out of step with the others, and the phase shading -- taken from
    whichever node happened to sort first at each window_start -- was correct for
    at most one of them.

    Re-basing on each node's own phase-0 entry puts every node on ONE timeline:
    x=0 is "baseline starts", pre-baseline idle falls at negative x where it is
    obviously not part of the experiment, and the bands are then true for every
    line on the axis. This is a PLOT axis only -- the feature table is untouched,
    so nothing here can reach a model.
    """
    df = run_df.copy()
    if "window_start" not in df.columns:
        return df
    # Anchor on preprocess.py's RAW `segment` value, not _phase_names() -- that
    # returns display strings ("Baseline", "Blackhole attack"), so matching it
    # against a lowercase segment name silently never fires and every node keeps
    # its own un-rebased clock.
    if "segment" in df.columns:
        is_base = df["segment"].astype(str) == "baseline"
    else:
        lab = pd.to_numeric(
            df["Label" if "Label" in df.columns else "window_label"], errors="coerce")
        is_base = lab == 0
    # Fall back to the node's own first window when a capture has no baseline at
    # all (root-only or truncated runs still plot, just un-rebased).
    base = df["window_start"].where(is_base)
    key = "node_id" if "node_id" in df.columns else None
    if key is None:
        origin = base.min() if base.notna().any() else df["window_start"].min()
        df["_t"] = df["window_start"] - origin
        return df
    origins = base.groupby(df[key]).min()
    fallback = df.groupby(key)["window_start"].min()
    origins = origins.fillna(fallback)
    df["_t"] = df["window_start"] - df[key].map(origins)
    return df


def _phase_spans(run_df: pd.DataFrame) -> list[tuple[float, float, str, str]]:
    """
    Contiguous (start, end, phase name, colour) runs for background shading.

    Compares phase NAMES, not the raw Label: Label is NaN on unlabelled windows
    and NaN != NaN, so the old label comparison opened a new span on every
    unlabelled window and stacked hundreds of translucent red spans into a
    solid block that looked like the attack.

    Spans are built on `_t` (see _align_to_baseline), NOT window_start. The
    previous version took the first row per window_start "because all nodes in a
    run share the root's broadcast schedule" -- they share the schedule, but not
    the clock it is measured on, so the bands only ever lined up with whichever
    node booted first.
    """
    axis = "_t" if "_t" in run_df.columns else "window_start"
    if axis not in run_df.columns:
        return []
    ordered = run_df.sort_values(axis).drop_duplicates(axis)
    if ordered.empty:
        return []
    names = _phase_names(ordered).tolist()
    starts = ordered[axis].tolist()
    _, palette = _phase_order_palette(names)
    step = float(np.median(np.diff(starts))) if len(starts) > 1 else 1.0

    spans = []
    span_start, current = starts[0], names[0]
    for t, name in zip(starts[1:], names[1:]):
        if name != current:
            spans.append((span_start, t, current, palette[current]))
            span_start, current = t, name
    spans.append((span_start, starts[-1] + step, current, palette[current]))
    return spans


def _draw_timeseries(plot_df, features, title, out_path, single_node=False):
    """Render one time-series figure and return its path.

    Shared by BOTH views below so the per-run overlay and the per-node plots can
    never drift apart in alignment, shading or labelling -- the misaligned bands
    fixed on 2026-09-23 came from exactly that kind of duplicated drawing code.
    """
    fig, axes = plt.subplots(len(features), 1,
                             figsize=(12, 3.6 * len(features)), sharex=True)
    if len(features) == 1:
        axes = [axes]
    fig.suptitle(title, fontsize=10)
    phase_spans = _phase_spans(plot_df)
    # One colour per NODE for the whole figure. Letting matplotlib cycle per
    # axis gave the same board a different colour in each panel (each panel
    # skips the nodes it has no data for), so a line could not be followed
    # from ForwardingRatio down to PDR.
    palette = sns.color_palette("tab10", 10) + sns.color_palette("Dark2", 8)
    node_color = {n: palette[i % len(palette)]
                  for i, n in enumerate(sorted(plot_df["node_id"].astype(str).unique()))}

    for ax, feat in zip(axes, features):
        if feat not in plot_df.columns:
            ax.text(0.5, 0.5, f"'{feat}' not in dataset", ha="center", va="center",
                    transform=ax.transAxes, color="gray")
            continue

        plotted_any = False
        for node_id, node_df in plot_df.groupby("node_id"):
            node_df = node_df.sort_values("_t")
            if node_df[feat].notna().any():
                role = (node_df["node_role"].iloc[0]
                        if "node_role" in node_df.columns else None)
                ax.plot(
                    node_df["_t"], node_df[feat],
                    linewidth=1.2,
                    color="#222222" if single_node else node_color[str(node_id)],
                    label=f"{node_id} ({role})" if role else node_id,
                )
                plotted_any = True

        # An all-NaN feature (PDR on a root-only capture, say) draws no lines at
        # all. Say so on the axis rather than leaving a blank panel — and skip
        # the legend, which warns "No artists with labels found" otherwise.
        if not plotted_any:
            ax.text(0.5, 0.5, f"no data for '{feat}' here",
                    ha="center", va="center", transform=ax.transAxes, color="gray")

        for span_start, span_end, _name, color in phase_spans:
            ax.axvspan(span_start, span_end, color=color, alpha=0.13,
                       linewidth=0, zorder=0)
        # The one moment every node agrees on, now that they are aligned.
        ax.axvline(0.0, color="#444444", linewidth=0.9, linestyle="--", zorder=1)

        ax.set_ylabel(_axis_label(feat), fontsize=9)
        if ax.get_legend_handles_labels()[0]:
            ax.legend(fontsize=7, loc="upper left", title="Node", title_fontsize=7)

    if phase_spans:
        from matplotlib.patches import Patch
        seen = dict.fromkeys((n, c) for _, _, n, c in phase_spans)
        fig.legend(
            handles=[Patch(color=c, alpha=0.35, label=n) for n, c in seen],
            loc="lower center", ncol=len(seen), fontsize=8, frameon=False,
        )

    axes[-1].set_xlabel("Time relative to each node's BASELINE start (s)  "
                        "— dashed line = t0")
    fig.tight_layout(rect=(0, 0.05 if phase_spans else 0, 1, 1))
    fig.savefig(out_path, dpi=120)
    plt.close(fig)
    return out_path


def plot_time_series(
    df: pd.DataFrame,
    output_dir: str,
    features: list[str] | None = None,
) -> list[str]:
    """
    Selected feature trajectories over the run — per the thesis (Section
    4.2.6): "Selected feature trajectories (e.g., parent switch events, PDR)".
    The paper's two are kept; the "e.g." leaves room for two more, added so
    EVERY role gets a line (with only those two the attacker's and the root's
    figures were blank panels):
      ForwardingRatio_5w  the attacker-side primary signature, smoothed over
                          5 windows = verify_attack.py's pooling (display only,
                          see add_display_columns).
      RootArrivals        the root's received-probe count, the independent
                          root-side view of the same drop (display only).
    Neither is a Table 4.11 feature and neither enters stats/correlation/PCA.

    TWO VIEWS, both written, because they answer different questions:

      timeseries_<attack>_<topology>_<site>_<repeat>.png
          every node of one run overlaid. This is the "did the phases line up
          across nodes, and did the attack land where we said it would" view.
      timeseries_<source_file>.png
          one figure per node, one per capture file. This is the "what exactly
          did THIS board do" view, and it is the one to open when a single node
          looks wrong.

    Only the overlay existed after the 2026-09-23 run-grouping fix, which
    silently dropped the per-node figures people were already using. Both are
    produced now; neither replaces the other.

    Both are drawn on `_t` (see _align_to_baseline): t=0 is the moment THAT node
    entered baseline, so pre-baseline idle sits at negative t and the phase bands
    are true for every line on the axis.
    """
    if features is None:
        # ForwardingRatio is the one PRIMARY signature that measures the
        # attacker itself; with only ParentSwitchRate + PDR the attacker's and
        # the root's figures were blank panels. RootArrivals gives the root a line.
        features = ["ForwardingRatio_5w", "PDR", "RootArrivals", "ParentSwitchRate"]

    df = df.copy()
    # Group by the RUN, using the columns preprocess.py already resolved.
    #
    # _extract_run_id() regex-matches "RUN_xxx_telem", the OLD firmware filename
    # shape (NODE_AABBCC..._RUN_001_telem.csv). Every real capture now comes out
    # of export_logs.py/import_sdcard.py as
    # child_node2_linear_blackhole_r1_20260922_220313_telem.csv, so the regex
    # never matched and the fallback returned the whole filename — which is why
    # the overlay never existed until this was fixed. The identity columns are
    # right there in the table and cannot drift from the filename.
    id_cols = [c for c in ("attack", "topology", "location", "run_repeat")
               if c in df.columns]
    if id_cols:
        df["_run_id"] = df[id_cols].astype(str).agg("_".join, axis=1)
    else:
        df["_run_id"] = df["source_file"].apply(_extract_run_id)

    written = []
    for run_id, run_df in df.groupby("_run_id"):
        run_df = _align_to_baseline(run_df).sort_values("_t")
        safe_run = str(run_id).replace(".csv", "").replace("/", "_")

        # ── view 1: the whole run, every node on one axis ──
        # A node with NO labelled window (preprocess unlabels one whose phases
        # disagree with the root's, phase_sync.py) has no baseline to align on,
        # so it would sit on its own clock and stripe the shared phase bands.
        # It keeps its per-node figure below; the overlay names it instead.
        label_col = "Label" if "Label" in run_df.columns else "window_label"
        overlay_df, left_out = run_df, []
        if label_col in run_df.columns and "node_id" in run_df.columns:
            has_label = run_df[label_col].notna().groupby(run_df["node_id"]).any()
            left_out = sorted(has_label.index[~has_label])
            if left_out and len(left_out) < len(has_label):
                overlay_df = run_df[~run_df["node_id"].isin(left_out)]
            else:
                left_out = []
        note = ("\nNot shown - no labelled window (out of sync with the root, see "
                "preprocess report): " + ", ".join(left_out)) if left_out else ""
        written.append(_draw_timeseries(
            overlay_df, features,
            f"Feature trajectories over the run — {run_id}\n"
            "Background colour = experiment phase.  t=0 is when BASELINE starts on "
            "each node;\nnegative t is pre-baseline idle (node booted, root had not "
            "announced a phase yet) and is excluded from analysis." + note,
            os.path.join(output_dir, f"timeseries_{safe_run}.png")))

        # ── view 2: one figure per capture file, same names as before ──
        if "source_file" not in run_df.columns:
            continue
        for src, node_df in run_df.groupby("source_file"):
            node_ids = node_df["node_id"].unique()
            who = node_ids[0] if len(node_ids) == 1 else f"{len(node_ids)} nodes"
            role = (node_df["node_role"].iloc[0]
                    if "node_role" in node_df.columns else "")
            safe_src = str(src).replace(".csv", "").replace("/", "_")
            written.append(_draw_timeseries(
                node_df, features,
                f"Feature trajectories — {who}"
                f"{f' ({role})' if role else ''}\n{src}\n"
                "Background colour = experiment phase.  t=0 is when BASELINE starts; "
                "negative t is pre-baseline idle (excluded from analysis).",
                os.path.join(output_dir, f"timeseries_{safe_src}.png"),
                single_node=len(node_ids) == 1))

    return written


# ─────────────────────────────────────────────────────────────────────────
# 4. Cross-layer correlation analysis
# ─────────────────────────────────────────────────────────────────────────

def compute_correlations(
    df: pd.DataFrame,
    exclude_leaking: bool = True,
) -> tuple[pd.DataFrame, pd.DataFrame, list[str]]:
    """
    Pearson and Spearman correlation matrices across the 16 Table 4.11
    features, per Section 4.2.6: "to examine relationships between PHY,
    MAC, and Network layer features."

    All-NaN columns are excluded automatically (correlation is undefined
    on them) — returns the two matrices plus the list of columns that
    were excluded and why, so the exclusion is never silent.

    exclude_leaking (default True) additionally drops the label-equivalent
    columns from _leaking_for(df) (leakage.py, per dataset). Correlating a feature against
    the attack's own switch measures the switch, not a cross-layer
    relationship: ConsistencyScore is |ForwardingRatio - 1| to 1.1e-16, so
    leaving both in manufactures a perfect correlation that says nothing about
    the network. Pass False for the attacker-side diagnostic view.
    """
    pearson, spearman, excluded, _constant, _n = _correlate(df, exclude_leaking)
    return pearson, spearman, excluded


# Which windows each correlation view uses. Section 4.2.6 asks for "cross-layer
# consistency during baseline and its breakdown during manipulation", so the
# baseline and attack windows each get their own matrix; "" pools every
# experiment window. Unlabelled windows (mesh forming, root not up, a node out of
# sync) are never used - the same rule as the distribution plots and PCA.
CORRELATION_VIEWS = {
    "": ("all experiment phases", lambda names: ~names.map(_is_unlabelled)),
    "_baseline": ("baseline only", lambda names: names == "Baseline"),
    "_attack": ("attack only", lambda names: names.str.endswith(" attack")),
}


def _correlate(df: pd.DataFrame, exclude_leaking: bool = True, view: str = ""):
    """(pearson, spearman, all-NaN columns, constant columns, n windows) for one view.

    A column that is constant over the view's windows has no correlation (0/0)
    and is dropped from the matrix but NAMED, so a flat feature - RetryRate on a
    stationary blackhole run - reads as the result it is, not as missing data.
    """
    rows = df[CORRELATION_VIEWS[view][1](_phase_names(df)).values]
    candidate_cols = [c for c in FEATURE_COLUMNS if c in df.columns]
    if exclude_leaking:
        candidate_cols = [c for c in candidate_cols if c not in _leaking_for(df)]
    excluded = _detect_allnan_columns(rows, candidate_cols)
    usable_cols = [c for c in candidate_cols if c not in excluded]

    numeric_df = rows[usable_cols].apply(pd.to_numeric, errors="coerce")
    constant = [c for c in usable_cols if numeric_df[c].nunique() <= 1]
    numeric_df = numeric_df.drop(columns=constant)

    return (numeric_df.corr(method="pearson"), numeric_df.corr(method="spearman"),
            excluded, constant, len(rows))


def plot_correlation_heatmaps(
    df: pd.DataFrame,
    output_dir: str,
) -> tuple[str, str, list[str]]:
    """correlation_{pearson,spearman}{,_baseline,_attack}.png + .csv (see
    CORRELATION_VIEWS). Returns the pooled pair's paths and all-NaN columns."""
    excluded = []
    for view in CORRELATION_VIEWS:
        pearson, spearman, view_excluded, constant, n_rows = _correlate(df, view=view)
        if not view:
            excluded = view_excluded
        if n_rows == 0:
            continue    # e.g. a baseline-only capture has no attack view
        for name, matrix in [("pearson", pearson), ("spearman", spearman)]:
            matrix.to_csv(os.path.join(output_dir, f"correlation_{name}{view}.csv"))
        _draw_correlation_pair(pearson, spearman, view, view_excluded, constant,
                               n_rows, output_dir)

    pearson_path = os.path.join(output_dir, "correlation_pearson.png")
    spearman_path = os.path.join(output_dir, "correlation_spearman.png")
    return pearson_path, spearman_path, excluded


def _draw_correlation_pair(pearson, spearman, view, excluded, constant, n_rows,
                           output_dir):

    layer_of = {f: layer for layer, feats in LAYER_GROUPS.items() for f in feats}
    method_blurb = {
        "pearson": "Pearson r — how well two features follow a straight-line relationship",
        "spearman": "Spearman ρ — how consistently two features rise or fall together "
                    "(rank-based; catches curved trends too)",
    }
    # Colour-bar ticks spelled out in words: the bare -1..1 scale was the part
    # nobody could read without already knowing what a correlation is.
    cbar_ticks = [1, 0.7, 0.3, 0, -0.3, -0.7, -1]
    cbar_words = [
        "+1  always rise together", "+0.7  strong", "+0.3  weak",
        "0  no relationship",
        "−0.3  weak", "−0.7  strong", "−1  one rises, other falls",
    ]

    for name, matrix in [("pearson", pearson), ("spearman", spearman)]:
        tick_names = [f"{c} [{layer_of.get(c, 'Cross-layer')}]" for c in matrix.columns]
        fig, ax = plt.subplots(figsize=(13, 11))
        sns.heatmap(
            matrix, annot=True, fmt=".2f", cmap="coolwarm",
            center=0, vmin=-1, vmax=1, square=True, ax=ax, linewidths=0.5,
            xticklabels=tick_names, yticklabels=tick_names,
            annot_kws={"fontsize": 15, "fontweight": "medium"},
            cbar_kws={"label": "", "shrink": 0.8},
        )
        ax.grid(False)
        cbar = ax.collections[0].colorbar
        cbar.set_ticks(cbar_ticks)
        cbar.set_ticklabels(cbar_words, fontsize=9)
        ax.tick_params(axis="x", labelrotation=40, labelsize=9)
        plt.setp(ax.get_xticklabels(), ha="right", rotation_mode="anchor")
        ax.tick_params(axis="y", labelsize=9)

        title = (f"{name.capitalize()} correlation between features - "
                 f"{CORRELATION_VIEWS[view][0]} ({n_rows} labelled windows, all nodes)"
                 f"\n{method_blurb[name]}")
        # Wrap the lists manually rather than relying on matplotlib's title
        # auto-wrap (which doesn't wrap titles by default and was clipping the
        # last column name off the right edge of the figure).
        if excluded:
            excluded_text = "Not shown (no data in these windows): " + ", ".join(excluded)
            title += "\n" + textwrap.fill(excluded_text, width=110)
        if constant:
            constant_text = ("Not shown (same value in every window, so no correlation "
                             "exists - a result, not a gap): "
                             + ", ".join(f"{c} [{layer_of.get(c, 'Cross-layer')}]"
                                         for c in constant))
            title += "\n" + textwrap.fill(constant_text, width=110)
        ax.set_title(title, fontsize=10, loc="left")

        fig.text(
            0.01, 0.01,
            "How to read: each cell compares two features across every window. "
            "Red = when one goes up, the other tends to go up. "
            "Blue = when one goes up, the other tends to go down.\n"
            "Pale = no clear relationship. The number is the strength (0 to ±1). "
            "The diagonal is each feature against itself (always 1). "
            "Correlation shows features move together, not that one causes the other.",
            fontsize=8.5, color="#444444", ha="left", va="bottom",
        )
        fig.tight_layout(rect=(0, 0.05, 1, 1))
        out_path = os.path.join(output_dir, f"correlation_{name}{view}.png")
        fig.savefig(out_path, dpi=120)
        plt.close(fig)


# ─────────────────────────────────────────────────────────────────────────
# 5. Dimensionality reduction — PCA and t-SNE
# ─────────────────────────────────────────────────────────────────────────

def run_dimensionality_reduction(
    df: pd.DataFrame,
    exclude_tunnel: bool = True,
    tsne_perplexity: float | None = None,
    random_state: int = 42,
    max_nan_fraction: float = 0.5,
    exclude_leaking: bool = True,
) -> dict:
    """
    Z-score standardizes the feature columns (Equation 4.18), then runs
    both PCA and t-SNE for a 2D projection, colored by ground-truth
    label — per Section 4.2.6: "to provide an initial visual assessment
    of feature-space separability before formal clustering."

    Columns excluded from the projection, in order:
      1. Columns that are all-NaN for every row (mathematically
         required — PCA/t-SNE cannot operate on them at all).
      2. Tunnel features, if exclude_tunnel=True (default), per Section
         4.2.5.1's own documented option: "auxiliary tunnel features may
         be excluded before normalization to assess whether behavioral
         separation emerges without explicit manipulation indicators."
      3. Columns whose NaN fraction exceeds `max_nan_fraction` (default
         0.5). This is what keeps the projection from collapsing to zero
         rows: several features are defined for only ONE node role —
         ForwardingRatio/IngressEgressDelta/ConsistencyScore exist only on
         the attacker, PDR only on victims — so no single window is
         non-NaN in all of them at once. Feeding those role-exclusive
         columns into a common matrix and then dropping rows with any NaN
         wipes EVERY row (an attacker window is NaN in PDR, a victim window
         is NaN in ForwardingRatio). Dropping the sparse columns first
         projects the broadly-defined cross-layer features over the windows
         that actually share them, instead of producing an empty plot.
      4. Columns that are CONSTANT across every surviving row. A
         zero-variance column carries no separability information, and
         feeding one in is actively dangerous rather than merely useless:
         StandardScaler maps it to all-zeros, and if EVERY column is
         constant the whole matrix becomes zeros. PCA then divides by a
         zero total variance (explained_variance_ratio_ = 0/0 = NaN) and
         t-SNE's init="pca" divides its all-zero embedding by a zero
         standard deviation, handing the Barnes-Hut quadtree a set of NaN
         coordinates. The tree recurses without bound on those and the
         process dies with a Windows stack overflow (0xC00000FD /
         exit -1073741571) — killed by the OS inside the C extension, with
         no Python traceback to explain it.

         Seen on blackhole/linear/G402 (2026-09-14): a ROOT-ONLY capture.
         The root has no parent link, so rssi_dbm and retry_count are 0 on
         every raw sample, which makes all 8 otherwise-usable columns
         constant. Dropping them first turns that crash into the labelled
         "not enough variance" panel below.

    Rows with any remaining NaN in the surviving columns are dropped
    (PCA/t-SNE need a complete matrix) — the count dropped is reported,
    not silently absorbed.

    Returns a dict with the fitted projections, the excluded-column
    list, and the dropped-row count, so the caller (or the plotting
    function below) has everything needed to label the output honestly.
    """
    candidate_cols = [c for c in FEATURE_COLUMNS if c in df.columns]

    # Leakage guard (default on). A projection computed over the attack's own
    # switch separates the classes perfectly and proves nothing: the separation
    # is the switch being on. Dropping these columns is what makes the
    # projection a statement about network behaviour. leakage.py holds the list
    # and the reason for each entry. Pass exclude_leaking=False for the
    # attacker-side diagnostic view.
    leaking_excluded = (
        [c for c in candidate_cols if c in _leaking_for(df)]
        if exclude_leaking else []
    )

    allnan_excluded = _detect_allnan_columns(df, candidate_cols)

    tunnel_cols = [c for c in candidate_cols if c.startswith("Tunnel")]
    tunnel_excluded = tunnel_cols if exclude_tunnel else []

    # Role-exclusive / structurally-sparse columns: too many NaNs to share a
    # complete matrix with the rest. Excluding them is what prevents the
    # all-rows-dropped empty projection (see docstring point 3).
    sparse_excluded = [
        c for c in candidate_cols
        if c not in allnan_excluded and df[c].isna().mean() > max_nan_fraction
    ]

    excluded = sorted(set(allnan_excluded) | set(tunnel_excluded)
                      | set(sparse_excluded) | set(leaking_excluded))
    usable_cols = [c for c in candidate_cols if c not in excluded]

    label_col = "Label" if "Label" in df.columns else "window_label"
    working = df[usable_cols + [label_col]].copy()
    working[usable_cols] = working[usable_cols].apply(pd.to_numeric, errors="coerce")
    working["_phase"] = _phase_names(df).values

    # Windows with no ground truth (pre-baseline etc.) can't show whether the
    # PHASES separate, which is this plot's whole question — and on
    # blackhole/linear/home (2026-09-22) a handful of them sat at PC1 ≈ 35,
    # squashing every labelled point into one corner. preprocess.py already
    # keeps them out of every benign/attack population; do the same here.
    unlabelled_rows = working["_phase"].map(_is_unlabelled)
    n_unlabelled = int(unlabelled_rows.sum())
    working = working[~unlabelled_rows]

    n_before = len(working)
    working = working.dropna(subset=usable_cols)
    n_dropped = n_before - len(working)

    # Constant-column drop (docstring point 4). Computed AFTER the dropna, since
    # it's the surviving rows that decide whether a column actually varies —
    # but skipped when nothing survived, where nunique() is 0 for every column
    # and would report a no-rows table as a no-variance one.
    constant_excluded = [] if working.empty else [
        c for c in usable_cols if working[c].nunique(dropna=False) <= 1
    ]
    if constant_excluded:
        excluded = sorted(set(excluded) | set(constant_excluded))
        usable_cols = [c for c in usable_cols if c not in constant_excluded]

    def _bail(message: str) -> dict:
        return {
            "error": message,
            "excluded_columns": excluded,
            "allnan_excluded": sorted(allnan_excluded),
            "sparse_excluded": sorted(sparse_excluded),
            "constant_excluded": sorted(constant_excluded),
            "n_dropped_rows": n_dropped,
            "n_unlabelled_excluded": n_unlabelled,
        }

    # PCA(n_components=2) needs at least two columns that actually vary, so this
    # one guard covers both "everything is flat" and "only one column varies".
    if working.empty or len(usable_cols) < 2:
        n_nodes_in_table = (
            df["node_id"].nunique() if "node_id" in df.columns else 0
        )
        node_hint = ""
        if n_nodes_in_table:
            names = sorted(df["node_id"].astype(str).unique())[:3]
            node_hint = (
                f" ({n_nodes_in_table} node(s) in table: {', '.join(names)}"
                + (", ..." if n_nodes_in_table > len(names) else "")
                + ")"
            )
        if constant_excluded and not usable_cols:
            return _bail(
                f"Not enough variance for a projection: all "
                f"{len(constant_excluded)} usable feature columns are constant "
                f"across {len(working)} windows{node_hint}.\n"
                f"Constant: {', '.join(sorted(constant_excluded))}."
            )
        return _bail(
            f"Not enough usable data for dimensionality reduction "
            f"({len(usable_cols)} usable columns, {len(working)} complete rows "
            f"after dropping {n_dropped} rows with remaining NaNs"
            + (f"; {len(constant_excluded)} constant column(s) dropped: "
               f"{', '.join(sorted(constant_excluded))}" if constant_excluded else "")
            + f"){node_hint}."
        )

    X = working[usable_cols].to_numpy()
    y = working[label_col].to_numpy()

    # Checked BEFORE the scaler, not after: StandardScaler raises ValueError on a
    # non-finite input, so a post-scale check never gets to run. dropna() above
    # removes NaNs but not infinities, and a divide-by-zero in features.py can
    # produce one. Report it as a panel like every other unusable-data case
    # instead of letting a traceback fail the whole M8 step.
    if not np.isfinite(X).all():
        bad = int((~np.isfinite(X)).sum())
        bad_cols = [c for i, c in enumerate(usable_cols) if not np.isfinite(X[:, i]).all()]
        return _bail(
            f"Feature matrix contains non-finite values ({bad} of {X.size} cells) — "
            f"refusing to run PCA/t-SNE on it. Affected columns: {', '.join(bad_cols)}."
        )

    # Clipped after standardising: the topology features are ~constant, so the
    # handful of windows where a node switched parent sat 40-48 sd out (G402,
    # sep. 25, 2026) and PC1 described those few windows instead of the run.
    # Clipping keeps the events visible without letting them own an axis.
    scaler = StandardScaler()
    X_scaled = np.clip(scaler.fit_transform(X), -PCA_Z_CLIP, PCA_Z_CLIP)

    pca = PCA(n_components=2, random_state=random_state)
    pca_proj = pca.fit_transform(X_scaled)

    # t-SNE perplexity must be < n_samples; default to a reasonable
    # fraction of the dataset size rather than sklearn's flat default
    # of 30, which errors out on small synthetic test runs.
    n_samples = X_scaled.shape[0]
    if tsne_perplexity is None:
        tsne_perplexity = min(30, max(5, n_samples // 4))
    tsne_perplexity = min(tsne_perplexity, n_samples - 1)

    # Surviving variance is necessary but not sufficient for t-SNE: Barnes-Hut
    # also degenerates when the points are heavily duplicated, because the
    # quadtree has to keep subdividing to separate coincident coordinates. That
    # is a realistic shape here — 1 Hz windows over an idle mesh repeat a lot —
    # so count DISTINCT rows, not rows. PCA is well-defined on duplicates, so a
    # skip here costs only the right-hand panel, not the whole figure.
    n_distinct = np.unique(X_scaled, axis=0).shape[0]
    tsne_proj = None
    tsne_skipped = None
    if n_distinct < 5 or n_distinct <= tsne_perplexity:
        tsne_skipped = (
            f"t-SNE skipped — only {n_distinct} distinct point(s) among "
            f"{n_samples} windows (perplexity {tsne_perplexity:g}). "
            f"Too degenerate for a Barnes-Hut embedding; PCA panel is unaffected."
        )
    else:
        tsne = TSNE(
            n_components=2, perplexity=tsne_perplexity,
            random_state=random_state, init="pca",
        )
        tsne_proj = tsne.fit_transform(X_scaled)

    return {
        "pca_projection": pca_proj,
        "pca_explained_variance_ratio": pca.explained_variance_ratio_,
        "tsne_projection": tsne_proj,
        "tsne_skipped": tsne_skipped,
        "tsne_perplexity_used": tsne_perplexity,
        "n_distinct_points": n_distinct,
        "labels": y,
        "phase_names": working["_phase"].tolist(),
        "n_unlabelled_excluded": n_unlabelled,
        "usable_columns": usable_cols,
        "excluded_columns": excluded,
        "allnan_excluded": sorted(allnan_excluded),
        "sparse_excluded": sorted(sparse_excluded),
        "constant_excluded": sorted(constant_excluded),
        "n_dropped_rows": n_dropped,
        "n_rows_used": len(working),
    }


def _wrap_for_axis(message: str, width: int = 64) -> str:
    """
    Hard-wraps a message to `width` columns, preserving existing line breaks.

    Needed because matplotlib's text(wrap=True) wraps to the FIGURE width, not
    the axes width, so a long message runs straight out of its panel.
    """
    return "\n".join(
        "\n".join(textwrap.wrap(line, width=width)) if line.strip() else line
        for line in message.splitlines()
    )


def _draw_error_panel(ax, message: str):
    """Writes a projection's "couldn't draw this" message into ax."""
    ax.text(0.5, 0.5, _wrap_for_axis(message), ha="center", va="center",
            fontsize=10, color="darkred", transform=ax.transAxes)
    ax.set_xticks([])
    ax.set_yticks([])


def _draw_projection_axis(
    ax, proj, label_names, palette, title: str,
    xlabel: str, ylabel: str, skipped: str | None = None,
):
    """
    Scatters one 2D projection onto ax, or writes a centred grey note when that
    projection was skipped (proj is None). Shared by the whole-mesh and
    tunnel-end figures, which draw the same PCA/t-SNE pair.
    """
    if proj is None:
        ax.text(0.5, 0.5, _wrap_for_axis(skipped or "not available", width=46),
                ha="center", va="center",
                fontsize=9, color="dimgray", transform=ax.transAxes)
        ax.set_xticks([])
        ax.set_yticks([])
        ax.set_title(title)
        return

    order, _ = _phase_order_palette(label_names)
    sns.scatterplot(
        x=proj[:, 0], y=proj[:, 1],
        hue=label_names, hue_order=order, palette=palette, ax=ax,
        s=22, alpha=0.6, linewidth=0,
    )
    ax.legend(title="Phase", fontsize=8, title_fontsize=8)
    ax.set_title(title)
    ax.set_xlabel(xlabel)
    ax.set_ylabel(ylabel)


def _pca_title(result: dict) -> str:
    """PCA panel title. Variance ratios are NaN on a degenerate matrix, so they
    are only formatted as percentages when they're actually finite."""
    var_explained = result["pca_explained_variance_ratio"]
    if len(var_explained) < 2 or not np.isfinite(var_explained[:2]).all():
        return "PCA (explained variance undefined — no variance in inputs)"
    return (f"PCA (PC1: {var_explained[0]:.1%} var, PC2: {var_explained[1]:.1%} var; "
            f"z clipped at ±{PCA_Z_CLIP:g})")


def plot_dimensionality_reduction(
    df: pd.DataFrame,
    output_dir: str,
    **kwargs,
) -> tuple[str | None, dict]:
    result = run_dimensionality_reduction(df, **kwargs)

    if "error" in result:
        fig, ax = plt.subplots(figsize=(8, 6))
        _draw_error_panel(ax, result["error"])
        out_path = os.path.join(output_dir, "dimensionality_reduction.png")
        fig.savefig(out_path, dpi=120)
        plt.close(fig)
        return out_path, result

    fig, axes = plt.subplots(1, 2, figsize=(14, 6))

    label_names = result["phase_names"]
    _, palette = _phase_order_palette(label_names)

    _draw_projection_axis(
        axes[0], result["pca_projection"], label_names, palette,
        _pca_title(result), "PC1 — strongest combined pattern",
        "PC2 — next strongest pattern",
    )
    _draw_projection_axis(
        axes[1], result["tsne_projection"], label_names, palette,
        f"t-SNE (perplexity={result['tsne_perplexity_used']})",
        "t-SNE dim 1 (no units — only closeness matters)",
        "t-SNE dim 2", skipped=result.get("tsne_skipped"),
    )

    sparse = result.get("sparse_excluded") or []
    allnan = result.get("allnan_excluded") or []
    constant = result.get("constant_excluded") or []
    excl_bits = []
    if allnan:
        excl_bits.append(f"all-NaN: {', '.join(allnan)}")
    if sparse:
        excl_bits.append(f"role-sparse (>50% NaN): {', '.join(sparse)}")
    if constant:
        excl_bits.append(f"constant (no variance): {', '.join(constant)}")
    subtitle = (
        f"{result['n_rows_used']} windows used"
        + (f" ({result['n_dropped_rows']} dropped for remaining NaNs)" if result["n_dropped_rows"] else "")
        + (f"; {result['n_unlabelled_excluded']} unlabelled (pre-baseline) windows left out"
           if result.get("n_unlabelled_excluded") else "")
        + ("\nExcluded — " + "; ".join(excl_bits) if excl_bits else "\nExcluded columns: none")
    )
    fig.suptitle(f"Dimensionality reduction — feature-space separability\n{subtitle}", fontsize=10)
    fig.tight_layout()

    out_path = os.path.join(output_dir, "dimensionality_reduction.png")
    fig.savefig(out_path, dpi=120)
    plt.close(fig)

    return out_path, result


def plot_tunnel_end_projection(
    df: pd.DataFrame,
    output_dir: str,
    max_nan_fraction: float = 0.4,
    **kwargs,
) -> tuple[str | None, dict]:
    """
    Companion projection over the TUNNEL-END nodes only, with the tunnel
    features kept in.

    The whole-mesh plot above cannot show them: TunnelIntensity/TunnelBytes
    exist on the two wormhole ends and nowhere else, so across a 6-node mesh
    they sit around 67% NaN and are dropped as role-sparse. The result is a
    projection built from the features a wormhole barely touches (RSSI,
    retries, parent switches) — it answers "is the attack visible in what
    EVERY node can measure?", which is the honest detection question, but it
    is silent on the tunnel evidence and reads as though there is none.

    Restricting the rows to the nodes that actually have a tunnel makes those
    columns dense again, so this plot answers the complementary question:
    "does the tunnel evidence separate the attack window?" Keep both — one is
    the realistic detector's view, the other the ground-truth confirmation.

    Returns (None, {...}) when the table has no tunnel data at all (any
    baseline or blackhole run), which is not an error — there is simply no
    tunnel to plot.

    max_nan_fraction is 0.4 here rather than the 0.5 used mesh-wide: on a
    two-node subset a feature defined on exactly ONE end lands at ~0.50, right
    on the boundary, and keeping it would drop the other end's rows entirely
    at the dropna step — collapsing a two-node plot to one node. PDR is
    exactly this case (victims have it, the wormhole exit does not).
    """
    tunnel_cols = [c for c in FEATURE_COLUMNS
                   if c.startswith("Tunnel") and c in df.columns]
    if not tunnel_cols:
        return None, {"skipped": "no tunnel feature columns in this table"}

    has_tunnel = df[tunnel_cols].notna().any(axis=1)
    if not has_tunnel.any():
        return None, {"skipped": "no rows carry tunnel data (not a wormhole run)"}

    subset = df[has_tunnel].copy()
    node_col = "node_id" if "node_id" in subset.columns else None
    n_nodes = subset[node_col].nunique() if node_col else 0

    result = run_dimensionality_reduction(
        subset, exclude_tunnel=False, max_nan_fraction=max_nan_fraction, **kwargs
    )
    out_path = os.path.join(output_dir, "dimensionality_reduction_tunnel_ends.png")

    if "error" in result:
        fig, ax = plt.subplots(figsize=(8, 6))
        _draw_error_panel(ax, result["error"])
        fig.savefig(out_path, dpi=120)
        plt.close(fig)
        return out_path, result

    fig, axes = plt.subplots(1, 2, figsize=(14, 6))
    label_names = result["phase_names"]
    _, palette = _phase_order_palette(label_names)

    _draw_projection_axis(
        axes[0], result["pca_projection"], label_names, palette,
        _pca_title(result), "PC1 — strongest combined pattern",
        "PC2 — next strongest pattern",
    )
    _draw_projection_axis(
        axes[1], result["tsne_projection"], label_names, palette,
        f"t-SNE (perplexity={result['tsne_perplexity_used']})",
        "t-SNE dim 1 (no units — only closeness matters)",
        "t-SNE dim 2", skipped=result.get("tsne_skipped"),
    )

    kept_tunnel = [c for c in result["usable_columns"] if c.startswith("Tunnel")]
    subtitle = (
        f"{result['n_rows_used']} windows from {n_nodes} tunnel-end node(s); "
        f"tunnel features INCLUDED: {', '.join(kept_tunnel) if kept_tunnel else 'none survived'}"
    )
    if result.get("excluded_columns"):
        subtitle += "\nExcluded: " + ", ".join(result["excluded_columns"])
    fig.suptitle(
        "Tunnel-end projection — separability WITH the tunnel features\n" + subtitle,
        fontsize=10,
    )
    fig.tight_layout()
    fig.savefig(out_path, dpi=120)
    plt.close(fig)

    result["n_nodes"] = n_nodes
    result["tunnel_columns_kept"] = kept_tunnel
    return out_path, result


# ─────────────────────────────────────────────────────────────────────────
# Orchestration
# ─────────────────────────────────────────────────────────────────────────

def add_display_columns(df: pd.DataFrame, n: int = 5) -> pd.DataFrame:
    """Plot-only columns. Never written back to the feature table.

    ForwardingRatio_5w: forwarded / received summed over the last n windows of
      the same file - the same ratio-of-sums verify_attack.py tests
      (it uses fixed 5-window blocks; this slides, which suits a time series). Per 1 s window
      a probe received just before the edge is forwarded just after it, so the
      raw feature flips 0 -> 2 on an honest relay (values up to 3.0 on G402).
    RootArrivals: the root's probes_count_delta, which on the root counts
      probes RECEIVED (root_main.c s_probes_received).
    """
    df = df.copy()
    if {"recv_count_delta", "forward_count_delta", "source_file", "window_start"} <= set(df.columns):
        order = df.sort_values(["source_file", "window_start"]).index
        g = df.loc[order].groupby("source_file")
        recv = g["recv_count_delta"].transform(lambda s: s.rolling(n, min_periods=1).sum())
        fwd = g["forward_count_delta"].transform(lambda s: s.rolling(n, min_periods=1).sum())
        ratio = (fwd / recv).where(recv > 0)
        # Only where the per-window feature is defined for that node at all.
        relay = df.loc[order].groupby("source_file")["ForwardingRatio"].transform(lambda s: s.notna().any())
        df["ForwardingRatio_5w"] = ratio.where(relay).reindex(df.index)
    if {"node_role", "probes_count_delta"} <= set(df.columns):
        df["RootArrivals"] = df["probes_count_delta"].where(df["node_role"] == "root")
    return df


def run_eda(feature_table_path: str, output_dir: str) -> dict:
    """
    Runs all five thesis-specified analyses against a feature_table.csv
    (M7's output) and writes plots + tables to output_dir. Returns a
    summary dict for printing or further inspection.
    """
    _ensure_dir(output_dir)
    df = pd.read_csv(feature_table_path)
    # Display columns feed the plots only: stats, correlation, PCA and the
    # leakage audit select FEATURE_COLUMNS, so they never see them.
    df = add_display_columns(df)

    summary = {}

    # 1. Descriptive statistics
    stats_df = descriptive_statistics(df)
    stats_path = os.path.join(output_dir, "descriptive_statistics.csv")
    stats_df.to_csv(stats_path, index=False)

    stats_by_phase_df = descriptive_statistics_by_phase(df)
    stats_by_phase_path = os.path.join(output_dir, "descriptive_statistics_by_phase.csv")
    stats_by_phase_df.to_csv(stats_by_phase_path, index=False)

    summary["descriptive_statistics"] = stats_path
    summary["descriptive_statistics_by_phase"] = stats_by_phase_path

    # 2. Distribution visualization
    dist_plots = plot_distributions(df, output_dir)
    summary["distribution_plots"] = dist_plots

    # 3. Time-series plots
    ts_plots = plot_time_series(df, output_dir)
    summary["time_series_plots"] = ts_plots

    # 4. Cross-layer correlation
    pearson_path, spearman_path, corr_excluded = plot_correlation_heatmaps(df, output_dir)
    summary["correlation_pearson_plot"] = pearson_path
    summary["correlation_spearman_plot"] = spearman_path
    summary["correlation_excluded_columns"] = corr_excluded


    # 5. PCA / t-SNE
    dimred_path, dimred_result = plot_dimensionality_reduction(df, output_dir)
    summary["dimensionality_reduction_plot"] = dimred_path
    summary["dimensionality_reduction_excluded_columns"] = dimred_result.get("excluded_columns", [])
    summary["dimensionality_reduction_error"] = dimred_result.get("error")
    summary["dimensionality_reduction_tsne_skipped"] = dimred_result.get("tsne_skipped")

    # 5b. Same projection over the tunnel ends only, tunnel features kept.
    # Skipped (returns None) on baseline/blackhole tables, which have no tunnel.
    tunnel_path, tunnel_result = plot_tunnel_end_projection(df, output_dir)
    summary["tunnel_end_projection_plot"] = tunnel_path
    summary["tunnel_end_projection"] = tunnel_result

    # 6. Leakage audit — the panel's 2:40-4:50 objection, answered numerically.
    #
    # Runs on EVERY analysis pass rather than on request, because the failure
    # mode it catches is silent: a feature table that a model separates
    # perfectly looks like a good result until someone asks which column did
    # it. Writing the number next to every column each time means the answer
    # is already on disk when that question is asked. Columns kept out of the
    # model still get audited, so the report shows what was excluded AND what
    # excluding it was worth.
    try:
        audit = leakage.single_feature_decidability(df)
        audit_path = os.path.join(output_dir, "leakage_audit.csv")
        audit.to_csv(audit_path, index=False)
        summary["leakage_audit"] = audit_path

        allowed, excluded_map = leakage.split_columns(df)
        summary["model_feature_allowlist"] = allowed
        summary["leakage_excluded_columns"] = sorted(excluded_map)

        leakage.print_decidability_report(
            audit, os.path.dirname(feature_table_path) or feature_table_path)

        # A column still allowed into the model that on its own reproduces the
        # label is the panel's objection surviving the fix. Say so here rather
        # than leaving it to be discovered in the CSV.
        survivors = audit[(~audit["excluded"])
                          & (audit["lift_over_majority"] > 0.15)]
        if len(survivors):
            print("    WARNING: these columns are model inputs AND decide the "
                  "label on their own:")
            for _, r in survivors.iterrows():
                print("      {:<22} {:.4f} vs {:.4f} majority".format(
                    r["feature"], r["threshold_accuracy"],
                    r["majority_baseline"]))
            print("    Excluding features cannot fix this: a 100% drop rate in "
                  "a fixed attack window")
            print("    is separable by construction. It needs attack-parameter "
                  "variation (panel 12:45-16:00).")
            summary["leakage_survivors"] = survivors["feature"].tolist()
    except (KeyError, ValueError) as exc:
        # An unlabelled or single-class table is a legitimate state (a pure
        # baseline run has no attack windows), not an error worth aborting the
        # whole EDA pass for.
        print(f"  (leakage audit skipped: {exc})")
        summary["leakage_audit"] = None

    summary["orphan_plots"] = _find_orphan_timeseries(df, output_dir)

    return summary


def _find_orphan_timeseries(df: pd.DataFrame, output_dir: str) -> list[str]:
    """Per-run plots in output_dir whose source file is no longer in the table.

    The aggregate outputs (stats, correlation, PCA) are recomputed from
    feature_table.csv on every run, so they always reflect the current dataset.
    The per-run time-series PNGs are not: they are written once per source file
    and never removed, so a capture that gets archived or re-exported leaves its
    plot behind. The folder then shows more runs than the dataset contains, and
    nothing says which are real.

    Found on wormhole/star (2026-07-27): the first star r1 attempt was archived
    after being re-run, but its 6 time-series plots stayed in eda_output/ — 18
    plots for a 12-file dataset, 6 of them depicting a discarded run.

    Reported, not deleted — same reasoning as trim_run.py's stale check.
    """
    if "source_file" not in df.columns:
        return []
    current = {os.path.splitext(str(s))[0] for s in df["source_file"].unique()}
    # The whole-run overlay is named after the run, not a file (plot_time_series
    # view 1). Without this every overlay was reported stale on every pass.
    id_cols = [c for c in ("attack", "topology", "location", "run_repeat") if c in df.columns]
    if id_cols:
        runs = df[id_cols].astype(str).agg("_".join, axis=1).unique()
        current |= {str(r).replace(".csv", "").replace("/", "_") for r in runs}
    prefix = "timeseries_"
    orphans = []
    for path in sorted(glob.glob(os.path.join(output_dir, prefix + "*.png"))):
        stem = os.path.basename(path)[len(prefix):-len(".png")]
        if stem not in current:
            orphans.append(os.path.basename(path))
    return orphans


def main():
    import argparse
    parser = argparse.ArgumentParser(
        description="NIS16 Milestone 8 — Exploratory Data Analysis"
    )
    parser.add_argument("feature_table", help="Path to feature_table.csv (M7's output)")
    parser.add_argument(
        "-o", "--output-dir", default="eda_output",
        help="Directory to write plots and tables into (default: eda_output)",
    )
    args = parser.parse_args()

    print(f"Running EDA on: {args.feature_table}")
    summary = run_eda(args.feature_table, args.output_dir)

    print()
    print("── EDA Summary ─────────────────────────────────────")
    print(f"  Descriptive statistics:  {summary['descriptive_statistics']}")
    print(f"  Distribution plots:      {len(summary['distribution_plots'])} written")
    print(f"  Time-series plots:       {len(summary['time_series_plots'])} written")
    print(f"  Correlation plots:       {summary['correlation_pearson_plot']}, "
          f"{summary['correlation_spearman_plot']}")
    if summary["correlation_excluded_columns"]:
        print(f"    excluded (all-NaN): {summary['correlation_excluded_columns']}")
    print(f"  PCA/t-SNE plot:          {summary['dimensionality_reduction_plot']}")
    if summary["dimensionality_reduction_excluded_columns"]:
        print(f"    excluded: {summary['dimensionality_reduction_excluded_columns']}")
    # The projection can legitimately produce nothing to look at (root-only or
    # otherwise flat capture). That is written into the PNG, but say it here too —
    # otherwise the run reads as fully successful and nobody opens the file.
    if summary.get("dimensionality_reduction_error"):
        print("    [!] no projection drawn — "
              + " ".join(summary["dimensionality_reduction_error"].split()))
    elif summary.get("dimensionality_reduction_tsne_skipped"):
        print("    [!] " + " ".join(summary["dimensionality_reduction_tsne_skipped"].split()))
    tunnel_plot = summary.get("tunnel_end_projection_plot")
    tunnel_info = summary.get("tunnel_end_projection") or {}
    if tunnel_plot:
        print(f"  Tunnel-end projection:   {tunnel_plot}")
        print(f"    {tunnel_info.get('n_rows_used', '?')} window(s) from "
              f"{tunnel_info.get('n_nodes', '?')} tunnel-end node(s); "
              f"tunnel features kept: {tunnel_info.get('tunnel_columns_kept') or 'none'}")
    else:
        print(f"  Tunnel-end projection:   skipped — {tunnel_info.get('skipped', 'n/a')}")
    orphans = summary.get("orphan_plots") or []
    if orphans:
        print(f"  [!] {len(orphans)} STALE per-run plot(s) — source no longer in the "
              f"feature table (archived or re-exported run):")
        for name in orphans:
            print(f"        {name}")
        print("      Aggregate outputs are current; delete these so the folder "
              "matches the dataset.")
    print(f"  All outputs in:          {args.output_dir}/")
    print("───────────────────────────────────────────────────────")


if __name__ == "__main__":
    main()

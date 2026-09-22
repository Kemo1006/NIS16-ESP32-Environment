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
    "ForwardingRatio": "packets forwarded ÷ received (0–1)",
    "IngressEgressDelta": "packets received − forwarded",
    "RetryRate": "MAC retries ÷ transmissions (0–1)",
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
# Fixed per role so "victim" is the same colour in every figure; seaborn's
# default assigns colours by first appearance, which differs per feature.
ROLE_COLORS = {"victim": "#4c72b0", "root": "#55a868", "blackhole": "#dd8452",
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
    (baseline/blackhole/wormhole) — useful for spotting which features
    shift between phases before formal distribution plots.
    """
    present = [c for c in FEATURE_COLUMNS if c in df.columns]
    label_col = "Label" if "Label" in df.columns else "window_label"

    rows = []
    for label_val, group in df.groupby(label_col):
        label_name = LABEL_NAMES.get(label_val, str(label_val))
        for col in present:
            series = group[col]
            n_valid = series.notna().sum()
            rows.append({
                "label": label_name,
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
        features = ["ForwardingRatio", "RetryRate", "RSSI_Hop_Diff"]

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
            try:
                sns.histplot(
                    data=hist_df,
                    x=feat, hue="Phase", hue_order=order, palette=palette,
                    kde=True, ax=axes[0], bins=nbins,
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
                note = (f"Every window has {feat} = {valid[feat].iloc[0]:g}.\n"
                        "Nothing varies, so there is no distribution to compare.")
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


def _phase_spans(run_df: pd.DataFrame) -> list[tuple[float, float, str, str]]:
    """
    Contiguous (start, end, phase name, colour) runs for background shading.

    Compares phase NAMES, not the raw Label: Label is NaN on unlabelled windows
    and NaN != NaN, so the old label comparison opened a new span on every
    unlabelled window and stacked hundreds of translucent red spans into a
    solid block that looked like the attack. Taken from the first row per
    window_start — all nodes in a run share the root's broadcast schedule.
    """
    if "window_start" not in run_df.columns:
        return []
    ordered = run_df.sort_values("window_start").drop_duplicates("window_start")
    if ordered.empty:
        return []
    names = _phase_names(ordered).tolist()
    starts = ordered["window_start"].tolist()
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


def plot_time_series(
    df: pd.DataFrame,
    output_dir: str,
    features: list[str] | None = None,
) -> list[str]:
    """
    Plots selected feature trajectories over run duration (window_start)
    per node, to visualize temporal alignment of manipulation windows —
    per the thesis: "Selected feature trajectories (e.g., parent switch
    events, PDR)". Defaults to exactly those two.

    One figure per RUN (not per source_file/node — see _extract_run_id's
    docstring for why those differ), with one line per node within that
    run, matching how a person would actually want to inspect "did phase
    transitions align across nodes within this run", which is the
    thesis's stated purpose for this analysis.
    """
    if features is None:
        features = ["ParentSwitchRate", "PDR"]

    df = df.copy()
    df["_run_id"] = df["source_file"].apply(_extract_run_id)

    written = []
    for run_id, run_df in df.groupby("_run_id"):
        run_df = run_df.sort_values("window_start")

        fig, axes = plt.subplots(len(features), 1, figsize=(12, 3.6 * len(features)), sharex=True)
        if len(features) == 1:
            axes = [axes]
        fig.suptitle(f"Feature trajectories over the run — {run_id}\n"
                     "Background colour = experiment phase at that time", fontsize=11)
        phase_spans = _phase_spans(run_df)

        for ax, feat in zip(axes, features):
            if feat not in run_df.columns:
                ax.text(0.5, 0.5, f"'{feat}' not in dataset", ha="center", va="center",
                         transform=ax.transAxes, color="gray")
                continue

            plotted_any = False
            for node_id, node_df in run_df.groupby("node_id"):
                node_df = node_df.sort_values("window_start")
                if node_df[feat].notna().any():
                    role = (node_df["node_role"].iloc[0]
                            if "node_role" in node_df.columns else None)
                    ax.plot(
                        node_df["window_start"], node_df[feat],
                        linewidth=1.2, color="#222222" if run_df["node_id"].nunique() == 1 else None,
                        label=f"{node_id} ({role})" if role else node_id,
                    )
                    plotted_any = True

            # An all-NaN feature (PDR on a root-only capture, say) draws no lines
            # at all. Say so on the axis, the same way the missing-column branch
            # above does, rather than leaving a blank panel — and skip the legend,
            # which warns "No artists with labels found" when nothing was plotted.
            if not plotted_any:
                ax.text(0.5, 0.5, f"no data for '{feat}' in this run",
                        ha="center", va="center", transform=ax.transAxes,
                        color="gray")

            for start, end, name, color in phase_spans:
                ax.axvspan(start, end, color=color, alpha=0.13, linewidth=0, zorder=0)

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

        axes[-1].set_xlabel("Run time — window_start (s)")
        fig.tight_layout(rect=(0, 0.05 if phase_spans else 0, 1, 1))

        safe_name = str(run_id).replace(".csv", "").replace("/", "_")
        out_path = os.path.join(output_dir, f"timeseries_{safe_name}.png")
        fig.savefig(out_path, dpi=120)
        plt.close(fig)
        written.append(out_path)

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
    columns listed in leakage.LEAKING_COLUMNS. Correlating a feature against
    the attack's own switch measures the switch, not a cross-layer
    relationship: ConsistencyScore is |ForwardingRatio - 1| to 1.1e-16, so
    leaving both in manufactures a perfect correlation that says nothing about
    the network. Pass False for the attacker-side diagnostic view.
    """
    candidate_cols = [c for c in FEATURE_COLUMNS if c in df.columns]
    if exclude_leaking:
        candidate_cols = [c for c in candidate_cols if c not in leakage.LEAKING_COLUMNS]
    excluded = _detect_allnan_columns(df, candidate_cols)
    usable_cols = [c for c in candidate_cols if c not in excluded]

    numeric_df = df[usable_cols].apply(pd.to_numeric, errors="coerce")

    pearson = numeric_df.corr(method="pearson")
    spearman = numeric_df.corr(method="spearman")

    return pearson, spearman, excluded


def plot_correlation_heatmaps(
    df: pd.DataFrame,
    output_dir: str,
) -> tuple[str, str, list[str]]:
    pearson, spearman, excluded = compute_correlations(df)

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

        title = (f"{name.capitalize()} correlation between features "
                 f"({len(df)} windows, all nodes and phases)\n{method_blurb[name]}")
        if excluded:
            # Wrap the excluded-columns list manually rather than relying
            # on matplotlib's title auto-wrap (which doesn't wrap titles
            # by default and was clipping the last column name off the
            # right edge of the figure).
            excluded_text = "Not shown (no data in this run): " + ", ".join(excluded)
            title += "\n" + textwrap.fill(excluded_text, width=110)
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
        out_path = os.path.join(output_dir, f"correlation_{name}.png")
        fig.savefig(out_path, dpi=120)
        plt.close(fig)

    pearson_path = os.path.join(output_dir, "correlation_pearson.png")
    spearman_path = os.path.join(output_dir, "correlation_spearman.png")
    return pearson_path, spearman_path, excluded


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
        [c for c in candidate_cols if c in leakage.LEAKING_COLUMNS]
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

    scaler = StandardScaler()
    X_scaled = scaler.fit_transform(X)

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
    return f"PCA (PC1: {var_explained[0]:.1%} var, PC2: {var_explained[1]:.1%} var)"


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

def run_eda(feature_table_path: str, output_dir: str) -> dict:
    """
    Runs all five thesis-specified analyses against a feature_table.csv
    (M7's output) and writes plots + tables to output_dir. Returns a
    summary dict for printing or further inspection.
    """
    _ensure_dir(output_dir)
    df = pd.read_csv(feature_table_path)

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

    pearson_df, spearman_df, _ = compute_correlations(df)
    pearson_df.to_csv(os.path.join(output_dir, "correlation_pearson.csv"))
    spearman_df.to_csv(os.path.join(output_dir, "correlation_spearman.csv"))

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

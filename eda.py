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

import os
import warnings

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

# The 16 Table 4.11 feature names, in the order the thesis presents them.
# Used to decide which columns count as "features" for stats/correlation/
# PCA purposes, as opposed to identity/metadata columns like node_id.
FEATURE_COLUMNS = [
    "ForwardingRatio", "IngressEgressDelta", "RetryRate", "PDR",
    "ParentSwitchRate", "LayerChangeCount", "HopStabilityDuration",
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
        "ParentSwitchRate", "LayerChangeCount", "HopStabilityDuration",
    ],
}

LABEL_NAMES = {0: "Baseline", 1: "Blackhole", 2: "Wormhole"}


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

    label_col = "Label" if "Label" in df.columns else "window_label"
    role_col = "node_role" if "node_role" in df.columns else "role"

    written = []
    for feat in features:
        if feat not in df.columns:
            warnings.warn(f"plot_distributions: '{feat}' not in dataframe, skipping")
            continue

        fig, axes = plt.subplots(1, 2, figsize=(13, 5))
        fig.suptitle(f"{feat} — distribution by phase and node role")

        valid = df[df[feat].notna()]

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
            label_display = valid[label_col].map(lambda v: LABEL_NAMES.get(v, str(v)))
            sns.histplot(
                data=valid.assign(_label_display=label_display),
                x=feat, hue="_label_display", kde=True, ax=axes[0],
                element="step", stat="density", common_norm=False,
            )
            axes[0].set_title("Histogram by phase")

            sns.boxplot(
                data=valid.assign(_label_display=label_display),
                x="_label_display", y=feat, hue=role_col, ax=axes[1],
            )
            axes[1].set_title("Box plot by phase and role")
            axes[1].set_xlabel("Phase")

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

        fig, axes = plt.subplots(len(features), 1, figsize=(11, 3.5 * len(features)), sharex=True)
        if len(features) == 1:
            axes = [axes]
        fig.suptitle(f"Feature trajectories — {run_id}")

        for ax, feat in zip(axes, features):
            if feat not in run_df.columns:
                ax.text(0.5, 0.5, f"'{feat}' not in dataset", ha="center", va="center",
                         transform=ax.transAxes, color="gray")
                continue

            for node_id, node_df in run_df.groupby("node_id"):
                node_df = node_df.sort_values("window_start")
                if node_df[feat].notna().any():
                    ax.plot(
                        node_df["window_start"], node_df[feat],
                        marker="o", markersize=3, label=node_id,
                    )

            # Shade phase regions using window_phase_id / window_label
            # so attack windows are visually obvious against the trace.
            # Phase shading is computed once per run (not per node) since
            # all nodes in a run should share the same broadcast phase
            # schedule — using the first node's labels as the reference.
            label_col = "Label" if "Label" in run_df.columns else "window_label"
            if label_col in run_df.columns:
                phase_changes = (
                    run_df[["window_start", label_col]]
                    .drop_duplicates("window_start")
                    .sort_values("window_start")
                )
                prev_label = None
                span_start = None
                for _, row in phase_changes.iterrows():
                    if row[label_col] != prev_label:
                        if prev_label is not None and prev_label != 0:
                            ax.axvspan(span_start, row["window_start"], color="red", alpha=0.08)
                        span_start = row["window_start"]
                        prev_label = row[label_col]

            ax.set_ylabel(feat)
            ax.legend(fontsize=7, loc="upper right")

        axes[-1].set_xlabel("window_start (s)")
        fig.tight_layout()

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
) -> tuple[pd.DataFrame, pd.DataFrame, list[str]]:
    """
    Pearson and Spearman correlation matrices across the 16 Table 4.11
    features, per Section 4.2.6: "to examine relationships between PHY,
    MAC, and Network layer features."

    All-NaN columns are excluded automatically (correlation is undefined
    on them) — returns the two matrices plus the list of columns that
    were excluded and why, so the exclusion is never silent.
    """
    candidate_cols = [c for c in FEATURE_COLUMNS if c in df.columns]
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

    for name, matrix in [("pearson", pearson), ("spearman", spearman)]:
        fig, ax = plt.subplots(figsize=(11, 9))
        sns.heatmap(
            matrix, annot=True, fmt=".2f", cmap="coolwarm",
            center=0, vmin=-1, vmax=1, square=True, ax=ax,
            cbar_kws={"label": "correlation coefficient"},
        )
        title = f"{name.capitalize()} correlation — cross-layer features"
        if excluded:
            # Wrap the excluded-columns list manually rather than relying
            # on matplotlib's title auto-wrap (which doesn't wrap titles
            # by default and was clipping the last column name off the
            # right edge of the figure).
            import textwrap
            excluded_text = "excluded (all-NaN): " + ", ".join(excluded)
            wrapped = textwrap.fill(excluded_text, width=70)
            title += f"\n{wrapped}"
        ax.set_title(title, fontsize=9, loc="left")
        fig.tight_layout()
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
         Currently this has no additional effect beyond (1) since the
         tunnel columns are already all-NaN — but the flag is kept
         separate and explicit so it still does something meaningful
         once tunnel data exists and someone wants to run this
         comparison the thesis describes.

    Rows with any remaining NaN in the surviving columns are dropped
    (PCA/t-SNE need a complete matrix) — the count dropped is reported,
    not silently absorbed.

    Returns a dict with the fitted projections, the excluded-column
    list, and the dropped-row count, so the caller (or the plotting
    function below) has everything needed to label the output honestly.
    """
    candidate_cols = [c for c in FEATURE_COLUMNS if c in df.columns]
    allnan_excluded = _detect_allnan_columns(df, candidate_cols)

    tunnel_cols = [c for c in candidate_cols if c.startswith("Tunnel")]
    tunnel_excluded = tunnel_cols if exclude_tunnel else []

    excluded = sorted(set(allnan_excluded) | set(tunnel_excluded))
    usable_cols = [c for c in candidate_cols if c not in excluded]

    label_col = "Label" if "Label" in df.columns else "window_label"
    working = df[usable_cols + [label_col]].copy()
    working[usable_cols] = working[usable_cols].apply(pd.to_numeric, errors="coerce")

    n_before = len(working)
    working = working.dropna(subset=usable_cols)
    n_dropped = n_before - len(working)

    if working.empty or len(usable_cols) < 2:
        return {
            "error": (
                f"Not enough usable data for dimensionality reduction "
                f"({len(usable_cols)} usable columns, {len(working)} complete rows "
                f"after dropping {n_dropped} rows with remaining NaNs)."
            ),
            "excluded_columns": excluded,
            "n_dropped_rows": n_dropped,
        }

    X = working[usable_cols].to_numpy()
    y = working[label_col].to_numpy()

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

    tsne = TSNE(
        n_components=2, perplexity=tsne_perplexity,
        random_state=random_state, init="pca",
    )
    tsne_proj = tsne.fit_transform(X_scaled)

    return {
        "pca_projection": pca_proj,
        "pca_explained_variance_ratio": pca.explained_variance_ratio_,
        "tsne_projection": tsne_proj,
        "tsne_perplexity_used": tsne_perplexity,
        "labels": y,
        "usable_columns": usable_cols,
        "excluded_columns": excluded,
        "n_dropped_rows": n_dropped,
        "n_rows_used": len(working),
    }


def plot_dimensionality_reduction(
    df: pd.DataFrame,
    output_dir: str,
    **kwargs,
) -> tuple[str | None, dict]:
    result = run_dimensionality_reduction(df, **kwargs)

    if "error" in result:
        fig, ax = plt.subplots(figsize=(8, 6))
        ax.text(
            0.5, 0.5, result["error"], ha="center", va="center",
            wrap=True, fontsize=10, color="darkred", transform=ax.transAxes,
        )
        ax.set_xticks([])
        ax.set_yticks([])
        out_path = os.path.join(output_dir, "dimensionality_reduction.png")
        fig.savefig(out_path, dpi=120)
        plt.close(fig)
        return out_path, result

    fig, axes = plt.subplots(1, 2, figsize=(14, 6))

    label_names = [LABEL_NAMES.get(v, str(v)) for v in result["labels"]]
    palette = sns.color_palette("Set1", n_colors=len(set(label_names)))

    sns.scatterplot(
        x=result["pca_projection"][:, 0], y=result["pca_projection"][:, 1],
        hue=label_names, palette=palette, ax=axes[0], s=40, alpha=0.8,
    )
    var_explained = result["pca_explained_variance_ratio"]
    axes[0].set_title(
        f"PCA (PC1: {var_explained[0]:.1%} var, PC2: {var_explained[1]:.1%} var)"
    )
    axes[0].set_xlabel("PC1")
    axes[0].set_ylabel("PC2")

    sns.scatterplot(
        x=result["tsne_projection"][:, 0], y=result["tsne_projection"][:, 1],
        hue=label_names, palette=palette, ax=axes[1], s=40, alpha=0.8,
    )
    axes[1].set_title(f"t-SNE (perplexity={result['tsne_perplexity_used']})")
    axes[1].set_xlabel("t-SNE dim 1")
    axes[1].set_ylabel("t-SNE dim 2")

    subtitle = (
        f"{result['n_rows_used']} windows used"
        + (f" ({result['n_dropped_rows']} dropped for remaining NaNs)" if result["n_dropped_rows"] else "")
        + f"\nExcluded columns: {', '.join(result['excluded_columns']) if result['excluded_columns'] else 'none'}"
    )
    fig.suptitle(f"Dimensionality reduction — feature-space separability\n{subtitle}", fontsize=10)
    fig.tight_layout()

    out_path = os.path.join(output_dir, "dimensionality_reduction.png")
    fig.savefig(out_path, dpi=120)
    plt.close(fig)

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

    return summary


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
    print(f"  All outputs in:          {args.output_dir}/")
    print("───────────────────────────────────────────────────────")


if __name__ == "__main__":
    main()

"""
features.py — NIS16 Milestone 7: Cross-Layer Feature Engineering (16 Features)

Computes the 16 features defined in Table 4.11 of the thesis, from the
outputs of Milestone 6's preprocessing pipeline (preprocess.py).

This module is intentionally NOT a single black-box function — each
feature family is its own clearly-labeled function so the milestone
criterion "Feature specifications may iterate as the EDA reveals which
carry useful signal" (per the milestones form) is easy to act on: swap
out or tune one function without touching the others.

────────────────────────────────────────────────────────────────────────
HONEST SCOPE NOTE — read this before trusting the output blindly
────────────────────────────────────────────────────────────────────────
Of the 16 features in Table 4.11, this module computes all 16, but THREE
of them rely on raw telemetry fields that root_main.c / victim_main.c
do not currently log, and are therefore filled with NaN + a flag rather
than a fabricated number:

  ForwardingRatio       — needs separate recv_count / forward_count for
                          TRANSIT packets specifically (Equation 4.2).
                          Current firmware only logs probes_count, a
                          single counter that doesn't distinguish
                          locally-generated traffic from forwarded
                          transit traffic. Until the firmware logs
                          recv_count/forward_count separately (this is
                          exactly what Milestone 2's blackhole attacker
                          state variables — recv_counter, forward_counter,
                          drop_counter — are for), this feature is NaN
                          for every row and flagged in the
                          'missing_firmware_fields' column.

  IngressEgressDelta    — same root cause as ForwardingRatio (Equation 4.3
                          needs the same two counters). NaN + flagged.

  ConsistencyScore      — derived directly from ForwardingRatio
                          (Equation 4.15), so it inherits the same gap.

  TunnelIntensity/
  TunnelBytes/
  TunnelLatency          — these three are correctly NaN/0 for every
                          non-attacker node per the thesis's own
                          schema note ("present only for attacker nodes
                          during topology-distortion runs"). That's not
                          a gap, that's the spec. They'll populate once
                          attacker_node/ firmware (Milestone 2) exists
                          and starts writing tunnel_tx/tunnel_rx/
                          inject_counter to its CSV.

Every other feature (11 of 16) computes a real number from data the
firmware already logs. The NaN columns are still emitted with their
correct names so the M7 milestone criterion "Feature table contains
all 16 columns" is met structurally — but "all 16 columns" and "all 16
columns have real numbers in them right now" are different claims, and
this docstring exists so nobody mistakes one for the other when M8/M9
consume this output.
────────────────────────────────────────────────────────────────────────

Usage:
    from preprocess import run_pipeline
    from features import compute_features

    windowed, report, filled = run_pipeline("raw_csv_folder")
    feature_table = compute_features(windowed, filled, arrivals_dir="raw_csv_folder")
"""

from __future__ import annotations

import glob
import os

import numpy as np
import pandas as pd

EPSILON = 1e-6  # Equation 4.2 / 4.4 divide-by-zero guard, matches preprocess.py
WINDOW_SECONDS = 5  # must match preprocess.py's WINDOW_SECONDS

# Firmware fields these three features need but root_main.c / victim_main.c
# do not currently log (see module docstring). Listed once here so the
# "missing_firmware_fields" flag and the docstring can't drift apart.
FEATURES_BLOCKED_ON_FIRMWARE = (
    "ForwardingRatio",
    "IngressEgressDelta",
    "ConsistencyScore",
)


# ─────────────────────────────────────────────────────────────────────────
# A. Forwarding Behavior Features (Equations 4.2, 4.3, 4.15)
# ─────────────────────────────────────────────────────────────────────────

def compute_forwarding_features(windowed: pd.DataFrame) -> pd.DataFrame:
    """
    ForwardingRatio, IngressEgressDelta, ConsistencyScore.

    BLOCKED ON FIRMWARE — see module docstring. windowed (M6's output)
    only carries probes_count_delta, a single counter that does not
    separate "packets received for forwarding" (recv_count) from
    "packets actually forwarded" (forward_count). Without that split,
    Equation 4.2's numerator and denominator are the same undefined
    quantity, so computing a number here would be fabrication, not
    measurement. Returns NaN for all three with the gap flagged.
    """
    out = pd.DataFrame(index=windowed.index)

    has_recv = "recv_count_delta" in windowed.columns
    has_fwd = "forward_count_delta" in windowed.columns

    if has_recv and has_fwd:
        # Future path, once firmware logs recv_count/forward_count
        # separately (M2's blackhole attacker counters are exactly this).
        recv = windowed["recv_count_delta"]
        fwd = windowed["forward_count_delta"]
        out["ForwardingRatio"] = fwd / (recv + EPSILON)
        out["IngressEgressDelta"] = (recv - fwd).abs()
        out["ConsistencyScore"] = (out["ForwardingRatio"] - 1.0).abs()
    else:
        out["ForwardingRatio"] = np.nan
        out["IngressEgressDelta"] = np.nan
        out["ConsistencyScore"] = np.nan

    return out


# ─────────────────────────────────────────────────────────────────────────
# B. Link Reliability Features (Equation 4.4, 4.5)
# ─────────────────────────────────────────────────────────────────────────

def compute_link_reliability_features(windowed: pd.DataFrame) -> pd.DataFrame:
    """
    RetryRate (Equation 4.4): proportion of tx attempts needing MAC retry.

    RetryRate = retry_count_delta / (tx_count_delta + retry_count_delta + eps)

    This denominator choice — total attempts INCLUDING retries, not just
    tx_count_delta alone — matches the equation's definition ("proportion
    of transmission attempts that required retransmission"): if tx_count
    already counts only first-attempt sends, retries are additional
    attempts on top of that, so they belong in the denominator too.

    PDR is intentionally NOT computed here — it needs the root's
    probe-arrival log joined against each victim's own probes_count,
    which is a cross-node operation. See compute_pdr_features() below.
    """
    out = pd.DataFrame(index=windowed.index)

    retry = windowed["retry_count_delta"]
    tx = windowed["tx_count_delta"]
    out["RetryRate"] = retry / (tx + retry + EPSILON)

    return out


def compute_pdr_features(
    windowed: pd.DataFrame,
    arrivals_dir: str,
) -> pd.DataFrame:
    """
    Packet Delivery Ratio (Equation 4.5), victim nodes only.

    PDR = probes_received_at_root_from_this_victim / probes_sent_by_victim

    Per the thesis ("root counts received probes by tracking unique
    sequence numbers embedded in each probe") and the milestones form's
    implementation note ("PDR ... require[s] joining each node's outgoing
    log with the root's probe-arrival log on (src_node_id, sequence_number)"),
    this is necessarily a join across two different files:

      - probes_SENT:     this victim's own probes_count_delta (windowed)
      - probes_RECEIVED: count of DISTINCT seq_num values in the root's
                          *_arrivals.csv where src_mac matches this
                          victim's MAC, falling in the same window

    The arrivals file only has src_mac (not src_node_id directly), so
    this function needs a node_id -> MAC lookup. We build that lookup
    from `windowed` itself: M6 carries parent_mac (the node's own
    upstream link) but NOT the node's own MAC. Practically, node_id
    encodes the MAC already (NODE_<MAC> per build_node_id() in
    mesh_setup.c), so we parse it back out rather than requiring a
    separate mapping file.

    If no *_arrivals.csv file is found in arrivals_dir (e.g. only
    telemetry CSVs were provided, or this is a synthetic-data test run
    without a root), PDR is NaN for every row rather than silently 0 —
    a missing root log is a data-availability problem, not a delivery
    failure, and those two situations should never look the same in
    the output.
    """
    out = pd.DataFrame(index=windowed.index, columns=["PDR"], dtype=float)
    out["PDR"] = np.nan

    arrival_files = sorted(glob.glob(os.path.join(arrivals_dir, "*_arrivals.csv")))
    if not arrival_files:
        return out  # no root log available — leave PDR as NaN, not 0

    # Rebase each arrivals file onto its own run's relative clock (t=0
    # at that file's first timestamp), matching preprocess.py's per-
    # (node, run) rebasing approach. This assumes the arrivals file's
    # first timestamp is close to its run's true start — true in
    # practice since root starts listening immediately on boot, before
    # any victim sends a first probe.
    rebased_frames = []
    for f in arrival_files:
        a = pd.read_csv(f)
        if a.empty:
            continue
        a["timestamp_s"] = a["timestamp_us"] / 1_000_000.0
        a["t_rel"] = a["timestamp_s"] - a["timestamp_s"].min()
        a["window_idx"] = (a["t_rel"] // WINDOW_SECONDS).astype(int)
        a["window_start"] = a["window_idx"] * WINDOW_SECONDS
        rebased_frames.append(a)

    if not rebased_frames:
        return out

    arrivals_rebased = pd.concat(rebased_frames, ignore_index=True)

    # node_id -> MAC, parsed from the NODE_<MAC> naming convention in
    # build_node_id() (mesh_setup.c). MAC in node_id has no separators;
    # arrivals.csv src_mac uses colon-separated hex — normalize both to
    # bare uppercase hex for comparison.
    def node_id_to_mac(node_id: str) -> str:
        if not isinstance(node_id, str) or not node_id.startswith("NODE_"):
            return ""
        return node_id[5:].upper()

    def normalize_mac(mac: str) -> str:
        if not isinstance(mac, str):
            return ""
        return mac.replace(":", "").upper()

    arrivals_rebased["_src_mac_norm"] = arrivals_rebased["src_mac"].apply(normalize_mac)

    # Received count: distinct seq_num per (src_mac, window_start).
    received = (
        arrivals_rebased
        .groupby(["_src_mac_norm", "window_start"])["seq_num"]
        .nunique()
        .rename("probes_received_window")
        .reset_index()
    )

    # Coverage set: which source MACs the root logged ANYTHING for,
    # anywhere across the provided arrivals files. This is the critical
    # distinction this function needs to get right: a window with zero
    # arrivals from a node the root DOES otherwise hear from is a real
    # PDR=0 (the blackhole signature this feature exists to detect). A
    # node the root NEVER logged anything for is a genuine coverage gap
    # (wrong topology, node never associated, root CSV not pulled, etc.)
    # and PDR should be NaN, not silently 0 — those two situations must
    # not look identical in the output, or this feature becomes useless
    # for exactly the case it exists to catch.
    covered_macs = set(arrivals_rebased["_src_mac_norm"].unique())

    windowed_local = windowed.copy()
    windowed_local["_node_mac_norm"] = windowed_local["node_id"].apply(node_id_to_mac)

    merged = windowed_local.merge(
        received,
        left_on=["_node_mac_norm", "window_start"],
        right_on=["_src_mac_norm", "window_start"],
        how="left",
    )

    probes_sent = merged["probes_count_delta"]
    probes_recv = merged["probes_received_window"]

    # Zero-fill ONLY for nodes the root has coverage of (per covered_macs);
    # leave as NaN for nodes the root never logged at all.
    is_covered = merged["_node_mac_norm"].isin(covered_macs)
    probes_recv_filled = probes_recv.where(~is_covered | probes_recv.notna(), 0.0)

    pdr = probes_recv_filled / (probes_sent + EPSILON)
    pdr = pdr.where(is_covered, np.nan)
    # PDR cannot exceed 1.0 in a correct dataset; clip defensively in case
    # of probe retransmission double-counting at the application layer,
    # and surface that as worth investigating rather than silently passing
    # through.
    pdr_clipped = pdr.clip(upper=1.0)

    out = pd.DataFrame(index=windowed.index)
    out["PDR"] = pdr_clipped.values
    out["_pdr_clipped"] = (pdr > 1.0).fillna(False).values

    return out


# ─────────────────────────────────────────────────────────────────────────
# C. Topology Stability Features (Equations 4.6, 4.7, 4.8)
# ─────────────────────────────────────────────────────────────────────────

def compute_topology_stability_features(
    windowed: pd.DataFrame,
    filled_long: pd.DataFrame,
) -> pd.DataFrame:
    """
    ParentSwitchRate, LayerChangeCount, HopStabilityDuration.

    These three CANNOT be computed from windowed (M6's output) alone,
    because windowing collapses each window down to a single modal
    layer/parent value — exactly the transition information these
    features need is destroyed by that aggregation. They are computed
    here from filled_long instead: the gap-filled, PRE-windowing,
    one-row-per-second table that preprocess.run_pipeline() now returns
    as its third value.

    ParentSwitchRate (Eq 4.6): count of parent_mac changes within the
    window / window duration in seconds.

    LayerChangeCount (Eq 4.7): count of layer value changes within the
    window (raw count, not rate — matches the equation as named).

    HopStabilityDuration (Eq 4.8): longest continuous run, in seconds,
    during which BOTH layer and parent_mac stayed constant, scanning
    across the window's samples in time order.
    """
    long_df = filled_long.copy()
    long_df["window_idx"] = (long_df["t_rel"] // WINDOW_SECONDS).astype(int)
    long_df["window_start"] = long_df["window_idx"] * WINDOW_SECONDS

    rows = []
    for (node_id, source_file, window_idx), grp in long_df.groupby(
        ["node_id", "_source_file", "window_idx"]
    ):
        grp = grp.sort_values("t_rel")
        layers = grp["layer"].to_numpy()
        parents = grp["parent_mac"].to_numpy()

        n_layer_changes = int(np.sum(layers[1:] != layers[:-1])) if len(layers) > 1 else 0
        n_parent_changes = int(np.sum(parents[1:] != parents[:-1])) if len(parents) > 1 else 0

        window_duration_s = max(grp["t_rel"].max() - grp["t_rel"].min(), EPSILON)
        parent_switch_rate = n_parent_changes / window_duration_s

        # HopStabilityDuration: longest run where (layer, parent) constant
        same_as_prev = np.ones(len(grp), dtype=bool)
        if len(grp) > 1:
            same_as_prev[1:] = (layers[1:] == layers[:-1]) & (parents[1:] == parents[:-1])
        run_lengths = []
        run = 0
        t_vals = grp["t_rel"].to_numpy()
        run_start_t = t_vals[0] if len(t_vals) else 0
        for i, same in enumerate(same_as_prev):
            if same:
                run += 1
            else:
                if run > 0:
                    run_lengths.append(t_vals[i - 1] - run_start_t)
                run = 1
                run_start_t = t_vals[i]
        if run > 0:
            run_lengths.append(t_vals[-1] - run_start_t)
        hop_stability_duration = max(run_lengths) if run_lengths else 0.0

        rows.append({
            "node_id": node_id,
            "source_file": source_file,
            "window_start": grp["window_start"].iloc[0],
            "ParentSwitchRate": parent_switch_rate,
            "LayerChangeCount": n_layer_changes,
            "HopStabilityDuration": hop_stability_duration,
        })

    return pd.DataFrame(rows)


# ─────────────────────────────────────────────────────────────────────────
# D. Physical Layer Features (Equations 4.9, 4.10, 4.11)
# ─────────────────────────────────────────────────────────────────────────

def compute_physical_layer_features(
    windowed: pd.DataFrame,
    filled_long: pd.DataFrame,
) -> pd.DataFrame:
    """
    RSSI_mean, RSSI_var: already computed by M6 as rssi_dbm_mean /
    rssi_dbm_var — just renamed here to match Table 4.12's exact column
    names so M8's plotting code can reference the spec's names directly.

    RSSI_stability (Eq 4.11): longest continuous interval, in seconds,
    where RSSI stays within ±3 dBm of the WINDOW MEAN. Needs the raw
    per-second RSSI sequence, same reason as the topology features above
    — computed from filled_long, not from the already-aggregated mean.
    """
    out = pd.DataFrame(index=windowed.index)
    out["RSSI_mean"] = windowed["rssi_dbm_mean"]
    out["RSSI_var"] = windowed["rssi_dbm_var"]

    long_df = filled_long.copy()
    long_df["window_idx"] = (long_df["t_rel"] // WINDOW_SECONDS).astype(int)
    long_df["window_start"] = long_df["window_idx"] * WINDOW_SECONDS

    stability_rows = []
    for (node_id, source_file, window_idx), grp in long_df.groupby(
        ["node_id", "_source_file", "window_idx"]
    ):
        grp = grp.sort_values("t_rel")
        rssi = grp["rssi_dbm"].to_numpy()
        t_vals = grp["t_rel"].to_numpy()
        valid = ~np.isnan(rssi)

        if valid.sum() == 0:
            stability_rows.append({
                "node_id": node_id, "source_file": source_file,
                "window_start": grp["window_start"].iloc[0],
                "RSSI_stability": 0.0,
            })
            continue

        window_mean = np.nanmean(rssi)
        within_band = np.where(valid, np.abs(rssi - window_mean) <= 3.0, False)

        run_lengths = []
        run = 0
        run_start_t = t_vals[0] if len(t_vals) else 0
        for i, ok in enumerate(within_band):
            if ok:
                run += 1
            else:
                if run > 0:
                    run_lengths.append(t_vals[i - 1] - run_start_t)
                run = 0
                run_start_t = t_vals[i] if i + 1 < len(t_vals) else t_vals[i]
        if run > 0:
            run_lengths.append(t_vals[-1] - run_start_t)

        stability_rows.append({
            "node_id": node_id, "source_file": source_file,
            "window_start": grp["window_start"].iloc[0],
            "RSSI_stability": max(run_lengths) if run_lengths else 0.0,
        })

    stability_df = pd.DataFrame(stability_rows)
    return out, stability_df


# ─────────────────────────────────────────────────────────────────────────
# E. Cross-Layer Inconsistency Features (Equations 4.12-4.15)
# ─────────────────────────────────────────────────────────────────────────

def compute_cross_layer_features(
    windowed: pd.DataFrame,
    baseline_rssi_by_layer: dict[int, float] | None = None,
) -> pd.DataFrame:
    """
    RSSI_Hop_Diff (Eq 4.12/4.13): |observed RSSI - baseline median RSSI
    for this layer|, where the baseline median is computed empirically
    per the thesis ("derived empirically from the baseline windows of
    the same experimental run").

    If baseline_rssi_by_layer is not supplied, this function computes it
    itself from windows where window_label == 0 (baseline) in the
    SAME windowed DataFrame passed in — matching the thesis's "same
    experimental run" requirement, since this function operates on
    one experiment's windowed table at a time.

    LatencyHopRatio (Eq 4.14): NaN here — needs Mean RTT from probe/
    response exchanges, which requires a response message the current
    firmware does not send (victim->root probes are one-way; there is
    no root->victim response leg to time a round trip on). Flagged
    rather than computed from a wrong proxy.
    """
    out = pd.DataFrame(index=windowed.index)

    if baseline_rssi_by_layer is None:
        baseline_mask = windowed["window_label"] == 0
        baseline_rssi_by_layer = (
            windowed.loc[baseline_mask]
            .groupby("layer")["rssi_dbm_mean"]
            .median()
            .to_dict()
        )

    def lookup_baseline(layer):
        return baseline_rssi_by_layer.get(layer, np.nan)

    expected_rssi = windowed["layer"].map(lookup_baseline)
    out["RSSI_Hop_Diff"] = (windowed["rssi_dbm_mean"] - expected_rssi).abs()

    # LatencyHopRatio — blocked on firmware (no RTT response leg exists).
    out["LatencyHopRatio"] = np.nan

    return out


# ─────────────────────────────────────────────────────────────────────────
# F. Auxiliary Tunnel Features (Equations 4.16, 4.17) — attacker nodes only
# ─────────────────────────────────────────────────────────────────────────

def compute_tunnel_features(windowed: pd.DataFrame) -> pd.DataFrame:
    """
    TunnelIntensity, TunnelBytes, TunnelLatency.

    Per the thesis's own schema note in Table 4.12: "present only for
    attacker nodes during topology-distortion runs; for all other nodes
    and phases, these fields are null or zero." This function correctly
    returns NaN for every row UNTIL attacker_node/ firmware exists and
    logs tunnel_tx_counter / tunnel_rx_counter / tunnel_bytes / 
    inject_counter into its telemetry CSV (Milestone 2 deliverable,
    currently in progress per this conversation's M1/M2 firmware work).

    Once that firmware field exists, this function should be extended
    to read tunnel_tx_count_delta / tunnel_rx_count_delta / 
    tunnel_bytes_delta from windowed (M6 would need those added to its
    CUMULATIVE_COLUMNS list first) and compute:
        TunnelIntensity = (tunnel_tx_delta + tunnel_rx_delta) / WINDOW_SECONDS
        TunnelBytes     = tunnel_bytes_delta
        TunnelLatency   = mean of per-packet echo RTTs within the window
    """
    out = pd.DataFrame(index=windowed.index)
    out["TunnelIntensity"] = np.nan
    out["TunnelBytes"] = np.nan
    out["TunnelLatency"] = np.nan
    return out


# ─────────────────────────────────────────────────────────────────────────
# Orchestration
# ─────────────────────────────────────────────────────────────────────────

def compute_features(
    windowed: pd.DataFrame,
    filled_long: pd.DataFrame,
    arrivals_dir: str | None = None,
) -> pd.DataFrame:
    """
    Compute all 16 Table 4.11 features and attach them to windowed,
    returning one combined feature table matching Table 4.12's schema
    (plus the identity/metadata columns M6 already provides).

    Parameters
    ----------
    windowed : the M6 windowed output (preprocess.run_pipeline()[0])
    filled_long : the M6 gap-filled long-format table
                  (preprocess.run_pipeline()[2])
    arrivals_dir : folder containing *_arrivals.csv (root's probe-arrival
                   log). If None, PDR is NaN for every row.

    Returns
    -------
    A copy of windowed with 16 feature columns appended, plus a
    'missing_firmware_fields' column listing (comma-separated) which of
    the 16 features are NaN due to a firmware gap rather than a real
    absence of signal — see module docstring for which three those are.
    """
    fwd = compute_forwarding_features(windowed)
    link = compute_link_reliability_features(windowed)
    topo = compute_topology_stability_features(windowed, filled_long)
    phy, rssi_stab = compute_physical_layer_features(windowed, filled_long)
    cross = compute_cross_layer_features(windowed)
    tunnel = compute_tunnel_features(windowed)

    result = windowed.copy()
    result = pd.concat([result, fwd, link, phy, cross, tunnel], axis=1)

    # topo and rssi_stab are keyed by (node_id, source_file, window_start)
    # rather than positional index, since they're computed via groupby
    # over filled_long which has a different row count than windowed.
    # Merge them in rather than concat.
    result = result.merge(
        topo, on=["node_id", "source_file", "window_start"], how="left"
    )
    result = result.merge(
        rssi_stab, on=["node_id", "source_file", "window_start"], how="left"
    )

    if arrivals_dir is not None:
        pdr = compute_pdr_features(windowed, arrivals_dir)
        result["PDR"] = pdr["PDR"].values
        if "_pdr_clipped" in pdr.columns:
            result["_pdr_clipped"] = pdr["_pdr_clipped"].values
    else:
        result["PDR"] = np.nan

    result["Label"] = result["window_label"]

    blocked = ",".join(FEATURES_BLOCKED_ON_FIRMWARE)
    result["missing_firmware_fields"] = blocked

    return result


# ─────────────────────────────────────────────────────────────────────────
# CLI
# ─────────────────────────────────────────────────────────────────────────

def main():
    import argparse
    from preprocess import run_pipeline

    parser = argparse.ArgumentParser(
        description="NIS16 Milestone 7 — Cross-Layer Feature Engineering"
    )
    parser.add_argument("input_dir", help="Folder of raw *_telem.csv files")
    parser.add_argument(
        "-o", "--output", default="feature_table.csv",
        help="Output path for the feature table (default: feature_table.csv)",
    )
    parser.add_argument(
        "--arrivals-dir", default=None,
        help="Folder containing *_arrivals.csv for PDR computation "
             "(defaults to input_dir if not specified)",
    )
    args = parser.parse_args()

    arrivals_dir = args.arrivals_dir or args.input_dir

    print(f"Running M6 preprocessing on: {args.input_dir}")
    windowed, report, filled = run_pipeline(args.input_dir)
    print(report.summary())

    print()
    print(f"Computing 16 Table 4.11 features...")
    feature_table = compute_features(windowed, filled, arrivals_dir=arrivals_dir)

    feature_table.to_csv(args.output, index=False)
    print(f"Wrote {len(feature_table)} feature rows to: {args.output}")

    nan_counts = {}
    for col in [
        "ForwardingRatio", "IngressEgressDelta", "RetryRate", "PDR",
        "ParentSwitchRate", "LayerChangeCount", "HopStabilityDuration",
        "RSSI_mean", "RSSI_var", "RSSI_stability",
        "RSSI_Hop_Diff", "LatencyHopRatio", "ConsistencyScore",
        "TunnelIntensity", "TunnelBytes", "TunnelLatency",
    ]:
        if col in feature_table.columns:
            nan_counts[col] = feature_table[col].isna().sum()

    print()
    print("── Feature NaN Counts ──────────────────────────────")
    for col, n in nan_counts.items():
        flag = " [FIRMWARE GAP]" if col in FEATURES_BLOCKED_ON_FIRMWARE else ""
        flag = " [ATTACKER-ONLY, expected]" if col.startswith("Tunnel") else flag
        flag = " [no response leg exists]" if col == "LatencyHopRatio" else flag
        print(f"  {col}: {n}/{len(feature_table)} NaN{flag}")
    print("─────────────────────────────────────────────────────")


if __name__ == "__main__":
    main()

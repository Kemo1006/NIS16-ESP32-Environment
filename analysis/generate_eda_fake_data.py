"""
generate_eda_fake_data.py — larger synthetic dataset for testing eda.py

The M6/M7 test fixtures (fake_data/, from generate_fake_data.py) are
deliberately small and targeted at specific bugs — they're unit tests,
not representative datasets. EDA needs something closer to what a real
multi-run experiment would produce: enough rows per phase to plot a
distribution, enough runs to see correlation structure, and a baseline-
vs-attack separation that resembles the thesis's own stated expected
ranges (Section 4.3.1.2: baseline retry rate <5%, baseline PDR ~0.97).

This generates several synthetic "runs" directly in M7's feature-table
shape (skipping the raw-CSV step, since EDA operates on feature_table.csv,
not on raw telemetry) with:
  - baseline windows: low retry rate, high PDR, low RSSI_Hop_Diff, stable
    topology — matching thesis-stated expected baseline behavior
  - blackhole windows: PDR drops sharply (thesis's own blackhole
    signature), retry rate rises moderately (indirect propagation
    effect per Section 4.3.1.2)
  - wormhole windows: RSSI_Hop_Diff spikes (physical-logical mismatch
    per Section 4.3.1.4), ParentSwitchRate rises

This is synthetic data with injected separation, not a claim about what
the real hardware will produce — it exists so eda.py's plotting and
statistical code can be exercised against data that actually has
structure, rather than only against the sparse M6/M7 debugging
fixtures where 67 of 70 rows are baseline and nothing would show up
on a plot regardless of whether the plotting code was correct.
"""

from __future__ import annotations

import os

import numpy as np
import pandas as pd


def _make_window_rows(
    node_id: str,
    role: str,
    source_file: str,
    n_windows: int,
    label: int,
    rng: np.random.Generator,
    *,
    retry_rate_range: tuple[float, float],
    pdr_range: tuple[float, float],
    rssi_hop_diff_range: tuple[float, float],
    parent_switch_rate_range: tuple[float, float],
    layer: int,
    window_start_offset: int = 0,
) -> list[dict]:
    rows = []
    for i in range(n_windows):
        rows.append({
            "window_start": window_start_offset + i * 5,
            "node_id": node_id,
            "source_file": source_file,
            "node_role": role,
            "layer": layer,
            "parent_mac": "1C:C3:AB:FA:54:98",
            "n_samples_present": 5,
            "n_samples_expected": 5,
            "rssi_dbm_mean": rng.normal(-58, 3),
            "rssi_dbm_var": abs(rng.normal(1.5, 0.5)),
            "rssi_dbm_min": rng.normal(-62, 2),
            "rssi_dbm_max": rng.normal(-54, 2),
            "retry_count_delta": max(0, rng.normal(5, 2)),
            "tx_count_delta": max(1, rng.normal(15, 3)),
            "probes_count_delta": max(0, round(rng.normal(5, 1))),
            "window_label": label,
            "window_phase_id": label,
            # M7 feature columns — the ones EDA actually plots/correlates
            "ForwardingRatio": np.nan,        # firmware gap, see features.py
            "IngressEgressDelta": np.nan,     # firmware gap
            "ConsistencyScore": np.nan,       # firmware gap
            "RetryRate": float(np.clip(rng.uniform(*retry_rate_range), 0, 1)),
            "RSSI_mean": rng.normal(-58, 3),
            "RSSI_var": abs(rng.normal(1.5, 0.5)),
            "RSSI_Hop_Diff": max(0, rng.uniform(*rssi_hop_diff_range)),
            "LatencyHopRatio": np.nan,        # no RTT response leg, see features.py
            "TunnelIntensity": np.nan,        # attacker-only
            "TunnelBytes": np.nan,            # attacker-only
            "TunnelLatency": np.nan,          # attacker-only
            "ParentSwitchRate": max(0, rng.uniform(*parent_switch_rate_range)),
            "LayerChangeCount": rng.poisson(0.1) if label == 0 else rng.poisson(0.6),
            "HopStabilityDuration": rng.uniform(3.5, 5.0) if label == 0 else rng.uniform(1.0, 4.0),
            "RSSI_stability": rng.uniform(3.5, 5.0),
            "PDR": float(np.clip(rng.uniform(*pdr_range), 0, 1)),
            "Label": label,
            "missing_firmware_fields": "ForwardingRatio,IngressEgressDelta,ConsistencyScore",
        })
    return rows


def generate_eda_dataset(output_path: str, seed: int = 100):
    """
    Builds a synthetic feature_table.csv-shaped dataset spanning 4 runs
    (mirroring M4's experimental matrix structure, though only 4 runs
    here, not the real 24+) across the three ground-truth labels:
    0=baseline, 1=blackhole, 2=wormhole. Two node roles (root, victim)
    per run, ~12 windows per node per phase segment.
    """
    rng = np.random.default_rng(seed)
    all_rows = []

    run_configs = [
        ("RUN_001", "star"),
        ("RUN_002", "tree"),
        ("RUN_003", "linear_chain"),
        ("RUN_004", "partial_mesh"),
    ]

    for run_id, topology in run_configs:
        for node_idx, (node_name, role, layer) in enumerate([
            ("NODE_ROOT01", "root", 0),
            ("NODE_VICTIM01", "victim", 1),
            ("NODE_VICTIM02", "victim", 1),
        ]):
            # Real csv_logger.c node_ids are MAC-derived and stable across
            # runs (the board doesn't get a new identity each experiment);
            # only run_id changes per run. Using a fixed node_name here
            # (rather than embedding run_id in it) matches that and avoids
            # a doubled run_id in source_file below.
            node_id = node_name
            source_file = f"{node_id}_{run_id}_telem.csv"
            offset = 0

            # Baseline segment (label 0) — thesis-stated expected ranges:
            # retry rate <5%, PDR ~0.97
            baseline_rows = _make_window_rows(
                node_id, role, source_file, n_windows=12, label=0, rng=rng,
                retry_rate_range=(0.01, 0.05),
                pdr_range=(0.93, 0.99),
                rssi_hop_diff_range=(0.5, 4.0),
                parent_switch_rate_range=(0.0, 0.02),
                layer=layer, window_start_offset=offset,
            )
            all_rows.extend(baseline_rows)
            offset += 12 * 5

            # Attack segment — blackhole for half the runs, wormhole for
            # the other half, alternating, so both attack types appear
            # across the synthetic dataset (only victim/attacker-adjacent
            # nodes show strong attack signal; root's own telemetry is
            # less directly affected, mirrored here by milder ranges)
            is_blackhole = run_configs.index((run_id, topology)) % 2 == 0

            if role == "victim":
                if is_blackhole:
                    attack_rows = _make_window_rows(
                        node_id, role, source_file, n_windows=9, label=1, rng=rng,
                        retry_rate_range=(0.08, 0.18),   # moderate rise, Section 4.3.1.2
                        pdr_range=(0.10, 0.45),           # sharp drop, blackhole signature
                        rssi_hop_diff_range=(1.0, 5.0),   # not primarily a wormhole effect
                        parent_switch_rate_range=(0.0, 0.05),
                        layer=layer, window_start_offset=offset,
                    )
                else:
                    attack_rows = _make_window_rows(
                        node_id, role, source_file, n_windows=9, label=2, rng=rng,
                        retry_rate_range=(0.02, 0.07),    # mild — not the primary signal
                        pdr_range=(0.85, 0.99),           # delivery itself isn't disrupted
                        rssi_hop_diff_range=(10.0, 22.0), # physical-logical mismatch, Section 4.3.1.4
                        parent_switch_rate_range=(0.10, 0.30),  # topology instability
                        layer=layer, window_start_offset=offset,
                    )
            else:
                # root: milder versions of the same shift, since root
                # observes attack effects indirectly via arrivals/topology
                # rather than experiencing them directly
                label = 1 if is_blackhole else 2
                attack_rows = _make_window_rows(
                    node_id, role, source_file, n_windows=9, label=label, rng=rng,
                    retry_rate_range=(0.02, 0.06),
                    pdr_range=(0.90, 0.99),
                    rssi_hop_diff_range=(0.5, 4.0) if is_blackhole else (4.0, 10.0),
                    parent_switch_rate_range=(0.0, 0.03) if is_blackhole else (0.03, 0.12),
                    layer=layer, window_start_offset=offset,
                )
            all_rows.extend(attack_rows)
            offset += 9 * 5

            # Cooldown segment — back to baseline label, slightly noisier
            # than the initial baseline (residual effects)
            cooldown_rows = _make_window_rows(
                node_id, role, source_file, n_windows=6, label=0, rng=rng,
                retry_rate_range=(0.01, 0.07),
                pdr_range=(0.88, 0.99),
                rssi_hop_diff_range=(0.5, 5.0),
                parent_switch_rate_range=(0.0, 0.04),
                layer=layer, window_start_offset=offset,
            )
            all_rows.extend(cooldown_rows)

    df = pd.DataFrame(all_rows)
    df.to_csv(output_path, index=False)
    print(f"Wrote {len(df)} synthetic feature rows ({df['node_id'].nunique()} nodes, "
          f"{len(run_configs)} runs) -> {output_path}")
    print(f"  Label distribution: {df['Label'].value_counts().sort_index().to_dict()}")
    return df


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser(description="Generate larger synthetic dataset for EDA testing")
    parser.add_argument("-o", "--output", default="eda_fake_data/feature_table.csv")
    args = parser.parse_args()
    os.makedirs(os.path.dirname(args.output) or ".", exist_ok=True)
    generate_eda_dataset(args.output)

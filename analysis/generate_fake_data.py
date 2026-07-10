"""
generate_fake_data.py — synthetic *_telem.csv generator for testing preprocess.py

Produces files matching the EXACT schema csv_logger.c writes:
  timestamp_us,node_id,role,layer,parent_mac,rssi_dbm,retry_count,
  tx_count,probes_count,phase_id,gt_label

This lets Milestone 6 be built, tested, and demoed before Milestone 1
hardware is fully working — the pipeline only cares about the CSV shape,
not where the rows came from.

Simulates a 3-node baseline-only run (root + 2 victims) at 1 Hz for a
configurable duration, with controllable gap injection so the
missing-data handling path (linear interpolation / forward-fill /
window discard) can be exercised and verified.
"""

from __future__ import annotations

import argparse
import os
import random

import numpy as np
import pandas as pd


def generate_node_csv(
    node_id: str,
    role: str,
    layer: int,
    parent_mac: str,
    duration_s: int,
    rssi_base: float,
    rssi_noise: float,
    out_path: str,
    gap_indices: set[int] | None = None,
    seed: int = 0,
):
    """
    Write one synthetic *_telem.csv file.

    gap_indices: set of sample indices (0-based, seconds since start) to
    DROP from the output, simulating missed/lost telemetry rows. Use
    this to test the gap-handling logic in preprocess.py — e.g. pass
    {10} for a single 1s gap (should interpolate), or {10, 11, 12} for
    a 3s gap (should trigger window discard).
    """
    rng = np.random.default_rng(seed)
    gap_indices = gap_indices or set()

    rows = []
    retry_cum = 0
    tx_cum = 0
    probes_cum = 0

    for t in range(duration_s):
        if t in gap_indices:
            continue  # simulate a dropped/missing sample

        # Phase schedule mirrors the M1 baseline-only run:
        # 0-9s stabilise (label still baseline), 10s+ baseline proper.
        # Real runs would have attack phases here too; for M6 testing,
        # a flat baseline run is sufficient to validate the windowing
        # logic, and a second generated run below adds an attack phase
        # to exercise modal-label assignment across a transition.
        phase_id = 0
        gt_label = 0

        rssi = rssi_base + rng.normal(0, rssi_noise)
        retry_cum += rng.integers(0, 3)
        tx_cum += rng.integers(1, 4)
        probes_cum += rng.integers(0, 2) if role != "root" else 0

        rows.append({
            "timestamp_us": t * 1_000_000,
            "node_id": node_id,
            "role": role,
            "layer": layer,
            "parent_mac": parent_mac,
            "rssi_dbm": round(rssi, 1),
            "retry_count": retry_cum,
            "tx_count": tx_cum,
            "probes_count": probes_cum,
            "phase_id": phase_id,
            "gt_label": gt_label,
        })

    df = pd.DataFrame(rows)
    df.to_csv(out_path, index=False)
    print(f"  Wrote {len(df)} rows ({len(gap_indices)} gaps injected) -> {out_path}")


def generate_run_with_attack_phase(
    node_id: str,
    role: str,
    layer: int,
    parent_mac: str,
    out_path: str,
    seed: int = 1,
):
    """
    Generate a fuller run: 10s stabilise + 20s baseline + 15s attack
    (blackhole-style, label=1) + 10s cooldown, at 1 Hz, no gaps.
    Used to verify modal-label assignment correctly picks the dominant
    label in windows that straddle a phase transition.
    """
    rng = np.random.default_rng(seed)
    rows = []
    retry_cum = 0
    tx_cum = 0
    probes_cum = 0

    schedule = (
        [(0, 0)] * 10   # stabilise -> baseline label
        + [(0, 0)] * 20  # baseline
        + [(1, 1)] * 15  # blackhole attack
        + [(3, 0)] * 10  # cooldown -> baseline label again
    )

    for t, (phase_id, gt_label) in enumerate(schedule):
        rssi = -55 + rng.normal(0, 2.0)
        retry_cum += rng.integers(0, 3)
        tx_cum += rng.integers(1, 4)
        probes_cum += rng.integers(0, 2) if role != "root" else 0

        rows.append({
            "timestamp_us": t * 1_000_000,
            "node_id": node_id,
            "role": role,
            "layer": layer,
            "parent_mac": parent_mac,
            "rssi_dbm": round(rssi, 1),
            "retry_count": retry_cum,
            "tx_count": tx_cum,
            "probes_count": probes_cum,
            "phase_id": phase_id,
            "gt_label": gt_label,
        })

    df = pd.DataFrame(rows)
    df.to_csv(out_path, index=False)
    print(f"  Wrote {len(df)} rows (with attack phase) -> {out_path}")


def generate_topology_switch_fixture(out_path: str, seed: int = 50):
    """
    40s run where layer/parent_mac switches mid-window (at t=22, inside
    the window covering t=20-24) rather than on a window boundary.

    This specific timing matters: a switch landing exactly ON a window
    boundary produces zero detected events, because each window only
    diffs samples WITHIN itself — the transition becomes invisible,
    split across two windows that each individually look stable. Only a
    mid-window switch actually exercises the within-window diff logic
    in features.compute_topology_stability_features(). An earlier version
    of this fixture put the switch at t=20 exactly and silently passed a
    broken test as a result — this timing was chosen specifically to
    avoid that trap.
    """
    rng = np.random.default_rng(seed)
    rows = []
    retry_cum = tx_cum = probes_cum = 0

    for t in range(40):
        if t < 22:
            layer, parent = 1, "1C:C3:AB:FA:54:98"
        else:
            layer, parent = 2, "AA:BB:CC:DD:EE:FF"

        rssi = -55 + rng.normal(0, 1.5)
        retry_cum += rng.integers(0, 3)
        tx_cum += rng.integers(1, 4)
        probes_cum += rng.integers(0, 2)

        rows.append({
            "timestamp_us": t * 1_000_000, "node_id": "NODE_TOPOTEST",
            "role": "victim", "layer": layer, "parent_mac": parent,
            "rssi_dbm": round(rssi, 1), "retry_count": retry_cum,
            "tx_count": tx_cum, "probes_count": probes_cum,
            "phase_id": 0, "gt_label": 0,
        })

    pd.DataFrame(rows).to_csv(out_path, index=False)
    print(f"  Wrote topology-switch fixture (mid-window switch at t=22) -> {out_path}")


def generate_pdr_fixtures(victim_path: str, arrivals_path: str, seed: int = 60):
    """
    A matched victim/root pair for testing PDR end-to-end. The victim's
    node_id follows the real NODE_<MAC> convention (build_node_id() in
    mesh_setup.c) so features.compute_pdr_features()'s node_id->MAC
    parsing has something real to match against — most other fixtures in
    this file use human-readable ids like NODE_VICTIM01, which are
    correct for testing windowing/missing-data logic but cannot exercise
    the MAC-matching join PDR depends on.

    Victim sends one probe every other second (2 per 5s window); root
    receives all of them. Expected PDR = 1.0 in every window — this
    fixture tests the "happy path" of the join. See
    generate_blackhole_pdr_fixtures() for the path where PDR should
    legitimately drop.
    """
    node_id = "NODE_2805A532D7B4"
    mac = "28:05:A5:32:D7:B4"

    vrows = []
    probes_cum = 0
    rng = np.random.default_rng(seed)
    for t in range(60):
        probes_cum += 1 if t % 2 == 0 else 0
        vrows.append({
            "timestamp_us": t * 1_000_000, "node_id": node_id, "role": "victim",
            "layer": 1, "parent_mac": "1C:C3:AB:FA:54:98",
            "rssi_dbm": round(-58 + rng.normal(0, 1), 1),
            "retry_count": t, "tx_count": t * 2, "probes_count": probes_cum,
            "phase_id": 0, "gt_label": 0,
        })
    pd.DataFrame(vrows).to_csv(victim_path, index=False)

    arows = []
    seq = 0
    for t in range(60):
        if t % 2 == 0:
            arows.append({
                "timestamp_us": t * 1_000_000, "node_id": "NODE_ROOT01",
                "role": "root", "layer": 0, "parent_mac": "00:00:00:00:00:00",
                "rssi_dbm": -50, "retry_count": 0, "tx_count": 0,
                "probes_received": 1, "phase_id": 0, "gt_label": 0,
                "src_mac": mac, "seq_num": seq, "latency_us": 5000,
            })
            seq += 1
    pd.DataFrame(arows).to_csv(arrivals_path, index=False)

    print(f"  Wrote matched PDR fixture pair (expected PDR=1.0) -> {victim_path}, {arrivals_path}")


def generate_blackhole_pdr_fixtures(victim_path: str, arrivals_path: str):
    """
    Victim sends 1 probe/sec continuously for 20s (4 per 5s window).
    Root only logs arrivals for the first 10s, then stops — simulating
    a blackhole attacker silently dropping probes starting at t=10.

    Expected PDR: 1.0 for windows at t=0-9 (root heard everything),
    then 0.0 (not NaN) for windows at t=10+, since the root DOES have
    coverage of this node (it heard from it during 0-9s) — a window
    with zero arrivals from an otherwise-covered node is a real
    PDR=0, which is the actual blackhole detection signature this
    feature exists to produce.

    This is the single most important fixture in this file: an earlier
    version of features.compute_pdr_features() returned NaN for these
    windows instead of 0.0, because it couldn't distinguish "root never
    heard from this node" from "root usually hears from this node but
    didn't this window" — which would have made the blackhole's exact
    expected signature invisible as NaN instead of visible as a PDR
    drop. If this fixture's t=10+ windows ever show NaN again instead
    of 0.0, that regression has come back.
    """
    node_id = "NODE_AABBCCDDEEFF"
    mac = "AA:BB:CC:DD:EE:FF"

    vrows = []
    probes_cum = 0
    for t in range(20):
        probes_cum += 1
        vrows.append({
            "timestamp_us": t * 1_000_000, "node_id": node_id, "role": "victim",
            "layer": 1, "parent_mac": "1C:C3:AB:FA:54:98", "rssi_dbm": -55,
            "retry_count": t, "tx_count": t, "probes_count": probes_cum,
            "phase_id": 0, "gt_label": 0,
        })
    pd.DataFrame(vrows).to_csv(victim_path, index=False)

    arows = []
    seq = 0
    for t in range(10):  # root only hears the first half — simulated blackhole
        arows.append({
            "timestamp_us": t * 1_000_000, "node_id": "NODE_ROOT01",
            "role": "root", "layer": 0, "parent_mac": "00:00:00:00:00:00",
            "rssi_dbm": -50, "retry_count": 0, "tx_count": 0,
            "probes_received": 1, "phase_id": 0, "gt_label": 0,
            "src_mac": mac, "seq_num": seq, "latency_us": 4000,
        })
        seq += 1
    pd.DataFrame(arows).to_csv(arrivals_path, index=False)

    print(f"  Wrote blackhole-PDR fixture (expects PDR: 1.0 -> 1.0 -> 0.0 -> 0.0) -> {victim_path}, {arrivals_path}")


def main():
    parser = argparse.ArgumentParser(
        description="Generate synthetic NIS16 telemetry CSVs for testing preprocess.py"
    )
    parser.add_argument(
        "-o", "--output-dir",
        default="fake_data",
        help="Directory to write synthetic CSVs into (default: fake_data)",
    )
    parser.add_argument(
        "--duration", type=int, default=60,
        help="Duration in seconds for the simple baseline run (default: 60)",
    )
    args = parser.parse_args()

    os.makedirs(args.output_dir, exist_ok=True)

    print("Generating synthetic 3-node baseline run (clean, no gaps)...")
    generate_node_csv(
        node_id="NODE_ROOT01", role="root", layer=0, parent_mac="00:00:00:00:00:00",
        duration_s=args.duration, rssi_base=-50, rssi_noise=1.5,
        out_path=os.path.join(args.output_dir, "NODE_ROOT01_RUN_001_telem.csv"),
        seed=10,
    )
    generate_node_csv(
        node_id="NODE_VICTIM01", role="victim", layer=1, parent_mac="1C:C3:AB:FA:54:98",
        duration_s=args.duration, rssi_base=-58, rssi_noise=2.0,
        out_path=os.path.join(args.output_dir, "NODE_VICTIM01_RUN_001_telem.csv"),
        seed=20,
    )
    generate_node_csv(
        node_id="NODE_VICTIM02", role="victim", layer=1, parent_mac="1C:C3:AB:FA:54:98",
        duration_s=args.duration, rssi_base=-62, rssi_noise=2.5,
        out_path=os.path.join(args.output_dir, "NODE_VICTIM02_RUN_001_telem.csv"),
        seed=30,
        # Inject a single 1-second gap at t=25 (should be interpolated,
        # window kept) and a 3-second gap at t=40-42 (should trigger
        # window discard for that window).
        gap_indices={25, 40, 41, 42},
    )

    print()
    print("Generating synthetic run with an attack phase (for modal-label testing)...")
    generate_run_with_attack_phase(
        node_id="NODE_VICTIM01", role="victim", layer=1, parent_mac="1C:C3:AB:FA:54:98",
        out_path=os.path.join(args.output_dir, "NODE_VICTIM01_RUN_002_telem.csv"),
        seed=40,
    )

    print()
    print("Generating M7-specific fixtures (topology switch, PDR matching)...")
    generate_topology_switch_fixture(
        os.path.join(args.output_dir, "NODE_TOPOTEST_RUN_003_telem.csv"),
    )
    generate_pdr_fixtures(
        os.path.join(args.output_dir, "NODE_2805A532D7B4_RUN_001_telem.csv"),
        os.path.join(args.output_dir, "NODE_ROOT01_RUN_001_arrivals.csv"),
    )
    generate_blackhole_pdr_fixtures(
        os.path.join(args.output_dir, "NODE_AABBCCDDEEFF_RUN_001_telem.csv"),
        os.path.join(args.output_dir, "NODE_AABBCCDDEEFF_RUN_001_arrivals.csv"),
    )

    print()
    print(f"Done. Synthetic CSVs written to: {args.output_dir}/")
    print(f"Run the M6 pipeline with:")
    print(f"  python preprocess.py {args.output_dir} -o windowed_dataset.csv")
    print(f"Run the M7 feature pipeline with:")
    print(f"  python features.py {args.output_dir} -o feature_table.csv")


if __name__ == "__main__":
    main()

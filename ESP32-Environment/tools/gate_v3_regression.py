"""Regression gate for the schema-v3 rewrite (D-44): old tables vs regenerated tables.

For every cell it compares the 16 model features (and row counts) of a baseline copy of
`feature_table.csv` against the regenerated one under datasets/analysis. Differences are
classified, not just counted:
  EXPECTED  RetryRate on rows of a node that originates no probes (blackhole attacker,
            root, wormhole end A): the old table showed 0.0 (it divided the attacker's
            FORWARD count by itself), the new one is blank (nothing to measure).
  EXPECTED-B RetryRate on wormhole_b rows: in v1/v2 that node's retry_count was its TUNNEL count, so the
            old RetryRate was tunnelled/(sent+tunnelled); v3 reads its real failed sends (own_failed).
  UNEXPECTED any other feature difference > 1e-12  -> the gate fails.
Compare against tables made by the OLD code on the SAME input (not against older saved tables, which can
be stale against newer data/code).
Sniffer columns (Mac*) are ignored: they did not exist in the baseline copies.

Usage: python tools/gate_v3_regression.py <baseline_tables_dir>
"""
import os
import sys

import numpy as np
import pandas as pd

HERE = os.path.dirname(os.path.abspath(__file__))
NEW = os.path.normpath(os.path.join(HERE, "..", "datasets", "analysis"))
FEATURES = ["ForwardingRatio", "IngressEgressDelta", "ConsistencyScore", "RetryRate", "PDR",
            "NeighbourForwardingRatio", "TunnelIntensity", "TunnelBytes", "TunnelLatency"]
NO_ORIGIN = {"blackhole", "root", "wormhole_a"}


def main(base):
    cells = fails = n_expected = n_b = 0
    for dp, _, names in os.walk(base):
        if "feature_table.csv" not in names:
            continue
        rel = os.path.relpath(dp, base)
        new_p = os.path.join(NEW, rel, "feature_table.csv")
        if not os.path.exists(new_p):
            print("MISSING new table:", rel); fails += 1; continue
        a = pd.read_csv(os.path.join(dp, "feature_table.csv"))
        b = pd.read_csv(new_p)
        cells += 1
        if len(a) != len(b):
            print(f"ROW COUNT {rel}: {len(a)} -> {len(b)}"); fails += 1; continue
        # the feature set can grow (new features are fine); every old feature column must still be equal
        legacy = ("retry_count", "tx_count", "probes_count")
        feats = [c for c in a.columns if c in b.columns and not c.startswith(("Mac",) + legacy)]
        for c in feats:
            if a[c].dtype.kind not in "fiu" or b[c].dtype.kind not in "fiu":
                continue
            x, y = a[c].to_numpy(float), b[c].to_numpy(float)
            diff = ~((np.isnan(x) & np.isnan(y)) | (np.abs(x - y) <= 1e-12))
            if not diff.any():
                continue
            if c == "RetryRate":
                role = a["node_role"].astype(str)
                exp = diff & role.isin(NO_ORIGIN).to_numpy() & np.isnan(y)
                n_expected += int(exp.sum())
                diff = diff & ~exp
                expb = diff & (role == "wormhole_b").to_numpy()
                n_b += int(expb.sum())
                diff = diff & ~expb
            if diff.any():
                print(f"UNEXPECTED {rel}: {c} differs in {int(diff.sum())} window(s)"); fails += 1
    print(f"\n{cells} cells compared; expected RetryRate-blank windows: {n_expected}; wormhole_b RetryRate (tunnel count -> failed sends): {n_b}; problems: {fails}")
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))

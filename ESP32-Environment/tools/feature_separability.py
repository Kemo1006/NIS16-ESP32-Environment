#!/usr/bin/env python3
"""
feature_separability.py - Single-feature separability audit.

PANEL REQUIREMENT (CTTHES): the dataset must NOT be decided by one feature. If a
single feature out of 16 trivially separates attack from normal (1 = attack, 0 =
not), then the other 15 are irrelevant and clustering/ML is pointless. This audit
QUANTIFIES each feature's standalone separability so we can:
  (a) prove the attack signal is a CONFLUENCE of cross-layer features, not one, and
  (b) flag pure-artifact features (the auxiliary tunnel counters) to EXCLUDE from
      the clustering input (matches eda.py's exclude_tunnel + thesis Sec 4.2.5.1).

Method (both standard; see docs/2026-09-14_REFERENCES.md):
  - AUC / ROC per feature vs the binary attack label   (Fawcett 2006).
  - Mutual information per feature vs the label         (Ross 2014; sklearn
                                                         mutual_info_classif).
  - Coverage = fraction of rows where the feature is defined (non-NaN). A feature
    that separates perfectly but is defined on few rows (role-exclusive) CANNOT
    label the whole dataset by itself. The dangerous case is high separability AND
    high coverage together.
Multivariate rationale: thesis Sec 3.5.6 / 4.2.4.6 - rely on the combined
cross-layer state, not a single dominant indicator.

Input : a feature_table.csv (M7 output, needs 'Label'), OR a directory - all
        feature_table.csv files under it are pooled (run the whole matrix at once).
        Binary label: attack = (Label > 0).
Output: a ranked separability table, the list of trivial/artifact features to drop,
        and a verdict on whether any SINGLE feature globally determines the label.

Usage : python tools/feature_separability.py analysis
        python tools/feature_separability.py analysis/blackhole/linear_topology/feature_table.csv
"""
import argparse
import glob
import os
import sys

import numpy as np
import pandas as pd

try:
    from sklearn.metrics import roc_auc_score
    from sklearn.feature_selection import mutual_info_classif
except Exception:
    print("ERROR: scikit-learn required. Run: pip install -r analysis/requirements.txt")
    sys.exit(2)

FEATURES = [
    "ForwardingRatio", "IngressEgressDelta", "ConsistencyScore",
    "RetryRate", "PDR",
    "ParentSwitchRate", "LayerChangeCount", "HopStabilityDuration",
    "RSSI_mean", "RSSI_var", "RSSI_stability",
    "RSSI_Hop_Diff", "LatencyHopRatio",
    "TunnelIntensity", "TunnelBytes", "TunnelLatency",
]

TRIVIAL_SEP = 0.98        # AUC-based separability at/above this = near-perfect
HIGH_COVERAGE = 0.90      # defined on >=90% of rows
SIGNAL_SEP = 0.60         # "carries meaningful signal" threshold
MIN_SAMPLES = 30


def load(path):
    if os.path.isdir(path):
        files = sorted(glob.glob(os.path.join(path, "**", "feature_table.csv"), recursive=True))
        if not files:
            print(f"ERROR: no feature_table.csv found under {path}")
            sys.exit(2)
        frames = []
        for f in files:
            d = pd.read_csv(f)
            d["_source_table"] = os.path.relpath(f, path)
            frames.append(d)
        print(f"Pooled {len(files)} feature tables:")
        for f in files:
            print(f"   - {os.path.relpath(f, path)}")
        return pd.concat(frames, ignore_index=True)
    return pd.read_csv(path)


def audit(df):
    if "Label" not in df.columns:
        print("ERROR: no 'Label' column - is this an M7 feature_table.csv?")
        sys.exit(2)
    lab = pd.to_numeric(df["Label"], errors="coerce")
    y_all = (lab > 0).astype(int)
    n_rows = len(df)
    n_attack = int((y_all == 1).sum())
    n_normal = int((y_all == 0).sum())
    print(f"\n=== Single-feature separability audit ===")
    print(f"    rows: {n_rows}   normal (Label 0): {n_normal}   attack (Label>0): {n_attack}\n")
    if n_attack == 0 or n_normal == 0:
        print("Need BOTH normal and attack rows to audit separability. (Pool a baseline "
              "table + an attack table, or point at analysis/.)")
        sys.exit(0)

    rows = []
    for feat in FEATURES:
        if feat not in df.columns:
            continue
        s = pd.to_numeric(df[feat], errors="coerce")
        coverage = float(s.notna().mean())
        mask = s.notna()
        yf = y_all[mask]
        xf = s[mask]
        if len(xf) < MIN_SAMPLES or yf.nunique() < 2:
            rows.append((feat, len(xf), coverage, np.nan, np.nan, np.nan, "skip (one class / too few)"))
            continue
        try:
            auc = roc_auc_score(yf, xf)
        except Exception:
            auc = np.nan
        sep = max(auc, 1 - auc) if not np.isnan(auc) else np.nan
        try:
            mi = float(mutual_info_classif(xf.values.reshape(-1, 1), yf.values,
                                           discrete_features=False, random_state=0)[0])
        except Exception:
            mi = np.nan
        artifact = feat.startswith("Tunnel")
        trivial_global = (not np.isnan(sep)) and sep >= TRIVIAL_SEP and coverage >= HIGH_COVERAGE
        if artifact:
            flag = "ARTIFACT (exclude from clustering)"
        elif trivial_global:
            flag = "TRIVIAL GLOBAL SEPARATOR (!)"
        elif not np.isnan(sep) and sep >= SIGNAL_SEP:
            flag = "carries signal"
        else:
            flag = ""
        rows.append((feat, len(xf), coverage, auc, sep, mi, flag))

    rows.sort(key=lambda r: (r[4] if not (r[4] is None or (isinstance(r[4], float) and np.isnan(r[4]))) else -1),
              reverse=True)

    hdr = f"  {'feature':<20}{'n':>6}{'cover':>8}{'AUC':>7}{'sep':>7}{'MI':>7}  flag"
    print(hdr)
    print("  " + "-" * (len(hdr) - 2))
    for feat, n, cov, auc, sep, mi, flag in rows:
        auc_s = "  n/a" if (auc is None or np.isnan(auc)) else f"{auc:5.2f}"
        sep_s = "  n/a" if (sep is None or np.isnan(sep)) else f"{sep:5.2f}"
        mi_s = "  n/a" if (mi is None or np.isnan(mi)) else f"{mi:5.2f}"
        print(f"  {feat:<20}{n:>6}{cov:>8.2f}{auc_s:>7}{sep_s:>7}{mi_s:>7}  {flag}")

    artifacts = [r[0] for r in rows if r[6].startswith("ARTIFACT")]
    trivial = [r[0] for r in rows if r[6].startswith("TRIVIAL")]
    signal = [r[0] for r in rows if r[6] == "carries signal"]

    print("\n  --- summary ---")
    print(f"  Artifact features to EXCLUDE from clustering (tunnel counters): "
          f"{', '.join(artifacts) if artifacts else 'none'}")
    print(f"  Genuine cross-layer features carrying signal (sep >= {SIGNAL_SEP}): "
          f"{', '.join(signal) if signal else 'none'}")
    print()
    if trivial:
        print(f"  VERDICT: WARNING - {', '.join(trivial)} separate(s) the label near-perfectly")
        print(f"           AND cover almost every row. A single feature could drive clustering.")
        print(f"           Investigate before clustering (is it an accidental label leak?).")
        rc = 1
    elif len(signal) >= 2:
        print(f"  VERDICT: PASS - no single NON-artifact feature globally determines the label.")
        print(f"           The attack signal is a CONFLUENCE of {len(signal)} cross-layer features")
        print(f"           (highly-separating ones are role-exclusive / low-coverage, so none can")
        print(f"           label the whole dataset alone). Exclude the tunnel artifacts and cluster")
        print(f"           on the rest. Satisfies the panel's 'not one feature' requirement.")
        rc = 0
    else:
        print(f"  VERDICT: WEAK - fewer than 2 features carry signal. Collect more/varied data")
        print(f"           (the panel's variance requirement) before clustering.")
        rc = 0
    return rc


def main():
    ap = argparse.ArgumentParser(description="NIS16 single-feature separability audit (AUC + MI).")
    ap.add_argument("path", help="feature_table.csv, or a directory to pool all of them.")
    args = ap.parse_args()
    df = load(args.path)
    sys.exit(audit(df))


if __name__ == "__main__":
    main()

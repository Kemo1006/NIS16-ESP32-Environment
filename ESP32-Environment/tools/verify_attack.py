#!/usr/bin/env python3
"""
verify_attack.py - Paper-backed attack verification (3-sigma normal-vs-attack).

Confirms an attack run actually produced its expected cross-layer signature, by
testing whether the attack-phase windows deviate more than k sigma (default 3)
from the BASELINE-phase distribution of the signature features. This is the
verification method of:

  Zhukabayeva, T., Zholshiyeva, L., Mardenov, Y., Buja, A., Khan, S., & Alnazzawi,
  N. (2025). Real-Time Detection and Response to Wormhole and Sinkhole Attacks in
  Wireless Sensor Networks. Technologies, 13(8), 348.
  -> 3-sigma anomaly detection comparing routing behaviour under normal vs attack.

Signature features grounded in the literature:
  - Blackhole: forwarding-ratio / PDR collapse  (Airehrour et al. 2018).
  - Wormhole : duplicate arrivals + tunnel activity  (Zhukabayeva 2025; Ramirez 2019).

Unlike validate_integrity.py (schema/coverage) and verify_topology.py (structure),
this checks that the ATTACK ITSELF is real and matches the published expectation -
the panel's requirement that verification be paper-backed, not home-grown.

Input : a feature_table.csv (M7 output from analysis/<attack>/<topology>_topology/).
        Must contain the ground-truth 'Label' column (0=baseline/cooldown,
        1=blackhole, 2=wormhole) and the 16 Table 4.11 feature columns. Role-
        exclusive features (e.g. ForwardingRatio on the attacker, PDR on victims,
        Tunnel* on wormhole endpoints) are NaN elsewhere; we test each feature only
        where it is defined (non-NaN), so no node-role names are hardcoded.
Output: a per-feature 3-sigma report + overall CONFIRMED / NOT-CONFIRMED verdict.
        Exit code 0 if confirmed, 1 if not (so it can gate a run in a script).

Usage : python tools/verify_attack.py analysis/blackhole/linear_topology/feature_table.csv
        python tools/verify_attack.py <feature_table.csv> --attack wormhole --sigma 3
"""
import argparse
import math
import sys

import numpy as np
import pandas as pd

LABEL_BASELINE = 0
LABEL_BLACKHOLE = 1
LABEL_WORMHOLE = 2
ATTACK_LABEL = {"blackhole": LABEL_BLACKHOLE, "wormhole": LABEL_WORMHOLE}

# (feature, direction, tier)
#   direction 'down' = the attack pushes the feature BELOW baseline; 'up' = above.
#   tier 'primary' features DEFINE the attack; 'secondary' are supporting evidence.
SIGNATURES = {
    "blackhole": [
        ("ForwardingRatio",    "down", "primary"),    # attacker forwards -> drops (delivered/sent, Airehrour)
        ("PDR",                "down", "primary"),    # end-to-end delivery collapses
        ("ConsistencyScore",   "up",   "secondary"),  # |FR - 1| rises
        ("IngressEgressDelta", "up",   "secondary"),  # packets absorbed
        ("RetryRate",          "up",   "secondary"),  # victims retry
    ],
    "wormhole": [
        ("TunnelIntensity",    "up",   "primary"),    # tunnel active (~0 in baseline)
        ("TunnelBytes",        "up",   "primary"),    # tunnel data volume
        ("TunnelLatency",      "up",   "primary"),    # duplicate-arrival spread appears
        ("LatencyHopRatio",    "down", "secondary"),  # shortcut copy arrives faster (informational)
    ],
}


def stat_verdict(baseline, attack, direction, sigma):
    """3-sigma test for one feature: is the attack-phase mean > sigma from baseline?"""
    b = pd.to_numeric(baseline, errors="coerce").dropna()
    a = pd.to_numeric(attack, errors="coerce").dropna()
    res = {"n_base": len(b), "n_attack": len(a), "mu": np.nan, "sd": np.nan,
           "attack_mean": np.nan, "z": np.nan, "frac_beyond": np.nan,
           "status": "SKIP", "note": ""}
    if len(a) == 0:
        res["note"] = "no attack-phase values (signal absent during attack)"
        return res
    res["attack_mean"] = a.mean()
    if len(b) < 2:
        res["status"] = "INCONCLUSIVE"
        res["note"] = "insufficient baseline windows (need >=2)"
        return res
    mu = b.mean()
    sd = b.std(ddof=1)
    res["mu"], res["sd"] = mu, sd
    am = a.mean()
    if sd == 0 or math.isnan(sd):
        # Baseline perfectly stable -> any real move in the expected direction is anomalous.
        eps = 1e-9 * (abs(mu) + 1.0)
        if direction == "down":
            moved = am < mu - eps
            res["z"] = float("-inf") if moved else 0.0
            res["frac_beyond"] = float((a < mu - eps).mean())
        else:
            moved = am > mu + eps
            res["z"] = float("inf") if moved else 0.0
            res["frac_beyond"] = float((a > mu + eps).mean())
        res["note"] = "baseline sd=0 (perfectly stable)"
        res["status"] = "PASS" if moved else "FAIL"
        return res
    z = (am - mu) / sd
    res["z"] = z
    lo, hi = mu - sigma * sd, mu + sigma * sd
    if direction == "down":
        res["frac_beyond"] = float((a < lo).mean())
        res["status"] = "PASS" if z <= -sigma else "FAIL"
    else:
        res["frac_beyond"] = float((a > hi).mean())
        res["status"] = "PASS" if z >= sigma else "FAIL"
    return res


def detect_attacks(df):
    labels = set(pd.to_numeric(df["Label"], errors="coerce").dropna().astype(int))
    found = []
    if LABEL_BLACKHOLE in labels:
        found.append("blackhole")
    if LABEL_WORMHOLE in labels:
        found.append("wormhole")
    return found


def _fmt_z(z):
    if z == float("-inf"):
        return "   -inf"
    if z == float("inf"):
        return "   +inf"
    if math.isnan(z):
        return "    n/a"
    return f"{z:7.2f}"


def verify(df, attack, sigma):
    label = ATTACK_LABEL[attack]
    lab = pd.to_numeric(df["Label"], errors="coerce")
    base_mask = lab == LABEL_BASELINE
    atk_mask = lab == label
    print(f"\n=== Verifying {attack.upper()} (Label {label}) vs baseline (Label 0) ===")
    print(f"    baseline windows: {int(base_mask.sum())}   attack windows: {int(atk_mask.sum())}")
    print(f"    3-sigma normal-vs-attack test (Zhukabayeva et al. 2025)\n")
    header = (f"  {'feature':<20}{'tier':<10}{'baseline mu+-sd (n)':<26}"
              f"{'attack mean (n)':<18}{'z':>8}  verdict")
    print(header)
    print("  " + "-" * (len(header) - 2))

    primary_pass = 0
    primary_total = 0
    for feat, direction, tier in SIGNATURES[attack]:
        if feat not in df.columns:
            print(f"  {feat:<20}{tier:<10}(column missing)")
            continue
        r = stat_verdict(df.loc[base_mask, feat], df.loc[atk_mask, feat], direction, sigma)
        if tier == "primary" and r["status"] in ("PASS", "FAIL"):
            primary_total += 1
            primary_pass += 1 if r["status"] == "PASS" else 0
        mu_s = "n/a" if math.isnan(r["mu"]) else f"{r['mu']:.3f}+-{r['sd']:.3f}"
        base_s = f"{mu_s} ({r['n_base']})"
        am_s = "n/a" if math.isnan(r["attack_mean"]) else f"{r['attack_mean']:.3f}"
        atk_s = f"{am_s} ({r['n_attack']})"
        arrow = "v" if direction == "down" else "^"
        note = f" - {r['note']}" if r["note"] else ""
        print(f"  {feat:<20}{tier:<10}{base_s:<26}{atk_s:<18}{_fmt_z(r['z'])}  "
              f"{r['status']} ({arrow}){note}")

    conclusive = primary_total > 0
    confirmed = conclusive and primary_pass > 0
    print()
    if confirmed:
        print(f"  VERDICT: {attack.upper()} CONFIRMED  "
              f"({primary_pass}/{primary_total} primary signatures exceed {sigma:g}-sigma).")
    elif not conclusive:
        print(f"  VERDICT: INCONCLUSIVE - no primary signature feature had usable data "
              f"(need a full attack run with the correct node roles present).")
    else:
        print(f"  VERDICT: NOT CONFIRMED - no primary signature exceeded {sigma:g}-sigma. "
              f"Check the attacker setup / run.")
    return confirmed, conclusive


def main():
    ap = argparse.ArgumentParser(
        description="NIS16 paper-backed attack verification (3-sigma normal-vs-attack).")
    ap.add_argument("feature_table", help="Path to a feature_table.csv (M7 output, needs 'Label').")
    ap.add_argument("--attack", choices=["auto", "blackhole", "wormhole"], default="auto",
                    help="Which attack to verify (default: auto-detect from Label values).")
    ap.add_argument("--sigma", type=float, default=3.0, help="Sigma threshold (default 3).")
    args = ap.parse_args()

    try:
        df = pd.read_csv(args.feature_table)
    except Exception as e:
        print(f"ERROR: could not read {args.feature_table}: {e}")
        sys.exit(2)
    if "Label" not in df.columns:
        print("ERROR: no 'Label' column - is this an M7 feature_table.csv?")
        sys.exit(2)

    if args.attack == "auto":
        attacks = detect_attacks(df)
        if not attacks:
            print("This looks like a BASELINE-only table (no Label 1 or 2) - nothing to verify.")
            sys.exit(0)
    else:
        attacks = [args.attack]

    any_conclusive = False
    all_confirmed = True
    for atk in attacks:
        confirmed, conclusive = verify(df, atk, args.sigma)
        any_conclusive = any_conclusive or conclusive
        all_confirmed = all_confirmed and confirmed

    print()
    sys.exit(0 if (any_conclusive and all_confirmed) else 1)


if __name__ == "__main__":
    main()

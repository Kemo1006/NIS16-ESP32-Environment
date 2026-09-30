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

Two measurement guards sit in front of that test. Both exist because the dataset
uses 1-second windows (thesis-deviate D-9) while the firmware emits one probe per
PROBE_INTERVAL_MS = 1000, i.e. ~1 probe per window:

  - BLOCK AGGREGATION (--block, default 5 windows = the thesis's own Table 4.10
    window). A ratio measured over ~1 probe is a Bernoulli draw, not a rate. D-9
    argued this "costs no information - the mean over 5x as many windows carries
    the same evidence", which is true of the MEAN and false of the VARIANCE, and
    the 3-sigma test divides by exactly that variance. Measured on
    blackhole/linear/G402: a ratio measured over ~1 probe is a Bernoulli draw,
    so the per-window variance is dominated by sampling noise rather than by the
    network. The dataset itself is NOT re-windowed; D-9's row count is untouched.
    Only the statistic is computed on blocks.

    CORRECTION (2026-09-20): an earlier version of this note claimed pooling
    alone lifted ForwardingRatio to z = -6.10. Re-measured on the same capture,
    pooling gives z = -2.55, not -6.10 - pooling was never sufficient, because
    the baseline it pooled was contaminated (see below). Do not quote -6.10.

  - BASELINE FLOOR (BASELINE_FLOOR). Khan et al. (2022) measured PDR > 97% /
    loss < 1.8% on an ESP-MESH deployment. A baseline an order of magnitude below
    that is a broken measurement, not a quiet network, and an attack tested
    against it is meaningless. Such a feature is reported INVALID-BASE and left
    out of the verdict rather than silently counted as "no collapse detected".

  - FEASIBILITY CEILING. Both primary features are bounded below at 0, so the
    most negative z obtainable is (mu - 0) / sd of the baseline. On the
    2026-09-18 G402 capture that ceiling was 2.55 for ForwardingRatio and 1.21
    for PDR, and the observed z values were exactly -2.55 and -1.21: the attack
    was at 100% of its maximum possible effect and the test still said FAIL. A
    FAIL that a perfect attack cannot avoid is not a measurement of the attack,
    so such a feature is now reported INFEASIBLE and left out of the verdict.
    The root cause was upstream - ~30% of the "baseline" rows were windows in
    which the victims were probing a mesh the root had not joined yet, scored a
    genuine PDR of 0 - and is fixed in preprocess.assign_segments(). This guard
    exists so the same class of failure can never again be read as evidence
    that an attack did not happen.

  - RATIO-OF-SUMS for rate features (RATIO_OF_SUMS). Mean-of-ratios weights a
    window that saw 6 packets the same as one that saw 117, which let a single
    queue-flush window (ForwardingRatio 19.5) dominate the baseline variance.

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

import os

import numpy as np
import pandas as pd

# analysis/exposure.py holds the one definition of "who was actually exposed to
# the attacker", shared with features.py so this report and the feature table can
# never disagree about who counts as a victim. Path is derived from THIS file's
# location, so it follows the repo wherever it is checked out.
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "analysis"))
try:
    import exposure as _exposure
except ImportError:          # analysis/ missing — report still runs, just without
    _exposure = None         # the derived column on tables that lack it

LABEL_BASELINE = 0
LABEL_BLACKHOLE = 1
LABEL_WORMHOLE = 2
ATTACK_LABEL = {"blackhole": LABEL_BLACKHOLE, "wormhole": LABEL_WORMHOLE}

# Windows pooled per statistic point. 5 = the thesis's Table 4.10 window, which
# D-9 shortened to 1 s for row count; see the module docstring for why the test
# needs it back even though the dataset does not.
DEFAULT_BLOCK_WINDOWS = 5

# Lowest baseline mean at which a feature can still serve as a "normal" reference.
# Khan et al. (2022) measured PDR > 0.97 on ESP-MESH; 0.50 is deliberately far
# below that, so this fires only on a measurement that is plainly broken rather
# than on a merely lossy run.
BASELINE_FLOOR = {"PDR": 0.90, "ForwardingRatio": 0.90}

# A bounded ratio whose baseline standard deviation exceeds this fraction of its
# own mean is not a quiet network being measured well - it is a broken
# measurement. On the 2026-09-18 G402 capture ForwardingRatio's baseline was
# 0.994 +- 0.390 (sd/mu = 0.39) with a median of exactly 1.000: 549 of 601
# windows sat at 1.0 and the dispersion came from pre-root-join zeros and one
# queue-flush window at 19.5. Nothing about that distribution describes normal
# forwarding, and a 3-sigma test against it is meaningless.
BASELINE_DISPERSION_CEILING = {"PDR": 0.15, "ForwardingRatio": 0.15}

# Upper bound of each feature, where one physically exists. Used to compute the
# best z an 'up' feature could possibly reach. A ratio has a ceiling of 1.0;
# a count or a delta does not, so it is absent here and no feasibility bound is
# claimed for it.
FEATURE_UPPER_BOUND = {"PDR": 1.0, "ForwardingRatio": 1.0, "ConsistencyScore": 1.0}

# Features that are RATES (a numerator counted over a denominator) rather than
# free-standing measurements. For these the mean of per-window ratios is a
# biased, outlier-dominated estimator; the correct statistic over a block is the
# ratio of the summed numerator to the summed denominator. Maps
# feature -> (numerator column, denominator column) in the feature table.
# Each entry is a list of (numerator, denominator columns) options, first match
# wins; a denominator of several columns is their sum.
#   ForwardingRatio: features.py uses forward/recv on schema v2 (every relay);
#     tx/probes is the v1 attacker-only form. On v2, tx/probes is a node's OWN
#     sends, so pooling on it tested honest relays against their own traffic.
#   RetryRate: failures / attempts (Eq 4.4). Per 1 s window it is 0 or 1 at one
#     probe per second; summed over the block it is a real proportion.
RATIO_OF_SUMS = {
    "ForwardingRatio": [("forward_count_delta", ("recv_count_delta",)),
                        ("tx_count_delta", ("probes_count_delta",))],
    "RetryRate": [("retry_count_delta", ("tx_count_delta", "retry_count_delta"))],
}

# (feature, direction, tier)
#   direction 'down' = the attack pushes the feature BELOW baseline; 'up' = above.
#   tier 'primary' features DEFINE the attack; 'secondary' are supporting evidence.
SIGNATURES = {
    "blackhole": [
        ("ForwardingRatio",    "down", "primary"),    # attacker forwards -> drops (delivered/sent, Airehrour)
        ("PDR",                "down", "primary"),    # end-to-end delivery collapses
        ("ConsistencyScore",   "up",   "secondary"),  # |FR - 1| rises
        ("IngressEgressDelta", "up",   "secondary"),  # packets absorbed
        # Paper Table 3.4's pre-registered "victims retry more". KEEP it (team
        # decision sep. 23, 2026): its FAIL is the result to report. Victims
        # never see a failure - the attacker is alive and accepts every frame,
        # exactly as the paper's own S3.3.1.2 predicts - so on F3 (schema v2)
        # data retry_count = failed esp_mesh_send() calls on every role and
        # stays flat (G402 sep. 25: 0 failures in baseline AND attack).
        # Pre-F3 captures (no drop_count column) still carry the attacker's
        # drops in retry_count, so a PASS there is a LEAK, not evidence -
        # see RETRY_LEAK_NOTE below.
        ("RetryRate",          "up",   "secondary"),
    ],
    "wormhole": [
        ("TunnelIntensity",    "up",   "primary"),    # tunnel active (~0 in baseline)
        ("TunnelBytes",        "up",   "primary"),    # tunnel data volume
        ("TunnelLatency",      "up",   "primary"),    # duplicate-arrival spread appears
        ("LatencyHopRatio",    "down", "secondary"),  # shortcut copy arrives faster (informational)
    ],
}


# What a RetryRate verdict means, appended to its footnote (see SIGNATURES).
RETRY_MISS_NOTE = ("paper Table 3.4 predicted victims retry more; not observed - a "
                   "pre-registered miss to REPORT, not edit (docs/EXPECTED-RESULTS.md 6a)")
RETRY_LEAK_NOTE = ("pre-F3 capture (no drop_count): retry_count still holds the "
                   "attacker's own drops, so this PASS is LEAKAGE, not evidence")


def stat_verdict(baseline, attack, direction, sigma, feature=None, lower_bound=0.0):
    """3-sigma test for one feature: is the attack-phase mean > sigma from baseline?

    `feature` and `lower_bound` drive the feasibility ceiling described inline
    below; they default to a generic non-negative quantity, which is what every
    feature in SIGNATURES actually is.
    """
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

    # FEASIBILITY. A FAIL must mean "the attack did not move this feature". It
    # must never also mean "this test could not have detected it". Both features
    # are bounded, so there is a hard limit on how far the mean can travel:
    #   down-feature bounded below at `lower`: max |z| = (mu - lower) / sd
    #   up-feature   bounded above at `upper`: max  z  = (upper - mu) / sd
    # If that ceiling is under sigma, no attack of any strength could pass, and
    # reporting FAIL would be reporting the baseline's dispersion as evidence
    # about the attack. Measured on the 2026-09-18 G402 capture before the
    # preprocess fix: ForwardingRatio's ceiling was 2.55 and it scored exactly
    # -2.55; PDR's was 1.21 and it scored exactly -1.21. Both were at 100% of
    # the strongest effect a blackhole can produce and still "failed".
    if res["status"] == "FAIL":
        if direction == "down":
            max_z = (mu - lower_bound) / sd
        else:
            upper = FEATURE_UPPER_BOUND.get(feature)
            max_z = (upper - mu) / sd if upper is not None else float("inf")
        if max_z < sigma:
            res["status"] = "INFEASIBLE"
            res["note"] = (
                f"the attack drove this feature to {am:.4f}, but against a "
                f"baseline of {mu:.3f}+-{sd:.3f} the largest |z| ATTAINABLE is "
                f"{max_z:.2f} < {sigma:g} - no attack of any strength could have "
                f"passed. This is a statement about the baseline's dispersion, "
                f"not about the attack; excluded from the verdict"
            )
    return res


def block_aggregate(df, feats, block):
    """Pool consecutive windows into blocks of `block`, per node and per label.

    Grouping on Label as well as node is what keeps a block from straddling the
    baseline->attack boundary and averaging the two phases together.

    Returns (pooled_df, note). Falls back to the unpooled frame when the columns
    needed to order windows are absent (a legacy table, or a synthetic fixture),
    because a wrong pooling is worse than none.
    """
    if block <= 1:
        return df, "unpooled (--block 1): per-window statistic"
    missing = [c for c in ("window_start", "node_id") if c not in df.columns]
    if missing:
        return df, f"unpooled - table has no {'/'.join(missing)} column to pool on"
    present = [f for f in feats if f in df.columns]
    d = df.copy()
    d["_block"] = pd.to_numeric(d["window_start"], errors="coerce") // block
    keys = ["node_id", "Label", "_block"]
    pooled = d.groupby(keys, as_index=False)[present].mean()

    # RATE features get ratio-of-sums, not mean-of-ratios. Averaging per-window
    # ratios weights a window that saw 6 packets the same as one that saw 117,
    # so a single queue flush at the moment the root joins (117 forwarded / 6
    # received -> ForwardingRatio 19.5) dominates the baseline variance that the
    # 3-sigma test then divides by. Summing the numerator and denominator across
    # the block first is the standard estimator for a rate and is immune to it.
    notes = []
    for feat, options in RATIO_OF_SUMS.items():
        if feat not in pooled.columns:
            continue
        chosen = next(((n, dc) for n, dc in options
                       if n in d.columns and all(c in d.columns for c in dc)
                       and d[n].notna().any()), None)
        if chosen is None:
            continue
        num_col, den_cols = chosen
        cols = list(dict.fromkeys([num_col, *den_cols]))
        sums = d.groupby(keys, as_index=False)[cols].sum()
        den = sum(pd.to_numeric(sums[c], errors="coerce") for c in den_cols)
        num = pd.to_numeric(sums[num_col], errors="coerce")
        ratio = (num / den).where(den > 0, np.nan)
        merged = pooled.merge(sums[keys].assign(_ros=ratio), on=keys, how="left")
        # Only replace where the feature was already defined for that block, so
        # ratio-of-sums never invents a value on a role that has no relay data.
        pooled[feat] = merged["_ros"].where(pooled[feat].notna(), np.nan).values
        notes.append(feat)

    note = f"{block} windows per point (Table 4.10 window = 5)"
    if notes:
        note += f"; ratio-of-sums for {', '.join(notes)}"
    return pooled, note


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


# Short, fixed-width verdict flags for the table. Verbose notes (citations,
# thresholds, raw context) never go in the cell - they're collected and
# printed as numbered footnotes below the table instead, so a long note on
# one row can't shift every column after it.
STATUS_FLAG = {
    "PASS": "PASS",
    "FAIL": "FAIL",
    "INVALID-BASE": "EXCLUDED",
    "INFEASIBLE": "INFEASIBLE",
    "INCONCLUSIVE": "INCONCL",
    "SKIP": "SKIP",
}


def verify(df, attack, sigma, block=DEFAULT_BLOCK_WINDOWS):
    label = ATTACK_LABEL[attack]
    raw_lab = pd.to_numeric(df["Label"], errors="coerce")
    print(f"\n=== Verifying {attack.upper()} (Label {label}) vs baseline (Label 0) ===")
    print(f"    baseline windows: {int((raw_lab == LABEL_BASELINE).sum())}   "
          f"attack windows: {int((raw_lab == label).sum())}")

    feats = [f for f, _, _ in SIGNATURES[attack]]
    # Keep the PRE-AGGREGATION frame for the per-node report below: block_aggregate
    # pools `block` windows per point and keeps only the signature features, so it
    # drops node_role/hop. Per-node PDR is a descriptive breakdown, not an input to
    # the sigma test, so it wants the unpooled rows anyway.
    df_nodes = df
    df, agg_note = block_aggregate(df, feats, block)
    lab = pd.to_numeric(df["Label"], errors="coerce")
    base_mask = lab == LABEL_BASELINE
    atk_mask = lab == label

    print(f"    aggregation: {agg_note}")
    print(f"    3-sigma normal-vs-attack test (Zhukabayeva et al. 2025)\n")
    header = (f"  {'feature':<20}{'tier':<10}{'baseline mu+-sd (n)':<26}"
              f"{'attack mean (n)':<18}{'z':>7}  {'verdict':<13}ref")
    print(header)
    print("  " + "-" * (len(header) - 2))

    primary_pass = 0
    primary_total = 0
    primary_excluded = 0
    footnotes = []  # (marker, feature, note) - printed below the table, not in-cell
    for feat, direction, tier in SIGNATURES[attack]:
        if feat not in df.columns:
            print(f"  {feat:<20}{tier:<10}(column missing)")
            continue
        r = stat_verdict(df.loc[base_mask, feat], df.loc[atk_mask, feat],
                         direction, sigma, feature=feat)

        # A feature whose own baseline is broken cannot say anything about the
        # attack; counting its FAIL would read as evidence of no attack.
        floor = BASELINE_FLOOR.get(feat)
        if floor is not None and not math.isnan(r["mu"]) and r["mu"] < floor:
            r["status"] = "INVALID-BASE"
            r["note"] = (f"baseline mean {r['mu']:.3f} < {floor:g}; Khan et al. (2022) "
                         f"measured PDR > 0.97 on ESP-MESH, so this baseline is a "
                         f"broken measurement, not a quiet network - excluded")
        ceiling = BASELINE_DISPERSION_CEILING.get(feat)
        if (ceiling is not None and r["status"] not in ("INVALID-BASE", "SKIP")
                and not math.isnan(r["mu"]) and not math.isnan(r["sd"])
                and r["mu"] > 0 and (r["sd"] / r["mu"]) > ceiling):
            r["status"] = "INVALID-BASE"
            r["note"] = (f"baseline {r['mu']:.3f}+-{r['sd']:.3f} has sd/mu = "
                         f"{r['sd'] / r['mu']:.2f} > {ceiling:g} on a bounded ratio; "
                         f"that is a broken measurement, not normal operation "
                         f"(check for pre_baseline contamination) - excluded")

        if tier == "primary" and r["status"] in ("PASS", "FAIL"):
            primary_total += 1
            primary_pass += 1 if r["status"] == "PASS" else 0
        elif tier == "primary" and r["status"] in ("INVALID-BASE", "INFEASIBLE"):
            primary_excluded += 1
        mu_s = "n/a" if math.isnan(r["mu"]) else f"{r['mu']:.3f}+-{r['sd']:.3f}"
        base_s = f"{mu_s} ({r['n_base']})"
        am_s = "n/a" if math.isnan(r["attack_mean"]) else f"{r['attack_mean']:.3f}"
        atk_s = f"{am_s} ({r['n_attack']})"
        arrow = "v" if direction == "down" else "^"

        if feat == "RetryRate" and r["status"] in ("PASS", "FAIL"):
            pre_f3 = ("drop_count_delta" not in df.columns
                      or df["drop_count_delta"].isna().all())
            extra = RETRY_LEAK_NOTE if (pre_f3 and r["status"] == "PASS") else (
                RETRY_MISS_NOTE if r["status"] == "FAIL" else "")
            if extra:
                r["note"] = f"{r['note']}; {extra}" if r["note"] else extra

        ref = ""
        if r["note"]:
            footnotes.append((len(footnotes) + 1, feat, r["note"]))
            ref = f"[{footnotes[-1][0]}]"
        flag = STATUS_FLAG.get(r["status"], r["status"])
        verdict_s = f"{flag} [{arrow}]"
        print(f"  {feat:<20}{tier:<10}{base_s:<26}{atk_s:<18}{_fmt_z(r['z'])}  "
              f"{verdict_s:<13}{ref}")

    conclusive = primary_total > 0
    confirmed = conclusive and primary_pass > 0
    excluded_note = (f" {primary_excluded} primary feature(s) excluded on an invalid "
                     f"baseline - see notes below." if primary_excluded else "")
    if footnotes:
        print("\n  NOTES:")
        for marker, feat, note in footnotes:
            print(f"  [{marker}] {feat}: {note}")
    print()
    print_per_node_pdr(df_nodes, label)
    if confirmed:
        print(f"  VERDICT: {attack.upper()} CONFIRMED  "
              f"({primary_pass}/{primary_total} primary signatures exceed {sigma:g}-sigma)."
              + excluded_note)
    elif not conclusive:
        print(f"  VERDICT: INCONCLUSIVE - no primary signature feature had usable data "
              f"(need a full attack run with the correct node roles present)."
              + excluded_note)
    else:
        print(f"  VERDICT: NOT CONFIRMED - no primary signature exceeded {sigma:g}-sigma. "
              f"Check the attacker setup / run." + excluded_note)
    return confirmed, conclusive


def print_per_node_pdr(df, label, sigma_note=""):
    """Per-node PDR next to the pooled number the table above reports.

    WHY THIS EXISTS
    ---------------
    Since C7 Option 1 the blackhole is POSITIONAL: it can only drop traffic from
    nodes BELOW it in the tree. A victim that sits closer to the root than the
    attacker reaches the root without ever transiting it and is completely
    unaffected for the whole run.

    Pooling every victim into one PDR therefore averages "untouched" with
    "annihilated" and reports something that happened to NOBODY. Measured on
    blackhole/linear/home r1 (2026-09-22): pooled attack PDR 0.514, which is the
    mean of victim H01 at 1.000 (upstream of the attacker, never touched) and
    victim H03 at 0.0137 (downstream, near-total loss). Quoting 0.514 understates
    the attack on the node it actually hit by a factor of ~37, and the number
    moves run to run purely with where the attacker happened to land in the tree.

    So the pooled value stays (it is what the 3-sigma test consumes) and this
    prints the split underneath it, which is the figure the write-up should use.
    """
    if "PDR" not in df.columns or "node_id" not in df.columns:
        return

    # EXPOSURE is what decides who counts as a victim. The firmware's role says
    # what a board WAS BUILT as; exposure says whether the attacker actually sat
    # on its path to the root. A child above the attacker logs itself "victim"
    # and is never touched -- see analysis/exposure.py.
    df = df.copy()
    if "exposure" not in df.columns:
        # Older feature tables have no column; derive it here so this report is
        # correct on them too rather than silently falling back to the role.
        try:
            df["exposure"] = _exposure.compute_exposure(df).values
        except Exception:
            df["exposure"] = "unknown"
    lab = df["Label"] if "Label" in df.columns else df.get("window_label")
    if lab is None:
        return

    base = df[lab == LABEL_BASELINE]
    atk = df[lab == label]
    if atk.empty:
        return

    keys = ["node_id"]
    for extra in ("node_role", "exposure", "hop"):
        if extra in df.columns:
            keys.append(extra)

    b = base.groupby(keys)["PDR"].mean()
    a = atk.groupby(keys)["PDR"].agg(["mean", "count"])
    rows = []
    for k, r in a.iterrows():
        if pd.isna(r["mean"]):
            continue
        rows.append((k if isinstance(k, tuple) else (k,), b.get(k, float("nan")),
                     r["mean"], int(r["count"])))
    if not rows:
        return

    rows.sort(key=lambda t: t[2])   # worst-hit node first
    print("  PER-NODE PDR (the pooled row above averages these — see "
          "print_per_node_pdr.__doc__)")
    hdr = "  {:<20}{:<11}{:<12}{:>5}{:>11}{:>11}{:>7}".format(
        "node_id", "built as", "exposure", "hop", "baseline", "attack", "n")
    print(hdr)
    print("  " + "-" * (len(hdr) - 2))
    names = {k: i for i, k in enumerate(keys)}
    for key, bmean, amean, n in rows:
        node = key[0]

        def field(col, default="?"):
            i = names.get(col)
            return key[i] if i is not None and i < len(key) else default

        role = field("node_role")
        exp = field("exposure", "unknown")
        hop = field("hop", float("nan"))
        hop_s = "-" if pd.isna(hop) else f"{int(hop)}"
        b_s = "  n/a" if pd.isna(bmean) else f"{bmean:.4f}"
        # "victim" is printed for downstream nodes ONLY. Every other child is
        # named for what it actually was during the run, so the table can never
        # be read as "two victims, one of which somehow survived".
        exp_s = {"downstream": "VICTIM", "upstream": "not in path",
                 "attacker": "ATTACKER", "root": "root",
                 "no_attacker": "no attacker"}.get(str(exp), str(exp))
        print("  {:<20}{:<11}{:<12}{:>5}{:>11}{:>11}{:>7}".format(
            str(node), str(role), exp_s, hop_s, b_s, f"{amean:.4f}", n))

    ei = names.get("exposure")
    def exposure_of(r):
        return str(r[0][ei]) if ei is not None and ei < len(r[0]) else "unknown"

    victims = [r for r in rows if exposure_of(r) == "downstream"]
    bystanders = [r for r in rows if exposure_of(r) == "upstream"]
    print()
    if victims:
        worst = min(r[2] for r in victims)
        print("  ** {} VICTIM(S) — the attacker sits on their path to the root. "
              "Worst attack PDR {:.4f}.".format(len(victims), worst))
        print("     " + ", ".join(str(r[0][0]) for r in victims))
        print("     This is the population the write-up should quote. The pooled "
              "PDR above averages")
        print("     victims with bystanders and describes no actual node.")
    if bystanders:
        print("  ** {} node(s) were NOT in the attack path (built as children, "
              "never exposed):".format(len(bystanders)))
        print("     " + ", ".join(str(r[0][0]) for r in bystanders))
        print("     They sit ABOVE the attacker, so their traffic never transits "
              "it. Unaffected BY")
        print("     CONSTRUCTION — not evidence the attack was weak, and not "
              "victims.")
    if not victims and bystanders:
        print("  !! No node was downstream of the attacker in this run, so the "
              "capture cannot")
        print("     show a blackhole effect at all. Re-place the attacker and "
              "re-run.")
    print()


def main():
    ap = argparse.ArgumentParser(
        description="NIS16 paper-backed attack verification (3-sigma normal-vs-attack).")
    ap.add_argument("feature_table", help="Path to a feature_table.csv (M7 output, needs 'Label').")
    ap.add_argument("--attack", choices=["auto", "blackhole", "wormhole"], default="auto",
                    help="Which attack to verify (default: auto-detect from Label values).")
    ap.add_argument("--sigma", type=float, default=3.0, help="Sigma threshold (default 3).")
    ap.add_argument("--block", type=int, default=DEFAULT_BLOCK_WINDOWS,
                    help="Windows pooled per statistic point (default %(default)s = the "
                         "thesis's Table 4.10 5 s window; D-9 shortened the DATASET to "
                         "1 s windows, which leaves ~1 probe per window and inflates the "
                         "baseline variance the 3-sigma test divides by). 1 disables "
                         "pooling and reproduces the pre-fix numbers.")
    args = ap.parse_args()
    if args.block < 1:
        print("ERROR: --block must be >= 1")
        sys.exit(2)

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
        confirmed, conclusive = verify(df, atk, args.sigma, args.block)
        any_conclusive = any_conclusive or conclusive
        all_confirmed = all_confirmed and confirmed

    print()
    sys.exit(0 if (any_conclusive and all_confirmed) else 1)


if __name__ == "__main__":
    main()

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

Signature features grounded in the literature - ONLY these, nothing home-grown:
  - Blackhole: forwarding-ratio / PDR collapse  (Airehrour et al. 2018).
  - Wormhole : duplicate arrivals + tunnel activity  (Zhukabayeva 2025; Ramirez 2019).
RetryRate is deliberately NOT a signature (team decision sep. 30, 2026): no cited
study names it as a blackhole or wormhole indicator, and it measured flat in every
phase. It stays in feature_table.csv as a dataset column only (thesis-deviate D-15).

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
import contextlib
import io
import argparse
import math
import re
import sys
import textwrap

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
try:
    import attack_checks as _checks   # tools/attack_checks.py: setup + topology + UART
except ImportError:
    _checks = None

LABEL_BASELINE = 0
LABEL_BLACKHOLE = 1
LABEL_WORMHOLE = 2
ATTACK_LABEL = {"blackhole": LABEL_BLACKHOLE, "wormhole": LABEL_WORMHOLE}

# Windows pooled per statistic point. 5 = the thesis's Table 4.10 window, which
# D-9 shortened to 1 s for row count; see the module docstring for why the test
# needs it back even though the dataset does not.
DEFAULT_BLOCK_WINDOWS = 5

# Lowest baseline mean at which a feature can still serve as a "normal" reference.
# Khan et al. (2022) measured PDR > 0.97 on ESP-MESH. The floor was 0.50 and was
# RAISED to 0.90 in the F1-F3 audit (commit 0382647, see ARCHIVE.md): still
# below 0.97, so it fires on a broken measurement, not on a merely lossy run.
# A primary below it is EXCLUDED (INVALID-BASE), never counted as a FAIL.
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
RATIO_OF_SUMS = {
    "ForwardingRatio": [("forward_count_delta", ("recv_count_delta",)),
                        ("tx_count_delta", ("probes_count_delta",))],
    "NeighbourForwardingRatio": [("NeighbourOut", ("NeighbourIn",))],
}

# MINIMUM EFFECT (oct. 14 2026). 3-sigma alone is not enough on a bounded ratio
# with a near-flat baseline: baseline PDR 1.000 +- 0.000 makes ONE lost probe in
# the attack a z of -inf -> PASS. An attack has to move the feature by at least
# this much (absolute) as well. Values are far below any real attack (a
# blackhole takes victims from ~1.0 to ~0.0; a tunnel goes from 0 to ~1 msg/s)
# and far above one-probe noise.
MIN_EFFECT = {"PDR": 0.10, "ForwardingRatio": 0.10, "NeighbourForwardingRatio": 0.10,
              "ConsistencyScore": 0.10, "TunnelIntensity": 0.10, "TunnelBytes": 3.0,
              "DuplicateRate": 0.10}
# DuplicateRate is a ratio in [0, 1] (share of B's windows the root logged twice).
FEATURE_UPPER_BOUND["DuplicateRate"] = 1.0

# Fewest attack-phase points (blocks of --block windows) a feature needs before
# its mean is trusted: 6 x 5 s = 30 s of the ~180 s attack.
MIN_ATTACK_POINTS = 6

# (feature, direction, tier)
#   direction 'down' = the attack pushes the feature BELOW baseline; 'up' = above.
#   tier 'primary' features DEFINE the attack; 'secondary' are supporting evidence.
SIGNATURES = {
    "blackhole": [
        ("ForwardingRatio",    "down", "primary"),    # attacker forwards -> drops (delivered/sent, Airehrour)
        ("PDR",                "down", "primary"),    # end-to-end delivery collapses (Airehrour)
        ("ConsistencyScore",   "up",   "secondary"),  # |FR - 1| rises (same delivered/sent measure)
        ("IngressEgressDelta", "up",   "secondary"),  # packets absorbed: received - forwarded (Airehrour "discard, don't forward")
        ("NeighbourForwardingRatio", "down", "secondary"),  # same delivered/sent, measured by the attacker's NEIGHBOURS (not its self-report)
    ],
    "wormhole": [
        ("TunnelIntensity",    "up",   "primary"),    # tunnel active (~0 in baseline)
        # oct. 16 2026: a SECOND, INDEPENDENT primary. TunnelIntensity is the
        # attacking boards' own count; this one is measured by the ROOT: the
        # share of Node B's windows in which the root logged the same probe
        # twice (Ramirez Gomez et al. 2019: the wormhole's duplicate-packet
        # signature). Derived here from TunnelLatency, which features.py fills
        # only where a duplicate arrived (see _add_duplicate_rate).
        ("DuplicateRate",      "up",   "primary"),
        ("TunnelBytes",        "up",   "secondary"),  # = TunnelIntensity x 30 B: same
                                                      # measurement, so not a 2nd primary
        # MEASURED, never scored (oct. 16 2026, team decision): a 3-sigma test
        # cannot apply. TunnelLatency exists only while the tunnel runs (no
        # normal-phase values at all); LatencyHopRatio is an unsynchronised
        # relative delay whose normal spread is wider than its mean (max
        # attainable |z| 0.23-0.64 on every capture). Kept in the dataset and
        # printed in section [2] with their values.
        ("TunnelLatency",      "up",   "measured"),   # spread between a probe's 2 copies
        ("LatencyHopRatio",    "down", "measured"),   # relative delay per hop
    ],
}

# Signatures that describe the ATTACKING NODE's own behaviour, mapped to the
# node_role that identifies it. Since C7 Option 1 every node relays, so pooling
# ForwardingRatio averages the attacker (-> 0) with honest relays (stay 1) and a
# perfect blackhole reads as z ~ -2.4 (sept30 G402: pooled 0.826, attacker
# 0.002). For these only the attacker's windows are tested. No attacker rows ->
# the pooled test is used (legacy tables without node_role).
ATTACKER_SCOPED = {
    "blackhole": {"ForwardingRatio": "blackhole", "NeighbourForwardingRatio": "blackhole"},
}

# Attacker-scoped features that ALSO get a whole-network (all relays) row, as
# 'info' - shown for context, never counted, with a note saying how many honest
# relays kept the average near 1.0.
ALSO_POOLED = {"ForwardingRatio"}

# Row marker: an attacker-scoped feature on a table whose attacker is absent.
MISSING_ATTACKER = object()

# ForwardingRatio (attacker) = the attacker's OWN counters (forward / recv).
# NeighbourForwardingRatio (attacker) = the same ratio rebuilt WITHOUT them, from
# what its children say they handed it and what the root then received from
# below it (features.compute_neighbour_forwarding_features). Two sources, one
# quantity: identical rows mean the attacker's self-report was honest, not that
# one row was copied. sept30 partial_mesh G402: 612 of 616 attacker windows had
# recv == NeighbourIn and forward == NeighbourOut; the 4 others were clock
# jitter at window edges and cancel over a 5-window block.
NEIGHBOUR_NOTE = ("independent of the attacker's own counters: in = what its children "
                  "report handing it, out = what its parent (the root's arrivals) received "
                  "from below it. If this matches the ForwardingRatio (attacker) row, the "
                  "attacker's self-report is confirmed by its neighbours - two sources "
                  "agreeing, not one value printed twice")


EXPOSURE_LABEL = {"downstream": "VICTIM", "upstream": "not in path",
                  "attacker": "ATTACKER", "root": "root", "no_attacker": "no attacker",
                  "not_tunnelled": "not tunnelled"}


def _with_exposure(df):
    if "exposure" in df.columns:
        return df
    df = df.copy()
    try:
        df["exposure"] = _exposure.compute_exposure(df).values
    except Exception:
        df["exposure"] = "unknown"
    return df


def _pooled_note(df_nodes, feat, label, attackers, res, sigma):
    """Footnote for the 'all relays' row: how many honest relays it averages in.

    Only the attacker stops forwarding; every honest relay - a victim that
    relays included, since it forwards INTO the attacker - stays near 1.0. So
    the average passes or fails with the NUMBER of honest relays, not with the
    attack: linear G402 (5 honest) 0.826 FAIL, tree G402 (2 honest) 0.578 PASS.
    """
    status = res["status"]
    atk = df_nodes[pd.to_numeric(df_nodes["Label"], errors="coerce") == label]
    per_node = pd.to_numeric(atk[feat], errors="coerce").groupby(atk["node_id"]).mean().dropna()
    honest = per_node[~per_node.index.isin(attackers)]
    atk_val = per_node[per_node.index.isin(attackers)]
    n_h = len(honest)
    tail = ("Same measurement as the attacker row, so never counted (it would count one "
            "fact twice).")
    if atk_val.empty or any(math.isnan(res[k]) for k in ("mu", "sd", "attack_mean", "z")):
        return (f"average over all {len(per_node)} relays ({len(atk_val)} attacker + {n_h} "
                f"honest). " + tail)
    a = float(atk_val.mean())
    if n_h == 0:
        # Star + blackhole (D-16): every victim is a leaf under the attacker, so
        # the attacker is the ONLY relay and this row is the attacker row again.
        return (f"{res['attack_mean']:.3f} - the attacker is the only relay here (e.g. a star "
                f"hub), so this is the attacker row itself. " + tail)
    h = float(honest.mean())
    line = res["mu"] - sigma * res["sd"]
    if h <= line:
        cap = "any number of honest relays"
    elif line <= a:
        cap = "no honest relays at all"
    else:
        k = int(math.floor((line - a) / (h - line)))
        cap = f"at most ~{k} honest relay{'s' if k != 1 else ''}"
    # Only the attacker stops forwarding; every honest relay - a victim that
    # relays included, since it forwards INTO the attacker - stays near 1.0, so
    # this average passes or fails with the NUMBER of honest relays, not with
    # the attack (linear G402, 5 honest: 0.826 FAIL; tree G402, 2 honest: PASS).
    outcome = ("still drops past 3-sigma" if status == "PASS" else
               "does not reach 3-sigma - NOT evidence against the attack")
    return (f"network-wide {res['attack_mean']:.3f} (z {res['z']:.2f}) = the attacker's "
            f"{a:.3f} diluted by {n_h} honest relay(s) at {h:.3f}; it {outcome} (passing "
            f"allows {cap}). " + tail)


def _apply_min_effect(res, feature, mu, am):
    """Demote a PASS whose absolute change is too small to be an attack."""
    need = MIN_EFFECT.get(feature)
    if res["status"] == "PASS" and need is not None and abs(am - mu) < need:
        res["status"] = "FAIL"
        res["note"] = (f"beyond the sigma threshold but the change is only "
                       f"{abs(am - mu):.4f} (< {need:g}): too small to be an attack - "
                       f"a near-flat baseline makes any tiny move 'significant'")


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
        res["note"] = ("the normal phase never varied (sd = 0), so z is infinite: any "
                       "move in the expected direction counts")
        res["status"] = "PASS" if moved else "FAIL"
        _apply_min_effect(res, feature, mu, am)
        return res
    if len(a) < MIN_ATTACK_POINTS:
        res["status"] = "INCONCLUSIVE"
        res["note"] = (f"only {len(a)} attack point(s) - need >= {MIN_ATTACK_POINTS} "
                       f"(attack too short or the node dropped out)")
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

    _apply_min_effect(res, feature, mu, am)

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


RULE_W = 106  # report width; ASCII only - PowerShell 5.1 (analyze.ps1 | Out-Host) garbles box/emoji glyphs

# Short, fixed-width result words for the tables.
STATUS_FLAG = {
    "PASS": "PASS",
    "FAIL": "FAIL",
    "INVALID-BASE": "EXCLUDED",
    "INFEASIBLE": "UNTESTABLE",
    "INCONCLUSIVE": "NO DATA",
    "N/A": "N/A",
    "SKIP": "NO DATA",
}
TIER_WORD = {"primary": "primary", "secondary": "support"}

# The study behind each scored feature / check. ONLY studies already vetted in
# docs/references/2026-09-14_REFERENCES.md and docs/attack-validation/
# ATTACK-VALIDATION.md section 4 - that list deliberately stops at what is
# peer-reviewed and checked; do not add a tag here without adding it there.
STUDIES = {
    "Z":  "Zhukabayeva et al. (2025), Technologies 13(8):348 - 3-sigma normal-vs-attack "
          "test; wormhole = out-of-band tunnel between two nodes",
    "A":  "Airehrour, Gutierrez & Ray (2018), AJTDE 6(1):41-59 - blackhole = node that "
          "drops what it should forward; delivered/sent (ForwardingRatio, PDR) collapses",
    "KW": "Karlof & Wagner (2003) - blackhole damage depends on the attacker's POSITION "
          "(only traffic routed through it is lost)",
    "K":  "Khan et al. (2022), Sustainability 14(24):16630 - healthy ESP-MESH delivers "
          "PDR > 97 %: the floor for a valid normal phase",
    "R":  "Ramirez Gomez, Vargas Montoya & Leon Henao (2019), Rev. Colomb. Comput. 20(1) - "
          "wormhole signature = duplicate packets (same data unit twice)",
    "H":  "Hu, Perrig & Johnson (2003) - wormhole = a shortcut whose packets arrive with "
          "timing the claimed path cannot explain (packet leashes)",
    # D-23 (oct. 19 2026): the sources behind allowing board moves - checked online and
    # added to docs/references/2026-09-14_REFERENCES.md ("Added oct. 19, 2026")
    "E":  "Espressif Systems, ESP-WIFI-MESH API Guide (ESP-IDF v5.3), 'Intermediate Parent Node "
          "Failure' - official protocol documentation: children first retry the broken parent, then "
          "each selects a new parent; 'the network is healed, however the network routing has been "
          "affected'",
    "BA": "MacCoun & Perlmutter (2015), Nature 526:187-189 - blind analysis: the analysis is decided "
          "without looking at the result, to stop confirmation bias",
    "PR": "Simmons, Nelson & Simonsohn (2011), Psychol. Sci. 22(11):1359-1366; Nosek et al. (2018), "
          "PNAS 115(11):2600-2606 - rules fixed BEFORE the outcome is seen, not tuned afterwards",
}
FEATURE_STUDY = {
    "ForwardingRatio": "A", "PDR": "A", "ConsistencyScore": "A",
    "IngressEgressDelta": "A", "NeighbourForwardingRatio": "A",
    "TunnelIntensity": "Z", "TunnelBytes": "Z", "TunnelLatency": "H",
    "DuplicateRate": "R",
}
# Setup-check text -> study, matched on words the checks print.
CHECK_STUDY = [
    ("victim", "KW"), ("behind the attacker", "KW"), ("not behind", "KW"),
    ("forwarded", "A"), ("duplicate", "R"), ("UART", "Z"), ("shallower", "H"),
    ("REVERSED", "H"), ("SAME DEPTH", "H"),
    ("TOLERATED", "E"), ("ROBUST", "PR"),
]


def _reroute_lines(issues, measured):
    """Plain-words lines for [6]: one per board move + the robustness result."""
    out = []
    for it in issues or []:
        t = it.text
        who = t.split(" ", 1)[0]
        m = re.search(r"TOLERATED WITH EXCLUSION: it stayed a (\w+).*?but (\d+) of (\d+) windows", t)
        if m:
            out.append(f"{who}: ALLOWED - it stayed a {m.group(1)} in every second its path could be traced; "
                       f"the {m.group(2)} s it had NO path (its parent went down / it was searching) are LEFT OUT "
                       f"of the test [E]")
            continue
        m = re.search(r"TOLERATED: it stayed a (\w+) in every attack window \((\d+) s detached", t)
        if m:
            out.append(f"{who}: ALLOWED - it changed parent but stayed a {m.group(1)} the whole attack "
                       f"({m.group(2)} s re-joining, left out of the test) [E]")
            continue
        if "TOLERATED: the A end stayed shallower" in t:
            out.append(f"{who}: ALLOWED - it moved, but the A end stayed closer to the root than the B end, "
                       f"so the tunnel still skipped hops [E]")
            continue
        m = re.search(r"between VICTIM \((\d+) s\) and BYSTANDER \((\d+) s\)", t)
        if m and it.level == "FAIL":
            out.append(f"{who}: NOT ALLOWED - it was a VICTIM for {m.group(1)} s and a BYSTANDER for "
                       f"{m.group(2)} s: the attack reached it only part of the time, so its attack is two "
                       f"experiments mixed")
            continue
        if "ATTACKER itself moved" in t:
            out.append(f"{who}: NOT ALLOWED - the attacker moved; its position IS the experiment")
            continue
        if "the A end was NOT shallower" in t:
            out.append(f"{who}: NOT ALLOWED - the A end was not closer to the root than B for part of the "
                       f"attack: the shortcut changed")
            continue
        if "FLAPPED" in t:
            out.append(f"{who}: FLAPPED - its parent changed many times; allowed only because it never left its role, "
                       f"but the link is unstable [E]")
            continue
        if "has NO attack windows after" in t:
            m = re.search(r"after \+(\d+) s", t)
            out.append(f"{who}: WARNING - no attack windows after +{m.group(1) if m else '?'} s (went silent, or too few "
                       f"samples); the verdict uses the windows that exist")
            continue
        if "during the BASELINE" in t:
            out.append(f"{who}: its role changed during the BASELINE (no attack then - footnote only)")
            continue
        if "traceable VICTIM-seconds" in t and it.level == "FAIL":
            out.append("NOT ALLOWED - " + t)
            continue
        if t.startswith("ROBUST:"):
            out.append("Re-test: CONFIRMED again on the seconds BEFORE the first move alone - the moved "
                       "part is not what makes the verdict [PR]")
        elif t.startswith("NOT ROBUST"):
            out.append("Re-test: NOT confirmed on the seconds before the first move alone - the verdict "
                       "depends on the moved part, so the moves cannot be allowed [PR]")
        elif t.startswith("robustness re-test not possible"):
            m = re.search(r"only (\d+) s", t)
            out.append(f"Re-test: not possible - only {m.group(1) if m else '?'} s of attack came before the "
                       f"first move (needs 60 s); the verdict rests on the layout rule alone - footnote it")
    for line in measured or []:
        m = re.match(r"EXCLUDED from the test: (\d+) attack window", line)
        if m:
            out.append(f"Left out of the test: {m.group(1)} attack second(s) in total with no path to the root - "
                       f"they show 0 delivery for a reason that is not the attack, so leaving them out can only "
                       f"make the attack HARDER to confirm")
    return out


# ---- CONFIDENCE GRADE (oct. 19 2026, final form; user: "make the grading perfect, not
# confusing" + "two kinds of incomplete data"). The VERDICT line above is unchanged (the
# GUI, Campaign and redo list read it). From the checks above only - fixed rules:
#
#   STRONG           attack confirmed, all board data present, nothing to note
#   GOOD             attack confirmed, all board data present, notes for the report
#   MINOR GAPS  attack confirmed; some data is missing but NOT data the result needs:
#                    a board's cooldown (the verdict compares baseline vs attack only), or
#                    part of a board's attack (cut at the end, or only N s of it) - and the
#                    IMPACT CHECK proves it: the 3-sigma test re-run WITHOUT those boards
#                    still confirms the attack. (oct. 19 2026: a fixed "< 60 s = major" rule
#                    was dropped - it overrode the impact check's evidence on tree/G402/
#                    stationary, where B768 had 28 s and the attack held without it.)
#   MAJOR GAPS  attack confirmed and visible, but data the result relies on is missing:
#                    a board never measured in the attack (dropped out before it / no
#                    labelled window), a large share of victim time with no path - or
#                    minor gaps that FAILED the impact check
#   NOT CONFIRMED    no attack signature, too little to test, or the setup was invalid
#
# Every warning lands somewhere (verification #50). The Campaign / Verify status scale
# (user, oct. 19): green DONE = STRONG / GOOD (redo list OK) . yellow DONE - RECAPTURE ADVISED =
# MINOR GAPS (CHECK) . orange RECAPTURE REQUIRED = MAJOR GAPS (REDO,
# evidence 'verifier-data'), or another source demands a recapture . red REDO = NOT CONFIRMED
GRADES = ("STRONG", "GOOD", "MINOR GAPS", "MAJOR GAPS", "NOT CONFIRMED")
_FOOTNOTE = [  # (words in a WARN, short footnote)
    ("robustness re-test not possible", "the re-test on the seconds before the first move was not possible (too short)"),
    ("robustness re-test inconclusive", "the re-test on the seconds before the first move was inconclusive"),
    ("TOLERATED", "moved to a new parent but kept the same role - allowed"),
    ("FLAPPED", "its link was unstable - many parent changes"),
    ("during the BASELINE", "the layout changed during the baseline"),
    ("when START was pressed", "a board's role changed between the baseline and the attack"),
    ("in the first", "a board's role changed between the attack and the cooldown"),
    ("NOT in the baseline", "joined only during the attack"),
    ("FORCE-STARTED", "the run was force-started (START_ANYWAY)"),
    ("overridden by the operator", "START was pressed over failed pre-START checks"),
]


def _gap(it):
    """('major' | 'minor', board, text) when the issue is a DATA GAP, else None."""
    t = it.text
    who = t.split(" ", 1)[0] if t[:4].isalnum() else ""
    role = (" (attacker)" if "the ATTACKER" in t or re.match(r"\S+ \((blackhole|wormhole)", t) else
            " (victim)" if "a victim" in t else "")
    m = re.search(r"has NO attack windows after \+(\d+) s \((\d+) s before the end\)", t)
    if m:
        # measured, but only part of the attack: the impact check decides (no fixed cut).
        # "X of Y s" is drawn as a recorded / missing bar by the GUI.
        kept, gone = int(m.group(1)), int(m.group(2))
        return "minor", who, (f"{who}{role}: only {kept} of {kept + gone} s of its attack were recorded "
                              f"- the last {gone} s are missing (it went silent, or too few samples)")
    if "COOLDOWN" in t and ("has NO" in t or "only" in t):
        got = re.search(r"only (\d+) s of", t)
        full = re.search(r"the others: (\d+) s", t)
        return "minor", who, (f"{who}{role}: only {got.group(1) if got else 0} of {full.group(1) if full else '?'} s of "
                              f"cooldown were recorded - its recovery after the attack is not measured "
                              f"(the verdict compares baseline and attack only)")
    if "no attack-window telemetry" in t:
        return "major", "", t.split("telemetry from ", 1)[-1].split(" (")[0] + ": dropped out before the attack, so it was never measured"
    if "NO labelled window" in t:
        return "major", "", t.rsplit(": ", 1)[-1].split(" - ")[0] + ": no usable windows (no phase was seen), so the checks ran without it"
    if "left out - over" in t:
        m = re.search(r"(\d+) of (\d+) victim-seconds \((\d+)%\)", t)
        if m:
            a, b = int(m.group(1)), int(m.group(2))
            return "major", "", (f"only {b - a} of {b} victim-seconds could be tested - the other {a} ({m.group(3)}%) "
                                 f"had no path to the root and were left out")
        return "major", "", "most of the victims' attack time had no path to the root and was left out of the test"
    if t.startswith("IMPACT CHECK FAILED"):
        return "major", "", "the small gaps DO change the result: " + t.split(": ", 1)[-1]
    return None


def _confidence(confirmed, setup_invalid, conclusive, issues):
    """(grade, major gaps, minor gaps, notes, why_not) - see the table above."""
    issues = issues or []
    if not confirmed or setup_invalid:
        fails = [i.text for i in issues if i.level == "FAIL"]
        if setup_invalid and fails:
            return "NOT CONFIRMED", [], [], [], ["setup invalid: " + f for f in fails[:3]]
        return "NOT CONFIRMED", [], [], [], (["no primary signature moved beyond the threshold"] if conclusive
                                             else ["no primary signature could be tested (too little data)"])
    major, minor, notes, good = [], [], [], []
    for it in issues:
        if it.level == "OK" and it.text.startswith(("ROBUST:", "IMPACT CHECK:")):
            good.append(it.text.split(":", 1)[0].lower().replace("robust", "the re-test on the part BEFORE the first move confirmed it again")
                        if it.text.startswith("ROBUST:") else "impact check: " + it.text.split(": ", 1)[1])
            continue
        if it.level != "WARN":
            continue
        g = _gap(it)
        if g:
            (major if g[0] == "major" else minor).append(g[2])
            continue
        for words, short in _FOOTNOTE:
            if words in it.text:
                who = it.text.split(" ", 1)[0] if it.text[:4].isalnum() else ""
                board = who and not who.startswith(("the", "only", "this", "no", "START", "robustness"))
                notes.append(f"{who}: {short}" if board else (short[0].upper() + short[1:] if short.startswith(("moved", "its", "joined")) else short))
                break
        else:
            notes.append(" ".join(it.text.split())[:110] + ("..." if len(it.text) > 110 else ""))   # never dropped (#50)
    for it in issues:
        if it.level == "SKIP" and it.text.startswith("START_ANYWAY"):
            notes.append("whether the run was force-started could not be checked (no run log saved)")
            break
    major, minor, notes = (list(dict.fromkeys(x)) for x in (major, minor, notes))
    notes_all = notes + good
    if major:
        return "MAJOR GAPS", major, minor, notes_all, []
    if minor:
        return "MINOR GAPS", [], minor, notes_all, []
    if notes:
        return "GOOD", [], [], notes_all, []
    return "STRONG", [], [], notes_all, []


def _impact_issue(df_in, attack, sigma, block, issues):
    """IMPACT CHECK (oct. 19 2026): re-run the 3-sigma test WITHOUT the boards that have
    only minor gaps. Still confirmed -> the gaps do not change the result (OK). Not
    confirmed -> they DO (the grade becomes MAJOR GAPS). Only ever makes it stricter."""
    boards = sorted({g[1] for g in (_gap(i) for i in issues if i.level == "WARN") if g and g[0] == "minor" and g[1]})
    if not boards:
        return None
    keep = ~df_in["node_id"].astype(str).str[-4:].str.upper().isin([b.upper() for b in boards])
    saved = (_LAST_SETUP_INVALID[0], list(_LAST_ISSUES[0]))
    try:
        with contextlib.redirect_stdout(io.StringIO()):
            ok, conclusive = verify(df_in[keep].copy(), attack, sigma, block, checks=False)
    finally:
        _LAST_SETUP_INVALID[0], _LAST_ISSUES[0] = saved
    names = ", ".join(boards)
    if ok:
        return _checks.Issue("OK", f"IMPACT CHECK: without {names} (the boards with minor gaps) the attack is still "
                                   f"confirmed - the gaps do not change the result")
    return _checks.Issue(_checks.WARN, f"IMPACT CHECK FAILED: without {names} the attack is "
                                       f"{'not confirmed' if conclusive else 'untestable'} - the result depends on them")


def _n(k, word):
    """'1 note' / '2 notes' - no "(s)"."""
    return f"{k} {word}" + ("" if k == 1 else "s")


def _print_confidence(confirmed, setup_invalid, conclusive, issues, attack, count):
    grade, major, minor, notes, why_not = _confidence(confirmed, setup_invalid, conclusive, issues)
    if grade == "NOT CONFIRMED":
        print(" CONFIDENCE: NOT CONFIRMED - " + ("the setup was invalid" if setup_invalid else
                                                ("no attack signature" if conclusive else "too little data to test")))
        for w in why_not:
            print(_wrap(w, "     x "))
        return
    good = [n for n in notes if n.startswith(("the re-test on the part BEFORE", "impact check:"))]
    real = [n for n in notes if n not in good]
    say = {"STRONG": "attack confirmed, all board data present, nothing to note",
           "GOOD": f"attack confirmed, all board data present, {_n(len(real), 'note')} for the report",
           "MINOR GAPS": f"attack confirmed; {_n(len(minor), 'small gap')} in the data, none of which change{'s' if len(minor) == 1 else ''} the result - recapture advised",
           "MAJOR GAPS": f"attack confirmed, but data the result relies on is missing ({_n(len(major), 'major gap')}) - recapture required"}[grade]
    print(f" CONFIDENCE: {grade} - {say}")
    print(_wrap(f"ATTACK: confirmed - {count}", "     + "))
    print(_wrap("SETUP: no check failed", "     + "))
    for g in major:
        print(_wrap("MAJOR GAP (affects the result): " + g, "     ~ "))
    for g in minor:
        print(_wrap("MINOR GAP (result not affected): " + g, "     ~ "))
    if not major and not minor:
        print(_wrap("DATA: every board has usable data for the whole attack", "     + "))
    for n in good:
        print(_wrap(n, "     + "))
    for n in real:
        print(_wrap("note: " + n, "     ~ "))
    tag = {"STRONG": "", "GOOD": "", "MINOR GAPS": " - minor gaps", "MAJOR GAPS": " - major gaps"}[grade]
    foot = len(major) + len(minor) + len(real)
    print(_wrap(f"REPORT AS: \"{attack.upper()} CONFIRMED{tag}\""
                + (f" + {_n(foot, 'footnote')} (copy them to the thesis checklist)" if foot else ""), "     = "))


def _print_reroute_why(issues, measured, setup_invalid):
    lines = _reroute_lines(issues, measured)
    if not lines:
        return
    print()
    print(" [6] WHY THE BOARD MOVES WERE ALLOWED - OR NOT   (D-23; full note: docs/attack-validation/"
          "REROUTE-VERDICT.md)")
    for para in (
        "The question is not 'did a board change parent?' but 'did the move change WHO the attack "
        "reaches?' A blackhole only harms traffic that passes through it [KW], and ESP-WIFI-MESH heals "
        "itself: when a parent breaks down, its children first retry it, then each picks a new parent [E].",
        "How: for every board, every second, its parents are followed up to the root -> VICTIM (passes the "
        "attacker), BYSTANDER (does not), or NO PATH (detached / a board above it went down).",
        "Rules: a board must stay VICTIM or BYSTANDER the whole attack (3 s+ of each = NOT ALLOWED); the "
        "attacker may never move; NO-PATH seconds are left out of the test; where 60 s+ came before the "
        "first move, the attack must also be confirmed on those seconds alone.",
        "Fairness: decided from the layout only - delivery is never used to allow a move [BA]; the limits "
        "were fixed in advance and are the same for every run [PR].",
    ):
        print(_wrap(para, "     "))
    print()
    print("     This run:")
    for line in lines:
        print(_wrap(line, "       - "))
    print()
    print(_wrap("So: " + ("a move changed who the attack reached (or the re-test failed) - SETUP INVALID."
                          if setup_invalid else
                          "the moves did not change who the attack reached - the VERDICT above stands, "
                          "with the footnotes listed here."), "     "))
    print()
    print("     Sources for [6]:")
    for tag in ("E", "KW", "BA", "PR"):
        print(_wrap(STUDIES[tag], f"     [{tag}]{' ' * (3 - len(tag))}"))


# oct. 19 2026: setup checks grouped so a reader sees WHERE a problem is. First match
# wins - the order matters (e.g. "the ATTACKER has NO attack windows" is a BOARDS
# matter, "1 node not behind the attacker" a VICTIMS one).
CHECK_GROUPS = [
    ("BOARDS", ("NO attack windows", "no attack-window telemetry", "NO labelled window", "appears in the attack")),
    ("RE-TEST", ("ROBUST", "robustness")),
    ("TOPOLOGY", ("changed parent", "switched between", "topology", "FLAPPED", "during the BASELINE",
                  "when START was pressed", "in the first", "ATTACKER itself moved", "layout")),
    ("TUNNEL", ("UART", "tunnel", "A end", "B end", "shallower", "duplicate", "REVERSED", "SAME DEPTH", "wormhole")),
    ("VICTIMS", ("victim", "behind", "cut off", "kept delivering", "not specific")),
    ("ATTACKER", ("attacker", "forward", "received")),
    ("START", ("START", "force", "overridden")),
]
_LEVEL_RANK = {"FAIL": 3, "WARN": 2, "OK": 1, "SKIP": 0}


def _group_of(text):
    for name, words in CHECK_GROUPS:
        if any(w.lower() in text.lower() for w in words):
            return name
    return "OTHER"


def _grouped_checks(issues):
    """[(group, worst level, [issues])] in CHECK_GROUPS order."""
    groups = {}
    for it in issues:
        groups.setdefault(_group_of(it.text), []).append(it)
    out = []
    for name in [g for g, _ in CHECK_GROUPS] + ["OTHER"]:
        if name in groups:
            worst = max(groups[name], key=lambda i: _LEVEL_RANK.get(i.level, 0)).level
            out.append((name, worst, groups[name]))
    return out


def _check_study(text):
    tags = []
    for word, tag in CHECK_STUDY:
        if word.lower() in text.lower() and tag not in tags:
            tags.append(tag)
    return tags
CHECK_MARK = {"OK": "OK  ", "FAIL": "FAIL", "WARN": "WARN", "SKIP": "--  "}


# Set by verify(): True when the last wormhole check found a setup problem
# (main() turns it into exit code 3).
_LAST_SETUP_INVALID = [False]
_LAST_ISSUES = [[]]


def _num(x, nd=3):
    return "n/a" if x is None or (isinstance(x, float) and math.isnan(x)) else f"{x:.{nd}f}"


def _wrap(text, indent, width=RULE_W):
    """Word-wrap `text` to the report width with a hanging indent."""
    import textwrap
    return textwrap.fill(text, width=width, initial_indent=indent,
                         subsequent_indent=" " * len(indent))


def _measured_line(name, feat, r, sigma):
    """One plain-language line for a feature that is MEASURED, never scored."""
    am = r["attack_mean"]
    if feat == "TunnelLatency":
        if math.isnan(am):
            return f"{name}: no duplicated probe reached the root - nothing to measure"
        return (f"{name}: the two copies of B's probes reached the root {am:.1f} ms apart "
                f"(attack mean). Exists only while the tunnel runs, so there is no normal "
                f"value to test against - reported as a measurement: the wormhole's timing "
                f"mismatch")
    if feat == "LatencyHopRatio":
        if math.isnan(am) or math.isnan(r["mu"]):
            return f"{name}: not enough latency data"
        return (f"{name}: normal {r['mu']:.1f} +- {r['sd']:.1f} -> attack {am:.1f} "
                f"(z {_fmt_z(r['z']).strip()}). Relative one-way delay per hop (board clocks "
                f"are not synchronised) with rare 100s-of-ms spikes, so its normal spread is "
                f"too wide for a 3-sigma test - context only")
    if r.get("note"):
        return f"{name}: {r['note']}"
    return (f"{name}: normal {_num(r['mu'])} +- {_num(r['sd'])} -> attack "
            f"{_num(r['attack_mean'])} (z {_fmt_z(r['z']).strip()})")


def _robustness_issue(df_in, attack, sigma, block, issues):
    """D-23 fairness rule 5: a TOLERATED re-route may only stand if the verdict also
    holds on the attack windows BEFORE the first re-route. Uses the outcome only to
    DOWNGRADE: it can turn CONFIRMED into SETUP INVALID, never the other way."""
    if not any("TOLERATED" in it.text for it in issues):
        return None
    key = set()
    for it in issues:
        if "TOLERATED" in it.text:
            key.add(it.text.split(" ", 1)[0])
    onset = _checks.reroute_onset(df_in, attack)
    if onset is None:
        return None
    tc = _checks._tcol(df_in)
    lab = pd.to_numeric(df_in["Label"], errors="coerce")
    is_atk = lab == ATTACK_LABEL[attack]
    t = pd.to_numeric(df_in[tc], errors="coerce")
    pre = df_in.copy()
    pre.loc[is_atk & (t >= onset), "Label"] = float("nan")
    secs = t[is_atk & (t < onset)]
    span = float(secs.max() - t[is_atk].min()) if len(secs) else 0.0
    if span < _checks.ROBUST_MIN_ATTACK_S:
        return _checks.Issue(_checks.WARN, f"robustness re-test not possible: only {span:.0f} s of attack before the "
                                           f"first re-route (needs {_checks.ROBUST_MIN_ATTACK_S:.0f} s) - the TOLERATED "
                                           f"verdict rests on the layout rule alone")
    saved = _LAST_SETUP_INVALID[0]
    buf = io.StringIO()
    try:
        with contextlib.redirect_stdout(buf):
            ok, conclusive = verify(pre, attack, sigma, block, checks=False)
    finally:
        _LAST_SETUP_INVALID[0] = saved
    if not conclusive:
        return _checks.Issue(_checks.WARN, f"robustness re-test inconclusive on the {span:.0f} s of attack before the "
                                           f"first re-route - the TOLERATED verdict rests on the layout rule alone")
    if ok:
        return _checks.Issue("OK", f"ROBUST: the {span:.0f} s of attack BEFORE the first re-route confirm the attack on "
                                   f"their own (same {sigma:g}-sigma test) - the re-routed windows are not what makes "
                                   f"the verdict")
    return _checks.Issue(_checks.FAIL, f"NOT ROBUST: the {span:.0f} s of attack before the first re-route do NOT confirm "
                                       f"the attack on their own - the verdict depends on the windows after the "
                                       f"re-route, so the TOLERATED re-route cannot stand")


def verify(df, attack, sigma, block=DEFAULT_BLOCK_WINDOWS, checks=True):
    """Run the 3-sigma test + setup checks for one attack and print the report.

    Output is built first and printed in one go so the RESULT can sit at the
    top. The decision logic (what counts, what is excluded) is unchanged from
    the oct. 14 2026 version; only the layout changed (oct. 16 2026).
    Returns (confirmed, conclusive).
    """
    label = ATTACK_LABEL[attack]
    df_in = df
    # D-23 (oct. 19 2026): attack windows in which a board had no working path to
    # the root (detached / a board above it went down) are not attack evidence -
    # drop them from the scored test (fairness rule 6: only makes it HARDER).
    dropped = 0
    if checks and _checks is not None and hasattr(_checks, "unresolved_windows"):
        try:
            bad = _checks.unresolved_windows(df, attack)
            if bad:
                tc = _checks._tcol(df)
                key = list(zip(df["node_id"], pd.to_numeric(df[tc], errors="coerce").round(3)))
                hit = pd.Series([k in bad for k in key], index=df.index) & (pd.to_numeric(df["Label"], errors="coerce") == label)
                dropped = int(hit.sum())
                if dropped:
                    df = df.copy()
                    df.loc[hit, "Label"] = float("nan")
        except Exception:
            dropped = 0
    raw_lab = pd.to_numeric(df["Label"], errors="coerce")
    n_base_w = int((raw_lab == LABEL_BASELINE).sum())
    n_atk_w = int((raw_lab == label).sum())

    if attack == "wormhole":
        df = _add_duplicate_rate(df)
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

    scoped = ATTACKER_SCOPED.get(attack, {})
    attacker_ids = {}
    if "node_role" in df_nodes.columns and "node_id" in df_nodes.columns:
        for feat, role in scoped.items():
            ids = set(df_nodes.loc[df_nodes["node_role"] == role, "node_id"].dropna())
            if ids:
                attacker_ids[feat] = ids

    # A table that HAS node_role but no attacker rows = the attacker's telemetry
    # was never imported. Falling back to the pooled test there tests only the
    # honest relays (sept30 partial_mesh G402, before its attacker SD card was
    # imported: 70C80 alone, 357/357 forwarded -> FAIL counted as primary).
    # Report the row as missing instead; only legacy tables without node_role
    # still use the pooled test.
    has_roles = "node_role" in df_nodes.columns
    rows = []
    for feat, direction, tier in SIGNATURES[attack]:
        if feat in attacker_ids:
            if feat in ALSO_POOLED:
                rows.append((f"{feat} (all relays)", feat, direction, "info", None))
            rows.append((f"{feat} (attacker)", feat, direction, tier, attacker_ids[feat]))
        elif feat in scoped and has_roles:
            rows.append((f"{feat} (attacker)", feat, direction, tier, MISSING_ATTACKER))
        else:
            rows.append((feat, feat, direction, tier, None))

    primary_pass = primary_total = primary_excluded = primary_missing = 0
    scored, measured, notes = [], [], []
    best = None  # strongest passing primary, for the RESULT line
    for name, feat, direction, tier, node_ids in rows:
        if feat not in df.columns and node_ids is not MISSING_ATTACKER:
            if tier not in ("info", "measured"):
                scored.append((name, tier, None, direction))
            continue
        if node_ids is MISSING_ATTACKER:
            empty = pd.Series(dtype=float)
            r = stat_verdict(empty, empty, direction, sigma, feature=feat)
            r["status"] = "INCONCLUSIVE"
            r["note"] = (f"no '{scoped[feat]}' node in this table - the attacker's telemetry "
                         f"was not imported. Honest relays cannot stand in for it (they keep "
                         f"forwarding), so this row is left out of the verdict. Import the "
                         f"attacker's SD card and re-run analyze.ps1")
            if tier == "primary":
                primary_missing += 1
        else:
            scope = df["node_id"].isin(node_ids) if node_ids else pd.Series(True, index=df.index)
            r = stat_verdict(df.loc[base_mask & scope, feat], df.loc[atk_mask & scope, feat],
                             direction, sigma, feature=feat)
            if feat == "NeighbourForwardingRatio" and node_ids and not r["note"]:
                r["note"] = NEIGHBOUR_NOTE

        # A feature whose own baseline is broken cannot say anything about the
        # attack; counting its FAIL would read as evidence of no attack.
        floor = BASELINE_FLOOR.get(feat)
        if floor is not None and not math.isnan(r["mu"]) and r["mu"] < floor:
            r["status"] = "INVALID-BASE"
            r["note"] = (f"normal-phase mean {r['mu']:.3f} < {floor:g}; Khan et al. (2022) "
                         f"measured PDR > 0.97 on ESP-MESH, so this baseline is a "
                         f"broken measurement, not a quiet network - excluded")
        ceiling = BASELINE_DISPERSION_CEILING.get(feat)
        if (ceiling is not None and r["status"] not in ("INVALID-BASE", "SKIP")
                and not math.isnan(r["mu"]) and not math.isnan(r["sd"])
                and r["mu"] > 0 and (r["sd"] / r["mu"]) > ceiling):
            r["status"] = "INVALID-BASE"
            r["note"] = (f"normal phase {r['mu']:.3f}+-{r['sd']:.3f} has sd/mu = "
                         f"{r['sd'] / r['mu']:.2f} > {ceiling:g} on a bounded ratio; "
                         f"that is a broken measurement, not normal operation "
                         f"(check for pre_baseline contamination) - excluded")

        if tier == "info":
            r["note"] = _pooled_note(df_nodes, feat, label, attacker_ids[feat], r, sigma)
            measured.append(f"{name}: {r['note']}")
            continue
        if tier == "measured":
            measured.append(_measured_line(name, feat, r, sigma))
            continue

        if tier == "primary" and r["status"] in ("PASS", "FAIL"):
            primary_total += 1
            if r["status"] == "PASS":
                primary_pass += 1
                key = (math.isfinite(r["z"]), abs(r["z"]) if math.isfinite(r["z"]) else 0)
                if best is None or key > best[2]:
                    best = (name, r, key)
        elif tier == "primary" and r["status"] in ("INVALID-BASE", "INFEASIBLE"):
            primary_excluded += 1
        if r["note"]:
            notes.append((name, r["note"]))
        scored.append((name, tier, r, direction))

    conclusive = primary_total > 0
    confirmed = conclusive and primary_pass > 0
    if dropped:
        measured.append(f"EXCLUDED from the test: {dropped} attack window(s) in which a board had no working path to "
                        f"the root (detached, or a board above it went down) - neither attack evidence nor its absence "
                        f"(D-23; including them would only make the attack look stronger)")

    # SETUP CHECKS (tools/attack_checks.py, oct. 14 2026): topology during the
    # attack, the attacker / victims / tunnel behaving as designed. The 3-sigma
    # table says the features MOVED; these say whether the attack we claim is
    # what moved them. Any FAIL -> SETUP INVALID; WARN / SKIP never change it.
    setup_invalid = False
    if _checks is None or not checks:
        issues = None
    else:
        try:
            issues = _checks.setup_issues(df_nodes, attack)
        except Exception as e:                      # never block the verdict
            issues = [_checks.Issue(_checks.SKIP, f"setup checks could not run: {e}")]
        if confirmed:
            try:
                rob = _robustness_issue(df_in, attack, sigma, block, issues)
            except Exception as e:                  # never block the verdict
                rob = _checks.Issue(_checks.WARN, f"robustness re-test could not run: {e}")
            if rob is not None:
                issues.append(rob)
            try:
                imp = _impact_issue(df_in, attack, sigma, block, issues)
            except Exception as e:                  # never block the verdict
                imp = _checks.Issue(_checks.WARN, f"impact check could not run: {e}")
            if imp is not None:
                issues.append(imp)
        setup_invalid = any(it.level == _checks.FAIL for it in issues)
    # exit 3 means 'the signature passed, but the setup was invalid' - only then.
    _LAST_SETUP_INVALID[0] = setup_invalid and confirmed
    if checks:
        _LAST_ISSUES[0] = list(issues or [])     # redo_list.py reads the SAME issues (incl. the re-test)

    # ── verdict text ─────────────────────────────────────────────────────────
    count = f"{primary_pass}/{primary_total} primary signature(s) beyond {sigma:g}-sigma"
    extra = []
    if primary_excluded:
        extra.append(f"{primary_excluded} primary excluded (broken or untestable normal phase)")
    if primary_missing:
        extra.append(f"{primary_missing} primary not tested (attacker telemetry missing)")
    if confirmed and setup_invalid:
        result = "NOT CONFIRMED - SETUP INVALID"
        why = ("the signature moved, but a setup check FAILED (see [3]) - the attack did not "
               "run as designed. Do not report it as confirmed; fix the setup and recapture.")
        verdict = f"{attack.upper()} NOT CONFIRMED - SETUP INVALID  ({count})"
    elif confirmed:
        result = "CONFIRMED"
        b = best[1] if best else None
        if b is None:
            why = count
        elif math.isfinite(b["z"]):
            why = (f"{best[0]}: normal {b['mu']:.3f} -> attack {b['attack_mean']:.3f}, "
                   f"{b['z']:+.2f} sigma (needs {sigma:g})")
        else:
            why = (f"{best[0]}: normal {b['mu']:.3f} -> attack {b['attack_mean']:.3f}; the "
                   f"normal phase never varied, so this move is beyond any sigma")
        verdict = f"{attack.upper()} CONFIRMED  ({count})"
    elif not conclusive:
        result = "INCONCLUSIVE"
        why = ("no primary signature had usable data - need a full attack run with the "
               "attacking node's telemetry present.")
        verdict = "INCONCLUSIVE - no primary signature feature had usable data"
    else:
        result = "NOT CONFIRMED"
        why = f"no primary signature reached {sigma:g}-sigma - check the attacker setup / run."
        verdict = f"NOT CONFIRMED - no primary signature exceeded {sigma:g}-sigma"
    if extra:
        verdict += ". " + "; ".join(extra)

    # ── print ────────────────────────────────────────────────────────────────
    cell = " / ".join(str(_first_val(df_nodes, c)) for c in
                      ("topology", "location", "scenario") if _first_val(df_nodes, c))
    rep = _first_val(df_nodes, "run_repeat")
    title = f" {attack.upper()} VERIFICATION" + (f"  -  {cell}" if cell else "") \
        + (f"  (r{rep})" if rep not in (None, "") else "")
    print()
    print("=" * RULE_W)
    print(title)
    print("=" * RULE_W)
    print(f" RESULT : {result}")
    print(_wrap(why, "          "))
    print()

    used = {"Z"}
    print(" [1] ATTACK SIGNATURE   3-sigma test: attack phase vs normal phase  [Z]")
    print(f"     normal phase: {n_base_w} windows   attack phase: {n_atk_w} windows")
    print(_wrap(f"pooling: {agg_note}", "     "))
    print()
    print(f"     {'result':<11}{'feature':<37}{'normal':<17}{'attack':<9}{'z':>7}  "
          f"{'role':<15}study")
    print("     " + "-" * (RULE_W - 5))
    for name, tier, r, direction in scored:
        arrow = "down" if direction == "down" else "up"
        if r is None:
            print(f"     {'NO DATA':<11}{name:<37}(column missing)")
            continue
        normal = "n/a" if math.isnan(r["mu"]) else f"{r['mu']:.3f} +- {r['sd']:.3f}"
        atk = _num(r["attack_mean"])
        flag = STATUS_FLAG.get(r["status"], r["status"])
        tag = FEATURE_STUDY.get(name.split(" (")[0], "")
        used.update([tag] if tag else [])
        role = f"{TIER_WORD.get(tier, tier)}, {arrow}"
        print(f"     {flag:<11}{name:<37}{normal:<17}{atk:<9}{_fmt_z(r['z'])}  "
              f"{role:<15}{('[' + tag + ']') if tag else ''}")
    if notes:
        print()
        for i, (name, note) in enumerate(notes, 1):
            print(_wrap(f"{name}: {note}", f"     note {i}: "))
    print()

    if measured:
        print(" [2] MEASURED, NOT SCORED   shown for context; never part of the verdict")
        for line in measured:
            tag = FEATURE_STUDY.get(line.split(":")[0].split(" (")[0], "")
            if tag and tag != "A":
                used.add(tag)
                line += f" [{tag}]"
            print(_wrap(" ".join(line.split()), "     - "))
        print()

    print(" [3] SETUP CHECKS   did the attack run as designed? (from the data)")
    if issues is None:
        print("     ??   tools/attack_checks.py could not be imported - setup NOT checked")
    else:
        groups = _grouped_checks(issues)
        light = {"FAIL": "[FAIL]", "WARN": "[WARN]", "OK": "[ OK ]", "SKIP": "[ -- ]"}
        print("     AT A GLANCE:  " + "   ".join(f"{g} {light.get(w, '[ ?? ]')}" for g, w, _ in groups))
        print()
        try:
            sketch = _checks.layout_sketch(df_nodes, attack)
        except Exception:
            sketch = []
        if sketch:
            print("     LAYOUT AT THE START OF THE ATTACK   (who sat under whom;  * = what happened during the attack)")
            for ln in sketch:
                print("       " + ln)
            print()
        order = {"FAIL": 0, "WARN": 1, "SKIP": 2, "OK": 3}
        for g, w, its in groups:
            print(f"     {g} {'.' * max(3, 40 - len(g))} {w if w != 'SKIP' else '--'}")
            for it in sorted(its, key=lambda i: order.get(i.level, 9)):
                tags = _check_study(it.text)
                used.update(tags)
                text = it.text + ("  " + " ".join(f"[{t}]" for t in tags) if tags else "")
                print(_wrap(text, f"       {CHECK_MARK.get(it.level, '    ')} "))
    print()

    print(" [4] PER-NODE DELIVERY (PDR)")
    print_per_node_pdr(df_nodes, label)
    _print_unlisted(df_nodes, label)

    if any("Khan" in n for _, n in notes):
        used.add("K")
    print(" [5] STUDY BASIS   the peer-reviewed source behind each [tag] above")
    for tag in STUDIES:
        if tag in used:
            print(_wrap(STUDIES[tag], f"     [{tag}]{' ' * (3 - len(tag))}"))
    print()

    print("-" * RULE_W)
    print(f" VERDICT: {verdict}")
    _print_confidence(confirmed, setup_invalid, conclusive, issues, attack, count)
    print("-" * RULE_W)
    # oct. 19 2026 (user): the explanation of any allowed / refused board move, in
    # plain words with its sources, right below the verdict
    _print_reroute_why(issues, measured, setup_invalid)
    # A passing signature with a FAILED setup check is not a confirmation.
    return confirmed and not setup_invalid, conclusive


# ANSI colour per report line, by the words the report itself prints. Used ONLY
# when stdout is a real terminal (never into a pipe or file - the wizard's
# transcripts showed raw escapes as mojibake). analyze.ps1 colours the same
# words itself with Write-Host, which works on every Windows console.
_ANSI = {"green": "\033[32m", "red": "\033[31m", "yellow": "\033[33m",
         "cyan": "\033[36;1m", "dim": "\033[90m", "bold": "\033[1m"}


def _line_colour(line):
    t = line.strip()
    if not t:
        return None
    if set(t) <= set("=-"):
        return "dim"
    if t.startswith(("RESULT", "VERDICT")):
        if "NOT CONFIRMED" in t:
            return "red"
        if "INCONCLUSIVE" in t:
            return "yellow"
        return "green" if "CONFIRMED" in t else "bold"
    if t.startswith(("[1]", "[2]", "[3]", "[4]", "[5]", "[6]")) and line.startswith(" ["):
        return "cyan"
    if t.startswith("AT A GLANCE"):
        return "red" if "[FAIL]" in t else ("yellow" if "[WARN]" in t else "green")
    if t.startswith("LAYOUT AT THE START"):
        return "cyan"
    if " ..." in t and t.split()[-1] in ("FAIL", "WARN", "OK", "--") and t.split()[0].isupper():
        return {"FAIL": "red", "WARN": "yellow", "OK": "green"}.get(t.split()[-1], "dim")
    if "NOT ALLOWED" in t and ("+-- " in t or "`-- " in t):
        return "red"
    if t.startswith("CONFIDENCE"):
        return ("red" if "NOT CONFIRMED" in t.upper() else "green" if t.startswith(("CONFIDENCE: STRONG", "CONFIDENCE: GOOD"))
                else "yellow")
    if t.startswith(("+ ", "= ")):
        return "green"
    if t.startswith("~ "):
        return "yellow"
    if t.startswith("x ") and line.startswith("     x"):
        return "red"
    if t.startswith(("WORMHOLE VERIFICATION", "BLACKHOLE VERIFICATION")):
        return "bold"
    first = t.split()[0]
    if first in ("PASS", "OK"):
        return "green"
    if first == "FAIL":
        return "red"
    if first in ("WARN", "UNTESTABLE", "EXCLUDED", "NO", "N/A", "??", "!!"):
        return "yellow"
    if first in ("--", "note") or t.startswith("[") and line.startswith("     ["):
        return "dim"
    return None


def _print_coloured(text):
    if os.name == "nt":
        os.system("")              # switches the Windows console into VT mode
    for line in text.splitlines():
        c = _line_colour(line)
        print(f"{_ANSI[c]}{line}\033[0m" if c else line)


def _print_unlisted(df, label):
    """Name every non-root board the per-node PDR table could NOT show, and why.

    Without this the table reads as if only the listed boards were measured
    (oct. 16 2026, wormhole/tree/DLSU: 2 of 7 children listed, the other 5
    delivered normally in the raw arrivals)."""
    if not {"node_id", "Label", "PDR"} <= set(df.columns):
        return
    lab = pd.to_numeric(df["Label"], errors="coerce")
    atk = df[lab == label]
    listed = set(atk.loc[pd.to_numeric(atk["PDR"], errors="coerce").notna(), "node_id"])
    role = (df.dropna(subset=["node_role"]).groupby("node_id")["node_role"]
            .agg(lambda x: str(x.mode().iloc[0])) if "node_role" in df.columns else pd.Series())
    reasons = {}
    for n in sorted(set(df["node_id"].dropna()) - listed):
        r = str(role.get(n, "")).lower()
        if r == "root":
            continue
        if r in ("wormhole_a", "wormhole_b", "blackhole"):
            why = "attacking board - PDR is computed for plain children only"
        elif n not in set(atk["node_id"]):
            why = "no attack windows in the table (see [3])"
        else:
            why = "no delivery data in its attack windows"
        reasons.setdefault(why, []).append(n[-4:] if len(n) > 4 else n)
    for why, ns in reasons.items():
        print(_wrap(f"not listed: {', '.join(ns)} - {why}", "     "))
    if reasons:
        print()


def _add_duplicate_rate(df):
    """DuplicateRate per window, on Node B's rows only: 1.0 when the root logged
    one of that window's probes twice, else 0.0 (NaN on every other node).

    features.compute_latency_features fills TunnelLatency ONLY for windows whose
    probes arrived at the root more than once, so 'TunnelLatency present' is
    exactly 'the root saw a duplicate'. That makes this the root's own view of
    the attack - independent of the attacking boards' counters, which is what
    TunnelIntensity is built from. Not a dataset column; computed here."""
    if not {"TunnelLatency", "node_role"} <= set(df.columns):
        return df
    d = df.copy()
    is_b = d["node_role"].astype(str).str.lower() == "wormhole_b"
    dup = pd.to_numeric(d["TunnelLatency"], errors="coerce").notna().astype(float)
    d["DuplicateRate"] = dup.where(is_b, np.nan)
    return d


def _first_val(df, col):
    if col not in df.columns:
        return None
    v = df[col].dropna()
    if v.empty:
        return None
    x = v.iloc[0]
    return int(x) if isinstance(x, float) and x.is_integer() else x


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
    # Older feature tables have no exposure column; derive it so this report is
    # correct on them too rather than silently falling back to the role.
    df = _with_exposure(df)
    lab = df["Label"] if "Label" in df.columns else df.get("window_label")
    if lab is None:
        return

    base = df[lab == LABEL_BASELINE]
    atk = df[lab == label]
    if atk.empty:
        return

    # One row per (node, hop): a node that moved mid-run (mobility, or a tree
    # re-shuffle) shows each position it held. The summary below counts NODES.
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
        print("     no per-node PDR in this table (no plain child with delivery data)")
        print()
        return

    rows.sort(key=lambda t: t[2])   # worst-hit node first
    hdr = "     {:<20}{:<11}{:<12}{:>5}{:>11}{:>11}{:>7}".format(
        "node_id", "built as", "exposure", "hop", "baseline", "attack", "n")
    print(hdr)
    print("     " + "-" * (RULE_W - 5))
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
        exp_s = EXPOSURE_LABEL.get(str(exp), str(exp))
        print("     {:<20}{:<11}{:<12}{:>5}{:>11}{:>11}{:>7}".format(
            str(node), str(role), exp_s, hop_s, b_s, f"{amean:.4f}", n))

    ei = names.get("exposure")
    def exposure_of(r):
        return str(r[0][ei]) if ei is not None and ei < len(r[0]) else "unknown"

    def distinct(rs):
        """One entry per node - a node that changed hop has several rows."""
        seen, out = set(), []
        for r in rs:
            if r[0][0] not in seen:
                seen.add(r[0][0])
                out.append(r)
        return out

    victim_rows = [r for r in rows if exposure_of(r) == "downstream"]
    victims = distinct(victim_rows)
    bystanders = distinct([r for r in rows if exposure_of(r) == "upstream"])
    print()
    if victims:
        worst = min(r[2] for r in victim_rows)
        print("     ** {} VICTIM(S) - the attacker sits on their path to the root. "
              "Worst attack PDR {:.4f}.".format(len(victims), worst))
        print("        " + ", ".join(str(r[0][0]) for r in victims))
        print("        This is the population the write-up should quote. The pooled "
              "PDR above averages")
        print("        victims with bystanders and describes no actual node.")
    if bystanders:
        print("     ** {} node(s) were NOT in the attack path (built as children, "
              "never exposed):".format(len(bystanders)))
        print("        " + ", ".join(str(r[0][0]) for r in bystanders))
        print("        They sit ABOVE the attacker, so their traffic never transits "
              "it. Unaffected BY")
        print("        CONSTRUCTION - not evidence the attack was weak, and not "
              "victims.")
    if not victims and bystanders:
        print("     !! No node was downstream of the attacker in this run, so the "
              "capture cannot")
        print("        show a blackhole effect at all. Re-place the attacker and "
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
    setup_fail = False
    colour = sys.stdout.isatty() and not os.environ.get("NO_COLOR")
    for atk in attacks:
        if colour:
            buf = io.StringIO()
            with contextlib.redirect_stdout(buf):
                confirmed, conclusive = verify(df, atk, args.sigma, args.block)
            _print_coloured(buf.getvalue())
        else:
            confirmed, conclusive = verify(df, atk, args.sigma, args.block)
        any_conclusive = any_conclusive or conclusive
        all_confirmed = all_confirmed and confirmed
        setup_fail = setup_fail or _LAST_SETUP_INVALID[0]

    print()
    # Exit 3 = signatures passed but the attack setup was invalid (analyze.ps1
    # shows 'SETUP INVALID'); 1 = not confirmed / inconclusive; 0 = confirmed.
    if any_conclusive and all_confirmed:
        sys.exit(0)
    sys.exit(3 if setup_fail else 1)


if __name__ == "__main__":
    main()

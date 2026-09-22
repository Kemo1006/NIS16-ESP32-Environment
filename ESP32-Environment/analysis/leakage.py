#!/usr/bin/env python3
"""
leakage.py - Which columns may enter a clustering/ML model, and why not the rest.

WHY THIS FILE EXISTS
--------------------
CTTHES2 panel, 2:40-4:50:

    "if a single feature determines whether an instance is an attack, it could
     invalidate the clustering process. If only one indicator exists [...] then
     the remaining fifteen features become irrelevant. In such a case, machine
     learning would be unnecessary."

The objection is CORRECT for the dataset as captured. Measured on
blackhole/linear/G402 (2026-09-20):

  * ForwardingRatio alone separates attack from benign at 0.9694 accuracy
    against a 0.7685 majority-class baseline.
  * "Is ForwardingRatio NaN?" is by itself a near-perfect label at
    dataset-assembly level, because the column is only ever populated for one
    node role.
  * window_start alone scores 0.857, purely because every run uses the same
    fixed phase schedule (60/300/180/120 s).

So the fix is not to argue with the panel. It is to declare, in one place that
every analysis imports, which columns are legitimate model inputs and which are
label equivalents -- and to report the before/after numbers as a result.

This implements OPTION 3 of Plan/THESIS3-MEMBER-HOWTO.md section 1, C7
("redefine the feature honestly"): keep the role-gated features, report them as
attacker-side DIAGNOSTICS, and keep them out of any unsupervised model input.
Quoting that plan: "If those columns only ever exist for the attacker, using
them as model features IS the leakage. Removing them is a real fix, not a
retreat."

UPDATE 2026-09-21: OPTION 1 HAS NOW LANDED in firmware (see thesis-deviate D-12
and components/mesh_common/src/probe_relay.c). Every node relays at the
application layer and reports real recv/forward/drop, so on captures taken with
that firmware the three relay features are NO LONGER role-gated.

Rather than delete those entries, the decision is now made PER DATASET by
relay_features_are_gated() below: it asks how many node_roles actually carry
values for the column. Pre-C7 captures still exclude them (they really are
single-role); post-C7 captures allow them (the attacker is an outlier in a
populated distribution instead of the only value present). Both kinds of capture
will coexist in this project for months, so hardcoding either answer would be
wrong for half the data.

The before/after delta in single-feature accuracy across those two firmwares is
deliverable E2 -- the evidence that the panel's objection was fixed, not argued
with.

WHAT THIS FILE DOES NOT DO
--------------------------
It does not delete anything. Excluded columns stay in feature_table.csv and
stay available for the diagnostic reporting the paper still needs (the
attacker's own forward/drop record is the proof the manipulation ran). This
module only decides what a MODEL is allowed to see.

NIS16 -- CTTHES2/CTTHES3 -- host-side leakage guard
"""

from __future__ import annotations

import numpy as np
import pandas as pd

# The 16 Table 4.11 feature names, in the order the thesis presents them.
# Duplicated from eda.py deliberately: eda.py imports this module, not the
# reverse, so this is the definition and eda.py's is the alias.
TABLE_4_11_FEATURES = [
    "ForwardingRatio", "IngressEgressDelta", "RetryRate", "PDR",
    "ParentSwitchRate", "HopChangeCount", "HopStabilityDuration",
    "RSSI_mean", "RSSI_var", "RSSI_stability",
    "RSSI_Hop_Diff", "LatencyHopRatio", "ConsistencyScore",
    "TunnelIntensity", "TunnelBytes", "TunnelLatency",
]

# ---------------------------------------------------------------------------
# The exclusion list. Every entry carries the reason it is excluded, because a
# panel WILL ask "why is this one out and that one in", and an undocumented
# exclusion list is indistinguishable from cherry-picking.
# ---------------------------------------------------------------------------

LEAKING_COLUMNS: dict[str, str] = {
    # --- Role-gated relay features: defined ONLY on the blackhole attacker ---
    "ForwardingRatio": (
        "Role-gated: computed only for node_role == blackhole "
        "(features.py compute_forwarding_features). Honest nodes send with "
        "MESH_DATA_TODS, so the mesh stack relays below the application layer "
        "and no honest node can observe its own forwarding (verified against "
        "the firmware 2026-08-29). The column is therefore NaN for every node "
        "but the attacker, which makes is-this-NaN a label. Measured "
        "single-feature accuracy 0.9694 vs 0.7685 majority."
    ),
    "ConsistencyScore": (
        "Not an independent measurement: identically equal to "
        "abs(ForwardingRatio - 1) to 1.1e-16 on the real capture. Same role "
        "gate, same leak, no added information."
    ),
    "IngressEgressDelta": (
        "Not an independent measurement: equals recv_count * abs(1 - "
        "ForwardingRatio). Same role gate, same leak."
    ),

    # --- The MAC-layer feature that is actually the attack's own switch ---
    "RetryRate": (
        "Derived from retry_count, which blackhole_victim.c OVERLOADS as the "
        "attacker's own DROP counter. On the attacker it goes 0.0033 to 0.9991 "
        "across the attack window while victims go 0.0008 to 0.0000. It is the "
        "manipulation's own control variable wearing a MAC-layer name, not an "
        "802.11 retransmission count. See docs/DATA-DICTIONARY.md. Excluded "
        "until F3 gives every node a dedicated drop_count and retry_count can "
        "mean one thing."
    ),

    # --- Role-gated tunnel features: defined ONLY on wormhole endpoints ---
    "TunnelIntensity": (
        "Role-gated to node_role in (wormhole_a, wormhole_b); NaN everywhere "
        "else, so presence alone identifies the run type. Section 4.2.5.1 "
        "already permits excluding the auxiliary tunnel features before "
        "normalization -- this makes that mandatory rather than optional."
    ),
    "TunnelBytes": "Role-gated to wormhole endpoints -- see TunnelIntensity.",
    "TunnelLatency": "Role-gated to wormhole endpoints -- see TunnelIntensity.",
}

# Identity / provenance / schedule columns. These are not features at all, but
# they sit in the same table and a careless select_dtypes(number) sweeps some
# of them straight into a model.
METADATA_COLUMNS: dict[str, str] = {
    "attack_type": "Plain-text label equivalent (combine_all.py ships it verbatim).",
    "attack": "Plain-text label equivalent.",
    "exposure": (
        "Derived from the topology: 'downstream' means the attacker sits on "
        "this node's path to the root. Inside an attack window that IS very "
        "nearly the label, for the same reason node_role is."
    ),
    "node_role": (
        "Plain-text role, and role is what gates the leaking features above. "
        "The value blackhole in this column IS the answer."
    ),
    "Label": "The ground-truth label itself.",
    "window_label": "The ground-truth label itself.",
    "window_phase_id": "The phase id the label is derived from.",
    "phase_id": "The phase id the label is derived from.",
    "segment": "Derived from the phase schedule; names the attack window.",
    "window_start": (
        "Run-clock position. Every run uses the same fixed schedule "
        "(PHASE_STABILISE_S 60 / BASELINE 300 / ATTACK 180 / COOLDOWN 120), so "
        "elapsed time alone scores 0.857 accuracy. It is a clock, not a "
        "network measurement. This is exactly the panel 12:45-16:00 point "
        "about runs being identical."
    ),
    "t_anchor_s": "Run-clock position -- see window_start.",
    "node_id": "Board identity; the attacker board is a fixed MAC.",
    "source_file": "Filename; encodes role and run.",
    "parent_mac": "Board identity of the parent.",
    "topology": "Run provenance.",
    "location": "Run provenance.",
    "scenario": "Run provenance.",
    "run_repeat": "Run provenance.",
    "_pdr_clipped": "Internal diagnostic flag.",
    "missing_firmware_fields": "Internal diagnostic flag.",
}


# Columns excluded ONLY because one firmware generation could not measure them
# on honest nodes. C7 Option 1 changed that, so whether they leak is now a
# property OF THE DATA, not a fact about the project — and must be decided per
# dataset rather than hardcoded.
_RELAY_GATED_BEFORE_C7 = ("ForwardingRatio", "IngressEgressDelta", "ConsistencyScore")

# A column counts as genuinely multi-role once this many distinct node_roles
# carry values for it. Two is enough: the whole defect was "exactly one role has
# this column", so any second role breaks the is-it-NaN-identifies-the-attacker
# shortcut.
_MIN_ROLES_TO_CLEAR = 2


def relay_features_are_gated(df: pd.DataFrame) -> bool:
    """Do the relay features still exist on only ONE node role in THIS dataset?

    WHY THIS IS MEASURED, NOT ASSUMED
    ---------------------------------
    Before C7 Option 1, honest nodes sent with MESH_DATA_TODS: the mesh stack
    relayed below the application layer, so no honest node could observe its own
    forwarding and ForwardingRatio existed only on the blackhole attacker. "Is
    this column NaN?" therefore identified the attacker, which is leakage.

    After C7 Option 1 every node relays explicitly and reports real
    recv/forward/drop, so the column is populated across many roles and the
    shortcut is gone — the attacker becomes an OUTLIER in a real distribution
    instead of the only value present.

    Both kinds of capture will coexist in this project for a while, so hardcoding
    either answer would be wrong for half the data. This asks the dataset.

    Returns True when the features are still single-role (exclude them), False
    when several roles carry them (they are legitimate model inputs).
    """
    if "node_role" not in df.columns:
        return True     # cannot tell -> assume the unsafe case
    for col in _RELAY_GATED_BEFORE_C7:
        if col in df.columns:
            roles = df.loc[df[col].notna(), "node_role"].nunique()
            if roles >= _MIN_ROLES_TO_CLEAR:
                return False
    return True


def leaking_columns_for(df: pd.DataFrame) -> dict[str, str]:
    """LEAKING_COLUMNS adjusted for what this particular dataset can support."""
    out = dict(LEAKING_COLUMNS)
    if not relay_features_are_gated(df):
        for col in _RELAY_GATED_BEFORE_C7:
            out.pop(col, None)
    return out


def model_feature_allowlist(features: list[str] | None = None) -> list[str]:
    """The Table 4.11 features a clustering model is allowed to see."""
    source = TABLE_4_11_FEATURES if features is None else features
    return [c for c in source if c not in LEAKING_COLUMNS]


def split_columns(
    df: pd.DataFrame,
    candidates: list[str] | None = None,
) -> tuple[list[str], dict[str, str]]:
    """
    Split the candidate feature columns of df into (allowed, excluded).

    excluded maps column name -> the reason string, so every caller can print
    its own exclusions instead of silently dropping them.
    """
    source = TABLE_4_11_FEATURES if candidates is None else candidates
    present = [c for c in source if c in df.columns]

    leaking = leaking_columns_for(df)
    allowed, excluded = [], {}
    for col in present:
        reason = leaking.get(col) or METADATA_COLUMNS.get(col)
        if reason:
            excluded[col] = reason
        else:
            allowed.append(col)
    return allowed, excluded


def format_exclusions(excluded: dict[str, str], indent: str = "    ") -> str:
    """Render the exclusion map for a console report or a figure caption."""
    if not excluded:
        return indent + "(none)"
    lines = []
    for col, reason in excluded.items():
        lines.append(indent + col)
        # Wrap the reason to keep the console readable at 100 cols.
        words, line = reason.split(), ""
        for w in words:
            if len(line) + len(w) + 1 > 84:
                lines.append(indent + "    " + line)
                line = w
            else:
                line = (line + " " + w).strip()
        if line:
            lines.append(indent + "    " + line)
    return "\n".join(lines)


# ---------------------------------------------------------------------------
# Single-feature decidability audit -- the number the panel actually asked for
# ---------------------------------------------------------------------------

def single_feature_decidability(
    df: pd.DataFrame,
    label_col: str = "window_label",
    candidates: list[str] | None = None,
) -> pd.DataFrame:
    """
    For each candidate column, the best accuracy obtainable by ONE threshold on
    that column alone, next to the majority-class baseline.

    This is deliberately the crudest possible classifier: a single split point,
    chosen with full sight of the labels. That is the point. If a one-threshold
    rule on one column already reproduces the label, the panel's objection
    stands for that column and no amount of clustering sophistication repairs
    it. A column scoring at or near the majority baseline is carrying real,
    non-trivial signal.

    Also reports nan_accuracy: how well "is this value missing?" alone predicts
    the label. A high value there means the column's PRESENCE is the leak,
    which no threshold rule would reveal.

    Returns a DataFrame sorted worst-offender first. NaN-only columns are
    skipped (nothing to threshold).
    """
    if label_col not in df.columns:
        raise KeyError("label column " + repr(label_col) + " not in the feature table")

    source = TABLE_4_11_FEATURES if candidates is None else candidates
    present = [c for c in source if c in df.columns]

    leaking = leaking_columns_for(df)
    labels = df[label_col]
    labelled = labels.notna()
    if not labelled.any():
        raise ValueError(label_col + " is entirely NaN -- nothing to audit")

    y_all = (labels[labelled] > 0).to_numpy()
    majority = max(y_all.mean(), 1.0 - y_all.mean())

    rows = []
    for col in present:
        series = df.loc[labelled, col]

        # "Is it missing?" as a classifier, evaluated before dropping NaNs.
        is_nan = series.isna().to_numpy()
        if is_nan.any() and not is_nan.all():
            nan_acc = max((is_nan == y_all).mean(), (is_nan != y_all).mean())
        else:
            nan_acc = float("nan")

        usable = series.notna().to_numpy()
        if usable.sum() < 2:
            rows.append({
                "feature": col, "threshold_accuracy": float("nan"),
                "nan_accuracy": nan_acc, "coverage": float(usable.mean()),
                "excluded": col in leaking,
            })
            continue

        x = series[usable].to_numpy(dtype=float)
        y = y_all[usable]

        # Best single threshold: sweep the midpoints between sorted unique
        # values. Capped at 256 candidate splits -- the accuracy surface of a
        # one-dimensional threshold rule is piecewise constant, so a denser
        # sweep cannot find a materially better split, and this keeps the audit
        # cheap enough to run on every analysis pass.
        uniq = np.unique(x)
        if uniq.size < 2:
            best = max(y.mean(), 1.0 - y.mean())
        else:
            if uniq.size > 257:
                uniq = np.unique(np.quantile(uniq, np.linspace(0, 1, 257)))
            cuts = (uniq[:-1] + uniq[1:]) / 2.0
            best = 0.0
            for cut in cuts:
                pred = x > cut
                acc = max((pred == y).mean(), (pred != y).mean())
                if acc > best:
                    best = acc

        rows.append({
            "feature": col, "threshold_accuracy": best,
            "nan_accuracy": nan_acc, "coverage": float(usable.mean()),
            "excluded": col in leaking,
        })

    out = pd.DataFrame(rows)
    out["majority_baseline"] = majority
    out["lift_over_majority"] = out["threshold_accuracy"] - majority
    return out.sort_values("threshold_accuracy", ascending=False,
                           na_position="last").reset_index(drop=True)


def print_decidability_report(audit: pd.DataFrame, title: str = "") -> None:
    """Console rendering of single_feature_decidability()."""
    majority = audit["majority_baseline"].iloc[0] if len(audit) else float("nan")
    suffix = (" - " + title) if title else ""
    print()
    print("=== Single-feature decidability audit" + suffix)
    print("    Majority-class baseline: {:.4f}".format(majority))
    print("    (accuracy of ONE threshold on ONE column, labels visible)")
    print()
    print("    {:<22}{:>8}{:>8}{:>9}{:>8}  {}".format(
        "feature", "thresh", "lift", "nan-acc", "cover", "status"))
    print("    " + "-" * 22 + "-" * 8 + "-" * 8 + "-" * 9 + "-" * 8 + "  " + "-" * 11)
    for _, r in audit.iterrows():
        thresh = "     n/a" if pd.isna(r["threshold_accuracy"]) else "{:8.4f}".format(r["threshold_accuracy"])
        lift = "     n/a" if pd.isna(r["lift_over_majority"]) else "{:+8.4f}".format(r["lift_over_majority"])
        nan_acc = "      n/a" if pd.isna(r["nan_accuracy"]) else "{:9.4f}".format(r["nan_accuracy"])
        status = "EXCLUDED" if r["excluded"] else "model input"
        print("    {:<22}{}{}{}{:8.2f}  {}".format(
            r["feature"], thresh, lift, nan_acc, r["coverage"], status))
    print()

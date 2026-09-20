#!/usr/bin/env python3
"""
test_segments.py - Regression tests for preprocess.assign_segments().

Run: python test_segments.py          (no pytest needed - this box has none)

These cover the one function whose failure mode is silent and expensive: it
decides which rows count as "normal network behaviour", and a wrong answer
there does not crash anything, it just quietly poisons the reference
distribution that every 3-sigma verdict is measured against. That is exactly
what happened on 2026-09-18 (see mesh_config.h PHASE_ID_UNSET).

Two schemas must both work, forever:
  v1 - phase 0 means three different things (real baseline / stabilisation /
       "no broadcast heard yet"). Separated by inference from the phase exit.
  v2 - the firmware records PHASE_ID_UNSET for the third case (F1).

NIS16 - CTTHES2/CTTHES3
"""

import sys

import numpy as np
import pandas as pd

import preprocess
from preprocess import (
    GT_LABEL_UNSET,
    PHASE_ID_UNSET,
    SEGMENT_ATTACK,
    SEGMENT_BASELINE,
    SEGMENT_COOLDOWN,
    SEGMENT_PRE_BASELINE,
    assign_segments,
)

_FAILURES = []


def check(name, condition, detail=""):
    if condition:
        print(f"  PASS  {name}")
    else:
        print(f"  FAIL  {name}  {detail}")
        _FAILURES.append(name)


def _frame(phases, node="NODE_TEST", src="test_telem.csv"):
    """One window per second, phase ids given, labels derived like the firmware."""
    label_of = {0: 0, 1: 1, 2: 2, 3: 0, PHASE_ID_UNSET: GT_LABEL_UNSET}
    return pd.DataFrame({
        "node_id": node,
        "source_file": src,
        "window_start": np.arange(len(phases), dtype=float),
        "window_phase_id": phases,
        "window_label": [label_of[p] for p in phases],
    })


class _Report:
    """Minimal stand-in for PreprocessReport - only the field used here."""
    def __init__(self):
        self.nodes_without_phase_exit = []
        self.segment_counts = {}


# ---------------------------------------------------------------------------
# v1: phase 0 overloaded. 400 s of phase 0, then attack, then cooldown.
# The last PHASE_BASELINE_S (300) before the exit is the real baseline; the
# first 100 s is pre-root contamination and must be excluded.
# ---------------------------------------------------------------------------
def test_v1_splits_overloaded_phase_zero():
    print("\nv1 - phase 0 overloaded (inference path)")
    phases = [0] * 400 + [1] * 180 + [3] * 120
    out = assign_segments(_frame(phases), _Report())
    counts = out["segment"].value_counts().to_dict()

    check("first 100 s of phase 0 -> pre_baseline",
          counts.get(SEGMENT_PRE_BASELINE) == 100, counts)
    check("last 300 s of phase 0 -> baseline",
          counts.get(SEGMENT_BASELINE) == 300, counts)
    check("phase 1 -> attack", counts.get(SEGMENT_ATTACK) == 180, counts)
    check("phase 3 -> cooldown", counts.get(SEGMENT_COOLDOWN) == 120, counts)
    check("anchor is the phase exit (t=0 at window 400)",
          float(out.loc[out["window_start"] == 400.0, "t_anchor_s"].iloc[0]) == 0.0)
    check("pre_baseline rows have no label",
          out.loc[out["segment"] == SEGMENT_PRE_BASELINE, "window_label"].isna().all())
    check("attack rows keep label 1",
          (out.loc[out["segment"] == SEGMENT_ATTACK, "window_label"] == 1).all())


# ---------------------------------------------------------------------------
# v2: the same run, but the board recorded the pre-root window as UNSET.
# The segment breakdown must come out IDENTICAL to v1 - that equivalence is
# what makes captures from the two firmwares comparable.
# ---------------------------------------------------------------------------
def test_v2_unset_matches_v1():
    print("\nv2 - PHASE_ID_UNSET recorded (F1 path)")
    v1 = assign_segments(_frame([0] * 400 + [1] * 180 + [3] * 120), _Report())
    v2 = assign_segments(
        _frame([PHASE_ID_UNSET] * 100 + [0] * 300 + [1] * 180 + [3] * 120),
        _Report())

    check("v2 segments identical to v1",
          v1["segment"].tolist() == v2["segment"].tolist(),
          f"v1={v1['segment'].value_counts().to_dict()} "
          f"v2={v2['segment'].value_counts().to_dict()}")
    check("v2 anchor still the real phase exit, not the UNSET->0 transition",
          float(v2.loc[v2["window_start"] == 400.0, "t_anchor_s"].iloc[0]) == 0.0,
          "UNSET must not count as leaving phase 0")
    check("no GT_LABEL_UNSET survives as a class",
          not (pd.to_numeric(v2["window_label"], errors="coerce")
               == GT_LABEL_UNSET).any())


# ---------------------------------------------------------------------------
# The regression that motivated F1: a node whose ENTIRE phase-0 period is
# pre-root. Under the old initialiser every one of those rows was labelled
# baseline (class 0) and pooled into the reference distribution.
# ---------------------------------------------------------------------------
def test_unset_never_becomes_baseline():
    print("\nregression - a long pre-root window must never read as baseline")
    # 900 s unset (root brownout-looping), then a normal run.
    phases = [PHASE_ID_UNSET] * 900 + [0] * 300 + [1] * 180 + [3] * 120
    out = assign_segments(_frame(phases), _Report())
    unset_rows = out.iloc[:900]

    check("all 900 unset windows -> pre_baseline",
          (unset_rows["segment"] == SEGMENT_PRE_BASELINE).all(),
          unset_rows["segment"].value_counts().to_dict())
    check("none of them carry a label",
          unset_rows["window_label"].isna().all())
    check("baseline population is exactly the 300 real seconds",
          int((out["segment"] == SEGMENT_BASELINE).sum()) == 300)


# ---------------------------------------------------------------------------
# A node that boots, hears nothing, and is powered off. It has no phase exit,
# so it must contribute NOTHING to either class rather than defaulting to one.
# ---------------------------------------------------------------------------
def test_node_that_never_hears_a_broadcast():
    print("\nedge - node that never hears a broadcast")
    rep = _Report()
    out = assign_segments(_frame([PHASE_ID_UNSET] * 500), rep)

    check("no window is labelled", out["window_label"].isna().all())
    check("node reported as having no phase exit",
          len(rep.nodes_without_phase_exit) == 1,
          rep.nodes_without_phase_exit)
    check("nothing counted as baseline",
          int((out["segment"] == SEGMENT_BASELINE).sum()) == 0)


# ---------------------------------------------------------------------------
# Per-node anchoring: two nodes that booted at different times must each be
# anchored on their OWN phase exit. Boards never share a clock.
# ---------------------------------------------------------------------------
def test_per_node_anchor():
    print("\nmulti-node - each node anchors on its own phase exit")
    early = _frame([0] * 500 + [1] * 180, node="NODE_EARLY", src="early_telem.csv")
    late = _frame([0] * 320 + [1] * 180, node="NODE_LATE", src="late_telem.csv")
    out = assign_segments(pd.concat([early, late], ignore_index=True), _Report())

    per_node = out.groupby("node_id")["segment"].value_counts().unstack(fill_value=0)
    check("early node: 200 pre_baseline + 300 baseline",
          per_node.loc["NODE_EARLY", SEGMENT_PRE_BASELINE] == 200
          and per_node.loc["NODE_EARLY", SEGMENT_BASELINE] == 300,
          per_node.loc["NODE_EARLY"].to_dict())
    check("late node: 20 pre_baseline + 300 baseline",
          per_node.loc["NODE_LATE", SEGMENT_PRE_BASELINE] == 20
          and per_node.loc["NODE_LATE", SEGMENT_BASELINE] == 300,
          per_node.loc["NODE_LATE"].to_dict())


def main():
    print(f"assign_segments regression tests "
          f"(PHASE_BASELINE_S={preprocess.PHASE_BASELINE_S})")
    test_v1_splits_overloaded_phase_zero()
    test_v2_unset_matches_v1()
    test_unset_never_becomes_baseline()
    test_node_that_never_hears_a_broadcast()
    test_per_node_anchor()

    print()
    if _FAILURES:
        print(f"{len(_FAILURES)} FAILURE(S): {', '.join(_FAILURES)}")
        return 1
    print("all checks passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())

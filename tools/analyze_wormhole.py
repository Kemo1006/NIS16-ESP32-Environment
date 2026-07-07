#!/usr/bin/env python3
"""
analyze_wormhole.py — verify the wormhole signature in a root arrivals.csv.

Milestone-2 wormhole criterion: "root logs show duplicate probe arrivals with a
measurable latency difference during the attack window." This script proves it
directly from the root's probe-arrival log:

  * During the wormhole phase (phase_id == 2), each victim probe should reach
    root TWICE — once via the slow legitimate multi-hop path and once via the
    fast wormhole shortcut (Attacker B --UART--> Attacker A --> root). The two
    copies share (src_mac, seq_num) but differ in latency_us.
  * Baseline / cooldown windows should show NO duplicates (no leakage).

Usage
-----
    python analyze_wormhole.py --dir exports --topology tree --repeat 1
    python analyze_wormhole.py --file root_..._wormhole_r1_..._arrivals.csv

Standard library only.

NIS16 — CTTHES2 Milestone 2 / 4
"""

import argparse
import csv
import glob
import os
import statistics
import sys
from collections import defaultdict

PHASE_BASELINE = 0
PHASE_WORMHOLE = 2
PHASE_COOLDOWN = 3


def load_arrivals(path):
    rows = []
    with open(path, newline="", encoding="utf-8") as f:
        for row in csv.DictReader(f):
            try:
                rows.append({
                    "phase": int(row["phase_id"]),
                    "src": row["src_mac"],
                    "seq": int(row["seq_num"]),
                    "lat": int(row["latency_us"]),
                    "ts": int(row["timestamp_us"]),
                })
            except (KeyError, ValueError):
                continue
    return rows


def duplicates_in_phase(rows, phase):
    groups = defaultdict(list)
    for r in rows:
        if r["phase"] == phase:
            groups[(r["src"], r["seq"])].append(r)
    dups = {k: v for k, v in groups.items() if len(v) >= 2}
    return groups, dups


def resolve_file(args):
    if args.file:
        return args.file
    pattern = os.path.join(
        args.dir, f"root_*_{args.topology}_*_r{args.repeat}_*_arrivals.csv"
    )
    matches = sorted(glob.glob(pattern))
    if not matches:
        return None
    if len(matches) > 1:
        print(f"(!) Multiple matches; using newest:\n    {os.path.basename(matches[-1])}")
    return matches[-1]


def main():
    ap = argparse.ArgumentParser(description="Verify the wormhole arrival signature.")
    ap.add_argument("--dir", default="exports")
    ap.add_argument("--topology", default="tree")
    ap.add_argument("--repeat", default="1")
    ap.add_argument("--file", help="Explicit root arrivals.csv (overrides filters).")
    args = ap.parse_args()

    path = resolve_file(args)
    if not path or not os.path.exists(path):
        print("No root arrivals.csv found — pass --file or check --dir/--topology/--repeat.",
              file=sys.stderr)
        return 2

    print(f"Analyzing: {os.path.basename(path)}\n")
    rows = load_arrivals(path)
    if not rows:
        print("No arrival rows parsed.", file=sys.stderr)
        return 2

    # ── Wormhole window ─────────────────────────────────────────────────────
    wh_groups, wh_dups = duplicates_in_phase(rows, PHASE_WORMHOLE)
    n_wh = sum(len(v) for v in wh_groups.values())
    print("=== Wormhole phase (phase_id=2) ===")
    print(f"  Distinct probes (src,seq) : {len(wh_groups)}")
    print(f"  Total arrivals            : {n_wh}")
    print(f"  Duplicated probes         : {len(wh_dups)}")

    mismatches = []
    for _, arrivals in wh_dups.items():
        lats = sorted(a["lat"] for a in arrivals)
        mismatches.append(lats[-1] - lats[0])   # slow - fast, microseconds

    if mismatches:
        print(f"  Latency mismatch (us)     : "
              f"min={min(mismatches)}  median={int(statistics.median(mismatches))}  "
              f"max={max(mismatches)}")
        # Show a few examples.
        print("  Examples (src, seq -> latencies us):")
        for key, arrivals in list(sorted(wh_dups.items()))[:5]:
            lats = sorted(a["lat"] for a in arrivals)
            print(f"    {key[0]} seq={key[1]:>4} -> {lats}  (Δ={lats[-1]-lats[0]} us)")
    print()

    # ── Baseline leakage check ──────────────────────────────────────────────
    _, base_dups = duplicates_in_phase(rows, PHASE_BASELINE)
    _, cool_dups = duplicates_in_phase(rows, PHASE_COOLDOWN)
    print("=== Leakage check (should be ~0 duplicates) ===")
    print(f"  Baseline duplicates : {len(base_dups)}")
    print(f"  Cooldown duplicates : {len(cool_dups)}")
    print()

    # ── Verdict ─────────────────────────────────────────────────────────────
    have_dupes = len(wh_dups) > 0
    have_mismatch = bool(mismatches) and max(mismatches) > 0
    clean = len(base_dups) == 0 and len(cool_dups) == 0
    print("=== Milestone-2 wormhole verdict ===")
    print(f"  Duplicate arrivals in attack window : {'YES' if have_dupes else 'NO'}")
    print(f"  Measurable latency mismatch         : {'YES' if have_mismatch else 'NO'}")
    print(f"  No leakage into baseline/cooldown   : {'YES' if clean else 'NO'}")
    ok = have_dupes and have_mismatch and clean
    print(f"  --> {'WORMHOLE SIGNATURE CONFIRMED' if ok else 'signature INCOMPLETE — see above'}")
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())

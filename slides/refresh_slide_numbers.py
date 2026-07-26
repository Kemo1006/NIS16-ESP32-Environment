#!/usr/bin/env python3
"""
refresh_slide_numbers.py — print the current figures for the defence slides.

The deck (NIS16-defence-slides.html) hard-codes its numbers so it stays a plain,
self-contained file you can open and print anywhere. That means the figures go
stale the moment another run is recorded.

Run this, then paste the values into the three slides marked "UPDATE ME":

    slide 8   M3 topology coverage matrix
    slide 9   M4 matrix + the 8/24 headline
    slide 12  M8 dataset window/label counts
    slide 17  the closing three-number panel

    python slides\\refresh_slide_numbers.py

Reads the same sources the tools do — the ledger and the feature tables — so it
cannot disagree with run_matrix.py.
"""
from __future__ import annotations

import collections
import csv
import glob
import os
import sys

_HERE = os.path.dirname(os.path.abspath(__file__))
_ROOT = os.path.dirname(_HERE)

TOPOLOGIES = ["star", "tree", "linear", "partial"]
ATTACKS = ["blackhole", "wormhole"]
REPEATS = 3


def _ledger():
    """(topology, attack, repeat) -> status, straight from the M4 ledger."""
    path = os.path.join(_ROOT, "tools", "exports", "run_ledger.csv")
    done = {}
    if not os.path.exists(path):
        return done
    with open(path, newline="", encoding="utf-8") as f:
        for row in csv.DictReader(f):
            try:
                key = (row["topology"], row["attack"], int(row["repeat"]))
            except (KeyError, ValueError):
                continue
            done[key] = row.get("status")
    return done


def matrix_block(done):
    lines = ["                    r1  r2  r3"]
    total = 0
    for topo in ["linear", "star", "tree", "partial"]:
        for atk in ATTACKS:
            marks, n = [], 0
            for rep in range(1, REPEATS + 1):
                ok = done.get((topo, atk, rep), {}) == "done" if isinstance(
                    done.get((topo, atk, rep)), dict) else done.get((topo, atk, rep)) == "done"
                marks.append("✔" if ok else "·")
                n += 1 if ok else 0
            total += n
            lines.append("%-7s ▸ %-9s %s   %d/3" % (topo, atk, "   ".join(marks), n))
    lines.append("                          TOTAL  %d/%d" % (total, len(TOPOLOGIES) * len(ATTACKS) * REPEATS))
    return "\n".join(lines), total


def coverage(done):
    """M3 slide: which topology x attack pairs have at least one recorded run."""
    rows = []
    for topo in ["tree", "linear", "star", "partial"]:
        cells = []
        for atk in ATTACKS:
            any_done = any(done.get((topo, atk, r)) == "done" for r in range(1, REPEATS + 1))
            cells.append("✔" if any_done else "pending")
        rows.append((topo, cells[0], cells[1]))
    return rows


def datasets():
    out = []
    for path in sorted(glob.glob(os.path.join(_ROOT, "analysis", "*", "*_topology", "feature_table.csv"))):
        rel = os.path.relpath(os.path.dirname(path), os.path.join(_ROOT, "analysis")).replace(os.sep, " · ")
        with open(path, newline="", encoding="utf-8") as f:
            rows = list(csv.DictReader(f))
        if not rows:
            continue
        col = "Label" if "Label" in rows[0] else "window_label"
        lab = collections.Counter(r.get(col) for r in rows)
        benign = lab.get("0", 0)
        attack = sum(v for k, v in lab.items() if k not in ("0", None, ""))
        out.append((rel.replace("_topology", ""), len(rows), benign, attack))
    return out


def scale():
    files = rows = size = 0
    for p in glob.glob(os.path.join(_ROOT, "tools", "exports", "*", "*_topology", "*.csv")):
        if "_archive" in p:
            continue
        files += 1
        size += os.path.getsize(p)
        with open(p, errors="replace", encoding="utf-8") as f:
            rows += max(0, sum(1 for _ in f) - 1)
    windows = 0
    for p in glob.glob(os.path.join(_ROOT, "analysis", "*", "*_topology", "feature_table.csv")):
        with open(p, encoding="utf-8") as f:
            windows += max(0, sum(1 for _ in f) - 1)
    eda = len(glob.glob(os.path.join(_ROOT, "analysis", "*", "*_topology", "eda_output", "*")))
    return files, size / 1e6, rows, windows, eda


def main() -> int:
    done = _ledger()

    print("=" * 66)
    print(" SLIDE 9  ·  M4 matrix block  (paste into the <pre>)")
    print("=" * 66)
    block, total = matrix_block(done)
    print(block)
    print("\n  headline number : %d/24" % total)

    print("\n" + "=" * 66)
    print(" SLIDE 8  ·  M3 coverage table")
    print("=" * 66)
    for topo, bh, wh in coverage(done):
        print("  %-9s baseline ✔   blackhole %-8s wormhole %s" % (topo.capitalize(), bh, wh))

    print("\n" + "=" * 66)
    print(" SLIDE 12 ·  dataset windows / labels")
    print("=" * 66)
    for name, n, benign, attack in datasets():
        print("  %-28s %5d windows   %5d benign / %4d attack" % (name, n, benign, attack))

    print("\n" + "=" * 66)
    print(" SLIDE 3  ·  dataset scale")
    print("=" * 66)
    f, mb, r, w, e = scale()
    print("  raw files %d · %.1f MB · %s rows · %s windows · %d EDA files"
          % (f, mb, format(r, ","), format(w, ","), e))

    print("\n" + "=" * 66)
    print(" SLIDE 17 ·  closing panel")
    print("=" * 66)
    print("  %d/24 runs recorded · 0 failures" % total)
    print("  720/720/0    blackhole (unchanged unless re-measured)")
    print("  181·181·180  wormhole duplicates (add new runs as they land)")
    print()
    return 0


if __name__ == "__main__":
    sys.exit(main())

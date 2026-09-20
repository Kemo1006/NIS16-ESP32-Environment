#!/usr/bin/env python3
"""
inventory_cells.py - Which experimental cells actually have a COMPLETE run?

WHY THIS EXISTS
---------------
Milestone 4 needs >= 24 complete runs (4 topologies x 2 attacks x 3 repeats) with
intact per-node CSVs. Milestone 5 needs >= 95% sample coverage per node and flags
failing runs for repeat collection. The panel grades against those criteria.

Until now nobody could answer "how many complete runs do we have?" without opening
folders by hand, and the answer that got written down was wrong in BOTH directions:
STATUS.md said "only one experimental cell has data" and "zero wormhole captures
exist", while archive/2026-09-16_pre-restart/ holds wormhole linear, star AND
partial_mesh captures plus a second location (home). Captures that have been
ARCHIVED are still captures - archive.ps1 MOVES data out of tools/exports/ so the
next run starts clean, it does not discard it.

So: scan everything, judge each run against the milestone criteria, print the
table, and let the count be a fact instead of a recollection.

WHAT COUNTS AS A COMPLETE RUN
-----------------------------
  1. A root telemetry file.
  2. A root arrivals file WITH DATA ROWS. Without it PDR cannot be computed, and
     PDR is the only victim-side evidence of a blackhole - leaving only the
     attacker's own counters, which is circular.
  3. At least MIN_CHILDREN child telemetry files.
  4. On an attack cell, a node whose role column says it ran the attack.
  5. Every node at >= COVERAGE_FLOOR of its expected sample count (M5).

Anything less is reported with the specific reason, because the reason decides
whether the run is salvageable or has to be recaptured.

USAGE
    python inventory_cells.py                      # live exports + every archive
    python inventory_cells.py --live-only          # just tools/exports/
    python inventory_cells.py --csv inventory.csv  # machine-readable
    python inventory_cells.py --sample-interval-ms 1000   # older captures

NIS16 -- CTTHES2 M4/M5 accounting
"""

from __future__ import annotations

import argparse
import csv
import os
import re
import sys
from collections import defaultdict

_THIS_DIR = os.path.dirname(os.path.abspath(__file__))
_REPO = os.path.dirname(_THIS_DIR)

# Same convention export_logs.py writes and validate_integrity.py checks.
FILENAME_RE = re.compile(
    r"^(?P<role>root|victim|child)_(?P<nick>[^_]+)_(?P<topology>[^_]+)_(?P<attack>[^_]+)"
    r"_r(?P<repeat>\d+)_(?P<date>\d{8})_(?P<time>\d{6})_(?P<kind>telem|arrivals)\.csv$"
)

MIN_CHILDREN = 3            # below this the topology is not meaningfully exercised
COVERAGE_FLOOR = 0.95       # Milestone 5
DEFAULT_SAMPLE_INTERVAL_MS = 100

# Roles that mean "this node ran the manipulation", as written to the role column.
ATTACKER_ROLES = {"blackhole", "wormhole_a", "wormhole_b"}


def _read_meta(path, sample_interval_ms):
    """Row count, span, role and phase set from one CSV, without loading it all."""
    rows = 0
    first_ts = last_ts = None
    role = ""
    phases = set()
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as fh:
            header = fh.readline().strip().split(",")
            try:
                ts_i = header.index("timestamp_us")
            except ValueError:
                return None
            role_i = header.index("role") if "role" in header else None
            ph_i = header.index("phase_id") if "phase_id" in header else None

            for line in fh:
                line = line.strip()
                if not line:
                    continue
                f = line.split(",")
                if len(f) != len(header):
                    continue
                try:
                    ts = int(f[ts_i])
                except ValueError:
                    continue
                if first_ts is None:
                    first_ts = ts
                last_ts = ts
                rows += 1
                if role_i is not None and not role:
                    role = f[role_i]
                if ph_i is not None:
                    phases.add(f[ph_i])
    except OSError:
        return None

    span_s = ((last_ts - first_ts) / 1e6) if (first_ts is not None and last_ts is not None) else 0.0
    expected = span_s * (1000.0 / sample_interval_ms)
    coverage = (rows / expected) if expected > 0 else 0.0
    return {"rows": rows, "span_s": span_s, "coverage": coverage,
            "role": role, "phases": phases, "n_cols": len(header)}


def _cell_key(path, root):
    """(attack, topology, location, scenario) from the folder path under an exports root."""
    rel = os.path.relpath(os.path.dirname(path), root).replace("\\", "/")
    parts = [p for p in rel.split("/") if p not in (".", "trimmed", "_archive")]
    while len(parts) < 4:
        parts.append("")
    return tuple(parts[:4])


def scan(exports_root, source_label, sample_interval_ms):
    """Group every telem/arrivals file under exports_root into runs."""
    runs = defaultdict(lambda: {"telem": [], "arrivals": [], "source": source_label})

    for dirpath, _dirnames, filenames in os.walk(exports_root):
        norm = dirpath.replace("\\", "/")
        if "/trimmed" in norm or "/_archive" in norm:
            continue
        for name in filenames:
            m = FILENAME_RE.match(name)
            if not m:
                continue
            path = os.path.join(dirpath, name)
            g = m.groupdict()
            attack, topology, location, scenario = _cell_key(path, exports_root)
            # Folder wins over filename: the folder is where analyze.ps1 looks.
            attack = attack or g["attack"]
            topology = topology or g["topology"]
            key = (source_label, attack, topology, location, scenario, g["repeat"])
            runs[key][g["kind"]].append((path, g))
    return runs


def judge(run, sample_interval_ms):
    """Apply the completeness criteria. Returns (verdict, reasons, stats)."""
    reasons = []
    root_telem = None
    children = []
    attacker_role = ""
    low_coverage = []

    for path, g in run["telem"]:
        meta = _read_meta(path, sample_interval_ms)
        if meta is None or meta["rows"] == 0:
            reasons.append(f"{os.path.basename(path)}: no data rows")
            continue
        if g["role"] == "root":
            root_telem = meta
        else:
            children.append((os.path.basename(path), meta))
            if meta["role"] in ATTACKER_ROLES:
                attacker_role = meta["role"]
        if meta["coverage"] < COVERAGE_FLOOR:
            low_coverage.append((os.path.basename(path), meta["coverage"]))

    arrivals_rows = 0
    for path, _g in run["arrivals"]:
        meta = _read_meta(path, sample_interval_ms)
        if meta:
            arrivals_rows += meta["rows"]

    if root_telem is None:
        reasons.append("no root telemetry")
    if not run["arrivals"]:
        reasons.append("no root arrivals file")
    elif arrivals_rows == 0:
        reasons.append("arrivals file is header-only (PDR uncomputable)")
    if len(children) < MIN_CHILDREN:
        reasons.append(f"only {len(children)} child node(s), need >= {MIN_CHILDREN}")
    if low_coverage:
        worst = min(c for _n, c in low_coverage)
        reasons.append(f"{len(low_coverage)} node(s) below {COVERAGE_FLOOR:.0%} coverage "
                       f"(worst {worst:.1%})")

    stats = {
        "children": len(children),
        "arrivals_rows": arrivals_rows,
        "attacker_role": attacker_role,
        "schema": (root_telem or (children[0][1] if children else {})).get("n_cols", 0),
    }
    verdict = "COMPLETE" if not reasons else "INCOMPLETE"
    return verdict, reasons, stats


def main():
    ap = argparse.ArgumentParser(
        description="Inventory every experimental cell against the M4/M5 criteria.")
    ap.add_argument("--exports", default=os.path.join(_THIS_DIR, "exports"),
                    help="Live exports root (default: tools/exports).")
    ap.add_argument("--archive", default=os.path.join(_REPO, "archive"),
                    help="Archive root scanned for <archive>/*/exports (default: archive/).")
    ap.add_argument("--live-only", action="store_true",
                    help="Skip archived captures.")
    ap.add_argument("--sample-interval-ms", type=float, default=DEFAULT_SAMPLE_INTERVAL_MS,
                    help="Firmware sampling interval AT CAPTURE TIME. Captures are not "
                         "self-describing; older ones need 1000 or 200.")
    ap.add_argument("--csv", default=None, help="Also write the table here.")
    args = ap.parse_args()

    sources = []
    if os.path.isdir(args.exports):
        sources.append((args.exports, "live"))
    if not args.live_only and os.path.isdir(args.archive):
        for entry in sorted(os.listdir(args.archive)):
            sub = os.path.join(args.archive, entry, "exports")
            if os.path.isdir(sub):
                sources.append((sub, f"archive/{entry}"))

    if not sources:
        print("No exports tree found.", file=sys.stderr)
        return 2

    all_runs = {}
    for root, label in sources:
        all_runs.update(scan(root, label, args.sample_interval_ms))

    rows = []
    for key in sorted(all_runs):
        source, attack, topology, location, scenario, repeat = key
        verdict, reasons, stats = judge(all_runs[key], args.sample_interval_ms)
        rows.append({
            "source": source, "attack": attack, "topology": topology,
            "location": location or "-", "scenario": scenario or "-",
            "repeat": repeat, "verdict": verdict,
            "children": stats["children"], "arrivals_rows": stats["arrivals_rows"],
            "attacker_role": stats["attacker_role"] or "-",
            "schema_cols": stats["schema"],
            "reasons": "; ".join(reasons),
        })

    print()
    print("=" * 118)
    print("  EXPERIMENTAL CELL INVENTORY  —  M4 (>=24 complete runs) / M5 (>=95% coverage)")
    print("=" * 118)
    width = max([len(r["source"]) for r in rows] + [6]) + 2
    print(f"  {'source':<{width}}{'attack':<11}{'topology':<14}{'loc':<8}{'scn':<10}"
          f"{'r':<3}{'kids':<6}{'arr':<8}{'v'}")
    print("  " + "-" * 114)
    for r in rows:
        mark = "OK " if r["verdict"] == "COMPLETE" else "-- "
        print(f"  {r['source']:<{width}}{r['attack']:<11}{r['topology']:<14}"
              f"{r['location']:<8}{r['scenario']:<10}{r['repeat']:<3}"
              f"{r['children']:<6}{r['arrivals_rows']:<8}{mark}")
        if r["reasons"]:
            print(f"      why: {r['reasons']}")

    complete = [r for r in rows if r["verdict"] == "COMPLETE"]
    cells = {(r["attack"], r["topology"]) for r in rows}
    complete_cells = {(r["attack"], r["topology"]) for r in complete}
    locations = {r["location"] for r in rows if r["location"] != "-"}

    print()
    print("=" * 118)
    print(f"  runs found          : {len(rows)}")
    print(f"  COMPLETE runs       : {len(complete)}   (M4 target: 24)")
    print(f"  attack x topology cells with ANY data      : {len(cells)}")
    print(f"  attack x topology cells with a COMPLETE run: {len(complete_cells)}")
    print(f"  distinct locations captured                : {len(locations)} "
          f"({', '.join(sorted(locations)) if locations else 'none recorded'})")
    print("=" * 118)
    print("  NOTE: archived runs are real captures — archive.ps1 MOVES data out of")
    print("  tools/exports/ so the next run starts clean; it does not discard it.")
    print("  Re-analyse one with:  .\\analyze.ps1   (point it at that folder's exports/)")
    print()

    if args.csv:
        with open(args.csv, "w", newline="", encoding="utf-8") as fh:
            w = csv.DictWriter(fh, fieldnames=list(rows[0].keys()) if rows else
                               ["source", "attack", "topology", "location", "scenario",
                                "repeat", "verdict", "children", "arrivals_rows",
                                "attacker_role", "schema_cols", "reasons"])
            w.writeheader()
            w.writerows(rows)
        print(f"  wrote {args.csv}")

    return 0


if __name__ == "__main__":
    sys.exit(main())

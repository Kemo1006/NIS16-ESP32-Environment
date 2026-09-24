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
    python inventory_cells.py --checklist          # LIVE checklist: tools/exports + analysis
    python inventory_cells.py --checklist --scope archive   # archive/* checklist
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

ANALYSIS_ROOT = os.path.join(_REPO, "analysis")

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
            runs[key]["rel"] = os.path.relpath(dirpath, exports_root)
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
    n_reasons_before = len(reasons)
    for path, _g in run["arrivals"]:
        meta = _read_meta(path, sample_interval_ms)
        if meta:
            arrivals_rows += meta["rows"]
        elif not os.path.isfile(path):
            # Listed by os.walk but not openable: on Windows almost always a
            # path past MAX_PATH (260). Say so instead of "header-only".
            reasons.append(f"{os.path.basename(path)}: UNREADABLE "
                           f"(path {len(os.path.abspath(path))} chars - too long?)")

    if root_telem is None:
        reasons.append("no root telemetry")
    if not run["arrivals"]:
        reasons.append("no root arrivals file")
    elif arrivals_rows == 0 and len(reasons) == n_reasons_before:
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


def analysis_status(run, analysis_root):
    """'ok' / 'missing' / 'stale' for the analyze.ps1 output of this run's cell.

    analysis_root is analysis/ for live runs and archive/<name>/analysis/ for an
    archived one (archive.ps1 moves both trees together). The analysis folder
    MIRRORS the capture's own folder (analyze.ps1 writes it that way), so this
    is right for new .../<location>/stationary/ captures and for pre-rename
    ones with no scenario folder alike. 'stale' = feature_table.csv is older
    than the newest capture file, i.e. exported after the last analysis.
    """
    ft = os.path.join(analysis_root, run["rel"], "feature_table.csv")
    if not os.path.isfile(ft):
        return "missing"
    newest = max((os.path.getmtime(p) for p, _g in run["telem"] + run["arrivals"]),
                 default=0)
    return "ok" if os.path.getmtime(ft) >= newest else "stale"


def counts_as_done(r):
    """The ONE rule for a ticked cell: complete capture AND a current analysis.

    Which runs are even considered (live vs archive) is the caller's scope -
    the live checklist never counts an archived run.
    """
    return r["verdict"] == "COMPLETE" and r["analysis"] == "ok"


def in_scope(r, scope):
    return (r["source"] == "live") == (scope == "live")


def _not_done_reason(r):
    if r["verdict"] != "COMPLETE":
        return r["reasons"]
    if r["analysis"] == "stale":
        return "analysis older than capture - re-run analyze.ps1"
    return "captured OK, not analysed - run analyze.ps1"



# ---------------------------------------------------------------------------
# Campaign plan (CTTHES3) — 4 locations x 4 topologies x 2 attacks x 4 scenarios
# ---------------------------------------------------------------------------
# The team's design: in ONE location, per topology, 4 blackhole runs and 4
# wormhole runs, each run using a DIFFERENT scenario. That is what answers the
# panel's "r1-r3 are identical" comment (12:45-16:00) — the repeats stop being
# repeats and become conditions.
#
# TWO THINGS THAT DESIGN MUST NOT MISS, both decided by the firmware, not by us:
#
#  1. HIGHLOAD is whole-run. mesh_config.h sets PROBE_INTERVAL_MS to
#     HIGHLOAD_PROBE_INTERVAL_MS (250 ms, 4x) for the ENTIRE run, so phase 0 of a
#     highload attack run is already 300 s of *benign traffic under high load*
#     and phase 1 is the same load under attack. That within-run contrast IS the
#     panel's "distinguish high utilisation from malicious flooding" (44:30), and
#     it needs no extra run. Same nodes, same room, same RF — a better control
#     than a separate benign run could be.
#
#  2. BURST is attack-window-only, so it does NOT get that for free. One child
#     fires BURST_COUNT probes BURST_OFFSET_S into the attack-length window. On
#     an attack run that burst coincides with the attack; without a matched
#     BENIGN burst run there is nothing to compare it against, and "legitimate
#     burst" and "burst during an attack" are perfectly confounded — exactly the
#     bias the panel described. mesh_config.h says so outright: the root built
#     with this flag "also holds an attack-length PHASE_ID_BASELINE window on a
#     baseline run so the burst lands at the same offset in the matched pair".
#     run.ps1's own header shows the pair as two command blocks.
#
#     => every (location, topology) that runs a burst ATTACK also needs ONE
#        baseline burst run. It is shared between blackhole and wormhole, so the
#        cost is 1 extra run per (location, topology), not 2.
#
# MOBILITY and POWERCYCLE are human scenarios (no firmware flag) — label-only.
PLAN_LOCATIONS = ["home", "G402", "DLSU_Library", "Goks"]
PLAN_TOPOLOGIES = ["linear", "star", "tree", "partial_mesh"]
PLAN_ATTACKS = ["blackhole", "wormhole"]
# Every scenario run.ps1 accepts (-Scenario ValidateSet).
SCENARIO_POOL = ["stationary", "highload", "burst", "jitter", "mobility", "powercycle"]
SCENARIOS_PER_CELL = 4

# Scenarios whose attack runs require a matched benign run at the same scenario.
PAIRED_SCENARIOS = {"burst"}

# "stationary" is the no-variation scenario everywhere since sep. 24 2026;
# "none" is its old name, still read (old plan files, pre-rename captures).
SCENARIO_LABEL = {"none": "stationary"}


def canon_scenario(scn):
    return "stationary" if scn in (None, "", "-", "none") else scn


def lbl(scn):
    return SCENARIO_LABEL.get(scn, scn)

# RANDOMISED PLAN (user decision, sep. 24 2026): each (location, topology,
# attack) cell runs 4 DIFFERENT scenarios drawn from the 6 - so linear/blackhole
# may get jitter while linear/wormhole gets mobility. Drawn ONCE and saved here:
# a plan re-drawn on every checklist view would move the goalposts. Commit it so
# every laptop works the same plan. The slot order is also the run order.
PLAN_FILE = os.path.join(_THIS_DIR, "campaign_plan.json")


def _draw_plan(seed):
    """Balanced draw: per location every scenario is used 5-6 times (32 slots /
    6 scenarios), and blackhole/wormhole never get the same 4 on one topology."""
    import random
    rng = random.Random(seed)
    slots = len(PLAN_TOPOLOGIES) * len(PLAN_ATTACKS) * SCENARIOS_PER_CELL
    lo = slots // len(SCENARIO_POOL)
    hi = -(-slots // len(SCENARIO_POOL))
    cells = {}
    for loc in PLAN_LOCATIONS:
        for _try in range(200000):
            draw = {}
            for topo in PLAN_TOPOLOGIES:
                for atk in PLAN_ATTACKS:
                    draw[(topo, atk)] = rng.sample(SCENARIO_POOL, SCENARIOS_PER_CELL)
            counts = defaultdict(int)
            for s in draw.values():
                for x in s:
                    counts[x] += 1
            balanced = all(lo <= counts[x] <= hi for x in SCENARIO_POOL)
            distinct = all(set(draw[(t, "blackhole")]) != set(draw[(t, "wormhole")])
                           for t in PLAN_TOPOLOGIES)
            if balanced and distinct:
                break
        for (topo, atk), s in draw.items():
            cells[f"{loc}/{topo}/{atk}"] = s
    return cells


def load_plan(reshuffle=False, seed=None):
    """{(loc, topo, atk): [4 scenarios]} from PLAN_FILE, drawing it first if needed."""
    import json
    import random
    if os.path.isfile(PLAN_FILE) and not reshuffle:
        with open(PLAN_FILE, encoding="utf-8") as fh:
            data = json.load(fh)
    else:
        seed = seed if seed is not None else random.SystemRandom().randrange(1, 10**9)
        data = {"seed": seed, "pool": SCENARIO_POOL, "per_cell": SCENARIOS_PER_CELL,
                "note": "Drawn once by inventory_cells.py; slot order = run order. "
                        "Commit this file. --reshuffle re-draws it.",
                "cells": _draw_plan(seed)}
        with open(PLAN_FILE, "w", encoding="utf-8") as fh:
            json.dump(data, fh, indent=2)
        print(f"  NEW randomised plan drawn (seed {seed}) -> {PLAN_FILE}")
        print("  Commit it so every laptop works the same plan.")
    plan = {}
    for k, s in data["cells"].items():
        loc, topo, atk = k.split("/")
        plan[(loc, topo, atk)] = [canon_scenario(x) for x in s]
    return plan


def build_plan(assign):
    """Every run the campaign calls for, as (attack, topology, location, scenario).

    A (location, topology) whose blackhole OR wormhole drew burst also needs ONE
    matched benign burst run, shared by both attacks."""
    planned = []
    for loc in PLAN_LOCATIONS:
        for topo in PLAN_TOPOLOGIES:
            drawn = set()
            for atk in PLAN_ATTACKS:
                for scn in assign[(loc, topo, atk)]:
                    planned.append((atk, topo, loc, scn))
                    drawn.add(scn)
            for scn in sorted(drawn & PAIRED_SCENARIOS):
                planned.append(("baseline", topo, loc, scn))
    return planned


def report_plan(rows, assign, repeats=1):
    """Target matrix vs what is actually captured."""
    planned = [p for p in build_plan(assign) for _ in range(repeats)]
    have_n = defaultdict(int)
    for r in rows:
        if in_scope(r, "live") and counts_as_done(r):
            have_n[(r["attack"], r["topology"],
                    r["location"] if r["location"] != "-" else "",
                    canon_scenario(r["scenario"]))] += 1

    # Count against the per-cell tally so N repeats need N captures, not one.
    remaining_need = defaultdict(int)
    for cellk in planned:
        remaining_need[cellk] += 1
    done, missing = [], []
    for cellk, need in remaining_need.items():
        got = min(have_n.get(cellk, 0), need)
        done.extend([cellk] * got)
        missing.extend([cellk] * (need - got))

    print()
    print("=" * 118)
    print("  CAMPAIGN PLAN  —  "
          f"{len(PLAN_LOCATIONS)} locations x {len(PLAN_TOPOLOGIES)} topologies x "
          f"{len(PLAN_ATTACKS)} attacks x {SCENARIOS_PER_CELL} RANDOMISED scenarios each")
    print("=" * 118)
    print(f"  scenario pool : {', '.join(lbl(x) for x in SCENARIO_POOL)}  (each cell draws "
          f"{SCENARIOS_PER_CELL}; see {os.path.basename(PLAN_FILE)})")
    print(f"  repeats per cell : {repeats}")
    print(f"  + {len([p for p in planned if p[0] == 'baseline'])} matched BENIGN runs "
          f"for the paired scenario(s): {', '.join(sorted(PAIRED_SCENARIOS))}")
    print(f"  planned runs : {len(planned)}")
    print(f"  complete     : {len(done)}")
    print(f"  remaining    : {len(missing)}")
    print()

    # Per-location remaining, so a session at one site has a shopping list.
    per_loc = defaultdict(int)
    for _atk, _topo, loc, _scn in missing:
        per_loc[loc] += 1
    print("  remaining per location:")
    for loc in PLAN_LOCATIONS:
        print(f"    {loc:<16}{per_loc.get(loc, 0):>4}")

    # Run-time budget. One run is the phase timeline; the rest is flashing,
    # placement and export, which in practice dominates.
    run_s = 60 + 300 + 180 + 120
    print()
    print(f"  one run's phase timeline : {run_s} s ({run_s/60:.0f} min)")
    print(f"  capture time only        : {len(missing) * run_s / 3600:.1f} h")
    print(f"  realistic w/ setup+export: {len(missing) * 35 / 60:.1f} h "
          f"(at ~35 min/run for an 8-board rig)")
    print()
    print("  PANEL, 'you do not need to run each test for a full hour':")
    win = 1
    per_run_windows = (run_s // win) * 8
    print(f"    at 10 Hz x 8 nodes a single run already yields ~{per_run_windows:,} "
          f"one-second windows.")
    print(f"    {len(planned)} runs => ~{len(planned) * per_run_windows:,} windows, "
          f"vs the 10k the panel mentioned.")
    print("    You are ~2 orders of magnitude past 10k. Shortening PHASE_BASELINE_S")
    print("    (300 s) is the cheapest way to buy back campaign hours without")
    print("    losing statistical power — the panel explicitly invited this.")
    print("=" * 118)
    print()


def _worst_coverage(reasons):
    """Pull the worst coverage % out of a reason string, or None.

    judge() phrases it as "N node(s) below 95% coverage (worst 93.7%)". A run
    that fails ONLY on coverage is a near miss worth ranking; one missing a root
    file is a different kind of broken, so this returns None for those and they
    sort last.
    """
    m = re.search(r"worst ([\d.]+)%", reasons or "")
    return float(m.group(1)) if m else None


def _blocker_summary(reasons):
    """The shortest honest description of why a run did not count."""
    r = reasons or ""
    if "UNREADABLE" in r:
        return "file unreadable (path too long?)"
    if "no root telemetry" in r or "no root arrivals" in r:
        return "no root file"
    if "header-only" in r:
        return "arrivals header-only"
    if "child node(s), need" in r:
        return "too few children"
    if "no data rows" in r:
        return "empty telem file"
    cov = _worst_coverage(r)
    if cov is not None:
        return f"coverage {cov:.1f}% (floor {COVERAGE_FLOOR:.0%})"
    return (r[:40] + "...") if len(r) > 43 else (r or "unknown")


def report_checklist(rows, assign, repeats=1, scope="live"):
    """Tick-box progress table, grouped by location then topology.

    This is what run_wizard.ps1's "Campaign progress" option renders. It reads
    the SAME scan as the inventory above, so the checklist can never drift from
    what is actually on disk - the box is ticked because the files exist and
    pass the M4/M5 criteria, not because someone remembered doing the run.

    WHAT TICKS A BOX - scanned from the folders, no board/COM contact
    ------------------------------------------------------------------
    [x] only when ALL of these hold for a run in tools/exports/:
        - COMPLETE (root telemetry + non-empty arrivals + >= 3 children +
          every node >= 95% coverage)
        - analysed: analysis/<cell>/feature_table.csv exists and is newer
          than the capture (analyze.ps1 ran AFTER this export)
    [~] the cell has live data that is not there yet - the NEXT ACTIONS list
        says exactly what is missing (re-capture vs just run analyze.ps1).
    [ ] nothing live.

    TWO SCOPES (user decision, sep. 24 2026 - this used to pool both):
      live    - tools/exports/ + analysis/. Archiving a run takes it OFF this one.
      archive - archive/*/exports/ + that archive's own analysis/. Identical
                copies of one capture in several archives count once.
    """
    have = defaultdict(int)
    have_src = defaultdict(list)
    attempted = defaultdict(list)

    def _key(r):
        return (r["attack"], r["topology"],
                r["location"] if r["location"] != "-" else "",
                canon_scenario(r["scenario"]))

    out_of_scope = sum(1 for r in rows if not in_scope(r, scope))
    rows = [r for r in rows if in_scope(r, scope)]
    # One capture copied into two archives is one run, not two.
    seen, dup_srcs, uniq = {}, [], []
    for r in rows:
        sig = (r["attack"], r["topology"], r["location"], r["scenario"],
               r["repeat"], r["children"], r["arrivals_rows"])
        if sig in seen:
            dup_srcs.append((r["source"], seen[sig]))
            continue
        seen[sig] = r["source"]
        uniq.append(r)
    rows = uniq

    for r in rows:
        k = _key(r)
        if counts_as_done(r):
            have[k] += 1
            have_src[k].append(r)
        else:
            attempted[k].append(r)

    def mark(atk, topo, loc, scn):
        k = (atk, topo, loc, scn)
        n = have.get(k, 0)
        if repeats > 1:
            return f"{min(n, repeats)}/{repeats}"
        if n:
            return "[x]"
        return "[~]" if attempted.get(k) else "[ ]"

    total_done = total_planned = 0
    per_loc_done = defaultdict(int)
    first_open = {}

    def tally(atk, topo, loc, scn):
        nonlocal total_done, total_planned
        got = min(have.get((atk, topo, loc, scn), 0), repeats)
        total_planned += repeats
        total_done += got
        per_loc_done[loc] += got
        if got < repeats and not attempted.get((atk, topo, loc, scn)):
            first_open.setdefault(loc, (atk, topo, scn))
    print()
    print("=" * 96)
    where = ("tools\\exports\\ + analysis\\" if scope == "live"
             else "archive\\*\\exports\\ + archive\\*\\analysis\\")
    print(f"  CAMPAIGN PROGRESS - {scope.upper()}   "
          f"({'x' if repeats == 1 else str(repeats) + ' repeats'} per cell)   - from {where}")
    print("  [x] = captured + complete + analysed   [~] = data here, not done yet   "
          "[ ] = nothing here")
    print("=" * 96)

    for loc in PLAN_LOCATIONS:
        print()
        print(f"  -- {loc} " + "-" * (88 - len(loc)))
        print(f"    {'topology':<14}{'attack':<11}4 scenarios drawn for this cell "
              f"(left to right = run order)")
        for topo in PLAN_TOPOLOGIES:
            drawn = set()
            for atk in PLAN_ATTACKS:
                scns = assign[(loc, topo, atk)]
                drawn |= set(scns)
                for scn in scns:
                    tally(atk, topo, loc, scn)
                slots = "  ".join(f"{mark(atk, topo, loc, s)} {lbl(s):<10}" for s in scns)
                print(f"    {topo if atk == PLAN_ATTACKS[0] else '':<14}{atk:<11}{slots}")
            # Only an attack-window scenario needs a separate benign run; for the
            # others the attack run's own phase 0 IS the control.
            for scn in sorted(drawn & PAIRED_SCENARIOS):
                tally("baseline", topo, loc, scn)
                print(f"    {'':<14}{'benign':<11}{mark('baseline', topo, loc, scn)} "
                      f"{lbl(scn):<10}  (matched pair for this topology's {lbl(scn)} runs)")

    # Captures that are real but outside this cell's drawn 4: listed, not counted.
    planned_keys = set(build_plan(assign))
    off_plan = sorted({k for k in list(have) + list(attempted) if k not in planned_keys})

    print()
    print("=" * 96)
    print(f"  done: {total_done} / {total_planned} planned runs")
    if scope == "live" and out_of_scope:
        print(f"  ({out_of_scope} archived run(s) not counted here - see the ARCHIVE checklist)")
    if dup_srcs:
        print(f"  ({len(dup_srcs)} duplicate copy/copies of one capture counted once:")
        for a, b in sorted(set(dup_srcs)):
            print(f"      {a}  ==  {b}")
        print("   )")

    if off_plan:
        print()
        print("  OFF-PLAN (real data, but not one of that cell's drawn scenarios - not counted):")
        for atk, topo, loc, scn in off_plan:
            print(f"    {atk:<10}{topo:<24}{loc or '-':<14}{lbl(scn)}")

    if have_src:
        print()
        print(f"  DONE ({scope} capture + analysis):")
        tw = max([len(k[1]) for k in have_src] + [len("topology")]) + 2
        for k in sorted(have_src):
            atk, topo, loc, scn = k
            reps = ", ".join(f"r{r['repeat']}" for r in have_src[k])
            print(f"    [x] {atk:<10}{topo:<{tw}}{loc or '-':<8}{lbl(scn):<10} {reps}")

    # ---- what to do next, cheapest first -------------------------------------
    # A complete capture that only lacks analysis costs one analyze.ps1 call, so
    # it ranks above any near-miss that needs a new 11-minute capture.
    near = []
    for k, rs in attempted.items():
        if have.get(k, 0):
            continue                      # already satisfied by another repeat
        best = None
        for r in rs:
            if r["verdict"] == "COMPLETE":
                rank = (0, 0)
            else:
                cov = _worst_coverage(r["reasons"])
                rank = (1, -cov) if cov is not None else (2, 0)
            if best is None or rank < best[0]:
                best = (rank, r)
        near.append((best[0], k, best[1]))

    if near:
        near.sort(key=lambda t: t[0])
        print()
        print(f"  NEXT ACTIONS ({scope} cells with data, cheapest fix first):")
        tw2 = max([len(k[1]) for _r, k, _b in near[:12]] + [len("topology")]) + 2
        print(f"    {'attack':<11}{'topology':<{tw2}}{'loc':<8}{'scn':<10}{'what is missing'}")
        for _rank, k, r in near[:12]:
            atk, topo, loc, scn = k
            if r["verdict"] == "COMPLETE":
                why = _not_done_reason(r)
            else:
                why = "RE-CAPTURE: " + _blocker_summary(r["reasons"])
            src = "" if scope == "live" else f"   [{r['source']}]"
            print(f"    {atk:<11}{topo:<{tw2}}{loc or '-':<8}{lbl(scn):<10}{why}{src}")
        if len(near) > 12:
            print(f"    ... and {len(near) - 12} more - run with --plan for every reason.")

    # ---- suggested next capture -----------------------------------------------
    # Stay at the location with the most progress (fewest trips), first empty cell.
    if scope == "live" and first_open:
        loc = max(first_open, key=lambda l: (per_loc_done[l], -PLAN_LOCATIONS.index(l)))
        atk, topo, scn = first_open[loc]
        print()
        print(f"  SUGGESTED NEXT CAPTURE: {atk} / {topo} / {loc} / {lbl(scn)}   (run.ps1 -Scenario {scn})")
        print(f"     (next slot in run order, at the location with the most done runs)")
    print()
    print("  Scenarios are RANDOMISED per cell (4 of: " + ", ".join(lbl(x) for x in SCENARIO_POOL) + "),")
    print(f"     fixed in tools\\{os.path.basename(PLAN_FILE)}. A 'benign' row appears only where")
    print("     burst was drawn: burst fires inside the attack window only, so it needs")
    print("     a matched benign run. Every other scenario's control is phase 0.")
    print("=" * 96)
    print()

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
    ap.add_argument("--checklist", action="store_true",
                    help="Print the tick-box campaign progress table (what "
                         "run_wizard.ps1's Campaign progress option shows).")
    ap.add_argument("--scope", choices=["live", "archive"], default="live",
                    help="Checklist to print: live (tools/exports + analysis, the "
                         "default) or archive (archive/*/exports + their analysis).")
    ap.add_argument("--reshuffle", action="store_true",
                    help="Re-draw the randomised scenario plan (campaign_plan.json). "
                         "Only before the campaign starts - it moves every target.")
    ap.add_argument("--seed", type=int, default=None,
                    help="Seed for a new/reshuffled plan (default: random, recorded).")
    ap.add_argument("--repeats", type=int, default=1,
                    help="Planned repeats per (location, topology, attack, scenario) "
                         "cell. 1 => 128 attack runs; 4 => 512. See --plan.")
    ap.add_argument("--plan", action="store_true",
                    help="Also print the campaign matrix (4 locations x 4 topologies "
                         "x 2 attacks x 4 scenarios) and what is still missing.")
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
        a_root = (ANALYSIS_ROOT if source == "live"
                  else os.path.join(args.archive, source.split("/", 1)[1], "analysis"))
        analysis = analysis_status(all_runs[key], a_root)
        rows.append({
            "analysis": analysis,
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

    live = [r for r in rows if r["source"] == "live"]
    arch = [r for r in rows if r["source"] != "live"]
    live_done = [r for r in live if counts_as_done(r)]
    live_complete = [r for r in live if r["verdict"] == "COMPLETE"]
    arch_complete = [r for r in arch if r["verdict"] == "COMPLETE"]
    locations = {r["location"] for r in live if r["location"] != "-"}

    print()
    print("=" * 118)
    print(f"  LIVE (tools/exports)  runs: {len(live):<4} complete captures: {len(live_complete):<4}"
          f" DONE (complete + analysed): {len(live_done)}   (M4 target: 24)")
    print(f"  ARCHIVE (archive/*)   runs: {len(arch):<4} complete captures: {len(arch_complete):<4}"
          f" (never counted on the live checklist)")
    print(f"  live locations        : {len(locations)} "
          f"({', '.join(sorted(locations)) if locations else 'none'})")
    print("=" * 118)
    print("  Archived runs are real captures - archive.ps1 MOVES them, it does not discard")
    print("  them - but only tools/exports/ counts toward the live checklist.")
    print()

    if args.checklist or args.plan or args.reshuffle:
        assign = load_plan(args.reshuffle, args.seed)
    if args.checklist:
        report_checklist(rows, assign, args.repeats, args.scope)

    if args.plan:
        report_plan(rows, assign, args.repeats)

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

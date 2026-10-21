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
from datetime import datetime

_THIS_DIR = os.path.dirname(os.path.abspath(__file__))
_REPO = os.path.dirname(_THIS_DIR)
sys.path.insert(0, _THIS_DIR)
import name_stamp  # noqa: E402

# Same convention export_logs.py writes and validate_integrity.py checks.
FILENAME_RE = re.compile(
    r"^(?P<role>root|victim|child)_(?P<nick>[^_]+)_(?P<topology>[^_]+)_(?P<attack>[^_]+)"
    r"_r(?P<repeat>\d+)_(?P<stamp>" + name_stamp.STAMP + r")_(?P<kind>telem|arrivals)\.csv$"
)

ANALYSIS_ROOT = os.path.join(_REPO, "datasets", "analysis")

MIN_CHILDREN = 3            # below this the topology is not meaningfully exercised
COVERAGE_FLOOR = 0.95       # Milestone 5
DEFAULT_SAMPLE_INTERVAL_MS = 100

# Roles that mean "this node ran the manipulation", as written to the role column.
ATTACKER_ROLES = {"blackhole", "wormhole_a", "wormhole_b"}


def _read_meta(path, sample_interval_ms):
    """Row count, span, role and phase set from one CSV, without loading it all."""
    rows = 0
    first_ts = last_ts = None
    # Coverage counts only the experiment (phases 0-3), not phase 255 = setup /
    # mesh forming, which the analysis drops anyway (oct. 7, 2026: ED80's
    # setup-only gaps held a usable run at 91.6 %). Falls back to every row
    # when the file has no phase column.
    # Phase 255 can also sit in the MIDDLE of a file (e.g. burst runs), so the
    # expected count uses only the time between two consecutive experiment rows.
    exp_rows = 0
    exp_time_us = 0
    prev_exp_ts = None
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
                    if f[ph_i] != "255":
                        if prev_exp_ts is not None:
                            exp_time_us += ts - prev_exp_ts
                        prev_exp_ts = ts
                        exp_rows += 1
                    else:
                        prev_exp_ts = None
    except OSError:
        return None

    span_s = ((last_ts - first_ts) / 1e6) if (first_ts is not None and last_ts is not None) else 0.0
    if exp_rows:
        expected = exp_time_us / 1e6 * (1000.0 / sample_interval_ms) + 1
        coverage = exp_rows / expected
    else:
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
    when = None

    for path, g in run["telem"]:
        try:
            t = name_stamp.parse(g["stamp"], path)[0]
            when = t if when is None or t > when else when
        except ValueError:
            pass
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
        "when": when,
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
    # CONTENT, not clock (oct. 1, 2026): comparing modification times called
    # linear/G402/jitter 'stale' after a plain `git pull` - git rewrites a
    # pulled file's mtime even when its bytes are unchanged, so every pull made
    # finished analysis look out of date. The feature table records which
    # capture files went into it (source_file); the analysis is current when
    # every telemetry file of this run is in that list. mtime remains only as a
    # fallback for a feature table too old to carry source_file.
    analysed = _analysed_sources(ft)
    if analysed is not None:
        mine = {os.path.basename(p) for p, _g in run["telem"]}
        return "ok" if mine <= analysed else "stale"
    newest = max((os.path.getmtime(p) for p, _g in run["telem"] + run["arrivals"]),
                 default=0)
    return "ok" if os.path.getmtime(ft) >= newest else "stale"


_SOURCES_CACHE: dict = {}


def _analysed_sources(ft):
    """Set of source_file basenames in a feature_table.csv, or None if it has
    no source_file column. Cached: several runs can share one cell's table."""
    if ft not in _SOURCES_CACHE:
        found = None
        try:
            with open(ft, newline="", encoding="utf-8-sig") as fh:
                reader = csv.DictReader(fh)
                if reader.fieldnames and "source_file" in reader.fieldnames:
                    found = {os.path.basename(row["source_file"])
                             for row in reader if row.get("source_file")}
        except (OSError, csv.Error):
            found = None
        _SOURCES_CACHE[ft] = found
    return _SOURCES_CACHE[ft]


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
# Campaign plan (CTTHES3) — 3 locations x 4 topologies x 2 attacks x 4 scenarios
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
#  3. SINCE OCT. 7, 2026 (user's decision, replaces "burst only"): EVERY
#     (location, topology) gets exactly ONE matched benign run, and inside one
#     location the 4 topologies get 4 DIFFERENT benign scenarios (e.g. linear
#     = powercycle, tree = jitter, star = burst, partial_mesh = highload). Each
#     benign scenario is one that cell's attack runs also drew, so it is still a
#     matched pair. Drawn once, balanced across locations, saved in
#     campaign_plan.json "benign" (see _draw_benign). With 3 locations (oct. 7,
#     2026: home dropped) that is 12 benign runs, 108 total, 2 per scenario.
#
#  4. SINCE OCT. 21, 2026 (user: "3 runs each ... 1 run per location but with
#     diff scenario ... may also be randomized in other topology"): still ONE
#     benign run per (location, topology), but the rule is now PER TOPOLOGY -
#     its 3 benign runs (G402, Library, Yuchengco) use 3 DIFFERENT scenarios,
#     and which location gets which scenario is shuffled per topology (e.g.
#     tree: G402 highload, Library stationary, Yuchengco burst; partial_mesh:
#     G402 stationary ...). Each location still sees every scenario, each
#     scenario gets 4 runs. Benign runs already captured are pinned. Editable
#     by hand in the Campaign "Plan settings" dialog (--draw-benign /
#     --set-benign). D-35.
#
# MOBILITY and POWERCYCLE are human scenarios (no firmware flag) — label-only.
# oct. 7, 2026: "home" left the campaign (its captures still scan, as off-plan),
# "Goks" renamed "Yuchengco".
PLAN_LOCATIONS = ["G402", "DLSU_Library", "Yuchengco"]
PLAN_TOPOLOGIES = ["linear", "star", "tree", "partial_mesh"]
PLAN_ATTACKS = ["blackhole", "wormhole"]
# Campaign scenarios. oct. 9, 2026 (user): mobility + powercycle DROPPED from the
# campaign - they are human-in-the-loop scenarios. run.ps1 still accepts them
# (-Scenario ValidateSet), so old captures still scan, as off-plan.
# Pool == SCENARIOS_PER_CELL, so every cell runs all 4; only the order is drawn.
SCENARIO_POOL = ["stationary", "highload", "burst", "jitter"]
SCENARIOS_PER_CELL = 4
# oct. 21, 2026 (user: "give options more scenario in the settings like the mobility
# powercycle"): the two human-in-the-loop scenarios are back as OPT-IN plan options.
# They are OFF unless campaign_plan.json "add_scenarios" lists them (Plan settings
# tick box); ticked, every (location, topology, attack) cell gets that scenario as
# an extra slot after its drawn ones. The benign assignment is not touched.
OPTIONAL_SCENARIOS = ["mobility", "powercycle"]


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

# PLAN SETTINGS (user, oct. 21 2026: "tick and untick the scenario and location and
# it will modify the checklist - not a filter, if we change our minds we change the
# plan"). campaign_plan.json "skip" = {"scenarios": [...], "locations": [...],
# "topologies": [...], "attacks": [...]} ("baseline" in attacks drops the matched
# benign runs). A skipped item leaves the PLAN itself: its slots stop counting
# (done / total shrink), its captures become off-plan, nothing is deleted. The
# drawn order in "cells" is kept, so un-ticking it again restores the old slots.
PLAN_ALL = {"locations": list(PLAN_LOCATIONS), "topologies": list(PLAN_TOPOLOGIES),
            "attacks": list(PLAN_ATTACKS) + ["baseline"],
            "scenarios": list(SCENARIO_POOL) + OPTIONAL_SCENARIOS}


def read_plan_skip():
    import json
    try:
        with open(PLAN_FILE, encoding="utf-8") as fh:
            data = json.load(fh)
    except (OSError, ValueError):
        data = {}
    sk = dict(data.get("skip") or {})
    added = set(data.get("add_scenarios") or [])
    sk["scenarios"] = list(sk.get("scenarios") or []) + [x for x in OPTIONAL_SCENARIOS if x not in added]
    return {k: sorted(set(sk.get(k) or []) & set(v)) for k, v in PLAN_ALL.items()}


PLAN_SKIP = read_plan_skip()
SCENARIO_POOL += OPTIONAL_SCENARIOS
for _lst, _key in ((PLAN_LOCATIONS, "locations"), (PLAN_TOPOLOGIES, "topologies"),
                   (PLAN_ATTACKS, "attacks"), (SCENARIO_POOL, "scenarios")):
    _lst[:] = [x for x in _lst if x not in PLAN_SKIP[_key]]
SCENARIOS_PER_CELL = len(SCENARIO_POOL)   # every cell runs the whole active pool


def write_plan_skip(skip):
    """Save the "skip" settings into campaign_plan.json; everything else untouched."""
    import json
    with open(PLAN_FILE, encoding="utf-8") as fh:
        data = json.load(fh)
    clean = {k: sorted(set(skip.get(k) or []) & set(v)) for k, v in PLAN_ALL.items()}
    for k, v in PLAN_ALL.items():
        if k != "attacks" and len(clean[k]) >= len(v):
            raise SystemExit(f"ERROR: at least one {k[:-1]} must stay in the plan")
    added = [x for x in OPTIONAL_SCENARIOS if x not in clean["scenarios"]]
    stored = dict(clean, scenarios=[x for x in clean["scenarios"] if x not in OPTIONAL_SCENARIOS])
    if added:
        data["add_scenarios"] = added
    else:
        data.pop("add_scenarios", None)
    if any(stored.values()):
        data["skip"] = stored
    else:
        data.pop("skip", None)
    with open(PLAN_FILE, "w", encoding="utf-8") as fh:
        json.dump(data, fh, indent=2)
        fh.write("\n")
    return clean


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
            # With pool == per_cell both attacks necessarily share the same set.
            distinct = (SCENARIOS_PER_CELL >= len(SCENARIO_POOL)
                        or all(set(draw[(t, "blackhole")]) != set(draw[(t, "wormhole")])
                               for t in PLAN_TOPOLOGIES))
            if balanced and distinct:
                break
        for (topo, atk), s in draw.items():
            cells[f"{loc}/{topo}/{atk}"] = s
    return cells


def _draw_benign(cells, seed, pins=None):
    """{"loc/topo": scenario}: one benign run per (location, topology).

    Oct. 21, 2026 rule (D-35): per TOPOLOGY the locations get DIFFERENT
    scenarios (a shuffled permutation of the active pool, cycled when there are
    more locations than scenarios); per location the scenarios stay balanced.
    `pins` {"loc/topo": scenario} (benign runs already captured) are kept.
    The matched-pair rule holds because every cell runs the whole active pool.
    """
    import itertools
    import random
    rng = random.Random(seed)
    pins = {k: v for k, v in (pins or {}).items() if v in SCENARIO_POOL}
    pool, locs = list(SCENARIO_POOL), list(PLAN_LOCATIONS)
    reps = -(-len(locs) // len(pool))
    perms = sorted({p[:len(locs)] for p in itertools.permutations(pool * reps, len(locs))
                    if len(set(p[:len(locs)])) == min(len(pool), len(locs))})
    best, best_score = None, None
    for _ in range(4000):
        pick = {}
        for topo in PLAN_TOPOLOGIES:
            fit = [p for p in perms if all(pins.get(f"{l}/{topo}", x) == x for l, x in zip(locs, p))]
            perm = rng.choice(fit or perms)
            for l, x in zip(locs, perm):
                pick[f"{l}/{topo}"] = pins.get(f"{l}/{topo}", x)
        per_loc = [[sum(1 for t in PLAN_TOPOLOGIES if pick[f"{l}/{t}"] == x) for x in pool] for l in locs]
        totals = [sum(c[i] for c in per_loc) for i in range(len(pool))]
        same_neighbour = sum(1 for a, b in zip(PLAN_TOPOLOGIES, PLAN_TOPOLOGIES[1:])
                             if all(pick[f"{l}/{a}"] == pick[f"{l}/{b}"] for l in locs))
        score = (sum(max(c) - min(c) for c in per_loc) + max(totals) - min(totals),
                 same_neighbour, rng.random())
        if best_score is None or score < best_score:
            best, best_score = pick, score
    return {f"{l}/{t}": best[f"{l}/{t}"] for l in locs for t in PLAN_TOPOLOGIES}


def captured_benign():
    """{"loc/topo": scenario} for benign (baseline) runs with a root capture on disk."""
    out = {}
    base = os.path.join(_REPO, "datasets", "exports", "baseline")
    for topo in PLAN_TOPOLOGIES:
        for loc in PLAN_LOCATIONS:
            for scn in SCENARIO_POOL:
                d = os.path.join(base, topo, loc, scn)
                if os.path.isdir(d) and any(f.startswith("root_") for f in os.listdir(d)):
                    out.setdefault(f"{loc}/{topo}", scn)
    return out


def write_plan_benign(mapping):
    """Save a hand-edited / re-drawn benign assignment into campaign_plan.json."""
    import json
    with open(PLAN_FILE, encoding="utf-8") as fh:
        data = json.load(fh)
    new = dict(data.get("benign") or {})
    for k, v in mapping.items():
        loc, _, topo = k.partition("/")
        if loc not in PLAN_ALL["locations"] or topo not in PLAN_ALL["topologies"]:
            raise SystemExit(f"ERROR: unknown benign slot {k}")
        if canon_scenario(v) not in PLAN_ALL["scenarios"]:
            raise SystemExit(f"ERROR: unknown scenario {v} for {k}")
        new[k] = canon_scenario(v)
    data["benign"] = new
    data["benign_note"] = ("One matched benign (attack none) run per location/topology; per topology "
                           "the 3 locations use 3 different scenarios, shuffled per topology "
                           "(oct. 21, 2026, D-35). Edit in Campaign > Plan settings.")
    with open(PLAN_FILE, "w", encoding="utf-8") as fh:
        json.dump(data, fh, indent=2)
        fh.write("\n")
    return new


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
        if any(PLAN_SKIP.values()):
            data["skip"] = PLAN_SKIP   # a re-draw keeps the plan settings
        with open(PLAN_FILE, "w", encoding="utf-8") as fh:
            json.dump(data, fh, indent=2)
        print(f"  NEW randomised plan drawn (seed {seed}) -> {PLAN_FILE}")
        print("  Commit it so every laptop works the same plan.")
    if "benign" not in data or reshuffle:
        data["benign"] = _draw_benign(data["cells"], data.get("seed"), captured_benign())
        data["benign_note"] = ("One matched benign (attack none) run per location/topology; per topology "
                               "the 3 locations use 3 different scenarios (oct. 21, 2026, D-35).")
        with open(PLAN_FILE, "w", encoding="utf-8") as fh:
            json.dump(data, fh, indent=2)
        print(f"  benign runs drawn (one per location/topology) -> {PLAN_FILE}")
    plan = {}
    sk = PLAN_SKIP
    for k, s in data["cells"].items():
        loc, topo, atk = k.split("/")
        if loc in sk["locations"] or topo in sk["topologies"] or atk in sk["attacks"]:
            continue
        lst = [canon_scenario(x) for x in s if canon_scenario(x) not in sk["scenarios"]]
        plan[(loc, topo, atk)] = lst + [x for x in SCENARIO_POOL if x not in lst]   # opt-in extras
    # ("benign", loc, topo) -> [scenario]: the cell's one matched benign run.
    for k, scn in data["benign"].items():
        loc, topo = k.split("/")
        if loc in sk["locations"] or topo in sk["topologies"] or "baseline" in sk["attacks"]:
            continue
        plan[("benign", loc, topo)] = [s for s in [canon_scenario(scn)] if s not in sk["scenarios"]]
    return plan


def benign_for(assign, loc, topo):
    """The matched benign scenario(s) planned for one (location, topology)."""
    return assign.get(("benign", loc, topo), [])


def build_plan(assign):
    """Every run the campaign calls for, as (attack, topology, location, scenario).

    Each (location, topology) also gets ONE matched benign run (benign_for),
    shared by both attacks."""
    planned = []
    for loc in PLAN_LOCATIONS:
        for topo in PLAN_TOPOLOGIES:
            for atk in PLAN_ATTACKS:
                for scn in assign[(loc, topo, atk)]:
                    planned.append((atk, topo, loc, scn))
            for scn in benign_for(assign, loc, topo):
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
          f"(one per location/topology, a different scenario per topology)")
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


def _cell(r):
    """(attack, topology, location, scenario) of one inventory row."""
    return (r["attack"], r["topology"],
            r["location"] if r["location"] != "-" else "",
            canon_scenario(r["scenario"]))


def _classify(rows, scope):
    """Split the scanned rows of one scope into done / attempted per cell.

    Shared by the tick-box checklist and campaign_status() (board, sessions,
    dashboard JSON), so every view counts a run the same way. One capture
    copied into two archives is one run, not two.
    """
    out_of_scope = sum(1 for r in rows if not in_scope(r, scope))
    rows = [r for r in rows if in_scope(r, scope)]
    seen, dup_srcs, uniq = {}, [], []
    for r in rows:
        sig = (r["attack"], r["topology"], r["location"], r["scenario"],
               r["repeat"], r["children"], r["arrivals_rows"])
        if sig in seen:
            dup_srcs.append((r["source"], seen[sig]))
            continue
        seen[sig] = r["source"]
        uniq.append(r)

    have = defaultdict(int)
    have_src = defaultdict(list)
    attempted = defaultdict(list)
    latest = {}      # newest capture time per cell, from the filename stamps
    for r in uniq:
        k = _cell(r)
        if r["when"] is not None and (k not in latest or r["when"] > latest[k][0]):
            latest[k] = (r["when"], k[3])
        if counts_as_done(r):
            have[k] += 1
            have_src[k].append(r)
        else:
            attempted[k].append(r)
    return {"have": have, "have_src": have_src, "attempted": attempted,
            "latest": latest, "dup_srcs": dup_srcs, "out_of_scope": out_of_scope}


def report_checklist(rows, assign, repeats=1, scope="live", color=False):
    """Tick-box progress table, grouped by location then topology.

    LAYOUT (oct. 17 2026, user: "very messy"): one header with the overall bar,
    one block per location with its own bar, a fixed scenario grid, then only
    what needs a decision (NEEDS ATTENTION, NEXT CAPTURE, OFF-PLAN). The old
    per-run DONE list was dropped - it repeated the grid line for line.

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
    c = _classify(rows, scope)
    have, attempted = c["have"], c["attempted"]
    latest, dup_srcs, out_of_scope = c["latest"], c["dup_srcs"], c["out_of_scope"]
    C = _ansi(color)
    W = 94

    def last_run(atk, topo, loc, scns):
        found = [latest[(atk, topo, loc, s_)] for s_ in scns if (atk, topo, loc, s_) in latest]
        if not found:
            return ""
        when, _scn = max(found)
        return when.strftime("%b %d  %I:%M %p")

    def mark(atk, topo, loc, scn):
        """(plain text, coloured text) of one grid box - same width either way."""
        k = (atk, topo, loc, scn)
        n = have.get(k, 0)
        if repeats > 1:
            t = f"{min(n, repeats)}/{repeats}"
            return t, (C["g"] if n >= repeats else C["y"] if n or attempted.get(k) else C["d"]) + t + C["x"]
        if n:
            return "[x]", f"{C['g']}[x]{C['x']}"
        if attempted.get(k):
            return "[~]", f"{C['y']}[~]{C['x']}"
        return "[ ]", f"{C['d']}[ ]{C['x']}"

    total_done = total_planned = 0
    per_loc = defaultdict(lambda: [0, 0, 0])     # done, partial, planned
    first_open = {}

    def tally(atk, topo, loc, scn):
        nonlocal total_done, total_planned
        k = (atk, topo, loc, scn)
        got = min(have.get(k, 0), repeats)
        total_planned += repeats
        total_done += got
        per_loc[loc][0] += got
        per_loc[loc][1] += 1 if (got < repeats and attempted.get(k)) else 0
        per_loc[loc][2] += repeats
        if got < repeats and not attempted.get(k):
            first_open.setdefault(loc, (atk, topo, scn))

    # pre-count so the header can show the totals
    for loc in PLAN_LOCATIONS:
        for topo in PLAN_TOPOLOGIES:
            for atk in PLAN_ATTACKS:
                for scn in assign[(loc, topo, atk)]:
                    tally(atk, topo, loc, scn)
            for scn in benign_for(assign, loc, topo):
                tally("baseline", topo, loc, scn)
    partial_total = sum(v[1] for v in per_loc.values())

    rule, thin = "  " + "=" * (W - 2), "  " + "-" * (W - 2)

    def fit(text, first, rest):
        import textwrap
        return textwrap.fill(" ".join(text.split()), width=W, initial_indent=first,
                             subsequent_indent=rest, break_on_hyphens=False)
    print()
    print(rule)
    title = f"  CAMPAIGN CHECKLIST  |  {scope.upper()}"
    stamp = datetime.now().strftime("%b %d, %I:%M %p")
    print(f"{C['b']}{title}{C['x']}{' ' * (W - len(title) - len(stamp))}{C['d']}{stamp}{C['x']}")
    print(rule)
    pct = 100 * total_done / total_planned if total_planned else 0
    print(f"  {C['b']}{total_done} of {total_planned} runs done{C['x']}   "
          f"{_bar(total_done, partial_total, total_planned, 44, C)}  {pct:.0f} %")
    print(f"  {C['g']}[x]{C['x']} done   {C['y']}[~]{C['x']} data here, not done yet   "
          f"{C['d']}[ ]{C['x']} not captured   {C['d']} . {C['x']} not in the plan")
    print(f"  {C['d']}benign = the ONE matched no-attack run of that topology (its scenario is "
          f"the only box){C['x']}")

    cw = max(len(lbl(s_)) for s_ in SCENARIO_POOL) + 2
    for loc in PLAN_LOCATIONS:
        d, part, pl = per_loc[loc]
        head = f"  {loc}"
        tail = f"{d:>3} / {pl:<3} {_bar(d, part, pl, 20, C)}"
        tail_plain = f"{d:>3} / {pl:<3} " + "#" * 20
        print()
        print(f"{C['c']}{C['b']}{head}{C['x']}{' ' * (W - len(head) - len(tail_plain))}{tail}")
        print(thin)
        print(f"  {C['d']}{'':<14}{'':<11}" + "".join(f"{lbl(s_):^{cw}}" for s_ in SCENARIO_POOL)
              + f"  last capture{C['x']}")
        for ti, topo in enumerate(PLAN_TOPOLOGIES):
            if ti:
                print()
            rows_ = [(atk, assign[(loc, topo, atk)]) for atk in PLAN_ATTACKS]
            rows_.append(("baseline", benign_for(assign, loc, topo)))
            for ri, (atk, scns) in enumerate(rows_):
                cells = ""
                for s_ in SCENARIO_POOL:
                    if s_ in scns:
                        plain, col = mark(atk, topo, loc, s_)
                    else:
                        plain, col = ".", f"{C['d']}.{C['x']}"
                    pad = cw - len(plain)
                    cells += " " * (pad // 2) + col + " " * (pad - pad // 2)
                name = "benign" if atk == "baseline" else atk
                topo_txt = f"{C['b']}{topo:<14}{C['x']}" if ri == 0 else " " * 14
                print(f"  {topo_txt}{C['d'] if atk == 'baseline' else ''}{name:<11}"
                      f"{C['x'] if atk == 'baseline' else ''}{cells}  "
                      f"{C['d']}{last_run(atk, topo, loc, scns)}{C['x']}")

    # ---- what needs a decision ---------------------------------------------
    planned_keys = set(build_plan(assign))
    off_plan = sorted({k for k in list(have) + list(attempted) if k not in planned_keys})
    near = []
    for k, rs in attempted.items():
        if have.get(k, 0) or k not in planned_keys:
            continue
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

    print()
    print(rule)
    if near:
        near.sort(key=lambda t: t[0])
        print(f"  {C['y']}{C['b']}NEEDS ATTENTION{C['x']}  {C['d']}data here that does not count yet - "
              f"cheapest fix first{C['x']}")
        for _rank, k, r in near[:12]:
            atk, topo, loc, scn = k
            what = f"{atk} / {topo} / {loc or '-'} / {lbl(scn)}"
            if r["verdict"] == "COMPLETE":
                why, colr = _not_done_reason(r), C["y"]
            else:
                why, colr = "RECAPTURE - " + _blocker_summary(r["reasons"]), C["m"]
            src = "" if scope == "live" else f"  [{r['source']}]"
            print(f"    {C['y']}[~]{C['x']} {what:<48}{colr}{why}{C['x']}{C['d']}{src}{C['x']}")
        if len(near) > 12:
            print(f"    {C['d']}... and {len(near) - 12} more - run with --plan for every reason.{C['x']}")
        print()
    if scope == "live" and first_open:
        loc = max(first_open, key=lambda l: (per_loc[l][0], -PLAN_LOCATIONS.index(l)))
        atk, topo, scn = first_open[loc]
        what = "benign" if atk == "baseline" else atk
        print(f"  {C['g']}{C['b']}NEXT CAPTURE{C['x']}     {C['b']}{what} / {topo} / {loc} / "
              f"{lbl(scn)}{C['x']}   {C['d']}run.ps1 -Scenario {scn}{C['x']}")
        print(f"  {C['d']}                 (the location with the most done runs, next slot in run "
              f"order){C['x']}")
    if off_plan:
        names = ", ".join(f"{a_}/{t_}/{l_ or '-'}/{lbl(s_)}" for a_, t_, l_, s_ in off_plan)
        print(C["d"] + fit(f"{len(off_plan)} cell(s) of real data outside the plan, not "
                           f"counted: {names}", "  OFF-PLAN         ", " " * 19) + C["x"])
    notes = []
    if scope == "live" and out_of_scope:
        notes.append(f"{out_of_scope} archived run(s) are not counted here (Campaign -> [4] archive).")
    if dup_srcs:
        notes.append(f"{len(dup_srcs)} duplicate copy/copies of one capture counted once.")
    notes.append("A [x] means complete + analysed, not verified: the REDO LIST (Campaign -> [5]) "
                 "says which done cells still need a recapture.")
    notes.append("Scenarios are drawn per cell (" + ", ".join(lbl(x) for x in SCENARIO_POOL)
                 + f") and fixed in tools\\{os.path.basename(PLAN_FILE)}.")
    print()
    for t in notes:
        print(C["d"] + fit(t, "  ", "  ") + C["x"])
    print(rule)
    print()

# ---------------------------------------------------------------------------
# Campaign status, sessions, board, dashboard JSON (oct. 7, 2026)
# ---------------------------------------------------------------------------
# One structured status feeds three views, so they can never disagree:
#   --board     coloured summary for the wizard (progress bars + next-run card)
#   --sessions  remaining runs grouped into field sessions (see SESSION ORDER)
#   --json PATH the same data for the shareable dashboard page
#
# SESSION ORDER - why runs are grouped this way
#   Every run already wipes + reflashes every board, so firmware changes cost
#   nothing extra between runs. What DOES cost time is physical:
#     1. travelling to a location            -> one location per session
#     2. re-placing 8 boards for a topology  -> one topology per session
#     3. wiring the A<->B UART tunnel cable  -> all wormhole runs back to back
#   So a session = one (location, topology): its blackhole runs, then the
#   matched benign runs (plain firmware, no attacker), then the wormhole runs
#   once the cable is wired. Inside each attack the drawn scenario order is
#   kept (campaign_plan.json "slot order = run order").
RUN_MIN = 17             # ~11 min experiment + roster wait, export, analysis
TOPOLOGY_SETUP_MIN = 20  # re-placing the boards for a new topology
TUNNEL_WIRING_MIN = 10   # wiring + checking the wormhole UART cable


def campaign_status(rows, assign, scope="live"):
    """Every planned run with its state, plus totals and the field sessions."""
    c = _classify(rows, scope)
    have, attempted, latest = c["have"], c["attempted"], c["latest"]

    def state(k):
        if have.get(k, 0):
            return "done"
        return "partial" if attempted.get(k) else "todo"

    def why(k):
        rs = attempted.get(k) or []
        if not rs:
            return ""
        r = rs[-1]
        if r["verdict"] == "COMPLETE":
            return _not_done_reason(r)
        return "re-capture: " + _blocker_summary(r["reasons"])

    slots = []
    for loc in PLAN_LOCATIONS:
        for topo in PLAN_TOPOLOGIES:
            for atk in PLAN_ATTACKS:
                for i, scn in enumerate(assign[(loc, topo, atk)]):
                    slots.append({"location": loc, "topology": topo, "attack": atk,
                                  "scenario": scn, "kind": "attack", "slot": i + 1})
            for scn in benign_for(assign, loc, topo):
                slots.append({"location": loc, "topology": topo, "attack": "baseline",
                              "scenario": scn, "kind": "benign", "slot": 0})
    for sl in slots:
        k = (sl["attack"], sl["topology"], sl["location"], sl["scenario"])
        sl["state"] = state(k)
        sl["why"] = why(k) if sl["state"] == "partial" else ""
        # which KIND of partial (user, oct. 17 2026: 'datasets not analysed yet ->
        # in progress'): 'analyse' = the latest capture is COMPLETE, only its
        # analysis is missing / older than the capture; 'recapture' = the capture
        # itself falls short. '' when not partial.
        rs = attempted.get(k) or []
        sl["stage"] = ("" if sl["state"] != "partial"
                       else "analyse" if rs and rs[-1]["verdict"] == "COMPLETE" else "recapture")
        sl["last"] = latest[k][0].strftime("%Y-%m-%d %H:%M") if k in latest else ""

    def count(items):
        return {"planned": len(items),
                "done": sum(1 for x in items if x["state"] == "done"),
                "partial": sum(1 for x in items if x["state"] == "partial")}

    per_loc = {loc: {"all": count([x for x in slots if x["location"] == loc]),
                     "attack": count([x for x in slots
                                      if x["location"] == loc and x["kind"] == "attack"]),
                     "benign": count([x for x in slots
                                      if x["location"] == loc and x["kind"] == "benign"])}
               for loc in PLAN_LOCATIONS}
    per_attack = {a: count([x for x in slots if x["attack"] == a])
                  for a in PLAN_ATTACKS + ["baseline"]}
    per_scenario = {scn: count([x for x in slots if x["scenario"] == scn])
                    for scn in SCENARIO_POOL}

    # Sessions: one per (location, topology) that still has work. The location
    # with the most progress comes first (fewest trips), started sessions before
    # new ones, then topologies in plan order.
    sessions = []
    for loc in PLAN_LOCATIONS:
        for topo in PLAN_TOPOLOGIES:
            cell = [x for x in slots if x["location"] == loc and x["topology"] == topo]
            order = ([x for x in cell if x["attack"] == "blackhole"]
                     + [x for x in cell if x["kind"] == "benign"]
                     + [x for x in cell if x["attack"] == "wormhole"])
            left = [x for x in order if x["state"] != "done"]
            if not left:
                continue
            started = any(x["state"] != "todo" for x in cell)
            wired = any(x["attack"] == "wormhole" for x in left)
            minutes = (len(left) * RUN_MIN + (0 if started else TOPOLOGY_SETUP_MIN)
                       + (TUNNEL_WIRING_MIN if wired else 0))
            sessions.append({"location": loc, "topology": topo, "runs": left,
                             "remaining": len(left), "planned": len(cell),
                             "done": len(cell) - len(left), "minutes": minutes,
                             "started": started})
    loc_rank = {loc: per_loc[loc]["all"]["done"] for loc in PLAN_LOCATIONS}
    sessions.sort(key=lambda se: (-loc_rank[se["location"]],
                                  PLAN_LOCATIONS.index(se["location"]),
                                  not se["started"],
                                  PLAN_TOPOLOGIES.index(se["topology"])))
    for i, se in enumerate(sessions):
        se["n"] = i + 1

    nxt = None
    for se in sessions:
        cand = [x for x in se["runs"] if x["state"] == "todo"] or se["runs"]
        if cand:
            nxt = dict(cand[0], session=se["n"])
            break

    return {
        "scope": scope,
        "plan_file": os.path.basename(PLAN_FILE),
        "locations": PLAN_LOCATIONS, "topologies": PLAN_TOPOLOGIES,
        "attacks": PLAN_ATTACKS, "scenarios": SCENARIO_POOL,
        "skip": PLAN_SKIP, "plan_all": PLAN_ALL,
        "benign": {f"{loc}/{topo}": benign_for(assign, loc, topo)
                   for loc in PLAN_LOCATIONS for topo in PLAN_TOPOLOGIES},
        "run_minutes": RUN_MIN,
        "total": count(slots),
        "attack_total": count([x for x in slots if x["kind"] == "attack"]),
        "benign_total": count([x for x in slots if x["kind"] == "benign"]),
        "hours_left": round(sum(se["minutes"] for se in sessions) / 60, 1),
        "remaining": sum(1 for x in slots if x["state"] != "done"),
        "per_location": per_loc, "per_attack": per_attack, "per_scenario": per_scenario,
        "slots": slots, "sessions": sessions, "next": nxt,
    }


def _ansi(on):
    keys = ("b", "d", "g", "y", "c", "m", "x")
    if not on:
        return {k: "" for k in keys}
    return dict(zip(keys, ("\033[1m", "\033[2m", "\033[32m", "\033[33m",
                           "\033[36m", "\033[35m", "\033[0m")))


def _bar(done, partial, planned, width, C):
    if planned <= 0:
        return " " * width
    nd = round(width * done / planned)
    npart = min(width - nd, round(width * partial / planned))
    return (f"{C['g']}{'#' * nd}{C['y']}{'~' * npart}{C['d']}"
            f"{'.' * (width - nd - npart)}{C['x']}")


def _run_tag(x, C):
    a = {"blackhole": "BH", "wormhole": "WH", "baseline": "benign"}[x["attack"]]
    tag = f"{a} {lbl(x['scenario'])}"
    return f"{C['y']}{tag}{C['x']}" if x["state"] == "partial" else tag


def report_board(st, color=True, sessions_shown=3):
    """Short coloured summary: total, one bar per location, next run, next sessions."""
    C = _ansi(color)
    t = st["total"]
    pct = 100 * t["done"] / t["planned"] if t["planned"] else 0
    print()
    print(f"  {C['b']}CAMPAIGN{C['x']}  {t['done']}/{t['planned']} done ({pct:.0f}%)"
          f"  ·  {st['remaining']} left  ·  ~{st['hours_left']:.0f} h")
    print()
    for loc in st["locations"]:
        pl = st["per_location"][loc]["all"]
        print(f"  {loc:<13}{_bar(pl['done'], pl['partial'], pl['planned'], 24, C)}"
              f"  {pl['done']}/{pl['planned']}")
    n = st["next"]
    if n:
        what = "BENIGN" if n["kind"] == "benign" else n["attack"].upper()
        print()
        print(f"  {C['m']}NEXT{C['x']}  {C['b']}{what} · {n['topology']} · {n['location']} · "
              f"{lbl(n['scenario'])}{C['x']}")
    if st["sessions"]:
        print()
        for se in st["sessions"][:sessions_shown]:
            print(f"  {se['n']:>2}. {se['location']} {se['topology']:<13}"
                  f"{se['remaining']:>2} runs  {se['minutes'] / 60:.1f} h")
        more = len(st["sessions"]) - sessions_shown
        if more > 0:
            print(f"  {C['d']}    +{more} more sessions{C['x']}")
    print()


def report_sessions(st, color=True):
    """Every remaining run, one session (location + topology) per block."""
    C = _ansi(color)
    print()
    print(f"  {C['b']}SESSIONS{C['x']}  {st['remaining']} runs  ·  ~{st['hours_left']:.0f} h"
          f"  {C['d']}(order: BH -> benign -> WH){C['x']}")
    for se in st["sessions"]:
        print()
        print(f"  {C['c']}{se['n']:>2}. {se['location']} / {se['topology']}{C['x']}"
              f"  {C['d']}{se['minutes'] / 60:.1f} h{C['x']}")
        print("      " + "  ·  ".join(_run_tag(x, C) for x in se["runs"]))
    print()


def _write_status_json(st, path):
    import json
    from datetime import datetime
    out = dict(st, generated=datetime.now().strftime("%Y-%m-%d %H:%M"))
    with open(path, "w", encoding="utf-8") as fh:
        json.dump(out, fh, indent=1, default=str)
    print(f"  campaign status -> {path}")


def main():
    ap = argparse.ArgumentParser(
        description="Inventory every experimental cell against the M4/M5 criteria.")
    ap.add_argument("--exports", default=os.path.join(_REPO, "datasets", "exports"),
                    help="Live exports root (default: datasets/exports).")
    ap.add_argument("--archive", default=os.path.join(_REPO, "datasets", "archive"),
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
                    help="Checklist to print: live (datasets/exports + datasets/analysis, the "
                         "default) or archive (archive/*/exports + their analysis).")
    ap.add_argument("--reshuffle", action="store_true",
                    help="Re-draw the randomised scenario plan (campaign_plan.json). "
                         "Only before the campaign starts - it moves every target.")
    ap.add_argument("--seed", type=int, default=None,
                    help="Seed for a new/reshuffled plan (default: random, recorded).")
    ap.add_argument("--repeats", type=int, default=1,
                    help="Planned repeats per (location, topology, attack, scenario) "
                         "cell. 1 => 96 attack + 12 benign runs; 4 => 4x. See --plan.")
    ap.add_argument("--plan", action="store_true",
                    help="Also print the campaign matrix (4 locations x 4 topologies "
                         "x 2 attacks x 4 scenarios) and what is still missing.")
    ap.add_argument("--board", action="store_true",
                    help="Coloured campaign summary: progress bars, next run, next sessions "
                         "(what run_wizard.ps1's Campaign progress shows first).")
    ap.add_argument("--sessions", action="store_true",
                    help="Every remaining run grouped into field sessions "
                         "(one location + topology each).")
    ap.add_argument("--json", default=None, metavar="PATH",
                    help="Write the campaign status (slots, totals, sessions) as JSON, "
                         "for the dashboard page.")
    ap.add_argument("--no-color", action="store_true", help="Plain text, no ANSI colours.")
    ap.add_argument("--set-skip", default=None, metavar="JSON",
                    help='Plan settings: take items out of the plan, e.g. \'{"scenarios": ["jitter"]}\' '
                         '(keys: scenarios, locations, topologies, attacks; "{}" = full plan). '
                         'Writes campaign_plan.json "skip"; commit it so every laptop has the same plan.')
    ap.add_argument("--draw-benign", action="store_true",
                    help="Print a fresh benign assignment as JSON (one per location/topology, "
                         "per topology 3 different scenarios; captured benign runs pinned). Writes nothing.")
    ap.add_argument("--set-benign", default=None, metavar="JSON",
                    help='Save the benign assignment, e.g. \'{"G402/tree": "highload"}\' (only the given '
                         'slots change). Writes campaign_plan.json "benign".')
    args = ap.parse_args()
    if args.draw_benign:
        import json
        import random
        print(json.dumps({"benign": _draw_benign(None, args.seed if args.seed is not None
                                                 else random.SystemRandom().randrange(1, 10**9),
                                                 captured_benign()),
                          "captured": captured_benign(), "scenarios": SCENARIO_POOL}))
        return
    if args.set_benign is not None:
        import json
        new = write_plan_benign(json.loads(args.set_benign))
        print(f"benign plan saved: {len(new)} runs")
        return
    if args.set_skip is not None:
        import json
        clean = write_plan_skip(json.loads(args.set_skip))
        print("plan settings saved: " + (", ".join(f"no {k}: {', '.join(v)}" for k, v in clean.items() if v) or "full plan"))
        return
    summary_only = bool(args.board or args.sessions or args.json) and not (
        args.checklist or args.plan or args.csv or args.reshuffle)
    # oct. 17 2026: --checklist on its own is a VIEW (wizard Campaign -> [2]);
    # the per-run inventory table in front of it was most of the "messy".
    checklist_only = args.checklist and not (args.plan or args.csv or args.reshuffle)

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
            "when": stats["when"],
            "reasons": "; ".join(reasons),
        })

    if summary_only:
        st = campaign_status(rows, load_plan(False, None), args.scope)
        color = not args.no_color
        if color and os.name == "nt":
            os.system("")   # switches the Windows console into ANSI (VT) mode
        if args.board:
            report_board(st, color)
        if args.sessions:
            report_sessions(st, color)
        if args.json:
            _write_status_json(st, args.json)
        return 0

    if checklist_only:
        color = not args.no_color and sys.stdout.isatty() and not os.environ.get("NO_COLOR")
        if color and os.name == "nt":
            os.system("")
        report_checklist(rows, load_plan(False, None), args.repeats, args.scope, color=color)
        return 0

    print()
    print("=" * 118)
    print("  EXPERIMENTAL CELL INVENTORY  —  M4 (>=24 complete runs) / M5 (>=95% coverage)")
    print("=" * 118)
    # Every column sized from its widest value + 2 spaces. Fixed widths broke
    # the table (oct. 1, 2026): 'stationary' is exactly 10 chars and ran into
    # the repeat number ('stationary1'), and the pre-redesign archive's long
    # topology folder names pushed every later column out of line.
    def _w(key, title):
        return max([len(str(r[key])) for r in rows] + [len(title)]) + 2
    w_src, w_atk, w_top = _w("source", "source"), _w("attack", "attack"), _w("topology", "topology")
    w_loc, w_scn, w_rep = _w("location", "loc"), _w("scenario", "scn"), _w("repeat", "r")
    w_kid, w_arr = _w("children", "kids"), _w("arrivals_rows", "arr")
    header = (f"  {'source':<{w_src}}{'attack':<{w_atk}}{'topology':<{w_top}}{'loc':<{w_loc}}"
              f"{'scn':<{w_scn}}{'r':<{w_rep}}{'kids':<{w_kid}}{'arr':<{w_arr}}{'v'}")
    print(header)
    print("  " + "-" * (len(header) - 2))
    for r in rows:
        mark = "OK " if r["verdict"] == "COMPLETE" else "-- "
        print(f"  {r['source']:<{w_src}}{r['attack']:<{w_atk}}{r['topology']:<{w_top}}"
              f"{r['location']:<{w_loc}}{r['scenario']:<{w_scn}}{str(r['repeat']):<{w_rep}}"
              f"{str(r['children']):<{w_kid}}{str(r['arrivals_rows']):<{w_arr}}{mark}")
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
    print(f"  LIVE (datasets/exports)  runs: {len(live):<4} complete captures: {len(live_complete):<4}"
          f" DONE (complete + analysed): {len(live_done)}   (M4 target: 24)")
    print(f"  ARCHIVE (archive/*)   runs: {len(arch):<4} complete captures: {len(arch_complete):<4}"
          f" (never counted on the live checklist)")
    print(f"  live locations        : {len(locations)} "
          f"({', '.join(sorted(locations)) if locations else 'none'})")
    print("=" * 118)
    print("  Archived runs are real captures - archive.ps1 MOVES them, it does not discard")
    print("  them - but only datasets/exports/ counts toward the live checklist.")
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

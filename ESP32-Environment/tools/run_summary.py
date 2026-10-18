#!/usr/bin/env python3
"""run_summary.py — one health card per run: is every board's capture complete?

The check a person otherwise does by hand after an import (oct. 18 2026: seven
children of wormhole/linear/DLSU_Library/highload, read one by one): for every
board's telemetry file in one export folder, how many rows per phase, which
role it logged in each phase, and whether all boards saw the SAME schedule.
Nothing is changed - it only reads exports/<attack>/<topology>/<location>/<scenario>/.

    python tools/run_summary.py datasets/exports/wormhole/linear/DLSU_Library/highload
    python tools/run_summary.py <folder> --json out.json --expect 8

Per board: rows, phase counts (255 stabilise, 0 baseline, 1/2 attack,
3 cooldown), roles per phase, seconds covered. Run checks:
  * every board has baseline, attack (not for a baseline run) and cooldown
  * attack / cooldown row counts agree across boards (one schedule, one run)
  * one file per board (a second file = another run or a reboot piece)
  * --expect N boards present (root + children, e.g. from the preset)
Exit 0 = complete, 1 = something to look at, 2 = nothing readable.
"""
import argparse
import csv
import glob
import json
import os
import re
import sys

PHASE_NAMES = {255: "stabilise", 0: "baseline", 1: "blackhole", 2: "wormhole", 3: "cooldown", 4: "terminate"}
ATTACK_PHASE = {"blackhole": 1, "wormhole": 2}
SAMPLE_HZ = 10
# A board that missed a few broadcasts still has the same schedule; a board from
# ANOTHER run (another flash, a jitter draw) differs by far more than this.
SAME_SCHEDULE_TOL = 0.10


def read_board(path):
    """{node, rows, phases{id: n}, roles{id: [role...]}, seconds, last_phase} for one telem CSV."""
    phases, roles = {}, {}
    rows = 0
    old_rows = 0          # rows of an EARLIER root session at the top of the file (see below)
    seen_real = False
    node = ""
    t0 = t1 = None
    last = None
    with open(path, newline="", encoding="utf-8", errors="replace") as fh:
        rd = csv.DictReader(fh)
        for r in rd:
            try:
                ph = int(r.get("phase_id") or 255)
                ts = int(r.get("timestamp_us") or 0)
            except ValueError:
                continue
            # Same rule as analysis/preprocess.py (root restart): a board that kept
            # running while the root was re-flashed logs <old phases> -> 255 -> 0 ...
            # in ONE file. Everything up to the last 255 that follows a real phase is
            # the earlier session - excluded by the analysis, so not counted here.
            if ph == 255 and seen_real and last != 255:
                old_rows += rows
                phases, roles, rows, t0 = {}, {}, 0, None
            seen_real = seen_real or ph != 255
            rows += 1
            node = node or (r.get("node_id") or "")
            phases[ph] = phases.get(ph, 0) + 1
            role = (r.get("role") or "").strip()
            if role:
                roles.setdefault(ph, {})
                roles[ph][role] = roles[ph].get(role, 0) + 1
            t0 = ts if t0 is None else min(t0, ts)
            t1 = ts if t1 is None else max(t1, ts)
            last = ph
    return {
        "file": os.path.basename(path),
        "node": node.replace("NODE_", ""),
        "rows": rows,
        "phases": phases,
        "roles": {ph: sorted(rs, key=lambda k: -rs[k]) for ph, rs in roles.items()},
        "seconds": round((t1 - t0) / 1e6) if rows else 0,
        "last_phase": last,
        "old_rows": old_rows,
    }


def summarise(folder, expect=None):
    parts = os.path.normpath(folder).split(os.sep)
    attack = next((p for p in parts if p in ("baseline", "blackhole", "wormhole")), "")
    files = sorted(f for f in glob.glob(os.path.join(folder, "*_telem.csv")))
    boards = [read_board(f) for f in files]
    boards = [b for b in boards if b["rows"]]
    issues, notes = [], []
    for b in boards:
        if b["old_rows"]:
            notes.append(f"{_short(b['node'])}: the first {b['old_rows']:,} rows are an EARLIER root session (it kept running while the "
                         f"root was re-flashed) - excluded by the analysis (root-restart rule), not counted above")
    by_node = {}
    for b in boards:
        by_node.setdefault(b["node"] or b["file"], []).append(b)
    for node, bs in by_node.items():
        if len(bs) > 1:
            issues.append(f"{_short(node)}: {len(bs)} files in this folder (another run or a reboot piece) - the analysis takes ONE per board")

    want_attack = ATTACK_PHASE.get(attack)
    for b in boards:
        miss = []
        if not b["phases"].get(0):
            miss.append("baseline")
        if want_attack and not b["phases"].get(want_attack):
            other = [p for p in (1, 2) if b["phases"].get(p)]
            miss.append(f"attack (has phase {other[0]} instead)" if other else "attack")
        if not b["phases"].get(3):
            miss.append("cooldown")
        b["missing"] = miss
        if miss:
            issues.append(f"{_short(b['node'])}: missing {', '.join(miss)}")

    # one schedule: the attack and cooldown lengths every complete board saw
    for ph in [p for p in (want_attack, 3) if p]:
        counts = [b["phases"].get(ph, 0) for b in boards if b["phases"].get(ph)]
        if len(counts) < 2:
            continue
        med = sorted(counts)[len(counts) // 2]
        for b in boards:
            n = b["phases"].get(ph, 0)
            if n and abs(n - med) > SAME_SCHEDULE_TOL * med:
                issues.append(f"{_short(b['node'])}: {PHASE_NAMES.get(ph, ph)} {n:,} rows vs {med:,} on the other boards "
                              f"(~{n / SAMPLE_HZ:.0f} s vs ~{med / SAMPLE_HZ:.0f} s) - a different run, or it stalled")

    if attack == "wormhole":
        ends = {}
        for b in boards:
            for r in b["roles"].get(2, []) + b["roles"].get(0, []):
                if r.startswith("wormhole_"):
                    ends.setdefault(r, set()).add(b["node"])
        for need in ("wormhole_a", "wormhole_b"):
            if need not in ends:
                issues.append(f"no board logged as {need} in baseline/attack - tunnel end missing")
            elif len(ends[need]) > 1:
                issues.append(f"{len(ends[need])} boards logged as {need}: " + ", ".join(_short(n) for n in sorted(ends[need])))
    if expect and len(by_node) < expect:
        issues.append(f"{len(by_node)} of {expect} expected boards are here - {expect - len(by_node)} not imported yet")
    return {"folder": folder, "attack": attack, "boards": boards, "issues": issues, "notes": notes,
            "complete": bool(boards) and not issues}


def _short(mac):
    m = re.sub(r"[^0-9A-Fa-f]", "", mac or "")
    return (m[:2] + ":" + m[-2:]).upper() if len(m) >= 12 else (mac or "?")


def render(s):
    out = [f"RUN SUMMARY  {s['folder']}", ""]
    hdr = f"  {'board':<8} {'role':<12} {'rows':>7}  {'stab':>5} {'base':>6} {'attack':>6} {'cool':>5}  {'secs':>5}  status"
    out += [hdr, "  " + "-" * (len(hdr) - 2)]
    ap = ATTACK_PHASE.get(s["attack"])
    for b in sorted(s["boards"], key=lambda b: (0 if "root" in str(b["roles"].get(0, [""])[:1]) else 1, b["node"])):
        role = (b["roles"].get(0) or b["roles"].get(ap or 1) or b["roles"].get(255) or ["?"])[0]
        att = b["phases"].get(ap, 0) if ap else b["phases"].get(1, 0) + b["phases"].get(2, 0)
        st = "OK" if not b["missing"] else "missing " + ", ".join(b["missing"])
        out.append(f"  {_short(b['node']):<8} {role:<12} {b['rows']:>7,}  {b['phases'].get(255, 0):>5,} {b['phases'].get(0, 0):>6,} "
                   f"{att:>6,} {b['phases'].get(3, 0):>5,}  {b['seconds']:>5}  {st}")
    out.append("")
    if s["complete"]:
        out.append(f"RESULT: COMPLETE - all {len(s['boards'])} board(s) hold the whole run (baseline, attack, cooldown, one schedule).")
    elif not s["boards"]:
        out.append("RESULT: NO DATA - no telemetry file with rows in this folder.")
    else:
        out.append(f"RESULT: LOOK - {len(s['issues'])} thing(s) to check:")
        out += [f"  - {i}" for i in s["issues"]]
    if s.get("notes"):
        out += ["", "NOTES (not problems):"] + [f"  - {n}" for n in s["notes"]]
    return "\n".join(out)


def main():
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(errors="replace")
    ap = argparse.ArgumentParser(description="Per-board health card for one export folder (read-only).")
    ap.add_argument("folder")
    ap.add_argument("--expect", type=int, default=None, help="boards the run should have (root + children)")
    ap.add_argument("--json", metavar="PATH")
    a = ap.parse_args()
    if not os.path.isdir(a.folder):
        print(f"ERROR: {a.folder} is not a folder", file=sys.stderr)
        return 2
    s = summarise(a.folder, a.expect)
    print(render(s))
    if a.json:
        with open(a.json, "w", encoding="utf-8") as fh:
            json.dump(s, fh, indent=1, default=str)
    if not s["boards"]:
        return 2
    return 0 if s["complete"] else 1


if __name__ == "__main__":
    sys.exit(main())

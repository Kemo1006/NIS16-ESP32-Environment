"""
phase_summary.py - per-file phase coverage of one run folder, as JSON (read-only).

run_gui.ps1's Verify & analyse page draws a phase timeline bar per board from
this (oct. 17 2026): which phases each telemetry file holds, for how long, so a
board missing its baseline / attack / cooldown is visible before the numbers
are trusted.

    python phase_summary.py <folder>        # prints one JSON list

Each entry: file, node (NODE_<mac>), role, rows, seconds (first -> last
timestamp), seq (phases in the order they appear), phases {phase_id: rows}.
Phase ids as in the CSV: 255 stabilise, 0 baseline, 1 blackhole, 2 wormhole,
3 cooldown, 4 terminate. Nothing is written.
"""

import csv
import glob
import json
import os
import sys


def summarise(path):
    rows = 0
    phases = {}
    seq = []
    node = role = ""
    t0 = t1 = None
    with open(path, encoding="utf-8", errors="replace", newline="") as f:
        rd = csv.reader(f)
        head = next(rd, None)
        if not head:
            return None
        idx = {name: i for i, name in enumerate(head)}
        ip, it = idx.get("phase_id"), idx.get("timestamp_us")
        inode, irole = idx.get("node_id"), idx.get("role")
        for r in rd:
            if ip is None or len(r) <= ip:
                continue
            rows += 1
            p = r[ip]
            phases[p] = phases.get(p, 0) + 1
            if not seq or seq[-1] != p:
                seq.append(p)
            if not node and inode is not None and len(r) > inode:
                node = r[inode]
                role = r[irole] if irole is not None and len(r) > irole else ""
            if it is not None and len(r) > it:
                try:
                    t = int(r[it])
                    t0 = t if t0 is None else t0
                    t1 = t
                except ValueError:
                    pass
    secs = round((t1 - t0) / 1e6, 1) if t0 is not None and t1 is not None else None
    return {"file": os.path.basename(path), "node": node, "role": role, "rows": rows,
            "seconds": secs, "seq": seq, "phases": phases}


def main():
    if len(sys.argv) < 2:
        print("usage: phase_summary.py <folder>", file=sys.stderr)
        return 2
    folder = sys.argv[1]
    out = []
    for p in sorted(glob.glob(os.path.join(folder, "*_telem.csv"))):
        s = summarise(p)
        if s:
            out.append(s)
    print(json.dumps(out))
    return 0


if __name__ == "__main__":
    sys.exit(main())

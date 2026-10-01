#!/usr/bin/env python3
"""verify_burst.py - did the burst scenario actually FIRE in this capture?

Why this exists (oct. 1, 2026): two star/G402 "burst" runs were captured, analysed
and pushed before anyone noticed that no board had been built with -ScenarioTarget,
so nothing burst and the runs were really stationary. Nothing on screen said so.

How it decides - from the ROOT's arrivals CSV only, so it also works when the burst
lands inside a blackhole attack window (the attacker drops it and the root never
sees a single burst probe):

    Every victim numbers its probes (seq_num) and sends one per PROBE_INTERVAL.
    Between two consecutive probes the root receives from the same victim,
    seq_num advances by about the elapsed seconds. Dropped probes do not change
    that (seq counts what was SENT). The burst sender, however, sends BURST_COUNT
    (300) extra probes in a few seconds, so its seq_num runs ~300 ahead of the
    clock. excess = sum(d_seq - d_t / interval) over consecutive arrivals.
        ~0    -> normal victim
        ~+300 -> the burst sender

Exit codes: 0 = burst fired, 1 = NO burst fired, 2 = cannot tell (no arrivals file).

Usage:
    python tools/verify_burst.py datasets/exports/blackhole/star/G402/burst
    python tools/verify_burst.py <cell dir> --repeat 2
"""
import argparse
import csv
import glob
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from mesh_constants import mesh_config_int  # noqa: E402

BURST_COUNT = mesh_config_int("BURST_COUNT", 300)
PROBE_INTERVAL_S = 1.0       # burst runs use the normal 1000 ms interval (never highload)
FIRED_AT = BURST_COUNT // 2  # half the burst is unmistakable; normal victims stay within a few


def excess_per_source(path):
    """{src_mac: excess probes} from one root arrivals CSV."""
    last = {}
    excess = {}
    with open(path, newline="", encoding="utf-8-sig", errors="replace") as f:
        for r in csv.DictReader(f):
            try:
                src, seq, t = r["src_mac"], int(r["seq_num"]), int(r["timestamp_us"])
            except (KeyError, TypeError, ValueError):
                continue
            if src in last:
                pseq, pt = last[src]
                d_seq, d_t = seq - pseq, (t - pt) / 1e6
                # d_seq <= 0: duplicate or the victim rebooted (seq restarted) - not a burst.
                if d_seq > 0 and d_t >= 0:
                    excess[src] = excess.get(src, 0.0) + d_seq - d_t / PROBE_INTERVAL_S
            else:
                excess.setdefault(src, 0.0)
            last[src] = (seq, t)
    return excess


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("directory", help="cell export folder holding root_*_arrivals.csv")
    ap.add_argument("--repeat", type=int, help="only this repeat (r<N> in the filename)")
    args = ap.parse_args()

    files = sorted(glob.glob(os.path.join(args.directory, "root_*_arrivals.csv")))
    if args.repeat is not None:
        files = [p for p in files if re.search(r"_r%d_" % args.repeat, os.path.basename(p))]
    if not files:
        print("BURST: cannot tell - no root_*_arrivals.csv in %s" % args.directory)
        return 2

    all_fired = True
    for path in files:
        ex = excess_per_source(path)
        rep = re.search(r"_r(\d+)_", os.path.basename(path))
        print("BURST check - %s%s" % (os.path.basename(path), " (r%s)" % rep.group(1) if rep else ""))
        for src, e in sorted(ex.items(), key=lambda kv: -kv[1]):
            tag = "  << BURST SENDER" if e >= FIRED_AT else ""
            print("    %s  extra probes %+6.0f%s" % (src, e, tag))
        senders = [s for s, e in ex.items() if e >= FIRED_AT]
        if senders:
            print("  BURST FIRED - sender %s (~%d extra probes expected)." % (", ".join(senders), BURST_COUNT))
        else:
            all_fired = False
            print("  NO BURST FIRED - no victim sent the ~%d extra probes." % BURST_COUNT)
            print("  Either no board was built as the burst TARGET (run.ps1 -ScenarioTarget), or the")
            print("  sender's firmware predates the oct. 1, 2026 burst-window fix (victim_main.c never")
            print("  opened the window on an attack run). This capture is effectively STATIONARY -")
            print("  do not file or report it as burst.")
    return 0 if all_fired else 1


if __name__ == "__main__":
    sys.exit(main())

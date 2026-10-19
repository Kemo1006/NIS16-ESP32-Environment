#!/usr/bin/env python3
"""root_match.py - is a child's telemetry file from the SAME run as the root's arrivals?

oct. 19 2026 (verification #60): wormhole/partial_mesh/G402/stationary was run twice
an hour apart. Two children's files came from the first attempt (one picked by
Collect, one imported by hand) next to the root of the second. Nothing caught it:
both looked complete, and a card cannot say which attempt a file belongs to.

The root logs every probe it receives (src_mac, seq_num) with ITS phase at arrival.
A child's telemetry row carries ITS phase and how many probes it has sent so far
(probes_count). For the right file, the phase the child was in when it sent probe
n equals the root's phase when probe n arrived - except a handful sent in the last
instant of a phase. For a file of another attempt the seq numbers belong to other
probes, so whole minutes around every phase change disagree.

    python tools/root_match.py <child_telem.csv> <root_arrivals.csv | run folder>

Measured on the oct. 19 run: the 5 right files 0.0 % different; the 2 wrong ones
9.6 % and 18.9 %. A file is MISMATCH above MISMATCH_MAX; UNKNOWN when fewer than
MIN_COMPARED probes can be compared. MISMATCH = another run OR a board whose own
phase labels drifted from the root's (oct. 19 tree run: 2805 after two brownouts) -
either way its labels cannot be used as they are. UNKNOWN: a wormhole A / blackhole
attacker sends no probes of its own, a board never reached the root, or there are no
root arrivals yet. A board that REBOOTED restarts its seq at 1: the root's arrivals are
split at every restart and the file is judged on the boot that agrees best.
"""
import glob
import os
import sys

import pandas as pd

MISMATCH_MAX = 0.03      # right files: 0.0 %; wrong-run files on oct. 19: 9.6 % / 18.9 %
MIN_COMPARED = 60        # probes; fewer = no judgement
SEQ_RESTART = 50         # seq falling back by more than this = the board rebooted
REAL_PHASES = (0, 1, 2, 3)


def find_arrivals(folder):
    """Every root arrivals CSV in a run folder (more than one = more than one run in it)."""
    return sorted(glob.glob(os.path.join(folder, "*_arrivals.csv")))


def _mac_of(node_id):
    h = "".join(c for c in str(node_id).upper() if c in "0123456789ABCDEF")[-12:]
    return ":".join(h[i:i + 2] for i in range(0, 12, 2)) if len(h) == 12 else ""


_ARR_CACHE = {}


def _arrivals(path):
    key = (path, os.path.getmtime(path))
    if key not in _ARR_CACHE:
        a = pd.read_csv(path, usecols=["src_mac", "seq_num", "phase_id"], dtype=str, on_bad_lines="skip")
        a["seq_num"] = pd.to_numeric(a["seq_num"], errors="coerce")
        a["phase_id"] = pd.to_numeric(a["phase_id"], errors="coerce")
        a["src_mac"] = a["src_mac"].str.upper()
        _ARR_CACHE.clear()
        _ARR_CACHE[key] = a.dropna()
    return _ARR_CACHE[key]


def check(telem_csv, arrivals):
    """{verdict: MATCH | MISMATCH | UNKNOWN, compared, different, pct, why, root}.

    arrivals = one root arrivals CSV, or a run folder: then the file is checked against
    EVERY root in it and the best match wins (root = which arrivals file matched)."""
    paths = find_arrivals(arrivals) if arrivals and os.path.isdir(arrivals) else         ([arrivals] if arrivals and os.path.exists(arrivals) else [])
    if not paths:
        return {"verdict": "UNKNOWN", "compared": 0, "different": 0, "pct": 0.0, "root": "",
                "why": "no root arrivals file to compare with (export the root first)"}
    results = [dict(_check_one(telem_csv, p), root=os.path.basename(p)) for p in paths]
    rank = {"MATCH": 0, "MISMATCH": 1, "UNKNOWN": 2}
    return min(results, key=lambda r: (rank[r["verdict"]], r["pct"]))


def _check_one(telem_csv, arrivals):
    try:
        t = pd.read_csv(telem_csv, usecols=lambda c: c in ("node_id", "role", "probes_count", "retry_count",
                                                            "phase_id"), dtype=str, on_bad_lines="skip")
    except (ValueError, OSError) as e:
        return {"verdict": "UNKNOWN", "compared": 0, "different": 0, "pct": 0.0, "why": f"unreadable: {e}"}
    role = str(t["role"].mode().iloc[0]).lower() if not t.empty else ""
    if t.empty or role == "root":
        return {"verdict": "UNKNOWN", "compared": 0, "different": 0, "pct": 0.0, "why": "the root itself"}
    mac = _mac_of(t["node_id"].iloc[0])
    for c in ("probes_count", "retry_count", "phase_id"):
        if c in t.columns:
            t[c] = pd.to_numeric(t[c], errors="coerce")
    # The probe's seq_num goes up on EVERY attempt, probes_count only on a successful
    # send; a failed send is counted in retry_count (victim_main.c). So for a plain child
    # seq = probes_count + retry_count - a board with failed sends before it joined the
    # mesh otherwise looks ~17 % out of step (oct. 19: B768 / FE90 / 2805 - false alarms).
    # A wormhole end's retry column counts something else; its probes_count IS the seq.
    if role.startswith("wormhole") or "retry_count" not in t.columns:
        t["_seq"] = t["probes_count"]
    else:
        t["_seq"] = t["probes_count"] + t["retry_count"]
    sent_in = t.dropna(subset=["_seq", "phase_id"]).drop_duplicates("_seq").set_index("_seq")["phase_id"]
    a = _arrivals(arrivals)
    g = a[(a["src_mac"] == mac) & a["phase_id"].isin(REAL_PHASES)]
    # A board that REBOOTED restarts its probe numbers at 1, so the root's arrivals hold
    # the same seq twice (oct. 19 tree run, 2805: two brownouts -> a false 34 %). Split
    # them at every restart (seq falls back by > SEQ_RESTART) and judge the file on the
    # boot it holds: the segment that agrees best.
    seq = g["seq_num"].to_numpy()
    epoch, top, ep = [], -1, 0
    for v in seq:
        if top >= 0 and v < top - SEQ_RESTART:
            ep, top = ep + 1, -1
        top = max(top, v)
        epoch.append(ep)
    g = g.assign(_ep=epoch)
    best = None
    for _e, ge in g.groupby("_ep"):
        ph = ge["seq_num"].map(sent_in)
        ok = ph.isin(REAL_PHASES)
        k = int(ok.sum())
        if k == 0:
            continue
        d = int((ge.loc[ok, "phase_id"].values != ph[ok].values).sum())
        cand = (k >= MIN_COMPARED, -(d / k), k, d)
        best = cand if best is None or cand > best else best
    n = best[2] if best else 0
    if n < MIN_COMPARED:
        return {"verdict": "UNKNOWN", "compared": n, "different": 0, "pct": 0.0,
                "why": f"only {n} of its probes can be compared with the root's (it sends none of its own, e.g. a "
                       f"wormhole A or a blackhole attacker, or none reached the root)"}
    diff = best[3]
    pct = diff / n
    if pct > MISMATCH_MAX:
        return {"verdict": "MISMATCH", "compared": n, "different": diff, "pct": pct,
                "why": (f"{diff} of {n} probes ({100 * pct:.1f} %) were sent in a different phase than the root "
                        f"was in when they arrived (a right, in-sync file is ~0 %): this file is from ANOTHER run "
                        f"than the root's, or the board's phase labels were out of sync (e.g. after a reboot)")}
    return {"verdict": "MATCH", "compared": n, "different": diff, "pct": pct,
            "why": f"{n} probes compared, {100 * pct:.1f} % in a different phase - same run as the root"}


def main():
    if len(sys.argv) != 3:
        print(__doc__)
        return 2
    r = check(sys.argv[1], sys.argv[2])
    print(f"{r['verdict']}: {r['why']}")
    return {"MATCH": 0, "UNKNOWN": 0, "MISMATCH": 1}[r["verdict"]]


if __name__ == "__main__":
    sys.exit(main())

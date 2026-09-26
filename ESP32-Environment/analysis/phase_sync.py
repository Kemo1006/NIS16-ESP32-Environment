"""
phase_sync.py -- is every node's phase LABEL the root's phase at that moment?

WHY THIS EXISTS (blackhole/linear/G402, sep. 25, 2026). One child
(NODE_20500DE70C80) entered baseline, attack and cooldown ~110 s BEFORE the
root that ran the capture did. Its file was internally perfect -- 60 s
stabilise, 300 s baseline, 180 s attack, 120 s cooldown, no reboot -- so every
per-file check passed, yet ~105 of its "attack" windows were really baseline
and ~107 of its "cooldown" windows were the real attack. Its PDR row
(0.526 baseline / 0.583 attack, for a node the root proves lost EVERY probe in
the attack) got the whole PDR feature excluded. Nothing reported it.

HOW IT IS DETECTED, WITHOUT A SHARED CLOCK. The boards share no clock
(see thesis_no_cross_node_clock_join), but each probe carries its sender's
own send time and the root logs latency_us = root_now - send_ts_us, so

    send_ts (SENDER's clock) = arrival timestamp_us - latency_us

is exact on the sender's timeline. Looking up the node's own phase_id at that
instant and comparing it with the root's phase_id on the same arrival row
compares the two schedules probe by probe -- a clock-free join, like PDR's
seq_num join.

A probe is only compared when the node's phase is the SAME at send_ts and
EDGE_TOLERANCE_S either side of it, so the ~1 s it takes a phase broadcast and
a multi-hop probe to cross the mesh never counts as a mismatch. Phase 255
(stabilise / pre-baseline) is never compared: after a root reboot the children
sit in phase 0 while the new root stabilises in 255, and preprocess already
excludes that span correctly.

Not checkable: the blackhole attacker (the root never logs its own probes)
and any node with fewer than MIN_PROBES comparable arrivals. Those are
reported as unchecked, never as fine.
"""

from __future__ import annotations

import glob
import os
import re

import numpy as np
import pandas as pd

EXPERIMENT_PHASES = (0, 1, 2, 3)
EDGE_TOLERANCE_S = 5.0
MIN_PROBES = 20
# A clean node measured 0 mismatches of ~480 on G402; the desynced one ~40%.
MAX_MISMATCH_FRACTION = 0.05

_REPEAT_RE = re.compile(r"_r(\d+)_")


def _mac_of_node_id(node_id) -> str | None:
    hexpart = re.sub(r"[^0-9A-F]", "", str(node_id).upper().replace("NODE", ""))
    if len(hexpart) != 12:
        return None
    return ":".join(hexpart[i:i + 2] for i in range(0, 12, 2))


def _repeat_of(name: str) -> str | None:
    m = _REPEAT_RE.search(name)
    return m.group(1) if m else None


def load_arrivals_files(folder: str) -> dict[str, pd.DataFrame]:
    """{file name: arrivals rows} for every *_arrivals.csv directly in folder."""
    out = {}
    for fp in sorted(glob.glob(os.path.join(folder, "*_arrivals.csv"))):
        try:
            df = pd.read_csv(fp)
        except (pd.errors.EmptyDataError, pd.errors.ParserError):
            continue
        need = {"timestamp_us", "src_mac", "latency_us", "phase_id"}
        if df.empty or not need <= set(df.columns):
            continue
        for c in ("timestamp_us", "latency_us", "phase_id"):
            df[c] = pd.to_numeric(df[c], errors="coerce")
        df = df.dropna(subset=["timestamp_us", "latency_us", "phase_id"])
        df["_mac"] = df["src_mac"].astype(str).str.upper().str.strip()
        out[os.path.basename(fp)] = df
    return out


def _compare(telem: pd.DataFrame, arrivals: pd.DataFrame, mac: str) -> dict | None:
    a = arrivals[(arrivals["_mac"] == mac) & arrivals["phase_id"].isin(EXPERIMENT_PHASES)]
    if a.empty:
        return None
    t = pd.to_numeric(telem["timestamp_us"], errors="coerce").to_numpy(dtype=float)
    ph = pd.to_numeric(telem["phase_id"], errors="coerce").to_numpy(dtype=float)
    ok = ~(np.isnan(t) | np.isnan(ph))
    t, ph = t[ok], ph[ok]
    if len(t) < 2:
        return None
    order = np.argsort(t, kind="stable")
    t, ph = t[order], ph[order]

    send = (a["timestamp_us"] - a["latency_us"]).to_numpy(dtype=float)
    root_ph = a["phase_id"].to_numpy(dtype=float)
    inside = (send >= t[0]) & (send <= t[-1])
    tol = EDGE_TOLERANCE_S * 1e6

    def phase_at(x):
        return ph[np.clip(np.searchsorted(t, x, side="right") - 1, 0, len(t) - 1)]

    node_ph = phase_at(send)
    steady = (phase_at(send - tol) == node_ph) & (phase_at(send + tol) == node_ph)
    use = inside & steady & np.isin(node_ph, EXPERIMENT_PHASES)
    compared = int(use.sum())
    mismatched = node_ph[use] != root_ph[use]
    pairs = {}
    for n, r in zip(node_ph[use][mismatched], root_ph[use][mismatched]):
        pairs[(int(n), int(r))] = pairs.get((int(n), int(r)), 0) + 1
    return {
        "arrivals_in_file_span": int(inside.sum()),
        "arrivals_total": len(a),
        "compared": compared,
        "mismatched": int(mismatched.sum()),
        "pairs": pairs,
    }


def check_run(telem_by_file: dict[str, pd.DataFrame], folder: str) -> list[dict]:
    """One result per telemetry file: status 'ok', 'DESYNCED' or 'unchecked'.

    Files and arrivals are paired by repeat number (_r<N>_ in the name) when
    both carry one; among candidates, the arrivals file whose probes fall inside
    the telemetry file's time span most often wins. Boot-relative clocks mean a
    file from a DIFFERENT boot can overlap by chance, so a pairing where under
    half the node's arrivals land inside the file is reported unchecked rather
    than judged.
    """
    arrivals = load_arrivals_files(folder)
    results = []
    for name, telem in telem_by_file.items():
        node_id = str(telem["node_id"].dropna().iloc[0]) if "node_id" in telem and telem["node_id"].notna().any() else "?"
        res = {"file": name, "node_id": node_id, "status": "unchecked", "reason": "", "stats": None}
        results.append(res)
        role = str(telem["role"].dropna().iloc[0]).lower() if "role" in telem and telem["role"].notna().any() else ""
        if role == "root":
            res["status"], res["reason"] = "ok", "the root defines the schedule"
            continue
        mac = _mac_of_node_id(node_id)
        if mac is None:
            res["reason"] = "node_id is not a MAC"
            continue
        if not arrivals:
            res["reason"] = "no *_arrivals.csv in the folder"
            continue
        rep = _repeat_of(name)
        cands = {k: v for k, v in arrivals.items() if rep is None or _repeat_of(k) in (None, rep)}
        best = None
        for df in cands.values():
            s = _compare(telem, df, mac)
            if s and (best is None or s["arrivals_in_file_span"] > best["arrivals_in_file_span"]):
                best = s
        if best is None:
            res["reason"] = "the root logged no probes from it (expected for the blackhole attacker)"
            continue
        res["stats"] = best
        if best["arrivals_in_file_span"] < best["arrivals_total"] / 2:
            res["reason"] = ("under half its probes at the root fall inside this file's time span - "
                             "the file may be from a different boot")
            continue
        if best["compared"] < MIN_PROBES:
            res["reason"] = "only {} comparable probes".format(best["compared"])
            continue
        frac = best["mismatched"] / best["compared"]
        res["status"] = "DESYNCED" if frac > MAX_MISMATCH_FRACTION else "ok"
        res["reason"] = "{}/{} probes ({:.0%}) sent in a different phase than the root was in".format(
            best["mismatched"], best["compared"], frac)
    return results


def describe_pairs(pairs: dict) -> str:
    names = {0: "baseline", 1: "blackhole", 2: "wormhole", 3: "cooldown"}
    return ", ".join("node {} while root {}: {}".format(names.get(n, n), names.get(r, r), c)
                     for (n, r), c in sorted(pairs.items(), key=lambda kv: -kv[1]))

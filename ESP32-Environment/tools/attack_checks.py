#!/usr/bin/env python3
"""
attack_checks.py - "was the attack SET UP correctly?" checks for verify_attack.py.

WHY THIS EXISTS (oct. 14, 2026)
───────────────────────────────
The 3-sigma test in verify_attack.py answers one question: did the signature
features move? It cannot tell WHY they moved. Three real cases from this
project where the features moved and the attack was still not what we claim:

  - wormhole/linear/G402 r1: duplicates passed 3-sigma, but A sat 5 hops
    deeper than B - the tunnel was a detour, never a shortcut (ends reversed).
  - a wormhole run with NO UART cable passes TunnelIntensity, because Node B
    counts a probe as tunnelled when uart_write_bytes() returns.
  - blackhole/partial_mesh highload (C5): the ROOT lost 90 % of its arrival
    rows, so PDR collapsed for EVERY node - a blackhole-looking PDR with no
    blackhole behind it.

So every capture also has to pass these checks, read from the same feature
table. Each returns a list of Issue(level, text):

    FAIL  the setup was wrong -> the verdict becomes "SETUP INVALID"
    WARN  worth reading, does not change the verdict
    SKIP  the check could not run (columns missing) - no evidence either way

Checks, by group:
  TOPOLOGY  structure during the ATTACK windows matches the run's topology
            (same rules as topology_graph.validate / the root's live check);
            the nodes that carry the attack did not re-parent mid-attack.
  BLACKHOLE exactly one attacker; it relayed traffic; it really dropped it;
            >= 1 victim behind it; victims stayed ALIVE (own telemetry kept
            logging) yet were cut off; nodes NOT behind it were unaffected;
            attacker self-report agrees with its neighbours; recovery after.
  WORMHOLE  (analysis/exposure.wormhole_setup_issues: roles, A shallower than
            B, A received what B sent) + the root actually saw duplicates.
"""
from __future__ import annotations

import os
import re
import sys
from datetime import datetime, timedelta
from typing import NamedTuple

import pandas as pd

_HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, _HERE)
sys.path.insert(0, os.path.join(os.path.dirname(_HERE), "analysis"))
import exposure as _exposure          # noqa: E402
import topology_graph as _tg          # noqa: E402

FAIL, WARN, SKIP = "FAIL", "WARN", "SKIP"

# Thresholds. Deliberately loose: they separate "the attack happened as
# designed" from "something else happened", not good runs from great ones.
VICTIM_CUT_PDR = 0.50        # victims' mean attack PDR must fall below this
BYSTANDER_MAX_DROP = 0.30    # nodes NOT behind the attacker may lose at most this
ATTACKER_MAX_FORWARD = 0.50  # attacker forwarding more than this = drop not firing
NEIGHBOUR_DISAGREE = 0.25    # |self-reported FR - neighbour FR| above this
RECOVERY_PDR = 0.80          # victims' cooldown PDR below this = no recovery
TUNNEL_MIN_DELIVERY = 0.80   # A received / B sent below this = lossy wire

# Scenarios that MOVE or RESTART a node on purpose: a re-parent there is the
# scenario, not a broken setup.
MOVING_SCENARIOS = ("mobility", "powercycle")


class Issue(NamedTuple):
    level: str
    text: str


def _seg(df, name):
    if "segment" in df.columns:
        return df[df["segment"].astype(str) == name]
    lab = pd.to_numeric(df.get("Label"), errors="coerce")
    if name == "attack":
        return df[lab > 0]
    return df[lab == 0] if name == "baseline" else df.iloc[0:0]


def _roles(df):
    r = df.dropna(subset=["node_role"]).groupby("node_id")["node_role"]
    return r.agg(lambda s: s.mode().iloc[0]).astype(str).str.lower().to_dict()


def _first(df, col):
    v = df[col].dropna() if col in df.columns else pd.Series(dtype=object)
    return str(v.iloc[0]).lower() if not v.empty else ""


def _sum(df, col):
    return float(pd.to_numeric(df[col], errors="coerce").clip(lower=0).sum()) \
        if col in df.columns else float("nan")


def _short(n):
    return str(n).replace("NODE_", "")[-4:]


# ─────────────────────────────────────────────────────────────────────────
# TOPOLOGY
# ─────────────────────────────────────────────────────────────────────────

# Exposure-aware re-route judgement (oct. 18 2026, D-23; user: "allow a parent
# change when it does not damage the dataset - smart, but not cheating or biased").
# ESP-WIFI-MESH heals itself: when a board drops out, its children re-join
# elsewhere. That is only a different EXPERIMENT when it changes WHO THE ATTACK
# REACHES. Every board is classed per window by walking its parent chain at that
# moment:
#   victim    - the path to the root runs through the attacker
#   bystander - it reaches the root without the attacker
#   detached  - no parent right now (re-joining)
#   unknown   - the chain cannot be resolved (a board above has no window there)
# FAIRNESS RULES (why this cannot be used to rescue a run):
#   1. Outcome-blind: the tolerate / reject decision reads ONLY the structure
#      (parent_mac, hop). PDR / ForwardingRatio - the quantities the 3-sigma test
#      scores - are never used to accept a re-route. Accepting a layout because
#      "the attack still looked like it worked" would be circular.
#   2. Fixed in advance: the thresholds below are constants with a reason each,
#      set before they were run on any capture, and the same for every run.
#   3. Symmetric: a victim that becomes a bystander and a bystander that becomes
#      a victim fail alike; boards carried across by a moving parent count too.
#   4. The treatment is fixed: the ATTACKER moving is never tolerated.
#   5. The outcome may only DOWNGRADE: verify_attack.py re-runs the 3-sigma test
#      on the attack windows BEFORE the first re-route (robustness check); if the
#      verdict does not hold there, the run fails. It can never upgrade one.
FLIP_MIN_WINDOWS = 3          # >= 3 windows in each class = a real flip; fewer = window
                              # alignment noise (+-1 s) around a re-join
REROUTE_BUDGET = 0.10         # <= 10 % of a board's attack detached / unresolved = a brief
                              # re-join (normal ones: 3-6 s); more = a long outage (oct. 19 2026:
                              # those windows are EXCLUDED from the 3-sigma test, not fatal)
PHASE_EDGE_S = 60.0           # the layout "at START" = the last 60 s of the baseline;
                              # "after the attack" = the first 60 s of the cooldown
ROBUST_MIN_ATTACK_S = 60.0    # the robustness re-test needs >= 60 s of attack before
                              # the first re-route, or it is reported as untestable
# oct. 19 2026 - more situations (each can only ADD a warning / failure):
FLAP_MIN_CHANGES = 4          # >= 4 parent changes in one attack = an unstable link, not one re-route
SILENT_TAIL_S = 10.0          # a board whose windows stop >= 10 s before the attack ends went silent
MIN_VICTIM_EVIDENCE_S = 60    # < 60 traceable victim-seconds in the whole attack = too little to judge
NOPATH_SHARE_WARN = 0.25      # > 25 % of the victims' attack time without a path = weakened evidence
COOLDOWN_MIN_SHARE = 0.5      # a board with < 50 % of the others' cooldown = no usable recovery measurement
WINDOW_COVERAGE_FLOOR = 0.95  # a board needs windows for >= 95 % of the seconds of a phase - the project's
                              # own sample-coverage floor (Milestone 5; validate_integrity / inventory_cells)
                              # applied to the WINDOWS. Measured oct. 19: median 100 %, only 10 of 409
                              # board-attack phases below it, so it marks real anomalies, not noise


def _tcol(df):
    return "t_anchor_s" if "t_anchor_s" in df.columns else "window_start"


def _sta_map(df):
    sta = {}
    for n in set(df["node_id"].dropna()):
        v = _exposure.node_id_to_sta_int(n)
        if v is not None:
            sta.setdefault(v, n)
    return sta


def _parent_timeline(seg, sta):
    """node -> sorted [(t, parent node_id or None)] over one segment's windows."""
    tc = _tcol(seg)
    tl = {}
    for n, g in seg.dropna(subset=[tc]).groupby("node_id"):
        g = g.sort_values(tc)
        tl[n] = [(float(t), _exposure.resolve_parent(p, sta)) for t, p in zip(g[tc], g["parent_mac"])]
    return tl


def _parent_at(tl, n, t, tol=3.0):
    seq = tl.get(n)
    if not seq:
        return "unknown"
    import bisect
    ts = _TIMES.get(id(seq))
    if ts is None or len(ts) != len(seq):
        ts = _TIMES[id(seq)] = [x[0] for x in seq]
    i = bisect.bisect_left(ts, t)
    best = min((j for j in (i - 1, i) if 0 <= j < len(seq)), key=lambda j: abs(ts[j] - t))
    t0, p = seq[best]
    return p if abs(t0 - t) <= tol else "unknown"


_TIMES = {}      # id(timeline list) -> its times, for bisect (lists are rebuilt per call)


def _path_class(tl, n, t, attackers, roots):
    cur = n
    for _ in range(16):
        p = _parent_at(tl, cur, t)
        if p == "unknown":
            return "unknown"
        if p is None:
            return "detached"
        if p in attackers:
            return "victim"
        if p in roots:
            return "bystander"
        cur = p
    return "unknown"


def exposure_timeline(df, attack, segment="attack"):
    """{node: [(t, class)]} for every non-root, non-attacker board in one segment."""
    seg = _seg(df, segment)
    if seg.empty or not {"node_id", "parent_mac"} <= set(seg.columns):
        return {}
    roles = _roles(df)
    attackers = {n for n, r in roles.items() if r in _exposure.ATTACK_ROLES and r not in _exposure.WORMHOLE_ROLES}
    roots = {n for n, r in roles.items() if r in _exposure.ROOT_ROLES}
    tl = _parent_timeline(seg, _sta_map(df))
    _TIMES.clear()
    tc = _tcol(seg)
    out = {}
    for n, g in seg.dropna(subset=[tc]).groupby("node_id"):
        if n in attackers or n in roots:
            continue
        out[n] = [(float(t), _path_class(tl, n, float(t), attackers, roots)) for t in sorted(g[tc])]
    return out


def _flipped(classes):
    """True when a board spent >= FLIP_MIN_WINDOWS windows in BOTH victim and bystander."""
    return classes.count("victim") >= FLIP_MIN_WINDOWS and classes.count("bystander") >= FLIP_MIN_WINDOWS


def _majority(classes):
    kept = [c for c in classes if c in ("victim", "bystander")]
    return max(sorted(set(kept)), key=kept.count) if kept else None


def _edge(seq, which):
    """Classes in the last (baseline) / first (cooldown) PHASE_EDGE_S of a segment."""
    if not seq:
        return []
    if which == "last":
        t1 = seq[-1][0]
        return [c for t, c in seq if t >= t1 - PHASE_EDGE_S]
    t0 = seq[0][0]
    return [c for t, c in seq if t <= t0 + PHASE_EDGE_S]


def reroute_onset(df, attack, key_nodes=()):
    """Earliest attack time (t column) at which a key board's parent differs from its
    parent at the start of the attack (None = no re-route). Structure only."""
    atk = _seg(df, "attack")
    if atk.empty or "parent_mac" not in atk.columns:
        return None
    tc = _tcol(atk)
    onset = None
    for n, g in atk.dropna(subset=[tc]).groupby("node_id"):
        if key_nodes and n not in key_nodes:
            continue
        ps = [str(p) for p in g.sort_values(tc)["parent_mac"]]
        ts = list(g.sort_values(tc)[tc])
        first = next((p for p in ps if p not in ("", "nan", _exposure.ZERO_MAC)), None)
        if first is None:
            continue
        for t, p in zip(ts, ps):
            if p != first:
                onset = float(t) if onset is None else min(onset, float(t))
                break
    return onset


def _wormhole_order(df, roles):
    """(ok, bad seconds, seconds compared): A (exit) shallower than B (entry)?"""
    atk = _seg(df, "attack")
    if "hop" not in atk.columns:
        return None, 0, 0
    a = [n for n, r in roles.items() if r == "wormhole_a"]
    b = [n for n, r in roles.items() if r == "wormhole_b"]
    if len(a) != 1 or len(b) != 1:
        return None, 0, 0
    tc = _tcol(atk)
    ha = atk[atk["node_id"] == a[0]].dropna(subset=[tc, "hop"])[[tc, "hop"]].round({tc: 0}).groupby(tc)["hop"].first()
    hb = atk[atk["node_id"] == b[0]].dropna(subset=[tc, "hop"])[[tc, "hop"]].round({tc: 0}).groupby(tc)["hop"].first()
    both = pd.concat([ha.rename("a"), hb.rename("b")], axis=1).dropna()
    if both.empty:
        return None, 0, 0
    bad = int((both["a"] >= both["b"]).sum())
    return bad < FLIP_MIN_WINDOWS, bad, len(both)


def unresolved_windows(df, attack):
    """{(node_id, t)} of attack windows in which a board had NO working path to the
    root: detached, or a board above it went silent (crashed / reset). They are
    evidence of neither the attack nor its absence, so verify_attack.py drops them
    from the 3-sigma test (oct. 19 2026, fairness rule 6: this can only make the
    test HARDER - a dead parent also drives PDR to 0, which would read as attack)."""
    if attack != "blackhole":
        return set()
    out = set()
    for n, seq in exposure_timeline(df, attack).items():
        for t, c in seq:
            if c in ("detached", "unknown"):
                out.add((n, round(float(t), 3)))
    return out


def _delivery_note(atk, n):
    """Information only - never used to decide (fairness rule 1)."""
    if "PDR" not in atk.columns:
        return ""
    v = pd.to_numeric(atk.loc[atk["node_id"] == n, "PDR"], errors="coerce").dropna()
    return f" [delivery in the attack {v.mean():.2f} - shown, not used to decide]" if len(v) else ""


def _parent_changes(g, tc):
    """How many times a board's (non-zero) parent changed, in time order."""
    ps = [str(p) for p in g.sort_values(tc)["parent_mac"] if str(p) not in ("", "nan", _exposure.ZERO_MAC)]
    return sum(1 for a, b in zip(ps, ps[1:]) if a != b)


def _more_situations(df, attack, atk, roles, key_nodes, moved, timeline, scenario):
    """S1-S7 (oct. 19 2026). Layout / presence only - never delivery."""
    out = []
    if atk.empty or scenario in MOVING_SCENARIOS:
        return out
    tc = _tcol(atk)
    t0, t1 = float(atk[tc].min()), float(atk[tc].max())
    span = max(t1 - t0, 1.0)
    # S1 FLAPPING: many parent changes = an unstable link (its layout was never settled)
    if "parent_mac" in atk.columns:
        for n, g in atk.groupby("node_id"):
            k = _parent_changes(g, tc)
            if n in key_nodes and k >= FLAP_MIN_CHANGES:
                out.append(Issue(WARN, f"{_short(n)} ({roles.get(n, '?')}) FLAPPED: its parent changed {k} times during "
                                       f"the attack (>= {FLAP_MIN_CHANGES}) - an unstable link; move it closer before "
                                       f"the next capture"))
    # S2 / S3 WENT SILENT mid-attack (crash / reset / unplugged)
    for n, g in atk.groupby("node_id"):
        last = float(g[tc].max())
        if t1 - last < SILENT_TAIL_S or roles.get(n) in _exposure.ROOT_ROLES:
            continue
        who = roles.get(n, "?")
        gone_s = t1 - last
        # windows can be missing for two reasons: the board stopped (crash / reset /
        # power) OR preprocessing discarded them for too few samples (the attacker logs
        # unevenly while dropping traffic - oct. 19: 1C38 had data to +178 s but
        # windows only to +117 s). The table cannot tell which, so this is a WARNING,
        # never a failure.
        what = "the ATTACKER" if who in _exposure.ATTACK_ROLES else ("a victim" if n in key_nodes else "")
        if what:
            out.append(Issue(WARN, f"{_short(n)} ({who}) - {what} - has NO attack windows after +{last - t0:.0f} s "
                                   f"({gone_s:.0f} s before the end): it went SILENT (crash / reset / power) or its "
                                   f"windows had too few samples. The verdict uses the windows that exist; footnote it"))
    if attack == "blackhole" and timeline:
        # S4 LAYOUT CHANGED DURING THE BASELINE: the reference phase mixes two layouts
        base = exposure_timeline(df, attack, "baseline")
        for n, seq in sorted(base.items()):
            if _flipped([c for _t, c in seq]):
                out.append(Issue(WARN, f"{_short(n)} ({roles.get(n, '?')}) switched between VICTIM and BYSTANDER during "
                                       f"the BASELINE - its normal-phase reference mixes two layouts (no attack ran "
                                       f"then, so the verdict is not affected; footnote its per-board features)"))
        # S5 NEW BOARD: in the attack but never in the baseline
        bn = set(_seg(df, "baseline")["node_id"].dropna())
        for n in sorted(set(atk["node_id"].dropna()) - bn):
            if roles.get(n) not in _exposure.ROOT_ROLES:
                out.append(Issue(WARN, f"{_short(n)} ({roles.get(n, '?')}) appears in the attack but NOT in the baseline "
                                       f"- it has no normal-phase reference of its own"))
        # S6 / S7 HOW MUCH VICTIM EVIDENCE IS LEFT after leaving out no-path seconds
        had_victims = any(_majority([c for _t, c in seq]) == "victim" for seq in timeline.values())
        vic = sum(c == "victim" for seq in timeline.values() for _t, c in seq)
        nopath = sum(c in ("detached", "unknown") for seq in timeline.values()
                     if _majority([c for _t, c in seq]) == "victim" for _t, c in seq)
        if had_victims and vic < MIN_VICTIM_EVIDENCE_S:
            out.append(Issue(FAIL, f"only {vic} traceable VICTIM-seconds in the whole attack (needs "
                                   f"{MIN_VICTIM_EVIDENCE_S}) - too little evidence that the attack reached anyone"))
        elif had_victims and vic + nopath and nopath / (vic + nopath) > NOPATH_SHARE_WARN:
            out.append(Issue(WARN, f"{nopath} of {vic + nopath} victim-seconds ({nopath / (vic + nopath):.0%}) had no path "
                                   f"to the root and were left out - over {NOPATH_SHARE_WARN:.0%}: the verdict rests on "
                                   f"the remaining {vic} s"))
        elif had_victims:
            out.append(Issue("OK", f"victim evidence: {vic} traceable VICTIM-seconds"
                                   + (f", {nopath} no-path seconds left out ({nopath / (vic + nopath):.0%})" if nopath else "")))
    # S8 COOLDOWN coverage (oct. 19 2026): the 3-sigma verdict compares baseline vs attack
    # only, so a missing / short cooldown never changes it - it costs that board's
    # RECOVERY measurement. Reported as a minor data gap.
    cool = _seg(df, "cooldown")
    if not cool.empty and "node_id" in cool.columns:
        tcc = _tcol(cool)
        full = float(cool[tcc].max() - cool[tcc].min()) if len(cool) else 0.0
        if full > 0:
            have = cool.groupby("node_id")[tcc].agg(lambda v: float(v.max() - v.min()) + 1.0)
            for n in sorted(set(_seg(df, "baseline")["node_id"].dropna())):
                if roles.get(n) in _exposure.ROOT_ROLES:
                    continue
                got = float(have.get(n, 0.0))
                if got < COOLDOWN_MIN_SHARE * full:
                    out.append(Issue(WARN, f"{_short(n)} ({roles.get(n, '?')}) has {'NO' if got <= 0 else f'only {got:.0f} s of'} "
                                           f"COOLDOWN (the others: {full:.0f} s) - its recovery is not measured; the "
                                           f"verdict (baseline vs attack) does not use the cooldown"))
    # S9 GAPS INSIDE A PHASE (oct. 19 2026, verification #53): S2/S3 only see a board that goes
    # silent at the END; windows can also be missing in the MIDDLE (too few samples while the
    # board stalls / logs unevenly). Baseline: over the whole phase. Attack: over the board's own
    # first..last window (the end is S2/S3's job - never counted twice).
    for seg in ("baseline", "attack"):
        ph = _seg(df, seg)
        if ph.empty or "node_id" not in ph.columns:
            continue
        tcp = _tcol(ph)
        p0, p1 = float(ph[tcp].min()), float(ph[tcp].max())
        for n, g in ph.groupby("node_id"):
            if roles.get(n) in _exposure.ROOT_ROLES:
                continue
            a, b = (float(g[tcp].min()), float(g[tcp].max())) if seg == "attack" else (p0, p1)
            whole = int(round(b - a)) + 1
            have = len(set(g[tcp].round().astype(int)))
            if whole >= 20 and have < WINDOW_COVERAGE_FLOOR * whole:
                who = roles.get(n, "?")
                what = ("the ATTACKER" if who in _exposure.ATTACK_ROLES else
                        "a victim" if n in key_nodes else "a bystander")
                out.append(Issue(WARN, f"{_short(n)} ({who}) - {what} - has {seg} windows for only {have} of {whole} s "
                                       f"({int(100 * have / whole)}%, floor {WINDOW_COVERAGE_FLOOR:.0%}): windows missing INSIDE "
                                       f"the {seg} (too few samples, or the board stalled)"))
    return out


def layout_sketch(df, attack):
    """ASCII drawing of who sat under whom at the START of the attack, each board
    marked with its role / exposure, and what happened to it during the attack
    (oct. 19 2026, user: "an illustration so the reader understands it easily").
    ASCII only (Windows consoles). [] when the table has no layout columns."""
    atk = _seg(df, "attack")
    if atk.empty or not {"node_id", "parent_mac"} <= set(atk.columns):
        return []
    tc = _tcol(atk)
    roles = _roles(df)
    sta = _sta_map(df)
    t0, t1 = float(atk[tc].min()), float(atk[tc].max())
    timeline = exposure_timeline(df, attack) if attack == "blackhole" else {}
    first_parent, events = {}, {}
    for n, g in atk.dropna(subset=[tc]).groupby("node_id"):
        g = g.sort_values(tc)
        seq = [(float(t), _exposure.resolve_parent(p, sta), str(p)) for t, p in zip(g[tc], g["parent_mac"])]
        real = [(t, p) for t, p, raw in seq if raw not in ("", "nan", _exposure.ZERO_MAC) and p is not None]
        first_parent[n] = real[0][1] if real else None
        notes = []
        if real:
            cur = real[0][1]
            for t, p in real[1:]:
                if p != cur:
                    notes.append(f"moved -> under {_short(p)} at +{t - t0:.0f} s")
                    cur = p
        last = float(g[tc].max())
        if t1 - last >= SILENT_TAIL_S and roles.get(n) not in _exposure.ROOT_ROLES:
            notes.append(f"no windows after +{last - t0:.0f} s")
        events[n] = notes
    roots = [n for n, r in roles.items() if r in _exposure.ROOT_ROLES and n in first_parent or r in _exposure.ROOT_ROLES]
    root = roots[0] if roots else None

    def label(n):
        r = str(roles.get(n, "?"))
        if r in _exposure.ROOT_ROLES:
            return "ROOT"
        if r == "blackhole":
            return "ATTACKER"
        if r == "wormhole_a":
            return "WORMHOLE A (exit)"
        if r == "wormhole_b":
            return "WORMHOLE B (entry)"
        seq = [c for _t, c in timeline.get(n, [])]
        if _flipped(seq):
            return "VICTIM <-> BYSTANDER  (NOT ALLOWED)"
        m = _majority(seq)
        return {"victim": "VICTIM", "bystander": "bystander"}.get(m, "child")

    kids = {}
    for n, p in first_parent.items():
        if n == root:
            continue
        kids.setdefault(p if p in first_parent or p == root else None, []).append(n)
    lines, seen = [], set()

    def walk(n, prefix, last_child, depth):
        if n in seen or depth > 12:
            return
        seen.add(n)
        notes = events.get(n, [])
        tag = f"{_short(n):<6} {label(n)}" + (f"   * {'; '.join(notes)}" if notes else "")
        lines.append(f"{prefix}{'`-- ' if last_child else '+-- '}{tag}" if depth else f"{_short(n)}  ROOT")
        ch = sorted(kids.get(n, []), key=lambda x: (label(x) != "ATTACKER", _short(x)))
        for i, c in enumerate(ch):
            walk(c, prefix + ("" if depth == 0 else ("    " if last_child else "|   ")), i == len(ch) - 1, depth + 1)

    if root is not None:
        walk(root, "", True, 0)
    orphans = [n for n in first_parent if n not in seen and n != root]
    for n in sorted(orphans, key=_short):
        notes = events.get(n, [])
        lines.append(f"?   {_short(n):<6} {label(n)}  (its parent could not be traced)" + (f"   * {'; '.join(notes)}" if notes else ""))
    gone = sorted(set(_seg(df, "baseline")["node_id"].dropna()) - set(first_parent))
    for n in gone:
        lines.append(f"x   {_short(n):<6} {label(n)}  (in the baseline, NO attack windows)")
    return lines


def topology_issues(df, attack, key_nodes=()):
    """Structure + stability during the attack windows.

    key_nodes: the nodes whose position the attack depends on (attacker +
    victims for a blackhole, A + B for a wormhole). Re-parenting by one of
    them mid-attack is FAIL, except in a scenario that moves nodes on purpose.
    """
    need = {"node_id", "parent_mac", "node_role"}
    if not need <= set(df.columns):
        return [Issue(SKIP, "topology: no node_id/parent_mac/node_role column")]
    atk = _seg(df, "attack")
    if atk.empty:
        return [Issue(SKIP, "topology: no attack windows")]
    out = []
    topo = _first(df, "topology").replace("partial_mesh", "partial")
    scenario = _first(df, "scenario")
    roles = _roles(df)
    nodes = sorted(atk["node_id"].dropna().unique())
    sta = {v: n for n in nodes if (v := _exposure.node_id_to_sta_int(n)) is not None}

    # Structure: each node's dominant parent IN the attack windows.
    dom = atk.dropna(subset=["parent_mac"]).groupby("node_id")["parent_mac"] \
             .agg(lambda s: s.mode().iloc[0])
    links = {}
    for n in nodes:
        links[n] = None if roles.get(n) == "root" else \
            _exposure.resolve_parent(dom.get(n), sta)
    # A PARTIAL mesh only shows its extra parents over time, so it is judged on
    # every (child, parent) link seen across the experiment, not the attack alone.
    union = None
    if topo == "partial":
        exp = df[df["segment"].astype(str).isin(("baseline", "attack", "cooldown"))] \
            if "segment" in df.columns else df
        union = set()
        for n, p in exp.dropna(subset=["parent_mac"])[["node_id", "parent_mac"]] \
                       .drop_duplicates().itertuples(index=False):
            par = _exposure.resolve_parent(p, sta)
            if par is not None and n in links:
                union.add((n, par))
    # Boards in the table with NO attack window (dropped out, or windows
    # discarded / unlabelled). Their absence breaks the parent chain of the
    # boards below them, so the partial graph reads as "not attached" - a
    # statement about missing data, not about the mesh (oct. 16 2026).
    missing = sorted(set(df["node_id"].dropna()) - set(nodes))
    if topo in _tg.TOPOLOGIES and missing:
        status, reason = _tg.validate(topo, _tg.build_graph(links), union)
        if status == _tg.FAIL or status == _tg.WARN:
            out.append(Issue(WARN, f"topology during the attack cannot be judged: built from "
                                   f"{len(nodes)} of {len(nodes) + len(missing)} boards, the"
                                   f" others have no attack windows ("
                                   + ", ".join(_short(n) for n in missing)
                                   + "). The full-run structure check is verify_topology.py"))
        else:
            out.append(Issue("OK", f"topology during the attack = {topo} for the {len(nodes)}"
                                   f" boards with attack windows: {reason}"))
    elif topo in _tg.TOPOLOGIES:
        status, reason = _tg.validate(topo, _tg.build_graph(links), union)
        if status == _tg.FAIL:
            out.append(Issue(FAIL, f"topology during the attack is NOT {topo}: {reason}"))
        elif status == _tg.WARN:
            out.append(Issue(WARN, f"topology during the attack: {reason}"))
        else:
            out.append(Issue("OK", f"topology during the attack = {topo}: {reason}"))
    else:
        out.append(Issue(SKIP, f"topology: unknown topology {topo!r} in the table"))

    # Stability: distinct parents per node inside the attack windows.
    moved = {}
    for n, g in atk.dropna(subset=["parent_mac"]).groupby("node_id"):
        ps = {p for p in g["parent_mac"].astype(str) if p not in ("", "nan", _exposure.ZERO_MAC)}
        if len(ps) > 1:
            moved[n] = len(ps)
    # Re-routes are judged by what they did to the attack's reach (D-23), with
    # the fairness rules above: structure only, fixed thresholds, symmetric.
    timeline = exposure_timeline(df, attack) if attack == "blackhole" else {}
    flipped = {n for n, seq in timeline.items() if _flipped([c for _t, c in seq])}
    wh_ok, wh_bad, wh_n = _wormhole_order(df, roles) if attack == "wormhole" else (None, 0, 0)
    for n, k in sorted(moved.items()):
        who = roles.get(n, "?")
        msg = f"{_short(n)} ({who}) changed parent during the attack ({k} parents)"
        if scenario in MOVING_SCENARIOS:
            out.append(Issue(WARN, msg + f" (expected in a {scenario} run)"))
            continue
        if n not in key_nodes:
            out.append(Issue(WARN, msg))
            continue
        if who in _exposure.ATTACK_ROLES and attack == "blackhole":
            out.append(Issue(FAIL, msg + " - the ATTACKER itself moved: its position IS the experiment, so a"
                                         " moved attacker is never tolerated"))
            continue
        if attack == "blackhole" and n in timeline:
            cls = [c for _t, c in timeline[n]]
            off = cls.count("detached") + cls.count("unknown")
            if n in flipped:
                out.append(Issue(FAIL, msg + f" - it moved between VICTIM ({cls.count('victim')} s) and BYSTANDER "
                                             f"({cls.count('bystander')} s) during the attack, so the attack windows "
                                             f"mix two experiments"))
            elif _majority(cls) is None:
                out.append(Issue(FAIL, msg + " - its position during the attack could not be resolved"))
            elif off > REROUTE_BUDGET * len(cls):
                out.append(Issue(WARN, msg + f" - TOLERATED WITH EXCLUSION: it stayed a {_majority(cls).upper()} in every "
                                             f"window where its path could be traced, but {off} of {len(cls)} windows "
                                             f"({off / len(cls):.0%}, over the {REROUTE_BUDGET:.0%} of a brief re-join) had "
                                             f"no working path to the root (detached, or a board above it went down). "
                                             f"Those windows are EXCLUDED from the 3-sigma test. Decided from the layout only"
                                             + _delivery_note(atk, n)))
            else:
                out.append(Issue(WARN, msg + f" - TOLERATED: it stayed a {_majority(cls).upper()} in every attack window "
                                             f"({off} s detached while re-joining, limit "
                                             f"{int(REROUTE_BUDGET * len(cls))} s); the attack reached the same boards "
                                             f"(ESP-MESH self-healing re-route). Decided from the layout only"
                                             + _delivery_note(atk, n)))
            continue
        if attack == "wormhole" and wh_ok is not None:
            if wh_ok:
                out.append(Issue(WARN, msg + f" - TOLERATED: the A end stayed shallower than the B end in all {wh_n} "
                                             f"compared seconds, so the tunnel still skipped hops. Decided from the "
                                             f"layout only"))
            else:
                out.append(Issue(FAIL, msg + f" - the A end was NOT shallower than the B end for {wh_bad} of {wh_n} "
                                             f"seconds of the attack: the shortcut changed"))
            continue
        out.append(Issue(FAIL, msg + " - the attack depends on its position, so the"
                                     " attack windows mix two topologies"))
    # boards that did not move themselves but were carried across by an ancestor
    for n in sorted(flipped - set(moved)):
        seq = [c for _t, c in timeline[n]]
        out.append(Issue(FAIL, f"{_short(n)} ({roles.get(n, '?')}) switched between VICTIM ({seq.count('victim')} s) "
                               f"and BYSTANDER ({seq.count('bystander')} s) during the attack because a board above "
                               f"it moved - the attack windows mix two experiments"))
    # Phase-to-phase comparison: the layout when START was pressed (end of the
    # baseline) vs the attack vs the start of the cooldown. A board in a different
    # class between phases did not mix the attack windows (the checks above), but
    # its per-board features (hop, RSSI, latency) changed for a reason that is not
    # the attack: a confound to footnote - WARN, never a silent pass.
    if attack == "blackhole" and timeline and scenario not in MOVING_SCENARIOS:
        before = exposure_timeline(df, attack, "baseline")
        after = exposure_timeline(df, attack, "cooldown")
        for n in sorted(timeline):
            during = _majority([c for _t, c in timeline[n]])
            pre = _majority(_edge(before.get(n), "last"))
            post = _majority(_edge(after.get(n), "first"))
            if during and pre and pre != during:
                out.append(Issue(WARN, f"{_short(n)} ({roles.get(n, '?')}) was a {pre.upper()} when START was pressed "
                                       f"(last {PHASE_EDGE_S:.0f} s of the baseline) but a {during.upper()} in the attack - "
                                       f"the layout changed between the phases; its per-board baseline vs attack "
                                       f"comparison mixes the move with the attack"))
            if during and post and post != during:
                out.append(Issue(WARN, f"{_short(n)} ({roles.get(n, '?')}) was a {during.upper()} in the attack but a "
                                       f"{post.upper()} in the first {PHASE_EDGE_S:.0f} s of the cooldown - its recovery "
                                       f"is measured in another layout"))

    out += _more_situations(df, attack, atk, roles, key_nodes, moved, timeline, scenario)

    # Presence: nodes seen in the baseline but absent from the attack.
    base_nodes = set(_seg(df, "baseline")["node_id"].dropna())
    gone = sorted(base_nodes - set(nodes))
    if gone:
        # oct. 18 2026: a victim that dropped out (e.g. crashed) before the attack is
        # lost data, not a broken experiment, while OTHER victims carry the attack.
        # Losing the attacker itself - or every victim - still invalidates it.
        att_gone = any(n in key_nodes and roles.get(n) in _exposure.ATTACK_ROLES for n in gone)
        victims_left = [n for n in key_nodes if n in set(nodes) and roles.get(n) not in _exposure.ATTACK_ROLES]
        lvl = FAIL if (att_gone or (any(n in key_nodes for n in gone) and not victims_left)) else WARN
        out.append(Issue(lvl, "no attack-window telemetry from "
                              + ", ".join(_short(n) for n in gone)
                              + " (board dropped out, its file is missing, or its attack"
                              " windows were discarded for too few samples)"))
    # (The no-labelled-window WARN below is skipped for boards the presence
    # line above already named, so each board is reported once.)
    # Nodes in the table with NO labelled window at all (e.g. segment
    # no_phase_seen: preprocessing could not anchor their phases). They are
    # missing from the structure above, which otherwise reads as boards
    # "not attached to the root" (oct. 16 2026, wormhole/tree/DLSU).
    if "segment" in df.columns:
        lab = df[df["segment"].astype(str).isin(("baseline", "attack", "cooldown"))]
        unlab = sorted(set(df["node_id"].dropna()) - set(lab["node_id"].dropna())
                       - set(gone))
        if unlab:
            segs = sorted(df.loc[df["node_id"].isin(unlab), "segment"].astype(str).unique())
            out.append(Issue(WARN, f"{len(unlab)} node(s) have NO labelled window ("
                                   + ", ".join(segs) + "), so the checks above run without"
                                   " them: " + ", ".join(_short(n) for n in unlab)
                                   + " - their raw files may be COMPLETE: preprocessing unlabels a"
                                   " board whose phase labels are out of sync with the root's"
                                   " ([UNLABELLED] in the preprocessing report), or one that never"
                                   " left phase 0. A data/preprocessing gap, not evidence about the attack"))
    return out


# ─────────────────────────────────────────────────────────────────────────
# BLACKHOLE
# ─────────────────────────────────────────────────────────────────────────

def blackhole_issues(df):
    """(issues, key_nodes) for a blackhole capture."""
    if not {"node_id", "node_role"} <= set(df.columns):
        return [Issue(SKIP, "blackhole: no node_id/node_role column")], set()
    roles = _roles(df)
    attackers = [n for n, r in roles.items() if r == "blackhole"]
    if not attackers:
        return [Issue(FAIL, "no 'blackhole' node in the data - attacker telemetry"
                            " missing or the attacker was never flashed")], set()
    out = []
    if len(attackers) > 1:
        out.append(Issue(FAIL, f"{len(attackers)} boards logged as blackhole"
                               f" ({', '.join(map(_short, attackers))}) - there must be one"))
    a = attackers[0]
    atk, base, cool = _seg(df, "attack"), _seg(df, "baseline"), _seg(df, "cooldown")
    a_atk = atk[atk["node_id"] == a]

    # 1. The attacker relayed traffic AND dropped it.
    recv, fwd = _sum(a_atk, "recv_count_delta"), _sum(a_atk, "forward_count_delta")
    if recv == recv:                                   # not NaN
        if recv <= 0:
            out.append(Issue(FAIL, f"attacker {_short(a)} received NOTHING to relay during the"
                                   " attack - it sat where no traffic crosses it (a leaf?)"))
        elif fwd / recv > ATTACKER_MAX_FORWARD:
            out.append(Issue(FAIL, f"attacker {_short(a)} still FORWARDED {fwd / recv:.0%} of what"
                                   " it received during the attack - the drop never fired, so"
                                   " any delivery loss came from something else"))
        else:
            out.append(Issue("OK", f"attacker {_short(a)} received {recv:.0f}, forwarded"
                                   f" {fwd:.0f} ({fwd / recv:.0%}) during the attack"))

    # 2. Victims exist, stayed alive, and were cut off.
    d = df if "exposure" in df.columns else df.assign(exposure=_exposure.compute_exposure(df).values)
    exp = d.groupby("node_id")["exposure"].agg(lambda s: s.mode().iloc[0]).astype(str)
    victims = [n for n, e in exp.items() if e == "downstream"]
    bystanders = [n for n, e in exp.items() if e == "upstream"]
    if not victims:
        out.append(Issue(FAIL, "no node sits BEHIND the attacker (no victim) - a blackhole"
                               " here cannot cut anyone off; re-place the attacker"))
    elif "PDR" in df.columns:
        pdr = lambda seg, ns: pd.to_numeric(seg.loc[seg["node_id"].isin(ns), "PDR"],
                                            errors="coerce").groupby(seg["node_id"]).mean()
        v_atk, v_base, v_cool = pdr(atk, victims), pdr(base, victims), pdr(cool, victims)
        alive = set(atk.loc[atk["node_id"].isin(victims)
                            & (pd.to_numeric(atk.get("n_samples_present"), errors="coerce") > 0),
                            "node_id"]) if "n_samples_present" in atk.columns else set(victims)
        dead = [n for n in victims if n not in alive]
        if dead:
            out.append(Issue(FAIL, "victim(s) " + ", ".join(map(_short, dead)) + " logged NO"
                                   " telemetry during the attack - they were down, not"
                                   " blackholed (a dead node also delivers 0 %)"))
        if not v_atk.empty:
            m = float(v_atk.mean())
            if m > VICTIM_CUT_PDR:
                out.append(Issue(FAIL, f"the {len(victims)} victim(s) behind the attacker still"
                                       f" delivered {m:.0%} during the attack - not cut off"))
            else:
                out.append(Issue("OK", f"{len(victims)} victim(s) alive but cut off: attack PDR"
                                       f" {m:.3f} (baseline {float(v_base.mean()):.3f})"))
        if not v_cool.empty and float(v_cool.mean()) < RECOVERY_PDR:
            out.append(Issue(WARN, f"victims did not recover after the attack (cooldown PDR"
                                   f" {float(v_cool.mean()):.3f}) - check they stayed connected"))
        # 3. Specificity: nodes NOT behind the attacker must be unaffected.
        if bystanders:
            b_atk, b_base = pdr(atk, bystanders), pdr(base, bystanders)
            drop = (b_base - b_atk).dropna()
            bad = drop[drop > BYSTANDER_MAX_DROP]
            if not bad.empty:
                out.append(Issue(FAIL, "node(s) NOT behind the attacker also lost delivery: "
                                       + ", ".join(f"{_short(n)} -{v:.0%}" for n, v in bad.items())
                                       + " - the loss is not specific to the attacker's path"
                                         " (root overload / outage?)"))
            else:
                out.append(Issue("OK", f"{len(bystanders)} node(s) not behind the attacker kept"
                                       " delivering (loss is specific to the attacker's path)"))

    # 4. Self-report vs neighbours (two independent sources, one quantity).
    if {"NeighbourIn", "NeighbourOut"} <= set(df.columns) and recv == recv and recv > 0:
        nin, nout = _sum(a_atk, "NeighbourIn"), _sum(a_atk, "NeighbourOut")
        if nin > 0:
            gap = abs(fwd / recv - nout / nin)
            if gap > NEIGHBOUR_DISAGREE:
                out.append(Issue(WARN, f"attacker says it forwarded {fwd / recv:.0%}, its"
                                       f" neighbours say {nout / nin:.0%} - the self-report"
                                       " is not confirmed"))
    return out, set(attackers) | set(victims)


# ─────────────────────────────────────────────────────────────────────────
# WORMHOLE
# ─────────────────────────────────────────────────────────────────────────

def wormhole_issues(df):
    """(issues, key_nodes) for a wormhole capture."""
    out = []
    for m in _exposure.wormhole_setup_issues(df):
        out.append(Issue(SKIP if m.startswith("cannot check") else FAIL, m))
    if not {"node_id", "node_role"} <= set(df.columns):
        return out, set()
    roles = _roles(df)
    ends = {n for n, r in roles.items() if r in _exposure.WORMHOLE_ROLES}
    atk = _seg(df, "attack")
    if "TunnelIntensity" in df.columns:
        ti = pd.to_numeric(atk["TunnelIntensity"], errors="coerce")
        role = atk["node_role"].astype(str).str.lower()
        sent, got = ti[role == "wormhole_b"].sum(), ti[role == "wormhole_a"].sum()
        if sent > 0 and got > 0.05 * sent:
            lvl = WARN if got < TUNNEL_MIN_DELIVERY * sent else "OK"
            out.append(Issue(lvl, f"UART: B sent ~{sent:.0f} tunnel frames, A received ~{got:.0f}"
                                  f" ({got / sent:.0%})" + (" - lossy wire" if lvl == WARN else "")))
    # The root must actually have seen the duplicates (TunnelLatency is built
    # from duplicate arrivals in the root's log; NaN where there were none).
    if "TunnelLatency" in df.columns:
        dup = pd.to_numeric(atk["TunnelLatency"], errors="coerce").notna().sum()
        if dup == 0:
            out.append(Issue(FAIL, "the ROOT logged no duplicate arrivals during the attack -"
                                   " nothing re-injected by A reached it"))
        else:
            out.append(Issue("OK", f"the root saw duplicate arrivals in {dup} attack window(s)"))
    # Only claim the summary when every part of it was actually checked (a
    # SKIP, e.g. Node A with no labelled windows, means a part was not).
    # Node A with no attack windows but duplicates at the root: the duplicates
    # can only come from A re-injecting B's probes, so A demonstrably worked -
    # its missing windows are a telemetry gap, not a missing attacker (oct. 16
    # 2026, wormhole/tree/DLSU: A's windows discarded, raw count 181). It is
    # dropped from the key nodes so the presence check WARNs instead of FAILing.
    if "TunnelLatency" in df.columns and dup > 0:
        a_ids = {n for n, r in roles.items() if r == "wormhole_a"}
        if a_ids and not (set(atk["node_id"].dropna()) & a_ids):
            ends = ends - a_ids
            out.append(Issue(WARN, "Node A has no attack windows, but the root logged B's"
                                   " probes twice - only A re-injects them, so A worked;"
                                   " its attack telemetry is a data gap (check its raw export)"))
    if not any(i.level in (FAIL, SKIP) for i in out) and ends:
        out.insert(0, Issue("OK", "one A + one B, roles stable in the experiment,"
                                  " A shallower than B, tunnel carried data"))
    return out, ends


# ── START_ANYWAY (oct. 18 2026, verification #41 / checklist B-force) ─────────
# START_ANYWAY releases the root's safety gate (a child missing, or the wormhole
# ends not A-shallower-than-B). The root says so ONLY on its serial output -
# nothing goes into the SD-card CSVs - so the verifier could CONFIRM a forced
# run without a word. The run logs (datasets/run_logs/<attack>/<topology>/
# <location>/<scenario>/, written by the GUI / wizard monitors) DO hold the
# root's output: find the ones started in the hours before this capture was
# exported and look for the root's own forced-start lines (help text that
# merely MENTIONS START_ANYWAY does not count).
RUN_LOGS = os.path.join(os.path.dirname(_HERE), "datasets", "run_logs")
RUN_LOG_WINDOW_H = 4          # a run log must start at most this long before the export
_FORCED = re.compile(r"\[CTRL\] START_ANYWAY (?:after|-)|START_ANYWAY:OK")
_ROOT_SAW = re.compile(r"\[CTRL\]")
# written by the GUI (gui/PreStart.ps1) when the operator overrides a FAILED
# pre-START check with a typed reason (oct. 18 2026)
_PRESTART_OVR = re.compile(r"PRESTART_OVERRIDE: (.+)")
_ANSI = re.compile(r"\x1b\[[0-9;]*m")
_MON = {m: i for i, m in enumerate(
    ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"], 1)}


def stamp_from_name(name, year=None):
    """The time in a capture / log file name: 'oct18_0338PM', 'sept27_0311am'
    or '20260914_204207'. None when the name carries no time."""
    m = re.search(r"(\d{8})_(\d{6})", name)
    if m:
        try:
            return datetime.strptime(m.group(1) + m.group(2), "%Y%m%d%H%M%S")
        except ValueError:
            pass
    m = re.search(r"(?i)(jan|feb|mar|apr|may|jun|jul|aug|sept?|oct|nov|dec)(\d{1,2})_(\d{4})(am|pm)", name)
    if not m:
        return None
    mon = _MON[m.group(1).lower()[:3]]
    hh, mm = int(m.group(3)[:2]), int(m.group(3)[2:])
    if hh == 12:
        hh = 0
    if m.group(4).lower() == "pm":
        hh += 12
    try:
        return datetime(year or datetime.now().year, mon, int(m.group(2)), hh, mm)
    except ValueError:
        return None


def start_anyway_issues(df, logs_root=RUN_LOGS):
    """WARN if this capture's run was released with START_ANYWAY, OK if the root's
    log shows a normal start, SKIP when no root log was saved for it."""
    try:
        # NOT _first(): it lowercases, and the folders are 'G402', 'DLSU_Library'
        cell = [str(df[c].dropna().iloc[0]) if c in df.columns and df[c].notna().any() else ""
                for c in ("attack", "topology", "location", "scenario")]
        if any(v in ("", "None", "nan") for v in cell):
            return [Issue(SKIP, "START_ANYWAY: the table does not name its cell - cannot find the run log")]
        folder = os.path.join(logs_root, *cell)
        stamps = [stamp_from_name(str(f)) for f in df.get("source_file", pd.Series(dtype=str)).dropna().unique()]
        stamps = [s for s in stamps if s]
        if not stamps:
            return [Issue(SKIP, "START_ANYWAY: no export time in the file names - cannot match a run log")]
        export = max(stamps)
        if not os.path.isdir(folder):
            return [Issue(SKIP, f"START_ANYWAY: no run log saved for this cell ({os.path.relpath(folder, logs_root)}) "
                                f"- cannot tell whether the root's gate was overridden")]
        # the root log of THIS capture = the latest one started before the export
        # (an earlier aborted / forced attempt in the same window is not this run)
        best = None
        for name in sorted(os.listdir(folder)):
            if not name.endswith(".log"):
                continue
            path = os.path.join(folder, name)
            year = datetime.fromtimestamp(os.path.getmtime(path)).year
            st = stamp_from_name(name, year)
            if not st or not (export - timedelta(hours=RUN_LOG_WINDOW_H) <= st <= export + timedelta(minutes=5)):
                continue
            with open(path, "r", encoding="utf-8", errors="replace") as fh:
                text = _ANSI.sub("", fh.read())
            if _ROOT_SAW.search(text) and (best is None or st > best[0]):
                best = (st, name, text)
        if best:
            out = []
            for m in _PRESTART_OVR.finditer(best[2]):
                out.append(Issue(WARN, "START was pressed with FAILED pre-START checks, overridden by the operator - "
                                       f"footnote it: {m.group(1).strip()[:200]} ({best[1]})"))
            hit = _FORCED.search(best[2])
            if hit:
                text = best[2]
                line = text[text.rfind("\n", 0, hit.start()) + 1:text.find("\n", hit.end())].strip()
                return out + [Issue(WARN, "this run was FORCE-STARTED with START_ANYWAY (the root's safety gate was "
                                          f"overridden) - footnote it or recapture (checklist B-force). {best[1]}: {line[:140]}")]
            return out + [Issue("OK", f"normal START - no START_ANYWAY in the root's run log ({best[1]})")]
        return [Issue(SKIP, f"START_ANYWAY: no root run log from the {RUN_LOG_WINDOW_H} h before this capture "
                            f"({export:%b %d %I:%M %p}) - cannot tell whether the gate was overridden")]
    except Exception as e:                      # this check must never break the others
        return [Issue(SKIP, f"START_ANYWAY check could not run: {e}")]


def setup_issues(df, attack):
    """All checks for one attack: attack-specific first, then topology, then
    whether the run was force-started."""
    if attack == "blackhole":
        issues, key = blackhole_issues(df)
    elif attack == "wormhole":
        issues, key = wormhole_issues(df)
    else:
        return []
    return issues + topology_issues(df, attack, key) + start_anyway_issues(df)

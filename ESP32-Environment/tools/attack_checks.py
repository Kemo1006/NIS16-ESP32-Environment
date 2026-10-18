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
    for n, k in sorted(moved.items()):
        who = roles.get(n, "?")
        msg = f"{_short(n)} ({who}) changed parent during the attack ({k} parents)"
        if n in key_nodes and scenario not in MOVING_SCENARIOS:
            out.append(Issue(FAIL, msg + " - the attack depends on its position, so the"
                                         " attack windows mix two topologies"))
        else:
            out.append(Issue(WARN, msg + (f" (expected in a {scenario} run)"
                                          if scenario in MOVING_SCENARIOS else "")))
    # Presence: nodes seen in the baseline but absent from the attack.
    base_nodes = set(_seg(df, "baseline")["node_id"].dropna())
    gone = sorted(base_nodes - set(nodes))
    if gone:
        lvl = FAIL if any(n in key_nodes for n in gone) else WARN
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
                                   + " - a data/preprocessing gap, not evidence about the"
                                   " attack; check those boards' raw exports"))
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
            hit = _FORCED.search(best[2])
            if hit:
                text = best[2]
                line = text[text.rfind("\n", 0, hit.start()) + 1:text.find("\n", hit.end())].strip()
                return [Issue(WARN, "this run was FORCE-STARTED with START_ANYWAY (the root's safety gate was "
                                    f"overridden) - footnote it or recapture (checklist B-force). {best[1]}: {line[:140]}")]
            return [Issue("OK", f"normal START - no START_ANYWAY in the root's run log ({best[1]})")]
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

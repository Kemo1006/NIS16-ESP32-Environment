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
import sys
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
    if topo in _tg.TOPOLOGIES:
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
                              + " (board dropped out or its file is missing)"))
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
    if not any(i.level == FAIL for i in out) and ends:
        out.insert(0, Issue("OK", "one A + one B, roles stable in the experiment,"
                                  " A shallower than B, tunnel carried data"))
    return out, ends


def setup_issues(df, attack):
    """All checks for one attack: attack-specific first, then topology."""
    if attack == "blackhole":
        issues, key = blackhole_issues(df)
    elif attack == "wormhole":
        issues, key = wormhole_issues(df)
    else:
        return []
    return issues + topology_issues(df, attack, key)

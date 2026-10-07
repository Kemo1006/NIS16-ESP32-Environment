#!/usr/bin/env python3
"""
exposure.py — who was ACTUALLY exposed to the attacker, derived from topology.

WHY THIS EXISTS
───────────────
Every non-root board logs itself with a build-time role: "victim" on a plain
child, "blackhole" / "wormhole_a" / "wormhole_b" on an attacker. That role says
what the firmware IS, not what happened to the node — and since C7 made the
blackhole POSITIONAL, those are different questions.

Measured on blackhole/linear/home r1 (2026-09-22), chain ROOT → B0CB (H01) →
ATTACKER (H02) → 20500DE70C80 (H03):

    NODE_20500DE70C80   role=victim   PDR 1.000 → 0.0000   actually attacked
    NODE_B0CBD8F33218   role=victim   PDR 1.000 → 1.0000   never touched

Both are labelled "victim" and only one is. B0CB sits ABOVE the attacker, so its
traffic reaches the root without ever transiting it. Calling it a victim in the
write-up would be wrong, and pooling the two produces a PDR (0.514) that
describes neither. This is the panel's positional-effects objection, and the
answer is to stop taking "victim" from the firmware and derive it from the tree.

WHAT THIS COMPUTES
──────────────────
One value per node per run:

    root        the sink
    attacker    the node running the attack firmware
    downstream  a child whose path to the root PASSES THROUGH an attacker
                — the only nodes the attack can reach. THESE are the victims.
    upstream    a child that reaches the root without transiting an attacker
                — present in the capture, unaffected by construction
    unknown     the parent chain could not be resolved (no parent_mac, or a
                node that never joined). Never silently folded into another
                value: "we could not tell" and "not attacked" are different.
    not_tunnelled  WORMHOLE runs only: every non-attacker child, wherever it
                sits. wormhole_victim.c tunnels ONLY Node B's OWN probes (B
                sends each up the mesh as normal and copies it over the UART
                wire to A); every other node's traffic is relayed exactly as in
                baseline, so the blackhole rule above ("under an attacker =
                victim") does not apply. Until oct. 7 2026 it did, and a linear
                wormhole run would have labelled every child below B
                "downstream". The attack signal lives in B's probes.

⚠️ This is METADATA, never a feature. Inside an attack window "downstream" is
very nearly the label itself, so it is registered in leakage.py's
METADATA_COLUMNS for the same reason node_role is. It exists to make reporting
honest, not to feed a model.

NIS16 — CTTHES3
"""

from __future__ import annotations

import pandas as pd

# Roles whose firmware actively manipulates traffic. A node is "downstream" when
# one of these sits on its path to the root.
ATTACK_ROLES = ("blackhole", "wormhole_a", "wormhole_b")

# Attacker roles that do NOT make the nodes under them victims (see
# "not_tunnelled" in the module docstring).
WORMHOLE_ROLES = ("wormhole_a", "wormhole_b")

ROOT_ROLES = ("root",)

ZERO_MAC = "00:00:00:00:00:00"

# The identity columns that separate one run from another. The tree is only
# meaningful within a single run, so exposure is resolved per group.
RUN_KEYS = ("attack", "topology", "location", "run_repeat")


def mac_to_int(mac) -> int | None:
    try:
        return int(str(mac).replace(":", "").replace("-", ""), 16)
    except (ValueError, AttributeError):
        return None


def node_id_to_sta_int(node_id) -> int | None:
    """NODE_F42DC973E618 -> integer STA MAC, or None if unparseable."""
    hexpart = str(node_id).replace("NODE_", "").strip()
    if len(hexpart) != 12:
        return None
    return mac_to_int(hexpart)


def resolve_parent(parent_mac, sta_index: dict) -> str | None:
    """parent_mac (the parent's SoftAP BSSID = its STA MAC + 1) -> node_id.

    On the ESP32 the SoftAP MAC is always the STA MAC + 1, which is why the raw
    CSV's parent_mac never equals any node_id directly. Same resolution
    verify_topology.py uses; the -1 is tried first and the plain value second,
    so a capture that ever logs the STA MAC itself still resolves.
    """
    if parent_mac is None or str(parent_mac) in ("", "nan", ZERO_MAC):
        return None
    v = mac_to_int(parent_mac)
    if v is None:
        return None
    return sta_index.get(v - 1) or sta_index.get(v)


def _dominant_parent(group: pd.DataFrame) -> pd.Series:
    """The parent each node used, preferring what it used DURING the attack.

    A node can re-parent mid-run, so "its parent" is not a single value. What
    matters for exposure is where it sat while the attack was running, so the
    attack-window mode wins; the whole-run mode is the fallback for captures
    with no attack rows (baseline runs) or nodes absent from that window.
    """
    def mode_of(frame):
        if frame.empty or "parent_mac" not in frame.columns:
            return pd.Series(dtype=object)
        m = frame.dropna(subset=["parent_mac"]).groupby("node_id")["parent_mac"]
        return m.agg(lambda s: s.mode().iloc[0] if not s.mode().empty else None)

    attack_rows = group
    if "segment" in group.columns:
        sel = group[group["segment"].astype(str) == "attack"]
        if not sel.empty:
            attack_rows = sel
    primary = mode_of(attack_rows)
    fallback = mode_of(group)
    return fallback.combine_first(primary).combine_first(fallback) \
        if primary.empty else primary.combine_first(fallback)


def _exposure_for_run(group: pd.DataFrame) -> dict:
    """{node_id: exposure} for one run."""
    if "node_id" not in group.columns:
        return {}
    nodes = group["node_id"].dropna().unique().tolist()

    roles = {}
    if "node_role" in group.columns:
        r = group.dropna(subset=["node_role"]).groupby("node_id")["node_role"]
        roles = r.agg(lambda s: s.mode().iloc[0] if not s.mode().empty else None).to_dict()

    sta_index = {}
    for n in nodes:
        v = node_id_to_sta_int(n)
        if v is not None:
            sta_index[v] = n

    parents_raw = _dominant_parent(group).to_dict()
    parent_of = {n: resolve_parent(parents_raw.get(n), sta_index) for n in nodes}

    attackers = {n for n in nodes if str(roles.get(n, "")).lower() in ATTACK_ROLES}

    out = {}
    for n in nodes:
        role = str(roles.get(n, "")).lower()
        if role in ROOT_ROLES:
            out[n] = "root"
            continue
        if n in attackers:
            out[n] = "attacker"
            continue
        if not attackers:
            # A baseline run has no attacker at all; nobody is downstream of
            # one, and saying "upstream" would imply a comparison that does not
            # exist in this capture.
            out[n] = "no_attacker"
            continue
        if any(str(roles.get(a, "")).lower() in WORMHOLE_ROLES for a in attackers):
            out[n] = "not_tunnelled"
            continue

        # Walk to the root. `seen` guards against a cycle produced by a
        # re-parenting race in the logged data -- an infinite loop here would
        # hang the whole pipeline over a handful of malformed rows.
        cur, seen, hit = parent_of.get(n), {n}, False
        while cur is not None and cur not in seen:
            seen.add(cur)
            if cur in attackers:
                hit = True
                break
            cur = parent_of.get(cur)
        if hit:
            out[n] = "downstream"
        elif parent_of.get(n) is None:
            out[n] = "unknown"
        else:
            out[n] = "upstream"
    return out


def compute_exposure(df: pd.DataFrame) -> pd.Series:
    """Exposure per row, resolved independently within each run.

    Returns a Series aligned to df.index; "unknown" wherever the tree could not
    be reconstructed, never a guess.
    """
    if "node_id" not in df.columns:
        return pd.Series("unknown", index=df.index, dtype=object)

    keys = [k for k in RUN_KEYS if k in df.columns]
    result = pd.Series("unknown", index=df.index, dtype=object)
    if not keys:
        mapping = _exposure_for_run(df)
        return df["node_id"].map(mapping).fillna("unknown").astype(object)

    for _, idx in df.groupby(keys, dropna=False).groups.items():
        group = df.loc[idx]
        mapping = _exposure_for_run(group)
        result.loc[idx] = group["node_id"].map(mapping).fillna("unknown").values
    return result


def wormhole_setup_issues(df: pd.DataFrame) -> list[str]:
    """Placement / role problems in a WORMHOLE capture, read from the data alone.

    The auto-switch firmware (wormhole_victim.c, oct. 7 2026) decides which
    board is A (exit) and which is B (entry) from mesh depth and logs it in
    every row's node_role. These are the ways that can still go wrong, each of
    which leaves a capture that looks healthy everywhere else:

      - a board's role CHANGED during the run (both ends locked the same end
        and one switched - its rows before the switch describe the other end);
      - not exactly one wormhole_a and one wormhole_b (the ends never heard
        each other over UART and both fell back to the same build default);
      - in the ATTACK windows, A is not fewer hops from the root than B: the
        tunnel was no shortcut, so the duplicate's latency advantage the
        verifier looks for cannot exist (reversed placement, or same depth).

    Returns human-readable problems, one per string; [] = nothing found.
    Needs node_id + node_role; the depth check also needs hop and segment.
    """
    issues: list[str] = []
    if "node_role" not in df.columns or "node_id" not in df.columns:
        return ["cannot check the wormhole setup: no node_role/node_id column"]
    roles = df.dropna(subset=["node_role"]).copy()
    roles["node_role"] = roles["node_role"].astype(str).str.lower()
    wh = roles[roles["node_role"].isin(WORMHOLE_ROLES)]
    if wh.empty:
        return ["no wormhole_a / wormhole_b rows at all - not a wormhole capture,"
                " or the attacker boards' telemetry is missing"]

    for node, g in wh.groupby("node_id"):
        if "window_start" in g.columns:
            g = g.sort_values("window_start")
        seen = list(dict.fromkeys(g["node_role"]))      # order they appeared in
        if len(seen) > 1:
            issues.append(f"{node} changed role during the run ({' -> '.join(seen)}):"
                          " the ends disagreed and one switched; rows before the"
                          " switch belong to the other end")

    dominant = wh.groupby("node_id")["node_role"].agg(lambda s: s.mode().iloc[0])
    n_a = int((dominant == "wormhole_a").sum())
    n_b = int((dominant == "wormhole_b").sum())
    if n_a != 1 or n_b != 1:
        issues.append(f"{n_a} board(s) logged as wormhole_a and {n_b} as wormhole_b -"
                      " there must be exactly one of each (UART cable / HELLO never heard?)")
        return issues

    if "hop" in df.columns:
        rows = wh
        if "segment" in wh.columns:
            atk = wh[wh["segment"].astype(str) == "attack"]
            rows = atk if not atk.empty else wh
        hop = rows.groupby("node_role")["hop"].median()
        if "wormhole_a" in hop and "wormhole_b" in hop \
                and pd.notna(hop["wormhole_a"]) and pd.notna(hop["wormhole_b"]):
            ha, hb = float(hop["wormhole_a"]), float(hop["wormhole_b"])
            if ha >= hb:
                kind = "REVERSED" if ha > hb else "AT THE SAME DEPTH"
                issues.append(f"wormhole ends {kind} in the attack windows: A (exit) at hop"
                              f" {ha:g}, B (entry) at hop {hb:g} - the tunnel was no"
                              " shortcut, so no latency advantage can show")
    return issues


def is_victim(exposure: pd.Series) -> pd.Series:
    """The honest definition: a victim is a node the attack could actually reach."""
    return exposure.astype(str) == "downstream"

"""Telemetry schema v3: the SAME meaning on every board.

WHY (D-44). In schema v1/v2 the three raw counters probes_count / tx_count / retry_count
meant a different thing on each role (child = own sends, blackhole attacker = relay
received/forwarded, root = arrivals/broadcasts, wormhole ends = tunnel counts), and the
attacker repeated its relay numbers in recv_count/forward_count. Readers had to
special-case every role. v3 gives each quantity its own column and writes 0 where a
quantity does not apply to a role.

v3 columns (the identity/time columns are unchanged):

  own traffic      own_sent        probes this node ORIGINATED and the stack accepted
                   own_failed      its failed esp_mesh_send() calls
  relay traffic    recv_count      frames received FOR RELAY      (renamed nothing: already
                   forward_count   frames passed on                role-neutral since F3)
                   drop_count      accepted and deliberately/forcibly not passed on
  root only        arrivals_count  probes the root received
                   bcast_count     phase broadcasts sent
                   bcast_failed    phase broadcasts that failed
  wormhole ends    tunnel_tx       B: probes also written into the tunnel;
                                   A: probes re-injected toward the root
                   tunnel_rx       A: tunnelled probes received from B
                   tunnel_fail     A: re-injection send failures

to_v3(df) is the ONE place that knows how v1 (11 col), v2 (14 col) and v3 files map.
Raw logs are never edited; this converts them in memory (analysis) or into the clean copy
tree written by tools/migrate_telem_v3.py.
"""
from __future__ import annotations

import pandas as pd

IDENTITY = ["timestamp_us", "node_id", "role", "layer", "parent_mac", "rssi_dbm",
            "phase_id", "gt_label"]
V3_COUNTERS = ["own_sent", "own_failed",
               "recv_count", "forward_count", "drop_count",
               "arrivals_count", "bcast_count", "bcast_failed",
               "tunnel_tx", "tunnel_rx", "tunnel_fail"]
V3_HEADER = IDENTITY + V3_COUNTERS

V1_HEADER = ["timestamp_us", "node_id", "role", "layer", "parent_mac", "rssi_dbm",
             "retry_count", "tx_count", "probes_count", "phase_id", "gt_label"]
V2_EXTRA = ["recv_count", "forward_count", "drop_count"]

_CHILD = {"victim", "child"}


def detect_version(columns) -> int:
    """1 = original 11 columns, 2 = + recv/forward/drop, 3 = role-neutral."""
    cols = set(columns)
    if "own_sent" in cols:
        return 3
    if {"recv_count", "forward_count", "drop_count"} <= cols:
        return 2
    return 1


def _num(df: pd.DataFrame, col: str) -> pd.Series:
    if col in df.columns:
        return pd.to_numeric(df[col], errors="coerce")
    return pd.Series(0, index=df.index, dtype="float64")


def to_v3(df: pd.DataFrame, ver: int | None = None) -> pd.DataFrame:
    """Return a v3-layout copy of a v1/v2/v3 telemetry frame (row order and index kept).

    Roles are read from df["role"] (raw files say victim/blackhole/root/wormhole_a/
    wormhole_b; analysis tables say child instead of victim - both accepted).
    A cell that does not apply to a role is 0, never NaN, so every column is a plain
    integer in the clean files. Cumulative counters stay cumulative.
    """
    if ver is None:  # callers that concatenated files pass the per-file version explicitly
        ver = detect_version(df.columns)
    if ver == 3:
        keep = [c for c in V3_HEADER if c in df.columns]
        out = df[keep].copy()
        for c in V3_COUNTERS:
            if c not in out.columns:
                out[c] = 0
        return out[V3_HEADER]

    role = df["role"].astype(str).str.lower()
    is_child = role.isin(_CHILD)
    is_bh = role == "blackhole"
    is_root = role == "root"
    is_wa = role == "wormhole_a"
    is_wb = role == "wormhole_b"
    known = is_child | is_bh | is_root | is_wa | is_wb

    retry, tx, probes = _num(df, "retry_count"), _num(df, "tx_count"), _num(df, "probes_count")
    recv, fwd, drop = _num(df, "recv_count"), _num(df, "forward_count"), _num(df, "drop_count")
    zero = pd.Series(0, index=df.index, dtype="float64")

    out = df[[c for c in IDENTITY if c in df.columns]].copy()

    # own traffic
    own_sent = zero.copy()
    own_sent = own_sent.where(~is_child, probes)    # child: probes originated (probes_count; tx_count differs in ~7 of 1.1M rows)
    own_sent = own_sent.where(~is_wb, probes)       # end B: probes generated
    own_failed = zero.copy()
    own_failed = own_failed.where(~is_child, retry)  # child: failed sends
    if ver == 2:
        own_failed = own_failed.where(~is_bh, retry)  # F3 attacker: failed sends only
    out["own_sent"] = own_sent
    out["own_failed"] = own_failed

    # relay traffic
    if ver == 2:
        out["recv_count"], out["forward_count"], out["drop_count"] = recv, fwd, drop
    else:  # v1: only the attacker relays, and it filed the counts in the overloaded columns
        out["recv_count"] = zero.where(~is_bh, probes)
        out["forward_count"] = zero.where(~is_bh, tx)
        out["drop_count"] = zero.where(~is_bh, retry)

    # root only
    out["arrivals_count"] = zero.where(~is_root, probes)
    out["bcast_count"] = zero.where(~is_root, tx)
    out["bcast_failed"] = zero.where(~is_root, retry)

    # wormhole ends
    tunnel_tx = zero.copy()
    tunnel_tx = tunnel_tx.where(~is_wb, retry)       # B: probes also tunnelled
    tunnel_tx = tunnel_tx.where(~is_wa, tx)          # A: probes re-injected
    out["tunnel_tx"] = tunnel_tx
    out["tunnel_rx"] = zero.where(~is_wa, probes)    # A: received from B over the wire
    out["tunnel_fail"] = zero.where(~is_wa, retry)   # A: re-injection failures

    # unknown roles keep a visible trace instead of being silently zeroed
    if (~known).any():
        for c in ("own_sent", "own_failed"):
            out.loc[~known, c] = float("nan")
    for c in V3_COUNTERS:
        out[c] = out[c].astype("float64")
    return out[V3_HEADER]

"""Checks for analysis/schema.py. Run:  python analysis/test_schema.py"""
import os
import sys

import pandas as pd

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import schema  # noqa: E402

FAILS = []


def check(name, cond):
    print(("  PASS  " if cond else "  FAIL  ") + name)
    if not cond:
        FAILS.append(name)


def row(role, retry, tx, probes, recv=None, fwd=None, drop=None):
    d = {"timestamp_us": 1, "node_id": "NODE_X", "role": role, "layer": 2, "parent_mac": "aa",
         "rssi_dbm": -60, "retry_count": retry, "tx_count": tx, "probes_count": probes,
         "phase_id": 0, "gt_label": 0}
    if recv is not None:
        d.update(recv_count=recv, forward_count=fwd, drop_count=drop)
    return pd.DataFrame([d])


def one(df):
    return schema.to_v3(df).iloc[0]


# ---- v2 (F3) -------------------------------------------------------------
r = one(row("victim", retry=2, tx=10, probes=10, recv=0, fwd=0, drop=0))
check("v2 child: own_sent=probes_count, own_failed=retry, relay 0", (r.own_sent, r.own_failed, r.recv_count) == (10, 2, 0))
check("v2 child: root/tunnel columns are 0", (r.arrivals_count, r.bcast_count, r.tunnel_tx, r.tunnel_rx) == (0, 0, 0, 0))

r = one(row("blackhole", retry=0, tx=7, probes=9, recv=9, fwd=7, drop=2))
check("v2 attacker: originates nothing (own_sent=0)", r.own_sent == 0)
check("v2 attacker: relay in/out/drop kept", (r.recv_count, r.forward_count, r.drop_count) == (9, 7, 2))
check("v2 attacker: failed sends = retry_count", r.own_failed == 0)

r = one(row("root", retry=1, tx=30, probes=500, recv=0, fwd=0, drop=0))
check("v2 root: arrivals/broadcasts in their own columns", (r.arrivals_count, r.bcast_count, r.bcast_failed) == (500, 30, 1))
check("v2 root: own_* and relay are 0", (r.own_sent, r.own_failed, r.recv_count, r.forward_count) == (0, 0, 0, 0))

r = one(row("wormhole_b", retry=4, tx=50, probes=50, recv=0, fwd=0, drop=0))
check("v2 end B: own_sent=probes, tunnel_tx=retry", (r.own_sent, r.tunnel_tx) == (50, 4))
r = one(row("wormhole_a", retry=1, tx=6, probes=7, recv=0, fwd=0, drop=0))
check("v2 end A: tunnel_rx=probes, tunnel_tx=tx, tunnel_fail=retry", (r.tunnel_rx, r.tunnel_tx, r.tunnel_fail) == (7, 6, 1))
check("v2 end A: originates nothing", r.own_sent == 0)

# ---- v1 (pre-F3, 11 columns) --------------------------------------------
r = one(row("blackhole", retry=3, tx=7, probes=9))
check("v1 attacker: relay_in=probes, relay_out=tx, drops=retry, failed sends 0",
      (r.recv_count, r.forward_count, r.drop_count, r.own_failed, r.own_sent) == (9, 7, 3, 0, 0))
r = one(row("victim", retry=2, tx=10, probes=10))
check("v1 child: own_sent=probes_count, own_failed=retry, relay 0", (r.own_sent, r.own_failed, r.recv_count) == (10, 2, 0))

# ---- shape ----------------------------------------------------------------
out = schema.to_v3(row("victim", 0, 1, 1, 0, 0, 0))
check("column order is V3_HEADER", list(out.columns) == schema.V3_HEADER)
check("idempotent on v3", schema.to_v3(out).equals(out))
check("detect_version", (schema.detect_version(schema.V1_HEADER), schema.detect_version(schema.V1_HEADER + schema.V2_EXTRA),
                         schema.detect_version(schema.V3_HEADER)) == (1, 2, 3))
check("row count and index kept", len(out) == 1 and list(out.index) == [0])

print()
if FAILS:
    print("FAILED:", len(FAILS))
    sys.exit(1)
print("all checks passed")

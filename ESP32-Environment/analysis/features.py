"""
features.py — NIS16 Milestone 7: Cross-Layer Feature Engineering (16 Features)

Computes the 16 features defined in Table 4.11 of the thesis, from the
outputs of Milestone 6's preprocessing pipeline (preprocess.py).

This module is intentionally NOT a single black-box function — each
feature family is its own clearly-labeled function so the milestone
criterion "Feature specifications may iterate as the EDA reveals which
carry useful signal" (per the milestones form) is easy to act on: swap
out or tune one function without touching the others.

────────────────────────────────────────────────────────────────────────
HONEST SCOPE NOTE — read this before trusting the output blindly
────────────────────────────────────────────────────────────────────────
Of the 16 features in Table 4.11, this module computes all 16. Three of them
(ForwardingRatio / IngressEgressDelta / ConsistencyScore) are RELAY-node
features and are only non-NaN for the blackhole ATTACKER row:

  ForwardingRatio / IngressEgressDelta / ConsistencyScore
                        — computed for node_role == "blackhole" from the
                          attacker's counters (blackhole_victim.c logs
                          probes_count = RECEIVED, tx_count = FORWARDED,
                          retry_count = DROPPED into the shared schema). See
                          compute_forwarding_features() for the mapping. They
                          are NaN for victim/root rows (those nodes don't relay
                          transit traffic, so a forwarding ratio is undefined
                          for them — this is correct, not a gap), and NaN for
                          every row of a run where the attacker's telemetry CSV
                          was NOT exported (a data-collection gap — export the
                          attacker board too). Baseline/wormhole runs have no
                          blackhole attacker, so these are legitimately NaN there.

  TunnelIntensity/
  TunnelBytes            — computed for the WORMHOLE attacker endpoints
                          (node_role "wormhole_a"/"wormhole_b") from the
                          tunnel-message counts their firmware
                          (wormhole_victim.c) logs into the shared schema
                          (Node B retry_count = frames tunnelled, Node A
                          probes_count = frames received). NaN for
                          victim/root and for baseline/blackhole runs (no
                          wormhole endpoints), ~0 in a wormhole run's
                          baseline phase — matching the thesis note "null
                          or zero for all other nodes and phases". See
                          compute_tunnel_features().
  TunnelLatency          — stays NaN: the A<->B tunnel is a one-way UART
                          write with no echo leg, so no round trip exists
                          to time. Flagged, not faked (like LatencyHopRatio).

Every other feature (11 of 16) computes a real number from data the
firmware already logs. The NaN columns are still emitted with their
correct names so the M7 milestone criterion "Feature table contains
all 16 columns" is met structurally — but "all 16 columns" and "all 16
columns have real numbers in them right now" are different claims, and
this docstring exists so nobody mistakes one for the other when M8/M9
consume this output.
────────────────────────────────────────────────────────────────────────

Usage:
    from preprocess import run_pipeline
    from features import compute_features

    windowed, report, filled = run_pipeline("raw_csv_folder")
    feature_table = compute_features(windowed, filled, arrivals_dir="raw_csv_folder")
"""

from __future__ import annotations

import glob
import os
import sys
import warnings

# Windows consoles default to a codepage (e.g. cp1252) that can't encode the
# box-drawing characters (─) used in the printed NaN-count summary below.
# Reconfigure to UTF-8 so this script's own diagnostic output never crashes
# the run after the real work (the output CSV) is already written.
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

import numpy as np
import pandas as pd

EPSILON = 1e-6  # Equation 4.2 / 4.4 divide-by-zero guard, matches preprocess.py

# IMPORTED, never redeclared. This was a literal 5 while preprocess.py used 1
# (deviation D-9), and the two must agree: compute_topology_stability_features()
# and compute_physical_layer_features() build their own window_start on this
# grid and then merge onto the windowed table by window_start, so a mismatch
# silently drops every row whose window_start is not a multiple of the larger
# value. Measured on the 2026-09-18 G402 capture: ParentSwitchRate,
# LayerChangeCount, HopStabilityDuration and RSSI_stability were 79.9% NaN and
# LatencyHopRatio 92.5% NaN, with 100% of the survivors sitting on
# window_start % 5 == 0 — a merge-key artefact, not a property of the data.
# It also made eda.py drop 12 of 16 features from PCA/t-SNE.
# Importing it makes divergence impossible.
from preprocess import WINDOW_SECONDS  # noqa: E402

# Wire size of one wormhole tunnel frame, for TunnelBytes. Mirrors
# sizeof(tunnel_pkt_t) in wormhole_victim.c: __attribute__((packed)) struct of
# magic(4) + probe_pkt_t{magic(4)+seq(4)+send_ts(8)+src_mac(6)=22} + crc(4) = 30.
# If that struct changes, change this to match.
TUNNEL_FRAME_BYTES = 30

# The layer the firmware reports for the root (esp_mesh_get_layer() == 1).
# Used only as a fallback when a run has no root row to read it from.
ROOT_LAYER_DEFAULT = 1

# parent_mac the firmware writes when a node has no upstream link (detached).
# A node in that state cannot be held responsible for undelivered probes.
NO_PARENT_MAC = "00:00:00:00:00:00"

# RELAY-node features: only defined for a node that receives transit traffic
# and forwards it, which in this testbed is the blackhole ATTACKER alone. They
# are NaN in baseline and wormhole runs BY DESIGN (no relay present), and
# populate on the attacker's windows in a blackhole run — verified 155/884 rows
# on the 2026-07-25 blackhole·linear capture. This is not a firmware gap; the
# name is kept because "missing_firmware_fields" is part of the output schema.
FEATURES_BLOCKED_ON_FIRMWARE = (
    "ForwardingRatio",
    "IngressEgressDelta",
    "ConsistencyScore",
)


# ─────────────────────────────────────────────────────────────────────────
# A. Forwarding Behavior Features (Equations 4.2, 4.3, 4.15)
# ─────────────────────────────────────────────────────────────────────────

def compute_forwarding_features(windowed: pd.DataFrame) -> pd.DataFrame:
    """
    ForwardingRatio (Eq 4.2), IngressEgressDelta (Eq 4.3), ConsistencyScore (Eq 4.15).

    These are RELAY-node features — only defined for a node that receives transit
    traffic and forwards it. In this testbed that is the blackhole ATTACKER
    (node_role == "blackhole"), whose firmware (blackhole_victim.c) records, into
    the shared 11-column schema:
        probes_count = packets RECEIVED from victims   (-> probes_count_delta)
        tx_count     = packets FORWARDED to root        (-> tx_count_delta)
        retry_count  = packets DROPPED                  (-> retry_count_delta)
    So for attacker rows: recv = probes_count_delta, forward = tx_count_delta, and
        ForwardingRatio    = forward / recv        (~1.0 baseline, ~0 during attack)
        IngressEgressDelta = |recv - forward|      (~0 baseline, > 0 during attack)
        ConsistencyScore   = |ForwardingRatio - 1| (~0 baseline, ~1 during attack)

    For every OTHER role (victim, root) these stay NaN on purpose — those nodes
    don't relay transit traffic, so a forwarding ratio is undefined for them
    (matches the thesis, where only the attacker has a meaningful forwarding
    ratio). Windows where the attacker received nothing (recv==0) are also NaN,
    since the ratio is undefined with no transit traffic.

    NOTE: this needs the attacker board's telemetry CSV to be present. If you
    only export root+victims (not the attacker), there are no blackhole-role
    rows and all three stay NaN — that is a data-collection gap, not a bug here.
    """
    out = pd.DataFrame(index=windowed.index)
    out["ForwardingRatio"] = np.nan
    out["IngressEgressDelta"] = np.nan
    out["ConsistencyScore"] = np.nan

    # Preferred path: telemetry schema v2 (F3) logs dedicated relay counters.
    #
    # recv_count is "frames received FOR RELAY", so a node that does not relay
    # reports 0 and stays NaN here — which is the correct undefined, not a
    # forwarding ratio of zero. That distinction is load-bearing: the ROOT
    # receives every probe in the run but relays none of them, so if it ever
    # reported its arrivals as recv_count it would score ForwardingRatio = 0.0
    # in every window and the measurement node would look like the attacker.
    # root_main.c reports 0/0/0 for exactly this reason.
    if "recv_count_delta" in windowed.columns and "forward_count_delta" in windowed.columns:
        recv = windowed["recv_count_delta"]
        fwd = windowed["forward_count_delta"]
        ratio = (fwd / (recv + EPSILON)).where(recv > 0, np.nan)

        # A pure relay cannot emit more than it accepted. A ratio above 1 means
        # a queued backlog flushed across a window boundary (measured at 19.5 on
        # the 2026-09-18 capture, where it carried most of the baseline
        # variance), not that forwarding improved. Flag it rather than letting
        # it inflate the baseline spread the 3-sigma test divides by.
        impossible = ratio > 1.0 + 1e-9
        if impossible.any():
            print(f"[features] WARNING: {int(impossible.sum())} window(s) have "
                  f"ForwardingRatio > 1 (max {ratio.max():.2f}). A relay cannot "
                  f"forward more than it received; this is a queue flush across "
                  f"a window edge. Check segment assignment before trusting the "
                  f"baseline distribution.")

        out["ForwardingRatio"] = ratio
        out["IngressEgressDelta"] = (recv - fwd).abs()
        out["ConsistencyScore"] = (ratio - 1.0).abs()
        return out

    # Current firmware: derive from the blackhole attacker's overloaded counters.
    # Compute ONLY for attacker rows; leave every other role NaN.
    if "node_role" in windowed.columns:
        mask = windowed["node_role"] == "blackhole"
        if mask.any():
            recv = windowed.loc[mask, "probes_count_delta"]
            fwd = windowed.loc[mask, "tx_count_delta"]
            ratio = (fwd / (recv + EPSILON)).where(recv > 0, np.nan)
            out.loc[mask, "ForwardingRatio"] = ratio
            out.loc[mask, "IngressEgressDelta"] = (recv - fwd).abs()
            out.loc[mask, "ConsistencyScore"] = (ratio - 1.0).abs()

    return out


# ─────────────────────────────────────────────────────────────────────────
# Shared: the root's probe-arrival log
# ─────────────────────────────────────────────────────────────────────────

def node_id_to_mac_norm(node_id: str) -> str:
    """NODE_<MAC> -> bare uppercase hex, per build_node_id() (mesh_setup.c)."""
    if not isinstance(node_id, str) or not node_id.startswith("NODE_"):
        return ""
    return node_id[5:].upper()


def normalize_mac(mac: str) -> str:
    """arrivals.csv src_mac is colon-separated; node_id's is not."""
    if not isinstance(mac, str):
        return ""
    return mac.replace(":", "").upper()


def load_arrivals(arrivals_dir: str) -> pd.DataFrame | None:
    """
    Load + rebase every *_arrivals.csv in arrivals_dir into one frame, or
    None if there are none. Shared by the PDR and latency features so the
    schema guard below lives in exactly one place.

    Rebases each file onto its own run's relative clock (t=0 at that file's
    first timestamp), matching preprocess.py's per-(node, run) approach.
    This assumes the arrivals file's first timestamp is close to its run's
    true start — true in practice since the root starts listening
    immediately on boot, before any victim sends a first probe.

    Adds: timestamp_s, t_rel, window_idx, window_start, _src_mac_norm.
    """
    arrival_files = sorted(glob.glob(os.path.join(arrivals_dir, "*_arrivals.csv")))
    if not arrival_files:
        return None

    rebased_frames = []
    for f in arrival_files:
        a = pd.read_csv(f)
        if a.empty:
            continue
        # An *_arrivals.csv that carries the TELEMETRY schema is a broken
        # capture, not a PDR-less run: it means the export spliced telem.csv
        # into the arrivals file and trim_run.py kept the telemetry block.
        # Fail loudly here — silently returning PDR=NaN would let a whole
        # feature table be built with the thesis's core detection feature
        # quietly missing. Re-trim with the current tools/trim_run.py.
        missing = {"src_mac", "seq_num"} - set(a.columns)
        if missing:
            raise ValueError(
                f"{os.path.basename(f)} is missing {sorted(missing)} — it does "
                f"not hold the probe-arrival schema (columns found: "
                f"{list(a.columns)}). This file is a mis-trimmed copy of the "
                f"root's telemetry. Re-run:  python trim_run.py "
                f"<raw export folder> --apply   (tools/trim_run.py now splits "
                f"mixed-schema captures) and point features.py at the "
                f"regenerated trimmed folder."
            )
        a["timestamp_s"] = a["timestamp_us"] / 1_000_000.0
        a["t_rel"] = a["timestamp_s"] - a["timestamp_s"].min()
        a["window_idx"] = (a["t_rel"] // WINDOW_SECONDS).astype(int)
        a["window_start"] = a["window_idx"] * WINDOW_SECONDS
        a["_source_arrivals_file"] = os.path.basename(f)
        rebased_frames.append(a)

    if not rebased_frames:
        # An arrivals FILE exists but holds zero rows. That is categorically
        # different from "no root log was provided" (the `not arrival_files`
        # case above) and must not look the same: the root ran, was asked for
        # its arrivals, and had nothing to report — it received no probes at
        # all, in any phase.
        #
        # By far the most common cause is a stale BLACKHOLE_ATTACKER_MAC:
        # blackhole victims send P2P to whatever MAC was compiled into them, so
        # if that board isn't in the mesh every probe is addressed to nobody.
        # Root logs zero arrivals, and PDR *and* ForwardingRatio come out fully
        # NaN while every board looks healthy. Cost a full run twice in 2026-09.
        # Warn rather than raise: RSSI/RetryRate features from this capture are
        # still valid, so the table is worth building — but nobody should
        # discover this by noticing an all-NaN column later.
        warnings.warn(
            "[features] {} arrivals file(s) found but ALL are EMPTY (header only) "
            "in {!r}. The root received ZERO probes for the whole run, so PDR and "
            "ForwardingRatio will be 100% NaN and this capture cannot demonstrate "
            "the blackhole signature. Most likely cause: BLACKHOLE_ATTACKER_MAC in "
            "mesh_config.h does not match the board actually running attacker "
            "firmware, so victims P2P'd every probe to a node that wasn't there. "
            "Fix it and RE-FLASH the victims (the MAC is compiled into them). "
            "Check the attacker's boot log: it now prints a MISMATCH banner.".format(
                len(arrival_files), arrivals_dir
            ),
            stacklevel=2,
        )
        return None

    arrivals_rebased = pd.concat(rebased_frames, ignore_index=True)
    arrivals_rebased["_src_mac_norm"] = arrivals_rebased["src_mac"].apply(normalize_mac)
    return arrivals_rebased


# ─────────────────────────────────────────────────────────────────────────
# B. Link Reliability Features (Equation 4.4, 4.5)
# ─────────────────────────────────────────────────────────────────────────

def compute_link_reliability_features(windowed: pd.DataFrame) -> pd.DataFrame:
    """
    RetryRate (Equation 4.4): proportion of tx attempts needing MAC retry.

    RetryRate = retry_count_delta / (tx_count_delta + retry_count_delta + eps)

    This denominator choice — total attempts INCLUDING retries, not just
    tx_count_delta alone — matches the equation's definition ("proportion
    of transmission attempts that required retransmission"): if tx_count
    already counts only first-attempt sends, retries are additional
    attempts on top of that, so they belong in the denominator too.

    PDR is intentionally NOT computed here — it needs the root's
    probe-arrival log joined against each victim's own probes_count,
    which is a cross-node operation. See compute_pdr_features() below.
    """
    out = pd.DataFrame(index=windowed.index)

    retry = windowed["retry_count_delta"]
    tx = windowed["tx_count_delta"]
    out["RetryRate"] = retry / (tx + retry + EPSILON)

    return out


def compute_pdr_features(
    windowed: pd.DataFrame,
    arrivals_dir: str,
) -> pd.DataFrame:
    """
    Packet Delivery Ratio (Equation 4.5), victim nodes only.

    PDR = probes_received_at_root_from_this_victim / probes_sent_by_victim

    JOIN KEY: (node, sequence number) — NOT (node, time window). This is the
    join the milestones form specifies ("joining each node's outgoing log with
    the root's probe-arrival log on (src_node_id, sequence_number)"), and it is
    the only one this testbed can support. Every board keeps its own
    boot-relative esp_timer clock, nothing disciplines them to a common origin,
    and preprocess.rebase_time() rebases each node to its OWN first sample.
    Measured on blackhole/linear/G402, the three victims' clocks sat -56 s,
    +359 s and +361 s from the root's — the root's arrivals log reports an
    impossible NEGATIVE one-way latency for one of them — i.e. window offsets
    of 69, 347 and 346 windows. Keying the join on window_start therefore
    compared each victim's probes against a slice of the root's log minutes
    away and returned a baseline PDR of 0.079 on a run whose true baseline PDR
    is 0.94-1.00. Sequence numbers carry no clock, so they cross the node
    boundary intact.

    RECONSTRUCTING THE SEQUENCE NUMBER. victim_main.c advances the probe's
    seq_num on every send ATTEMPT (`pkt.seq_num = ++seq`) but only advances
    probes_count on success, counting a failure into retry_count instead. So at
    any instant  seq == probes_count + retry_count.  That is why this needs the
    counters' ABSOLUTE values at the window edges (probes_count_first/_last,
    retry_count_first/_last, emitted by preprocess.build_windows) and not their
    deltas. Verified on G402: 703 probes + 1 retry = 704 = the highest seq_num
    the root logged from that victim.

    A window's probes therefore occupy seq range (seq_first, seq_last], and:
      numerator   = how many of THOSE sequence numbers the root logged
      denominator = probes_count_delta — successful sends only. A probe that
                    esp_mesh_send rejected never reached the air, so it is not
                    a delivery failure; its sequence number simply never
                    arrives, which keeps the ratio <= 1 on its own.

    If no *_arrivals.csv file is found in arrivals_dir (e.g. only telemetry
    CSVs were provided, or this is a synthetic-data test run without a root),
    PDR is NaN for every row rather than silently 0 — a missing root log is a
    data-availability problem, not a delivery failure, and those two situations
    should never look the same in the output.

    ATTRIBUTION RULE. A window gets a real PDR (including 0.0) only when all
    five hold:

      1. node_role == "victim". The blackhole ATTACKER emits probes of its own
         which the root never logs in ANY phase, so counting it as a victim
         added 298 all-zero baseline rows on G402 and dragged the baseline
         under the sanity floor. Relay behaviour is measured by
         ForwardingRatio, not by PDR.
      2. the node actually TRANSMITTED that window (probes_count_delta > 0).
         A 0/0 ratio is undefined, so it must be NaN — never 0.0. Dividing by
         (0 + EPSILON) yields a literal 0.0, indistinguishable from total
         delivery failure, and is exactly how a false blackhole signature gets
         manufactured.
      3. the node held a real mesh ASSOCIATION that window (layer > 0 and a
         non-zero parent_mac). A detached node's undelivered probes are a
         connectivity artefact, not a forwarding failure.
      4. neither counter RESET mid-window. A reboot restarts seq numbering, so
         the reconstructed range would address the wrong probes entirely.
      5. the root was RUNNING in that window's PHASE. Phase ids come from the
         root's own mesh-wide broadcast, so they are the one cross-node
         reference needing no clock — which is what the old arrival-span check
         was reaching for and could not reach correctly. A phase the root
         never logged is a phase we have no delivery evidence for.

    Where all five hold and the root logged none of the window's sequence
    numbers, that is a genuine PDR of 0 — the blackhole signature this feature
    exists to detect.
    """
    out = pd.DataFrame(index=windowed.index)
    out["PDR"] = np.nan
    out["_pdr_clipped"] = False

    arrivals = load_arrivals(arrivals_dir)
    if arrivals is None:
        return out  # no root log available — leave PDR as NaN, not 0

    if "node_role" not in windowed.columns:
        warnings.warn(
            "[features] windowed dataset has no node_role column, so victim rows "
            "cannot be told apart from the blackhole attacker's (whose probes the "
            "root never logs). PDR left NaN rather than reported for the wrong "
            "nodes.",
            stacklevel=2,
        )
        return out

    edge_cols = ["probes_count_first", "probes_count_last",
                 "retry_count_first", "retry_count_last"]
    missing = [c for c in edge_cols if c not in windowed.columns]
    if missing:
        raise ValueError(
            f"windowed dataset is missing {missing}. PDR joins the root's "
            f"arrivals log on probe SEQUENCE NUMBER (the boards share no clock, "
            f"so a window-keyed join is not possible), and reconstructing a "
            f"window's sequence range needs the absolute counter values at its "
            f"edges, not just the deltas. This table came from an older "
            f"preprocess.py. Rebuild it:  python analysis/preprocess.py ...  "
            f"then re-run features.py."
        )

    # Every sequence number the root logged, per source MAC. No timestamps
    # involved anywhere — that is the whole point.
    recv_by_mac = {
        mac: set(pd.to_numeric(g["seq_num"], errors="coerce").dropna().astype(int))
        for mac, g in arrivals.groupby("_src_mac_norm")
    }

    # Phases the root itself logged (condition 5). Phase ids arrive by mesh
    # broadcast, so they are comparable across nodes without a shared clock.
    # Absent root telemetry we cannot make this check at all, and an arrivals
    # file is itself evidence the root ran, so fall through rather than NaN
    # every row.
    root_phases = None
    if "window_phase_id" in windowed.columns:
        rp = windowed.loc[windowed["node_role"] == "root", "window_phase_id"].dropna()
        if not rp.empty:
            root_phases = set(rp)

    probes_sent = pd.to_numeric(windowed["probes_count_delta"], errors="coerce")
    seq_first = (pd.to_numeric(windowed["probes_count_first"], errors="coerce")
                 + pd.to_numeric(windowed["retry_count_first"], errors="coerce"))
    seq_last = (pd.to_numeric(windowed["probes_count_last"], errors="coerce")
                + pd.to_numeric(windowed["retry_count_last"], errors="coerce"))

    is_victim = windowed["node_role"] == "victim"
    transmitted = probes_sent.fillna(0) > 0
    parent = windowed["parent_mac"].fillna(NO_PARENT_MAC).astype(str).str.upper()
    associated = (windowed["layer"].fillna(-1) > 0) & (parent != NO_PARENT_MAC)

    def _reset_flag(col):
        if col not in windowed.columns:
            return pd.Series(False, index=windowed.index)
        return windowed[col].fillna(False).astype(bool)

    no_reset = ~(_reset_flag("probes_count_reset_detected")
                 | _reset_flag("retry_count_reset_detected"))
    seq_known = seq_first.notna() & seq_last.notna()
    if root_phases is None:
        root_running = pd.Series(True, index=windowed.index)
    else:
        root_running = windowed["window_phase_id"].isin(root_phases)

    attributable = (is_victim & transmitted & associated
                    & no_reset & seq_known & root_running)

    macs = windowed["node_id"].apply(node_id_to_mac_norm)
    pdr = pd.Series(np.nan, index=windowed.index, dtype=float)
    for idx in windowed.index[attributable]:
        got = recv_by_mac.get(macs.at[idx])
        if not got:
            # Root logged nothing at all from this victim. Every other guard
            # passed, so that is a real total delivery failure, not missing data.
            pdr.at[idx] = 0.0
            continue
        lo, hi = int(seq_first.at[idx]), int(seq_last.at[idx])
        pdr.at[idx] = sum(1 for s in range(lo + 1, hi + 1) if s in got) / probes_sent.at[idx]

    # PDR cannot exceed 1.0 in a correct dataset; clip defensively in case of
    # probe retransmission double-counting at the application layer, and
    # surface that as worth investigating rather than silently passing through.
    out["PDR"] = pdr.clip(upper=1.0).values
    out["_pdr_clipped"] = (pdr > 1.0).fillna(False).values

    return out


def compute_latency_features(
    windowed: pd.DataFrame,
    arrivals_dir: str,
) -> pd.DataFrame:
    """
    LatencyHopRatio (Eq 4.14) and TunnelLatency (Table 4.11, auxiliary).

    Both come out of the root's arrivals log, and both need the same
    correction first, so they are computed together.

    THE CLOCK PROBLEM
    ─────────────────
    root_main.c:329 logs `latency = now - pkt->send_ts_us`, where `now` is
    the ROOT's esp_timer_get_time() and send_ts_us is the VICTIM's. Those
    two clocks both start at their own board's boot and are never
    synchronised, so the raw column is

        latency_us = true_one_way_latency - (root_boot - victim_boot)

    i.e. the truth plus a large constant offset — hugely NEGATIVE in
    practice, because children are powered before the root (-194 s was
    typical on the 2026-07-20 wormhole run). Used raw it is meaningless.

    The offset is CONSTANT for a given (arrivals file, src_mac), so it
    cancels under any subtraction within that group. That is what makes
    both features recoverable from data already on disk, with no firmware
    change and no re-run:

    LatencyHopRatio
        Subtract each (file, src_mac) MINIMUM. The result is delay
        relative to that node's fastest observed delivery in the run —
        a RELATIVE ONE-WAY delay, not the round trip Eq 4.14 names,
        because the firmware sends no response leg to time an RTT
        against. Divided by hop count (layer - 1; the root is layer 1)
        it still carries exactly the signal the equation is for: delay
        that does not match the reported path length. On the 2026-07-25
        baseline·linear run it rises monotonically with depth
        (1.9 ms at layer 2 -> 12.7 ms at layer 6), which is the
        behaviour Eq 4.14's "consistent ratio per hop" describes.

        This is a documented deviation — see thesis-deviate.md. The
        thesis-faithful alternative (a root->victim response leg) is a
        firmware change that would invalidate every run already captured.

    TunnelLatency
        The thesis defines this as the tunnel's round-trip time measured
        with periodic echo messages; the A<->B UART link is one-way
        (wormhole_victim.c tunnel_forwarder_task), so no echo exists.
        What DOES exist is the milestone form's own stated wormhole
        signature: "the same logical probe arrives at root twice — once
        via slow multi-hop, once via fast wormhole shortcut, with a
        measurable latency mismatch". root_main.c:316-320 deliberately
        does NOT de-duplicate wormhole copies precisely so that both
        arrivals survive into the log.

        So TunnelLatency = the spread between the duplicate arrivals of
        one probe, max(latency_us) - min(latency_us) over each
        (file, src_mac, seq_num) group of size > 1. Both rows share one
        victim clock and one root clock, so the offset cancels EXACTLY
        here — no minimum-subtraction needed and no estimation involved.
        This is a real measurement, not a proxy.

        Keyed to the src_mac whose probes were duplicated (the same way
        PDR is keyed), which deviates from Table 4.12's "attacker nodes
        only" — the divergence is a property of the manipulated traffic,
        and the arrivals row records no marker for which copy came
        through the tunnel. Also in thesis-deviate.md.

    Windows with no arrivals (or no duplicates, for TunnelLatency) stay
    NaN rather than 0 — absence of a measurement is not a measurement of
    zero, the same rule the PDR coverage set follows above.
    """
    out = pd.DataFrame(index=windowed.index)
    out["LatencyHopRatio"] = np.nan
    out["TunnelLatency"] = np.nan

    arrivals = load_arrivals(arrivals_dir)
    if arrivals is None or "latency_us" not in arrivals.columns:
        return out

    a = arrivals.copy()
    grp = ["_source_arrivals_file", "_src_mac_norm"]

    # ── LatencyHopRatio ──────────────────────────────────────────────
    a["_lat_rel_ms"] = (
        a["latency_us"] - a.groupby(grp)["latency_us"].transform("min")
    ) / 1000.0

    lat_win = (
        a.groupby(["_src_mac_norm", "window_start"])["_lat_rel_ms"]
        .mean()
        .rename("_lat_rel_ms_mean")
        .reset_index()
    )

    # ── TunnelLatency ────────────────────────────────────────────────
    dup = a.groupby(grp + ["seq_num"]).agg(
        _spread_us=("latency_us", lambda s: s.max() - s.min()),
        _n=("latency_us", "size"),
        window_start=("window_start", "min"),
        _src=("_src_mac_norm", "first"),
    ).reset_index(drop=True)
    dup = dup[dup["_n"] > 1]

    if not dup.empty:
        tun_win = (
            dup.groupby(["_src", "window_start"])["_spread_us"]
            .mean()
            .div(1000.0)
            .rename("_tunnel_latency_ms")
            .reset_index()
            .rename(columns={"_src": "_src_mac_norm"})
        )
    else:
        tun_win = pd.DataFrame(
            columns=["_src_mac_norm", "window_start", "_tunnel_latency_ms"])

    # ── Merge onto the windowed rows ─────────────────────────────────
    w = windowed.copy()
    w["_node_mac_norm"] = w["node_id"].apply(node_id_to_mac_norm)
    w["_row_order"] = np.arange(len(w))

    merged = w.merge(
        lat_win, left_on=["_node_mac_norm", "window_start"],
        right_on=["_src_mac_norm", "window_start"], how="left",
    ).merge(
        tun_win, left_on=["_node_mac_norm", "window_start"],
        right_on=["_src_mac_norm", "window_start"], how="left",
        suffixes=("", "_tun"),
    ).sort_values("_row_order")

    # Hop count = how many layers below the root this node sits. Derive the
    # root's own layer from the data rather than hard-coding it: the firmware
    # reports the root at layer 1 (esp_mesh_get_layer), but the M6/M7 test
    # fixtures use 0-based layers, and hard-coding either convention silently
    # produces an all-NaN column on the other. Fall back to the firmware
    # convention when no root row is present (e.g. the root CSV wasn't
    # exported). The root itself has no path to itself — NaN, not a divide
    # by zero. layer == -1 is the disconnected sentinel and also lands NaN.
    root_layer = ROOT_LAYER_DEFAULT
    if "node_role" in merged.columns:
        root_layers = merged.loc[merged["node_role"] == "root", "layer"]
        if not root_layers.empty:
            root_layer = root_layers.mode().iloc[0]

    hops = merged["layer"] - root_layer
    ratio = merged["_lat_rel_ms_mean"] / hops.where(hops > 0, np.nan)

    out["LatencyHopRatio"] = ratio.values
    out["TunnelLatency"] = merged["_tunnel_latency_ms"].values

    return out


# ─────────────────────────────────────────────────────────────────────────
# C. Topology Stability Features (Equations 4.6, 4.7, 4.8)
# ─────────────────────────────────────────────────────────────────────────

def compute_topology_stability_features(
    windowed: pd.DataFrame,
    filled_long: pd.DataFrame,
) -> pd.DataFrame:
    """
    ParentSwitchRate, LayerChangeCount, HopStabilityDuration.

    These three CANNOT be computed from windowed (M6's output) alone,
    because windowing collapses each window down to a single modal
    layer/parent value — exactly the transition information these
    features need is destroyed by that aggregation. They are computed
    here from filled_long instead: the gap-filled, PRE-windowing,
    one-row-per-second table that preprocess.run_pipeline() now returns
    as its third value.

    ParentSwitchRate (Eq 4.6): count of parent_mac changes within the
    window / window duration in seconds.

    LayerChangeCount (Eq 4.7): count of layer value changes within the
    window (raw count, not rate — matches the equation as named).

    HopStabilityDuration (Eq 4.8): longest continuous run, in seconds,
    during which BOTH layer and parent_mac stayed constant, scanning
    across the window's samples in time order.
    """
    long_df = filled_long.copy()
    long_df["window_idx"] = (long_df["t_rel"] // WINDOW_SECONDS).astype(int)
    long_df["window_start"] = long_df["window_idx"] * WINDOW_SECONDS

    rows = []
    for (node_id, source_file, window_idx), grp in long_df.groupby(
        ["node_id", "_source_file", "window_idx"]
    ):
        grp = grp.sort_values("t_rel")
        layers = grp["layer"].to_numpy()
        parents = grp["parent_mac"].to_numpy()

        n_layer_changes = int(np.sum(layers[1:] != layers[:-1])) if len(layers) > 1 else 0
        n_parent_changes = int(np.sum(parents[1:] != parents[:-1])) if len(parents) > 1 else 0

        window_duration_s = max(grp["t_rel"].max() - grp["t_rel"].min(), EPSILON)
        parent_switch_rate = n_parent_changes / window_duration_s

        # HopStabilityDuration: longest run where (layer, parent) constant
        same_as_prev = np.ones(len(grp), dtype=bool)
        if len(grp) > 1:
            same_as_prev[1:] = (layers[1:] == layers[:-1]) & (parents[1:] == parents[:-1])
        run_lengths = []
        run = 0
        t_vals = grp["t_rel"].to_numpy()
        run_start_t = t_vals[0] if len(t_vals) else 0
        for i, same in enumerate(same_as_prev):
            if same:
                run += 1
            else:
                if run > 0:
                    run_lengths.append(t_vals[i - 1] - run_start_t)
                run = 1
                run_start_t = t_vals[i]
        if run > 0:
            run_lengths.append(t_vals[-1] - run_start_t)
        hop_stability_duration = max(run_lengths) if run_lengths else 0.0

        rows.append({
            "node_id": node_id,
            "source_file": source_file,
            "window_start": grp["window_start"].iloc[0],
            "ParentSwitchRate": parent_switch_rate,
            "LayerChangeCount": n_layer_changes,
            "HopStabilityDuration": hop_stability_duration,
        })

    return pd.DataFrame(rows)


# ─────────────────────────────────────────────────────────────────────────
# D. Physical Layer Features (Equations 4.9, 4.10, 4.11)
# ─────────────────────────────────────────────────────────────────────────

def compute_physical_layer_features(
    windowed: pd.DataFrame,
    filled_long: pd.DataFrame,
) -> pd.DataFrame:
    """
    RSSI_mean, RSSI_var: already computed by M6 as rssi_dbm_mean /
    rssi_dbm_var — just renamed here to match Table 4.12's exact column
    names so M8's plotting code can reference the spec's names directly.

    RSSI_stability (Eq 4.11): longest continuous interval, in seconds,
    where RSSI stays within ±3 dBm of the WINDOW MEAN. Needs the raw
    per-second RSSI sequence, same reason as the topology features above
    — computed from filled_long, not from the already-aggregated mean.
    """
    out = pd.DataFrame(index=windowed.index)
    out["RSSI_mean"] = windowed["rssi_dbm_mean"]
    out["RSSI_var"] = windowed["rssi_dbm_var"]

    long_df = filled_long.copy()
    long_df["window_idx"] = (long_df["t_rel"] // WINDOW_SECONDS).astype(int)
    long_df["window_start"] = long_df["window_idx"] * WINDOW_SECONDS

    stability_rows = []
    for (node_id, source_file, window_idx), grp in long_df.groupby(
        ["node_id", "_source_file", "window_idx"]
    ):
        grp = grp.sort_values("t_rel")
        rssi = grp["rssi_dbm"].to_numpy()
        t_vals = grp["t_rel"].to_numpy()
        valid = ~np.isnan(rssi)

        if valid.sum() == 0:
            stability_rows.append({
                "node_id": node_id, "source_file": source_file,
                "window_start": grp["window_start"].iloc[0],
                "RSSI_stability": 0.0,
            })
            continue

        window_mean = np.nanmean(rssi)
        within_band = np.where(valid, np.abs(rssi - window_mean) <= 3.0, False)

        run_lengths = []
        run = 0
        run_start_t = t_vals[0] if len(t_vals) else 0
        for i, ok in enumerate(within_band):
            if ok:
                run += 1
            else:
                if run > 0:
                    run_lengths.append(t_vals[i - 1] - run_start_t)
                run = 0
                run_start_t = t_vals[i] if i + 1 < len(t_vals) else t_vals[i]
        if run > 0:
            run_lengths.append(t_vals[-1] - run_start_t)

        stability_rows.append({
            "node_id": node_id, "source_file": source_file,
            "window_start": grp["window_start"].iloc[0],
            "RSSI_stability": max(run_lengths) if run_lengths else 0.0,
        })

    stability_df = pd.DataFrame(stability_rows)
    return out, stability_df


# ─────────────────────────────────────────────────────────────────────────
# E. Cross-Layer Inconsistency Features (Equations 4.12-4.15)
# ─────────────────────────────────────────────────────────────────────────

def compute_cross_layer_features(
    windowed: pd.DataFrame,
    baseline_rssi_by_layer: dict[int, float] | None = None,
) -> pd.DataFrame:
    """
    RSSI_Hop_Diff (Eq 4.12/4.13): |observed RSSI - baseline median RSSI
    for this layer|, where the baseline median is computed empirically
    per the thesis ("derived empirically from the baseline windows of
    the same experimental run").

    If baseline_rssi_by_layer is not supplied, this function computes it
    itself from windows where window_label == 0 (baseline) in the
    SAME windowed DataFrame passed in — matching the thesis's "same
    experimental run" requirement, since this function operates on
    one experiment's windowed table at a time.

    LatencyHopRatio (Eq 4.14): NaN here — needs Mean RTT from probe/
    response exchanges, which requires a response message the current
    firmware does not send (victim->root probes are one-way; there is
    no root->victim response leg to time a round trip on). Flagged
    rather than computed from a wrong proxy.
    """
    out = pd.DataFrame(index=windowed.index)

    if baseline_rssi_by_layer is None:
        baseline_mask = windowed["window_label"] == 0
        baseline_rssi_by_layer = (
            windowed.loc[baseline_mask]
            .groupby("layer")["rssi_dbm_mean"]
            .median()
            .to_dict()
        )

    def lookup_baseline(layer):
        return baseline_rssi_by_layer.get(layer, np.nan)

    expected_rssi = windowed["layer"].map(lookup_baseline)
    out["RSSI_Hop_Diff"] = (windowed["rssi_dbm_mean"] - expected_rssi).abs()

    # LatencyHopRatio — blocked on firmware (no RTT response leg exists).
    out["LatencyHopRatio"] = np.nan

    return out


# ─────────────────────────────────────────────────────────────────────────
# F. Auxiliary Tunnel Features (Equations 4.16, 4.17) — attacker nodes only
# ─────────────────────────────────────────────────────────────────────────

def compute_tunnel_features(windowed: pd.DataFrame) -> pd.DataFrame:
    """
    TunnelIntensity (Eq 4.16), TunnelBytes, TunnelLatency (Eq 4.17).

    Per thesis Table 4.12: "present only for attacker nodes during
    topology-distortion runs; for all other nodes and phases, these fields
    are null or zero." In this testbed the topology-distortion attacker is
    the WORMHOLE pair, whose firmware (wormhole_victim.c) records tunnel
    activity into the shared 11-column schema — no dedicated tunnel columns
    needed, exactly like the blackhole attacker overloads its counters:

        Node B (node_role == "wormhole_b", entry): retry_count = probes
            TUNNELLED to A over the wired UART link (0 in baseline, climbs
            during the wormhole phase). -> retry_count_delta per window.
        Node A (node_role == "wormhole_a", exit): probes_count = tunnel
            frames RECEIVED from B over UART (0 until attack). ->
            probes_count_delta per window.

    Both are the per-endpoint tunnel-message count, so per 5 s window:
        TunnelIntensity = tunnel_msgs_delta / WINDOW_SECONDS   (msgs/second)
        TunnelBytes     = tunnel_msgs_delta * TUNNEL_FRAME_BYTES

    These stay NaN for victim/root rows and for baseline/blackhole runs
    (no wormhole endpoints present) — "null or zero for all other nodes and
    phases" per the spec. During baseline phases of a wormhole run the
    deltas are ~0, so TunnelIntensity/TunnelBytes are ~0 there, which is the
    "or zero" half of the same spec note.

    TunnelLatency stays NaN on purpose: the A<->B tunnel is a ONE-WAY UART
    write (B -> A, wormhole_victim.c tunnel_forwarder_task), with no echo
    leg back to B, so there is no round trip to time. Flagged rather than
    faked from a wrong proxy — same honesty rule as LatencyHopRatio.
    """
    out = pd.DataFrame(index=windowed.index)
    out["TunnelIntensity"] = np.nan
    out["TunnelBytes"] = np.nan
    out["TunnelLatency"] = np.nan  # one-way UART tunnel: no RTT leg exists

    if "node_role" not in windowed.columns:
        return out

    def _fill(mask: pd.Series, msg_col: str) -> None:
        if mask.any() and msg_col in windowed.columns:
            # Cumulative counters only ever climb; clip defends against a
            # counter reset (node reboot mid-run) yielding a negative delta.
            msgs = windowed.loc[mask, msg_col].clip(lower=0)
            out.loc[mask, "TunnelIntensity"] = msgs / WINDOW_SECONDS
            out.loc[mask, "TunnelBytes"] = msgs * TUNNEL_FRAME_BYTES

    _fill(windowed["node_role"] == "wormhole_b", "retry_count_delta")
    _fill(windowed["node_role"] == "wormhole_a", "probes_count_delta")

    return out


# ─────────────────────────────────────────────────────────────────────────
# Orchestration
# ─────────────────────────────────────────────────────────────────────────

def compute_features(
    windowed: pd.DataFrame,
    filled_long: pd.DataFrame,
    arrivals_dir: str | None = None,
) -> pd.DataFrame:
    """
    Compute all 16 Table 4.11 features and attach them to windowed,
    returning one combined feature table matching Table 4.12's schema
    (plus the identity/metadata columns M6 already provides).

    Parameters
    ----------
    windowed : the M6 windowed output (preprocess.run_pipeline()[0])
    filled_long : the M6 gap-filled long-format table
                  (preprocess.run_pipeline()[2])
    arrivals_dir : folder containing *_arrivals.csv (root's probe-arrival
                   log). If None, PDR is NaN for every row.

    Returns
    -------
    A copy of windowed with 16 feature columns appended, plus a
    'missing_firmware_fields' column listing (comma-separated) which of
    the 16 features are NaN due to a firmware gap rather than a real
    absence of signal — see module docstring for which three those are.
    """
    fwd = compute_forwarding_features(windowed)
    link = compute_link_reliability_features(windowed)
    topo = compute_topology_stability_features(windowed, filled_long)
    phy, rssi_stab = compute_physical_layer_features(windowed, filled_long)
    cross = compute_cross_layer_features(windowed)
    tunnel = compute_tunnel_features(windowed)

    result = windowed.copy()
    result = pd.concat([result, fwd, link, phy, cross, tunnel], axis=1)

    # topo and rssi_stab are keyed by (node_id, source_file, window_start)
    # rather than positional index, since they're computed via groupby
    # over filled_long which has a different row count than windowed.
    # Merge them in rather than concat.
    result = result.merge(
        topo, on=["node_id", "source_file", "window_start"], how="left"
    )
    result = result.merge(
        rssi_stab, on=["node_id", "source_file", "window_start"], how="left"
    )

    if arrivals_dir is not None:
        pdr = compute_pdr_features(windowed, arrivals_dir)
        result["PDR"] = pdr["PDR"].values
        if "_pdr_clipped" in pdr.columns:
            result["_pdr_clipped"] = pdr["_pdr_clipped"].values
        # LatencyHopRatio / TunnelLatency also come from the arrivals log;
        # they overwrite the NaN placeholders set by the cross-layer and
        # tunnel blocks above (see compute_latency_features for why those
        # placeholders existed and what changed).
        lat = compute_latency_features(windowed, arrivals_dir)
        result["LatencyHopRatio"] = lat["LatencyHopRatio"].values
        result["TunnelLatency"] = lat["TunnelLatency"].values
    else:
        result["PDR"] = np.nan

    result["Label"] = result["window_label"]

    blocked = ",".join(FEATURES_BLOCKED_ON_FIRMWARE)
    result["missing_firmware_fields"] = blocked

    return result


# ─────────────────────────────────────────────────────────────────────────
# CLI
# ─────────────────────────────────────────────────────────────────────────

def main():
    import argparse
    from preprocess import run_pipeline

    parser = argparse.ArgumentParser(
        description="NIS16 Milestone 7 — Cross-Layer Feature Engineering"
    )
    parser.add_argument("input_dir", help="Folder of raw *_telem.csv files")
    parser.add_argument(
        "-o", "--output", default="feature_table.csv",
        help="Output path for the feature table (default: feature_table.csv)",
    )
    parser.add_argument(
        "--arrivals-dir", default=None,
        help="Folder containing *_arrivals.csv for PDR computation "
             "(defaults to input_dir if not specified)",
    )
    args = parser.parse_args()

    arrivals_dir = args.arrivals_dir or args.input_dir

    print(f"Running M6 preprocessing on: {args.input_dir}")
    windowed, report, filled = run_pipeline(args.input_dir)
    print(report.summary())

    print()
    print(f"Computing 16 Table 4.11 features...")
    feature_table = compute_features(windowed, filled, arrivals_dir=arrivals_dir)

    feature_table.to_csv(args.output, index=False)
    print(f"Wrote {len(feature_table)} feature rows to: {args.output}")

    nan_counts = {}
    for col in [
        "ForwardingRatio", "IngressEgressDelta", "RetryRate", "PDR",
        "ParentSwitchRate", "LayerChangeCount", "HopStabilityDuration",
        "RSSI_mean", "RSSI_var", "RSSI_stability",
        "RSSI_Hop_Diff", "LatencyHopRatio", "ConsistencyScore",
        "TunnelIntensity", "TunnelBytes", "TunnelLatency",
    ]:
        if col in feature_table.columns:
            nan_counts[col] = feature_table[col].isna().sum()

    print()
    print("── Feature NaN Counts ──────────────────────────────")
    total = len(feature_table)
    has_nodes = "node_id" in feature_table.columns
    for col, n in nan_counts.items():
        # The hint used to be static text keyed only on the column NAME, so a
        # wormhole run printed "TunnelIntensity: 1616/2470 NaN [ATTACKER-ONLY:
        # needs a wormhole run]" while that very column held 854 real values on
        # both tunnel ends. Read literally it says the attack never happened.
        # Describe what the data actually shows instead.
        if n == total:
            if col in FEATURES_BLOCKED_ON_FIRMWARE:
                flag = " [all-NaN — RELAY-NODE ONLY: needs a blackhole run]"
            elif col.startswith("Tunnel"):
                flag = " [all-NaN — TUNNEL-END ONLY: needs a wormhole run]"
            else:
                flag = " [all-NaN]"
        elif n:
            carriers = (feature_table.loc[feature_table[col].notna(), "node_id"].nunique()
                        if has_nodes else 0)
            flag = (f" [{total - n} value(s) on {carriers} node(s) — "
                    f"not applicable elsewhere]")
        else:
            flag = ""
        if col == "LatencyHopRatio":
            flag += " [relative one-way delay — see thesis-deviate.md]"
        print(f"  {col}: {n}/{total} NaN{flag}")
    print("─────────────────────────────────────────────────────")


if __name__ == "__main__":
    main()

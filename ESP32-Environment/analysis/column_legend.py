"""
column_legend.py — plain-language legend for every CSV column in the pipeline.

Writes <name>_legend.csv NEXT TO a data CSV, one row per column that file
actually has: what it is, its unit / allowed values, and the caveats that
matter when reading it (several raw counters mean different things on
different roles — see docs/DATA-DICTIONARY.md, which this mirrors).

Why a separate file and not a header block inside the data CSV: every reader
in this repo (pandas, validate_integrity.py, preprocess.py's *_telem.csv glob)
expects row 1 to be the header and every later row to be data. Comment or
legend rows inside the file would break them, and capture CSVs never carry
metadata rows (see the SD provenance rule). A `_legend.csv` suffix matches
none of the pipeline's globs (*_telem.csv, *_arrivals.csv, feature_table.csv).

Called automatically by preprocess.py and features.py after they write their
output. Can also be run by hand on any CSV, e.g. a raw capture:

    python column_legend.py path/to/child_node2_..._telem.csv
    python column_legend.py path/to/file.csv -o somewhere/legend.csv
"""

from __future__ import annotations

import csv
import os
import sys

# (group, meaning, unit / values, notes)
_L = {}


def _add(col, group, meaning, unit="", notes=""):
    _L[col] = (group, meaning, unit, notes)


# ── Raw telemetry, written by the board (csv_logger.c) ─────────────────────
_add("timestamp_us", "Raw (board)",
     "Time this row was logged, since THIS board powered on (one row every 0.1 s)",
     "microseconds",
     "Not wall-clock and not synchronised between boards — never compare "
     "timestamps across two boards.")
_add("node_id", "Raw (board)", "Which board wrote the row",
     "NODE_<12-hex Wi-Fi MAC>")
_add("role", "Raw (board)", "What the board was flashed as",
     "victim | blackhole | wormhole_a | wormhole_b | root",
     "wormhole_b = tunnel entry, wormhole_a = tunnel exit.")
_add("layer", "Raw (board)",
     "Depth of the node in the mesh tree (ESP-WIFI-MESH numbering)",
     "1 = root, 2 = direct child of root, ... ; -1 = no parent",
     "Mesh tree depth, NOT an OSI layer. hop = layer - 1.")
_add("parent_mac", "Raw (board)",
     "Wi-Fi address of the node this board is connected up to",
     "MAC address",
     "00:00:00:00:00:00 on the root and whenever the node has no parent.")
_add("rssi_dbm", "Raw (board)",
     "Signal strength of the link from this node to its parent (one link only)",
     "dBm (closer to 0 = stronger, e.g. -40 strong, -85 weak)",
     "0 is a placeholder meaning 'no parent link', not a reading — always 0 on "
     "the root. Does not add up across hops.")
_add("retry_count", "Raw (board)",
     "Running total of sends that FAILED at the application layer",
     "count, cumulative since boot",
     "NOT an 802.11 radio retransmission count. Meaning depends on role: "
     "victim = failed esp_mesh_send() calls; blackhole (schema v1) = probes it "
     "deliberately DROPPED (the attack's own counter); root = failed phase "
     "broadcasts; wormhole_b = probes tunnelled to A; wormhole_a = "
     "re-injection failures.")
_add("tx_count", "Raw (board)",
     "Running total of messages this node sent (transmit count)",
     "count, cumulative since boot",
     "Meaning depends on role: victim = probes handed to the mesh stack "
     "(equals probes_count on every victim row; accepted is not the same as "
     "delivered); blackhole = probes forwarded on to the root; root = "
     "successful phase broadcasts; wormhole_b = probes sent direct to root; "
     "wormhole_a = probes re-injected toward the root.")
_add("probes_count", "Raw (board)",
     "Running total of probe packets (the small test messages every victim "
     "sends to the root — once a second, or 4 per second in the high-load build — so delivery can be measured)",
     "count, cumulative since boot",
     "Meaning depends on role: victim = probes it CREATED; blackhole = probes "
     "it RECEIVED from victims to relay; root = probes received; wormhole_b = "
     "probes generated; wormhole_a = probes received from B over the tunnel.")
_add("probes_received", "Raw (board)",
     "Root's running total of probes received from the mesh (arrivals file)",
     "count, cumulative since boot")
_add("phase_id", "Raw (board)",
     "Experiment phase the root had announced when this row was logged",
     "0 baseline | 1 blackhole | 2 wormhole | 3 cooldown | 4 terminate | "
     "255 not heard yet",
     "255 = the node hasn't received the root's first phase broadcast yet.")
_add("gt_label", "Raw (board)",
     "Ground-truth attack label for this row",
     "0 normal | 1 blackhole | 2 wormhole | 255 unknown",
     "Cooldown and terminate both count as 0 (normal).")
_add("recv_count", "Raw (board)",
     "Running total of packets received from another node FOR RELAY "
     "(not ones this node created)",
     "count, cumulative since boot",
     "Schema v2 only. Same meaning on every role. Honest nodes report 0: the "
     "mesh stack relays below the app layer, where the app can't count it.")
_add("forward_count", "Raw (board)",
     "Running total of relay packets this node passed on toward the root",
     "count, cumulative since boot", "Schema v2 only. Same meaning on every role.")
_add("drop_count", "Raw (board)",
     "Running total of relay packets this node received and did NOT pass on",
     "count, cumulative since boot",
     "Schema v2 only. Same meaning on every role. The blackhole's drops land here.")
_add("src_mac", "Raw (board)",
     "Which victim sent the probe that just arrived (arrivals file, root only)",
     "MAC address")
_add("seq_num", "Raw (board)",
     "Probe sequence number, counted per sending victim",
     "integer, increases by 1 per probe",
     "Used to join root arrivals to victims — never join on time.")
_add("latency_us", "Raw (board)",
     "Root clock at arrival minus victim clock at sending",
     "microseconds",
     "Mixes two unsynchronised clocks, so the raw value includes a large "
     "constant offset (often hugely negative). Only differences within one "
     "victim mean anything.")

# ── Windowed dataset, added by preprocess.py ────────────────────────────────
_add("window_start", "Windowed (preprocess)",
     "Start of this 1-second window, measured from the start of the node's log",
     "seconds")
_add("source_file", "Windowed (preprocess)",
     "Name of the raw capture CSV this window came from")
_add("attack", "Windowed (preprocess)",
     "Attack scenario of the run, from the folder name",
     "baseline | blackhole | wormhole")
_add("topology", "Windowed (preprocess)",
     "Mesh layout of the run, from the folder name", "e.g. linear | star | tree")
_add("location", "Windowed (preprocess)",
     "Where the run was recorded, from the folder name",
     "e.g. home | G402 | DLSU_Library | Goks; 'unrecorded' if the folder has none")
_add("scenario", "Windowed (preprocess)",
     "Optional sub-scenario from the folder name",
     "'stationary' if not given (= run.ps1 -Scenario none)")
_add("run_repeat", "Windowed (preprocess)",
     "Repeat number of the run, from the _r1_/_r2_/_r3_ tag in the filename",
     "integer")
_add("node_role", "Windowed (preprocess)",
     "The board's role (copied from raw 'role')",
     "victim | blackhole | wormhole_a | wormhole_b | root")
_add("hop", "Windowed (preprocess)",
     "How many hops this node is from the root",
     "0 = root, 1 = direct child, ...",
     "hop = layer - 1. Use this in the paper rather than 'layer'.")
_add("n_samples_present", "Windowed (preprocess)",
     "How many raw samples actually landed in this window (boards log at 10 Hz)",
     "count, 10 = complete window",
     "Lower than n_samples_expected = rows missing (logging gap or reboot).")
_add("n_samples_expected", "Windowed (preprocess)",
     "How many raw samples a complete window should have",
     "count (10 = 10 Hz x 1 s window)")
_add("rssi_dbm_mean", "Windowed (preprocess)",
     "Average signal strength to parent in this window", "dBm",
     "0 placeholders are blanked to empty before averaging.")
_add("rssi_dbm_var", "Windowed (preprocess)",
     "Variance of signal strength in this window", "dBm²")
_add("rssi_dbm_min", "Windowed (preprocess)",
     "Weakest signal reading in this window", "dBm")
_add("rssi_dbm_max", "Windowed (preprocess)",
     "Strongest signal reading in this window", "dBm")

for _base in ("retry_count", "tx_count", "probes_count",
              "recv_count", "forward_count", "drop_count"):
    _add(f"{_base}_delta", "Windowed (preprocess)",
         f"How much {_base} went up during this window (_last - _first)",
         "count per window (never negative)",
         f"The per-window version of the running total — see '{_base}' for "
         "what is being counted on each role.")
    _add(f"{_base}_reset_detected", "Windowed (preprocess)",
         f"True if {_base} went DOWN inside the window or since the previous "
         "window ended (board rebooted and the counter restarted from 0)",
         "True | False",
         "When True, the _delta for this window was forced to 0 and is not trustworthy.")
    _add(f"{_base}_first", "Windowed (preprocess)",
         f"Running total {_base} at the START edge of the window (the previous "
         "window's last row; this window's first row when there is no "
         "directly preceding kept window)", "count")
    _add(f"{_base}_last", "Windowed (preprocess)",
         f"Running total {_base} at the last row of the window", "count")

_add("window_label", "Windowed (preprocess)",
     "Ground-truth label for the window",
     "0 normal | 1 blackhole | 2 wormhole | empty = unlabelled",
     "Empty outside the three real phases (e.g. pre_baseline), so those "
     "windows never enter a normal or attack group.")
_add("window_phase_id", "Windowed (preprocess)",
     "Most common phase_id among the window's raw rows",
     "0 baseline | 1 blackhole | 2 wormhole | 3 cooldown | 4 terminate | 255 not heard yet")
_add("t_anchor_s", "Windowed (preprocess)",
     "Time relative to the moment THIS node first left phase 0 (attack start "
     "as seen by this node)",
     "seconds (negative = before the attack started)",
     "Lets windows from different boards be lined up without shared clocks.")
_add("segment", "Windowed (preprocess)",
     "Which part of the experiment the window belongs to",
     "pre_baseline | baseline | attack | cooldown | baseline_rebroadcast | no_phase_seen",
     "pre_baseline = node was up before the experiment's baseline started; "
     "unlabelled and excluded from analysis, but kept.")

# ── Feature table, added by features.py (thesis Table 4.11) ─────────────────
_add("ForwardingRatio", "Feature (features.py)",
     "Share of relay packets the node actually passed on", "0-1 (1 = forwarded everything)",
     "Only defined on a node that relays (the blackhole attacker); empty elsewhere.")
_add("IngressEgressDelta", "Feature (features.py)",
     "Relay packets received minus forwarded", "packets per window",
     "Only defined on a relaying node.")
_add("ConsistencyScore", "Feature (features.py)",
     "How far ForwardingRatio is from 1", "0-1, = |ForwardingRatio - 1|",
     "Only defined on a relaying node.")
_add("RetryRate", "Feature (features.py)",
     "Failed sends ÷ all send attempts in the window", "0-1",
     "Built from retry_count, so it is NOT a radio retransmission rate. "
     "Excluded as label leakage only on pre-F3 captures (no drop_count) or "
     "when a wormhole Node B is present (leakage.retry_count_is_overloaded).")
_add("PDR", "Feature (features.py)",
     "Packet Delivery Ratio: share of this victim's probes the root received",
     "0-1 (1 = all delivered)",
     "Victims only. Matched by sequence number, not by time.")
_add("_pdr_clipped", "Feature (features.py)",
     "True if PDR came out above 1 and was capped", "True | False",
     "Happens when duplicates (e.g. wormhole copies) arrive; worth checking.")
_add("ParentSwitchRate", "Feature (features.py)",
     "How often the node changed parent", "parent changes per second")
_add("HopChangeCount", "Feature (features.py)",
     "How many times the node's tree depth changed in the window", "count")
_add("HopStabilityDuration", "Feature (features.py)",
     "Longest stretch in the window with the same parent AND same depth",
     "seconds")
_add("RSSI_mean", "Feature (features.py)",
     "Average signal strength to parent (same as rssi_dbm_mean)", "dBm")
_add("RSSI_var", "Feature (features.py)",
     "Signal strength variance (same as rssi_dbm_var)", "dBm²")
_add("RSSI_stability", "Feature (features.py)",
     "Longest stretch in the window where signal stayed within ±3 dBm of its mean",
     "seconds")
_add("RSSI_Hop_Diff", "Feature (features.py)",
     "How far the signal is from what's normal for this depth",
     "dB, = |RSSI - baseline median RSSI at this layer|",
     "Baseline median comes from the same run's baseline windows.")
_add("LatencyHopRatio", "Feature (features.py)",
     "Extra delivery delay per hop, compared with this victim's fastest "
     "delivery in the run",
     "milliseconds per hop",
     "Relative one-way delay, not round-trip (no reply leg exists).")
_add("TunnelIntensity", "Feature (features.py)",
     "Messages sent through the wormhole tunnel", "messages per second",
     "Wormhole tunnel ends only; empty elsewhere.")
_add("TunnelBytes", "Feature (features.py)",
     "Data sent through the wormhole tunnel", "bytes per window",
     "Wormhole tunnel ends only.")
_add("TunnelLatency", "Feature (features.py)",
     "Time gap between two copies of the same probe arriving at the root "
     "(slow mesh path vs fast tunnel)",
     "milliseconds", "Empty when no duplicate arrivals.")
_add("Label", "Feature (features.py)",
     "Final ground-truth label used for analysis (copy of window_label)",
     "0 normal | 1 blackhole | 2 wormhole | empty = unlabelled")
_add("missing_firmware_fields", "Feature (features.py)",
     "Features that are only defined on relaying nodes and may be empty here",
     "comma-separated feature names",
     "Same text on every row; informational only.")


FIELDS = ["column", "group", "meaning", "unit_or_values", "notes"]


def legend_rows(columns) -> list[dict]:
    rows = []
    for col in columns:
        group, meaning, unit, notes = _L.get(
            col, ("Unknown", "(no legend entry — add one in analysis/column_legend.py)", "", ""))
        rows.append(dict(zip(FIELDS, (col, group, meaning, unit, notes))))
    return rows


def default_legend_path(data_path: str) -> str:
    stem, _ = os.path.splitext(data_path)
    return stem + "_legend.csv"


def write_legend(columns, data_path: str, out_path: str | None = None) -> str:
    """Writes the legend for `columns` beside data_path (or to out_path)."""
    out_path = out_path or default_legend_path(data_path)
    # utf-8-sig so Excel shows ±, ÷, ² correctly instead of mojibake.
    with open(out_path, "w", newline="", encoding="utf-8-sig") as f:
        w = csv.DictWriter(f, fieldnames=FIELDS)
        w.writeheader()
        w.writerows(legend_rows(columns))
    return out_path


def main():
    import argparse
    p = argparse.ArgumentParser(description="Write a column legend for a CSV.")
    p.add_argument("csv_path")
    p.add_argument("-o", "--output", default=None,
                   help="Legend path (default: <csv name>_legend.csv beside it)")
    args = p.parse_args()
    with open(args.csv_path, newline="", encoding="utf-8-sig") as f:
        header = next(csv.reader(f))
    out = write_legend(header, args.csv_path, args.output)
    unknown = [c for c in header if c not in _L]
    print(f"Wrote legend for {len(header)} columns to: {out}")
    if unknown:
        print(f"  no entry for: {', '.join(unknown)}", file=sys.stderr)


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""
verify_topology.py — Milestone 3 (Multi-Topology Testbed Deployment) checker.

Reconstructs the mesh parent-child structure from the per-node telemetry CSVs of
a single run and verifies the Milestone-3 criteria:

  * Each topology converges to its intended structure within 60 s.
  * Structure is verifiable from parent-MAC and layer values.
  * The mesh is stable through the baseline phase (no spontaneous re-routing).

How the tree is rebuilt without extra logging
----------------------------------------------
Each node logs `node_id` (derived from its Wi-Fi STA MAC) and `parent_mac`
(its parent's SoftAP BSSID). On the ESP32 the SoftAP MAC is always the STA MAC
+ 1, so a child's parent STA MAC = parent_mac - 1. That lets us map every
`parent_mac` back to the node that owns it and draw the tree.

Usage
-----
    python verify_topology.py --dir exports --topology star --attack none --repeat 1
    python verify_topology.py --files root_*.csv victim_*.csv --expect star

Standard library only — no pandas/pyserial needed.

NIS16 — CTTHES2 Milestone 3
"""

import argparse
import csv
import glob
import os
import sys
from collections import Counter, defaultdict

# Phase IDs (mirror mesh_config.h).
PHASE_BASELINE = 0

# Mesh-formation window before Phase 0 really begins — PHASE_STABILISE_S in
# components/mesh_common/include/mesh_config.h. Rows logged before the root's
# first phase broadcast reaches a node are stamped PHASE_ID_BASELINE by
# default (phase_listener.c), so a node's INITIAL parent acquisition looks
# like a baseline re-route unless this window is excluded. Milestone 3 asks
# two separate questions — "converges within 60 s" and "stable through the
# 5-minute baseline" — and counting formation as instability conflates them.
STABILISE_S = 60.0

# ESP-WIFI-MESH reports the root at layer 1.
ROOT_LAYER = 1

ZERO_MAC = "00:00:00:00:00:00"


# ── MAC helpers ─────────────────────────────────────────────────────────────
def mac_to_int(mac: str) -> int:
    return int(mac.replace(":", "").replace("-", ""), 16)


def int_to_mac(v: int) -> str:
    b = v.to_bytes(6, "big")
    return ":".join(f"{x:02X}" for x in b)


def node_id_to_sta_int(node_id: str):
    """NODE_F42DC973E618 -> integer STA MAC, or None if unparseable."""
    hexpart = node_id.replace("NODE_", "").strip()
    if len(hexpart) != 12:
        return None
    try:
        return int(hexpart, 16)
    except ValueError:
        return None


# ── Per-node summary ────────────────────────────────────────────────────────
class NodeSummary:
    def __init__(self, node_id, role, stabilise_s=STABILISE_S):
        self.node_id = node_id
        self.role = role
        self.stabilise_s = stabilise_s
        # Changes seen during the formation window, excluded from the
        # baseline-stability verdict but reported so the exclusion is visible.
        self.formation_changes = 0
        self.sta_int = node_id_to_sta_int(node_id)
        self.samples = 0
        self.first_ts = None
        self.last_ts = None
        self.layers = []            # (ts, layer)
        self.parents = []           # (ts, parent_mac)
        self.parent_switches = 0
        self.layer_changes = 0
        self.baseline_parent_switches = 0
        self.baseline_layer_changes = 0
        self.converge_ts = None     # first ts at final (layer, parent)
        self.final_layer = None
        self.final_parent = None

    def add(self, ts, layer, parent_mac, phase_id):
        self.samples += 1
        if self.first_ts is None:
            self.first_ts = ts
        self.last_ts = ts

        # Seconds since THIS node started logging. Each board's esp_timer
        # starts at its own boot, so a node-relative clock is the only one
        # available here; children boot before the root, which is exactly
        # why their formation shows up inside their own first seconds.
        t_rel = (ts - self.first_ts) / 1e6
        forming = t_rel < self.stabilise_s

        if self.layers and self.layers[-1][1] != layer:
            self.layer_changes += 1
            if phase_id == PHASE_BASELINE:
                if forming:
                    self.formation_changes += 1
                else:
                    self.baseline_layer_changes += 1
        # Ignore the transient all-zero parent before the node has a parent.
        if self.parents and self.parents[-1][1] != parent_mac and parent_mac != ZERO_MAC:
            self.parent_switches += 1
            if phase_id == PHASE_BASELINE:
                if forming:
                    self.formation_changes += 1
                else:
                    self.baseline_parent_switches += 1

        self.layers.append((ts, layer))
        self.parents.append((ts, parent_mac))

    def finalize(self):
        if not self.layers:
            return
        self.final_layer = self.layers[-1][1]
        # Final parent = last non-zero parent (root stays zero).
        self.final_parent = ZERO_MAC
        for _, p in reversed(self.parents):
            if p != ZERO_MAC:
                self.final_parent = p
                break
        # Convergence = earliest ts from which (layer, parent) never changed.
        target = (self.final_layer, self.final_parent)
        conv = None
        for (tsl, layer), (tsp, parent) in zip(self.layers, self.parents):
            eff_parent = parent if parent != ZERO_MAC else self.final_parent
            if (layer, eff_parent) == target:
                if conv is None:
                    conv = tsl
            else:
                conv = None
        self.converge_ts = conv

    def converge_seconds(self):
        if self.converge_ts is None or self.first_ts is None:
            return None
        return (self.converge_ts - self.first_ts) / 1e6


# ── Load a run ──────────────────────────────────────────────────────────────
def load_files(paths, stabilise_s=STABILISE_S):
    nodes = {}
    for path in paths:
        with open(path, newline="", encoding="utf-8") as f:
            reader = csv.DictReader(f)
            if reader.fieldnames is None or "node_id" not in reader.fieldnames:
                continue
            for row in reader:
                nid = row["node_id"]
                if nid not in nodes:
                    nodes[nid] = NodeSummary(nid, row.get("role", "?"),
                                             stabilise_s=stabilise_s)
                try:
                    ts = int(row["timestamp_us"])
                    layer = int(row["layer"])
                    phase = int(row["phase_id"])
                except (ValueError, KeyError):
                    continue
                nodes[nid].add(ts, layer, row["parent_mac"], phase)
    for n in nodes.values():
        n.finalize()
    return nodes


def resolve_files(args):
    if args.files:
        out = []
        for pat in args.files:
            out.extend(glob.glob(pat) if any(c in pat for c in "*?[") else [pat])
        return [p for p in out if p.endswith("telem.csv")] or out
    pattern = os.path.join(
        args.dir, f"*_{args.topology}_{args.attack}_r{args.repeat}_*_telem.csv"
    )
    return sorted(glob.glob(pattern))


# ── Tree reconstruction ─────────────────────────────────────────────────────
def build_tree(nodes):
    """Return (children_of[node_id] -> list, root_id, unresolved[list])."""
    sta_index = {n.sta_int: nid for nid, n in nodes.items() if n.sta_int is not None}
    children = defaultdict(list)
    root_id = None
    unresolved = []
    for nid, n in nodes.items():
        if n.final_parent in (None, ZERO_MAC) or n.final_layer == ROOT_LAYER:
            if n.final_layer == ROOT_LAYER or n.role == "root":
                root_id = nid
            continue
        parent_sta = mac_to_int(n.final_parent) - 1     # SoftAP -> STA
        parent_id = sta_index.get(parent_sta)
        if parent_id is None:
            unresolved.append((nid, n.final_parent))
        else:
            children[parent_id].append(nid)
    return children, root_id, unresolved


def print_tree(children, node_id, nodes, prefix=""):
    n = nodes[node_id]
    role = n.role
    print(f"{prefix}{node_id}  (layer {n.final_layer}, role {role})")
    for i, child in enumerate(sorted(children.get(node_id, []))):
        print_tree(children, child, nodes, prefix + "    ")


# ── Expected-topology checks ────────────────────────────────────────────────
def check_expected(expect, nodes, children, root_id):
    layers = [n.final_layer for n in nodes.values() if n.final_layer is not None]
    if not layers:
        return ["No layer data — cannot check topology."]
    max_layer = max(layers)
    layer_hist = Counter(layers)
    n_non_root = sum(1 for n in nodes.values() if n.final_layer != ROOT_LAYER)
    notes = []

    if expect == "star":
        # All non-root nodes are direct children of root: max layer == 2.
        if max_layer == ROOT_LAYER + 1:
            notes.append(f"PASS star: all {n_non_root} nodes at layer {ROOT_LAYER+1} (direct children of root).")
        else:
            notes.append(f"WARN star: expected max layer {ROOT_LAYER+1}, got {max_layer}.")
    elif expect == "linear":
        # One node per layer -> a chain.
        multi = [ly for ly, c in layer_hist.items() if c > 1]
        if not multi and max_layer >= ROOT_LAYER + 2:
            notes.append(f"PASS linear: one node per layer, depth {max_layer}.")
        else:
            notes.append(f"WARN linear: layer histogram {dict(sorted(layer_hist.items()))} "
                         f"(want exactly one node per layer, depth >= {ROOT_LAYER+2}).")
    elif expect == "tree":
        if max_layer >= ROOT_LAYER + 2:
            notes.append(f"PASS tree: multi-hop depth {max_layer} with intermediate forwarders.")
        else:
            notes.append(f"WARN tree: depth only {max_layer} — looks like a star, not a tree.")
    elif expect == "partial":
        switchers = [nid for nid, n in nodes.items() if n.parent_switches > 0]
        notes.append(f"INFO partial: {len(switchers)} node(s) changed parent during the run "
                     f"(multiple potential parents is expected for a partial mesh).")
    return notes


# ── Main ────────────────────────────────────────────────────────────────────
def main():
    ap = argparse.ArgumentParser(description="Verify mesh topology from telem CSVs.")
    ap.add_argument("--dir", default="exports", help="Folder of exported CSVs.")
    ap.add_argument("--topology", default="star")
    ap.add_argument("--attack", default="none")
    ap.add_argument("--repeat", default="1")
    ap.add_argument("--files", nargs="*", help="Explicit telem CSVs (overrides --dir filters).")
    ap.add_argument("--expect", choices=["star", "tree", "linear", "partial"],
                    help="Assert the intended topology and report PASS/WARN.")
    ap.add_argument("--converge-limit", type=float, default=60.0,
                    help="Convergence deadline in seconds (Milestone-3 criterion).")
    ap.add_argument("--stabilise-s", type=float, default=STABILISE_S,
                    help="Mesh-formation window excluded from the baseline "
                         "re-routing verdict (default: PHASE_STABILISE_S = "
                         f"{STABILISE_S:.0f}s). Use 0 to count every change.")
    args = ap.parse_args()

    paths = resolve_files(args)
    if not paths:
        print("No matching telem CSVs found. Check --dir/--topology/--attack/--repeat "
              "or pass --files.", file=sys.stderr)
        return 2

    print(f"Loaded {len(paths)} telemetry file(s):")
    for p in paths:
        print(f"  - {os.path.basename(p)}")
    print()

    nodes = load_files(paths, stabilise_s=args.stabilise_s)
    if not nodes:
        print("No node rows parsed.", file=sys.stderr)
        return 2

    children, root_id, unresolved = build_tree(nodes)

    # ── Structure ───────────────────────────────────────────────────────────
    print("=== Reconstructed structure ===")
    if root_id:
        print_tree(children, root_id, nodes)
    else:
        print("(!) No root node identified (no node at layer 1).")
    if unresolved:
        print("\n(!) Unresolved parents (parent board not among the loaded files):")
        for nid, pmac in unresolved:
            print(f"    {nid} -> parent BSSID {pmac}")
    print()

    # ── Per-node convergence & stability ────────────────────────────────────
    print("=== Per-node convergence & stability ===")
    all_converged = True
    baseline_stable = True
    for nid in sorted(nodes):
        n = nodes[nid]
        secs = n.converge_seconds()
        conv_str = f"{secs:5.1f}s" if secs is not None else "  n/a"
        ok = secs is not None and secs <= args.converge_limit
        if not ok and n.final_layer != ROOT_LAYER:
            all_converged = False
        if n.baseline_parent_switches or n.baseline_layer_changes:
            baseline_stable = False
        flag = "OK " if ok else "  ?"
        forming = (f"  formation {n.formation_changes}"
                   if n.formation_changes else "")
        print(f"  [{flag}] {nid}  layer={n.final_layer}  converge={conv_str}  "
              f"parent_switches={n.parent_switches} (baseline {n.baseline_parent_switches})  "
              f"layer_changes={n.layer_changes} (baseline {n.baseline_layer_changes})  "
              f"samples={n.samples}{forming}")
    total_forming = sum(n.formation_changes for n in nodes.values())
    if total_forming:
        print(f"\n  ({total_forming} parent/layer change(s) occurred inside the "
              f"first {args.stabilise_s:.0f}s of a node's own log — mesh "
              f"formation, not re-routing. Excluded from the baseline verdict "
              f"below; counted in the totals above. --stabilise-s 0 to include "
              f"them.)")
    print()

    # ── Expected topology ───────────────────────────────────────────────────
    if args.expect:
        print("=== Expected-topology check ===")
        for note in check_expected(args.expect, nodes, children, root_id):
            print(f"  {note}")
        print()

    # ── Verdict ─────────────────────────────────────────────────────────────
    print("=== Milestone-3 verdict ===")
    print(f"  Converged within {args.converge_limit:.0f}s : "
          f"{'YES' if all_converged else 'NO — see nodes marked ?'}")
    print(f"  Baseline re-routing free            : "
          f"{'YES' if baseline_stable else 'NO — parent/layer changed during baseline'}")
    return 0 if (all_converged and baseline_stable) else 1


if __name__ == "__main__":
    raise SystemExit(main())

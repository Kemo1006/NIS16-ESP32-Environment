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
    python verify_topology.py
        Interactive: just asks which topology and location to verify, then
        auto-finds and reports every attack/repeat captured for that combo.
    python verify_topology.py --dir exports --topology star --attack none --repeat 1
    python verify_topology.py --files root_*.csv victim_*.csv --expect star

Standard library only — no pandas/pyserial needed.

NIS16 — CTTHES2 Milestone 3
"""

import argparse
import csv
import glob
import os
import re
import sys
from collections import defaultdict

_THIS_DIR = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, _THIS_DIR)
import topology_graph  # noqa: E402  (same folder; the rules shared with the firmware)

# User-facing topology names (match run.ps1/menu.ps1's -Topology vocabulary and
# --expect's choices below). Only "partial" differs from its own exports/
# folder name - docs/2026-09-14_SETUP-RULES-CONFIG.md C4: "Topology folder
# names: star, tree, linear, partial_mesh".
TOPOLOGIES = ["star", "tree", "linear", "partial"]
TOPOLOGY_DIRNAMES = {"partial": "partial_mesh"}


def topology_dirname(topology):
    return TOPOLOGY_DIRNAMES.get(topology, topology)


REPEAT_RE = re.compile(r"_r(\d+)_")

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


def resolve_files(args, dir_is_default):
    if args.files:
        out = []
        for pat in args.files:
            out.extend(glob.glob(pat) if any(c in pat for c in "*?[") else [pat])
        return [p for p in out if p.endswith("telem.csv")] or out

    # Captures live nested as exports/<attack>/<topology>/<location>/... (see
    # docs/2026-09-14_SETUP-RULES-CONFIG.md C4) - never flat in exports/ itself,
    # so the old non-recursive glob.glob() straight against --dir never matched
    # a single file, no matter what --topology/--attack/--repeat were passed.
    # Scope the walk to <dir>/<attack>/<topology> (recursing through every
    # location under it - --location narrows to just one).
    search_root = os.path.join(args.dir, args.attack, topology_dirname(args.topology))
    if args.location:
        search_root = os.path.join(search_root, args.location)
        # Scenario is one level deeper than location (see docs/2026-09-14_SETUP-
        # RULES-CONFIG.md C4) - narrows further when given; the recursive walk
        # below finds scenario subfolders either way, this just scopes it to
        # one. 'none' is the pre-scenario default and is NEVER a real folder
        # (see export_logs.py's _subdir_for), so an explicit `--scenario none`
        # must not narrow the search at all.
        if getattr(args, "scenario", None) and args.scenario != "none":
            search_root = os.path.join(search_root, args.scenario)
    if not os.path.isdir(search_root):
        if dir_is_default:
            # --dir is still the script default and this attack+topology (nor
            # --location) hasn't been captured under it yet - report that as
            # "nothing found" (main() lists what DOES exist) rather than
            # silently sweeping the WHOLE default exports/ tree by repeat
            # number alone, which would mix unrelated topologies/attacks that
            # just happen to share an "r1" into one bogus reconstructed tree.
            return []
        # --dir was explicitly pointed somewhere (e.g. straight at an already-
        # scoped leaf folder like tools\exports\blackhole\linear\home) - trust
        # it outright and search it as-is; --topology/--attack are redundant
        # in that case since the folder itself already scopes them.
        search_root = args.dir

    r_token = f"_r{args.repeat}_"
    matches = []
    for dirpath, dirnames, filenames in os.walk(search_root):
        # Skip trimmed/ (and any _archive/) copies - they re-save the SAME
        # rows under a different path, so reading both would double every
        # sample and scramble the per-node timestamp order load_files() and
        # every convergence/stability check here assume is monotonic.
        dirnames[:] = [d for d in dirnames if d != "trimmed" and not d.startswith("_archive")]
        for name in sorted(filenames):
            if name.endswith("_telem.csv") and r_token in name:
                matches.append(os.path.join(dirpath, name))
    return sorted(matches)


# ── Structure reconstruction ────────────────────────────────────────────────
# Firmware wrote role="victim" for every plain child until 2026-09-23; it writes
# "child" now. Captures from before that flash keep the old word forever, so both
# are folded to one display name here -- the same canonicalisation preprocess.py
# applies (ROLE_ALIASES). A node is a VICTIM only if an attacker sits between it
# and the root, which is what exposure_of() below decides from the rebuilt tree.
ROLE_ALIASES = {"victim": "child"}
ATTACK_ROLES = ("blackhole", "wormhole_a", "wormhole_b")


def canonical_role(role):
    return ROLE_ALIASES.get(str(role).strip().lower(), str(role).lower())


def exposure_of(nid, nodes, parent_of):
    """'ATTACKER' / 'VICTIM' / 'not in path' / 'root' for one node."""
    n = nodes.get(nid)
    r = canonical_role(getattr(n, "role", "")) if n else ""
    if r == "root":
        return "root"
    if r in ATTACK_ROLES:
        return "ATTACKER"
    if not any(canonical_role(getattr(v, "role", "")) in ATTACK_ROLES
               for v in nodes.values()):
        return "-"
    cur, seen = parent_of.get(nid), {nid}
    while cur is not None and cur not in seen:
        seen.add(cur)
        if canonical_role(getattr(nodes.get(cur), "role", "")) in ATTACK_ROLES:
            return "VICTIM"
        cur = parent_of.get(cur)
    return "not in path"


def _resolve_parent(mac, sta_index):
    """parent_mac (the parent's SoftAP BSSID = STA + 1) -> node_id, or None."""
    if mac in (None, "", ZERO_MAC):
        return None
    try:
        v = mac_to_int(mac)
    except ValueError:
        return None
    return sta_index.get(v - 1) or sta_index.get(v)


def build_graph(nodes):
    """Final parent links -> topology_graph.Graph, plus every parent link seen
    over the run (the union graph a partial mesh is judged on).

    Returns (graph, union_edges, unresolved[(node_id, parent_mac)]). Layers are
    derived from the links (BFS from the root they identify), not read from
    the CSV's layer column."""
    sta_index = {n.sta_int: nid for nid, n in nodes.items() if n.sta_int is not None}
    links, unresolved = {}, []
    for nid, n in nodes.items():
        par = _resolve_parent(n.final_parent, sta_index)
        if par is None and n.final_parent not in (None, "", ZERO_MAC):
            unresolved.append((nid, n.final_parent))
            par = f"unresolved:{n.final_parent}"   # counted in graph.unresolved
        links[nid] = par
    union_edges = []
    for nid, n in nodes.items():
        for mac in {p for _, p in n.parents}:
            par = _resolve_parent(mac, sta_index)
            if par is not None:
                union_edges.append((nid, par))
    return topology_graph.build_graph(links), union_edges, unresolved


def print_structure_banner(graph, nodes, expect=None):
    """The MESH_SETUP topology banner, rebuilt from the CAPTURED CSVs.

    WHY THIS EXISTS
    ---------------
    The firmware already prints this table over serial while a run is live
    (mesh_setup.c). That is useful at the bench and useless afterwards: it
    scrolls past, it is not in the dataset, and a panel cannot be shown it.
    This renders the same view from the exported CSVs, so the structure of any
    run - including archived ones from months ago - can be printed on demand
    and pasted into the paper.

    It also answers two questions asked directly in review:

      * "show which one is parent mac address and child mac address" - the
        UPLINK column is the PARENT of the node on that row. Every other MAC in
        the table is a node's own (child-side) STA MAC.
      * "if you look at the data you will know it's linear topology without
        needing visuals" (adviser, 8:15-9:45) - that is exactly what this is:
        the topology, read out of the data, with no diagram required.

    ⚠️ HOP, not LAYER. Espressif numbers the root layer 1; this prints HOP
    (root = 0), because the panel read "layer" as an OSI layer and it is not -
    see preprocess._layer_to_hop. The raw layer is still what the CSV carries.
    """
    order = []
    stack = [(graph.root, 0)]
    seen = set()
    while stack:
        nid, depth = stack.pop()
        if nid is None or nid in seen:
            continue
        seen.add(nid)
        order.append((nid, depth))
        kids = sorted([k for k, p in graph.parent.items() if p == nid], reverse=True)
        stack.extend((k, depth + 1) for k in kids)

    def mac_of(nid):
        v = node_id_to_sta_int(nid)
        return int_to_mac(v) if v is not None else "??:??:??:??:??:??"

    n_reach = len(order)
    print()
    print("=" * 69)
    print(" MESH TOPOLOGY  (rebuilt from captured CSVs)")
    print(f" TYPE        : {(expect or 'unspecified').upper()}")
    print(f" NODE COUNT  : {len(nodes)}")
    print(f" HOP DEPTH   : {max((d for _n, d in order), default=0)}"
          f"   (root = hop 0)")
    print(f" REACHABLE   : {n_reach} of {len(nodes)}")
    print("-" * 69)
    print(" HOP   MAC ADDRESS        ROLE       EXPOSURE      UPLINK (= ITS PARENT)")
    for nid, depth in order:
        n = nodes[nid]
        par = graph.parent.get(nid)
        uplink = "--:--:--:--:--:--  (root, no parent)" if par is None else mac_of(par)
        exp = exposure_of(nid, nodes, graph.parent)
        print(f" H{depth:02d}   {mac_of(nid)}  "
              f"{canonical_role(n.role).upper():<10} {exp:<13} {uplink}")

    missing = [nid for nid in nodes if nid not in seen]
    for nid in missing:
        n = nodes[nid]
        print(f" ???   {mac_of(nid)}  {canonical_role(n.role).upper():<10} "
              f"{'unknown':<13} NOT REACHABLE FROM ROOT")
    print("-" * 69)
    print(" ROLE is what the board was BUILT as; EXPOSURE is what this run's")
    print(" topology makes it. A child is a VICTIM only when an attacker sits")
    print(" between it and the root - one above the attacker is never touched.")
    print(" UPLINK is the node's PARENT. All other MACs are the node's own.")
    print(" Note: in the raw CSV, parent_mac is the parent's SoftAP BSSID,")
    print(" which is its STA MAC + 1. Resolved here already.")
    print("=" * 69)


def print_tree(graph, nodes, start=None):
    """Depth-first, iterative (a chain can be far deeper than Python's
    recursion limit). Shows the derived layer and flags where the node's own
    logged layer disagrees. start = a detached fragment's top instead of the
    root; its layers can't be derived (the link to the root is missing), so
    only the logged ones are shown."""
    stack = [(graph.root if start is None else start, 0)]
    while stack:
        nid, depth = stack.pop()
        n = nodes[nid]
        derived = graph.layer.get(nid)
        if derived is None:
            label = f"logged layer {n.final_layer}"
        elif n.final_layer == derived:
            label = f"layer {derived}"
        else:
            label = f"layer {derived}, logged {n.final_layer}"
        print(f"{'    ' * depth}{nid}  ({label}, role {canonical_role(n.role)})")
        for child in sorted(graph.children[nid], reverse=True):
            stack.append((child, depth + 1))


# ── Interactive mode ────────────────────────────────────────────────────────
# Triggered when the script is run with none of --topology/--attack/--repeat/
# --location/--files overridden (see main()) - the two questions below are the
# ONLY thing asked; attack and repeat are auto-discovered from whatever is
# actually on disk instead of forcing the old star/none/r1 guess.

def _iter_telem_files(root):
    """Every *_telem.csv under root, skipping trimmed/_archive copies (same
    rows re-saved under another path - see resolve_files' comment)."""
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d != "trimmed" and not d.startswith("_archive")]
        for name in filenames:
            if name.endswith("_telem.csv"):
                yield os.path.join(dirpath, name)


def discover_topologies(exports_dir):
    """User-facing topology names that have >=1 telem CSV under any attack/."""
    dirname_to_topology = {v: k for k, v in TOPOLOGY_DIRNAMES.items()}
    found = set()
    if not os.path.isdir(exports_dir):
        return []
    for attack_name in os.listdir(exports_dir):
        attack_path = os.path.join(exports_dir, attack_name)
        if not os.path.isdir(attack_path):
            continue
        for topo_dirname in os.listdir(attack_path):
            topo_path = os.path.join(attack_path, topo_dirname)
            if not os.path.isdir(topo_path):
                continue
            topology = dirname_to_topology.get(topo_dirname, topo_dirname)
            if topology not in TOPOLOGIES:
                continue
            if any(True for _ in _iter_telem_files(topo_path)):
                found.add(topology)
    return [t for t in TOPOLOGIES if t in found]   # canonical order


def discover_locations(exports_dir, topology):
    """(has_flat, [location names]) for one topology, across every attack."""
    topo_dirname = topology_dirname(topology)
    has_flat = False
    locations = set()
    if os.path.isdir(exports_dir):
        for attack_name in os.listdir(exports_dir):
            topo_path = os.path.join(exports_dir, attack_name, topo_dirname)
            if not os.path.isdir(topo_path):
                continue
            for entry in os.listdir(topo_path):
                entry_path = os.path.join(topo_path, entry)
                if os.path.isfile(entry_path) and entry.endswith("_telem.csv"):
                    has_flat = True
                elif (os.path.isdir(entry_path) and entry != "trimmed"
                      and not entry.startswith("_archive")):
                    if any(True for _ in _iter_telem_files(entry_path)):
                        locations.add(entry)
    return has_flat, sorted(locations)


def discover_groups(exports_dir, topology, location):
    """{(attack, scenario, repeat_str): [paths]} for one topology(+location),
    across every attack. location=None means the flat/pre-location-logging
    layout - only files directly under <attack>/<topology>/, never a location
    subfolder's files (those belong to their own group).

    scenario is the first path component under the location folder (one level
    below --location, see docs/2026-09-14_SETUP-RULES-CONFIG.md C4) - a file
    found directly IN the location folder (no scenario subfolder at all, e.g.
    a pre-scenario capture) groups as scenario='none', which is exactly what
    such a capture's run.ps1 -Scenario would have been. Without this, a 'none'
    r1 and a 'burst' r1 at the same attack/location would wrongly merge into
    one group — they are different runs that happen to share a repeat number."""
    topo_dirname = topology_dirname(topology)
    groups = defaultdict(list)
    if not os.path.isdir(exports_dir):
        return groups
    for attack_name in sorted(os.listdir(exports_dir)):
        topo_path = os.path.join(exports_dir, attack_name, topo_dirname)
        if not os.path.isdir(topo_path):
            continue
        if location:
            loc_path = os.path.join(topo_path, location)
            if not os.path.isdir(loc_path):
                continue
            for path in _iter_telem_files(loc_path):
                rel = os.path.relpath(path, loc_path)
                parts = rel.split(os.sep)
                scenario = parts[0] if len(parts) > 1 else "none"
                m = REPEAT_RE.search(os.path.basename(path))
                repeat = m.group(1) if m else "?"
                groups[(attack_name, scenario, repeat)].append(path)
        else:
            file_iter = (
                os.path.join(topo_path, name)
                for name in sorted(os.listdir(topo_path))
                if name.endswith("_telem.csv")
                and os.path.isfile(os.path.join(topo_path, name))
            )
            for path in file_iter:
                m = REPEAT_RE.search(os.path.basename(path))
                repeat = m.group(1) if m else "?"
                groups[(attack_name, "none", repeat)].append(path)
    return groups


def prompt_choice(title, options, default_index=0):
    print(f"\n{title}")
    for i, opt in enumerate(options, 1):
        marker = "  <- default (press Enter)" if (i - 1) == default_index else ""
        print(f"  [{i}] {opt}{marker}")
    while True:
        raw = input(f"Press Enter to keep [{default_index + 1}], "
                     f"or type 1-{len(options)} > ").strip()
        if not raw:
            return options[default_index]
        if raw.isdigit() and 1 <= int(raw) <= len(options):
            return options[int(raw) - 1]
        print(f"  Enter a number from 1 to {len(options)}.")


def interactive_run(args):
    exports_dir = args.dir
    topologies = discover_topologies(exports_dir)
    if not topologies:
        print(f"No captured telem CSVs found anywhere under {exports_dir}.", file=sys.stderr)
        return 2
    topology = prompt_choice("Which topology do you want to verify?", topologies)

    has_flat, locations = discover_locations(exports_dir, topology)
    loc_options = list(locations)
    flat_label = "(no location - flat capture, pre-dates per-site logging)"
    if has_flat:
        loc_options.append(flat_label)
    if not loc_options:
        print(f"No captures found for topology '{topology}'.", file=sys.stderr)
        return 2
    loc_choice = prompt_choice("Which location?", loc_options)
    location = None if loc_choice == flat_label else loc_choice

    groups = discover_groups(exports_dir, topology, location)
    if not groups:
        print(f"No telem CSVs found for topology={topology} "
              f"location={location or '(flat)'}.", file=sys.stderr)
        return 2

    print(f"\nFound {len(groups)} run(s) for topology={topology} "
          f"location={location or '(flat)'}:")
    for attack, scenario, repeat in sorted(groups):
        print(f"  - attack={attack:<10} scenario={scenario:<11} repeat=r{repeat}  "
              f"({len(groups[(attack, scenario, repeat)])} file(s))")

    overall_rc = 0
    for attack, scenario, repeat in sorted(groups):
        paths = sorted(groups[(attack, scenario, repeat)])
        print("\n" + "=" * 70)
        print(f"  attack={attack}  topology={topology}  "
              f"location={location or '(flat)'}  scenario={scenario}  repeat=r{repeat}")
        print("=" * 70)
        rc = analyze_and_print(paths, topology, args.converge_limit, args.stabilise_s)
        overall_rc = max(overall_rc, rc)

    print("\n" + "=" * 70)
    print(f"  {len(groups)} run(s) checked for topology={topology} "
          f"location={location or '(flat)'}.")
    print("=" * 70)
    return overall_rc


# ── Main ────────────────────────────────────────────────────────────────────
def analyze_and_print(paths, expect, converge_limit, stabilise_s, structure=False):
    """Load, reconstruct, and report on exactly one run. Returns 0/1/2."""
    print(f"Loaded {len(paths)} telemetry file(s):")
    for p in paths:
        print(f"  - {os.path.basename(p)}")
    print()

    nodes = load_files(paths, stabilise_s=stabilise_s)
    if not nodes:
        print("No node rows parsed.", file=sys.stderr)
        return 2

    graph, union_edges, unresolved = build_graph(nodes)

    # Printed FIRST when asked: it is the thing a reader wants to see, and
    # it stands on its own without the milestone verdict underneath it.
    if structure:
        print_structure_banner(graph, nodes, expect)


    # ── Structure ───────────────────────────────────────────────────────────
    print("=== Reconstructed structure ===")
    if graph.root is not None and not graph.cycle:
        print(f"{graph.reachable} node(s) attached, {graph.max_layer} layer(s)")
        print_tree(graph, nodes)
    elif graph.cycle:
        print("(!) Parent links form a cycle - no valid structure to draw.")
    else:
        print("(!) No root node identified (no node without a parent).")
    if graph.detached and not graph.cycle:
        tops = [nid for nid in graph.detached if graph.parent[nid] is None]
        print(f"\n(!) {len(graph.detached)} node(s) not attached to the root, in "
              f"{len(tops)} fragment(s):")
        for top in sorted(tops):
            print_tree(graph, nodes, start=top)
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
        ok = secs is not None and secs <= converge_limit
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
              f"first {stabilise_s:.0f}s of a node's own log — mesh "
              f"formation, not re-routing. Excluded from the baseline verdict "
              f"below; counted in the totals above. --stabilise-s 0 to include "
              f"them.)")
    print()

    # ── Expected topology ───────────────────────────────────────────────────
    # STAR/LINEAR are enforced by the firmware -> a violation FAILs the run.
    # TREE/PARTIAL come from placement -> a mismatch only WARNs. See
    # topology_graph.py for the structural rules.
    structure_ok = True
    if expect:
        print("=== Expected-topology check ===")
        status, reason = topology_graph.validate(expect, graph, union_edges)
        print(f"  {status} {expect}: {reason}")
        structure_ok = status != topology_graph.FAIL
        print()

    # ── Verdict ─────────────────────────────────────────────────────────────
    print("=== Milestone-3 verdict ===")
    print(f"  Converged within {converge_limit:.0f}s : "
          f"{'YES' if all_converged else 'NO — see nodes marked ?'}")
    print(f"  Baseline re-routing free            : "
          f"{'YES' if baseline_stable else 'NO — parent/layer changed during baseline'}")
    if expect:
        print(f"  Structure matches {expect:<17} : "
              f"{'YES' if structure_ok else 'NO — see the topology check above'}")
    return 0 if (all_converged and baseline_stable and structure_ok) else 1


def main():
    ap = argparse.ArgumentParser(description="Verify mesh topology from telem CSVs.")
    # Resolve the default RELATIVE TO THIS SCRIPT, not the shell's CWD. A bare
    # "exports" silently scans (and lets other tools create) a stray .\exports\
    # wherever you happen to be standing — the repo root, most often. Real
    # captures always live in tools/exports/. An explicit --dir still wins.
    ap.add_argument("--dir", default=os.path.join(_THIS_DIR, "exports"),
                    help="Folder of exported CSVs "
                         "(default: the exports/ folder next to this script).")
    ap.add_argument("--topology", choices=TOPOLOGIES, default="star")
    ap.add_argument("--attack", default="none")
    ap.add_argument("--repeat", default="1")
    ap.add_argument("--location", default=None,
                    help="Location subfolder (home/G402/DLSU_Library/Goks). "
                         "Default: search every location under --dir/--attack/--topology.")
    ap.add_argument("--scenario", default=None,
                    help="Scenario subfolder (none/burst/highload/mobility/"
                         "powercycle), one level under --location. Needs "
                         "--location to be given too. Default: search every "
                         "scenario under --location (the recursive walk finds "
                         "them regardless — this only narrows to one).")
    ap.add_argument("--files", nargs="*", help="Explicit telem CSVs (overrides --dir filters).")
    ap.add_argument("--structure", action="store_true",
                    help="Print the MESH TOPOLOGY / parent-child structure banner "
                         "rebuilt from the captured CSVs (the same view the firmware "
                         "prints over serial during a live run, but for any run, "
                         "including archived ones). UPLINK = that node's parent.")
    ap.add_argument("--expect", choices=TOPOLOGIES,
                    help="Check the structure against this topology: OK/WARN/FAIL "
                         "(star/linear violations FAIL the run).")
    ap.add_argument("--converge-limit", type=float, default=60.0,
                    help="Convergence deadline in seconds (Milestone-3 criterion).")
    ap.add_argument("--stabilise-s", type=float, default=STABILISE_S,
                    help="Mesh-formation window excluded from the baseline "
                         "re-routing verdict (default: PHASE_STABILISE_S = "
                         f"{STABILISE_S:.0f}s). Use 0 to count every change.")
    args = ap.parse_args()

    # No filter flags at all -> interactive: just ask topology + location,
    # auto-discover every attack/repeat captured for that combo, and report
    # on all of them. Any explicit flag (including --files) opts back into the
    # exact original deterministic/scriptable behavior below.
    interactive = (
        not args.files
        and args.topology == ap.get_default("topology")
        and args.attack == ap.get_default("attack")
        and args.repeat == ap.get_default("repeat")
        and args.location == ap.get_default("location")
    )
    if interactive:
        return interactive_run(args)

    paths = resolve_files(args, dir_is_default=(args.dir == ap.get_default("dir")))
    if not paths:
        print("No matching telem CSVs found. Check --dir/--topology/--attack/--repeat/--location "
              "or pass --files.", file=sys.stderr)
        found = sorted({
            os.path.relpath(os.path.join(dp, f), args.dir)
            for dp, _dn, fnames in os.walk(args.dir)
            for f in fnames
            if f.endswith("_telem.csv") and "trimmed" not in os.path.relpath(dp, args.dir).split(os.sep)
        })
        if found:
            print(f"\ntelem CSVs that DO exist under {args.dir}:", file=sys.stderr)
            for p in found[:20]:
                print(f"  {p}", file=sys.stderr)
            if len(found) > 20:
                print(f"  ... and {len(found) - 20} more", file=sys.stderr)
        else:
            print(f"\n(no *_telem.csv files exist anywhere under {args.dir} at all)", file=sys.stderr)
        return 2

    return analyze_and_print(paths, args.expect, args.converge_limit,
                             args.stabilise_s, structure=args.structure)


if __name__ == "__main__":
    raise SystemExit(main())

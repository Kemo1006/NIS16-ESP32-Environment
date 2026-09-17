"""
topology_graph.py - derive a mesh's layers from its parent links and check the
result against the built topology's STRUCTURE.

Nothing here assumes a node count, a layer count or a node ID. Layers come
from a breadth-first walk out of whichever node the links show to be the root
(root = layer 1, the ESP-WIFI-MESH convention). Each topology is judged only by
its defining shape:

  star     every node is a direct child of the center - max layer 2 for any N
  linear   every node has at most one child - a chain of any length
  tree     one root, no cycles - any depth
  partial  a tree at any instant, but nodes are seen under more than one parent
           over time, without every pair being linked (that would be full mesh)

Verdicts follow how each shape is produced: STAR and LINEAR are enforced by the
firmware (max_layer 2 / chain + 1 child), so a violation is FAIL. TREE and
PARTIAL shapes come from physical placement, so a mismatch there is WARN. A
cycle in the parent links is FAIL for every topology - it isn't a valid mesh.

components/mesh_common/src/topology_graph.c applies the same rules live on the
root; keep the two in step. Standard library only.
"""

from __future__ import annotations

import random
from collections import deque

TOPOLOGIES = ("star", "tree", "linear", "partial")
OK, WARN, FAIL = "OK", "WARN", "FAIL"
ROOT_LAYER = 1


class Graph:
    """Parent links resolved into a rooted structure.

    parent[node]   -> parent node, or None
    children[node] -> list of child nodes (input order preserved)
    layer[node]    -> 1 for the root; nodes not reachable from it are absent
    """

    def __init__(self, parent_links):
        self.nodes = list(parent_links)
        known = set(self.nodes)
        self.parent = {}
        self.unresolved = []
        self.cycle = False
        for node, par in parent_links.items():
            if par is not None and par not in known:
                self.unresolved.append(node)
                par = None
            if par == node:
                self.cycle = True
                par = None
            self.parent[node] = par

        self.children = {n: [] for n in self.nodes}
        for node in self.nodes:
            par = self.parent[node]
            if par is not None:
                self.children[par].append(node)

        # A parent chain that never reaches a parentless node is a cycle.
        n = len(self.nodes)
        for node in self.nodes:
            cur, steps = node, 0
            while cur is not None and steps <= n:
                cur = self.parent[cur]
                steps += 1
            if cur is not None:
                self.cycle = True
                break

        # Root = the parentless node that carries the most of the mesh. A node
        # that hasn't joined yet is parentless too but reaches only itself. A
        # node whose parent exists but isn't in the data is NOT a root - it
        # only competes if no genuinely parentless node exists.
        self.root = None
        missing = set(self.unresolved)
        for allow_missing in (False, True):
            best = 0
            for node in self.nodes:
                if self.parent[node] is None and (allow_missing or node not in missing):
                    reach = len(self._bfs(node))
                    if reach > best:
                        self.root, best = node, reach
            if self.root is not None:
                break
        self.layer = self._bfs(self.root) if self.root is not None else {}
        self.max_layer = max(self.layer.values(), default=0)

    def _bfs(self, start):
        layer = {start: ROOT_LAYER}
        queue = deque([start])
        while queue:
            u = queue.popleft()
            for c in self.children[u]:
                if c not in layer:
                    layer[c] = layer[u] + 1
                    queue.append(c)
        return layer

    @property
    def reachable(self):
        return len(self.layer)

    @property
    def detached(self):
        return [n for n in self.nodes if n not in self.layer]

    def leaf(self):
        """Deepest reachable node (the far endpoint of a chain)."""
        return max(self.layer, key=lambda n: self.layer[n]) if self.layer else None


def build_graph(parent_links):
    return Graph(parent_links)


def union_layers(graph, union_edges):
    """Min-hop layers over every link ever observed (undirected), from the
    graph's root. union_edges: iterable of (child, parent) pairs."""
    adj = {n: set() for n in graph.nodes}
    for a, b in union_edges:
        if a in adj and b in adj and a != b:
            adj[a].add(b)
            adj[b].add(a)
    if graph.root is None:
        return {}, adj
    layer = {graph.root: ROOT_LAYER}
    queue = deque([graph.root])
    while queue:
        u = queue.popleft()
        for v in adj[u]:
            if v not in layer:
                layer[v] = layer[u] + 1
                queue.append(v)
    return layer, adj


def validate(topology, graph, union_edges=None):
    """(status, reason) for the graph against the topology's structural rules."""
    if topology not in TOPOLOGIES:
        return FAIL, f"unknown topology {topology!r}"
    if not graph.nodes:
        return WARN, "no nodes"
    if graph.cycle:
        return FAIL, "parent links form a cycle - not a valid mesh"
    if graph.root is None:
        return FAIL, "no root found"

    status = OK
    if topology == "star":
        deep = [n for n, ly in graph.layer.items() if ly > 2]
        if deep:
            n = deep[0]
            return FAIL, (f"{n} is at layer {graph.layer[n]} - a star allows only the "
                          f"center (1) and its direct nodes (2)")
        reason = f"center {graph.root} + {graph.reachable - 1} direct node(s)"

    elif topology == "linear":
        branch = [n for n in graph.layer if len(graph.children[n]) > 1]
        if branch:
            n = branch[0]
            return FAIL, (f"{n} has {len(graph.children[n])} children - a linear "
                          f"chain allows 1 (branch)")
        reason = f"chain of {graph.reachable} node(s), {graph.root} .. {graph.leaf()}"

    elif topology == "tree":
        if graph.reachable >= 3 and graph.max_layer <= 2:
            status = WARN
            reason = (f"all {graph.reachable} nodes hang directly off the root - "
                      f"flat like a star (depth 2)")
        else:
            reason = f"{graph.reachable} node(s), depth {graph.max_layer}"

    else:  # partial
        edges = [(n, graph.parent[n]) for n in graph.nodes if graph.parent[n] is not None]
        edges += list(union_edges or [])
        hops, adj = union_layers(graph, edges)
        parents_seen = {}
        for child, par in edges:
            if child in adj and par in adj and child != par:
                parents_seen.setdefault(child, set()).add(par)
        multi = sum(1 for s in parents_seen.values() if len(s) >= 2)
        v = len(hops)
        e = sum(len(adj[n]) for n in hops) // 2
        if v >= 3 and e == v * (v - 1) // 2:
            status = WARN
            reason = f"every pair of the {v} nodes is linked - that is a full mesh, not partial"
        elif multi == 0:
            status = WARN
            reason = (f"{v} nodes, each seen under only one parent so far - still a "
                      f"plain tree (depth {graph.max_layer})")
        else:
            reason = (f"{e} links over {v} nodes, {multi} node(s) seen under 2+ parents, "
                      f"tree depth {graph.max_layer}, min-hop depth "
                      f"{max(hops.values(), default=0)}")

    detached = graph.detached
    if detached:
        reason += f"; {len(detached)} node(s) not attached to the root"
        if status == OK:
            status = WARN
    return status, reason


# ── synthetic graphs (tests, fake data) ─────────────────────────────────────

def synthetic_roster(topology, n, depth=None, seed=None):
    """Fake-data rows for a valid structure: [(node_id, role, layer, parent_mac)].

    Node 0 is NODE_ROOT01, the rest NODE_VICTIM01.. (the existing fixture
    names). Each node gets a synthetic STA MAC; parent_mac is the parent's
    SoftAP BSSID (STA + 1) the way the firmware logs it, all zeros on the root.
    Layers are derived from the generated links, root = 1.
    """
    links, _ = generate(topology, n, depth=depth, seed=seed)
    graph = build_graph(links)

    def sta(i):
        return 0x020000000000 + i * 4

    def fmt(v):
        return ":".join(f"{(v >> s) & 0xFF:02X}" for s in range(40, -1, -8))

    rows = []
    for i in range(n):
        node_id = "NODE_ROOT01" if i == 0 else f"NODE_VICTIM{i:02d}"
        role = "root" if i == 0 else "victim"
        par = links[i]
        parent_mac = "00:00:00:00:00:00" if par is None else fmt(sta(par) + 1)
        rows.append((node_id, role, graph.layer[i], parent_mac))
    return rows



def generate(topology, n, depth=None, seed=None, alt_parent_fraction=0.34,
             partial_fanout=2):
    """Valid synthetic structure of any size.

    Returns (parent_links, history): parent_links maps node index -> parent
    index (None for the root, node 0); history is a list of extra
    (child, parent) links observed over time - only non-empty for partial.
    """
    if topology not in TOPOLOGIES:
        raise ValueError(f"unknown topology {topology!r}")
    if n < 1:
        raise ValueError("need at least one node")
    rng = random.Random(seed)
    links = {0: None}
    history = []

    if topology == "linear":
        for i in range(1, n):
            links[i] = i - 1

    elif topology == "star":
        for i in range(1, n):
            links[i] = 0

    elif topology == "tree":
        depth = depth if depth is not None else max(3, min(n, 4))
        if depth > n:
            raise ValueError(f"a tree of depth {depth} needs at least {depth} nodes")
        for i in range(1, depth):                 # spine gives the exact depth
            links[i] = i - 1
        layer = {i: i + 1 for i in range(depth)}
        for i in range(depth, n):                 # the rest branch off, never deeper
            par = rng.choice([p for p in layer if layer[p] < depth])
            links[i] = par
            layer[i] = layer[par] + 1

    else:  # partial: bounded fan-out tree + alternate parents seen over time
        layer = {0: 1}
        kids = {0: 0}
        for i in range(1, n):
            par = rng.choice([p for p in layer if kids[p] < partial_fanout])
            links[i] = par
            kids[par] += 1
            kids[i] = 0
            layer[i] = layer[par] + 1
        def alternates(i):
            return [p for p in layer if p != links[i] and p != i and layer[p] < layer[i]]

        for i in range(1, n):
            if rng.random() < alt_parent_fraction and alternates(i):
                history.append((i, rng.choice(alternates(i))))
        if not history:   # a partial mesh needs at least one alternate parent
            for i in range(1, n):
                if alternates(i):
                    history.append((i, rng.choice(alternates(i))))
                    break
    return links, history
